#!/usr/bin/env bash
# One command after the real $ZC launch (Stockereum by default, VENUE=sender for sender.family):
#   ZC=<token address> [VENUE=stockereum|sender] [LAUNCH_BLOCK=<block of the launch tx>] ./scripts/go-live.sh
# 1. deploys the ZC pool + burn contract on the existing Entrypoint and registers it (owner key)
# 2. points the Railway service at it and rebuilds (NEXT_PUBLIC_* are baked at build time)
set -euo pipefail
: "${ZC:?ZC token address required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRYPOINT="${ENTRYPOINT:-0x7a8DA01D241C3cFcF7803cdB007EcE5663749193}"
RPC="${RPC:-$(cat "$HOME/.config/zipcoin/quicknode.url" 2>/dev/null || echo https://ethereum-rpc.publicnode.com)}"
export VENUE="${VENUE:-stockereum}" LAUNCH_BLOCK="${LAUNCH_BLOCK:-}"

RPC="$RPC" ENTRYPOINT="$ENTRYPOINT" ASSET="$ZC" OUT=zc-mainnet "$ROOT/scripts/deploy-stack.sh"

DEP="$ROOT/vendor/privacy-pools-core/packages/contracts/deployments/zc-mainnet.json"
python3 - "$DEP" <<'EOF'
import json, os, subprocess, sys
d = json.load(open(sys.argv[1]))
vals = {
    "NEXT_PUBLIC_ZC": d["zc"],
    "NEXT_PUBLIC_POOL": d["pool"],
    "NEXT_PUBLIC_BROADCASTER": d["broadcaster"],
    "NEXT_PUBLIC_SCOPE": str(d["scope"]),
    "NEXT_PUBLIC_DEPLOY_BLOCK": str(d["deployBlock"]),
    "NEXT_PUBLIC_VENUE": os.environ["VENUE"],
    "TOKEN_LAUNCH_BLOCK": os.environ.get("LAUNCH_BLOCK") or "",
}
args = ["railway", "variables", "--service", "web", "--environment", "production", "--skip-deploys"]
for k, v in vals.items():
    args += ["--set", f"{k}={v}"]
env = dict(os.environ, RAILWAY_CALLER="skill:use-railway@1.2.2", RAILWAY_AGENT_SESSION="zipcoin-go-live")
subprocess.run(args, cwd=os.path.join(os.path.dirname(sys.argv[1]), "../../../../../web"), env=env, check=True, capture_output=True)
print("railway vars updated:", json.dumps(vals, indent=2))
EOF

cd "$ROOT/web"
RAILWAY_CALLER="skill:use-railway@1.2.2" RAILWAY_AGENT_SESSION="zipcoin-go-live" railway up --service web --environment production --detach -m "go live: \$ZC $ZC"
echo "rebuilding; live in ~3 minutes"
