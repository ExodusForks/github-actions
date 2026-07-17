#!/usr/bin/env bash
set -euo pipefail

RPC_URL="http://127.0.0.1:8899"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
SCENARIO_DIR="${RUNNER_TEMP:-/tmp}/scenario-nearmax"
MAX_PROGRAM_SIZE=10485715
MIN_EXTEND_SIZE=10240
ARTIFACT_MARGIN=2000

mkdir -p "$SCENARIO_DIR" target/deploy

gunzip -c "$FIXTURES_DIR/program-huge.so.gz" > target/deploy/fixture-nearmax.so
HUGE_SIZE=$(wc -c < target/deploy/fixture-nearmax.so | tr -d ' ')
TARGET_CURRENT=$((HUGE_SIZE - ARTIFACT_MARGIN))
HEADROOM=$((MAX_PROGRAM_SIZE - TARGET_CURRENT))

if [ "$HUGE_SIZE" -gt "$MAX_PROGRAM_SIZE" ]; then
  echo "Fixture drift: huge artifact of $HUGE_SIZE bytes exceeds max program size $MAX_PROGRAM_SIZE" >&2
  exit 1
fi
if [ "$HEADROOM" -le 0 ] || [ "$HEADROOM" -ge "$MIN_EXTEND_SIZE" ]; then
  echo "Fixture drift: pre-extend headroom of $HEADROOM bytes is outside (0, $MIN_EXTEND_SIZE)" >&2
  exit 1
fi

solana-keygen new -s --no-bip39-passphrase --force -o "$SCENARIO_DIR/deployer.json" >/dev/null
solana-keygen new -s --no-bip39-passphrase --force -o "$SCENARIO_DIR/program-id.json" >/dev/null
DEPLOYER=$(solana-keygen pubkey "$SCENARIO_DIR/deployer.json")
PROGRAM_ID=$(solana-keygen pubkey "$SCENARIO_DIR/program-id.json")

for i in 1 2 3; do
  solana airdrop 200 "$DEPLOYER" -u "$RPC_URL" && break
  if [ "$i" -eq 3 ]; then
    echo "Airdrop failed after 3 attempts" >&2
    exit 1
  fi
  sleep 2
done

solana program deploy "$FIXTURES_DIR/program-small.so" \
  --program-id "$SCENARIO_DIR/program-id.json" \
  -u "$RPC_URL" -k "$SCENARIO_DIR/deployer.json" \
  --commitment confirmed

PRE_LEN=$(solana program show "$PROGRAM_ID" -u "$RPC_URL" | grep "Data Length:" | awk '{print $3}')
EXTEND_SETUP=$((TARGET_CURRENT - PRE_LEN))

for i in 1 2 3; do
  if solana program extend "$PROGRAM_ID" "$EXTEND_SETUP" \
    -u "$RPC_URL" -k "$SCENARIO_DIR/deployer.json" \
    --commitment confirmed; then
    break
  fi
  if [ "$i" -eq 3 ]; then
    echo "Setup extend failed after 3 attempts" >&2
    exit 1
  fi
  sleep 2
done

PRE_LEN=$(solana program show "$PROGRAM_ID" -u "$RPC_URL" | grep "Data Length:" | awk '{print $3}')
if [ "$PRE_LEN" -ne "$TARGET_CURRENT" ]; then
  echo "Setup failed: program data length is $PRE_LEN, expected $TARGET_CURRENT" >&2
  exit 1
fi

echo "Prepared nearmax scenario: deployer=$DEPLOYER program-id=$PROGRAM_ID pre-len=$PRE_LEN headroom=$HEADROOM"
{
  echo "keypair=$(cat "$SCENARIO_DIR/deployer.json")"
  echo "deployer=$DEPLOYER"
  echo "program-id=$PROGRAM_ID"
  echo "buffer-authority=$DEPLOYER"
  echo "pre-len=$PRE_LEN"
} >> "$GITHUB_OUTPUT"
