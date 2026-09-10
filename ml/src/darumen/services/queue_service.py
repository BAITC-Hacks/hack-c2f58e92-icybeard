"""Queue Intelligence: wait quantiles, refusal risk and alternatives from the wait model and the queue state."""
from __future__ import annotations

import grpc
import numpy as np
import pandas as pd

from ..v1 import common_pb2, queue_pb2, queue_pb2_grpc
from .state import ModelState, haversine_km

DEFAULT_LIMIT = 5


def model_info(state: ModelState) -> common_pb2.ModelInfo:
    return common_pb2.ModelInfo(**state.model_info)


def explanation(state: ModelState, row: pd.DataFrame, target: str = "q50") -> common_pb2.Explanation:
    ru = state.wait.explain(row, lang="ru", target=target)[0]
    kz = state.wait.explain(row, lang="kz", target=target)[0]
    factors = [common_pb2.Factor(name=r["name"], contribution=r["contribution"], text_ru=r["text"], text_kz=k["text"])
               for r, k in zip(ru["factors"], kz["factors"], strict=True)]
    return common_pb2.Explanation(factors=factors, summary_ru=ru["summary"], summary_kz=kz["summary"])


class QueueIntelligenceServicer(queue_pb2_grpc.QueueIntelligenceServicer):
    def __init__(self, state: ModelState):
        self.state = state

    def _resolve(self, request: queue_pb2.PredictWaitRequest, context: grpc.ServicerContext) -> tuple[pd.DataFrame, np.ndarray]:
        """Feature rows and weights: one organisation, or every organisation of the region with the profile
        weighted by its referrals of the last four weeks."""
        state = self.state
        profile, region = request.profile_code, request.region.kato
        if profile not in state.known_profiles:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown profile_code '{profile}'")
        if request.mo_code:
            if request.mo_code not in state.known_organisations:
                context.abort(grpc.StatusCode.NOT_FOUND, f"unknown mo_code '{request.mo_code}'")
            mo_codes, weights = [request.mo_code], np.ones(1)
        else:
            if region not in state.known_regions:
                context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown region '{region}'")
            orgs = state.organisations(region, profile)
            if orgs.empty:
                context.abort(grpc.StatusCode.NOT_FOUND, f"no organisations with profile '{profile}' in region '{region}'")
            mo_codes, weights = list(orgs["mo_code"]), orgs["registered_4w"].to_numpy(dtype=float) + 1.0
        rows = state.feature_rows(mo_codes, profile, request.icd10, request.referral_purpose, request.finance_source,
                                  request.territorial_type, request.registration_date)
        return rows, weights / weights.sum()

    def PredictWait(self, request, context):
        rows, weights = self._resolve(request, context)
        pred = self.state.wait.predict(rows)
        top = rows.iloc[[int(np.argmax(weights))]]
        return queue_pb2.PredictWaitResponse(
            p50_days=float(pred["p50_days"].to_numpy() @ weights), p90_days=float(pred["p90_days"].to_numpy() @ weights),
            p_within_30_days=float(pred["p_within_30"].to_numpy() @ weights),
            explanation=explanation(self.state, top), model=model_info(self.state))

    def PredictRefusal(self, request, context):
        rows, weights = self._resolve(request, context)
        pred = self.state.wait.predict(rows)
        top = rows.iloc[[int(np.argmax(weights))]]
        return queue_pb2.PredictRefusalResponse(
            p_refusal=float(pred["p_refusal"].to_numpy() @ weights),
            explanation=explanation(self.state, top, target="refusal"), model=model_info(self.state))

    def Alternatives(self, request, context):
        state, base = self.state, request.base
        if base.profile_code not in state.known_profiles:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown profile_code '{base.profile_code}'")
        region = base.region.kato or state.region_of(base.mo_code)
        if region not in state.known_regions:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown region '{region}'")
        orgs = state.organisations(region, base.profile_code)
        orgs = orgs[orgs["mo_code"] != base.mo_code]
        if orgs.empty:
            return queue_pb2.AlternativesResponse(model=model_info(state))
        rows = state.feature_rows(list(orgs["mo_code"]), base.profile_code, base.icd10, base.referral_purpose,
                                  base.finance_source, base.territorial_type, base.registration_date)
        pred = state.wait.predict(rows)
        origin = state.registry_by_code.get(base.mo_code, {})
        items = []
        for i, mo in enumerate(orgs["mo_code"]):
            rg = state.registry_by_code.get(mo, {})
            distance = haversine_km(origin.get("lat"), origin.get("lon"), rg.get("lat"), rg.get("lon"))
            if request.max_distance_km > 0 and distance > request.max_distance_km:
                continue
            items.append(queue_pb2.Alternative(
                organization=common_pb2.OrganizationRef(mo_code=mo, name=str(rg.get("name_canonical") or mo),
                                                        region=common_pb2.RegionRef(kato=region)),
                p50_days=float(pred["p50_days"].iloc[i]), p90_days=float(pred["p90_days"].iloc[i]),
                p_refusal=float(pred["p_refusal"].iloc[i]), distance_km=distance))
        items.sort(key=lambda a: a.p50_days)
        limit = request.limit or DEFAULT_LIMIT
        return queue_pb2.AlternativesResponse(alternatives=items[:limit], model=model_info(state))
