"""dagster dev -m darumen.orchestration.definitions

Assets mirror the make targets (data → refdata → gold → models → publish) so the lineage is visible in Dagster
while the CLI stays the source of truth. Paths come from DARUMEN_DATASETS and DARUMEN_LAKEHOUSE.
"""

import os
from pathlib import Path

import dagster as dg
from dagster import AssetExecutionContext

from ..intake.contracts import load_contracts
from ..intake.pipeline import Lakehouse, plan_batches, run_batch
from ..lakehouse.gold import BUILDERS, build_gold
from ..refdata.build import build_refdata

CONTRACTS_DIR = Path(__file__).resolve().parents[4] / "contracts"


def _lake() -> Lakehouse:
    return Lakehouse(Path(os.environ.get("DARUMEN_LAKEHOUSE", "lakehouse")))


@dg.asset(group_name="intake", description="Слепая загрузка папки наборов через контракты в bronze, silver и карантин")
def silver(context: AssetExecutionContext) -> dg.MaterializeResult:
    lake = _lake()
    datasets = Path(os.environ.get("DARUMEN_DATASETS", "DataSets"))
    contracts = {c.dataset: c for c in load_contracts(CONTRACTS_DIR)}
    loaded: dict[str, int] = {}
    for plan in plan_batches(datasets, CONTRACTS_DIR):
        if plan.match is None or plan.match.kind != "exact":
            context.log.warning("skipping %s: no exact contract", plan.files[0].parent.name)
            continue
        result = run_batch(plan.files, contracts[plan.match.contract.dataset], lake)
        loaded[result.dataset] = result.rows_silver
        context.log.info("%s %s silver=%s quarantine=%s", result.status, result.dataset, result.rows_silver, result.rows_quarantine)
    return dg.MaterializeResult(metadata={"datasets": len(loaded), "rows": sum(loaded.values())})


@dg.asset(group_name="refdata", deps=[silver], description="Регионы, профили коек, реестр организаций из silver")
def refdata(context: AssetExecutionContext) -> dg.MaterializeResult:
    report = build_refdata(_lake())
    context.log.info("refdata: %s", report)
    return dg.MaterializeResult(metadata={k: v for k, v in report.items() if isinstance(v, (int, float, str))})


def _gold_asset(name: str):
    @dg.asset(name=name, group_name="gold", deps=[refdata], description=f"Витрина gold.{name} (docs/gold-schemas.md)")
    def _asset() -> dg.MaterializeResult:
        rows = build_gold(_lake(), only=[name])[name]
        return dg.MaterializeResult(metadata={"rows": rows})

    return _asset


gold_assets = [_gold_asset(name) for name in BUILDERS]


@dg.asset(group_name="models", deps=[dg.AssetKey(name) for name in BUILDERS], description="Обучение моделей и карточки: darumen.models.train")
def models() -> dg.MaterializeResult:
    from ..models.train import main as train_main

    code = train_main(["--lakehouse", str(_lake().root)])
    return dg.MaterializeResult(metadata={"exit_code": code})


@dg.asset(group_name="serving", deps=[models], description="Публикация gold и refdata в Postgres и ClickHouse")
def published() -> dg.MaterializeResult:
    from ..lakehouse.publish import publish

    counts = publish(_lake())
    return dg.MaterializeResult(metadata={store: sum(tables.values()) for store, tables in counts.items()})


defs = dg.Definitions(assets=[silver, refdata, *gold_assets, models, published])
