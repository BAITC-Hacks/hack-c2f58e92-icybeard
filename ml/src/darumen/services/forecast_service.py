"""Load Forecasting: precomputed forecasts of any registered stream, with backtest metrics per series."""
from __future__ import annotations

import grpc

from ..models.forecast import smape
from ..models.streams import Stream
from ..v1 import common_pb2, forecast_pb2, forecast_pb2_grpc
from .state import ModelState


class LoadForecastingServicer(forecast_pb2_grpc.LoadForecastingServicer):
    def __init__(self, state: ModelState):
        self.state = state

    def Forecast(self, request, context):
        state = self.state
        stream = state.streams.get(request.stream_id)
        if stream is None:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown stream_id '{request.stream_id}', known: {sorted(state.streams)}")
        entity = dict(request.entity)
        missing = [k for k in stream.entity if not entity.get(k)]
        if missing:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"entity keys for {stream.stream_id}: {list(stream.entity)}, missing {missing}")
        fc = state.forecasts
        mask = fc["stream_id"] == stream.stream_id
        for key in stream.entity:
            mask &= fc[key].astype(str) == entity[key]
        rows = fc[mask].sort_values("horizon")
        if request.horizon > 0:
            rows = rows[rows["horizon"] <= request.horizon]
        if rows.empty:
            context.abort(grpc.StatusCode.NOT_FOUND, f"no forecast for {entity} in {stream.stream_id}")
        points = [forecast_pb2.ForecastPoint(period=str(r.period), yhat=float(r.yhat), lo=float(r.lo), hi=float(r.hi))
                  for r in rows.itertuples()]
        name, _, version = str(rows["model"].iloc[0]).partition("@")
        flat = bool(rows["flat"].iloc[0]) if "flat" in rows.columns else False
        report = state.reports.get(stream.stream_id, {})
        return forecast_pb2.ForecastResponse(
            points=points, backtest=self._backtest(stream, entity, report, chosen=name), flat=flat,
            model=common_pb2.ModelInfo(name=name, version=version, trained_through=str(report.get("trained_through", ""))))

    def _backtest(self, stream: Stream, entity: dict[str, str], report: dict, chosen: str | None = None) -> forecast_pb2.BacktestMetrics:
        """sMAPE of this series in the rolling-origin backtest; MASE at stream level because its scale is
        in-sample per series and not stored. Zero means no backtest. `chosen` — модель этого ряда."""
        chosen, baseline = chosen or report.get("chosen"), report.get("baseline")
        mase = float(report.get("models", {}).get(chosen, {}).get("mase", 0.0)) if chosen else 0.0
        backtest = self.state.backtests.get(stream.stream_id)
        if backtest is None or chosen not in backtest or baseline not in backtest:
            return forecast_pb2.BacktestMetrics(mase=mase)
        part = backtest[backtest["unique_id"] == "|".join(entity[k] for k in stream.entity)]
        if part.empty:
            return forecast_pb2.BacktestMetrics(mase=mase)
        y = part["y"].to_numpy(dtype=float)
        return forecast_pb2.BacktestMetrics(smape=smape(y, part[chosen].to_numpy(dtype=float)), mase=mase,
                                            baseline_smape=smape(y, part[baseline].to_numpy(dtype=float)))
