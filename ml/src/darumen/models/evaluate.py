"""python -m darumen.models.evaluate [--lakehouse lakehouse]

Re-evaluates the saved models on the held-out splits and prints the report that the slides quote.
Fails (exit 1) when a model does not beat its baseline, so CI catches regressions.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from ..intake.pipeline import Lakehouse
from .common import load_features, models_dir, write_json
from .wait import WaitModel, evaluate_split

MIN_SIMULATOR_SPEARMAN = 0.5


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
    simulate = {}
    sim_path = models_dir(lake) / "simulate" / "counterfactual_q1.json"
    if sim_path.exists():
        simulate = json.loads(sim_path.read_text(encoding="utf-8"))
        c = simulate["consistency"]
        consistent = c["spearman"] >= MIN_SIMULATOR_SPEARMAN
        failed |= not consistent
        print(f"simulate Q1 counterfactual: {simulate['saved_share']:.1%} of waiting days saved (band {simulate['saved_share_band'][0]:.1%}–"
              f"{simulate['saved_share_band'][1]:.1%}), {simulate['groups_with_moves']} groups | vs observed p50: spearman {c['spearman']:.2f}, "
              f"MAE {c['mae_days']:.1f} d | {'OK' if consistent else 'INCONSISTENT WITH OBSERVED WAITS'}")
    index = {}
    index_path = lake.root / "gold" / "access_index.parquet"
    if index_path.exists():
        idx = pd.read_parquet(index_path)
        latest = idx[(idx["profile_code"] == "all") & (idx["month"] == idx["month"].max())].sort_values("rank")
        index = {"rows": len(idx), "months": int(idx["month"].nunique()), "latest_month": str(idx["month"].max().date()),
                 "latest_top": latest.head(3)[["region_kato", "index_value"]].to_dict("records"),
                 "latest_bottom": latest.tail(3)[["region_kato", "index_value"]].to_dict("records")}
        print(f"index    {index['rows']:,} rows over {index['months']} months | {index['latest_month']} top: "
              + ", ".join(f"{r['region_kato']} ({r['index_value']})" for r in index["latest_top"]) + " | bottom: "
              + ", ".join(f"{r['region_kato']} ({r['index_value']})" for r in index["latest_bottom"]))
    write_json(models_dir(lake) / "report.json", {"wait": report, "forecast": forecasts, "anomaly": anomalies,
                                                   "simulate": simulate, "index": index,
                                                   "model_version": model.metadata.get("version")})
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
