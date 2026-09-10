"""gRPC server for the model services: python -m darumen.services --lakehouse lakehouse --port 50051"""
from __future__ import annotations

import argparse
import logging
import os
from concurrent import futures
from pathlib import Path

import grpc
from grpc_health.v1 import health, health_pb2, health_pb2_grpc
from grpc_reflection.v1alpha import reflection

from ..intake.pipeline import Lakehouse
from ..v1 import (
    forecast_pb2,
    forecast_pb2_grpc,
    queue_pb2,
    queue_pb2_grpc,
    simulation_pb2,
    simulation_pb2_grpc,
)
from .forecast_service import LoadForecastingServicer
from .queue_service import QueueIntelligenceServicer
from .simulation_service import SimulationServicer
from .state import ModelState

DEFAULT_PORT = 50051
SERVICES = (queue_pb2.DESCRIPTOR.services_by_name["QueueIntelligence"].full_name,
            forecast_pb2.DESCRIPTOR.services_by_name["LoadForecasting"].full_name,
            simulation_pb2.DESCRIPTOR.services_by_name["Simulation"].full_name)
log = logging.getLogger("darumen.services")


def build_server(state: ModelState, address: str = f"[::]:{DEFAULT_PORT}", workers: int = 8) -> tuple[grpc.Server, int]:
    """Server with both services, health for every service name and reflection for grpcurl; returns the bound port."""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=workers))
    queue_pb2_grpc.add_QueueIntelligenceServicer_to_server(QueueIntelligenceServicer(state), server)
    forecast_pb2_grpc.add_LoadForecastingServicer_to_server(LoadForecastingServicer(state), server)
    simulation_pb2_grpc.add_SimulationServicer_to_server(SimulationServicer(state), server)
    health_servicer = health.HealthServicer()
    for name in ("", *SERVICES):
        health_servicer.set(name, health_pb2.HealthCheckResponse.SERVING)
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)
    reflection.enable_server_reflection((*SERVICES, health.SERVICE_NAME, reflection.SERVICE_NAME), server)
    port = server.add_insecure_port(address)
    if port == 0:
        raise OSError(f"cannot bind {address}")
    return server, port


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="darumen.services")
    parser.add_argument("--lakehouse", default=os.environ.get("DARUMEN_LAKEHOUSE", "lakehouse"))
    parser.add_argument("--host", default="[::]")
    parser.add_argument("--port", type=int, default=int(os.environ.get("DARUMEN_MODELS_PORT", DEFAULT_PORT)))
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    state = ModelState.load(Lakehouse(Path(args.lakehouse)))
    server, port = build_server(state, f"{args.host}:{args.port}")
    server.start()
    log.info("serving on %s, data as of %s, %s organisation×profile states, streams %s, wait model %s",
             port, state.as_of.date(), len(state.queue), sorted(state.streams), state.model_info)
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        server.stop(grace=5)
    return 0
