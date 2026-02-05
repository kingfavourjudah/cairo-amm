#!/bin/bash

set -e

# Havilah AMM Deployment Script for Starknet Sepolia Testnet
# Usage: ./scripts/deploy.sh <token0_address> <token1_address> [fee]

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_FEE=3  # 0.3%
RPC_URL="${STARKNET_RPC_URL:-https://starknet-sepolia.public.blastapi.io/rpc/v0_7}"

# Check arguments
if [ "$#" -lt 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: ./scripts/deploy.sh <token0_address> <token1_address> [fee]"
    echo ""
    echo "Arguments:"
    echo "  token0_address  - Address of the first token"
    echo "  token1_address  - Address of the second token"
    echo "  fee             - Fee in basis points (default: 3 = 0.3%)"
    echo ""
    echo "Environment variables:"
    echo "  STARKNET_RPC_URL     - RPC endpoint (default: Sepolia public RPC)"
    echo "  STARKNET_ACCOUNT     - Path to account file"
    echo "  STARKNET_KEYSTORE    - Path to keystore file"
    exit 1
fi

TOKEN0=$1
TOKEN1=$2
FEE=${3:-$DEFAULT_FEE}

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   Havilah AMM Deployment Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if starkli is installed
if ! command -v starkli &> /dev/null; then
    echo -e "${RED}Error: starkli is not installed${NC}"
    echo "Install it with: curl https://get.starkli.sh | sh"
    exit 1
fi

# Check if account is configured
if [ -z "$STARKNET_ACCOUNT" ]; then
    echo -e "${RED}Error: STARKNET_ACCOUNT environment variable not set${NC}"
    echo "Set it to the path of your account file"
    exit 1
fi

if [ -z "$STARKNET_KEYSTORE" ]; then
    echo -e "${RED}Error: STARKNET_KEYSTORE environment variable not set${NC}"
    echo "Set it to the path of your keystore file"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  RPC URL: $RPC_URL"
echo "  Token0:  $TOKEN0"
echo "  Token1:  $TOKEN1"
echo "  Fee:     $FEE ($(echo "scale=1; $FEE / 10" | bc)%)"
echo ""

# Build the contract
echo -e "${YELLOW}Building contracts...${NC}"
scarb build

# Get the Sierra file path
SIERRA_FILE="target/dev/havilah_amm_HavilahAmm.contract_class.json"

if [ ! -f "$SIERRA_FILE" ]; then
    echo -e "${RED}Error: Sierra file not found at $SIERRA_FILE${NC}"
    echo "Make sure the contract compiled successfully"
    exit 1
fi

# Declare the contract
echo ""
echo -e "${YELLOW}Declaring contract...${NC}"
DECLARE_OUTPUT=$(starkli declare "$SIERRA_FILE" \
    --rpc "$RPC_URL" \
    --account "$STARKNET_ACCOUNT" \
    --keystore "$STARKNET_KEYSTORE" \
    2>&1)

# Extract class hash from output
CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)

if [ -z "$CLASS_HASH" ]; then
    # Check if already declared
    if echo "$DECLARE_OUTPUT" | grep -q "already declared"; then
        CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
        echo -e "${YELLOW}Contract already declared${NC}"
    else
        echo -e "${RED}Error declaring contract:${NC}"
        echo "$DECLARE_OUTPUT"
        exit 1
    fi
fi

echo -e "${GREEN}Class hash: $CLASS_HASH${NC}"

# Deploy the contract
echo ""
echo -e "${YELLOW}Deploying contract...${NC}"
DEPLOY_OUTPUT=$(starkli deploy "$CLASS_HASH" \
    "$TOKEN0" \
    "$TOKEN1" \
    "u16:$FEE" \
    --rpc "$RPC_URL" \
    --account "$STARKNET_ACCOUNT" \
    --keystore "$STARKNET_KEYSTORE" \
    2>&1)

# Extract contract address from output
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | tail -1)

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo -e "${RED}Error deploying contract:${NC}"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deployment Successful${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Class Hash:       ${YELLOW}$CLASS_HASH${NC}"
echo -e "Contract Address: ${YELLOW}$CONTRACT_ADDRESS${NC}"
echo ""
echo -e "View on Voyager:"
echo -e "  https://sepolia.voyager.online/contract/$CONTRACT_ADDRESS"
echo ""

# Save deployment info
DEPLOYMENT_FILE="deployments/sepolia_$(date +%Y%m%d_%H%M%S).json"
mkdir -p deployments
cat > "$DEPLOYMENT_FILE" << EOF
{
  "network": "sepolia",
  "class_hash": "$CLASS_HASH",
  "contract_address": "$CONTRACT_ADDRESS",
  "token0": "$TOKEN0",
  "token1": "$TOKEN1",
  "fee": $FEE,
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo -e "Deployment info saved to: ${GREEN}$DEPLOYMENT_FILE${NC}"
