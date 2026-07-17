#!/usr/bin/env bash
set -euo pipefail

RPC_URL="http://127.0.0.1:8899"
LEDGER_DIR="${RUNNER_TEMP:-/tmp}/test-ledger"

rm -rf "$LEDGER_DIR"
solana-test-validator --reset --quiet --ledger "$LEDGER_DIR" > "${RUNNER_TEMP:-/tmp}/validator-stdout.log" 2>&1 &
echo "Validator started with PID $!"

for i in $(seq 1 60); do
  if solana cluster-version -u "$RPC_URL" >/dev/null 2>&1; then
    echo "Validator healthy after ${i}s"
    exit 0
  fi
  sleep 1
done

echo "Validator did not become healthy within 60s" >&2
tail -50 "$LEDGER_DIR/validator.log" 2>/dev/null || true
exit 1
