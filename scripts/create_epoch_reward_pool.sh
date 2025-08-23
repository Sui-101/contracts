#!/bin/bash
source .env

sui client call \
    --package "$CONTENT_PACKAGE" \
    --module epoch_rewards \
    --function create_epoch_reward_pool \
    --args "$CONTENT_CONFIG_ID" "$REWARD_DISTRIBUTOR_ID" "0x1" "0x1" "0x1" "0x1" "0x1" "0x1" "0x6" \
    --gas-budget 100000000

# 0xc3bc5344dcfc510d18821a07a39b94aff2bfb46dc1df423cf7219c0b7c50308b