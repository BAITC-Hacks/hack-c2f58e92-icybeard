"""Command line for blind intake.

    python -m darumen.intake add <file|folder> [--contracts contracts] [--lakehouse lakehouse]
    python -m darumen.intake inspect <file>
    python -m darumen.intake status [--lakehouse lakehouse]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .contracts import load_contracts, match_signature
from .events import TOPIC_BATCH_LOADED, EventPublisher
from .fingerprint import fingerprint
from .pipeline import STATUS_BLOCKED, STATUS_LOADED, Lakehouse, draft_contract, plan_batches, run_batch


def cmd_add(args: argparse.Namespace) -> int:
    lake = Lakehouse(Path(args.lakehouse))
    publisher = None if args.no_events else EventPublisher.from_env()
    exit_code = 0
    for plan in plan_batches(Path(args.path), Path(args.contracts)):
        first = plan.files[0]
        if plan.match is None:
            draft = draft_contract(first, plan.fingerprint, lake)
            print(f"UNKNOWN   {first.parent.name}/{first.name}: схема не найдена, черновик контракта: {draft}")
            continue
        contract = plan.match.contract
        label = f"{contract.dataset} ({plan.match.kind}, {plan.match.score:.2f})"
        if plan.match.kind != "exact" and not args.allow_fuzzy:
            print(f"REVIEW    {label}: нечёткое совпадение, запустите с --allow-fuzzy после проверки стюардом")
            continue
        print(f"BATCH     {label}: {len(plan.files)} файлов", flush=True)
        result = run_batch(plan.files, contract, lake)
        print(f"{result.status.upper():9s} {result.batch_id}: bronze={result.rows_bronze} silver={result.rows_silver} "
              f"quarantine={result.rows_quarantine} parse_rejected={result.rows_parse_rejected}")
        for warning in result.warnings:
            print(f"          ! {warning}")
        if result.error:
            print(f"          x {result.error}")
        if result.status == STATUS_BLOCKED:
            exit_code = 2
        elif publisher is not None and result.status == STATUS_LOADED:
            try:
                event_id = publisher.batch_loaded(result.dataset, result.batch_id, result.rows_silver, result.rows_quarantine, result.partitions)
                print(f"EVENT     {TOPIC_BATCH_LOADED} {event_id}")
            except Exception as exc:  # noqa: BLE001 - загрузка важнее уведомления, ошибка видна в выводе
                print(f"          ! событие не отправлено: {type(exc).__name__}: {exc}")
    return exit_code


def cmd_inspect(args: argparse.Namespace) -> int:
    fp = fingerprint(Path(args.path))
    print(f"format={fp.format} encoding={fp.encoding} bom={fp.has_bom} delimiter={fp.delimiter!r} size={fp.size_bytes}")
    print("header:", ", ".join(fp.header))
    match = match_signature(fp.signature, load_contracts(Path(args.contracts)))
    print("contract:", f"{match.contract.dataset} ({match.kind}, {match.score:.2f})" if match else "не найден")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    lake = Lakehouse(Path(args.lakehouse))
    rows = lake.all_manifests()
    if not rows:
        print("манифестов нет")
        return 0
    print(f"{'dataset':22s} {'status':8s} {'bronze':>9s} {'silver':>9s} {'quar':>6s} {'finished':20s} batch")
    for m in rows:
        print(f"{m['dataset']:22s} {m['status']:8s} {m['rows_bronze']:>9} {m['rows_silver']:>9} {m['rows_quarantine']:>6} "
              f"{m['finished_at'][:19]:20s} {m['batch_id']}")
    loaded = sum(1 for m in rows if m["status"] == STATUS_LOADED)
    print(f"{len(rows)} батчей, {loaded} загружено")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.intake", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    add = sub.add_parser("add", help="загрузить файл или папку")
    add.add_argument("path")
    add.add_argument("--contracts", default="contracts")
    add.add_argument("--lakehouse", default="lakehouse")
    add.add_argument("--allow-fuzzy", action="store_true", help="принимать нечёткие совпадения контракта")
    add.add_argument("--no-events", action="store_true", help="не публиковать intake.batch.loaded в Kafka даже при заданных KAFKA_BOOTSTRAP и SCHEMA_REGISTRY_URL")
    add.set_defaults(func=cmd_add)
    inspect = sub.add_parser("inspect", help="отпечаток файла и подбор контракта")
    inspect.add_argument("path")
    inspect.add_argument("--contracts", default="contracts")
    inspect.set_defaults(func=cmd_inspect)
    status = sub.add_parser("status", help="манифесты загрузок")
    status.add_argument("--lakehouse", default="lakehouse")
    status.set_defaults(func=cmd_status)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
