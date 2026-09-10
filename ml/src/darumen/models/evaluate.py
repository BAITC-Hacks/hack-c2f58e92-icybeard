"""python -m darumen.models.evaluate [--lakehouse lakehouse]

Re-evaluates the saved models on the held-out splits and prints the report that the slides quote.
Fails (exit 1) when a model does not beat its baseline, so CI catches regressions.
"""
from __future__ import annotations

import argparse
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
    write_json(models_dir(lake) / "report.json", {"wait": report, "model_version": model.metadata.get("version")})
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
