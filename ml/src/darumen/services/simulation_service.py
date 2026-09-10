"""Simulation: what-if scenarios and redistribution on the calibrated fluid queue, from the preloaded states."""
from __future__ import annotations

import grpc

from ..models.simulate import VERSION, redistribute, simulate_states
from ..v1 import common_pb2, simulation_pb2, simulation_pb2_grpc
from .state import ModelState

DEFAULT_HORIZON_DAYS = 90
DEFAULT_MAX_SHARE_PCT = 20.0


def _model_info(state: ModelState) -> common_pb2.ModelInfo:
    return common_pb2.ModelInfo(name="fluid_queue", version=VERSION, trained_through=str(state.as_of.date()))


class SimulationServicer(simulation_pb2_grpc.SimulationServicer):
    def __init__(self, state: ModelState):
        self.state = state

    def _check(self, region: str, profile: str, context: grpc.ServicerContext) -> None:
        if profile not in self.state.known_profiles:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown profile_code '{profile}'")
        if region not in self.state.known_regions:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"unknown region '{region}'")

    def Simulate(self, request, context):
        self._check(request.region.kato, request.profile_code, context)
        result = simulate_states(self.state.sim_states, request.region.kato, request.profile_code, request.capacity_delta_pct,
                                 request.redirect_share_pct, request.horizon_days or DEFAULT_HORIZON_DAYS)
        if "error" in result:
            context.abort(grpc.StatusCode.NOT_FOUND, result["error"])
        return simulation_pb2.SimulateResponse(
            organisations=result["organisations"],
            baseline=simulation_pb2.ScenarioOutcome(mean_wait_days=result["baseline"]["mean_wait_days"]),
            scenario=simulation_pb2.ScenarioOutcome(mean_wait_days=result["scenario"]["mean_wait_days"]),
            delta_days=result["delta_days"], ci_low=result["ci"][0], ci_high=result["ci"][1],
            assumptions=result["assumptions"], model=_model_info(self.state))

    def Redistribute(self, request, context):
        self._check(request.region.kato, request.profile_code, context)
        result = redistribute(self.state.sim_states, request.region.kato, request.profile_code,
                              max_share_moved_pct=request.max_share_moved_pct or DEFAULT_MAX_SHARE_PCT,
                              horizon_days=request.horizon_days or DEFAULT_HORIZON_DAYS)
        registry = self.state.registry_by_code

        def org(mo: str) -> common_pb2.OrganizationRef:
            row = registry.get(mo, {})
            return common_pb2.OrganizationRef(mo_code=mo, name=str(row.get("name_canonical") or mo),
                                              region=common_pb2.RegionRef(kato=request.region.kato))

        moves = [simulation_pb2.Move(**{"from": org(m["from_mo"]), "to": org(m["to_mo"])},
                                     share_of_source_pct=m["share_of_source_pct"], arrivals_per_day=m["arrivals_per_day"],
                                     wait_from_before=m["wait_from_before"], wait_from_after=m["wait_from_after"],
                                     wait_to_before=m["wait_to_before"], wait_to_after=m["wait_to_after"])
                 for m in result["moves"]]
        return simulation_pb2.RedistributeResponse(
            moves=moves, total_wait_days_before=result.get("total_wait_days_before", 0.0),
            total_wait_days_after=result.get("total_wait_days_after", 0.0), total_delta_days=result["total_delta_days"],
            horizon_days=result.get("horizon_days", request.horizon_days or DEFAULT_HORIZON_DAYS), model=_model_info(self.state))
