#!/bin/bash

set -e

# Deploy Mock ERC20 Tokens for Testing
# Usage: ./scripts/deploy_mock_tokens.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

RPC_URL="${STARKNET_RPC_URL:-https://starknet-sepolia.public.blastapi.io/rpc/v0_7}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   Mock Token Deployment Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if starkli is installed
if ! command -v starkli &> /dev/null; then
    echo -e "${RED}Error: starkli is not installed${NC}"
    exit 1
fi

# Check environment variables
if [ -z "$STARKNET_ACCOUNT" ] || [ -z "$STARKNET_KEYSTORE" ]; then
    echo -e "${RED}Error: STARKNET_ACCOUNT and STARKNET_KEYSTORE must be set${NC}"
    exit 1
fi

# Build contracts
echo -e "${YELLOW}Building contracts...${NC}"
scarb build

SIERRA_FILE="target/dev/havilah_amm_MockERC20.contract_class.json"

if [ ! -f "$SIERRA_FILE" ]; then
    echo -e "${RED}Error: Sierra file not found${NC}"
    exit 1
fi

# Declare MockERC20
echo ""
echo -e "${YELLOW}Declaring MockERC20...${NC}"
DECLARE_OUTPUT=$(starkli declare "$SIERRA_FILE" \
    --rpc "$RPC_URL" \
    --account "$STARKNET_ACCOUNT" \
    --keystore "$STARKNET_KEYSTORE" \
    2>&1) || true

CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
echo -e "${GREEN}MockERC20 Class Hash: $CLASS_HASH${NC}"

# Deploy Token A
echo ""
echo -e "${YELLOW}Deploying Havilah Token A (HTA)...${NC}"
TOKEN_A_OUTPUT=$(starkli deploy "$CLASS_HASH" \
    "str:Havilah Token A" \
    "str:HTA" \
    "u8:18" \
    --rpc "$RPC_URL" \
    --account "$STARKNET_ACCOUNT" \
    --keystore "$STARKNET_KEYSTORE" \
    2>&1)

TOKEN_A=$(echo "$TOKEN_A_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | tail -1)
echo -e "${GREEN}Token A Address: $TOKEN_A${NC}"

# Deploy Token B
echo ""
echo -e "${YELLOW}Deploying Havilah Token B (HTB)...${NC}"
TOKEN_B_OUTPUT=$(starkli deploy "$CLASS_HASH" \
    "str:Havilah Token B" \
    "str:HTB" \
    "u8:18" \
    --rpc "$RPC_URL" \
    --account "$STARKNET_ACCOUNT" \
    --keystore "$STARKNET_KEYSTORE" \
    2>&1)

TOKEN_B=$(echo "$TOKEN_B_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | tail -1)
echo -e "${GREEN}Token B Address: $TOKEN_B${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Mock Tokens Deployed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Token A (HTA): ${YELLOW}$TOKEN_A${NC}"
echo -e "Token B (HTB): ${YELLOW}$TOKEN_B${NC}"
echo ""
echo -e "To deploy the AMM with these tokens, run:"
echo -e "  ${YELLOW}./scripts/deploy.sh $TOKEN_A $TOKEN_B 3${NC}"
echo ""

# Save deployment info
DEPLOYMENT_FILE="deployments/mock_tokens_$(date +%Y%m%d_%H%M%S).json"
mkdir -p deployments
cat > "$DEPLOYMENT_FILE" << EOF
{
  "network": "sepolia",
  "mock_erc20_class_hash": "$CLASS_HASH",
  "token_a": {
    "address": "$TOKEN_A",
    "name": "Havilah Token A",
    "symbol": "HTA",
    "decimals": 18
  },
  "token_b": {
    "address": "$TOKEN_B",
    "name": "Havilah Token B",
    "symbol": "HTB",
    "decimals": 18
  },
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo -e "Deployment info saved to: ${GREEN}$DEPLOYMENT_FILE${NC}"
