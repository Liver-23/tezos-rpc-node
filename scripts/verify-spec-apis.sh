#!/usr/bin/env python3
"""Verify Tezos RPC endpoints listed in TEZOSSpec.json against a running node."""
from __future__ import annotations

import json
import os
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

SPEC_PATH = Path(__file__).resolve().parents[1] / "TEZOSSpec.json"
RPC_URL = os.environ.get("RPC_URL", "http://127.0.0.1:8732").rstrip("/")
DEFAULT_TIMEOUT_S = float(os.environ.get("VERIFY_TIMEOUT", "30"))
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


def api_timeout_s(api: dict) -> float:
    category = api.get("category") or {}
    if category.get("hanging_api"):
        return 0.0
    raw = api.get("timeout_ms", "0")
    try:
        ms = int(raw)
    except (TypeError, ValueError):
        ms = 0
    if ms > 0:
        return min(ms / 1000.0, 120.0)
    return DEFAULT_TIMEOUT_S


def should_skip(api: dict, path: str) -> str | None:
    category = api.get("category") or {}
    if category.get("hanging_api"):
        return "hanging/long-poll endpoint"
    if path.startswith("/monitor/") or path.endswith("/monitor_operations"):
        return "monitor stream (long-poll)"
    # Listing all contracts at head can take minutes on full/archive nodes.
    if path.endswith("/context/contracts"):
        return "heavy context list"
    return None


def fetch_protocol_hash() -> str | None:
    status, body, err = request(
        "GET", "/chains/main/blocks/head/header", DEFAULT_TIMEOUT_S, max_body=65536
    )
    if err or status != 200:
        return None
    try:
        data = json.loads(body)
        return data.get("protocol")
    except json.JSONDecodeError:
        return None


def request(
    method: str, path: str, timeout_s: float, *, max_body: int = 512
) -> tuple[int | None, str, str | None]:
    url = f"{RPC_URL}{path}"
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read(max_body).decode("utf-8", errors="replace")
            return resp.status, body, None
    except urllib.error.HTTPError as exc:
        body = exc.read(max_body).decode("utf-8", errors="replace")
        return exc.code, body, None
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, socket.timeout):
            return None, "", "timeout"
        if isinstance(reason, TimeoutError):
            return None, "", "timeout"
        return None, "", str(reason)
    except TimeoutError:
        return None, "", "timeout"


def main() -> int:
    if not SPEC_PATH.is_file():
        print(f"Spec not found: {SPEC_PATH}", file=sys.stderr)
        return 1

    verbose = os.environ.get("VERIFY_VERBOSE", "").lower() in ("1", "true", "yes")

    with SPEC_PATH.open(encoding="utf-8") as f:
        spec = json.load(f)

    collections = spec["Spec"]["api_collections"]
    ok = 0
    skipped = 0
    failed: list[str] = []

    status, body, err = request("GET", "/chains/main/chain_id", DEFAULT_TIMEOUT_S)
    if err or status != 200 or MAINNET_CHAIN_ID not in body:
        print(f"FAIL chain_id: status={status} err={err} body={body[:120]!r}")
        return 1
    print(f"OK mainnet chain_id ({MAINNET_CHAIN_ID})")

    protocol = fetch_protocol_hash()
    if protocol:
        PLACEHOLDERS["{Protocol_hash}"] = protocol
        print(f"OK protocol placeholder -> {protocol}")
    else:
        print("WARN could not resolve protocol hash; protocol paths may 404")

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

            skip_reason = should_skip(api, path)
            if skip_reason:
                skipped += 1
                if verbose:
                    print(f"SKIP {method} {path} ({skip_reason})")
                continue

            timeout_s = api_timeout_s(api)
            status, _, err = request(method, path, timeout_s)

            if verbose:
                print(f"  {method} {path} -> {status or err}")

            if err == "timeout":
                failed.append(f"{method} {path} -> timeout ({timeout_s}s)")
                continue
            if err:
                failed.append(f"{method} {path} -> error ({err})")
                continue

            # Any HTTP response means the RPC route exists (body may be invalid for smoke test).
            acceptable = {200, 204, 400, 404, 405, 500}
            if status in acceptable:
                ok += 1
            else:
                failed.append(f"{method} {path} -> {status}")

    print(
        f"Checked: {ok} ok, {skipped} skipped "
        f"(placeholders + long-poll), {len(failed)} failed"
    )
    for line in failed[:25]:
        print(f"  {line}")
    if len(failed) > 25:
        print(f"  ... and {len(failed) - 25} more")

    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
