"""Queue Intelligence models: waiting-time quantiles, probability of admission within 30 days, refusal risk.

Training data: gold.features_wait (round-the-clock referrals). Splits: train (January–February 2025),
test_time (March 2025), test_mo (10 % of organisations held out entirely). Baseline: median and
90th percentile of realised waits per organisation and profile in the training period.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd

from .common import (
    CATEGORICAL,
    FEATURES,
    LABELS_KZ,
    LABELS_RU,
    NUMERIC,
    auc,
    brier,
    calibration_table,
    coverage,
    encode,
    mae,
    pinball,
    write_json,
)

VERSION = "1.0.0"
QUANTILES = (0.5, 0.9)
WITHIN_DAYS = 30
PARAMS = {"learning_rate": 0.05, "num_leaves": 63, "min_data_in_leaf": 100, "feature_fraction": 0.8,
          "bagging_fraction": 0.8, "bagging_freq": 1, "lambda_l2": 1.0, "verbose": -1, "seed": 42}
ROUNDS = 600
EARLY_STOP = 50


@dataclass
class WaitModel:
    boosters: dict[str, lgb.Booster]
    categories: dict[str, list[str]]
    baseline: pd.DataFrame           # mo_code, profile_code, base_p50, base_p90, base_refusal
    profile_baseline: pd.DataFrame   # profile_code, base_p50, base_p90, base_refusal
    global_baseline: dict[str, float]
    metadata: dict = field(default_factory=dict)

    # ---------- inference ----------
    def predict(self, rows: pd.DataFrame) -> pd.DataFrame:
        x, _ = encode(rows, self.categories)
        out = pd.DataFrame(index=rows.index)
        out["p50_days"] = np.clip(self.boosters["q50"].predict(x), 0, None)
        out["p90_days"] = np.maximum(np.clip(self.boosters["q90"].predict(x), 0, None), out["p50_days"])
        out["p_within_30"] = self.boosters["within30"].predict(x)
        out["p_refusal"] = self.boosters["refusal"].predict(x)
        return out

    def baseline_predict(self, rows: pd.DataFrame) -> pd.DataFrame:
        merged = rows[["mo_code", "profile_code"]].merge(self.baseline, how="left", on=["mo_code", "profile_code"])
        by_profile = rows[["profile_code"]].merge(self.profile_baseline, how="left", on="profile_code")
        out = pd.DataFrame(index=rows.index)
        for col in ("base_p50", "base_p90", "base_refusal"):
            out[col] = merged[col].to_numpy()
            fallback = by_profile[col].to_numpy()
            out[col] = np.where(np.isnan(out[col]), fallback, out[col])
            out[col] = np.where(np.isnan(out[col]), self.global_baseline[col], out[col])
        return out

    def explain(self, rows: pd.DataFrame, top: int = 4, lang: str = "ru", target: str = "q50") -> list[dict]:
        """Per-row SHAP contributions of one booster, rendered as short sentences: days for the quantile
        models, log-odds for the risk models (the summary converts the base to a probability)."""
        x, _ = encode(rows, self.categories)
        contrib = self.boosters[target].predict(x, pred_contrib=True)
        labels = LABELS_KZ if lang == "kz" else LABELS_RU
        in_days = target in ("q50", "q90")
        results = []
        for i, (_, row) in enumerate(rows.iterrows()):
            pairs = sorted(zip(FEATURES, contrib[i][:-1], strict=True), key=lambda kv: -abs(kv[1]))[:top]
            factors = []
            for name, value in pairs:
                raw = row.get(name)
                shown = f"{raw:.1f}" if isinstance(raw, (float, np.floating)) and not pd.isna(raw) else str(raw)
                sign = "+" if value >= 0 else "−"
                unit = (" күн" if lang == "kz" else " дн.") if in_days else ""
                factors.append({"name": name, "contribution": float(value),
                                "text": f"{labels.get(name, name)}: {shown} ({sign}{abs(value):.1f}{unit})"})
            base = float(contrib[i][-1])
            if in_days:
                summary = (f"Базовое ожидание {base:.0f} дн., ключевые факторы: " if lang != "kz" else f"Базалық күту {base:.0f} күн, негізгі факторлар: ")
            else:
                risk = 1 / (1 + np.exp(-base))
                summary = (f"Базовый риск {risk:.0%}, ключевые факторы: " if lang != "kz" else f"Базалық тәуекел {risk:.0%}, негізгі факторлар: ")
            summary += "; ".join(f["text"] for f in factors[:2])
            results.append({"summary": summary, "factors": factors})
        return results

    # ---------- persistence ----------
    def save(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        for name, booster in self.boosters.items():
            booster.save_model(str(directory / f"{name}.txt"))
        self.baseline.to_parquet(directory / "baseline.parquet", index=False)
        self.profile_baseline.to_parquet(directory / "baseline_profile.parquet", index=False)
        write_json(directory / "metadata.json", {**self.metadata, "categories": self.categories,
                                                 "global_baseline": self.global_baseline, "version": VERSION})

    @classmethod
    def load(cls, directory: Path) -> WaitModel:
        meta = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
        boosters = {name: lgb.Booster(model_file=str(directory / f"{name}.txt")) for name in ("q50", "q90", "within30", "refusal")}
        return cls(boosters, meta["categories"], pd.read_parquet(directory / "baseline.parquet"),
                   pd.read_parquet(directory / "baseline_profile.parquet"), meta["global_baseline"], meta)


# ---------- training ----------

def _fit(objective: dict, x: pd.DataFrame, y: np.ndarray, x_val: pd.DataFrame, y_val: np.ndarray) -> lgb.Booster:
    params = {**PARAMS, **objective}
    train = lgb.Dataset(x, y, categorical_feature=CATEGORICAL, free_raw_data=False)
    valid = lgb.Dataset(x_val, y_val, reference=train, categorical_feature=CATEGORICAL, free_raw_data=False)
    return lgb.train(params, train, num_boost_round=ROUNDS, valid_sets=[valid],
                     callbacks=[lgb.early_stopping(EARLY_STOP, verbose=False)])


def _baselines(train: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict[str, float]]:
    admitted = train[train["wait_days"].notna()]
    by_mo = admitted.groupby(["mo_code", "profile_code"])["wait_days"].agg(base_p50="median", base_p90=lambda s: s.quantile(0.9)).reset_index()
    ref_mo = train.groupby(["mo_code", "profile_code"])["refused"].mean().rename("base_refusal").reset_index()
    by_mo = by_mo.merge(ref_mo, on=["mo_code", "profile_code"], how="outer")
    by_profile = admitted.groupby("profile_code")["wait_days"].agg(base_p50="median", base_p90=lambda s: s.quantile(0.9)).reset_index()
    by_profile = by_profile.merge(train.groupby("profile_code")["refused"].mean().rename("base_refusal").reset_index(), on="profile_code", how="outer")
    global_ = {"base_p50": float(admitted["wait_days"].median()), "base_p90": float(admitted["wait_days"].quantile(0.9)),
               "base_refusal": float(train["refused"].mean())}
    return by_mo, by_profile, global_


def evaluate_split(model: WaitModel, df: pd.DataFrame) -> dict:
    """Metrics of the model and of the baseline on one split."""
    pred = model.predict(df)
    base = model.baseline_predict(df)
    admitted = df["wait_days"].notna().to_numpy()
    y_wait = df.loc[admitted, "wait_days"].to_numpy(dtype=float)
    metrics = {
        "n": len(df), "n_admitted": int(admitted.sum()),
        "pinball_p50": pinball(y_wait, pred.loc[admitted, "p50_days"].to_numpy(), 0.5),
        "pinball_p50_baseline": pinball(y_wait, base.loc[admitted, "base_p50"].to_numpy(), 0.5),
        "pinball_p90": pinball(y_wait, pred.loc[admitted, "p90_days"].to_numpy(), 0.9),
        "pinball_p90_baseline": pinball(y_wait, base.loc[admitted, "base_p90"].to_numpy(), 0.9),
        "mae_p50": mae(y_wait, pred.loc[admitted, "p50_days"].to_numpy()),
        "mae_p50_baseline": mae(y_wait, base.loc[admitted, "base_p50"].to_numpy()),
        "coverage_p90": coverage(y_wait, pred.loc[admitted, "p90_days"].to_numpy()),
        "coverage_p90_baseline": coverage(y_wait, base.loc[admitted, "base_p90"].to_numpy()),
    }
    known = (df["wait_days"].notna() | df["refused"]).to_numpy()
    y_within = df.loc[known, "within_30"].to_numpy(dtype=float)
    p_within = pred.loc[known, "p_within_30"].to_numpy()
    y_ref = df["refused"].to_numpy(dtype=float)
    metrics.update({
        "auc_within30": auc(y_within, p_within), "brier_within30": brier(y_within, p_within),
        "auc_refusal": auc(y_ref, pred["p_refusal"].to_numpy()), "auc_refusal_baseline": auc(y_ref, base["base_refusal"].to_numpy()),
        "brier_refusal": brier(y_ref, pred["p_refusal"].to_numpy()),
        "calibration_within30": calibration_table(y_within, p_within),
        "calibration_refusal": calibration_table(y_ref, pred["p_refusal"].to_numpy()),
    })
    return metrics


def breakdown(model: WaitModel, df: pd.DataFrame, key: str, top: int = 25) -> list[dict]:
    """Ошибка модели и baseline по срезам (регион, профиль): видно, где модель хуже простого правила."""
    pred = model.predict(df)
    base = model.baseline_predict(df)
    rows = []
    for value, part in df.groupby(key, observed=True):
        admitted = part["wait_days"].notna().to_numpy()
        if int(admitted.sum()) < 50:  # менее 50 наблюдений — оценка шумная, в отчёт не идёт
            continue
        y = part.loc[admitted, "wait_days"].to_numpy(dtype=float)
        p = pred.loc[part.index[admitted], "p50_days"].to_numpy()
        b = base.loc[part.index[admitted], "base_p50"].to_numpy()
        rows.append({key: str(value), "n": int(admitted.sum()),
                     "pinball_p50": pinball(y, p, 0.5), "pinball_p50_baseline": pinball(y, b, 0.5),
                     "mae_p50": mae(y, p), "mae_p50_baseline": mae(y, b)})
    rows.sort(key=lambda r: r["n"], reverse=True)
    return rows[:top]


def train_wait(features: pd.DataFrame, out_dir: Path, trained_through: str | None = None) -> tuple[WaitModel, dict]:
    train = features[features["split"] == "train"]
    tests = {name: features[features["split"] == name] for name in ("test_time", "test_mo")}
    x_train, categories = encode(train)
    # early stopping on a slice of March held out from the model selection reports
    val = tests["test_time"].sample(frac=0.3, random_state=42) if len(tests["test_time"]) > 20 else tests["test_time"]
    x_val, _ = encode(val, categories)

    admitted = train["wait_days"].notna().to_numpy()
    admitted_val = val["wait_days"].notna().to_numpy()
    y_wait = train["wait_days"].to_numpy(dtype=float)
    y_wait_val = val["wait_days"].to_numpy(dtype=float)
    boosters = {
        "q50": _fit({"objective": "quantile", "alpha": 0.5}, x_train[admitted], y_wait[admitted], x_val[admitted_val], y_wait_val[admitted_val]),
        "q90": _fit({"objective": "quantile", "alpha": 0.9}, x_train[admitted], y_wait[admitted], x_val[admitted_val], y_wait_val[admitted_val]),
    }
    known = (train["wait_days"].notna() | train["refused"]).to_numpy()
    known_val = (val["wait_days"].notna() | val["refused"]).to_numpy()
    boosters["within30"] = _fit({"objective": "binary"}, x_train[known], train["within_30"].to_numpy(dtype=float)[known],
                                x_val[known_val], val["within_30"].to_numpy(dtype=float)[known_val])
    boosters["refusal"] = _fit({"objective": "binary"}, x_train, train["refused"].to_numpy(dtype=float),
                               x_val, val["refused"].to_numpy(dtype=float))

    by_mo, by_profile, global_ = _baselines(train)
    model = WaitModel(boosters, categories, by_mo, by_profile, global_)
    report = {name: evaluate_split(model, df) for name, df in tests.items() if len(df)}
    if len(tests["test_time"]):
        report["by_region"] = breakdown(model, tests["test_time"], "region_kato")
        report["by_profile"] = breakdown(model, tests["test_time"], "profile_code")
    importance = {name: dict(zip(FEATURES, booster.feature_importance("gain").tolist(), strict=True)) for name, booster in boosters.items()}
    model.metadata = {
        "name": "wait_quantile", "trained_through": trained_through or str(train["registration_date"].max()),
        "train_rows": len(train), "features": FEATURES, "categorical": CATEGORICAL, "numeric": NUMERIC,
        "params": PARAMS, "best_iterations": {k: int(b.best_iteration or b.current_iteration()) for k, b in boosters.items()},
        "metrics": report, "importance_gain": importance,
    }
    model.save(out_dir)
    write_json(out_dir / "report.json", report)
    return model, report


def model_card(model: WaitModel, report: dict) -> str:
    meta = model.metadata
    lines = [
        "# Карточка модели: ожидание плановой госпитализации и риск отказа",
        "",
        f"Версия {VERSION}. Обучено на {meta['train_rows']:,} направлениях круглосуточных стационаров, регистрация с 1 января по {meta['trained_through']}.",
        "Четыре бустинга LightGBM: квантили p50 и p90 времени ожидания (дни), вероятность госпитализации за 30 дней, вероятность отказа.",
        "Baseline: медиана и 90-й перцентиль фактического ожидания по организации и профилю за обучающий период, доля отказов по организации и профилю.",
        "",
        "## Метрики на отложенных выборках",
        "",
        "| Выборка | n | Пинбол p50 (модель / baseline) | Пинбол p90 (модель / baseline) | MAE p50 (модель / baseline) | Покрытие p90 | AUC за 30 дней | AUC отказа (модель / baseline) |",
        "|---|---|---|---|---|---|---|---|",
    ]
    names = {"test_time": "Март 2025 (время)", "test_mo": "10 % организаций (перенос)"}
    for split, m in report.items():
        lines.append(f"| {names.get(split, split)} | {m['n']:,} | {m['pinball_p50']:.2f} / {m['pinball_p50_baseline']:.2f} | "
                     f"{m['pinball_p90']:.2f} / {m['pinball_p90_baseline']:.2f} | {m['mae_p50']:.2f} / {m['mae_p50_baseline']:.2f} | "
                     f"{m['coverage_p90']:.3f} | {m['auc_within30']:.3f} | {m['auc_refusal']:.3f} / {m['auc_refusal_baseline']:.3f} |")
    top = sorted(meta["importance_gain"]["q50"].items(), key=lambda kv: -kv[1])[:8]
    lines += ["", "## Главные признаки модели p50 (gain)", ""] + [f"- {LABELS_RU.get(k, k)}: {v:,.0f}" for k, v in top]
    lines += [
        "", "## Признаки", "",
        "Категориальные: " + ", ".join(CATEGORICAL) + ".", "Числовые: " + ", ".join(NUMERIC) + ".",
        "Все признаки загрузки считаются по данным строго до даты регистрации направления (тест на утечку в ml/tests/test_gold.py).",
        "", "## Ограничения", "",
        "- Данные покрывают только I квартал 2025 года: сезонность не выучена, прогноз на другие сезоны не проверен.",
        "- Очередь на начало квартала не видна (направления до 1 января отсутствуют), поэтому признаки очереди в первые недели занижены.",
        "- Регион организации для 391 из 1 406 организаций определён по большинству направлений, а не по справочнику.",
        "- Модель говорит о сроках и рисках логистики, не о клинических решениях; перенаправление подтверждает врач.",
    ]
    return "\n".join(lines) + "\n"
