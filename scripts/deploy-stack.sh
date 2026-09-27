#!/usr/bin/env bash
# Deploys the zipcoin stack for one sender token and registers it.
#   RPC=<url> ASSET=<token> OUT=<name> ./scripts/deploy-stack.sh
# Keys are read from ~/.config/zipcoin/*.key and never printed.
#   test_deployer.key  pays for deployments (holds no role afterwards)
#   owner.key          Entrypoint OWNER (registers pools)
#   postman.key        ASP postman
#   relayer.key        relayer hot wallet
# Reuses ENTRYPOINT if set (the Entrypoint is shared by every pool), otherwise deploys the proxy.
# FUND=1 tops up owner / postman / relayer from the deployer (FUND_OWNER, FUND_POSTMAN, FUND_RELAYER in ETH).
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
: "${RPC:?RPC required}" "${ASSET:?ASSET required}" "${OUT:?OUT required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
C="$ROOT/vendor/privacy-pools-core/packages/contracts"
K="$HOME/.config/zipcoin"
key() { local k; k="$(tr -d '\n' < "$K/$1.key")"; [[ $k == 0x* ]] || k="0x$k"; printf '%s' "$k"; }
addr() { cast wallet address --private-key "$(key "$1")"; }

DEPLOYER_PK="$(key test_deployer)"
OWNER="$(addr owner)"; POSTMAN="$(addr postman)"; RELAYER="$(addr relayer)"
echo "deployer $(addr test_deployer)  owner $OWNER  postman $POSTMAN  relayer $RELAYER"

if [ "${FUND:-0}" = "1" ]; then
  for who in owner postman relayer; do
    amt_var="FUND_$(echo "$who" | tr a-z A-Z)"; amt="${!amt_var:-0}"
    [ "$amt" = "0" ] && continue
    cast send --rpc-url "$RPC" --private-key "$DEPLOYER_PK" "$(addr "$who")" --value "${amt}ether" >/dev/null
    echo "funded $who $amt ETH"
  done
fi

cd "$C"
if [ -z "${ENTRYPOINT:-}" ]; then
  ENTRYPOINT=$(OWNER_ADDRESS="$OWNER" POSTMAN_ADDRESS="$POSTMAN" forge script script/zipcoin/Zipcoin.s.sol:DeployEntrypointProxy \
    --rpc-url "$RPC" --broadcast --private-key "$DEPLOYER_PK" --slow 2>&1 | sed -n 's/.*Entrypoint \(0x[0-9a-fA-F]\{40\}\).*/\1/p' | tail -1)
  [ -n "$ENTRYPOINT" ] || { echo "entrypoint deploy failed"; exit 1; }
  echo "entrypoint $ENTRYPOINT"
fi

mkdir -p deployments
ENTRYPOINT_ADDRESS="$ENTRYPOINT" ASSET_ADDRESS="$ASSET" MIN_BURN="${MIN_BURN:-1000000000000000000000}" OUT_FILE="./deployments/$OUT.json" \
  forge script script/zipcoin/Zipcoin.s.sol:DeployPoolUnregistered --rpc-url "$RPC" --broadcast --private-key "$DEPLOYER_PK" --slow >/dev/null
POOL=$(python3 -c "import json;print(json.load(open('deployments/$OUT.json'))['pool'])")

cast send --rpc-url "$RPC" --private-key "$(key owner)" "$ENTRYPOINT" \
  "registerPool(address,address,uint256,uint256,uint256)" "$ASSET" "$POOL" "${MIN_DEPOSIT:-1000000000000000000}" "${VETTING_BPS:-50}" "${MAX_RELAY_BPS:-300}" >/dev/null
echo "registered pool $POOL"
cat "deployments/$OUT.json"
