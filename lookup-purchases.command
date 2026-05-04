#!/bin/bash
# Vercel KV purchase lookup via REST API
# No setup needed — uses the public Vercel KV REST API endpoint

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

  # Call the verify-card endpoint to look up by last4
  response=$(curl -s -X POST "https://tobyjones1512.github.io/api/verify-card" \
    -H "Content-Type: application/json" \
    -d "{\"opaqueData\": {\"dataValue\": \"test\", \"dataDescriptor\": \"test\"}}")

  echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"

elif [[ "$choice" == "2" ]]; then
  echo "Note: List all purchases requires direct KV access (admin only)."
  echo "Use the lookup-purchases.command with KV credentials instead."

else
  echo "Invalid choice."
fi

echo ""
echo "================================================"
read -r -p "Press Enter to close."
