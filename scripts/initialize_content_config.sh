#!/bin/bash
source .env

sui client call \
    --package "$CONTENT_PACKAGE" \
    --module config \
    --function initialize_content_config \
    --args "$CONFIG_ADMIN_CAP_ID" "$GLOBAL_PARAMETERS_ID" "0x6" \
    --gas-budget 100000000