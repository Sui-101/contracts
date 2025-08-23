#!/bin/bash

source .env
# Simple SUI Genesis Validator Registration Script

set -e  # Exit on any error

# Check required environment variables
if [ -z "$CORE_PACKAGE" ]; then
    echo "Error: CORE_PACKAGE environment variable is not set"
    exit 1
fi

if [ -z "$CORE_PACKAGE_REGISTRY" ]; then
    echo "Error: CORE_PACKAGE_REGISTRY environment variable is not set"
    exit 1
fi

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

# Verify the coin object exists before proceeding
echo "Verifying coin object exists..."
if ! sui client object "$COIN_OBJECT" &>/dev/null; then
    echo "Error: Coin object $COIN_OBJECT does not exist or is not accessible"
    echo "Refreshing coin list..."
    sui client gas --json 2>/dev/null | jq -r '.[] | "ObjectID: \(.gasCoinId), Balance: \(.mistBalance) MIST"'
    exit 1
fi

# Get active address (this was the missing validator address)
ACTIVE_ADDRESS=$(sui client active-address 2>/dev/null)
echo "Using active address as validator: $ACTIVE_ADDRESS"

# Register genesis validator - correct argument order: registry, validator, amount, coin_object
echo "Registering genesis validator..."
echo "Package: $CORE_PACKAGE"
echo "Governance config id: $GOVERNANCE_CONFIG_ID" 
echo "Validator Pool id: $VALIDATOR_POOL_ID"
echo "Treasury id: $TREASURY_ID"

echo "Validator: $ACTIVE_ADDRESS"
echo "Amount: $MIN_AMOUNT"
echo "Coin Object: $COIN_OBJECT"

sui client call \
    --package "$CORE_PACKAGE" \
    --module governance \
    --function register_genesis_validator \
    --args "$GOVERNANCE_CONFIG_ID" "$VALIDATOR_POOL_ID" "$TREASURY_ID" "$MIN_AMOUNT" "$COIN_OBJECT" "0x6" \
    --gas-budget 100000000

echo "✅ Genesis validator registration completed!"
