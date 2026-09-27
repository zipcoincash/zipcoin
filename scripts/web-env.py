#!/usr/bin/env python3
"""Writes web/.env.local for a deployment. Secrets are read from ~/.config/zipcoin and never printed.

usage: web-env.py <deployment.json> <chain_id> <public_rpc> <server_rpc> [KEY=VALUE ...]
"""
import json
import os
import sys

dep, chain_id, public_rpc, server_rpc, *extra = sys.argv[1:]
d = json.load(open(dep))
keys = os.path.expanduser("~/.config/zipcoin")


def secret(name):
    k = open(f"{keys}/{name}.key").read().strip()
    return k if k.startswith("0x") else "0x" + k


public = {
    "NEXT_PUBLIC_CHAIN_ID": chain_id,
    "NEXT_PUBLIC_RPC_URL": public_rpc,
    "NEXT_PUBLIC_ZC": d["zc"],
    "NEXT_PUBLIC_ENTRYPOINT": d["entrypoint"],
    "NEXT_PUBLIC_POOL": d["pool"],
    "NEXT_PUBLIC_BROADCASTER": d["broadcaster"],
    "NEXT_PUBLIC_SCOPE": str(d["scope"]),
    "NEXT_PUBLIC_DEPLOY_BLOCK": str(d["deployBlock"]),
    "NEXT_PUBLIC_RELAY_FEE_BPS": "100",
    "NEXT_PUBLIC_MIN_BURN": "1000000000000000000000",
    "NEXT_PUBLIC_MIN_RELAY": "10000000000000000000000",
    "RPC_URL": server_rpc,
    "ENABLE_WORKERS": "1",
    "ASP_DELAY_SEC": "60",
    "ASP_TICK_MS": "20000",
    "RELAY_SUBSIDY_BPS": "10000",
    "RELAY_DAILY_SUBSIDY_WEI": "10000000000000000",
    "LOG_CHUNK_BLOCKS": "5000",
}
for kv in extra:
    k, v = kv.split("=", 1)
    public[k] = v

path = os.path.join(os.path.dirname(__file__), "..", "web", ".env.local")
old = os.umask(0o177)
with open(path, "w") as f:
    for k, v in public.items():
        f.write(f"{k}={v}\n")
    f.write(f"RELAYER_PRIVATE_KEY={secret('relayer')}\n")
    f.write(f"POSTMAN_PRIVATE_KEY={secret('postman')}\n")
os.umask(old)
for k, v in public.items():
    print(f"{k}={v}")
print("RELAYER_PRIVATE_KEY=<from ~/.config/zipcoin/relayer.key>")
print("POSTMAN_PRIVATE_KEY=<from ~/.config/zipcoin/postman.key>")
