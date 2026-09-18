"""Command line for blind intake.

    python -m darumen.intake add <file|folder> [--contracts contracts] [--lakehouse lakehouse]
    python -m darumen.intake inspect <file>
    python -m darumen.intake status [--lakehouse lakehouse]
    python -m darumen.intake contracts list [--lakehouse lakehouse]
    python -m darumen.intake contracts approve <dataset> [--contracts contracts] [--lakehouse lakehouse]
    python -m darumen.intake reprocess <file|folder> [--contracts contracts] [--lakehouse lakehouse]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

from .contracts import load_contracts, match_signature
from .events import TOPIC_BATCH_LOADED, EventPublisher
from .fingerprint import fingerprint
from .gold_refresh import rebuild_after_batch
from .pipeline import STATUS_BLOCKED, STATUS_LOADED, Lakehouse, draft_contract, plan_batches, run_batch


def _run_plans(target: Path, contracts_dir: Path, lake: Lakehouse, publisher: EventPublisher | None, allow_fuzzy: bool) -> int:
    """Shared core of `add` and `reprocess`: plan → run each matched batch → publish → rebuild gold (4.5)."""
    exit_code = 0
    for plan in plan_batches(target, contracts_dir):
        first = plan.files[0]
        if plan.match is None:
            draft = draft_contract(first, plan.fingerprint, lake)
            print(f"UNKNOWN   {first.parent.name}/{first.name}: схема не найдена, черновик контракта: {draft}")
            continue
        contract = plan.match.contract
        label = f"{contract.dataset} ({plan.match.kind}, {plan.match.score:.2f})"
        if plan.match.kind != "exact" and not allow_fuzzy:
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
        elif result.status == STATUS_LOADED:
            gold = rebuild_after_batch(lake, result.dataset)
            if gold["rebuilt"]:
                print(f"GOLD      пересобрано: {', '.join(t['table'] for t in gold['rebuilt'])}" + (" и опубликовано" if gold["published"] else ""))
            if gold["warning"]:
                print(f"          ! {gold['warning']}")
            if publisher is not None:
                try:
                    event_id = publisher.batch_loaded(result.dataset, result.batch_id, result.rows_silver, result.rows_quarantine, result.partitions)
                    print(f"EVENT     {TOPIC_BATCH_LOADED} {event_id}")
                except Exception as exc:  # noqa: BLE001 - загрузка важнее уведомления, ошибка видна в выводе
                    print(f"          ! событие не отправлено: {type(exc).__name__}: {exc}")
    return exit_code


def cmd_add(args: argparse.Namespace) -> int:
    lake = Lakehouse(Path(args.lakehouse))
    publisher = None if args.no_events else EventPublisher.from_env()
    return _run_plans(Path(args.path), Path(args.contracts), lake, publisher, args.allow_fuzzy)


def cmd_reprocess(args: argparse.Namespace) -> int:
    """4.4: перезапустить файл(ы) после того, как контракт поменялся (утверждён черновик, поправлено
    правило) — тот же путь, что и `add`, специально с --allow-fuzzy по умолчанию, так как файл уже прошёл
    ручную проверку стюардом при первой загрузке или при утверждении черновика."""
    lake = Lakehouse(Path(args.lakehouse))
    publisher = None if args.no_events else EventPublisher.from_env()
    return _run_plans(Path(args.path), Path(args.contracts), lake, publisher, allow_fuzzy=True)


def cmd_contracts(args: argparse.Namespace) -> int:
    lake = Lakehouse(Path(args.lakehouse))
    if args.contracts_command == "list":
        drafts = sorted(lake.drafts().glob("*.yaml"))
        if not drafts:
            print("черновиков нет")
            return 0
        for path in drafts:
            draft = yaml.safe_load(path.read_text(encoding="utf-8"))
            print(f"{draft['dataset']:24s} {draft.get('title', ''):40s} колонок: {len(draft.get('columns', {}))}  {path}")
        return 0
    # approve
    draft_path = lake.drafts() / f"{args.dataset}.yaml"
    if not draft_path.exists():
        print(f"черновик '{args.dataset}' не найден в {lake.drafts()}")
        return 1
    draft = yaml.safe_load(draft_path.read_text(encoding="utf-8"))
    source_file = draft.pop("source_file", None)
    draft.pop("draft_model", None)
    draft["status"] = "approved"
    contracts_dir = Path(args.contracts)
    contracts_dir.mkdir(parents=True, exist_ok=True)
    contract_path = contracts_dir / f"{draft['dataset']}.yaml"
    contract_path.write_text(yaml.safe_dump(draft, allow_unicode=True, sort_keys=False), encoding="utf-8")
    draft_path.unlink()
    print(f"APPROVED  {draft['dataset']}: {contract_path}")
    if source_file and Path(source_file).exists():
        publisher = None if args.no_events else EventPublisher.from_env()
        return _run_plans(Path(source_file), contracts_dir, lake, publisher, allow_fuzzy=True)
    print("          исходный файл черновика не найден, переобработайте его отдельно через `intake reprocess`")
    return 0


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
    reprocess = sub.add_parser("reprocess", help="перезапустить файл после правки контракта")
    reprocess.add_argument("path")
    reprocess.add_argument("--contracts", default="contracts")
    reprocess.add_argument("--lakehouse", default="lakehouse")
    reprocess.add_argument("--no-events", action="store_true")
    reprocess.set_defaults(func=cmd_reprocess)
    contracts = sub.add_parser("contracts", help="черновики контрактов: список и утверждение")
    contracts_sub = contracts.add_subparsers(dest="contracts_command", required=True)
    contracts_list = contracts_sub.add_parser("list", help="черновики, ждущие утверждения")
    contracts_list.add_argument("--lakehouse", default="lakehouse")
    contracts_approve = contracts_sub.add_parser("approve", help="утвердить черновик и переобработать его файл")
    contracts_approve.add_argument("dataset")
    contracts_approve.add_argument("--contracts", default="contracts")
    contracts_approve.add_argument("--lakehouse", default="lakehouse")
    contracts_approve.add_argument("--no-events", action="store_true")
    contracts.set_defaults(func=cmd_contracts)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
