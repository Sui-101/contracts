#!/bin/bash

source .env
# Configure Registry with External Objects Script
# This script configures the PackageRegistry with Treasury and GlobalParameters objects

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

# Treasury and GlobalParameters object IDs (these should be set in .env or passed as arguments)
if [ -z "$TREASURY_OBJECT_ID" ]; then
    echo "Error: TREASURY_OBJECT_ID environment variable is not set"
    echo "Please set TREASURY_OBJECT_ID in .env or export it"
    exit 1
fi

if [ -z "$GLOBAL_PARAMETERS_OBJECT_ID" ]; then
    echo "Error: GLOBAL_PARAMETERS_OBJECT_ID environment variable is not set"
    echo "Please set GLOBAL_PARAMETERS_OBJECT_ID in .env or export it"
    exit 1
fi

if [ -z "$CORE_REGISTRY_CAP" ]; then
    echo "Error: CORE_REGISTRY_CAP environment variable is not set"
    echo "Please set CORE_REGISTRY_CAP in .env or export it"
    exit 1
fi

# Get active address
ACTIVE_ADDRESS=$(sui client active-address 2>/dev/null)
echo "Using active address: $ACTIVE_ADDRESS"

echo "Configuration Details:"
echo "======================"
echo "Package: $CORE_PACKAGE"
echo "Registry: $CORE_PACKAGE_REGISTRY"
echo "Treasury Object: $TREASURY_OBJECT_ID"
echo "GlobalParameters Object: $GLOBAL_PARAMETERS_OBJECT_ID"
echo "Registry Admin Cap: $CORE_REGISTRY_CAP"
echo ""

# Check if registry is already configured
echo "Checking current registry status..."
REGISTRY_STATUS=$(sui client call \
    --package "$CORE_PACKAGE" \
    --module governance \
    --function get_registry_status \
    --args "$CORE_PACKAGE_REGISTRY" \
    --gas-budget 10000000 \
    --json 2>/dev/null | jq -r '.effects.status.status')

if [ "$REGISTRY_STATUS" != "success" ]; then
    echo "Warning: Unable to check registry status"
fi

# Verify objects exist
echo "Verifying Treasury object exists..."
if ! sui client object "$TREASURY_OBJECT_ID" &>/dev/null; then
    echo "Error: Treasury object $TREASURY_OBJECT_ID does not exist or is not accessible"
    exit 1
fi

echo "Verifying GlobalParameters object exists..."
if ! sui client object "$GLOBAL_PARAMETERS_OBJECT_ID" &>/dev/null; then
    echo "Error: GlobalParameters object $GLOBAL_PARAMETERS_OBJECT_ID does not exist or is not accessible"
    exit 1
fi

echo "Verifying Registry Admin Cap exists..."
if ! sui client object "$CORE_REGISTRY_CAP" &>/dev/null; then
    echo "Error: Registry Admin Cap $CORE_REGISTRY_CAP does not exist or is not accessible"
    exit 1
fi

echo ""
echo "Configuring registry with external objects..."
echo "=============================================="

# Call the configure_registry_with_shared_global_parameters function
sui client call \
    --package "$CORE_PACKAGE" \
    --module governance \
    --function configure_registry_with_shared_global_parameters \
    --args "$CORE_PACKAGE_REGISTRY" "$TREASURY_OBJECT_ID" "$GLOBAL_PARAMETERS_OBJECT_ID" "$CORE_REGISTRY_CAP" "0x6" \
    --gas-budget 200000000

echo ""
echo "✅ Registry configuration completed!"
echo ""

# Verify configuration was successful
echo "Verifying configuration..."
FINAL_STATUS=$(sui client call \
    --package "$CORE_PACKAGE" \
    --module governance \
    --function is_registry_configured \
    --args "$CORE_PACKAGE_REGISTRY" \
    --gas-budget 10000000 \
    --json 2>/dev/null)

if [ $? -eq 0 ]; then
    IS_CONFIGURED=$(echo "$FINAL_STATUS" | jq -r '.effects.created[0].reference.objectId' 2>/dev/null || echo "unknown")
    if [ "$IS_CONFIGURED" != "unknown" ] && [ "$IS_CONFIGURED" != "null" ]; then
        echo "✅ Registry is now configured successfully!"
    else
        echo "⚠️  Registry configuration status unclear - please check manually"
    fi
else
    echo "⚠️  Unable to verify configuration status"
fi

echo ""
echo "Configuration complete. The registry should now be ready for use."
echo "Error 999 (E_PACKAGE_NOT_CONFIGURED) should no longer occur."