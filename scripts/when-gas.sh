#!/usr/bin/env bash
# Waits until the mainnet base fee is at or below MAX_GWEI, then runs the given command.
#   MAX_GWEI=2.5 ./scripts/when-gas.sh <command...>
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
MAX_GWEI="${MAX_GWEI:-2.5}"
RPC_READ="${RPC_READ:-https://ethereum-rpc.publicnode.com}"
while true; do
  base=$(cast base-fee --rpc-url "$RPC_READ" 2>/dev/null || echo 999000000000)
  gwei=$(python3 -c "print(round($base/1e9,3))")
  if python3 -c "import sys; sys.exit(0 if $base/1e9 <= $MAX_GWEI else 1)"; then
    echo "$(date -u +%H:%M:%S) base fee $gwei gwei <= $MAX_GWEI, running"
    exec "$@"
  fi
  echo "$(date -u +%H:%M:%S) base fee $gwei gwei, waiting"
  sleep 30
done
