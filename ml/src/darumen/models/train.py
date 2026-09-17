"""python -m darumen.models.train [--lakehouse lakehouse] [--only wait,forecast,anomaly,simulate,index,los,survival,anomaly_labels]"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from ..intake.pipeline import Lakehouse
from .anomaly import detect_all
from .anomaly_labels import train_anomaly_labels
from .cards import write_cards
from .common import load_features, mlflow_log, models_dir
from .forecast import forecast_all
from .index import build_index, method_note
from .los import train_los
from .simulate import counterfactual_q1
from .survival import train_survival
from .wait import model_card, train_wait

CARDS_DIR = Path(__file__).resolve().parents[4] / "docs" / "model-cards"
PARTS = ("wait", "forecast", "anomaly", "simulate", "index", "los", "survival", "anomaly_labels")


def parse_only(value: str) -> set[str]:
    """Части обучения из `--only`: точное совпадение имён, иначе `anomaly_labels` включал бы и `anomaly`."""
    parts = {p.strip() for p in value.split(",") if p.strip()}
    unknown = parts - set(PARTS)
    if unknown:
        raise SystemExit(f"неизвестные части --only: {', '.join(sorted(unknown))}; допустимы: {', '.join(PARTS)}")
    return parts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.models.train")
    parser.add_argument("--lakehouse", default="lakehouse")
    parser.add_argument("--only", default=",".join(PARTS),
                        help="через запятую: wait, forecast, anomaly, simulate, index, los, survival, anomaly_labels")
    parser.add_argument("--cards", default=str(CARDS_DIR))
    parser.add_argument("--streams", default="", help="через запятую: только эти потоки для forecast и anomaly")
    args = parser.parse_args(argv)
    lake = Lakehouse(Path(args.lakehouse))
    streams = [s for s in args.streams.split(",") if s] or None
    only = parse_only(args.only)
    started = time.time()
    if "wait" in only:
        out = models_dir(lake) / "wait"
        features = load_features(lake)
        model, report = train_wait(features, out)
        card = model_card(model, report)
        cards = Path(args.cards)
        cards.mkdir(parents=True, exist_ok=True)
        (cards / "wait.md").write_text(card, encoding="utf-8")
        flat = {f"{split}_{k}": v for split, m in report.items() for k, v in m.items() if isinstance(v, (int, float))}
        run_id = mlflow_log("wait", {"rows": model.metadata["train_rows"], **model.metadata["params"]}, flat,
                            [out / "metadata.json", cards / "wait.md"])
        for split, m in report.items():
            print(f"{split:10s} n={m['n']:>7,} pinball_p50 {m['pinball_p50']:.2f} (base {m['pinball_p50_baseline']:.2f}) "
                  f"pinball_p90 {m['pinball_p90']:.2f} (base {m['pinball_p90_baseline']:.2f}) coverage_p90 {m['coverage_p90']:.3f} "
                  f"auc_within30 {m['auc_within30']:.3f} auc_refusal {m['auc_refusal']:.3f} (base {m['auc_refusal_baseline']:.3f})")
        print(f"saved to {out}, card {cards / 'wait.md'}, mlflow run {run_id}")
    if "forecast" in only:
        for stream_id, report in forecast_all(lake, only=streams).items():
            if report.get("skipped"):
                print(f"forecast {stream_id:20s} skipped: {report['skipped']}")
                continue
            chosen = report["chosen"]
            better = report['models'][chosen]['series_better_than_baseline']
            print(f"forecast {stream_id:20s} series={report['series']:>5} h={report['horizon']} chosen={chosen} "
                  f"mase {report['models'][chosen]['mase']:.3f} (baseline {report['models'][report['baseline']]['mase']:.3f}) "
                  f"smape {report['models'][chosen]['smape']:.3f} (baseline {report['models'][report['baseline']]['smape']:.3f}) "
                  + (f"better on {better:.0%} of series" if better is not None else "baseline kept: the naive model won the backtest"))
            flat = {k: v for k, v in report["models"][chosen].items() if isinstance(v, (int, float)) and v is not None}
            mlflow_log(f"forecast_{stream_id}", {"chosen": chosen, "series": report["series"]}, flat,
                       [lake.root / "models" / "forecast" / stream_id / "report.json"])
    if "anomaly" in only:
        for stream_id, report in detect_all(lake, only=streams).items():
            if report.get("skipped"):
                print(f"anomaly  {stream_id:20s} skipped: {report['skipped']}")
                continue
            print(f"anomaly  {stream_id:20s} series={report['series']:>5} alerts={report['alerts']} critical={report['critical']} "
                  f"entity-specific={report['entity_specific']} | injected spikes: precision@k {report.get('precision_at_k', float('nan')):.2f} "
                  f"recall {report.get('recall_at_threshold', float('nan')):.2f} alerts/1000 {report.get('alerts_per_1000_points', float('nan')):.1f}")
    if "simulate" in only:
        summary = counterfactual_q1(lake)
        lo, hi = summary["saved_share_band"]
        c = summary["consistency"]
        print(f"simulate counterfactual Q1: {summary['groups_with_moves']} region×profile groups with moves, "
              f"{summary['saved_days']:,.0f} of {summary['wait_days_before']:,.0f} waiting days saved ({summary['saved_share']:.1%}, band {lo:.1%}–{hi:.1%}) "
              f"over {summary['horizon_days']} days from {summary['as_of']}; consistency with observed p50: spearman {c['spearman']:.2f}, MAE {c['mae_days']:.1f} d")
        mlflow_log("simulate", {"as_of": summary["as_of"], "horizon_days": summary["horizon_days"]},
                   {k: v for k, v in summary.items() if isinstance(v, (int, float))} | {f"consistency_{k}": v for k, v in c.items()},
                   [lake.root / "models" / "simulate" / "counterfactual_q1.json"])
    if {"forecast", "anomaly", "simulate"} & only:
        for path in write_cards(lake, Path(args.cards)):
            print(f"card {path}")
    if "los" in only:
        report = train_los(lake, models_dir(lake) / "los")
        print(f"los      train={report['train_rows']:,} test={report['test_rows']:,} | pinball p50 {report['pinball_p50']:.3f} "
              f"(baseline {report['pinball_p50_baseline']:.3f}) MAE {report['mae']:.2f} (baseline {report['mae_baseline']:.2f}) | "
              f"{report['cells']} ячеек region×profile в gold/los_by_profile")
        mlflow_log("los", {"train_rows": report["train_rows"]},
                   {k: v for k, v in report.items() if isinstance(v, (int, float))},
                   [lake.root / "models" / "los" / "report.json"])
    if "survival" in only:
        report = train_survival(lake, models_dir(lake) / "survival")
        for split, m in report["splits"].items():
            print(f"survival {split:10s} n={m['n']:>7,} c-index {m['c_index']:.3f} (base {m['c_index_baseline']:.3f}) "
                  f"auc30 {m['auc30']:.3f} (base {m['auc30_baseline']:.3f}) "
                  f"P(госп.≤30) {m['p_admit_mean']['30']:.2f} факт {m['observed_share']['30']:.2f}")
        mlflow_log("survival", {"train_rows": report["train_rows"]},
                   {f"{s}_{k}": v for s, m in report["splits"].items() for k, v in m.items()
                    if isinstance(v, (int, float))},
                   [lake.root / "models" / "survival" / "report.json"])
    if "anomaly_labels" in only:
        report = train_anomaly_labels(lake, models_dir(lake) / "anomaly_labels")
        if report.get("skipped"):
            print(f"anomaly_labels skipped: {report['skipped']}")
        else:
            print(f"anomaly_labels n={report['labels']} (+{report['positives']}/−{report['negatives']}) "
                  f"CV-AUC {report['auc_cv']:.3f} (baseline |score| {report['auc_baseline_abs_score']:.3f})")
    if "index" in only:
        index = build_index(lake)
        note = Path(args.cards).parent / "access-index.md"
        method_note(note)
        latest = index[(index["profile_code"] == "all") & (index["month"] == index["month"].max())]
        print(f"index    {len(index):,} rows, latest month {index['month'].max()}: top {latest.iloc[0]['region_kato']} "
              f"({latest.iloc[0]['index_value']}), bottom {latest.iloc[-1]['region_kato']} ({latest.iloc[-1]['index_value']}); note {note}")
    print(f"done in {time.time() - started:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
