#!/bin/bash
source .env

MIN_AMOUNT=100000000  # 0.1 SUI in MIST

# Find SUI coin object with sufficient balance (get fresh data)
echo "Finding SUI coin object with balance > $MIN_AMOUNT MIST..."

# Get fresh coin data and find suitable coin
COIN_DATA=$(sui client gas --json 2>/dev/null)
COIN_OBJECT=$(echo "$COIN_DATA" | jq -r --arg min "$MIN_AMOUNT" '.[] | select((.mistBalance | tonumber) > ($min | tonumber)) | .gasCoinId' | head -1)

if [ -z "$COIN_OBJECT" ] || [ "$COIN_OBJECT" = "null" ]; then
    echo "Error: No SUI coin object found with balance > $MIN_AMOUNT MIST"
    echo "Available coins:"
    echo "$COIN_DATA" | jq -r '.[] | "ObjectID: \(.gasCoinId), Balance: \(.mistBalance) MIST"'
    exit 1
fi

COIN_BALANCE=$(echo "$COIN_DATA" | jq -r --arg coin "$COIN_OBJECT" '.[] | select(.gasCoinId == $coin) | .mistBalance')
echo "Using coin object: $COIN_OBJECT (Balance: $COIN_BALANCE MIST)"

TITLE="Hello blockthon2025"
URL="https://jinuahn05.me/"
DESC="This is the best article"
TAGS="[]"  
CATEGORY="Move"
PREVIEW="[]"
AUTHOR="[]" 
DEPOSIT_AMOUNT="$MIN_AMOUNT" # 0.1 SUI

sui client call \
    --package "$CONTENT_PACKAGE" \
    --module articles \
    --function create_external_article \
    --args "$PIPELINE_CONFIG_ID" "$SESSION_REGISTRY_ID" "$CONTENT_CONFIG_ID" "$VALIDATOR_POOL_ID" "$GLOBAL_PARAMETERS_ID" "$EPOCH_REWARD_POOL_ID" "$TITLE" "$URL" "$DESC" "$TAGS" "$CATEGORY" "$PREVIEW" "$AUTHOR" "$COIN_OBJECT" "$DEPOSIT_AMOUNT" "0x6" \
    --gas-budget 100000000