"""python -m darumen.models.evaluate [--lakehouse lakehouse]

Re-evaluates the saved models on the held-out splits and prints the report that the slides quote.
Fails (exit 1) when a model does not beat its baseline, so CI catches regressions.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from ..intake.pipeline import Lakehouse
from .common import load_features, models_dir, write_json
from .wait import WaitModel, evaluate_split


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.models.evaluate")
    parser.add_argument("--lakehouse", default="lakehouse")
    args = parser.parse_args(argv)
    lake = Lakehouse(Path(args.lakehouse))
    model = WaitModel.load(models_dir(lake) / "wait")
    features = load_features(lake)
    report = {}
    failed = False
    for split in ("test_time", "test_mo"):
        df = features[features["split"] == split]
        if not len(df):
            continue
        m = evaluate_split(model, df)
        report[split] = m
        beats = m["pinball_p50"] < m["pinball_p50_baseline"] and m["pinball_p90"] < m["pinball_p90_baseline"] and m["auc_refusal"] > m["auc_refusal_baseline"]
        failed |= not beats
        print(f"{split:10s} n={m['n']:>7,} | p50 pinball {m['pinball_p50']:.2f} vs base {m['pinball_p50_baseline']:.2f} | "
              f"p90 pinball {m['pinball_p90']:.2f} vs base {m['pinball_p90_baseline']:.2f} | coverage p90 {m['coverage_p90']:.3f} | "
              f"AUC within30 {m['auc_within30']:.3f} | AUC refusal {m['auc_refusal']:.3f} vs base {m['auc_refusal_baseline']:.3f} | "
              f"{'OK' if beats else 'WORSE THAN BASELINE'}")
    forecasts = {}
    for path in sorted((models_dir(lake) / "forecast").glob("*/report.json")):
        rep = json.loads(path.read_text(encoding="utf-8"))
        if rep.get("skipped"):
            continue
        chosen, base = rep["chosen"], rep["baseline"]
        beats = rep["models"][chosen]["mase"] <= rep["models"][base]["mase"]
        failed |= not beats
        forecasts[rep["stream"]] = rep
        print(f"forecast {rep['stream']:18s} series={rep['series']:>5} | MASE {rep['models'][chosen]['mase']:.3f} vs naive {rep['models'][base]['mase']:.3f} | "
              f"sMAPE {rep['models'][chosen]['smape']:.3f} vs {rep['models'][base]['smape']:.3f} | {'OK' if beats else 'WORSE THAN BASELINE'}")
    anomalies = {}
    for path in sorted((models_dir(lake) / "anomaly").glob("*/report.json")):
        rep = json.loads(path.read_text(encoding="utf-8"))
        anomalies[rep["stream"]] = rep
        print(f"anomaly  {rep['stream']:18s} alerts={rep['alerts']:>5} | injected spikes precision@k {rep.get('precision_at_k', float('nan')):.2f} "
              f"recall {rep.get('recall_at_threshold', float('nan')):.2f}")
    write_json(models_dir(lake) / "report.json", {"wait": report, "forecast": forecasts, "anomaly": anomalies,
                                                   "model_version": model.metadata.get("version")})
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
