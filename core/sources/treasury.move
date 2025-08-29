module core::treasury {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::transfer;

    const E_INSUFFICIENT_BALANCE: u64 = 3001;
    const E_NOT_AUTHORIZED: u64 = 3002;
    const E_INVALID_AMOUNT: u64 = 3004;

    public struct Treasury has key {
        id: UID,
        balance: Balance<SUI>,
        total_deposits: u64,
        total_withdrawals: u64,
    }

    public struct TreasuryAdminCap has key, store {
        id: UID,
    }

    public struct FundsDeposited has copy, drop {
        amount: u64,
        depositor: address,
        timestamp: u64,
    }

    public struct FundsWithdrawn has copy, drop {
        amount: u64,
        recipient: address,
        timestamp: u64,
    }

    fun init(ctx: &mut TxContext) {
        let treasury = Treasury {
            id: object::new(ctx),
            balance: balance::zero(),
            total_deposits: 0,
            total_withdrawals: 0,
        };

        let admin_cap = TreasuryAdminCap {
            id: object::new(ctx),
        };

        transfer::share_object(treasury);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    public fun deposit_funds(
        treasury: &mut Treasury,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&payment);
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut treasury.balance, payment_balance);
        
        treasury.total_deposits = treasury.total_deposits + amount;
        
        event::emit(FundsDeposited {
            amount,
            depositor: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    public fun withdraw_funds(
        _admin_cap: &TreasuryAdminCap,
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&treasury.balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        let withdrawn = balance::split(&mut treasury.balance, amount);
        treasury.total_withdrawals = treasury.total_withdrawals + amount;
        
        transfer::public_transfer(coin::from_balance(withdrawn, ctx), recipient);
        
        event::emit(FundsWithdrawn {
            amount,
            recipient,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    public fun get_balance(treasury: &Treasury): u64 {
        balance::value(&treasury.balance)
    }

    public fun get_treasury_stats(treasury: &Treasury): (u64, u64) {
        (treasury.total_deposits, treasury.total_withdrawals)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}