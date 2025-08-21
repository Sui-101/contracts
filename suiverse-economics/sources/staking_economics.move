module suiverse_economics::staking_economics {
    use std::string::{Self as string, String};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{ID, UID};
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::math;

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INSUFFICIENT_STAKE: u64 = 2;
    const E_INVALID_AMOUNT: u64 = 3;
    const E_VALIDATOR_NOT_ACTIVE: u64 = 4;
    const E_INSUFFICIENT_BALANCE: u64 = 5;
    const E_STAKE_BELOW_MINIMUM: u64 = 6;
    const E_INVALID_TIER: u64 = 7;
    const E_SLASHING_IN_PROGRESS: u64 = 8;
    const E_CERTIFICATE_NOT_FOUND: u64 = 9;

    // Stake tiers
    const TIER_STARTER: u8 = 1;      // 10 SUI
    const TIER_BASIC: u8 = 2;        // 50 SUI
    const TIER_BRONZE: u8 = 3;       // 100 SUI
    const TIER_SILVER: u8 = 4;       // 500 SUI
    const TIER_GOLD: u8 = 5;         // 1,000 SUI
    const TIER_PLATINUM: u8 = 6;     // 5,000 SUI

    // Violation types for slashing
    const VIOLATION_LAZY_VALIDATION: u8 = 1;      // 10% slash
    const VIOLATION_WRONG_CONSENSUS: u8 = 2;      // 5% slash
    const VIOLATION_MALICIOUS_APPROVAL: u8 = 3;   // 50% slash
    const VIOLATION_COLLUSION: u8 = 4;            // 100% slash

    // Admin capability
    public struct AdminCap has key {
        id: UID,
    }

    // Stake tier configuration
    public struct StakeTier has store {
        tier_level: u8,
        minimum_stake: u64,
        weight_multiplier: u64,        // Basis points (1x = 10000)
        slash_protection: u8,          // Percentage protection
        reward_multiplier: u64,        // Basis points (1x = 10000)
    }

    // Staking configuration
    public struct StakingConfig has key {
        id: UID,
        minimum_stake: u64,                    // Initially 10 SUI
        stake_tiers: vector<StakeTier>,
        
        // Slashing rules
        lazy_validation_slash: u8,             // 10%
        wrong_consensus_slash: u8,             // 5%
        malicious_approval_slash: u8,          // 50%
        collusion_slash: u8,                   // 100%
        
        // Bootstrap protection
        max_slash_cap: u8,                     // Initially 50%
        min_remaining_stake_ratio: u8,         // Never slash below this % of minimum
        
        // Certificate boost
        certificate_boost_percentage: u8,       // 50% boost for boosted certificates
        
        // Last governance update
        last_update_proposal: ID,
    }

    // Certificate information for validators
    public struct CertificateInfo has store {
        certificate_type: String,
        certificate_id: ID,
        current_value: u64,
        boosted: bool,
        acquisition_epoch: u64,
    }

    // Validator stake profile
    public struct ValidatorStake has key {
        id: UID,
        validator: address,
        
        // Staking information
        total_stake: u64,
        active_stake: u64,
        pending_stake: Balance<SUI>,
        
        // Tier and multipliers
        current_tier: u8,
        weight_multiplier: u64,
        reward_multiplier: u64,
        
        // Knowledge proof (PoK)
        certificates: vector<CertificateInfo>,
        knowledge_score: u64,
        
        // Performance tracking
        validation_accuracy: u64,           // Out of 10000 (100.00%)
        total_validations: u64,
        correct_validations: u64,
        slashed_count: u64,
        
        // Status
        active: bool,
        suspended: bool,
        suspension_end_epoch: u64,
        
        // Staking history
        stake_history: vector<StakeEvent>,
        last_stake_change: u64,
    }

    // Stake event for history tracking
    public struct StakeEvent has store {
        event_type: u8,                // 1: Stake, 2: Unstake, 3: Slash, 4: Reward
        amount: u64,
        epoch: u64,
        tier_before: u8,
        tier_after: u8,
    }

    // Certificate value tracking
    public struct CertificateValue has key, store {
        id: UID,
        certificate_type: String,
        base_value: u64,
        current_value: u64,
        total_issued: u64,
        active_validators_holding: u64,
        recent_exam_pass_rate: u64,
        scarcity_multiplier: u64,
        difficulty_multiplier: u64,
        age_decay: u64,
        last_rebalance: u64,
    }

    // Slashing record
    public struct SlashingRecord has key, store {
        id: UID,
        validator: address,
        violation_type: u8,
        original_amount: u64,
        slashed_amount: u64,
        protection_applied: u64,
        epoch: u64,
        evidence_hash: vector<u8>,
        processed: bool,
    }

    // Stake pool for managing total stakes
    public struct StakePool has key {
        id: UID,
        total_staked: u64,
        active_validators: u64,
        total_slashed: u64,
        slashed_funds: Balance<SUI>,
        reward_pool: Balance<SUI>,
        pending_rewards: u64,
    }

    // Events
    public struct ValidatorStakedEvent has copy, drop {
        validator: address,
        amount: u64,
        new_total_stake: u64,
        new_tier: u8,
        epoch: u64,
    }

    public struct ValidatorUnstakedEvent has copy, drop {
        validator: address,
        amount: u64,
        remaining_stake: u64,
        new_tier: u8,
        epoch: u64,
    }

    public struct ValidatorSlashedEvent has copy, drop {
        validator: address,
        violation_type: u8,
        original_amount: u64,
        slashed_amount: u64,
        protection_applied: u64,
        epoch: u64,
    }

    public struct CertificateAddedEvent has copy, drop {
        validator: address,
        certificate_type: String,
        certificate_id: ID,
        value: u64,
        boosted: bool,
        epoch: u64,
    }

    public struct CertificateValueUpdatedEvent has copy, drop {
        certificate_type: String,
        old_value: u64,
        new_value: u64,
        rebalance_epoch: u64,
    }

    public struct ValidatorWeightUpdatedEvent has copy, drop {
        validator: address,
        old_weight: u64,
        new_weight: u64,
        knowledge_score: u64,
        stake_multiplier: u64,
        epoch: u64,
    }

    // Initialize the staking economics system
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        // Initialize stake tiers
        let stake_tiers = vector[
            StakeTier {
                tier_level: TIER_STARTER,
                minimum_stake: 10_000_000_000,      // 10 SUI
                weight_multiplier: 10000,           // 1.0x
                slash_protection: 0,                // 0% protection
                reward_multiplier: 10000,           // 1.0x
            },
            StakeTier {
                tier_level: TIER_BASIC,
                minimum_stake: 50_000_000_000,      // 50 SUI
                weight_multiplier: 13000,           // 1.3x
                slash_protection: 10,               // 10% protection
                reward_multiplier: 11000,           // 1.1x
            },
            StakeTier {
                tier_level: TIER_BRONZE,
                minimum_stake: 100_000_000_000,     // 100 SUI
                weight_multiplier: 15000,           // 1.5x
                slash_protection: 20,               // 20% protection
                reward_multiplier: 12000,           // 1.2x
            },
            StakeTier {
                tier_level: TIER_SILVER,
                minimum_stake: 500_000_000_000,     // 500 SUI
                weight_multiplier: 20000,           // 2.0x
                slash_protection: 30,               // 30% protection
                reward_multiplier: 15000,           // 1.5x
            },
            StakeTier {
                tier_level: TIER_GOLD,
                minimum_stake: 1000_000_000_000,    // 1,000 SUI
                weight_multiplier: 25000,           // 2.5x
                slash_protection: 40,               // 40% protection
                reward_multiplier: 18000,           // 1.8x
            },
            StakeTier {
                tier_level: TIER_PLATINUM,
                minimum_stake: 5000_000_000_000,    // 5,000 SUI
                weight_multiplier: 30000,           // 3.0x
                slash_protection: 50,               // 50% protection
                reward_multiplier: 20000,           // 2.0x
            },
        ];

        let staking_config = StakingConfig {
            id: object::new(ctx),
            minimum_stake: 10_000_000_000,          // 10 SUI
            stake_tiers,
            lazy_validation_slash: 10,              // 10%
            wrong_consensus_slash: 5,               // 5%
            malicious_approval_slash: 50,           // 50%
            collusion_slash: 100,                   // 100%
            max_slash_cap: 50,                      // 50% max slash during bootstrap
            min_remaining_stake_ratio: 100,         // Never slash below 100% of minimum
            certificate_boost_percentage: 50,       // 50% boost
            last_update_proposal: object::id_from_address(@0x0),
        };

        let stake_pool = StakePool {
            id: object::new(ctx),
            total_staked: 0,
            active_validators: 0,
            total_slashed: 0,
            slashed_funds: balance::zero(),
            reward_pool: balance::zero(),
            pending_rewards: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(staking_config);
        transfer::share_object(stake_pool);
    }

    // Stake SUI to become a validator
    public fun stake_as_validator(
        staking_config: &StakingConfig,
        stake_pool: &mut StakePool,
        stake_payment: Coin<SUI>,
        ctx: &mut TxContext
    ): ValidatorStake {
        let stake_amount = coin::value(&stake_payment);
        assert!(stake_amount >= staking_config.minimum_stake, E_INSUFFICIENT_STAKE);

        let stake_balance = coin::into_balance(stake_payment);
        let current_epoch = tx_context::epoch(ctx);
        let validator_address = tx_context::sender(ctx);

        // Determine tier
        let tier = calculate_tier(&staking_config.stake_tiers, stake_amount);
        let tier_info = get_tier_info(&staking_config.stake_tiers, tier);

        let validator_stake = ValidatorStake {
            id: object::new(ctx),
            validator: validator_address,
            total_stake: stake_amount,
            active_stake: stake_amount,
            pending_stake: balance::zero(),
            current_tier: tier,
            weight_multiplier: tier_info.weight_multiplier,
            reward_multiplier: tier_info.reward_multiplier,
            certificates: vector::empty(),
            knowledge_score: 0,
            validation_accuracy: 10000,               // Start at 100%
            total_validations: 0,
            correct_validations: 0,
            slashed_count: 0,
            active: true,
            suspended: false,
            suspension_end_epoch: 0,
            stake_history: vector[
                StakeEvent {
                    event_type: 1,                    // Stake
                    amount: stake_amount,
                    epoch: current_epoch,
                    tier_before: 0,
                    tier_after: tier,
                }
            ],
            last_stake_change: current_epoch,
        };

        // Update pool
        stake_pool.total_staked = stake_pool.total_staked + stake_amount;
        stake_pool.active_validators = stake_pool.active_validators + 1;
        balance::join(&mut stake_pool.reward_pool, stake_balance);

        event::emit(ValidatorStakedEvent {
            validator: validator_address,
            amount: stake_amount,
            new_total_stake: stake_amount,
            new_tier: tier,
            epoch: current_epoch,
        });

        validator_stake
    }

    // Add additional stake
    public fun add_stake(
        staking_config: &StakingConfig,
        stake_pool: &mut StakePool,
        validator_stake: &mut ValidatorStake,
        additional_stake: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        assert!(validator_stake.active, E_VALIDATOR_NOT_ACTIVE);
        
        let stake_amount = coin::value(&additional_stake);
        let stake_balance = coin::into_balance(additional_stake);
        let current_epoch = tx_context::epoch(ctx);

        let old_tier = validator_stake.current_tier;
        let old_total = validator_stake.total_stake;

        // Add to pending stake
        balance::join(&mut validator_stake.pending_stake, stake_balance);
        validator_stake.total_stake = validator_stake.total_stake + stake_amount;
        validator_stake.active_stake = validator_stake.active_stake + stake_amount;

        // Recalculate tier
        let new_tier = calculate_tier(&staking_config.stake_tiers, validator_stake.total_stake);
        if (new_tier != old_tier) {
            let tier_info = get_tier_info(&staking_config.stake_tiers, new_tier);
            validator_stake.current_tier = new_tier;
            validator_stake.weight_multiplier = tier_info.weight_multiplier;
            validator_stake.reward_multiplier = tier_info.reward_multiplier;
        };

        // Record stake event
        vector::push_back(&mut validator_stake.stake_history, StakeEvent {
            event_type: 1,                // Stake
            amount: stake_amount,
            epoch: current_epoch,
            tier_before: old_tier,
            tier_after: new_tier,
        });

        validator_stake.last_stake_change = current_epoch;

        // Update pool
        stake_pool.total_staked = stake_pool.total_staked + stake_amount;

        event::emit(ValidatorStakedEvent {
            validator: validator_stake.validator,
            amount: stake_amount,
            new_total_stake: validator_stake.total_stake,
            new_tier: new_tier,
            epoch: current_epoch,
        });
    }

    // Unstake (partial or full)
    public fun unstake(
        staking_config: &StakingConfig,
        stake_pool: &mut StakePool,
        validator_stake: &mut ValidatorStake,
        unstake_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(validator_stake.active, E_VALIDATOR_NOT_ACTIVE);
        assert!(unstake_amount <= validator_stake.active_stake, E_INSUFFICIENT_STAKE);

        let remaining_stake = validator_stake.total_stake - unstake_amount;
        let current_epoch = tx_context::epoch(ctx);
        let old_tier = validator_stake.current_tier;

        // Check minimum stake requirement if not full unstake
        if (remaining_stake > 0) {
            assert!(remaining_stake >= staking_config.minimum_stake, E_STAKE_BELOW_MINIMUM);
        };

        // Remove stake from pending first, then from reward pool
        let unstake_balance = if (balance::value(&validator_stake.pending_stake) >= unstake_amount) {
            balance::split(&mut validator_stake.pending_stake, unstake_amount)
        } else {
            let from_pending = balance::value(&validator_stake.pending_stake);
            let mut pending_balance = balance::withdraw_all(&mut validator_stake.pending_stake);
            let from_pool = unstake_amount - from_pending;
            let pool_balance = balance::split(&mut stake_pool.reward_pool, from_pool);
            balance::join(&mut pending_balance, pool_balance);
            pending_balance
        };

        // Update stake amounts
        validator_stake.total_stake = remaining_stake;
        validator_stake.active_stake = remaining_stake;

        // Recalculate tier
        let new_tier = if (remaining_stake == 0) {
            0
        } else {
            calculate_tier(&staking_config.stake_tiers, remaining_stake)
        };

        if (new_tier != old_tier && new_tier > 0) {
            let tier_info = get_tier_info(&staking_config.stake_tiers, new_tier);
            validator_stake.current_tier = new_tier;
            validator_stake.weight_multiplier = tier_info.weight_multiplier;
            validator_stake.reward_multiplier = tier_info.reward_multiplier;
        } else if (new_tier == 0) {
            validator_stake.active = false;
            stake_pool.active_validators = stake_pool.active_validators - 1;
        };

        // Record unstake event
        vector::push_back(&mut validator_stake.stake_history, StakeEvent {
            event_type: 2,                // Unstake
            amount: unstake_amount,
            epoch: current_epoch,
            tier_before: old_tier,
            tier_after: new_tier,
        });

        validator_stake.last_stake_change = current_epoch;

        // Update pool
        stake_pool.total_staked = stake_pool.total_staked - unstake_amount;

        // Transfer unstaked amount back to validator
        let unstake_coin = coin::from_balance(unstake_balance, ctx);
        transfer::public_transfer(unstake_coin, validator_stake.validator);

        event::emit(ValidatorUnstakedEvent {
            validator: validator_stake.validator,
            amount: unstake_amount,
            remaining_stake,
            new_tier,
            epoch: current_epoch,
        });
    }

    // Add certificate to validator
    public fun add_certificate(
        validator_stake: &mut ValidatorStake,
        certificate_type: String,
        certificate_id: ID,
        certificate_value: u64,
        boosted: bool,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        
        let cert_info = CertificateInfo {
            certificate_type,
            certificate_id,
            current_value: certificate_value,
            boosted,
            acquisition_epoch: current_epoch,
        };

        vector::push_back(&mut validator_stake.certificates, cert_info);
        
        // Recalculate knowledge score
        update_knowledge_score(validator_stake);

        event::emit(CertificateAddedEvent {
            validator: validator_stake.validator,
            certificate_type,
            certificate_id,
            value: certificate_value,
            boosted,
            epoch: current_epoch,
        });
    }

    // Slash validator for violations
    public fun slash_validator(
        staking_config: &StakingConfig,
        stake_pool: &mut StakePool,
        validator_stake: &mut ValidatorStake,
        violation_type: u8,
        evidence_hash: vector<u8>,
        ctx: &mut TxContext
    ): SlashingRecord {
        assert!(validator_stake.active, E_VALIDATOR_NOT_ACTIVE);
        
        let current_epoch = tx_context::epoch(ctx);
        let original_stake = validator_stake.active_stake;

        // Calculate slash percentage
        let slash_percentage = match (violation_type) {
            VIOLATION_LAZY_VALIDATION => staking_config.lazy_validation_slash,
            VIOLATION_WRONG_CONSENSUS => staking_config.wrong_consensus_slash,
            VIOLATION_MALICIOUS_APPROVAL => staking_config.malicious_approval_slash,
            VIOLATION_COLLUSION => staking_config.collusion_slash,
            _ => abort E_INVALID_AMOUNT,
        };

        // Apply tier protection
        let tier_info = get_tier_info(&staking_config.stake_tiers, validator_stake.current_tier);
        let protection = tier_info.slash_protection;
        let effective_slash = (slash_percentage * (100 - protection)) / 100;

        // Apply bootstrap cap
        let capped_slash = std::u64::min((effective_slash as u64), (staking_config.max_slash_cap as u64));

        // Calculate actual slash amount
        let calculated_slash = (original_stake * capped_slash) / 100;
        
        // Ensure minimum stake remains
        let min_stake = (staking_config.minimum_stake * (staking_config.min_remaining_stake_ratio as u64)) / 100;
        let max_allowable_slash = if (original_stake > min_stake) {
            original_stake - min_stake
        } else {
            0
        };

        let final_slash = std::u64::min(calculated_slash, max_allowable_slash);
        let protection_applied = calculated_slash - final_slash;

        // Apply slash
        if (final_slash > 0) {
            // Remove from pending stake first, then from active
            let slashed_balance = if (balance::value(&validator_stake.pending_stake) >= final_slash) {
                balance::split(&mut validator_stake.pending_stake, final_slash)
            } else {
                let from_pending = balance::value(&validator_stake.pending_stake);
                let mut pending_balance = balance::withdraw_all(&mut validator_stake.pending_stake);
                let from_active = final_slash - from_pending;
                let active_balance = balance::split(&mut stake_pool.reward_pool, from_active);
                balance::join(&mut pending_balance, active_balance);
                pending_balance
            };

            // Update validator stake
            validator_stake.total_stake = validator_stake.total_stake - final_slash;
            validator_stake.active_stake = validator_stake.active_stake - final_slash;
            validator_stake.slashed_count = validator_stake.slashed_count + 1;

            // Check if still meets minimum
            if (validator_stake.active_stake < staking_config.minimum_stake) {
                validator_stake.active = false;
                validator_stake.suspended = true;
                validator_stake.suspension_end_epoch = current_epoch + 30; // 30 epochs suspension
                stake_pool.active_validators = stake_pool.active_validators - 1;
            };

            // Add to slashed funds
            balance::join(&mut stake_pool.slashed_funds, slashed_balance);
            stake_pool.total_slashed = stake_pool.total_slashed + final_slash;

            // Reduce certificate values temporarily
            let mut i = 0;
            while (i < vector::length(&validator_stake.certificates)) {
                let cert = vector::borrow_mut(&mut validator_stake.certificates, i);
                cert.current_value = (cert.current_value * 80) / 100; // 20% reduction
                i = i + 1;
            };

            // Record slash event
            vector::push_back(&mut validator_stake.stake_history, StakeEvent {
                event_type: 3,                // Slash
                amount: final_slash,
                epoch: current_epoch,
                tier_before: validator_stake.current_tier,
                tier_after: validator_stake.current_tier,
            });
        };

        // Create slashing record
        let slashing_record = SlashingRecord {
            id: object::new(ctx),
            validator: validator_stake.validator,
            violation_type,
            original_amount: calculated_slash,
            slashed_amount: final_slash,
            protection_applied,
            epoch: current_epoch,
            evidence_hash,
            processed: true,
        };

        event::emit(ValidatorSlashedEvent {
            validator: validator_stake.validator,
            violation_type,
            original_amount: calculated_slash,
            slashed_amount: final_slash,
            protection_applied,
            epoch: current_epoch,
        });

        slashing_record
    }

    // Calculate validator weight (Knowledge × Stake × Performance)
    public fun calculate_validator_weight(
        staking_config: &StakingConfig,
        validator_stake: &ValidatorStake
    ): u64 {
        if (!validator_stake.active) {
            return 0
        };

        // Knowledge score (sum of certificate values with boosts)
        let knowledge = validator_stake.knowledge_score;
        
        // Stake multiplier (logarithmic growth)
        let base_stake = staking_config.minimum_stake / 1000; // Convert to manageable number
        let current_stake = validator_stake.active_stake / 1000;
        let stake_multiplier = if (current_stake > 0) {
            // Simplified sqrt calculation: weight based on tier multiplier
            validator_stake.weight_multiplier
        } else {
            10000 // 1.0x
        };

        // Performance multiplier (0.5x to 1.5x based on accuracy)
        let perf_multiplier = 5000 + (validator_stake.validation_accuracy / 2);

        // Total weight calculation
        let weight = (knowledge * stake_multiplier * perf_multiplier) / 100_000_000;
        
        weight
    }

    // Update knowledge score based on certificates
    fun update_knowledge_score(validator_stake: &mut ValidatorStake) {
        let mut total_score = 0u64;
        let mut i = 0;

        while (i < vector::length(&validator_stake.certificates)) {
            let cert = vector::borrow(&validator_stake.certificates, i);
            let cert_value = cert.current_value;
            
            // Apply boost if enabled
            let final_value = if (cert.boosted) {
                (cert_value * 150) / 100  // 50% boost
            } else {
                cert_value
            };
            
            total_score = total_score + final_value;
            i = i + 1;
        };

        validator_stake.knowledge_score = total_score;
    }

    // Helper function to calculate tier based on stake amount
    fun calculate_tier(stake_tiers: &vector<StakeTier>, stake_amount: u64): u8 {
        let mut tier = TIER_STARTER;
        let mut i = 0;
        
        while (i < vector::length(stake_tiers)) {
            let tier_info = vector::borrow(stake_tiers, i);
            if (stake_amount >= tier_info.minimum_stake) {
                tier = tier_info.tier_level;
            };
            i = i + 1;
        };
        
        tier
    }

    // Helper function to get tier information
    fun get_tier_info(stake_tiers: &vector<StakeTier>, tier_level: u8): &StakeTier {
        let mut i = 0;
        while (i < vector::length(stake_tiers)) {
            let tier_info = vector::borrow(stake_tiers, i);
            if (tier_info.tier_level == tier_level) {
                return tier_info
            };
            i = i + 1;
        };
        abort E_INVALID_TIER
    }

    // Update staking configuration (governance only)
    public fun update_staking_config(
        _: &AdminCap,
        config: &mut StakingConfig,
        new_minimum_stake: u64,
        new_slash_percentages: vector<u8>,
        new_max_slash_cap: u8,
        proposal_id: ID,
    ) {
        config.minimum_stake = new_minimum_stake;
        
        if (vector::length(&new_slash_percentages) >= 4) {
            config.lazy_validation_slash = *vector::borrow(&new_slash_percentages, 0);
            config.wrong_consensus_slash = *vector::borrow(&new_slash_percentages, 1);
            config.malicious_approval_slash = *vector::borrow(&new_slash_percentages, 2);
            config.collusion_slash = *vector::borrow(&new_slash_percentages, 3);
        };
        
        config.max_slash_cap = new_max_slash_cap;
        config.last_update_proposal = proposal_id;
    }

    // Getter functions
    public fun get_minimum_stake(config: &StakingConfig): u64 {
        config.minimum_stake
    }

    public fun get_validator_total_stake(validator_stake: &ValidatorStake): u64 {
        validator_stake.total_stake
    }

    public fun get_validator_active_stake(validator_stake: &ValidatorStake): u64 {
        validator_stake.active_stake
    }

    public fun get_validator_tier(validator_stake: &ValidatorStake): u8 {
        validator_stake.current_tier
    }

    public fun get_validator_knowledge_score(validator_stake: &ValidatorStake): u64 {
        validator_stake.knowledge_score
    }

    public fun get_validator_weight_multiplier(validator_stake: &ValidatorStake): u64 {
        validator_stake.weight_multiplier
    }

    public fun get_validator_active_status(validator_stake: &ValidatorStake): bool {
        validator_stake.active
    }

    public fun get_total_staked(stake_pool: &StakePool): u64 {
        stake_pool.total_staked
    }

    public fun get_active_validators_count(stake_pool: &StakePool): u64 {
        stake_pool.active_validators
    }

    public fun get_validation_accuracy(validator_stake: &ValidatorStake): u64 {
        validator_stake.validation_accuracy
    }

    // Test functions
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_test_validator_stake(
        validator: address,
        stake_amount: u64,
        ctx: &mut TxContext
    ): ValidatorStake {
        ValidatorStake {
            id: object::new(ctx),
            validator,
            total_stake: stake_amount,
            active_stake: stake_amount,
            pending_stake: balance::zero(),
            current_tier: TIER_STARTER,
            weight_multiplier: 10000,
            reward_multiplier: 10000,
            certificates: vector::empty(),
            knowledge_score: 0,
            validation_accuracy: 10000,
            total_validations: 0,
            correct_validations: 0,
            slashed_count: 0,
            active: true,
            suspended: false,
            suspension_end_epoch: 0,
            stake_history: vector::empty(),
            last_stake_change: tx_context::epoch(ctx),
        }
    }
}