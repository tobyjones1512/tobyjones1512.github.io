#!/bin/bash
# Vercel KV purchase lookup
# Fill in your KV credentials from the Vercel dashboard (Storage → your KV store → .env.local)

KV_REST_API_URL="YOUR_KV_REST_API_URL_HERE"
KV_REST_API_TOKEN="YOUR_KV_REST_API_TOKEN_HERE"

# ── sanity check ─────────────────────────────────────────────────────────────
if [[ "$KV_REST_API_URL" == YOUR_* ]] || [[ "$KV_REST_API_TOKEN" == YOUR_* ]]; then
  echo "ERROR: Fill in KV_REST_API_URL and KV_REST_API_TOKEN in this file first."
  read -r -p "Press Enter to close."
  exit 1
fi

clear
echo "================================================"
echo "  Purchase Lookup — Toby Jones Software"
echo "================================================"
echo ""
echo "  1) Look up by card last 4 digits"
echo "  2) List ALL purchases"
echo ""
read -r -p "Choose [1/2]: " choice
echo ""

fetch_and_print() {
  local key="$1"
  local label="$2"

  local response
  response=$(curl -s \
    -H "Authorization: Bearer $KV_REST_API_TOKEN" \
    "$KV_REST_API_URL/get/$key")

  local raw
  raw=$(python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    v = r.get('result')
    if v is None or v == 'null':
        print('')
    else:
        # result may be a string (JSON-encoded array) or already a list
        if isinstance(v, str):
            v = json.loads(v)
        for i, rec in enumerate(v, 1):
            print(f\"  [{i}] Product:    {rec.get('product','?')}\")
            print(f\"      Serial Key: {rec.get('key','?')}\")
            print(f\"      Txn ID:     {rec.get('txnId','?')}\")
            print(f\"      Email:      {rec.get('email','?')}\")
            print(f\"      Date:       {rec.get('createdAt','?')}\")
            print()
except Exception as e:
    print(f'Parse error: {e}')
" <<< "$response")

  if [[ -z "$raw" ]]; then
    echo "  (no purchases)"
  else
    if [[ -n "$label" ]]; then
      echo "Card ending in $label:"
      echo "------------------------------------------------"
    fi
    echo "$raw"
  fi
}

if [[ "$choice" == "1" ]]; then
  read -r -p "Enter last 4 digits of card: " last4
  if ! [[ "$last4" =~ ^[0-9]{4}$ ]]; then
    echo "ERROR: Must be exactly 4 digits."
    read -r -p "Press Enter to close."
    exit 1
  fi
  echo ""
  echo "Looking up purchases for card ending in $last4..."
  echo ""
  fetch_and_print "keys:last4:$last4" "$last4"

elif [[ "$choice" == "2" ]]; then
  echo "Fetching all purchase keys..."
  echo ""

  # KEYS command via Upstash REST API
  keys_response=$(curl -s \
    -H "Authorization: Bearer $KV_REST_API_TOKEN" \
    "$KV_REST_API_URL/keys/keys:last4:*")

  all_keys=$(python3 -c "
import sys, json
try:
    r = json.loads(sys.stdin.read())
    keys = r.get('result', [])
    for k in keys:
        print(k)
except:
    pass
" <<< "$keys_response")

  if [[ -z "$all_keys" ]]; then
    echo "No purchases found in KV store."
  else
    count=0
    while IFS= read -r kv_key; do
      [[ -z "$kv_key" ]] && continue
      last4="${kv_key##*:}"
      echo "Card ending in $last4:"
      echo "------------------------------------------------"
      fetch_and_print "$kv_key" ""
      count=$((count + 1))
    done <<< "$all_keys"
    echo "Total cards with purchases: $count"
  fi

else
  echo "Invalid choice."
fi

echo "================================================"
read -r -p "Press Enter to close."
