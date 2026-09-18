"""FastAPI application of the data intake console. Mounted behind the .NET API by YARP under
/api/v1/intake/{files,drafts,quarantine} (see docs/finish-plan.md 4.1/4.2); the existing
GET /api/v1/intake/batches stays a normal .NET endpoint reading Postgres and is untouched.

    python -m darumen.intake.app [--host 0.0.0.0] [--port 8020]

A steward uploads one file through POST /intake/files: known schemas are loaded immediately (bronze →
silver → gold, 4.5) and published to Kafka exactly like `python -m darumen.intake add` does; unknown
schemas get a contract draft (4.6: LLM-enriched when a provider key is configured, otherwise the plain
heuristic from `pipeline.draft_contract`). GET /intake/drafts and POST /intake/drafts/{dataset}/approve
(4.4) let the steward review a draft and turn it into a real contract, which reprocesses the file that
produced it. GET /intake/quarantine (4.4/4.3) lists the rows a batch could not load, with their reasons.
"""
from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Annotated

import duckdb
import yaml
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from pydantic import BaseModel

from .contracts import load_contracts, match_signature
from .events import EventPublisher
from .fingerprint import fingerprint
from .gold_refresh import rebuild_after_batch
from .llm_draft import LlmContractDrafter, default_contract_drafter
from .pipeline import STATUS_LOADED, BatchResult, Lakehouse, draft_contract, run_batch

MAX_UPLOAD_BYTES = 500 * 1024 * 1024
DRAFT_SOURCE_DIR = "incoming"  # lake.root/incoming: keeps the uploaded file so an approved draft can be reprocessed


class ApproveIn(BaseModel):
    """Точечные правки стюарда перед утверждением: сменить dataset/title или добавить semantic колонке
    без необходимости редактировать YAML руками. Пусто по умолчанию — черновик утверждается как есть."""
    dataset: str | None = None
    title: str | None = None
    column_semantics: dict[str, str] = {}


def _sample_values(path: Path, header: list[str], delimiter: str) -> dict[str, list[str]]:
    con = duckdb.connect()
    try:
        rel = con.sql(
            f"SELECT * FROM read_csv('{path}', header=true, delim='{delimiter}', quote='\"', escape='\"', sample_size=200) LIMIT 20"
        )
        df = rel.df()
        return {col: [str(v) for v in df[col].dropna().unique()[:5]] for col in df.columns}
    except Exception:  # noqa: BLE001 - выборка для LLM необязательна, эвристический черновик уже готов
        return {}
    finally:
        con.close()


def _load_draft(lake: Lakehouse, dataset: str) -> tuple[Path, dict]:
    path = lake.drafts() / f"{dataset}.yaml"
    if not path.exists():
        raise HTTPException(404, f"draft '{dataset}' not found")
    return path, yaml.safe_load(path.read_text(encoding="utf-8"))


def create_app(lake: Lakehouse, contracts_dir: Path, drafter: LlmContractDrafter | None = None, publisher: EventPublisher | None = None) -> FastAPI:
    app = FastAPI(title="Darumen Intake", version="0.1.0")
    drafter = drafter or default_contract_drafter()
    (lake.root / DRAFT_SOURCE_DIR).mkdir(parents=True, exist_ok=True)

    def _publish_and_refresh(result: BatchResult) -> dict:
        extra: dict = {}
        if result.status == STATUS_LOADED:
            extra["gold"] = rebuild_after_batch(lake, result.dataset)
            active_publisher = publisher if publisher is not None else EventPublisher.from_env()
            if active_publisher is not None:
                try:
                    event_id = active_publisher.batch_loaded(result.dataset, result.batch_id, result.rows_silver, result.rows_quarantine, result.partitions)
                    extra["eventId"] = event_id
                except Exception as exc:  # noqa: BLE001 - партия уже загружена, отсутствие события не отменяет её
                    extra["eventWarning"] = f"{type(exc).__name__}: {exc}"
        return extra

    def _process_upload(path: Path) -> dict:
        contracts = load_contracts(contracts_dir)
        fp = fingerprint(path)
        match = match_signature(fp.signature, contracts)
        if match is None:
            draft_path = draft_contract(path, fp, lake)
            draft = yaml.safe_load(draft_path.read_text(encoding="utf-8"))
            draft["source_file"] = str(path)
            enriched = drafter.enrich(draft, _sample_values(path, list(fp.header), fp.delimiter))
            draft_path.write_text(yaml.safe_dump(enriched, allow_unicode=True, sort_keys=False), encoding="utf-8")
            return {"status": "unknown", "dataset": enriched["dataset"], "draft": enriched}
        result = run_batch([path], match.contract, lake)
        return {"status": result.status, "matchKind": match.kind, "matchScore": match.score, "batch": _batch_dict(result, _publish_and_refresh(result))}

    @app.get("/intake/health")
    def health():
        return {"status": "ok", "drafter": drafter.name, "llmAvailable": drafter.available()}

    @app.post("/intake/files", status_code=201)
    def upload(file: Annotated[UploadFile, File()]):
        if not file.filename:
            raise HTTPException(422, "filename is required")
        target = lake.root / DRAFT_SOURCE_DIR / file.filename
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("wb") as out:
            shutil.copyfileobj(file.file, out, length=1024 * 1024)
        if target.stat().st_size > MAX_UPLOAD_BYTES:
            target.unlink()
            raise HTTPException(413, "file is larger than 500 MB")
        try:
            return _process_upload(target)
        except NotImplementedError as exc:
            raise HTTPException(422, str(exc)) from exc

    @app.get("/intake/drafts")
    def list_drafts():
        items = []
        for path in sorted(lake.drafts().glob("*.yaml")):
            draft = yaml.safe_load(path.read_text(encoding="utf-8"))
            items.append({"dataset": draft["dataset"], "title": draft.get("title", draft["dataset"]),
                         "columns": list(draft.get("columns", {}).keys()), "sourceFile": draft.get("source_file")})
        return {"items": items}

    @app.get("/intake/drafts/{dataset}")
    def get_draft(dataset: str):
        _, draft = _load_draft(lake, dataset)
        return draft

    @app.post("/intake/drafts/{dataset}/approve")
    def approve_draft(dataset: str, body: ApproveIn):
        draft_path, draft = _load_draft(lake, dataset)
        source_file = draft.pop("source_file", None)
        draft.pop("draft_model", None)
        draft["dataset"] = body.dataset or draft["dataset"]
        if body.title:
            draft["title"] = body.title
        for column, semantic in body.column_semantics.items():
            if column not in draft.get("columns", {}):
                raise HTTPException(422, f"unknown column '{column}'")
            draft["columns"][column]["semantic"] = semantic
        draft["status"] = "approved"
        contracts_dir.mkdir(parents=True, exist_ok=True)
        contract_path = contracts_dir / f"{draft['dataset']}.yaml"
        contract_path.write_text(yaml.safe_dump(draft, allow_unicode=True, sort_keys=False), encoding="utf-8")
        draft_path.unlink()
        response: dict = {"contract": str(contract_path), "reprocessed": None}
        if source_file and Path(source_file).exists():
            response["reprocessed"] = _process_upload(Path(source_file))
        return response

    @app.get("/intake/quarantine")
    def quarantine(dataset: str, batch_id: str | None = Query(default=None, alias="batchId"), limit: int = Query(default=200, le=2000)):
        qdir = lake.quarantine(dataset)
        if not qdir.exists():
            return {"items": [], "total": 0}
        pattern = f"{batch_id}*.parquet" if batch_id else "*.parquet"
        files = sorted(qdir.glob(pattern))
        if not files:
            return {"items": [], "total": 0}
        con = duckdb.connect()
        try:
            files_sql = "[" + ", ".join("'" + str(f).replace("'", "''") + "'" for f in files) + "]"
            total = int(con.execute(f"SELECT count(*) FROM read_parquet({files_sql}, union_by_name=true)").fetchone()[0])
            rows = con.execute(f"SELECT * FROM read_parquet({files_sql}, union_by_name=true) LIMIT {int(limit)}").df()
            return {"items": rows.to_dict("records"), "total": total}
        finally:
            con.close()

    @app.post("/intake/reprocess")
    def reprocess(body: dict):
        path = Path(body["path"]) if "path" in body else lake.root / DRAFT_SOURCE_DIR / body["fileName"]
        if not path.exists():
            raise HTTPException(404, f"file not found: {path}")
        try:
            return _process_upload(path)
        except NotImplementedError as exc:
            raise HTTPException(422, str(exc)) from exc

    return app


def _batch_dict(result: BatchResult, extra: dict) -> dict:
    from dataclasses import asdict

    payload = asdict(result)
    payload.update(extra)
    return payload


def build_default_app() -> FastAPI:
    lake = Lakehouse(Path(os.environ.get("DARUMEN_LAKEHOUSE", "lakehouse")))
    contracts_dir = Path(os.environ.get("DARUMEN_CONTRACTS_DIR", "contracts"))
    return create_app(lake, contracts_dir)


def main() -> int:
    """python -m darumen.intake.app [--host 0.0.0.0] [--port 8020]"""
    import argparse

    import uvicorn

    parser = argparse.ArgumentParser(prog="darumen.intake.app")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("DARUMEN_INTAKE_PORT", "8020")))
    args = parser.parse_args()
    uvicorn.run(build_default_app(), host=args.host, port=args.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
