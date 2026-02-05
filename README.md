# Havilah Constant Product AMM

Welcome to the land of decentralized token swapping, where math does the market making and nobody asks for your KYC.

## What Is This Thing?

This is a constant product AMM built in Cairo for Starknet. If you've ever used Uniswap, you already know the vibe. The formula is simple:

```
x * y = k
```

That's it. That's the whole protocol. Two token reserves multiplied together always equal the same number (well, it grows a bit because fees). When someone wants to swap, the math figures out what they get. No order books. No matching engines. Just pure, beautiful arithmetic.

## What Can You Do Here?

**Swap Stuff**: Got token A but want token B? Throw some A into the pool, get some B out. The price? Whatever the ratio of reserves says it is.

**Provide Liquidity**: Feeling generous? Deposit both tokens and earn a cut of every trade. You get LP shares as proof you're now part-owner of this mathematical money printer.

**Remove Liquidity**: Changed your mind? Burn those LP shares and get your tokens back (plus any fees you earned, minus any impermanent loss you suffered - but that's a story for another README).

## The Math (Don't Skip This)

### Swapping

When you swap `dx` of token X for token Y:

```
dy = (y * dx) / (x + dx)
```

The fee gets taken out of `dx` first. So if the fee is 0.3%, you're really swapping 99.7% of what you sent in. The rest stays in the pool, making `k` slightly bigger and all LP holders slightly richer.

### Adding Liquidity

First person in? You get `sqrt(amount0 * amount1) - 1000` shares. That 1000 is permanently locked to prevent division-by-zero attacks.

Everyone after that gets shares proportional to what they add:
```
shares = min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1)
```

Pro tip: add tokens in the same ratio as the current reserves, or you're basically donating money to existing LPs.

### Removing Liquidity

You get back:
```
amount0 = shares * balance0 / totalSupply
amount1 = shares * balance1 / totalSupply
```

Fair and square. Your percentage of the pool, converted back to actual tokens.

## Getting Started

### You'll Need

- [Scarb](https://docs.swmansion.com/scarb/) >= 2.15.0 (the Cargo of Cairo)
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) >= 0.56.0 (for testing)

### Clone It

```bash
git clone https://github.com/kingfavourjudah/cairo-amm.git
cd cairo-amm
```

### Build It

```bash
scarb build
```

### Test It

```bash
snforge test
```

24 tests. All passing. We checked.

## The Interface

### The Important Functions

| Function | What It Does | What You Get Back |
|----------|--------------|-------------------|
| `swap(token_in, amount_in)` | Trade one token for another | Amount of tokens received |
| `add_liquidity(amount0, amount1)` | Become a liquidity provider | LP shares |
| `remove_liquidity(shares)` | Cash out your position | Tuple of (amount0, amount1) |

### The Read-Only Functions

| Function | What It Tells You |
|----------|-------------------|
| `get_reserves()` | Current token balances in the pool |
| `get_total_supply()` | Total LP shares in existence |
| `get_balance_of(account)` | How many LP shares someone has |
| `get_token0()` | Address of the first token |
| `get_token1()` | Address of the second token |
| `get_fee()` | The fee (3 = 0.3%, 10 = 1%, you get it) |
| `get_amount_out(token_in, amount_in)` | Preview a swap before doing it |
| `get_price()` | Price of token0 in token1 (18 decimal precision) |

### Events (For The Indexers)

| Event | When It Fires |
|-------|---------------|
| `Swap` | Someone traded tokens |
| `LiquidityAdded` | Someone added liquidity |
| `LiquidityRemoved` | Someone removed liquidity |
| `Sync` | Reserves got updated |

## How To Actually Use This

### Step 1: Approve Your Tokens

The AMM needs permission to move your tokens. Standard ERC20 stuff:

```cairo
token0.approve(amm_address, amount);
token1.approve(amm_address, amount);
```

### Step 2: Add Some Liquidity

```cairo
let shares = amm.add_liquidity(amount0, amount1);
```

If you're the first LP, congrats - you set the initial price. Choose wisely.

### Step 3: Swap Away

```cairo
// Check what you'll get first (optional but smart)
let expected_out = amm.get_amount_out(token0_address, swap_amount);

// Do the actual swap
let received = amm.swap(token0_address, swap_amount);
```

### Step 4: Exit When Ready

```cairo
let (amount0, amount1) = amm.remove_liquidity(shares);
```

## Deployment (Sepolia Testnet)

### Prerequisites

- [Starkli](https://github.com/xJonathanLEI/starkli) installed
- A funded Starknet Sepolia account

### Quick Setup

1. **Set up your account** (if you don't have one):

```bash
./scripts/setup_account.sh
```

2. **Fund your account** with Sepolia ETH from the [faucet](https://starknet-faucet.vercel.app/)

3. **Deploy your account**:

```bash
starkli account deploy $STARKNET_ACCOUNT --keystore $STARKNET_KEYSTORE
```

4. **Set environment variables**:

```bash
export STARKNET_ACCOUNT="$HOME/.starkli-wallets/deployer/account.json"
export STARKNET_KEYSTORE="$HOME/.starkli-wallets/deployer/keystore.json"
```

### Deploy Mock Tokens (Optional)

If you need test tokens:

```bash
./scripts/deploy_mock_tokens.sh
```

### Deploy the AMM

```bash
./scripts/deploy.sh <token0_address> <token1_address> [fee]
```

Example with 0.3% fee:

```bash
./scripts/deploy.sh 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d 3
```

The script will output the deployed contract address and save deployment info to `deployments/`.

## Things To Keep In Mind

1. **Impermanent Loss Is Real**: If token prices diverge, you might end up with less value than if you'd just held. That's the game.

2. **Slippage Exists**: Big swaps move the price. The formula doesn't care about your feelings.

3. **First LP Sets The Price**: If you're first in, make sure your ratio matches the real market price, or arbitrageurs will thank you for your donation.

4. **Fees Accumulate**: Every swap makes the pool slightly bigger. LP shares represent a growing pie.

## License

MIT

---

Built with Cairo. Tested with Foundry.
