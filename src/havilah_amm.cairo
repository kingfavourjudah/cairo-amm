use starknet::ContractAddress;

/// Havilah Constant Product AMM Interface
///
/// A simple AMM implementing the constant product formula (x * y = k)
/// for decentralized token swaps and liquidity provision.
#[starknet::interface]
pub trait IHavilahAmm<TContractState> {
    /// Swap one token for another
    /// Returns the amount of tokens received
    fn swap(ref self: TContractState, token_in: ContractAddress, amount_in: u256) -> u256;

    /// Add liquidity to the pool
    /// Returns the number of LP shares minted
    fn add_liquidity(ref self: TContractState, amount0: u256, amount1: u256) -> u256;

    /// Remove liquidity from the pool
    /// Returns the amounts of both tokens withdrawn
    fn remove_liquidity(ref self: TContractState, shares: u256) -> (u256, u256);

    // View functions
    fn get_reserves(self: @TContractState) -> (u256, u256);
    fn get_total_supply(self: @TContractState) -> u256;
    fn get_balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn get_token0(self: @TContractState) -> ContractAddress;
    fn get_token1(self: @TContractState) -> ContractAddress;
    fn get_fee(self: @TContractState) -> u16;

    /// Calculate expected output amount for a swap (useful for UI)
    fn get_amount_out(
        self: @TContractState, token_in: ContractAddress, amount_in: u256
    ) -> u256;

    /// Calculate the price of token0 in terms of token1
    fn get_price(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod HavilahAmm {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use core::num::traits::{Sqrt, Zero};

    // Precision for price calculations (18 decimals)
    const PRICE_PRECISION: u256 = 1_000_000_000_000_000_000;
    // Fee denominator (1000 = 100%)
    const FEE_DENOMINATOR: u256 = 1000;
    // Minimum liquidity to prevent division by zero attacks
    const MINIMUM_LIQUIDITY: u256 = 1000;

    #[storage]
    struct Storage {
        token0: IERC20Dispatcher,
        token1: IERC20Dispatcher,
        reserve0: u256,
        reserve1: u256,
        total_supply: u256,
        balance_of: Map::<ContractAddress, u256>,
        /// Fee in basis points (0-1000, where 1000 = 100%)
        /// E.g., 3 = 0.3%
        fee: u16,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Swap: Swap,
        LiquidityAdded: LiquidityAdded,
        LiquidityRemoved: LiquidityRemoved,
        Sync: Sync,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Swap {
        #[key]
        pub sender: ContractAddress,
        pub token_in: ContractAddress,
        pub amount_in: u256,
        pub amount_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityAdded {
        #[key]
        pub provider: ContractAddress,
        pub amount0: u256,
        pub amount1: u256,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityRemoved {
        #[key]
        pub provider: ContractAddress,
        pub amount0: u256,
        pub amount1: u256,
        pub shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Sync {
        pub reserve0: u256,
        pub reserve1: u256,
    }

    pub mod Errors {
        pub const INVALID_TOKEN: felt252 = 'HAVILAH: invalid token';
        pub const ZERO_AMOUNT: felt252 = 'HAVILAH: amount = 0';
        pub const ZERO_SHARES: felt252 = 'HAVILAH: shares = 0';
        pub const INVALID_RATIO: felt252 = 'HAVILAH: x/y != dx/dy';
        pub const FEE_TOO_HIGH: felt252 = 'HAVILAH: fee > 1000';
        pub const INSUFFICIENT_OUTPUT: felt252 = 'HAVILAH: insufficient output';
        pub const IDENTICAL_TOKENS: felt252 = 'HAVILAH: identical tokens';
        pub const ZERO_ADDRESS: felt252 = 'HAVILAH: zero address';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, token0: ContractAddress, token1: ContractAddress, fee: u16,
    ) {
        // Validate inputs
        assert(fee <= 1000, Errors::FEE_TOO_HIGH);
        assert(!token0.is_zero(), Errors::ZERO_ADDRESS);
        assert(!token1.is_zero(), Errors::ZERO_ADDRESS);
        assert(token0 != token1, Errors::IDENTICAL_TOKENS);

        self.token0.write(IERC20Dispatcher { contract_address: token0 });
        self.token1.write(IERC20Dispatcher { contract_address: token1 });
        self.fee.write(fee);
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn _mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.balance_of.write(to, self.balance_of.read(to) + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }

        fn _burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            let balance = self.balance_of.read(from);
            assert(balance >= amount, 'HAVILAH: insufficient balance');
            self.balance_of.write(from, balance - amount);
            self.total_supply.write(self.total_supply.read() - amount);
        }

        fn _update(ref self: ContractState, reserve0: u256, reserve1: u256) {
            self.reserve0.write(reserve0);
            self.reserve1.write(reserve1);
            self.emit(Sync { reserve0, reserve1 });
        }

        #[inline(always)]
        fn _select_token(self: @ContractState, token: ContractAddress) -> bool {
            let is_token0 = token == self.token0.read().contract_address;
            let is_token1 = token == self.token1.read().contract_address;
            assert(is_token0 || is_token1, Errors::INVALID_TOKEN);
            is_token0
        }

        #[inline(always)]
        fn _min(x: u256, y: u256) -> u256 {
            if x <= y { x } else { y }
        }

        fn _calculate_amount_out(
            self: @ContractState, amount_in: u256, reserve_in: u256, reserve_out: u256
        ) -> u256 {
            let fee: u256 = self.fee.read().into();
            let amount_in_with_fee = amount_in * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
            (reserve_out * amount_in_with_fee) / (reserve_in + amount_in_with_fee)
        }
    }

    #[abi(embed_v0)]
    impl HavilahAmm of super::IHavilahAmm<ContractState> {
        fn swap(ref self: ContractState, token_in: ContractAddress, amount_in: u256) -> u256 {
            assert(amount_in > 0, Errors::ZERO_AMOUNT);
            let is_token0 = self._select_token(token_in);

            let (token0, token1) = (self.token0.read(), self.token1.read());
            let (reserve0, reserve1) = (self.reserve0.read(), self.reserve1.read());

            let (token_in_dispatcher, token_out_dispatcher, reserve_in, reserve_out) = if is_token0 {
                (token0, token1, reserve0, reserve1)
            } else {
                (token1, token0, reserve1, reserve0)
            };

            let caller = get_caller_address();
            let this = get_contract_address();

            // Transfer tokens in
            token_in_dispatcher.transfer_from(caller, this, amount_in);

            // Calculate output using constant product formula:
            // xy = k
            // (x + dx)(y - dy) = k
            // dy = ydx / (x + dx)
            let amount_out = self._calculate_amount_out(amount_in, reserve_in, reserve_out);
            assert(amount_out > 0, Errors::INSUFFICIENT_OUTPUT);

            // Transfer tokens out
            token_out_dispatcher.transfer(caller, amount_out);

            // Update reserves based on actual balances
            self._update(token0.balance_of(this), token1.balance_of(this));

            // Emit event
            self.emit(Swap {
                sender: caller,
                token_in,
                amount_in,
                amount_out
            });

            amount_out
        }

        fn add_liquidity(ref self: ContractState, amount0: u256, amount1: u256) -> u256 {
            assert(amount0 > 0 && amount1 > 0, Errors::ZERO_AMOUNT);

            let caller = get_caller_address();
            let this = get_contract_address();
            let (token0, token1) = (self.token0.read(), self.token1.read());

            // Transfer tokens to the contract
            token0.transfer_from(caller, this, amount0);
            token1.transfer_from(caller, this, amount1);

            // Enforce ratio: x/y = dx/dy (no price impact on add)
            let (reserve0, reserve1) = (self.reserve0.read(), self.reserve1.read());
            if reserve0 > 0 || reserve1 > 0 {
                assert(reserve0 * amount1 == reserve1 * amount0, Errors::INVALID_RATIO);
            }

            // Calculate shares to mint
            // Using sqrt(xy) as the value function
            let total_supply = self.total_supply.read();
            let shares = if total_supply == 0 {
                // First liquidity provider - mint sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
                let liquidity: u256 = (amount0 * amount1).sqrt().into();
                assert(liquidity > MINIMUM_LIQUIDITY, Errors::ZERO_SHARES);
                // Lock minimum liquidity forever to prevent division by zero
                liquidity - MINIMUM_LIQUIDITY
            } else {
                // Subsequent providers - mint proportionally
                PrivateFunctions::_min(
                    amount0 * total_supply / reserve0,
                    amount1 * total_supply / reserve1,
                )
            };

            assert(shares > 0, Errors::ZERO_SHARES);
            self._mint(caller, shares);

            // Update reserves
            self._update(token0.balance_of(this), token1.balance_of(this));

            // Emit event
            self.emit(LiquidityAdded {
                provider: caller,
                amount0,
                amount1,
                shares,
            });

            shares
        }

        fn remove_liquidity(ref self: ContractState, shares: u256) -> (u256, u256) {
            assert(shares > 0, Errors::ZERO_SHARES);

            let caller = get_caller_address();
            let this = get_contract_address();
            let (token0, token1) = (self.token0.read(), self.token1.read());

            // Calculate token amounts: amount = shares/totalSupply * balance
            let (bal0, bal1) = (token0.balance_of(this), token1.balance_of(this));
            let total_supply = self.total_supply.read();

            let amount0 = (shares * bal0) / total_supply;
            let amount1 = (shares * bal1) / total_supply;
            assert(amount0 > 0 && amount1 > 0, Errors::ZERO_AMOUNT);

            // Burn shares first (reentrancy protection)
            self._burn(caller, shares);

            // Update reserves
            self._update(bal0 - amount0, bal1 - amount1);

            // Transfer tokens
            token0.transfer(caller, amount0);
            token1.transfer(caller, amount1);

            // Emit event
            self.emit(LiquidityRemoved {
                provider: caller,
                amount0,
                amount1,
                shares,
            });

            (amount0, amount1)
        }

        // View functions
        fn get_reserves(self: @ContractState) -> (u256, u256) {
            (self.reserve0.read(), self.reserve1.read())
        }

        fn get_total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn get_balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of.read(account)
        }

        fn get_token0(self: @ContractState) -> ContractAddress {
            self.token0.read().contract_address
        }

        fn get_token1(self: @ContractState) -> ContractAddress {
            self.token1.read().contract_address
        }

        fn get_fee(self: @ContractState) -> u16 {
            self.fee.read()
        }

        fn get_amount_out(
            self: @ContractState, token_in: ContractAddress, amount_in: u256
        ) -> u256 {
            if amount_in == 0 {
                return 0;
            }

            let is_token0 = self._select_token(token_in);
            let (reserve0, reserve1) = (self.reserve0.read(), self.reserve1.read());

            let (reserve_in, reserve_out) = if is_token0 {
                (reserve0, reserve1)
            } else {
                (reserve1, reserve0)
            };

            self._calculate_amount_out(amount_in, reserve_in, reserve_out)
        }

        fn get_price(self: @ContractState) -> u256 {
            let reserve0 = self.reserve0.read();
            let reserve1 = self.reserve1.read();

            if reserve0 == 0 {
                return 0;
            }

            // Price of token0 in terms of token1 with 18 decimal precision
            (reserve1 * PRICE_PRECISION) / reserve0
        }
    }
}
