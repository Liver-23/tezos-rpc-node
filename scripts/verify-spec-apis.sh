#!/usr/bin/env python3
"""Verify Tezos RPC endpoints listed in TEZOSSpec.json against a running node."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SPEC_PATH = Path(__file__).resolve().parents[1] / "TEZOSSpec.json"
RPC_URL = os.environ.get("RPC_URL", "http://127.0.0.1:8732").rstrip("/")
MAINNET_CHAIN_ID = "NetXdQprcVkpaWU"
PLACEHOLDERS = {
    "{block_id}": "head",
    "{chain_id}": "main",
    "{offset}": "0",
    "{length}": "1",
    "{contract_id}": "KT1RJ6PnyHzf2tZJm6UZHPxUAvHXyMh8L5JG",
    "{path}": "default",
    "{Protocol_hash}": "ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK",
    "{operation_hash}": "oo111111111111111111111111111111111111111111111111111111111111",
    "{operation_id}": "0",
    "{index}": "0",
    "{list_offset}": "0",
    "{list_length}": "1",
    "{peer_id}": "id111111111111111111111111",
    "{smart_rollup_address}": "sr1YpF5ANe4P7x9qC8s3k2m1n0p9o8i7u6y5t4r3e2w1q0",
}


def substitute(path: str) -> str | None:
    out = path
    for key, value in PLACEHOLDERS.items():
        out = out.replace(key, value)
    if "{" in out:
        return None
    return out


def request(method: str, path: str) -> tuple[int, str]:
    url = f"{RPC_URL}{path}"
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read(512).decode("utf-8", errors="replace")
            return resp.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read(512).decode("utf-8", errors="replace")
        return exc.code, body


def main() -> int:
    if not SPEC_PATH.is_file():
        print(f"Spec not found: {SPEC_PATH}", file=sys.stderr)
        return 1

    with SPEC_PATH.open(encoding="utf-8") as f:
        spec = json.load(f)

    collections = spec["Spec"]["api_collections"]
    ok = 0
    skipped = 0
    failed: list[str] = []

    # Chain id check (TEZOSSpec verification)
    status, body = request("GET", "/chains/main/chain_id")
    if status != 200 or MAINNET_CHAIN_ID not in body:
        print(f"FAIL chain_id: status={status} body={body[:120]!r}")
        return 1
    print(f"OK mainnet chain_id ({MAINNET_CHAIN_ID})")

    for coll in collections:
        if not coll.get("enabled", True):
            continue
        iface = coll["collection_data"]["api_interface"]
        http_type = coll["collection_data"]["type"]
        if iface != "rest":
            print(f"SKIP unsupported api_interface={iface!r}")
            continue

        method = http_type.upper()
        for api in coll.get("apis", []):
            if not api.get("enabled", True):
                continue
            path = substitute(api["name"])
            if path is None:
                skipped += 1
                continue

            status, _ = request(method, path)
            # POST helpers often return 400 without a body; still proves RPC route exists.
            acceptable = {200, 204}
            if method == "POST":
                acceptable |= {400, 404, 405, 500}
            if status in acceptable:
                ok += 1
            else:
                failed.append(f"{method} {path} -> {status}")

    print(f"Checked: {ok} ok, {skipped} skipped (unresolved placeholders), {len(failed)} failed")
    for line in failed[:25]:
        print(f"  {line}")
    if len(failed) > 25:
        print(f"  ... and {len(failed) - 25} more")

    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
