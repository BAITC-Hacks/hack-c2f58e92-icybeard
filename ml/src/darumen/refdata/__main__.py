"""python -m darumen.refdata build [--lakehouse lakehouse]"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from ..intake.pipeline import Lakehouse
from .build import build_refdata

parser = argparse.ArgumentParser(prog="darumen.refdata")
sub = parser.add_subparsers(dest="command", required=True)
build = sub.add_parser("build", help="собрать справочники и реестр организаций")
build.add_argument("--lakehouse", default="lakehouse")
args = parser.parse_args()
print(json.dumps(build_refdata(Lakehouse(Path(args.lakehouse))), ensure_ascii=False, indent=1))
