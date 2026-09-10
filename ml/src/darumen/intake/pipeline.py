"""Intake pipeline: raw files → bronze (as received) → silver (typed, derived, normalised),
with contract rules, quarantine and a manifest per batch.

Layout under the lakehouse root:
    bronze/<dataset>/<source file>.parquet
    silver/<dataset>/<partition>=<value>/.../<batch_id>_<i>.parquet
    quarantine/<dataset>/<batch_id>.parquet, <batch_id>_parse.parquet
    manifests/<dataset>/<batch_id>.json
    drafts/<name>.yaml                       contract drafts for unknown schemas
"""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from pathlib import Path

import duckdb
import yaml

from .contracts import Contract, Match, Rule, load_contracts, match_signature
from .fingerprint import Fingerprint, fingerprint
from .normalize import register_udfs

STATUS_LOADED = "loaded"
STATUS_BLOCKED = "blocked"
STATUS_SKIPPED = "skipped"
UNKNOWN_PARTITION = "unknown"
_PARTITION_FN = re.compile(r"^(month|year|date)\((\w+)\)$")


@dataclass
class RuleResult:
    level: str
    scope: str
    reason: str
    check: str
    failing: int | None
    passed: bool


@dataclass
class BatchResult:
    batch_id: str
    dataset: str
    status: str
    contract_hash: str
    files: list[dict] = field(default_factory=list)
    rows_bronze: int = 0
    rows_parse_rejected: int = 0
    rows_silver: int = 0
    rows_quarantine: int = 0
    rules: list[RuleResult] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    partitions: list[str] = field(default_factory=list)
    started_at: str = ""
    finished_at: str = ""
    lakehouse: str = ""
    error: str | None = None


class Lakehouse:
    def __init__(self, root: Path):
        self.root = Path(root)

    def bronze(self, dataset: str) -> Path:
        return self.root / "bronze" / dataset

    def silver(self, dataset: str) -> Path:
        return self.root / "silver" / dataset

    def quarantine(self, dataset: str) -> Path:
        return self.root / "quarantine" / dataset

    def manifests(self, dataset: str) -> Path:
        return self.root / "manifests" / dataset

    def drafts(self) -> Path:
        return self.root / "drafts"

    def silver_sql(self, dataset: str) -> str:
        """Table expression over a silver dataset; partition values stay strings (no hive autocast)."""
        pattern = str(self.silver(dataset) / "**" / "*.parquet")
        return f"read_parquet({_sql_str(pattern)}, hive_partitioning=true, hive_types_autocast=false)"

    def all_manifests(self) -> list[dict]:
        return [json.loads(p.read_text(encoding="utf-8")) for p in sorted((self.root / "manifests").glob("*/*.json"))]


def _sql_str(value: str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def _q(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def _md5(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as fh:
        while chunk := fh.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat()


# ---------- silver SQL -------------------------------------------------------------------------

def cast_expr(col: str, spec: dict) -> str:
    q = _q(col)
    src = f"nullif(trim({q}), '')"
    for null_value in spec.get("null_values", []):
        src = f"nullif({src}, {_sql_str(null_value)})"
    kind = spec.get("type", "string")
    if kind == "timestamp":
        parts = [f"try_cast({src} AS TIMESTAMP)"]
        parts += [f"try_strptime({src}, {_sql_str(fmt)})" for fmt in spec.get("formats", [])]
        return f"coalesce({', '.join(parts)})"
    if kind == "date":
        return f"coalesce(try_cast({src} AS DATE), try_cast(try_cast({src} AS TIMESTAMP) AS DATE))"
    if kind == "int":
        return f"try_cast(replace({src}, ' ', '') AS BIGINT)"
    if kind == "decimal":
        return f"try_cast(replace(replace({src}, ' ', ''), ',', '.') AS DOUBLE)"
    if kind == "bool":
        return f"try_cast({src} AS BOOLEAN)"
    return src


def partition_columns(partition: tuple[str, ...]) -> tuple[list[str], list[str], list[str]]:
    """Partition column names, the names that are computed, and their SQL expressions."""
    names: list[str] = []
    computed: list[str] = []
    exprs: list[str] = []
    for item in partition:
        match = _PARTITION_FN.match(item)
        if not match:
            names.append(item)
            continue
        fn, col = match.groups()
        name = f"p_{fn}"
        fmt = {"month": "%Y-%m", "year": "%Y", "date": "%Y-%m-%d"}[fn]
        exprs.append(f"coalesce(strftime({_q(col)}, {_sql_str(fmt)}), {_sql_str(UNKNOWN_PARTITION)}) AS {_q(name)}")
        names.append(name)
        computed.append(name)
    return names, computed, exprs


def build_silver_sql(contract: Contract, source_sql: str) -> str:
    # dropped columns (direct identifiers) stay in bronze only; `as` renames a source column in silver
    kept = {col: spec for col, spec in contract.columns.items() if not spec.get("drop", False)}
    typed = [f"{cast_expr(col, spec)} AS {_q(spec.get('as', col))}" for col, spec in kept.items()]
    typed += [_q(col) for col in contract.signature if col not in contract.columns]
    typed += [_q("_source_file"), _q("_row_hash")]
    layer1 = f"SELECT {', '.join(typed)} FROM ({source_sql})"

    derived = ["*"]
    for col, spec in kept.items():
        alias = spec.get("as", col)
        for name, rule in (spec.get("derive") or {}).items():
            if "split" in rule:
                derived.append(f"split_part({_q(alias)}, {_sql_str(rule['split'])}, {int(rule['index']) + 1}) AS {_q(name)}")
        semantic = spec.get("semantic")
        if semantic == "region_name":
            derived.append(f"to_kato({_q(alias)}) AS {_q(spec.get('derive_as', alias + '_kato'))}")
        elif semantic == "mo_name":
            derived.append(f"mo_name_key({_q(alias)}) AS {_q(spec.get('derive_as', alias + '_key'))}")
        elif semantic == "icd10":
            derived.append(f"icd10_canon({_q(alias)}) AS {_q(spec.get('derive_as', alias + '_canon'))}")
    layer2 = f"SELECT {', '.join(derived)} FROM ({layer1})"

    dataset_level = ["*"] + [f"({expr}) AS {_q(name)}" for name, expr in contract.derive.items()]
    layer3 = f"SELECT {', '.join(dataset_level)} FROM ({layer2})"

    names, computed, exprs = partition_columns(contract.partition)
    plain = [n for n in names if n not in computed]
    select = ["* EXCLUDE (" + ", ".join(_q(n) for n in plain) + ")" if plain else "*"]
    select += [f"coalesce({_q(n)}, {_sql_str(UNKNOWN_PARTITION)}) AS {_q(n)}" for n in plain]
    select += exprs
    return f"SELECT {', '.join(select)} FROM ({layer3})"


# ---------- batch ----------------------------------------------------------------------------------

def _files_digest(files: list[dict]) -> str:
    return hashlib.sha1("".join(f["md5"] for f in files).encode()).hexdigest()[:8]


def _already_loaded(lake: Lakehouse, dataset: str, digest: str) -> str | None:
    for path in sorted(lake.manifests(dataset).glob("*.json")):
        manifest = json.loads(path.read_text(encoding="utf-8"))
        if manifest.get("status") == STATUS_LOADED and manifest.get("files_digest") == digest:
            return manifest["batch_id"]
    return None


def _read_csv_sql(path: Path, fp: Fingerprint, contract: Contract) -> str:
    fmt = contract.format
    if fp.encoding != "utf-8":
        raise NotImplementedError(f"{path.name}: encoding {fp.encoding} is not supported yet, convert to UTF-8")
    return (
        f"read_csv({_sql_str(str(path))}, header=true, all_varchar=true, "
        f"delim={_sql_str(fmt.get('delimiter', fp.delimiter))}, quote={_sql_str(fmt.get('quote', chr(34)))}, "
        f"escape={_sql_str(fmt.get('escape', chr(34)))}, store_rejects=true)"
    )


def run_batch(files: list[Path], contract: Contract, lake: Lakehouse, con: duckdb.DuckDBPyConnection | None = None) -> BatchResult:
    started = _now()
    files = [Path(f) for f in files]
    descriptors = [{"name": f.name, "path": str(f), "bytes": f.stat().st_size, "md5": _md5(f), "rows": 0} for f in files]
    digest = _files_digest(descriptors)
    previous = _already_loaded(lake, contract.dataset, digest)
    if previous:
        return BatchResult(previous, contract.dataset, STATUS_SKIPPED, contract.contract_hash, descriptors,
                           started_at=started, finished_at=_now(), lakehouse=str(lake.root))

    batch_id = f"{contract.dataset}-{datetime.now(UTC):%Y%m%dT%H%M%SZ}-{digest}"
    result = BatchResult(batch_id, contract.dataset, STATUS_LOADED, contract.contract_hash, descriptors,
                         started_at=started, lakehouse=str(lake.root))
    own_connection = con is None
    con = con or duckdb.connect()
    try:
        register_udfs(con)
        _bronze(con, files, contract, lake, result)
        _silver(con, contract, lake, result)
    except Exception as exc:  # noqa: BLE001 - any failure must land in the manifest, not crash the run
        result.status = STATUS_BLOCKED
        result.error = f"{type(exc).__name__}: {exc}"
    finally:
        if own_connection:
            con.close()
    result.finished_at = _now()
    _write_manifest(lake, result, digest)
    return result


def _bronze(con, files: list[Path], contract: Contract, lake: Lakehouse, result: BatchResult) -> None:
    bronze_dir = lake.bronze(contract.dataset)
    bronze_dir.mkdir(parents=True, exist_ok=True)
    for path, desc in zip(files, result.files, strict=True):
        fp = fingerprint(path)
        cols = ", ".join(_q(c) for c in fp.header)
        target = bronze_dir / f"{path.stem}.parquet"
        con.execute(
            f"COPY (SELECT *, {_sql_str(path.name)} AS \"_source_file\", now() AS \"_ingested_at\", "
            f"md5(concat_ws('|', {cols})) AS \"_row_hash\" FROM {_read_csv_sql(path, fp, contract)}) "
            f"TO {_sql_str(str(target))} (FORMAT PARQUET)"
        )
        desc["rows"] = int(con.execute(f"SELECT count(*) FROM read_parquet({_sql_str(str(target))})").fetchone()[0])
        desc["bronze"] = str(target)
    result.rows_bronze = sum(d["rows"] for d in result.files)
    try:
        rejected = int(con.execute("SELECT count(*) FROM reject_errors").fetchone()[0])
    except duckdb.Error:
        rejected = 0
    result.rows_parse_rejected = rejected
    if rejected:
        qdir = lake.quarantine(contract.dataset)
        qdir.mkdir(parents=True, exist_ok=True)
        con.execute(f"COPY (SELECT * FROM reject_errors) TO {_sql_str(str(qdir / (result.batch_id + '_parse.parquet')))} (FORMAT PARQUET)")
        result.warnings.append(f"{rejected} строк не разобраны CSV-парсером, см. quarantine/*_parse.parquet")


def _silver(con, contract: Contract, lake: Lakehouse, result: BatchResult) -> None:
    bronze_files = "[" + ", ".join(_sql_str(d["bronze"]) for d in result.files) + "]"
    con.execute(f"CREATE OR REPLACE TEMP VIEW silver_tmp AS {build_silver_sql(contract, f'SELECT * FROM read_parquet({bronze_files})')}")

    row_rules = [r for r in contract.rules if r.scope == "row"]
    row_rules += [Rule("quarantine", f"{_q(c)} IS NOT NULL", "row", f"missing:{c}") for c in contract.required_columns()]
    for rule in row_rules:
        failing = int(con.execute(f"SELECT count(*) FROM silver_tmp WHERE NOT coalesce(({rule.check}), true)").fetchone()[0])
        result.rules.append(RuleResult(rule.level, rule.scope, rule.reason, rule.check, failing, failing == 0))
    blocked = [r for r in result.rules if r.level == "block" and not r.passed]
    if blocked:
        result.status = STATUS_BLOCKED
        result.error = "blocked by rules: " + "; ".join(f"{r.reason} ({r.failing} rows)" for r in blocked)
        return

    quarantine_rules = [r for r in row_rules if r.level == "quarantine"]
    reason_expr = "NULL"
    if quarantine_rules:
        cases = " ".join(f"WHEN NOT coalesce(({r.check}), true) THEN {_sql_str(r.reason)}" for r in quarantine_rules)
        reason_expr = f"CASE {cases} ELSE NULL END"
    con.execute(f"CREATE OR REPLACE TEMP VIEW silver_marked AS SELECT *, {reason_expr} AS \"_quarantine_reason\" FROM silver_tmp")

    for rule in (r for r in contract.rules if r.scope == "dataset"):
        try:
            value = con.execute(f"SELECT ({rule.check}) FROM silver_tmp").fetchone()[0]
        except duckdb.Error as exc:
            value = None
            result.warnings.append(f"правило не вычислено: {rule.reason}: {exc}")
        result.rules.append(RuleResult(rule.level, rule.scope, rule.reason, rule.check, None, bool(value)))
        if not value:
            result.warnings.append(f"предупреждение: {rule.reason}")
    if contract.keys:
        key_expr = ", ".join(_q(k) for k in contract.keys)
        dupes = int(con.execute(
            f"SELECT count(*) - count(DISTINCT concat_ws('|', {key_expr})) FROM silver_marked WHERE \"_quarantine_reason\" IS NULL"
        ).fetchone()[0])
        if dupes:
            result.warnings.append(f"дубликаты по ключу ({', '.join(contract.keys)}): {dupes} строк")

    names, _, _ = partition_columns(contract.partition)
    silver_dir = lake.silver(contract.dataset)
    silver_dir.mkdir(parents=True, exist_ok=True)
    clean = 'SELECT * EXCLUDE ("_quarantine_reason") FROM silver_marked WHERE "_quarantine_reason" IS NULL'
    if names:
        cols = ", ".join(_q(n) for n in names)
        con.execute(
            f"COPY ({clean}) TO {_sql_str(str(silver_dir))} (FORMAT PARQUET, PARTITION_BY ({cols}), "
            f"OVERWRITE_OR_IGNORE true, FILENAME_PATTERN {_sql_str(result.batch_id + '_{i}')})"
        )
        parts = con.execute(f"SELECT DISTINCT {cols} FROM ({clean}) ORDER BY ALL").fetchall()
        result.partitions = ["/".join(f"{n}={v}" for n, v in zip(names, row, strict=True)) for row in parts]
    else:
        con.execute(f"COPY ({clean}) TO {_sql_str(str(silver_dir / (result.batch_id + '.parquet')))} (FORMAT PARQUET)")
    result.rows_silver = int(con.execute(f"SELECT count(*) FROM ({clean})").fetchone()[0])

    quarantined = int(con.execute('SELECT count(*) FROM silver_marked WHERE "_quarantine_reason" IS NOT NULL').fetchone()[0])
    result.rows_quarantine = quarantined
    if quarantined:
        qdir = lake.quarantine(contract.dataset)
        qdir.mkdir(parents=True, exist_ok=True)
        con.execute(
            f"COPY (SELECT * FROM silver_marked WHERE \"_quarantine_reason\" IS NOT NULL) "
            f"TO {_sql_str(str(qdir / (result.batch_id + '.parquet')))} (FORMAT PARQUET)"
        )


def _write_manifest(lake: Lakehouse, result: BatchResult, digest: str) -> Path:
    directory = lake.manifests(result.dataset)
    directory.mkdir(parents=True, exist_ok=True)
    payload = asdict(result)
    payload["files_digest"] = digest
    path = directory / f"{result.batch_id}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    return path


# ---------- unknown schema → draft contract -------------------------------------------------------

_DUCK_TO_CONTRACT = {
    "TIMESTAMP": "timestamp", "TIMESTAMP_NS": "timestamp", "DATE": "date", "BIGINT": "int", "INTEGER": "int",
    "SMALLINT": "int", "TINYINT": "int", "HUGEINT": "int", "DOUBLE": "decimal", "FLOAT": "decimal",
    "BOOLEAN": "bool",
}


def draft_contract(path: Path, fp: Fingerprint, lake: Lakehouse, con: duckdb.DuckDBPyConnection | None = None) -> Path:
    """Auto-profile an unknown CSV and write a contract draft for the data steward."""
    own = con is None
    con = con or duckdb.connect()
    try:
        rel = con.sql(
            f"SELECT * FROM read_csv({_sql_str(str(path))}, header=true, delim={_sql_str(fp.delimiter)}, "
            f"quote='\"', escape='\"', sample_size=20000)"
        )
        columns = {}
        for name, dtype in zip(rel.columns, rel.dtypes, strict=True):
            kind = str(dtype).upper()
            ctype = _DUCK_TO_CONTRACT.get(kind, "decimal" if kind.startswith("DECIMAL") else "string")
            spec: dict = {"type": ctype, "nullable": True}
            lowered = name.lower()
            if ctype == "string" and ("icd" in lowered or "mkb" in lowered):
                spec["semantic"] = "icd10"
            elif ctype == "string" and "region" in lowered:
                spec["semantic"] = "region_name"
            elif ctype == "string" and ("organization" in lowered or lowered.endswith("_mo") or lowered.startswith("mo_")):
                spec["semantic"] = "mo_name"
            columns[name] = spec
    finally:
        if own:
            con.close()
    slug = re.sub(r"[^\w]+", "_", path.stem.split("_part_")[0]).strip("_").lower()[:60] or "dataset"
    draft = {
        "dataset": slug,
        "title": path.stem.split("_part_")[0],
        "status": "draft",
        "source": {"file": path.name},
        "format": {"type": "csv", "encoding": "utf-8-sig" if fp.has_bom else fp.encoding, "delimiter": fp.delimiter,
                   "quote": '"', "escape": '"'},
        "keys": [],
        "signature": list(fp.header),
        "columns": columns,
        "privacy": {"class": "unknown", "public_aggregates_min_count": 5},
        "rules": [],
        "partition": [],
    }
    lake.drafts().mkdir(parents=True, exist_ok=True)
    out = lake.drafts() / f"{slug}.yaml"
    out.write_text(yaml.safe_dump(draft, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return out


# ---------- discovery ---------------------------------------------------------------------------------

@dataclass
class Plan:
    files: list[Path]
    match: Match | None
    fingerprint: Fingerprint


def plan_batches(target: Path, contracts_dir: Path) -> list[Plan]:
    """Group incoming files into batches: a file, a folder of parts, or a folder of dataset folders."""
    target = Path(target)
    contracts = load_contracts(contracts_dir)
    groups: list[list[Path]] = []
    if target.is_file():
        groups.append([target])
    else:
        csvs = sorted(p for p in target.glob("*.csv") if p.is_file())
        if csvs:
            groups.append(csvs)
        for sub in sorted(p for p in target.iterdir() if p.is_dir()):
            sub_csvs = sorted(p for p in sub.glob("*.csv") if p.is_file())
            if sub_csvs:
                groups.append(sub_csvs)
    plans: list[Plan] = []
    for group in groups:
        by_signature: dict[tuple[str, ...], list[Path]] = {}
        fps: dict[tuple[str, ...], Fingerprint] = {}
        for path in group:
            fp = fingerprint(path)
            by_signature.setdefault(fp.signature, []).append(path)
            fps.setdefault(fp.signature, fp)
        for signature, files in by_signature.items():
            plans.append(Plan(files, match_signature(signature, contracts), fps[signature]))
    return plans
