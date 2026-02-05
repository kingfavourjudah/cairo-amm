#!/bin/bash

set -e

# Account Setup Script for Starknet Sepolia
# This script helps create a new account for testnet deployment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ACCOUNT_DIR="$HOME/.starkli-wallets/deployer"
KEYSTORE_FILE="$ACCOUNT_DIR/keystore.json"
ACCOUNT_FILE="$ACCOUNT_DIR/account.json"
RPC_URL="${STARKNET_RPC_URL:-https://starknet-sepolia.public.blastapi.io/rpc/v0_7}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   Starknet Account Setup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check if starkli is installed
if ! command -v starkli &> /dev/null; then
    echo -e "${RED}Error: starkli is not installed${NC}"
    echo "Install it with: curl https://get.starkli.sh | sh"
    exit 1
fi

# Create directory
mkdir -p "$ACCOUNT_DIR"

# Check if keystore already exists
if [ -f "$KEYSTORE_FILE" ]; then
    echo -e "${YELLOW}Keystore already exists at $KEYSTORE_FILE${NC}"
    echo "Delete it first if you want to create a new one"
else
    echo -e "${YELLOW}Creating new keystore...${NC}"
    echo "You will be prompted to enter a password to encrypt your private key"
    echo ""
    starkli signer keystore new "$KEYSTORE_FILE"
    echo ""
    echo -e "${GREEN}Keystore created at: $KEYSTORE_FILE${NC}"
fi

# Get the public key
echo ""
echo -e "${YELLOW}Fetching public key...${NC}"
PUBLIC_KEY=$(starkli signer keystore inspect "$KEYSTORE_FILE" 2>&1 | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
echo -e "Public key: ${GREEN}$PUBLIC_KEY${NC}"

# Check if account file exists
if [ -f "$ACCOUNT_FILE" ]; then
    echo ""
    echo -e "${YELLOW}Account file already exists at $ACCOUNT_FILE${NC}"
    ACCOUNT_ADDRESS=$(cat "$ACCOUNT_FILE" | grep -oE '"address":\s*"0x[a-fA-F0-9]+"' | grep -oE '0x[a-fA-F0-9]+')
    echo -e "Account address: ${GREEN}$ACCOUNT_ADDRESS${NC}"
else
    echo ""
    echo -e "${YELLOW}Initializing OpenZeppelin account...${NC}"
    starkli account oz init "$ACCOUNT_FILE" --keystore "$KEYSTORE_FILE"

    ACCOUNT_ADDRESS=$(cat "$ACCOUNT_FILE" | grep -oE '"address":\s*"0x[a-fA-F0-9]+"' | grep -oE '0x[a-fA-F0-9]+')
    echo ""
    echo -e "${GREEN}Account initialized${NC}"
    echo -e "Account address: ${YELLOW}$ACCOUNT_ADDRESS${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Setup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Fund your account with Sepolia ETH:"
echo -e "   ${YELLOW}https://starknet-faucet.vercel.app/${NC}"
echo -e "   Account: ${YELLOW}$ACCOUNT_ADDRESS${NC}"
echo ""
echo "2. Deploy your account (after funding):"
echo -e "   ${YELLOW}starkli account deploy $ACCOUNT_FILE --keystore $KEYSTORE_FILE --rpc $RPC_URL${NC}"
echo ""
echo "3. Set environment variables:"
echo -e "   ${YELLOW}export STARKNET_ACCOUNT=$ACCOUNT_FILE${NC}"
echo -e "   ${YELLOW}export STARKNET_KEYSTORE=$KEYSTORE_FILE${NC}"
echo ""
echo "4. Add to your shell profile (~/.bashrc or ~/.zshrc):"
cat << EOF

# Starknet deployment config
export STARKNET_ACCOUNT="$ACCOUNT_FILE"
export STARKNET_KEYSTORE="$KEYSTORE_FILE"
export STARKNET_RPC_URL="$RPC_URL"

EOF
