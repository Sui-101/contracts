#!/bin/bash
source .env

sui client call \
    --package "$CORE_PACKAGE" \
    --module governance \
    --function initialize_governance \
    --args "$GOVERNANCE_CONFIG_ID" "$GOVERNANCE_ADMIN_CAP_ID" "0x6" \
    --gas-budget 100000000