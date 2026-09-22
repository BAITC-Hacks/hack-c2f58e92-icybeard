"""4.5: rebuild and publish only the gold tables affected by a newly loaded batch, right after intake —
so a file uploaded through the console (or `intake add`/`intake reprocess`) is visible on the dashboards
without a separate manual `make pipeline` run. Best-effort: publish needs Postgres/ClickHouse reachable,
which is not guaranteed right after a lone intake call (e.g. local dev without `docker compose up`), so a
failure here is reported as a warning, never raised — the load itself already succeeded and is not undone.
"""
from __future__ import annotations

import os

from ..lakehouse.gold import build_gold
from ..lakehouse.publish import publish
from .pipeline import Lakehouse

# dataset (silver, contract's `dataset`) -> gold tables that read it (see lakehouse/gold.py BUILDERS/silver_sql calls)
DATASET_GOLD_TABLES: dict[str, tuple[str, ...]] = {
    "bg_referrals": ("queue_daily", "throughput_4w", "features_wait"),
    "bg_er_refusals": ("er_visits_daily",),
    "ersb_cases": ("admissions_monthly",),
    "vac_facts": ("vac_monthly",),
    "onco_ext": ("onco_monthly",),
    "rx_issued": ("rx_weekly", "rx_nosology_monthly", "rx_mnn"),
    "rx_fulfilled": ("rx_weekly", "rx_nosology_monthly", "rx_mnn"),
    "drug_specs": ("drug_programs",),
}


def rebuild_after_batch(lake: Lakehouse, dataset: str) -> dict[str, object]:
    """Rebuild the gold tables that read `dataset` and republish them; returns what happened, never raises."""
    tables = DATASET_GOLD_TABLES.get(dataset)
    if not tables:
        return {"rebuilt": [], "published": False, "warning": None}
    result: dict[str, object] = {"rebuilt": [], "published": False, "warning": None}
    try:
        counts = build_gold(lake, only=list(tables))
        result["rebuilt"] = [{"table": name, "rows": n} for name, n in counts.items()]
    except Exception as exc:  # noqa: BLE001 - партия уже загружена, витрины можно пересобрать и вручную (make gold)
        result["warning"] = f"gold не пересобран: {type(exc).__name__}: {exc}"
        return result
    dsn = os.environ.get("POSTGRES_DSN")
    if not dsn:
        # Без явного адреса витрины не публикуются: DSN по умолчанию — localhost dev-стека, и одиночный intake
        # (или тест на временном lakehouse) молча перезаписал бы там настоящие gold-таблицы.
        result["warning"] = "витрины пересобраны, но не опубликованы: POSTGRES_DSN не задан"
        return result
    try:
        publish(lake, pg_dsn=dsn)
        result["published"] = True
    except Exception as exc:  # noqa: BLE001 - Postgres/ClickHouse не обязаны быть подняты рядом с одиночным intake
        result["warning"] = f"витрины пересобраны, но не опубликованы (Postgres/ClickHouse недоступны?): {type(exc).__name__}: {exc}"
    return result
