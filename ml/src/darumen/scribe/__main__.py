"""python -m darumen.scribe [--port 8010]"""
from __future__ import annotations

import argparse
import os

import uvicorn

from .app import build_default_app


def main() -> int:
    parser = argparse.ArgumentParser(prog="darumen.scribe")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("DARUMEN_SCRIBE_PORT", "8010")))
    args = parser.parse_args()
    uvicorn.run(build_default_app(), host=args.host, port=args.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
