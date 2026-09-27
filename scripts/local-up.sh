#!/usr/bin/env bash
# Local rehearsal: deploy the full zipcoin stack on an anvil mainnet fork and point web/.env.local at it.
# Prereq (separate terminal): anvil --fork-url https://eth.drpc.org --chain-id 31337 --port 8545
# The fork RPC must serve historical state (drpc / flashbots / tenderly do; publicnode does not).
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="$ROOT/vendor/privacy-pools-core/packages/contracts"

# anvil default test accounts 0 (owner/dev) and 1 (postman); these keys are public test keys
OWNER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

cd "$C"
mkdir -p deployments
OWNER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 POSTMAN_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  forge script script/zipcoin/Zipcoin.s.sol:LocalFork --rpc-url http://127.0.0.1:8545 --broadcast --private-key "$OWNER_PK" --slow >/dev/null

python3 - "$C/deployments/zipcoin-local.json" "$ROOT/web/.env.local" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
open(sys.argv[2], "w").write(f"""# local anvil fork of mainnet (anvil default test keys only)
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_ZC={d['zc']}
NEXT_PUBLIC_ENTRYPOINT={d['entrypoint']}
NEXT_PUBLIC_POOL={d['pool']}
NEXT_PUBLIC_BROADCASTER={d['broadcaster']}
NEXT_PUBLIC_SCOPE={d['scope']}
NEXT_PUBLIC_DEPLOY_BLOCK={d['deployBlock']}
NEXT_PUBLIC_RELAY_FEE_BPS=100
NEXT_PUBLIC_MIN_BURN=1000000000000000000000
NEXT_PUBLIC_MIN_RELAY=10000000000000000000000
RPC_URL=http://127.0.0.1:8545
RELAYER_PRIVATE_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
POSTMAN_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ASP_DELAY_SEC=30
ENABLE_WORKERS=1
ASP_TICK_MS=10000
RELAY_SUBSIDY_BPS=10000
RELAY_DAILY_SUBSIDY_WEI=500000000000000000
""")
print(json.dumps(d, indent=2))
EOF
