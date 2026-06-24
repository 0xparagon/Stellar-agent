#!/usr/bin/env bash
# cleanup-demo.sh — return leftover demo tokens to treasury after each run.
#
# After a lifecycle run the seller holds ~9.9M MUSD and the treasury holds
# ~100K MUSD from the 1% fee split. This script sends those balances back
# so repeated runs start clean.
#
# Usage:
#   ./scripts/cleanup-demo.sh
#
# Requires the same .env as demo/ (SELLER_SECRET, BUYER_SECRET, USDC_TOKEN_CONTRACT).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../demo/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

: "${SELLER_SECRET:?SELLER_SECRET must be set}"
: "${BUYER_SECRET:?BUYER_SECRET must be set}"
: "${USDC_TOKEN_CONTRACT:?USDC_TOKEN_CONTRACT must be set}"
: "${STELLAR_NETWORK:=testnet}"

# Resolve public keys
SELLER_PUBKEY=$(node -e "const {Keypair}=require('@stellar/stellar-sdk');console.log(Keypair.fromSecret('$SELLER_SECRET').publicKey())")
TREASURY=$(node -e "const {Keypair}=require('@stellar/stellar-sdk');console.log(Keypair.fromSecret('$BUYER_SECRET').publicKey())")

echo "[cleanup] Seller  : $SELLER_PUBKEY"
echo "[cleanup] Treasury: $TREASURY"
echo "[cleanup] Token   : $USDC_TOKEN_CONTRACT"

# Query seller USDC balance via Horizon
BALANCE=$(curl -sf "https://horizon-testnet.stellar.org/accounts/$SELLER_PUBKEY" \
  | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const b=JSON.parse(d).balances?.find(b=>b.asset_type!=='native');console.log(b?b.balance:'0');})" \
  2>/dev/null || echo "0")

echo "[cleanup] Seller USDC balance: $BALANCE"

if [[ "$BALANCE" == "0" || "$BALANCE" == "0.0000000" ]]; then
  echo "[cleanup] Nothing to clean up."
  exit 0
fi

# Convert to stroops (7 decimal places), leave 0 remainder
STROOPS=$(node -e "console.log(BigInt(Math.floor(parseFloat('$BALANCE') * 1e7)).toString())")

echo "[cleanup] Returning $BALANCE USDC ($STROOPS stroops) to treasury..."

stellar contract invoke \
  --source-account "$SELLER_SECRET" \
  --network "$STELLAR_NETWORK" \
  --id "$USDC_TOKEN_CONTRACT" \
  -- transfer \
  --from "$SELLER_PUBKEY" \
  --to "$TREASURY" \
  --amount "$STROOPS"

echo "[cleanup] Done."
