use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

use havilah_amm::havilah_amm::{IHavilahAmmDispatcher, IHavilahAmmDispatcherTrait};
use havilah_amm::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

const INITIAL_MINT: u256 = 1_000_000_000_000_000_000_000_000; // 1M tokens with 18 decimals
const LIQUIDITY_AMOUNT: u256 = 100_000_000_000_000_000_000_000; // 100K tokens
const SWAP_AMOUNT: u256 = 1_000_000_000_000_000_000_000; // 1K tokens
const FEE: u16 = 3; // 0.3% fee

fn USER1() -> ContractAddress {
    'USER1'.try_into().unwrap()
}

fn USER2() -> ContractAddress {
    'USER2'.try_into().unwrap()
}

fn setup() -> (IHavilahAmmDispatcher, IMockERC20Dispatcher, IMockERC20Dispatcher) {
    // Deploy mock tokens
    let token_class = declare("MockERC20").unwrap().contract_class();

    let mut token0_calldata: Array<felt252> = array![];
    let name0: ByteArray = "Havilah Token A";
    let symbol0: ByteArray = "HTA";
    name0.serialize(ref token0_calldata);
    symbol0.serialize(ref token0_calldata);
    18_u8.serialize(ref token0_calldata);
    let (token0_address, _) = token_class.deploy(@token0_calldata).unwrap();

    let mut token1_calldata: Array<felt252> = array![];
    let name1: ByteArray = "Havilah Token B";
    let symbol1: ByteArray = "HTB";
    name1.serialize(ref token1_calldata);
    symbol1.serialize(ref token1_calldata);
    18_u8.serialize(ref token1_calldata);
    let (token1_address, _) = token_class.deploy(@token1_calldata).unwrap();

    // Deploy AMM
    let amm_class = declare("HavilahAmm").unwrap().contract_class();
    let mut amm_calldata: Array<felt252> = array![];
    token0_address.serialize(ref amm_calldata);
    token1_address.serialize(ref amm_calldata);
    FEE.serialize(ref amm_calldata);
    let (amm_address, _) = amm_class.deploy(@amm_calldata).unwrap();

    let amm = IHavilahAmmDispatcher { contract_address: amm_address };
    let token0 = IMockERC20Dispatcher { contract_address: token0_address };
    let token1 = IMockERC20Dispatcher { contract_address: token1_address };

    // Mint tokens to users
    token0.mint(USER1(), INITIAL_MINT);
    token1.mint(USER1(), INITIAL_MINT);
    token0.mint(USER2(), INITIAL_MINT);
    token1.mint(USER2(), INITIAL_MINT);

    // Approve AMM to spend tokens
    start_cheat_caller_address(token0_address, USER1());
    token0.approve(amm_address, INITIAL_MINT);
    stop_cheat_caller_address(token0_address);

    start_cheat_caller_address(token1_address, USER1());
    token1.approve(amm_address, INITIAL_MINT);
    stop_cheat_caller_address(token1_address);

    start_cheat_caller_address(token0_address, USER2());
    token0.approve(amm_address, INITIAL_MINT);
    stop_cheat_caller_address(token0_address);

    start_cheat_caller_address(token1_address, USER2());
    token1.approve(amm_address, INITIAL_MINT);
    stop_cheat_caller_address(token1_address);

    (amm, token0, token1)
}

fn add_initial_liquidity(
    amm: IHavilahAmmDispatcher
) {
    start_cheat_caller_address(amm.contract_address, USER1());
    amm.add_liquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);
}

// ============ Constructor Tests ============

#[test]
fn test_constructor_sets_tokens() {
    let (amm, token0, token1) = setup();

    assert(amm.get_token0() == token0.contract_address, 'wrong token0');
    assert(amm.get_token1() == token1.contract_address, 'wrong token1');
}

#[test]
fn test_constructor_sets_fee() {
    let (amm, _, _) = setup();

    assert(amm.get_fee() == FEE, 'wrong fee');
}

#[test]
fn test_initial_reserves_are_zero() {
    let (amm, _, _) = setup();

    let (reserve0, reserve1) = amm.get_reserves();
    assert(reserve0 == 0, 'reserve0 not 0');
    assert(reserve1 == 0, 'reserve1 not 0');
}

#[test]
fn test_initial_total_supply_is_zero() {
    let (amm, _, _) = setup();

    assert(amm.get_total_supply() == 0, 'total supply not 0');
}

// ============ Add Liquidity Tests ============

#[test]
fn test_add_liquidity_first_provider() {
    let (amm, token0, token1) = setup();

    let balance0_before = token0.balance_of(USER1());
    let balance1_before = token1.balance_of(USER1());

    start_cheat_caller_address(amm.contract_address, USER1());
    let shares = amm.add_liquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);

    // Check shares minted (sqrt(100K * 100K) - 1000 minimum liquidity)
    let expected_shares: u256 = LIQUIDITY_AMOUNT - 1000;
    assert(shares == expected_shares, 'wrong shares minted');

    // Check reserves updated
    let (reserve0, reserve1) = amm.get_reserves();
    assert(reserve0 == LIQUIDITY_AMOUNT, 'wrong reserve0');
    assert(reserve1 == LIQUIDITY_AMOUNT, 'wrong reserve1');

    // Check token balances
    assert(token0.balance_of(USER1()) == balance0_before - LIQUIDITY_AMOUNT, 'wrong token0 balance');
    assert(token1.balance_of(USER1()) == balance1_before - LIQUIDITY_AMOUNT, 'wrong token1 balance');

    // Check LP balance
    assert(amm.get_balance_of(USER1()) == shares, 'wrong LP balance');
}

#[test]
fn test_add_liquidity_second_provider() {
    let (amm, _, _) = setup();

    // First provider adds liquidity
    add_initial_liquidity(amm);

    let total_supply_before = amm.get_total_supply();

    // Second provider adds equal liquidity
    let add_amount: u256 = 50_000_000_000_000_000_000_000; // 50K tokens

    start_cheat_caller_address(amm.contract_address, USER2());
    let shares = amm.add_liquidity(add_amount, add_amount);
    stop_cheat_caller_address(amm.contract_address);

    // Shares should be proportional
    let expected_shares = add_amount * total_supply_before / LIQUIDITY_AMOUNT;
    assert(shares == expected_shares, 'wrong proportional shares');

    // Check reserves
    let (reserve0, reserve1) = amm.get_reserves();
    assert(reserve0 == LIQUIDITY_AMOUNT + add_amount, 'wrong reserve0');
    assert(reserve1 == LIQUIDITY_AMOUNT + add_amount, 'wrong reserve1');
}

#[test]
#[should_panic(expected: 'HAVILAH: x/y != dx/dy')]
fn test_add_liquidity_wrong_ratio_reverts() {
    let (amm, _, _) = setup();

    // First provider adds liquidity
    add_initial_liquidity(amm);

    // Second provider tries to add with wrong ratio
    start_cheat_caller_address(amm.contract_address, USER2());
    amm.add_liquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT / 2); // Wrong ratio
    stop_cheat_caller_address(amm.contract_address);
}

#[test]
#[should_panic(expected: 'HAVILAH: amount = 0')]
fn test_add_liquidity_zero_amount_reverts() {
    let (amm, _, _) = setup();

    start_cheat_caller_address(amm.contract_address, USER1());
    amm.add_liquidity(0, LIQUIDITY_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);
}

// ============ Swap Tests ============

#[test]
fn test_swap_token0_for_token1() {
    let (amm, token0, token1) = setup();
    add_initial_liquidity(amm);

    let balance0_before = token0.balance_of(USER2());
    let balance1_before = token1.balance_of(USER2());

    start_cheat_caller_address(amm.contract_address, USER2());
    let amount_out = amm.swap(token0.contract_address, SWAP_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);

    // Verify output is less than input (due to fee and price impact)
    assert(amount_out > 0, 'no output');
    assert(amount_out < SWAP_AMOUNT, 'output too high');

    // Check balances
    assert(token0.balance_of(USER2()) == balance0_before - SWAP_AMOUNT, 'wrong token0 balance');
    assert(token1.balance_of(USER2()) == balance1_before + amount_out, 'wrong token1 balance');

    // Verify constant product is maintained or increased
    let (reserve0, reserve1) = amm.get_reserves();
    let k_after = reserve0 * reserve1;
    let k_before = LIQUIDITY_AMOUNT * LIQUIDITY_AMOUNT;
    assert(k_after >= k_before, 'k decreased');
}

#[test]
fn test_swap_token1_for_token0() {
    let (amm, token0, token1) = setup();
    add_initial_liquidity(amm);

    start_cheat_caller_address(amm.contract_address, USER2());
    let amount_out = amm.swap(token1.contract_address, SWAP_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);

    // Verify output
    assert(amount_out > 0, 'no output');

    // Check that user received token0
    assert(
        token0.balance_of(USER2()) == INITIAL_MINT + amount_out,
        'wrong token0 balance after swap'
    );
}

#[test]
fn test_swap_with_fee() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    // Get expected output
    let expected_out = amm.get_amount_out(token0.contract_address, SWAP_AMOUNT);

    start_cheat_caller_address(amm.contract_address, USER2());
    let actual_out = amm.swap(token0.contract_address, SWAP_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);

    assert(actual_out == expected_out, 'output mismatch');
}

#[test]
#[should_panic(expected: 'HAVILAH: amount = 0')]
fn test_swap_zero_amount_reverts() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    start_cheat_caller_address(amm.contract_address, USER2());
    amm.swap(token0.contract_address, 0);
    stop_cheat_caller_address(amm.contract_address);
}

#[test]
#[should_panic(expected: 'HAVILAH: invalid token')]
fn test_swap_invalid_token_reverts() {
    let (amm, _, _) = setup();
    add_initial_liquidity(amm);

    let invalid_token: ContractAddress = 'INVALID'.try_into().unwrap();

    start_cheat_caller_address(amm.contract_address, USER2());
    amm.swap(invalid_token, SWAP_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);
}

// ============ Remove Liquidity Tests ============

#[test]
fn test_remove_liquidity() {
    let (amm, token0, token1) = setup();
    add_initial_liquidity(amm);

    let shares = amm.get_balance_of(USER1());
    let shares_to_remove = shares / 2;

    let balance0_before = token0.balance_of(USER1());
    let balance1_before = token1.balance_of(USER1());

    start_cheat_caller_address(amm.contract_address, USER1());
    let (amount0, amount1) = amm.remove_liquidity(shares_to_remove);
    stop_cheat_caller_address(amm.contract_address);

    // Check amounts received
    assert(amount0 > 0, 'no amount0');
    assert(amount1 > 0, 'no amount1');

    // Check balances increased
    assert(token0.balance_of(USER1()) == balance0_before + amount0, 'wrong token0 balance');
    assert(token1.balance_of(USER1()) == balance1_before + amount1, 'wrong token1 balance');

    // Check shares burned
    assert(amm.get_balance_of(USER1()) == shares - shares_to_remove, 'shares not burned');
}

#[test]
fn test_remove_all_liquidity() {
    let (amm, token0, token1) = setup();
    add_initial_liquidity(amm);

    let shares = amm.get_balance_of(USER1());

    start_cheat_caller_address(amm.contract_address, USER1());
    let (amount0, amount1) = amm.remove_liquidity(shares);
    stop_cheat_caller_address(amm.contract_address);

    // Should receive back approximately what was deposited (minus locked minimum liquidity)
    assert(amount0 > 0, 'no amount0');
    assert(amount1 > 0, 'no amount1');

    // LP balance should be zero
    assert(amm.get_balance_of(USER1()) == 0, 'shares remain');
}

#[test]
#[should_panic(expected: 'HAVILAH: shares = 0')]
fn test_remove_liquidity_zero_shares_reverts() {
    let (amm, _, _) = setup();
    add_initial_liquidity(amm);

    start_cheat_caller_address(amm.contract_address, USER1());
    amm.remove_liquidity(0);
    stop_cheat_caller_address(amm.contract_address);
}

#[test]
#[should_panic(expected: 'HAVILAH: insufficient balance')]
fn test_remove_liquidity_insufficient_shares_reverts() {
    let (amm, _, _) = setup();
    add_initial_liquidity(amm);

    let shares = amm.get_balance_of(USER1());

    start_cheat_caller_address(amm.contract_address, USER1());
    amm.remove_liquidity(shares + 1);
    stop_cheat_caller_address(amm.contract_address);
}

// ============ View Function Tests ============

#[test]
fn test_get_amount_out() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    let amount_out = amm.get_amount_out(token0.contract_address, SWAP_AMOUNT);

    // Amount out should be positive but less than input
    assert(amount_out > 0, 'no output');
    assert(amount_out < SWAP_AMOUNT, 'output >= input');
}

#[test]
fn test_get_amount_out_zero_input() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    let amount_out = amm.get_amount_out(token0.contract_address, 0);
    assert(amount_out == 0, 'should be 0');
}

#[test]
fn test_get_price_equal_reserves() {
    let (amm, _, _) = setup();
    add_initial_liquidity(amm);

    let price = amm.get_price();
    // With equal reserves, price should be 1e18
    let expected_price: u256 = 1_000_000_000_000_000_000;
    assert(price == expected_price, 'price should be 1e18');
}

#[test]
fn test_get_price_after_swap() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    let price_before = amm.get_price();

    // Swap token0 for token1 (should increase price of token0)
    start_cheat_caller_address(amm.contract_address, USER2());
    amm.swap(token0.contract_address, SWAP_AMOUNT);
    stop_cheat_caller_address(amm.contract_address);

    let price_after = amm.get_price();

    // After buying token1 with token0, token0 reserve increases, token1 decreases
    // So price (token1/token0) should decrease
    assert(price_after < price_before, 'price should decrease');
}

// ============ Integration Tests ============

#[test]
fn test_multiple_swaps() {
    let (amm, token0, token1) = setup();
    add_initial_liquidity(amm);

    let small_swap: u256 = 100_000_000_000_000_000_000; // 100 tokens

    // Perform multiple swaps
    start_cheat_caller_address(amm.contract_address, USER2());

    let out1 = amm.swap(token0.contract_address, small_swap);
    let out2 = amm.swap(token1.contract_address, small_swap);
    let out3 = amm.swap(token0.contract_address, small_swap);

    stop_cheat_caller_address(amm.contract_address);

    // All swaps should produce output
    assert(out1 > 0, 'swap 1 failed');
    assert(out2 > 0, 'swap 2 failed');
    assert(out3 > 0, 'swap 3 failed');

    // K should be maintained or increased
    let (reserve0, reserve1) = amm.get_reserves();
    let k_after = reserve0 * reserve1;
    let k_before = LIQUIDITY_AMOUNT * LIQUIDITY_AMOUNT;
    assert(k_after >= k_before, 'k decreased');
}

#[test]
fn test_add_remove_liquidity_cycle() {
    let (amm, token0, token1) = setup();

    let initial_balance0 = token0.balance_of(USER1());
    let initial_balance1 = token1.balance_of(USER1());

    // Add liquidity
    start_cheat_caller_address(amm.contract_address, USER1());
    let shares = amm.add_liquidity(LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT);

    // Remove all liquidity
    let (amount0_back, amount1_back) = amm.remove_liquidity(shares);
    stop_cheat_caller_address(amm.contract_address);

    // Should get back approximately what was put in (minus locked minimum liquidity)
    let final_balance0 = token0.balance_of(USER1());
    let final_balance1 = token1.balance_of(USER1());

    // Loss should be minimal (only the locked minimum liquidity worth)
    let loss0 = initial_balance0 - final_balance0;
    let loss1 = initial_balance1 - final_balance1;

    // Locked liquidity is 1000, which represents a proportional amount of tokens
    assert(loss0 < 2000, 'too much token0 lost');
    assert(loss1 < 2000, 'too much token1 lost');
}

#[test]
fn test_fee_accumulation() {
    let (amm, token0, _) = setup();
    add_initial_liquidity(amm);

    let shares_before = amm.get_balance_of(USER1());
    let (reserve0_before, reserve1_before) = amm.get_reserves();
    let k_before = reserve0_before * reserve1_before;

    // Perform a large swap to accumulate fees
    let large_swap: u256 = 10_000_000_000_000_000_000_000; // 10K tokens

    start_cheat_caller_address(amm.contract_address, USER2());
    amm.swap(token0.contract_address, large_swap);
    stop_cheat_caller_address(amm.contract_address);

    let (reserve0_after, reserve1_after) = amm.get_reserves();
    let k_after = reserve0_after * reserve1_after;

    // K should increase due to fees
    assert(k_after > k_before, 'fees not accumulated');

    // LP shares value should have increased (same shares, more underlying)
    let shares_after = amm.get_balance_of(USER1());
    assert(shares_after == shares_before, 'shares should not change');
}
