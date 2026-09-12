"""python -m darumen.lakehouse build|publish [--lakehouse lakehouse] [--only ...]"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from ..intake.pipeline import Lakehouse
from .gold import BUILDERS, build_gold


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.lakehouse")
    sub = parser.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build", help="собрать витрины gold")
    build.add_argument("--lakehouse", default="lakehouse")
    build.add_argument("--only", default="", help="через запятую: " + ", ".join(BUILDERS))
    publish = sub.add_parser("publish", help="опубликовать gold и refdata в Postgres и ClickHouse")
    publish.add_argument("--lakehouse", default="lakehouse")
    publish.add_argument("--only", choices=["postgres", "clickhouse"], default=None)
    args = parser.parse_args(argv)
    started = time.time()
    lake = Lakehouse(Path(args.lakehouse))
    if args.command == "build":
        only = [x for x in args.only.split(",") if x] or None
        for name, rows in build_gold(lake, only=only).items():
            print(f"{name:22s} {rows:>12,} rows" if rows else f"{name:22s} {'skipped (no silver)':>12}")
    else:
        from .publish import publish as publish_all

        for store, tables in publish_all(lake, only=args.only).items():
            for name, rows in tables.items():
                print(f"{store:10s} {name:26s} {rows:>12,} rows")
    print(f"done in {time.time() - started:.1f}s")
    return 0
