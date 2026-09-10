"""python -m darumen.models.train [--lakehouse lakehouse] [--only wait]"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

from ..intake.pipeline import Lakehouse
from .anomaly import detect_all
from .cards import write_cards
from .common import load_features, mlflow_log, models_dir
from .forecast import forecast_all
from .wait import model_card, train_wait

CARDS_DIR = Path(__file__).resolve().parents[4] / "docs" / "model-cards"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.models.train")
    parser.add_argument("--lakehouse", default="lakehouse")
    parser.add_argument("--only", default="wait,forecast,anomaly", help="через запятую: wait, forecast, anomaly")
    parser.add_argument("--cards", default=str(CARDS_DIR))
    args = parser.parse_args(argv)
    lake = Lakehouse(Path(args.lakehouse))
    started = time.time()
    if "wait" in args.only:
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
    if "forecast" in args.only:
        for stream_id, report in forecast_all(lake).items():
            if report.get("skipped"):
                print(f"forecast {stream_id:20s} skipped: {report['skipped']}")
                continue
            chosen = report["chosen"]
            print(f"forecast {stream_id:20s} series={report['series']:>5} h={report['horizon']} chosen={chosen} "
                  f"mase {report['models'][chosen]['mase']:.3f} (baseline {report['models'][report['baseline']]['mase']:.3f}) "
                  f"smape {report['models'][chosen]['smape']:.3f} (baseline {report['models'][report['baseline']]['smape']:.3f}) "
                  f"better on {report['models'][chosen]['series_better_than_baseline']:.0%} of series")
            flat = {k: v for k, v in report["models"][chosen].items() if isinstance(v, (int, float)) and v is not None}
            mlflow_log(f"forecast_{stream_id}", {"chosen": chosen, "series": report["series"]}, flat,
                       [lake.root / "models" / "forecast" / stream_id / "report.json"])
    if "anomaly" in args.only:
        for stream_id, report in detect_all(lake).items():
            if report.get("skipped"):
                print(f"anomaly  {stream_id:20s} skipped: {report['skipped']}")
                continue
            print(f"anomaly  {stream_id:20s} series={report['series']:>5} alerts={report['alerts']} critical={report['critical']} "
                  f"entity-specific={report['entity_specific']} | injected spikes: precision@k {report.get('precision_at_k', float('nan')):.2f} "
                  f"recall {report.get('recall_at_threshold', float('nan')):.2f} alerts/1000 {report.get('alerts_per_1000_points', float('nan')):.1f}")
    if "forecast" in args.only or "anomaly" in args.only:
        for path in write_cards(lake, Path(args.cards)):
            print(f"card {path}")
    print(f"done in {time.time() - started:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
