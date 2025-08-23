/// Enhanced Treasury Module for SuiVerse Platform
/// 
/// This module provides comprehensive treasury management for the SuiVerse decentralized learning platform,
/// including multi-asset management, governance integration, revenue distribution, and economic mechanisms.
/// 
/// Key Features:
/// - Multi-asset treasury pools with allocation strategies
/// - DAO-controlled treasury operations with governance proposals
/// - Revenue collection and distribution mechanisms
/// - Staking reward calculation and distribution
/// - Emergency controls and audit trails
/// - Yield optimization and economic incentive alignment
module suiverse_core::treasury {
    use std::string::{Self as string, String};
    use std::option::{Self as option, Option};
    use std::vector;
    use sui::object::{Self as object, ID, UID};
    use sui::tx_context::{Self as tx_context, TxContext};
    use sui::coin::{Self as coin, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self as balance, Balance};
    use sui::event;
    use sui::table::{Self as table, Table};
    use sui::clock::{Self as clock, Clock};
    use sui::transfer;
    use suiverse_core::utils;

    // Import related modules for integration
    // use suiverse::parameters::{Self, SystemParameters};

    // =============== Constants ===============
    
    // Error codes - Treasury Operations
    const E_INSUFFICIENT_BALANCE: u64 = 3001;
    const E_NOT_AUTHORIZED: u64 = 3002;
    const E_WITHDRAWAL_LIMIT_EXCEEDED: u64 = 3003;
    const E_INVALID_AMOUNT: u64 = 3004;
    const E_POOL_NOT_FOUND: u64 = 3005;
    const E_ALREADY_EXISTS: u64 = 3006;
    const E_EMERGENCY_MODE: u64 = 3007;
    const E_COOLDOWN_PERIOD: u64 = 3008;
    const E_INVALID_POOL_TYPE: u64 = 3009;
    const E_INVALID_ALLOCATION: u64 = 3010;
    
    // Error codes - Governance Integration
    const E_GOVERNANCE_PROPOSAL_REQUIRED: u64 = 3011;
    const E_PROPOSAL_NOT_EXECUTED: u64 = 3012;
    const E_INVALID_GOVERNANCE_ACTION: u64 = 3013;
    const E_TREASURY_LOCKED: u64 = 3014;
    const E_MULTISIG_REQUIRED: u64 = 3015;
    
    // Error codes - Economic Mechanisms
    const E_INVALID_YIELD_STRATEGY: u64 = 3016;
    const E_REWARD_CALCULATION_FAILED: u64 = 3017;
    const E_DISTRIBUTION_FAILED: u64 = 3018;
    const E_INVALID_STAKING_PARAMS: u64 = 3019;
    const E_SLASHING_AMOUNT_INVALID: u64 = 3020;

    // Treasury pool types (expanded)
    const POOL_REWARDS: u8 = 1;
    const POOL_VALIDATION: u8 = 2;
    const POOL_GOVERNANCE: u8 = 3;
    const POOL_OPERATIONS: u8 = 4;
    const POOL_EMERGENCY: u8 = 5;
    const POOL_STAKING: u8 = 6;
    const POOL_ROYALTIES: u8 = 7;
    const POOL_SPONSORSHIP: u8 = 8;
    const POOL_YIELD_FARMING: u8 = 9;
    const POOL_INSURANCE: u8 = 10;
    const POOL_DEVELOPMENT: u8 = 11;
    const POOL_MARKETING: u8 = 12;

    // Withdrawal limits (in MIST, 1 SUI = 1_000_000_000 MIST)
    const DAILY_WITHDRAWAL_LIMIT: u64 = 10000_000_000_000; // 10,000 SUI
    const EMERGENCY_WITHDRAWAL_LIMIT: u64 = 100000_000_000_000; // 100,000 SUI
    const GOVERNANCE_WITHDRAWAL_LIMIT: u64 = 50000_000_000_000; // 50,000 SUI

    // Economic constants
    const BASIS_POINTS: u64 = 10000; // 100% = 10,000 basis points
    const EPOCH_DURATION_MS: u64 = 86400000; // 24 hours in milliseconds
    const ANNUAL_EPOCHS: u64 = 365; // Approximate epochs per year
    const MIN_STAKING_PERIOD: u64 = 7; // Minimum staking period in epochs

    // Governance action types
    const ACTION_ALLOCATE_FUNDS: u8 = 1;
    const ACTION_UPDATE_STRATEGY: u8 = 2;
    const ACTION_EMERGENCY_WITHDRAW: u8 = 3;
    const ACTION_YIELD_FARMING: u8 = 4;
    const ACTION_INSURANCE_CLAIM: u8 = 5;

    // Yield strategies
    const STRATEGY_CONSERVATIVE: u8 = 1;
    const STRATEGY_BALANCED: u8 = 2;
    const STRATEGY_AGGRESSIVE: u8 = 3;
    const STRATEGY_CUSTOM: u8 = 4;

    // =============== Structs ===============
    
    /// Comprehensive treasury vault with advanced features
    public struct Treasury has key, store {
        id: UID,
        
        // Core Balance Management
        total_balance: Balance<SUI>,
        pools: Table<u8, TreasuryPool>,
        pool_allocations: Table<u8, u64>, // Pool type -> allocation percentage (basis points)
        
        // Treasury Statistics
        total_deposits: u64,
        total_withdrawals: u64,
        total_rewards_distributed: u64,
        total_fees_collected: u64,
        total_yield_generated: u64,
        
        // Withdrawal Tracking and Limits
        daily_withdrawals: Table<u64, u64>, // epoch_day -> amount
        last_withdrawal_day: u64,
        withdrawal_limits: Table<u8, u64>, // Pool type -> daily limit
        
        // Governance Integration
        governance_actions: Table<ID, GovernanceAction>,
        pending_proposals: vector<ID>,
        multisig_threshold: u8,
        authorized_signers: vector<address>,
        
        // Emergency Controls
        emergency_mode: bool,
        emergency_admin: Option<address>,
        last_emergency_activation: u64,
        emergency_cooldown: u64,
        
        // Economic Mechanisms
        staking_pools: Table<address, StakingPosition>,
        total_staked: u64,
        reward_rates: Table<u8, u64>, // Pool type -> annual reward rate (basis points)
        yield_strategies: Table<u8, YieldStrategy>,
        
        // Revenue Streams
        revenue_sources: Table<String, RevenueStream>,
        distribution_schedules: Table<u8, DistributionSchedule>,
        
        // Audit and Compliance
        transaction_history: Table<u64, vector<TreasuryTransaction>>,
        audit_logs: vector<AuditEntry>,
        compliance_checks: Table<String, bool>,
        
        // Treasury Configuration
        treasury_config: TreasuryConfig,
        version: u64,
        last_update: u64,
    }

    /// Individual treasury pool with enhanced features
    public struct TreasuryPool has store {
        pool_type: u8,
        balance: Balance<SUI>,
        allocated_amount: u64,
        reserved_amount: u64,
        yield_accumulated: u64,
        last_yield_calculation: u64,
        withdrawal_history: vector<WithdrawalRecord>,
        pool_strategy: u8,
        performance_metrics: PoolMetrics,
        last_updated: u64,
    }

    /// Governance action for treasury operations
    public struct GovernanceAction has store {
        action_type: u8,
        proposal_id: ID,
        target_pool: Option<u8>,
        amount: Option<u64>,
        parameters: vector<u8>,
        required_signatures: u8,
        current_signatures: vector<address>,
        executed: bool,
        created_at: u64,
        execution_deadline: u64,
    }

    /// Staking position for reward calculation
    public struct StakingPosition has store, drop {
        staker: address,
        amount: u64,
        start_epoch: u64,
        lock_period: u64,
        reward_rate: u64,
        accumulated_rewards: u64,
        last_claim_epoch: u64,
        auto_compound: bool,
    }

    /// Yield strategy configuration
    public struct YieldStrategy has store {
        strategy_type: u8,
        target_apy: u64, // Annual percentage yield in basis points
        risk_level: u8,
        allocation_weights: Table<u8, u64>, // Pool type -> weight
        rebalance_frequency: u64,
        last_rebalance: u64,
        performance_history: vector<u64>,
    }

    /// Revenue stream tracking
    public struct RevenueStream has store {
        stream_name: String,
        source_type: u8,
        daily_average: u64,
        monthly_total: u64,
        allocation_rules: Table<u8, u64>, // Pool type -> percentage
        last_distribution: u64,
        active: bool,
    }

    /// Distribution schedule for automated payouts
    public struct DistributionSchedule has store {
        pool_type: u8,
        frequency: u64, // In epochs
        amount_per_distribution: u64,
        recipients: vector<address>,
        distribution_weights: vector<u64>,
        last_distribution: u64,
        next_distribution: u64,
        active: bool,
    }

    /// Pool performance metrics
    public struct PoolMetrics has store {
        total_deposits: u64,
        total_withdrawals: u64,
        total_yield: u64,
        average_balance: u64,
        utilization_rate: u64, // Percentage of pool actively used
        performance_score: u64, // Relative performance vs target
    }

    /// Withdrawal record for audit trail
    public struct WithdrawalRecord has store {
        amount: u64,
        recipient: address,
        reason: String,
        authorized_by: address,
        timestamp: u64,
        governance_proposal_id: Option<ID>,
    }

    /// Treasury transaction for comprehensive logging
    public struct TreasuryTransaction has store {
        transaction_type: u8,
        pool_involved: Option<u8>,
        amount: u64,
        counterparty: address,
        description: String,
        metadata: vector<u8>,
        timestamp: u64,
        block_height: u64,
    }

    /// Audit entry for compliance tracking
    public struct AuditEntry has store {
        audit_type: String,
        description: String,
        auditor: address,
        finding_level: u8, // 1=Info, 2=Warning, 3=Critical
        resolved: bool,
        timestamp: u64,
    }

    /// Treasury configuration parameters
    public struct TreasuryConfig has store {
        min_pool_balance: u64,
        max_single_withdrawal: u64,
        governance_delay: u64,
        emergency_threshold: u64,
        yield_calculation_frequency: u64,
        audit_frequency: u64,
        multisig_enabled: bool,
        auto_rebalancing: bool,
    }

    /// Treasury admin capability with role-based access
    public struct TreasuryAdminCap has key, store {
        id: UID,
        admin_level: u8, // 1=Basic, 2=Advanced, 3=Emergency
        authorized_pools: vector<u8>,
        withdrawal_limit: u64,
    }

    /// Treasury governance capability for DAO operations
    public struct TreasuryGovernanceCap has key, store {
        id: UID,
        proposal_power: u64,
        authorized_actions: vector<u8>,
    }

    /// Multi-signature operation capability
    public struct TreasuryMultiSigCap has key, store {
        id: UID,
        signer_address: address,
        signing_power: u64,
        active: bool,
    }

    /// Treasury auditor capability (read-only with special permissions)
    public struct TreasuryAuditorCap has key, store {
        id: UID,
        audit_scope: vector<u8>, // Pool types auditor can access
        reporting_authority: bool,
    }

    // =============== Events ===============
    
    // Core Treasury Events
    public struct FundsDeposited has copy, drop {
        pool_type: u8,
        amount: u64,
        depositor: address,
        source: String,
        timestamp: u64,
    }

    public struct FundsWithdrawn has copy, drop {
        pool_type: u8,
        amount: u64,
        recipient: address,
        reason: String,
        authorized_by: address,
        governance_proposal_id: Option<ID>,
        timestamp: u64,
    }

    public struct RewardDistributed has copy, drop {
        recipient: address,
        amount: u64,
        reward_type: String,
        pool_source: u8,
        calculation_basis: String,
        timestamp: u64,
    }

    // Governance Events
    public struct GovernanceActionCreated has copy, drop {
        action_id: ID,
        action_type: u8,
        proposal_id: ID,
        required_signatures: u8,
        execution_deadline: u64,
        created_by: address,
        timestamp: u64,
    }

    public struct GovernanceActionExecuted has copy, drop {
        action_id: ID,
        executed_by: address,
        final_signatures: vector<address>,
        timestamp: u64,
    }

    public struct TreasuryGovernanceUpdate has copy, drop {
        parameter_changed: String,
        old_value: vector<u8>,
        new_value: vector<u8>,
        proposal_id: ID,
        timestamp: u64,
    }

    // Emergency Events
    public struct EmergencyModeActivated has copy, drop {
        activated_by: address,
        reason: String,
        affected_pools: vector<u8>,
        timestamp: u64,
    }

    public struct EmergencyModeDeactivated has copy, drop {
        deactivated_by: address,
        duration_ms: u64,
        timestamp: u64,
    }

    public struct EmergencyWithdrawal has copy, drop {
        amount: u64,
        pool_type: u8,
        recipient: address,
        justification: String,
        authorized_by: address,
        timestamp: u64,
    }

    // Economic Events
    public struct PoolRebalanced has copy, drop {
        from_pools: vector<u8>,
        to_pools: vector<u8>,
        amounts: vector<u64>,
        rebalance_strategy: u8,
        trigger: String,
        timestamp: u64,
    }

    public struct YieldCalculated has copy, drop {
        pool_type: u8,
        yield_amount: u64,
        yield_rate: u64,
        calculation_period: u64,
        strategy_used: u8,
        timestamp: u64,
    }

    public struct StakingRewardDistributed has copy, drop {
        staker: address,
        amount: u64,
        staking_period: u64,
        reward_rate: u64,
        auto_compounded: bool,
        timestamp: u64,
    }

    // Revenue Events
    public struct RevenueCollected has copy, drop {
        source: String,
        amount: u64,
        allocation_breakdown: vector<u64>, // Per pool allocation
        collection_method: String,
        timestamp: u64,
    }

    public struct RevenueDistributed has copy, drop {
        distribution_schedule_id: u8,
        total_amount: u64,
        recipients_count: u64,
        distribution_method: String,
        timestamp: u64,
    }

    // Audit and Compliance Events
    public struct TreasuryAudited has copy, drop {
        auditor: address,
        audit_scope: vector<u8>,
        findings_count: u64,
        overall_rating: u8,
        recommendations: vector<String>,
        timestamp: u64,
    }

    public struct ComplianceCheckCompleted has copy, drop {
        check_type: String,
        result: bool,
        details: String,
        checked_by: address,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        // Initialize comprehensive treasury configuration
        let mut treasury_config = TreasuryConfig {
            min_pool_balance: 1_000_000_000, // 1 SUI minimum per pool
            max_single_withdrawal: 10_000_000_000_000, // 10,000 SUI max
            governance_delay: 172800000, // 48 hours in ms
            emergency_threshold: 1_000_000_000_000, // 1,000 SUI for emergency actions
            yield_calculation_frequency: 86400000, // Daily yield calculation
            audit_frequency: 2592000000, // Monthly audits (30 days)
            multisig_enabled: true,
            auto_rebalancing: false, // Start with manual rebalancing
        };

        // Create main treasury with enhanced features
        let mut treasury = Treasury {
            id: object::new(ctx),
            
            // Core balances
            total_balance: balance::zero(),
            pools: table::new(ctx),
            pool_allocations: table::new(ctx),
            
            // Statistics
            total_deposits: 0,
            total_withdrawals: 0,
            total_rewards_distributed: 0,
            total_fees_collected: 0,
            total_yield_generated: 0,
            
            // Withdrawal management
            daily_withdrawals: table::new(ctx),
            last_withdrawal_day: 0,
            withdrawal_limits: table::new(ctx),
            
            // Governance
            governance_actions: table::new(ctx),
            pending_proposals: vector::empty(),
            multisig_threshold: 3, // Require 3 signatures for critical operations
            authorized_signers: vector::empty(),
            
            // Emergency controls
            emergency_mode: false,
            emergency_admin: option::none(),
            last_emergency_activation: 0,
            emergency_cooldown: 86400000, // 24 hours
            
            // Economic features
            staking_pools: table::new(ctx),
            total_staked: 0,
            reward_rates: table::new(ctx),
            yield_strategies: table::new(ctx),
            
            // Revenue management
            revenue_sources: table::new(ctx),
            distribution_schedules: table::new(ctx),
            
            // Audit and compliance
            transaction_history: table::new(ctx),
            audit_logs: vector::empty(),
            compliance_checks: table::new(ctx),
            
            treasury_config,
            version: 1,
            last_update: 0,
        };

        // Initialize default pool allocations (aligned with specification)
        initialize_default_pools(&mut treasury, ctx);
        
        // Initialize default withdrawal limits
        initialize_withdrawal_limits(&mut treasury);
        
        // Initialize default reward rates
        initialize_reward_rates(&mut treasury);
        
        // Create capability objects
        let admin_cap = TreasuryAdminCap {
            id: object::new(ctx),
            admin_level: 3, // Emergency level
            authorized_pools: vector[POOL_REWARDS, POOL_VALIDATION, POOL_GOVERNANCE, POOL_OPERATIONS, POOL_EMERGENCY],
            withdrawal_limit: EMERGENCY_WITHDRAWAL_LIMIT,
        };
        
        let governance_cap = TreasuryGovernanceCap {
            id: object::new(ctx),
            proposal_power: 10000, // Full governance power
            authorized_actions: vector[ACTION_ALLOCATE_FUNDS, ACTION_UPDATE_STRATEGY, ACTION_YIELD_FARMING],
        };
        
        let auditor_cap = TreasuryAuditorCap {
            id: object::new(ctx),
            audit_scope: vector[POOL_REWARDS, POOL_VALIDATION, POOL_GOVERNANCE, POOL_OPERATIONS, POOL_STAKING, POOL_ROYALTIES],
            reporting_authority: true,
        };

        // Share treasury and transfer capabilities
        transfer::share_object(treasury);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::transfer(governance_cap, tx_context::sender(ctx));
        transfer::transfer(auditor_cap, tx_context::sender(ctx));
    }

    // =============== Pool Management Functions ===============
    
    /// Initialize default treasury pools with proper allocations
    fun initialize_default_pools(treasury: &mut Treasury, ctx: &mut TxContext) {
        // Create default pools based on specification
        let pool_types = vector[
            POOL_REWARDS, POOL_VALIDATION, POOL_GOVERNANCE, POOL_OPERATIONS,
            POOL_EMERGENCY, POOL_STAKING, POOL_ROYALTIES, POOL_SPONSORSHIP,
            POOL_YIELD_FARMING, POOL_INSURANCE
        ];
        let allocations = vector[
            3000, 2000, 1000, 2000, 1000, 500, 500, 500, 300, 200
        ];

        let mut i = 0;
        while (i < vector::length(&pool_types)) {
            let pool_type = *vector::borrow(&pool_types, i);
            let allocation = *vector::borrow(&allocations, i);
            
            // Create pool
            let pool = TreasuryPool {
                pool_type,
                balance: balance::zero(),
                allocated_amount: 0,
                reserved_amount: 0,
                yield_accumulated: 0,
                last_yield_calculation: 0,
                withdrawal_history: vector::empty(),
                pool_strategy: STRATEGY_CONSERVATIVE,
                performance_metrics: PoolMetrics {
                    total_deposits: 0,
                    total_withdrawals: 0,
                    total_yield: 0,
                    average_balance: 0,
                    utilization_rate: 0,
                    performance_score: 5000, // Start at 50%
                },
                last_updated: 0,
            };

            table::add(&mut treasury.pools, pool_type, pool);
            table::add(&mut treasury.pool_allocations, pool_type, allocation);
            
            i = i + 1;
        };
    }

    /// Initialize withdrawal limits for each pool type
    fun initialize_withdrawal_limits(treasury: &mut Treasury) {
        let limit_pool_types = vector[
            POOL_REWARDS, POOL_VALIDATION, POOL_GOVERNANCE, POOL_OPERATIONS,
            POOL_EMERGENCY, POOL_STAKING, POOL_ROYALTIES, POOL_SPONSORSHIP
        ];
        let limits = vector[
            5000_000_000_000, 3000_000_000_000, 10000_000_000_000, 5000_000_000_000,
            50000_000_000_000, 2000_000_000_000, 1000_000_000_000, 1000_000_000_000
        ];

        let mut i = 0;
        while (i < vector::length(&limit_pool_types)) {
            let pool_type = *vector::borrow(&limit_pool_types, i);
            let limit = *vector::borrow(&limits, i);
            table::add(&mut treasury.withdrawal_limits, pool_type, limit);
            i = i + 1;
        };
    }

    /// Initialize default reward rates (annual rates in basis points)
    fun initialize_reward_rates(treasury: &mut Treasury) {
        let rate_pool_types = vector[
            POOL_STAKING, POOL_VALIDATION, POOL_YIELD_FARMING, POOL_GOVERNANCE
        ];
        let rates = vector[
            800, 1200, 1500, 500  // 8%, 12%, 15%, 5% annual rates in basis points
        ];

        let mut i = 0;
        while (i < vector::length(&rate_pool_types)) {
            let pool_type = *vector::borrow(&rate_pool_types, i);
            let rate = *vector::borrow(&rates, i);
            table::add(&mut treasury.reward_rates, pool_type, rate);
            i = i + 1;
        };
    }

    // =============== Public Deposit Functions ===============
    
    /// Enhanced fund deposit with automatic allocation and yield calculation
    public fun deposit_funds(
        treasury: &mut Treasury,
        payment: Coin<SUI>,
        pool_type: u8,
        source: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&payment);
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(table::contains(&treasury.pools, pool_type), E_POOL_NOT_FOUND);
        
        let payment_balance = coin::into_balance(payment);
        
        // Add to total balance
        balance::join(&mut treasury.total_balance, payment_balance);
        
        // Allocate to specific pool
        let pool = table::borrow_mut(&mut treasury.pools, pool_type);
        let pool_balance = balance::split(&mut treasury.total_balance, amount);
        balance::join(&mut pool.balance, pool_balance);
        
        // Update pool metrics
        pool.allocated_amount = pool.allocated_amount + amount;
        pool.performance_metrics.total_deposits = pool.performance_metrics.total_deposits + amount;
        pool.last_updated = clock::timestamp_ms(clock);
        
        // Update treasury statistics
        treasury.total_deposits = treasury.total_deposits + amount;
        
        // Record transaction
        record_treasury_transaction(
            treasury,
            1, // Deposit type
            option::some(pool_type),
            amount,
            tx_context::sender(ctx),
            string::utf8(b"Deposit to pool"),
            vector::empty(),
            clock,
            ctx
        );
        
        // Calculate and update yield if applicable
        if (should_calculate_yield(treasury, pool_type, clock)) {
            calculate_pool_yield(treasury, pool_type, clock);
        };
        
        event::emit(FundsDeposited {
            pool_type,
            amount,
            depositor: tx_context::sender(ctx),
            source,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Deposit fee revenue with automatic distribution
    public fun deposit_fee_revenue(
        treasury: &mut Treasury,
        fee: Coin<SUI>,
        fee_type: String,
        distribution_rules: vector<u8>, // Pool types for distribution
        distribution_weights: vector<u64>, // Weights for distribution
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let total_amount = coin::value(&fee);
        assert!(total_amount > 0, E_INVALID_AMOUNT);
        assert!(vector::length(&distribution_rules) == vector::length(&distribution_weights), E_INVALID_ALLOCATION);
        
        let fee_balance = coin::into_balance(fee);
        balance::join(&mut treasury.total_balance, fee_balance);
        
        // Calculate total weight for proportional distribution
        let total_weight = utils::vector_sum(&distribution_weights);
        assert!(total_weight > 0, E_INVALID_ALLOCATION);
        
        // Distribute to pools based on weights
        let mut i = 0;
        let mut allocated_total = 0;
        while (i < vector::length(&distribution_rules)) {
            let pool_type = *vector::borrow(&distribution_rules, i);
            let weight = *vector::borrow(&distribution_weights, i);
            let allocation = (total_amount * weight) / total_weight;
            
            if (allocation > 0 && table::contains(&treasury.pools, pool_type)) {
                let pool = table::borrow_mut(&mut treasury.pools, pool_type);
                let pool_allocation = balance::split(&mut treasury.total_balance, allocation);
                balance::join(&mut pool.balance, pool_allocation);
                
                pool.allocated_amount = pool.allocated_amount + allocation;
                pool.performance_metrics.total_deposits = pool.performance_metrics.total_deposits + allocation;
                allocated_total = allocated_total + allocation;
            };
            
            i = i + 1;
        };
        
        treasury.total_fees_collected = treasury.total_fees_collected + total_amount;
        
        event::emit(RevenueCollected {
            source: fee_type,
            amount: total_amount,
            allocation_breakdown: distribution_weights,
            collection_method: string::utf8(b"Automatic Distribution"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Package-level Withdrawal Functions ===============
    
    /// Enhanced withdrawal for rewards with governance tracking
    public fun withdraw_for_rewards(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        reward_type: String,
        calculation_basis: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(!treasury.emergency_mode, E_EMERGENCY_MODE);
        assert!(table::contains(&treasury.pools, POOL_REWARDS), E_POOL_NOT_FOUND);
        
        // Check daily withdrawal limits before borrowing
        assert!(check_daily_withdrawal_limit(treasury, POOL_REWARDS, amount, clock), E_WITHDRAWAL_LIMIT_EXCEEDED);
        
        let pool = table::borrow_mut(&mut treasury.pools, POOL_REWARDS);
        assert!(balance::value(&pool.balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        let withdrawn = balance::split(&mut pool.balance, amount);
        
        // Update pool metrics
        pool.performance_metrics.total_withdrawals = pool.performance_metrics.total_withdrawals + amount;
        pool.last_updated = clock::timestamp_ms(clock);
        
        // Record withdrawal
        let withdrawal_record = WithdrawalRecord {
            amount,
            recipient,
            reason: reward_type,
            authorized_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
            governance_proposal_id: option::none(),
        };
        vector::push_back(&mut pool.withdrawal_history, withdrawal_record);
        
        // Update treasury statistics
        treasury.total_withdrawals = treasury.total_withdrawals + amount;
        treasury.total_rewards_distributed = treasury.total_rewards_distributed + amount;
        
        // Update daily withdrawal tracking
        update_daily_withdrawal_tracking(treasury, amount, clock);
        
        // Record transaction
        record_treasury_transaction(
            treasury,
            2, // Withdrawal type
            option::some(POOL_REWARDS),
            amount,
            recipient,
            reward_type,
            vector::empty(),
            clock,
            ctx
        );
        
        event::emit(RewardDistributed {
            recipient,
            amount,
            reward_type,
            pool_source: POOL_REWARDS,
            calculation_basis,
            timestamp: clock::timestamp_ms(clock),
        });
        
        coin::from_balance(withdrawn, ctx)
    }

    /// Enhanced withdrawal for validation rewards with performance tracking
    public fun withdraw_for_validation(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        validation_type: String,
        performance_bonus: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(!treasury.emergency_mode, E_EMERGENCY_MODE);
        assert!(table::contains(&treasury.pools, POOL_VALIDATION), E_POOL_NOT_FOUND);
        
        let total_amount = amount + performance_bonus;
        
        // Check daily withdrawal limits before borrowing
        assert!(check_daily_withdrawal_limit(treasury, POOL_VALIDATION, total_amount, clock), E_WITHDRAWAL_LIMIT_EXCEEDED);
        
        let pool = table::borrow_mut(&mut treasury.pools, POOL_VALIDATION);
        assert!(balance::value(&pool.balance) >= total_amount, E_INSUFFICIENT_BALANCE);
        
        let withdrawn = balance::split(&mut pool.balance, total_amount);
        
        // Update pool metrics and performance
        pool.performance_metrics.total_withdrawals = pool.performance_metrics.total_withdrawals + total_amount;
        update_pool_performance_score(pool, performance_bonus > 0);
        pool.last_updated = clock::timestamp_ms(clock);
        
        // Record withdrawal with detailed reason
        let withdrawal_record = WithdrawalRecord {
            amount: total_amount,
            recipient,
            reason: validation_type,
            authorized_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
            governance_proposal_id: option::none(),
        };
        vector::push_back(&mut pool.withdrawal_history, withdrawal_record);
        
        treasury.total_withdrawals = treasury.total_withdrawals + total_amount;
        update_daily_withdrawal_tracking(treasury, total_amount, clock);
        
        event::emit(RewardDistributed {
            recipient,
            amount: total_amount,
            reward_type: validation_type,
            pool_source: POOL_VALIDATION,
            calculation_basis: string::utf8(b"Validation Performance + Bonus"),
            timestamp: clock::timestamp_ms(clock),
        });
        
        coin::from_balance(withdrawn, ctx)
    }

    /// Governance-controlled withdrawal with proposal tracking
    public fun withdraw_for_governance(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        reason: String,
        proposal_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(!treasury.emergency_mode, E_EMERGENCY_MODE);
        assert!(table::contains(&treasury.pools, POOL_GOVERNANCE), E_POOL_NOT_FOUND);
        
        // Verify governance proposal was executed
        assert!(table::contains(&treasury.governance_actions, proposal_id), E_PROPOSAL_NOT_EXECUTED);
        let governance_action = table::borrow(&treasury.governance_actions, proposal_id);
        assert!(governance_action.executed, E_PROPOSAL_NOT_EXECUTED);
        
        let pool = table::borrow_mut(&mut treasury.pools, POOL_GOVERNANCE);
        assert!(balance::value(&pool.balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        // Check governance withdrawal limits
        assert!(amount <= GOVERNANCE_WITHDRAWAL_LIMIT, E_WITHDRAWAL_LIMIT_EXCEEDED);
        
        let withdrawn = balance::split(&mut pool.balance, amount);
        
        // Record withdrawal with governance tracking
        let withdrawal_record = WithdrawalRecord {
            amount,
            recipient,
            reason,
            authorized_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
            governance_proposal_id: option::some(proposal_id),
        };
        vector::push_back(&mut pool.withdrawal_history, withdrawal_record);
        
        // Update metrics
        pool.performance_metrics.total_withdrawals = pool.performance_metrics.total_withdrawals + amount;
        treasury.total_withdrawals = treasury.total_withdrawals + amount;
        
        event::emit(FundsWithdrawn {
            pool_type: POOL_GOVERNANCE,
            amount,
            recipient,
            reason,
            authorized_by: tx_context::sender(ctx),
            governance_proposal_id: option::some(proposal_id),
            timestamp: clock::timestamp_ms(clock),
        });
        
        coin::from_balance(withdrawn, ctx)
    }

    /// Withdraw staking rewards with compound option
    public fun withdraw_staking_rewards(
        treasury: &mut Treasury,
        staker: address,
        auto_compound: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<SUI> {
        assert!(table::contains(&treasury.staking_pools, staker), E_INVALID_STAKING_PARAMS);
        
        let staking_position = table::borrow_mut(&mut treasury.staking_pools, staker);
        let current_epoch = tx_context::epoch(ctx);
        
        // Calculate accumulated rewards
        let reward_amount = calculate_staking_rewards(staking_position, current_epoch);
        assert!(reward_amount > 0, E_REWARD_CALCULATION_FAILED);
        
        let pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        assert!(balance::value(&pool.balance) >= reward_amount, E_INSUFFICIENT_BALANCE);
        
        let rewards = balance::split(&mut pool.balance, reward_amount);
        
        if (auto_compound) {
            // Add rewards to staking amount
            staking_position.amount = staking_position.amount + reward_amount;
            staking_position.accumulated_rewards = 0;
            
            // Return the balance to the pool for auto-compounding
            balance::join(&mut pool.balance, rewards);
            
            event::emit(StakingRewardDistributed {
                staker,
                amount: reward_amount,
                staking_period: current_epoch - staking_position.start_epoch,
                reward_rate: staking_position.reward_rate,
                auto_compounded: true,
                timestamp: clock::timestamp_ms(clock),
            });
            
            // Return zero coin for auto-compound
            coin::from_balance(balance::zero(), ctx)
        } else {
            // Reset accumulated rewards
            staking_position.accumulated_rewards = 0;
            staking_position.last_claim_epoch = current_epoch;
            
            treasury.total_rewards_distributed = treasury.total_rewards_distributed + reward_amount;
            
            event::emit(StakingRewardDistributed {
                staker,
                amount: reward_amount,
                staking_period: current_epoch - staking_position.start_epoch,
                reward_rate: staking_position.reward_rate,
                auto_compounded: false,
                timestamp: clock::timestamp_ms(clock),
            });
            
            coin::from_balance(rewards, ctx)
        }
    }

    // =============== Admin Functions ===============
    
    /// Emergency withdrawal with enhanced controls and logging
    public fun emergency_withdraw(
        admin_cap: &TreasuryAdminCap,
        treasury: &mut Treasury,
        pool_type: u8,
        amount: u64,
        recipient: address,
        justification: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(admin_cap.admin_level >= 3, E_NOT_AUTHORIZED); // Require emergency level
        assert!(amount <= EMERGENCY_WITHDRAWAL_LIMIT, E_WITHDRAWAL_LIMIT_EXCEEDED);
        assert!(vector::contains(&admin_cap.authorized_pools, &pool_type), E_NOT_AUTHORIZED);
        assert!(table::contains(&treasury.pools, pool_type), E_POOL_NOT_FOUND);
        
        let pool = table::borrow_mut(&mut treasury.pools, pool_type);
        assert!(balance::value(&pool.balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        let withdrawn = balance::split(&mut pool.balance, amount);
        
        // Record emergency withdrawal with detailed audit trail
        let withdrawal_record = WithdrawalRecord {
            amount,
            recipient,
            reason: justification,
            authorized_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
            governance_proposal_id: option::none(),
        };
        vector::push_back(&mut pool.withdrawal_history, withdrawal_record);
        
        // Add to audit log
        let audit_entry = AuditEntry {
            audit_type: string::utf8(b"Emergency Withdrawal"),
            description: justification,
            auditor: tx_context::sender(ctx),
            finding_level: 3, // Critical level
            resolved: false,
            timestamp: clock::timestamp_ms(clock),
        };
        vector::push_back(&mut treasury.audit_logs, audit_entry);
        
        // Update metrics
        pool.performance_metrics.total_withdrawals = pool.performance_metrics.total_withdrawals + amount;
        treasury.total_withdrawals = treasury.total_withdrawals + amount;
        
        transfer::public_transfer(
            coin::from_balance(withdrawn, ctx),
            recipient
        );
        
        event::emit(EmergencyWithdrawal {
            amount,
            pool_type,
            recipient,
            justification,
            authorized_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Activate emergency mode with comprehensive controls
    public fun activate_emergency_mode(
        admin_cap: &TreasuryAdminCap,
        treasury: &mut Treasury,
        reason: String,
        affected_pools: vector<u8>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(admin_cap.admin_level >= 3, E_NOT_AUTHORIZED);
        
        treasury.emergency_mode = true;
        treasury.emergency_admin = option::some(tx_context::sender(ctx));
        treasury.last_emergency_activation = clock::timestamp_ms(clock);
        
        // Add comprehensive audit entry
        let audit_entry = AuditEntry {
            audit_type: string::utf8(b"Emergency Mode Activation"),
            description: reason,
            auditor: tx_context::sender(ctx),
            finding_level: 3, // Critical
            resolved: false,
            timestamp: clock::timestamp_ms(clock),
        };
        vector::push_back(&mut treasury.audit_logs, audit_entry);
        
        event::emit(EmergencyModeActivated {
            activated_by: tx_context::sender(ctx),
            reason,
            affected_pools,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Deactivate emergency mode with cooldown enforcement
    public fun deactivate_emergency_mode(
        admin_cap: &TreasuryAdminCap,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(admin_cap.admin_level >= 3, E_NOT_AUTHORIZED);
        assert!(treasury.emergency_mode, E_EMERGENCY_MODE);
        
        // Enforce cooldown period
        let current_time = clock::timestamp_ms(clock);
        assert!(
            current_time - treasury.last_emergency_activation >= treasury.emergency_cooldown,
            E_COOLDOWN_PERIOD
        );
        
        let duration = current_time - treasury.last_emergency_activation;
        
        treasury.emergency_mode = false;
        treasury.emergency_admin = option::none();
        
        // Mark related audit entries as resolved
        mark_emergency_audits_resolved(&mut treasury.audit_logs, current_time);
        
        event::emit(EmergencyModeDeactivated {
            deactivated_by: tx_context::sender(ctx),
            duration_ms: duration,
            timestamp: current_time,
        });
    }

    /// Advanced pool rebalancing with yield optimization
    public fun rebalance_pools_advanced(
        admin_cap: &TreasuryAdminCap,
        treasury: &mut Treasury,
        rebalance_strategy: u8,
        target_allocations: vector<u64>, // New allocation percentages
        pool_types: vector<u8>,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        assert!(admin_cap.admin_level >= 2, E_NOT_AUTHORIZED);
        assert!(vector::length(&target_allocations) == vector::length(&pool_types), E_INVALID_ALLOCATION);
        
        // Validate total allocation = 100%
        let total_allocation = utils::vector_sum(&target_allocations);
        assert!(total_allocation == BASIS_POINTS, E_INVALID_ALLOCATION);
        
        let mut from_pools = vector::empty<u8>();
        let mut to_pools = vector::empty<u8>();
        let mut amounts = vector::empty<u64>();
        
        // Calculate rebalancing moves
        let mut i = 0;
        while (i < vector::length(&pool_types)) {
            let pool_type = *vector::borrow(&pool_types, i);
            let target_allocation = *vector::borrow(&target_allocations, i);
            
            if (table::contains(&treasury.pools, pool_type)) {
                let current_allocation = *table::borrow(&treasury.pool_allocations, pool_type);
                
                if (target_allocation != current_allocation) {
                    // Update allocation
                    *table::borrow_mut(&mut treasury.pool_allocations, pool_type) = target_allocation;
                    
                    // Calculate amount to move
                    let total_treasury_value = balance::value(&treasury.total_balance);
                    let target_amount = (total_treasury_value * target_allocation) / BASIS_POINTS;
                    let pool = table::borrow(&treasury.pools, pool_type);
                    let current_amount = balance::value(&pool.balance);
                    
                    if (target_amount > current_amount) {
                        vector::push_back(&mut to_pools, pool_type);
                        vector::push_back(&mut amounts, target_amount - current_amount);
                    } else if (target_amount < current_amount) {
                        vector::push_back(&mut from_pools, pool_type);
                        vector::push_back(&mut amounts, current_amount - target_amount);
                    };
                };
            };
            
            i = i + 1;
        };
        
        // Execute rebalancing (simplified version - in production would need complex balancing logic)
        execute_pool_rebalancing(treasury, &from_pools, &to_pools, &amounts);
        
        event::emit(PoolRebalanced {
            from_pools,
            to_pools,
            amounts,
            rebalance_strategy,
            trigger: string::utf8(b"Manual Admin Rebalance"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Governance Functions ===============
    
    /// Create governance action for treasury operations
    public fun create_governance_action(
        governance_cap: &TreasuryGovernanceCap,
        treasury: &mut Treasury,
        action_type: u8,
        proposal_id: ID,
        target_pool: Option<u8>,
        amount: Option<u64>,
        parameters: vector<u8>,
        execution_deadline: u64,
        ctx: &mut TxContext,
    ) {
        assert!(vector::contains(&governance_cap.authorized_actions, &action_type), E_NOT_AUTHORIZED);
        
        let action_id = object::new(ctx);
        let action_id_inner = object::uid_to_inner(&action_id);
        object::delete(action_id);
        
        let required_signatures = if (action_type == ACTION_EMERGENCY_WITHDRAW) {
            treasury.multisig_threshold
        } else {
            2 // Regular operations require 2 signatures
        };
        
        let governance_action = GovernanceAction {
            action_type,
            proposal_id,
            target_pool,
            amount,
            parameters,
            required_signatures,
            current_signatures: vector::empty(),
            executed: false,
            created_at: tx_context::epoch(ctx),
            execution_deadline,
        };
        
        table::add(&mut treasury.governance_actions, action_id_inner, governance_action);
        vector::push_back(&mut treasury.pending_proposals, proposal_id);
        
        event::emit(GovernanceActionCreated {
            action_id: action_id_inner,
            action_type,
            proposal_id,
            required_signatures,
            execution_deadline,
            created_by: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });
    }

    /// Sign governance action with multi-sig support
    public fun sign_governance_action(
        multisig_cap: &TreasuryMultiSigCap,
        treasury: &mut Treasury,
        action_id: ID,
        ctx: &TxContext,
    ) {
        assert!(multisig_cap.active, E_NOT_AUTHORIZED);
        assert!(table::contains(&treasury.governance_actions, action_id), E_INVALID_GOVERNANCE_ACTION);
        
        let governance_action = table::borrow_mut(&mut treasury.governance_actions, action_id);
        assert!(!governance_action.executed, E_INVALID_GOVERNANCE_ACTION);
        
        let signer = tx_context::sender(ctx);
        
        // Check if already signed
        assert!(!vector::contains(&governance_action.current_signatures, &signer), E_ALREADY_EXISTS);
        
        // Add signature
        vector::push_back(&mut governance_action.current_signatures, signer);
        
        // Check if enough signatures collected
        if (vector::length(&governance_action.current_signatures) >= (governance_action.required_signatures as u64)) {
            execute_governance_action(treasury, action_id, ctx);
        };
    }

    /// Execute governance action when signatures are sufficient
    fun execute_governance_action(
        treasury: &mut Treasury,
        action_id: ID,
        ctx: &TxContext,
    ) {
        let governance_action = table::borrow_mut(&mut treasury.governance_actions, action_id);
        assert!(!governance_action.executed, E_INVALID_GOVERNANCE_ACTION);
        
        // Mark as executed
        governance_action.executed = true;
        
        // Remove from pending proposals
        let mut i = 0;
        while (i < vector::length(&treasury.pending_proposals)) {
            if (*vector::borrow(&treasury.pending_proposals, i) == governance_action.proposal_id) {
                vector::remove(&mut treasury.pending_proposals, i);
                break
            };
            i = i + 1;
        };
        
        // Execute based on action type
        if (governance_action.action_type == ACTION_ALLOCATE_FUNDS) {
            // Implementation would handle fund allocation
        } else if (governance_action.action_type == ACTION_UPDATE_STRATEGY) {
            // Implementation would handle strategy updates  
        } else {
            // Handle other action types
        };
        
        event::emit(GovernanceActionExecuted {
            action_id,
            executed_by: tx_context::sender(ctx),
            final_signatures: governance_action.current_signatures,
            timestamp: tx_context::epoch(ctx),
        });
    }

    // =============== Economic Mechanism Functions ===============
    
    /// Create staking position for validator (called from governance module)
    public fun create_validator_staking_position(
        treasury: &mut Treasury,
        validator_address: address,
        stake_amount: u64,
        ctx: &mut TxContext,
    ) {
        // Allow updating existing staking position or creating new one
        // This handles both genesis validators and regular validators
        if (table::contains(&treasury.staking_pools, validator_address)) {
            // Update existing position
            update_staking_position_stake(treasury, validator_address, stake_amount, ctx);
            return
        };
        
        // Get reward rate for validators (use staking pool rate)
        let reward_rate = if (table::contains(&treasury.reward_rates, POOL_STAKING)) {
            *table::borrow(&treasury.reward_rates, POOL_STAKING)
        } else {
            800 // Default 8% annual for validators
        };
        
        // Create staking position for validator
        let staking_position = StakingPosition {
            staker: validator_address,
            amount: stake_amount,
            start_epoch: tx_context::epoch(ctx),
            lock_period: MIN_STAKING_PERIOD, // Minimum lock period for validators
            reward_rate,
            accumulated_rewards: 0,
            last_claim_epoch: tx_context::epoch(ctx),
            auto_compound: false, // Validators start with manual reward claims
        };
        
        // Add to staking pools
        table::add(&mut treasury.staking_pools, validator_address, staking_position);
        
        // Update total staked amount
        treasury.total_staked = treasury.total_staked + stake_amount;
        
        // Ensure staking pool exists and add the stake amount to it
        if (!table::contains(&treasury.pools, POOL_STAKING)) {
            // Create staking pool if it doesn't exist
            let staking_pool = TreasuryPool {
                pool_type: POOL_STAKING,
                balance: balance::zero(),
                allocated_amount: 0,
                reserved_amount: 0,
                yield_accumulated: 0,
                last_yield_calculation: 0,
                withdrawal_history: vector::empty(),
                pool_strategy: STRATEGY_CONSERVATIVE,
                performance_metrics: PoolMetrics {
                    total_deposits: 0,
                    total_withdrawals: 0,
                    total_yield: 0,
                    average_balance: 0,
                    utilization_rate: 0,
                    performance_score: 5000,
                },
                last_updated: 0,
            };
            table::add(&mut treasury.pools, POOL_STAKING, staking_pool);
        };
        
        // Update staking pool allocation tracking
        let staking_pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        staking_pool.allocated_amount = staking_pool.allocated_amount + stake_amount;
        staking_pool.performance_metrics.total_deposits = staking_pool.performance_metrics.total_deposits + stake_amount;
    }
    
    /// Update staking position when validator adds more stake
    public fun update_staking_position_stake(
        treasury: &mut Treasury,
        validator_address: address,
        additional_stake: u64,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&treasury.staking_pools, validator_address), E_INVALID_STAKING_PARAMS);
        
        let staking_position = table::borrow_mut(&mut treasury.staking_pools, validator_address);
        
        // Calculate and accumulate any pending rewards before updating stake amount
        let current_epoch = tx_context::epoch(ctx);
        let pending_rewards = calculate_staking_rewards(staking_position, current_epoch);
        staking_position.accumulated_rewards = pending_rewards;
        staking_position.last_claim_epoch = current_epoch;
        
        // Update stake amount
        staking_position.amount = staking_position.amount + additional_stake;
        
        // Update treasury totals
        treasury.total_staked = treasury.total_staked + additional_stake;
        
        // Update staking pool allocation
        let staking_pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        staking_pool.allocated_amount = staking_pool.allocated_amount + additional_stake;
        staking_pool.performance_metrics.total_deposits = staking_pool.performance_metrics.total_deposits + additional_stake;
    }
    
    /// Remove staking position when validator withdraws stake
    public fun reduce_staking_position_stake(
        treasury: &mut Treasury,
        validator_address: address,
        stake_reduction: u64,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&treasury.staking_pools, validator_address), E_INVALID_STAKING_PARAMS);
        
        let staking_position = table::borrow_mut(&mut treasury.staking_pools, validator_address);
        assert!(staking_position.amount >= stake_reduction, E_INSUFFICIENT_BALANCE);
        
        // Calculate and preserve any pending rewards
        let current_epoch = tx_context::epoch(ctx);
        let pending_rewards = calculate_staking_rewards(staking_position, current_epoch);
        staking_position.accumulated_rewards = pending_rewards;
        staking_position.last_claim_epoch = current_epoch;
        
        // Reduce stake amount
        staking_position.amount = staking_position.amount - stake_reduction;
        
        // If stake goes to zero, remove the position entirely
        if (staking_position.amount == 0) {
            let _removed_position = table::remove(&mut treasury.staking_pools, validator_address);
        };
        
        // Update treasury totals
        treasury.total_staked = treasury.total_staked - stake_reduction;
        
        // Update staking pool allocation
        let staking_pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        staking_pool.allocated_amount = staking_pool.allocated_amount - stake_reduction;
        staking_pool.performance_metrics.total_withdrawals = staking_pool.performance_metrics.total_withdrawals + stake_reduction;
    }
    
    /// Calculate and distribute staking rewards
    public fun calculate_and_distribute_staking_rewards(
        treasury: &mut Treasury,
        epoch: u64,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        // Get all stakers (simplified - in production would iterate through staking_pools table)
        // This would be called periodically by the platform
        
        let reward_pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        let available_rewards = balance::value(&reward_pool.balance);
        
        if (available_rewards == 0) {
            return
        };
        
        // Calculate total rewards to distribute this epoch
        let epoch_reward_rate = get_epoch_reward_rate(treasury, POOL_STAKING);
        let total_rewards_to_distribute = (treasury.total_staked * epoch_reward_rate) / (BASIS_POINTS * ANNUAL_EPOCHS);
        
        if (total_rewards_to_distribute == 0 || total_rewards_to_distribute > available_rewards) {
            return
        };
        
        // Mark that staking rewards were calculated
        treasury.total_rewards_distributed = treasury.total_rewards_distributed + total_rewards_to_distribute;
        
        event::emit(YieldCalculated {
            pool_type: POOL_STAKING,
            yield_amount: total_rewards_to_distribute,
            yield_rate: epoch_reward_rate,
            calculation_period: epoch,
            strategy_used: STRATEGY_CONSERVATIVE,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Calculate yield for specified pool
    public fun calculate_pool_yield(
        treasury: &mut Treasury,
        pool_type: u8,
        clock: &Clock,
    ) {
        assert!(table::contains(&treasury.pools, pool_type), E_POOL_NOT_FOUND);
        
        let pool = table::borrow_mut(&mut treasury.pools, pool_type);
        let current_time = clock::timestamp_ms(clock);
        
        // Skip if recently calculated
        if (current_time - pool.last_yield_calculation < treasury.treasury_config.yield_calculation_frequency) {
            return
        };
        
        let pool_balance = balance::value(&pool.balance);
        if (pool_balance == 0) {
            return
        };
        
        // Get yield rate for this pool type
        let annual_yield_rate = if (table::contains(&treasury.reward_rates, pool_type)) {
            *table::borrow(&treasury.reward_rates, pool_type)
        } else {
            500 // Default 5% annual yield
        };
        
        // Calculate daily yield
        let time_elapsed = current_time - pool.last_yield_calculation;
        let daily_yield_rate = annual_yield_rate / ANNUAL_EPOCHS;
        let epochs_elapsed = time_elapsed / EPOCH_DURATION_MS;
        
        let yield_amount = (pool_balance * daily_yield_rate * epochs_elapsed) / BASIS_POINTS;
        
        if (yield_amount > 0) {
            pool.yield_accumulated = pool.yield_accumulated + yield_amount;
            pool.performance_metrics.total_yield = pool.performance_metrics.total_yield + yield_amount;
            treasury.total_yield_generated = treasury.total_yield_generated + yield_amount;
        };
        
        pool.last_yield_calculation = current_time;
        
        event::emit(YieldCalculated {
            pool_type,
            yield_amount,
            yield_rate: annual_yield_rate,
            calculation_period: epochs_elapsed,
            strategy_used: pool.pool_strategy,
            timestamp: current_time,
        });
    }

    /// Create staking position for user
    public fun create_staking_position(
        treasury: &mut Treasury,
        stake: Coin<SUI>,
        lock_period: u64,
        auto_compound: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let staker = tx_context::sender(ctx);
        let stake_amount = coin::value(&stake);
        assert!(stake_amount > 0, E_INVALID_AMOUNT);
        assert!(lock_period >= MIN_STAKING_PERIOD, E_INVALID_STAKING_PARAMS);
        
        // Check if staker already has a position
        if (table::contains(&treasury.staking_pools, staker)) {
            // Add to existing position
            let existing_position = table::borrow_mut(&mut treasury.staking_pools, staker);
            existing_position.amount = existing_position.amount + stake_amount;
        } else {
            // Create new position
            let reward_rate = if (table::contains(&treasury.reward_rates, POOL_STAKING)) {
                *table::borrow(&treasury.reward_rates, POOL_STAKING)
            } else {
                800 // Default 8% annual
            };
            
            let staking_position = StakingPosition {
                staker,
                amount: stake_amount,
                start_epoch: tx_context::epoch(ctx),
                lock_period,
                reward_rate,
                accumulated_rewards: 0,
                last_claim_epoch: tx_context::epoch(ctx),
                auto_compound,
            };
            
            table::add(&mut treasury.staking_pools, staker, staking_position);
        };
        
        // Add stake to staking pool
        let stake_balance = coin::into_balance(stake);
        let staking_pool = table::borrow_mut(&mut treasury.pools, POOL_STAKING);
        balance::join(&mut staking_pool.balance, stake_balance);
        
        treasury.total_staked = treasury.total_staked + stake_amount;
        
        event::emit(FundsDeposited {
            pool_type: POOL_STAKING,
            amount: stake_amount,
            depositor: staker,
            source: string::utf8(b"Staking Deposit"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Revenue Distribution Functions ===============
    
    /// Distribute revenue based on automated schedules
    public fun execute_revenue_distribution(
        treasury: &mut Treasury,
        schedule_id: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&treasury.distribution_schedules, schedule_id), E_POOL_NOT_FOUND);
        
        let schedule = table::borrow_mut(&mut treasury.distribution_schedules, schedule_id);
        assert!(schedule.active, E_INVALID_GOVERNANCE_ACTION);
        
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= schedule.next_distribution, E_COOLDOWN_PERIOD);
        
        let pool = table::borrow_mut(&mut treasury.pools, schedule.pool_type);
        let available_balance = balance::value(&pool.balance);
        
        assert!(available_balance >= schedule.amount_per_distribution, E_INSUFFICIENT_BALANCE);
        
        // Calculate individual distributions
        let total_weight = utils::vector_sum(&schedule.distribution_weights);
        assert!(total_weight > 0, E_INVALID_ALLOCATION);
        
        let mut i = 0;
        let mut total_distributed = 0;
        while (i < vector::length(&schedule.recipients)) {
            let recipient = *vector::borrow(&schedule.recipients, i);
            let weight = *vector::borrow(&schedule.distribution_weights, i);
            let distribution_amount = (schedule.amount_per_distribution * weight) / total_weight;
            
            if (distribution_amount > 0) {
                let distribution_balance = balance::split(&mut pool.balance, distribution_amount);
                let distribution_coin = coin::from_balance(distribution_balance, ctx);
                transfer::public_transfer(distribution_coin, recipient);
                
                total_distributed = total_distributed + distribution_amount;
            };
            
            i = i + 1;
        };
        
        // Update schedule
        schedule.last_distribution = current_time;
        schedule.next_distribution = current_time + schedule.frequency * EPOCH_DURATION_MS;
        
        // Update pool metrics
        pool.performance_metrics.total_withdrawals = pool.performance_metrics.total_withdrawals + total_distributed;
        treasury.total_withdrawals = treasury.total_withdrawals + total_distributed;
        
        event::emit(RevenueDistributed {
            distribution_schedule_id: schedule_id,
            total_amount: total_distributed,
            recipients_count: vector::length(&schedule.recipients),
            distribution_method: string::utf8(b"Automated Schedule"),
            timestamp: current_time,
        });
    }

    // =============== Audit and Compliance Functions ===============
    
    /// Perform comprehensive treasury audit
    public fun perform_treasury_audit(
        auditor_cap: &TreasuryAuditorCap,
        treasury: &mut Treasury,
        audit_scope: vector<u8>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(auditor_cap.reporting_authority, E_NOT_AUTHORIZED);
        
        let mut findings_count = 0;
        let mut recommendations = vector::empty<String>();
        
        // Audit each pool in scope
        let mut i = 0;
        while (i < vector::length(&audit_scope)) {
            let pool_type = *vector::borrow(&audit_scope, i);
            
            if (vector::contains(&auditor_cap.audit_scope, &pool_type) && 
                table::contains(&treasury.pools, pool_type)) {
                
                let pool = table::borrow(&treasury.pools, pool_type);
                
                // Check pool health
                let balance_check = audit_pool_balance(pool);
                let utilization_check = audit_pool_utilization(pool);
                let performance_check = audit_pool_performance(pool);
                
                if (!balance_check) {
                    findings_count = findings_count + 1;
                    vector::push_back(&mut recommendations, string::utf8(b"Pool balance below minimum threshold"));
                };
                
                if (!utilization_check) {
                    findings_count = findings_count + 1;
                    vector::push_back(&mut recommendations, string::utf8(b"Pool utilization rate suboptimal"));
                };
                
                if (!performance_check) {
                    findings_count = findings_count + 1;
                    vector::push_back(&mut recommendations, string::utf8(b"Pool performance below target"));
                };
            };
            
            i = i + 1;
        };
        
        // Overall rating (simplified)
        let overall_rating = if (findings_count == 0) {
            10 // Excellent
        } else if (findings_count <= 2) {
            8  // Good
        } else if (findings_count <= 5) {
            6  // Satisfactory
        } else {
            4  // Needs improvement
        };
        
        // Add audit entry
        let audit_entry = AuditEntry {
            audit_type: string::utf8(b"Comprehensive Treasury Audit"),
            description: string::utf8(b"Full treasury system audit"),
            auditor: tx_context::sender(ctx),
            finding_level: if (overall_rating >= 8) { 1 } else if (overall_rating >= 6) { 2 } else { 3 },
            resolved: overall_rating >= 8,
            timestamp: clock::timestamp_ms(clock),
        };
        vector::push_back(&mut treasury.audit_logs, audit_entry);
        
        event::emit(TreasuryAudited {
            auditor: tx_context::sender(ctx),
            audit_scope,
            findings_count,
            overall_rating,
            recommendations,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Perform compliance check for specific requirement
    public fun perform_compliance_check(
        auditor_cap: &TreasuryAuditorCap,
        treasury: &mut Treasury,
        check_type: String,
        expected_result: bool,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(auditor_cap.reporting_authority, E_NOT_AUTHORIZED);
        
        // Perform specific compliance check
        let result = execute_compliance_check(treasury, &check_type);
        
        // Update compliance tracking
        if (table::contains(&treasury.compliance_checks, check_type)) {
            *table::borrow_mut(&mut treasury.compliance_checks, check_type) = result;
        } else {
            table::add(&mut treasury.compliance_checks, check_type, result);
        };
        
        event::emit(ComplianceCheckCompleted {
            check_type,
            result,
            details: if (result == expected_result) {
                string::utf8(b"Compliance check passed")
            } else {
                string::utf8(b"Compliance check failed - requires attention")
            },
            checked_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Helper Functions ===============
    
    /// Check daily withdrawal limit for pool
    fun check_daily_withdrawal_limit(
        treasury: &Treasury,
        pool_type: u8,
        amount: u64,
        clock: &Clock,
    ): bool {
        if (!table::contains(&treasury.withdrawal_limits, pool_type)) {
            return true // No limit set
        };
        
        let daily_limit = *table::borrow(&treasury.withdrawal_limits, pool_type);
        let current_day = clock::timestamp_ms(clock) / 86400000; // Convert to days
        
        let current_daily_total = if (table::contains(&treasury.daily_withdrawals, current_day)) {
            *table::borrow(&treasury.daily_withdrawals, current_day)
        } else {
            0
        };
        
        (current_daily_total + amount) <= daily_limit
    }

    /// Update daily withdrawal tracking
    fun update_daily_withdrawal_tracking(
        treasury: &mut Treasury,
        amount: u64,
        clock: &Clock,
    ) {
        let current_day = clock::timestamp_ms(clock) / 86400000;
        
        if (table::contains(&treasury.daily_withdrawals, current_day)) {
            let current_total = table::borrow_mut(&mut treasury.daily_withdrawals, current_day);
            *current_total = *current_total + amount;
        } else {
            table::add(&mut treasury.daily_withdrawals, current_day, amount);
        };
        
        treasury.last_withdrawal_day = current_day;
    }

    /// Calculate staking rewards for position
    fun calculate_staking_rewards(
        position: &StakingPosition,
        current_epoch: u64,
    ): u64 {
        let epochs_staked = current_epoch - position.last_claim_epoch;
        if (epochs_staked == 0) {
            return position.accumulated_rewards
        };
        
        let epoch_reward_rate = position.reward_rate / ANNUAL_EPOCHS;
        let epoch_rewards = (position.amount * epoch_reward_rate * epochs_staked) / BASIS_POINTS;
        
        position.accumulated_rewards + epoch_rewards
    }

    /// Get epoch reward rate for pool
    fun get_epoch_reward_rate(treasury: &Treasury, pool_type: u8): u64 {
        if (table::contains(&treasury.reward_rates, pool_type)) {
            *table::borrow(&treasury.reward_rates, pool_type) / ANNUAL_EPOCHS
        } else {
            0
        }
    }

    /// Check if yield calculation is needed
    fun should_calculate_yield(treasury: &Treasury, pool_type: u8, clock: &Clock): bool {
        if (!table::contains(&treasury.pools, pool_type)) {
            return false
        };
        
        let pool = table::borrow(&treasury.pools, pool_type);
        let current_time = clock::timestamp_ms(clock);
        
        (current_time - pool.last_yield_calculation) >= treasury.treasury_config.yield_calculation_frequency
    }

    /// Update pool performance score based on recent activity
    fun update_pool_performance_score(pool: &mut TreasuryPool, positive_event: bool) {
        let adjustment = if (positive_event) { 100 } else { 50 }; // +1% or -0.5%
        
        if (positive_event) {
            let new_score = pool.performance_metrics.performance_score + adjustment;
            pool.performance_metrics.performance_score = if (new_score < 10000) { new_score } else { 10000 };
        } else {
            pool.performance_metrics.performance_score = if (pool.performance_metrics.performance_score > adjustment) {
                pool.performance_metrics.performance_score - adjustment
            } else {
                0
            };
        };
    }

    /// Execute pool rebalancing (simplified implementation)
    fun execute_pool_rebalancing(
        _treasury: &mut Treasury,
        _from_pools: &vector<u8>,
        _to_pools: &vector<u8>,
        _amounts: &vector<u64>,
    ) {
        // Simplified rebalancing - in production would need sophisticated balancing algorithm
        // This is a placeholder for the complex rebalancing logic
    }

    /// Mark emergency audit entries as resolved
    fun mark_emergency_audits_resolved(audit_logs: &mut vector<AuditEntry>, _current_time: u64) {
        let mut i = 0;
        while (i < vector::length(audit_logs)) {
            let audit_entry = vector::borrow_mut(audit_logs, i);
            if (*string::as_bytes(&audit_entry.audit_type) == b"Emergency Mode Activation") {
                audit_entry.resolved = true;
            };
            i = i + 1;
        };
    }

    /// Record treasury transaction for audit trail
    fun record_treasury_transaction(
        treasury: &mut Treasury,
        transaction_type: u8,
        pool_involved: Option<u8>,
        amount: u64,
        counterparty: address,
        description: String,
        metadata: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_epoch = tx_context::epoch(ctx);
        
        let transaction = TreasuryTransaction {
            transaction_type,
            pool_involved,
            amount,
            counterparty,
            description,
            metadata,
            timestamp: clock::timestamp_ms(clock),
            block_height: tx_context::epoch(ctx),
        };
        
        if (!table::contains(&treasury.transaction_history, current_epoch)) {
            table::add(&mut treasury.transaction_history, current_epoch, vector::empty());
        };
        
        let epoch_transactions = table::borrow_mut(&mut treasury.transaction_history, current_epoch);
        vector::push_back(epoch_transactions, transaction);
    }


    /// Audit pool balance health
    fun audit_pool_balance(pool: &TreasuryPool): bool {
        // Check if pool has sufficient balance for operations
        balance::value(&pool.balance) >= 1_000_000_000 // Minimum 1 SUI
    }

    /// Audit pool utilization rate
    fun audit_pool_utilization(pool: &TreasuryPool): bool {
        // Check if pool utilization is within acceptable range
        pool.performance_metrics.utilization_rate >= 3000 && // At least 30%
        pool.performance_metrics.utilization_rate <= 9000    // At most 90%
    }

    /// Audit pool performance
    fun audit_pool_performance(pool: &TreasuryPool): bool {
        // Check if pool performance meets target
        pool.performance_metrics.performance_score >= 5000 // At least 50%
    }

    /// Execute specific compliance check
    fun execute_compliance_check(treasury: &Treasury, check_type: &String): bool {
        let check_bytes = *string::as_bytes(check_type);
        
        if (check_bytes == b"emergency_mode_off") {
            !treasury.emergency_mode
        } else if (check_bytes == b"sufficient_reserves") {
            balance::value(&treasury.total_balance) >= 10_000_000_000_000 // 10,000 SUI minimum
        } else if (check_bytes == b"governance_active") {
            vector::length(&treasury.pending_proposals) <= 10 // Not too many pending
        } else {
            true // Default pass for unknown checks
        }
    }

    // =============== Read Functions ===============
    
    /// Get total treasury balance
    public fun get_total_balance(treasury: &Treasury): u64 {
        balance::value(&treasury.total_balance)
    }

    /// Get specific pool balance
    public fun get_pool_balance(treasury: &Treasury, pool_type: u8): u64 {
        if (table::contains(&treasury.pools, pool_type)) {
            let pool = table::borrow(&treasury.pools, pool_type);
            balance::value(&pool.balance)
        } else {
            0
        }
    }

    /// Get pool performance metrics
    public fun get_pool_metrics(treasury: &Treasury, pool_type: u8): (u64, u64, u64, u64, u64) {
        if (table::contains(&treasury.pools, pool_type)) {
            let pool = table::borrow(&treasury.pools, pool_type);
            (
                pool.performance_metrics.total_deposits,
                pool.performance_metrics.total_withdrawals,
                pool.performance_metrics.total_yield,
                pool.performance_metrics.utilization_rate,
                pool.performance_metrics.performance_score
            )
        } else {
            (0, 0, 0, 0, 0)
        }
    }

    /// Get treasury statistics
    public fun get_treasury_statistics(treasury: &Treasury): (u64, u64, u64, u64, u64) {
        (
            treasury.total_deposits,
            treasury.total_withdrawals,
            treasury.total_rewards_distributed,
            treasury.total_fees_collected,
            treasury.total_yield_generated
        )
    }

    /// Check if emergency mode is active
    public fun is_emergency_mode(treasury: &Treasury): bool {
        treasury.emergency_mode
    }

    /// Get staking position for user
    public fun get_staking_position(treasury: &Treasury, staker: address): (u64, u64, u64, u64) {
        if (table::contains(&treasury.staking_pools, staker)) {
            let position = table::borrow(&treasury.staking_pools, staker);
            (
                position.amount,
                position.start_epoch,
                position.accumulated_rewards,
                position.reward_rate
            )
        } else {
            (0, 0, 0, 0)
        }
    }

    /// Get pool allocation percentage
    public fun get_pool_allocation(treasury: &Treasury, pool_type: u8): u64 {
        if (table::contains(&treasury.pool_allocations, pool_type)) {
            *table::borrow(&treasury.pool_allocations, pool_type)
        } else {
            0
        }
    }

    /// Get governance action status
    public fun get_governance_action_status(treasury: &Treasury, action_id: ID): (bool, u64, u64) {
        if (table::contains(&treasury.governance_actions, action_id)) {
            let action = table::borrow(&treasury.governance_actions, action_id);
            (
                action.executed,
                vector::length(&action.current_signatures),
                (action.required_signatures as u64)
            )
        } else {
            (false, 0, 0)
        }
    }

    /// Get treasury configuration
    public fun get_treasury_config(treasury: &Treasury): (u64, u64, u64, bool, bool) {
        (
            treasury.treasury_config.min_pool_balance,
            treasury.treasury_config.max_single_withdrawal,
            treasury.treasury_config.governance_delay,
            treasury.treasury_config.multisig_enabled,
            treasury.treasury_config.auto_rebalancing
        )
    }

    /// Get pending proposal count
    public fun get_pending_proposal_count(treasury: &Treasury): u64 {
        vector::length(&treasury.pending_proposals)
    }

    /// Get audit log count
    public fun get_audit_log_count(treasury: &Treasury): u64 {
        vector::length(&treasury.audit_logs)
    }

    /// Get treasury version and last update
    public fun get_treasury_version_info(treasury: &Treasury): (u64, u64) {
        (treasury.version, treasury.last_update)
    }

    // =============== Test Functions ===============
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_test_treasury_pool(pool_type: u8, balance_amount: u64, ctx: &mut TxContext): TreasuryPool {
        TreasuryPool {
            pool_type,
            balance: balance::create_for_testing(balance_amount),
            allocated_amount: balance_amount,
            reserved_amount: 0,
            yield_accumulated: 0,
            last_yield_calculation: 0,
            withdrawal_history: vector::empty(),
            pool_strategy: STRATEGY_CONSERVATIVE,
            performance_metrics: PoolMetrics {
                total_deposits: balance_amount,
                total_withdrawals: 0,
                total_yield: 0,
                average_balance: balance_amount,
                utilization_rate: 5000,
                performance_score: 7500,
            },
            last_updated: 0,
        }
    }

    #[test_only]
    public fun create_test_staking_position(
        staker: address,
        amount: u64,
        start_epoch: u64,
        reward_rate: u64
    ): StakingPosition {
        StakingPosition {
            staker,
            amount,
            start_epoch,
            lock_period: MIN_STAKING_PERIOD,
            reward_rate,
            accumulated_rewards: 0,
            last_claim_epoch: start_epoch,
            auto_compound: false,
        }
    }
}