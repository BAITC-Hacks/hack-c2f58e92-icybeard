"""Download МЗ РК datasets from ashyq.data.gov.kz into DataSets/<title>/ and verify every part.

Usage:
    python scripts/download_datasets.py --list
    python scripts/download_datasets.py vac_facts treated_list [--workers 4] [--base DataSets]
    python scripts/download_datasets.py --verify-only referrals waiting refusals

Only one instance may run per base folder (lock file); a second copy exits immediately.
Parts are never resumed: a part is downloaded fresh, then checked by size, by the server's
multipart ETag when the object was uploaded in 10 MiB parts, and otherwise by a full CSV
field-count pass. Only standard library is required.
"""
from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit, urlunsplit
from urllib.request import Request, urlopen

REGISTRY = "https://ashyq.data.gov.kz/api/v0/registry/records/{id}?aspect=dcat-dataset-strings&aspect=dataset-distributions&dereference=true"
ETAG_PART_SIZE = 10 * 1024 * 1024
ATTEMPTS = 4
DATASETS = {
    "referrals": "magda-ds-4b553445-0570-4302-87e7-48e1edacfa41",
    "waiting": "magda-ds-abe1cec8-b45b-4e4c-ba04-891e0ed8b02f",
    "refusals": "magda-ds-62470e60-4a84-4c67-9c7b-4a5f14fc1d48",
    "treated_count": "magda-ds-5ebd7ba4-3bc1-4dbd-bce0-7538ce571902",
    "treated_list": "magda-ds-fe290577-78d8-4518-bd02-3cb0ec44fba5",
    "kdu": "magda-ds-d7975b53-50cb-4e24-8b16-ff4e5feb9dda",
    "staffing": "magda-ds-f4253f1c-27ac-4430-aaa6-fce37c95889c",
    "equipment": "magda-ds-aa44b972-17b6-4a6c-8c0b-cf13cfd9e3c3",
    "vac_facts": "magda-ds-5b5d3fb2-843e-4578-aa2d-7b0fd63f997e",
    "vac_refusals": "magda-ds-836fb474-c8fd-4bd1-9b4c-ad9f5c832483",
    "onco_first": "magda-ds-d5f48eaf-0094-488d-8bb1-f2b4529b098f",
    "onco_late": "magda-ds-2e65ac4e-0fb8-42b9-882f-23fba36bacb8",
    "onco_ext": "magda-ds-69b7691f-8bae-4cf9-9076-4392e7fcd392",
    "prescriptions_issued": "magda-ds-e6cd5fc0-eaa0-4445-bcae-fd6be2d3c972",
    "prescriptions_fulfilled": "magda-ds-3a2d309f-9880-45e0-9628-fa14967a3eb5",
    "drug_specs": "magda-ds-e94d2147-5f53-47b1-84f1-57cea415effa",
    "screenings": "magda-ds-bf74a4eb-4d9f-410e-ab84-09ceff6e6748",
    "newborns_almaty": "magda-ds-3a875c52-a394-4978-a505-695ec4372056",
}


def encoded(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, quote(unquote(parts.path)), parts.query, parts.fragment))


def registry(dataset_id: str) -> tuple[str, list[str]]:
    with urlopen(Request(REGISTRY.format(id=dataset_id), headers={"User-Agent": "darumen-downloader"})) as resp:
        record = json.load(resp)
    title = record["aspects"]["dcat-dataset-strings"]["title"].strip()
    dists = record["aspects"]["dataset-distributions"]["distributions"]
    urls = [d["aspects"]["dcat-distribution-strings"]["downloadURL"] for d in dists]
    urls = sorted(u for u in urls if u and "preview" not in u)
    return title, urls


def head(url: str) -> tuple[int | None, str | None]:
    out = subprocess.run(["curl", "-sIL", encoded(url)], capture_output=True, text=True).stdout
    size = etag = None
    for line in out.splitlines():
        key, _, value = line.partition(":")
        if key.lower() == "content-length":
            size = int(value.strip())
        elif key.lower() == "etag":
            etag = value.strip().strip('"')
    return size, etag


def multipart_etag(path: Path) -> str:
    digests = []
    with path.open("rb") as fh:
        while chunk := fh.read(ETAG_PART_SIZE):
            digests.append(hashlib.md5(chunk).digest())
    if len(digests) == 1:
        return hashlib.md5(path.read_bytes()).hexdigest()
    return hashlib.md5(b"".join(digests)).hexdigest() + f"-{len(digests)}"


def csv_is_consistent(path: Path) -> bool:
    with path.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader, None)
        if not header:
            return False
        return all(len(row) == len(header) for row in reader)


def verify(path: Path, size: int | None, etag: str | None) -> str:
    if not path.exists():
        return "missing"
    if size is None or path.stat().st_size != size:
        return "bad-size"
    if etag and multipart_etag(path) == etag:
        return "verified"
    return "ok-structural" if csv_is_consistent(path) else "corrupt"


def fetch(title: str, url: str, base: Path, verify_only: bool) -> str:
    folder = base / title
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / unquote(url.rsplit("/", 1)[-1])
    size, etag = head(url)
    status = verify(path, size, etag)
    if status in ("verified", "ok-structural") or verify_only:
        return f"{status:14s} {path.name[-48:]}"
    for _ in range(ATTEMPTS):
        if path.exists():
            path.unlink()
        subprocess.run(["curl", "-sL", "--retry", "3", "--retry-delay", "5", "-o", str(path), encoded(url)])
        status = verify(path, size, etag)
        if status in ("verified", "ok-structural"):
            return f"{status:14s} {path.name[-48:]}  {size / 1e6:.1f} MB"
        time.sleep(10)
    return f"FAILED         {path.name[-48:]}  ({status})"


def acquire_lock(base: Path):
    lock = (base / ".download.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit("another downloader is already running for this folder; not starting a second one")
    return lock


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("datasets", nargs="*", help="aliases from --list or raw magda-ds ids")
    parser.add_argument("--base", default="DataSets", help="target folder (default: DataSets)")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    if args.list or not args.datasets:
        for alias, dataset_id in DATASETS.items():
            print(f"{alias:14s} {dataset_id}")
        return 0
    base = Path(args.base).expanduser().resolve()
    base.mkdir(parents=True, exist_ok=True)
    lock = acquire_lock(base)
    for name in args.datasets:
        dataset_id = DATASETS.get(name, name)
        title, urls = registry(dataset_id)
        print(f"### {title}: {len(urls)} parts", flush=True)
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for line in pool.map(lambda u: fetch(title, u, base, args.verify_only), urls):
                print(line, flush=True)
    lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
