module suiverse_core::governance {
    use std::string::String;
    // use std::option; // Implicit import
    use sui::object::{ID, UID};
    use sui::tx_context::{TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::math;
    use suiverse_core::parameters::{Self, SystemParameters};
    use suiverse_core::treasury::{Self, Treasury};
    
    // =============== Constants ===============
    
    // Error codes - Proposal related
    const E_INSUFFICIENT_DEPOSIT: u64 = 1001;
    const E_NOT_AUTHORIZED: u64 = 1002;
    const E_PROPOSAL_NOT_FOUND: u64 = 1003;
    const E_VOTING_NOT_STARTED: u64 = 1004;
    const E_VOTING_ENDED: u64 = 1005;
    const E_ALREADY_VOTED: u64 = 1006;
    const E_QUORUM_NOT_MET: u64 = 1007;
    const E_THRESHOLD_NOT_MET: u64 = 1008;
    const E_EXECUTION_DELAY_NOT_MET: u64 = 1009;
    const E_ALREADY_EXECUTED: u64 = 1010;
    const E_INVALID_PROPOSAL_TYPE: u64 = 1011;
    const E_COOLDOWN_NOT_MET: u64 = 1012;
    
    // Error codes - Validator related
    const E_INSUFFICIENT_STAKE: u64 = 2001;
    const E_NOT_VALIDATOR: u64 = 2002;
    const E_ALREADY_VALIDATOR: u64 = 2003;
    const E_CERTIFICATE_NOT_FOUND: u64 = 2004;
    const E_INVALID_CERTIFICATE: u64 = 2005;
    const E_INSUFFICIENT_KNOWLEDGE_SCORE: u64 = 2006;
    const E_VALIDATOR_SUSPENDED: u64 = 2007;
    const E_INVALID_SLASH_REASON: u64 = 2008;
    const E_GENESIS_PHASE_ACTIVE: u64 = 2009;
    const E_NOT_GENESIS_VALIDATOR: u64 = 2010;
    const E_INVALID_WEIGHT_CALCULATION: u64 = 2011;
    const E_VALIDATOR_SELECTION_FAILED: u64 = 2012;
    const E_CERTIFICATE_ALREADY_REGISTERED: u64 = 2013;
    const E_STAKE_BELOW_MINIMUM: u64 = 2014;
    const E_SLASH_AMOUNT_TOO_HIGH: u64 = 2015;
    
    // Proposal types
    const PROPOSAL_TYPE_PARAMETER: u8 = 1;
    const PROPOSAL_TYPE_EXAM: u8 = 2;
    const PROPOSAL_TYPE_CERTIFICATE: u8 = 3;
    const PROPOSAL_TYPE_ECONOMIC: u8 = 4;
    
    // Economic proposal sub-types
    const ECONOMIC_TYPE_FEE_ADJUSTMENT: u8 = 10;
    const ECONOMIC_TYPE_REVENUE_SPLIT: u8 = 11;
    const ECONOMIC_TYPE_STAKING_PARAMETERS: u8 = 12;
    const ECONOMIC_TYPE_INCENTIVES: u8 = 13;
    const ECONOMIC_TYPE_MARKET_DYNAMICS: u8 = 14;
    const ECONOMIC_TYPE_TREASURY_ALLOCATION: u8 = 15;
    
    // Proposal status
    const STATUS_PENDING: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_PASSED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_EXECUTED: u8 = 4;
    const STATUS_CANCELLED: u8 = 5;
    
    // Default governance values
    const DEFAULT_PROPOSAL_DEPOSIT: u64 = 100_000_000_000; // 100 SUI
    const DEFAULT_VOTING_PERIOD: u64 = 604800000; // 7 days in ms
    const DEFAULT_EXECUTION_DELAY: u64 = 86400000; // 24 hours in ms
    const DEFAULT_QUORUM_PERCENTAGE: u8 = 20; // 20%
    const DEFAULT_APPROVAL_THRESHOLD: u8 = 66; // 66%
    
    // Validator states
    const VALIDATOR_STATE_ACTIVE: u8 = 1;
    const VALIDATOR_STATE_SUSPENDED: u8 = 2;
    const VALIDATOR_STATE_SLASHED: u8 = 3;
    const VALIDATOR_STATE_RETIRED: u8 = 4;
    
    // Certificate value decay and multipliers
    const CERTIFICATE_AGE_DECAY_MONTHLY: u64 = 5; // 5% per month
    const CERTIFICATE_MAX_DECAY: u64 = 50; // Maximum 50% decay
    const SCARCITY_BASE_MULTIPLIER: u64 = 10000;
    const DIFFICULTY_BASE_MULTIPLIER: u64 = 100;
    
    // Stake tiers and multipliers
    const STAKE_TIER_STARTER: u64 = 10_000_000_000; // 10 SUI
    const STAKE_TIER_BASIC: u64 = 50_000_000_000; // 50 SUI
    const STAKE_TIER_BRONZE: u64 = 100_000_000_000; // 100 SUI
    const STAKE_TIER_SILVER: u64 = 500_000_000_000; // 500 SUI
    const STAKE_TIER_GOLD: u64 = 1_000_000_000_000; // 1,000 SUI
    const STAKE_TIER_PLATINUM: u64 = 5_000_000_000_000; // 5,000 SUI
    
    // Slash reasons and percentages
    const SLASH_LAZY_VALIDATION: u8 = 1; // 10% slash
    const SLASH_WRONG_CONSENSUS: u8 = 2; // 5% slash
    const SLASH_MALICIOUS_APPROVAL: u8 = 3; // 50% slash
    const SLASH_COLLUSION: u8 = 4; // 100% slash
    
    // Bootstrap configuration
    const GENESIS_VALIDATOR_COUNT: u64 = 20;
    const BOOTSTRAP_PHASE_DURATION: u64 = 2592000000; // 30 days in ms
    const MIN_CERTIFICATES_FOR_NON_GENESIS: u64 = 3;
    
    // Weight calculation constants
    const KNOWLEDGE_WEIGHT_FACTOR: u64 = 100;
    const STAKE_WEIGHT_FACTOR: u64 = 100;
    const PERFORMANCE_WEIGHT_FACTOR: u64 = 100;
    const BASE_WEIGHT_DIVISOR: u64 = 10000;
    
    // =============== Structs ===============
    
    /// Governance configuration with PoK features
    public struct GovernanceConfig has key {
        id: UID,
        // Proposal parameters
        proposal_deposit: u64,
        voting_period: u64,
        execution_delay: u64,
        quorum_percentage: u8,
        approval_threshold: u8,
        
        // PoK parameters
        minimum_stake: u64,
        bootstrap_end_time: u64,
        genesis_validators: vector<address>,
        certificate_base_values: Table<String, u64>,
        slash_percentages: Table<u8, u64>,
        selection_algorithm: u8, // 1: Random, 2: Weighted, 3: Domain-specific
        max_validators_per_content: u64,
        rebalance_interval: u64,
        last_rebalance: u64,
    }
    
    /// Governance proposal
    public struct GovernanceProposal has key, store {
        id: UID,
        proposer: address,
        proposal_type: u8,
        title: String,
        description: String,
        target_module: Option<String>,
        parameter_key: Option<String>,
        new_value: Option<vector<u8>>,
        votes_for: u64,
        votes_against: u64,
        votes_abstain: u64,
        voting_start: u64,
        voting_end: u64,
        execution_time: Option<u64>,
        status: u8,
        deposit: Balance<SUI>,
    }
    
    /// Voting records table
    public struct VotingRecords has key {
        id: UID,
        records: Table<ID, Table<address, VoteRecord>>,
    }
    
    /// Individual vote record
    public struct VoteRecord has store {
        voter: address,
        proposal_id: ID,
        vote_type: u8, // 1: For, 2: Against, 3: Abstain
        voting_power: u64,
        timestamp: u64,
    }
    
    /// Enhanced validator profile with PoK features
    public struct PoKValidator has key, store {
        id: UID,
        address: address,
        
        // Knowledge proof
        certificates: vector<CertificateInfo>,
        knowledge_score: u64,
        domain_expertise: Table<String, u64>, // Domain -> Expertise level
        
        // Economic stake
        stake_amount: Balance<SUI>,
        stake_tier: u8,
        risk_multiplier: u64,
        boosted_certificates: Table<ID, u64>, // Certificate ID -> Boost amount
        
        // Performance metrics
        validation_count: u64,
        consensus_accuracy: u64, // Percentage (0-100)
        slashed_count: u64,
        total_rewards_earned: u64,
        
        // Status
        state: u8,
        weight: u64,
        last_validation: u64,
        suspension_end: Option<u64>,
        
        // Genesis validator flag
        is_genesis: bool,
    }
    
    /// Certificate information for validators
    public struct CertificateInfo has store, copy, drop {
        certificate_id: ID,
        certificate_type: String,
        skill_level: u8,
        earned_date: u64,
        base_value: u64,
        current_value: u64,
        is_boosted: bool,
    }
    
    /// Dynamic certificate value tracking
    public struct CertificateValue has key, store {
        id: UID,
        certificate_type: String,
        base_value: u64,
        current_value: u64,
        
        // Market dynamics
        total_issued: u64,
        active_validators_holding: u64,
        recent_exam_pass_rate: u64,
        
        // Multipliers
        scarcity_multiplier: u64,
        difficulty_multiplier: u64,
        age_decay: u64,
        
        last_rebalance: u64,
    }
    
    /// Validator registry (for backward compatibility with tests)
    public struct ValidatorRegistry has key {
        id: UID,
        validators: Table<address, ValidatorInfo>,
        total_stake: u64,
        active_validators: u64,
    }
    
    /// Basic validator info (for backward compatibility)
    public struct ValidatorInfo has store {
        stake_amount: u64,
        voting_power: u64,
        proposals_created: u64,
        votes_cast: u64,
        reputation: u64,
        is_active: bool,
    }
    
    /// Validator pool with PoK features
    public struct ValidatorPool has key {
        id: UID,
        active_validators: Table<address, PoKValidator>,
        total_weight: u64,
        validators_by_domain: Table<String, vector<address>>,
        validators_by_weight: vector<address>, // Sorted by weight
    }
    
    /// Slashing record for audit trail
    public struct SlashingRecord has key, store {
        id: UID,
        validator: address,
        slash_reason: u8,
        slash_amount: u64,
        evidence: vector<u8>,
        timestamp: u64,
        executed_by: address,
    }
    
    /// Stake tier information
    public struct StakeTier has store, copy, drop {
        tier_name: String,
        minimum_stake: u64,
        weight_multiplier: u64,
        slash_protection: u64, // Percentage protection
        reward_multiplier: u64,
    }
    
    // =============== Events ===============
    
    // Proposal events
    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        proposer: address,
        proposal_type: u8,
        title: String,
        voting_start: u64,
        voting_end: u64,
    }
    
    public struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
        vote_type: u8,
        voting_power: u64,
        timestamp: u64,
    }
    
    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        executor: address,
        timestamp: u64,
    }
    
    public struct ProposalCancelled has copy, drop {
        proposal_id: ID,
        reason: String,
        timestamp: u64,
    }
    
    // Validator events
    public struct ValidatorRegistered has copy, drop {
        validator: address,
        stake_amount: u64,
        knowledge_score: u64,
        is_genesis: bool,
        timestamp: u64,
    }
    
    public struct CertificateAdded has copy, drop {
        validator: address,
        certificate_id: ID,
        certificate_type: String,
        value_added: u64,
        new_knowledge_score: u64,
    }
    
    public struct ValidatorWeightUpdated has copy, drop {
        validator: address,
        old_weight: u64,
        new_weight: u64,
        knowledge_component: u64,
        stake_component: u64,
        performance_component: u64,
    }
    
    public struct ValidatorSlashed has copy, drop {
        validator: address,
        reason: u8,
        slash_amount: u64,
        new_stake: u64,
        timestamp: u64,
    }
    
    public struct CertificateValueRebalanced has copy, drop {
        certificate_type: String,
        old_value: u64,
        new_value: u64,
        scarcity_factor: u64,
        difficulty_factor: u64,
        timestamp: u64,
    }
    
    public struct ValidatorSelected has copy, drop {
        content_id: ID,
        validators: vector<address>,
        selection_method: u8,
        total_weight: u64,
    }
    
    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        // Initialize governance configuration with PoK features
        let mut config = GovernanceConfig {
            id: object::new(ctx),
            // Proposal parameters
            proposal_deposit: DEFAULT_PROPOSAL_DEPOSIT,
            voting_period: DEFAULT_VOTING_PERIOD,
            execution_delay: DEFAULT_EXECUTION_DELAY,
            quorum_percentage: DEFAULT_QUORUM_PERCENTAGE,
            approval_threshold: DEFAULT_APPROVAL_THRESHOLD,
            
            // PoK parameters
            minimum_stake: STAKE_TIER_STARTER,
            bootstrap_end_time: 0, // Will be set properly when clock is available
            genesis_validators: vector::empty(),
            certificate_base_values: table::new(ctx),
            slash_percentages: table::new(ctx),
            selection_algorithm: 2, // Weighted by default
            max_validators_per_content: 5,
            rebalance_interval: 86400000, // 24 hours
            last_rebalance: 0,
        };
        
        // Initialize slash percentages
        table::add(&mut config.slash_percentages, SLASH_LAZY_VALIDATION, 10);
        table::add(&mut config.slash_percentages, SLASH_WRONG_CONSENSUS, 5);
        table::add(&mut config.slash_percentages, SLASH_MALICIOUS_APPROVAL, 50);
        table::add(&mut config.slash_percentages, SLASH_COLLUSION, 100);
        
        // Initialize validator registry (for backward compatibility)
        let registry = ValidatorRegistry {
            id: object::new(ctx),
            validators: table::new(ctx),
            total_stake: 0,
            active_validators: 0,
        };
        
        // Initialize validator pool with PoK features
        let pool = ValidatorPool {
            id: object::new(ctx),
            active_validators: table::new(ctx),
            total_weight: 0,
            validators_by_domain: table::new(ctx),
            validators_by_weight: vector::empty(),
        };
        
        // Initialize voting records
        let voting_records = VotingRecords {
            id: object::new(ctx),
            records: table::new(ctx),
        };
        
        transfer::share_object(config);
        transfer::share_object(registry);
        transfer::share_object(pool);
        transfer::share_object(voting_records);
    }
    
    // =============== Public Entry Functions ===============
    
    /// Register as a genesis validator (bootstrap phase only)
    public entry fun register_genesis_validator(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        stake: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Check if still in bootstrap phase
        assert!(current_time < config.bootstrap_end_time, E_GENESIS_PHASE_ACTIVE);
        
        // Check genesis validator limit
        assert!(vector::length(&config.genesis_validators) < GENESIS_VALIDATOR_COUNT, E_GENESIS_PHASE_ACTIVE);
        
        // Check minimum stake
        let stake_amount = coin::value(&stake);
        assert!(stake_amount >= config.minimum_stake, E_INSUFFICIENT_STAKE);
        
        // Check not already registered
        assert!(!table::contains(&pool.active_validators, validator_address), E_ALREADY_VALIDATOR);
        
        // Create genesis validator
        let mut validator = PoKValidator {
            id: object::new(ctx),
            address: validator_address,
            certificates: vector::empty(),
            knowledge_score: 100, // Base score for genesis validators
            domain_expertise: table::new(ctx),
            stake_amount: coin::into_balance(stake),
            stake_tier: calculate_stake_tier(stake_amount),
            risk_multiplier: 100,
            boosted_certificates: table::new(ctx),
            validation_count: 0,
            consensus_accuracy: 100, // Start with perfect accuracy
            slashed_count: 0,
            total_rewards_earned: 0,
            state: VALIDATOR_STATE_ACTIVE,
            weight: calculate_initial_weight(100, stake_amount),
            last_validation: current_time,
            suspension_end: option::none(),
            is_genesis: true,
        };
        
        // Add to genesis validators list
        vector::push_back(&mut config.genesis_validators, validator_address);
        
        // Add to validator pool
        pool.total_weight = pool.total_weight + validator.weight;
        table::add(&mut pool.active_validators, validator_address, validator);
        update_validators_by_weight(pool, validator_address);
        
        event::emit(ValidatorRegistered {
            validator: validator_address,
            stake_amount,
            knowledge_score: 100,
            is_genesis: true,
            timestamp: current_time,
        });
    }
    
    /// Register as a regular validator (requires certificates)
    public entry fun register_validator_with_certificates(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        certificate_ids: vector<ID>,
        certificate_types: vector<String>,
        skill_levels: vector<u8>,
        earned_dates: vector<u64>,
        stake: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // After bootstrap, require certificates
        if (current_time >= config.bootstrap_end_time) {
            assert!(
                vector::length(&certificate_ids) >= MIN_CERTIFICATES_FOR_NON_GENESIS,
                E_INSUFFICIENT_KNOWLEDGE_SCORE
            );
        };
        
        // Check minimum stake
        let stake_amount = coin::value(&stake);
        assert!(stake_amount >= config.minimum_stake, E_INSUFFICIENT_STAKE);
        
        // Check not already registered
        assert!(!table::contains(&pool.active_validators, validator_address), E_ALREADY_VALIDATOR);
        
        // Process certificates and calculate knowledge score
        let (certificates, knowledge_score) = process_certificates(
            config,
            certificate_ids,
            certificate_types,
            skill_levels,
            earned_dates,
            current_time
        );
        
        // Create validator
        let mut validator = PoKValidator {
            id: object::new(ctx),
            address: validator_address,
            certificates,
            knowledge_score,
            domain_expertise: table::new(ctx),
            stake_amount: coin::into_balance(stake),
            stake_tier: calculate_stake_tier(stake_amount),
            risk_multiplier: 100,
            boosted_certificates: table::new(ctx),
            validation_count: 0,
            consensus_accuracy: 100,
            slashed_count: 0,
            total_rewards_earned: 0,
            state: VALIDATOR_STATE_ACTIVE,
            weight: calculate_initial_weight(knowledge_score, stake_amount),
            last_validation: current_time,
            suspension_end: option::none(),
            is_genesis: false,
        };
        
        // Calculate domain expertise from certificates
        calculate_domain_expertise(&mut validator);
        
        // Add to validator pool
        pool.total_weight = pool.total_weight + validator.weight;
        update_validators_by_domain(pool, validator_address, &validator);
        table::add(&mut pool.active_validators, validator_address, validator);
        update_validators_by_weight(pool, validator_address);
        
        event::emit(ValidatorRegistered {
            validator: validator_address,
            stake_amount,
            knowledge_score,
            is_genesis: false,
            timestamp: current_time,
        });
    }
    
    /// Add a new certificate to existing validator
    public entry fun add_certificate(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        certificate_id: ID,
        certificate_type: String,
        skill_level: u8,
        earned_date: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Get validator
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        
        // Check certificate not already added
        let mut i = 0;
        while (i < vector::length(&validator.certificates)) {
            let cert = vector::borrow(&validator.certificates, i);
            assert!(cert.certificate_id != certificate_id, E_CERTIFICATE_ALREADY_REGISTERED);
            i = i + 1;
        };
        
        // Get certificate value
        let base_value = get_certificate_base_value(config, &certificate_type);
        let current_value = calculate_certificate_current_value(
            base_value,
            earned_date,
            current_time,
            0, // Will be updated during rebalance
            0  // Will be updated during rebalance
        );
        
        // Create certificate info
        let cert_info = CertificateInfo {
            certificate_id,
            certificate_type,
            skill_level,
            earned_date,
            base_value,
            current_value,
            is_boosted: false,
        };
        
        // Add certificate and update knowledge score
        vector::push_back(&mut validator.certificates, cert_info);
        let old_score = validator.knowledge_score;
        validator.knowledge_score = validator.knowledge_score + current_value;
        
        // Recalculate weight
        let old_weight = validator.weight;
        validator.weight = calculate_validator_weight(validator);
        
        // Update pool total weight
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        
        // Update domain expertise
        calculate_domain_expertise(validator);
        
        // Store final knowledge score before releasing validator reference
        let final_knowledge_score = validator.knowledge_score;
        
        // Release validator reference and update validators by weight
        update_validators_by_weight(pool, validator_address);
        
        event::emit(CertificateAdded {
            validator: validator_address,
            certificate_id,
            certificate_type,
            value_added: current_value,
            new_knowledge_score: final_knowledge_score,
        });
    }
    
    /// Boost a specific certificate with additional stake
    public entry fun boost_certificate(
        pool: &mut ValidatorPool,
        certificate_id: ID,
        boost_stake: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        
        // Find certificate
        let mut i = 0;
        let mut found = false;
        while (i < vector::length(&validator.certificates)) {
            let cert = vector::borrow_mut(&mut validator.certificates, i);
            if (cert.certificate_id == certificate_id) {
                cert.is_boosted = true;
                cert.current_value = cert.current_value * 150 / 100; // 50% boost
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, E_CERTIFICATE_NOT_FOUND);
        
        // Add boost stake
        let boost_amount = coin::value(&boost_stake);
        balance::join(&mut validator.stake_amount, coin::into_balance(boost_stake));
        
        // Record boost
        if (table::contains(&validator.boosted_certificates, certificate_id)) {
            let current_boost = table::borrow_mut(&mut validator.boosted_certificates, certificate_id);
            *current_boost = *current_boost + boost_amount;
        } else {
            table::add(&mut validator.boosted_certificates, certificate_id, boost_amount);
        };
        
        // Recalculate weight
        let old_weight = validator.weight;
        validator.weight = calculate_validator_weight(validator);
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        
        update_validators_by_weight(pool, validator_address);
    }
    
    /// Slash a validator for violations
    public entry fun slash_validator(
        config: &GovernanceConfig,
        pool: &mut ValidatorPool,
        validator_address: address,
        reason: u8,
        evidence: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let executor = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate slash reason
        assert!(table::contains(&config.slash_percentages, reason), E_INVALID_SLASH_REASON);
        
        // Get validator
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        
        // Calculate slash amount with protection
        let slash_percentage = *table::borrow(&config.slash_percentages, reason);
        let protection = get_stake_tier_protection(validator.stake_tier);
        let effective_slash = slash_percentage * (100 - protection) / 100;
        
        // Apply bootstrap phase cap (max 50% slash)
        let max_slash = balance::value(&validator.stake_amount) * 50 / 100;
        let calculated_slash = balance::value(&validator.stake_amount) * effective_slash / 100;
        let final_slash = std::u64::min(calculated_slash, max_slash);
        
        // Never slash below minimum stake
        let remaining_stake = balance::value(&validator.stake_amount) - final_slash;
        assert!(remaining_stake >= config.minimum_stake, E_STAKE_BELOW_MINIMUM);
        
        // Apply slash
        let slashed_balance = balance::split(&mut validator.stake_amount, final_slash);
        // TODO: Transfer slashed amount to treasury - for now, send to sui system address
        transfer::public_transfer(
            coin::from_balance(slashed_balance, ctx),
            @0x5  // Sui system address as placeholder for treasury
        );
        
        // Update validator state
        validator.slashed_count = validator.slashed_count + 1;
        validator.consensus_accuracy = validator.consensus_accuracy * 90 / 100; // Reduce accuracy
        
        // Reduce certificate values temporarily (20% reduction)
        let mut i = 0;
        while (i < vector::length(&validator.certificates)) {
            let cert = vector::borrow_mut(&mut validator.certificates, i);
            cert.current_value = cert.current_value * 80 / 100;
            i = i + 1;
        };
        
        // Recalculate knowledge score and weight
        recalculate_knowledge_score(validator);
        let old_weight = validator.weight;
        validator.weight = calculate_validator_weight(validator);
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        
        // Suspend if stake below minimum
        if (balance::value(&validator.stake_amount) < config.minimum_stake) {
            validator.state = VALIDATOR_STATE_SUSPENDED;
            validator.suspension_end = option::some(current_time + 604800000); // 7 days
        };
        
        // Store final stake value before releasing validator reference
        let final_stake_value = balance::value(&validator.stake_amount);
        
        // Create slashing record
        let record = SlashingRecord {
            id: object::new(ctx),
            validator: validator_address,
            slash_reason: reason,
            slash_amount: final_slash,
            evidence,
            timestamp: current_time,
            executed_by: executor,
        };
        
        transfer::share_object(record);
        update_validators_by_weight(pool, validator_address);
        
        event::emit(ValidatorSlashed {
            validator: validator_address,
            reason,
            slash_amount: final_slash,
            new_stake: final_stake_value,
            timestamp: current_time,
        });
    }
    
    /// Select validators for content validation using weighted selection
    public entry fun select_validators_for_content(
        config: &GovernanceConfig,
        pool: &ValidatorPool,
        content_id: ID,
        content_type: String,
        required_count: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        assert!(required_count <= config.max_validators_per_content, E_VALIDATOR_SELECTION_FAILED);
        
        let selected = if (config.selection_algorithm == 1) {
            select_validators_random(pool, required_count, clock)
        } else if (config.selection_algorithm == 2) {
            select_validators_weighted(pool, required_count, clock)
        } else {
            select_validators_domain_specific(pool, &content_type, required_count, clock)
        };
        
        event::emit(ValidatorSelected {
            content_id,
            validators: selected,
            selection_method: config.selection_algorithm,
            total_weight: pool.total_weight,
        });
        
        selected
    }
    
    /// Rebalance certificate values based on market dynamics
    public entry fun rebalance_certificate_values(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        certificate_types: vector<String>,
        total_issued: vector<u64>,
        pass_rates: vector<u64>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if rebalance interval has passed
        assert!(
            current_time >= config.last_rebalance + config.rebalance_interval,
            E_INVALID_WEIGHT_CALCULATION
        );
        
        let mut i = 0;
        while (i < vector::length(&certificate_types)) {
            let cert_type = vector::borrow(&certificate_types, i);
            let issued = *vector::borrow(&total_issued, i);
            let pass_rate = *vector::borrow(&pass_rates, i);
            
            // Calculate new value based on scarcity and difficulty
            let base_value = get_certificate_base_value(config, cert_type);
            let scarcity = calculate_scarcity_multiplier(issued);
            let difficulty = calculate_difficulty_multiplier(pass_rate);
            
            let new_value = base_value * scarcity * difficulty / 10000;
            
            // Update certificate values in config
            if (table::contains(&config.certificate_base_values, *cert_type)) {
                *table::borrow_mut(&mut config.certificate_base_values, *cert_type) = new_value;
            };
            
            event::emit(CertificateValueRebalanced {
                certificate_type: *cert_type,
                old_value: base_value,
                new_value,
                scarcity_factor: scarcity,
                difficulty_factor: difficulty,
                timestamp: current_time,
            });
            
            i = i + 1;
        };
        
        // Update all validator weights after rebalance
        rebalance_all_validator_weights(pool);
        
        config.last_rebalance = current_time;
    }
    
    // =============== Helper Functions ===============
    
    fun calculate_stake_tier(stake_amount: u64): u8 {
        if (stake_amount >= STAKE_TIER_PLATINUM) {
            6
        } else if (stake_amount >= STAKE_TIER_GOLD) {
            5
        } else if (stake_amount >= STAKE_TIER_SILVER) {
            4
        } else if (stake_amount >= STAKE_TIER_BRONZE) {
            3
        } else if (stake_amount >= STAKE_TIER_BASIC) {
            2
        } else {
            1
        }
    }
    
    fun get_stake_tier_protection(tier: u8): u64 {
        if (tier == 6) { 50 }       // Platinum: 50% protection
        else if (tier == 5) { 40 }  // Gold: 40% protection
        else if (tier == 4) { 30 }  // Silver: 30% protection
        else if (tier == 3) { 20 }  // Bronze: 20% protection
        else if (tier == 2) { 10 }  // Basic: 10% protection
        else { 0 }                  // Starter: 0% protection
    }
    
    fun calculate_initial_weight(knowledge_score: u64, stake_amount: u64): u64 {
        let stake_multiplier = math::sqrt(stake_amount / 1_000_000_000) * 100;
        (knowledge_score * KNOWLEDGE_WEIGHT_FACTOR + stake_multiplier * STAKE_WEIGHT_FACTOR) / BASE_WEIGHT_DIVISOR
    }
    
    fun calculate_validator_weight(validator: &PoKValidator): u64 {
        // Knowledge component
        let knowledge = validator.knowledge_score * KNOWLEDGE_WEIGHT_FACTOR;
        
        // Stake component (logarithmic growth)
        let stake_multiplier = math::sqrt(balance::value(&validator.stake_amount) / 1_000_000_000) * 100;
        let stake = stake_multiplier * STAKE_WEIGHT_FACTOR;
        
        // Performance component (0.5x to 1.5x)
        let performance = (50 + validator.consensus_accuracy / 2) * PERFORMANCE_WEIGHT_FACTOR;
        
        (knowledge * stake * performance) / (BASE_WEIGHT_DIVISOR * 100)
    }
    
    fun process_certificates(
        config: &GovernanceConfig,
        certificate_ids: vector<ID>,
        certificate_types: vector<String>,
        skill_levels: vector<u8>,
        earned_dates: vector<u64>,
        current_time: u64
    ): (vector<CertificateInfo>, u64) {
        let mut certificates = vector::empty<CertificateInfo>();
        let mut total_score = 0u64;
        
        let mut i = 0;
        while (i < vector::length(&certificate_ids)) {
            let cert_type = vector::borrow(&certificate_types, i);
            let base_value = get_certificate_base_value(config, cert_type);
            let current_value = calculate_certificate_current_value(
                base_value,
                *vector::borrow(&earned_dates, i),
                current_time,
                0, // Will be updated during rebalance
                0  // Will be updated during rebalance
            );
            
            let cert = CertificateInfo {
                certificate_id: *vector::borrow(&certificate_ids, i),
                certificate_type: *cert_type,
                skill_level: *vector::borrow(&skill_levels, i),
                earned_date: *vector::borrow(&earned_dates, i),
                base_value,
                current_value,
                is_boosted: false,
            };
            
            vector::push_back(&mut certificates, cert);
            total_score = total_score + current_value;
            
            i = i + 1;
        };
        
        (certificates, total_score)
    }
    
    fun calculate_certificate_current_value(
        base_value: u64,
        earned_date: u64,
        current_time: u64,
        scarcity_multiplier: u64,
        difficulty_multiplier: u64
    ): u64 {
        // Calculate age decay
        let age_months = (current_time - earned_date) / 2592000000; // 30 days in ms
        let decay = std::u64::min(age_months * CERTIFICATE_AGE_DECAY_MONTHLY, CERTIFICATE_MAX_DECAY);
        let after_decay = base_value * (100 - decay) / 100;
        
        // Apply multipliers if available
        if (scarcity_multiplier > 0 && difficulty_multiplier > 0) {
            after_decay * scarcity_multiplier * difficulty_multiplier / 10000
        } else {
            after_decay
        }
    }
    
    fun get_certificate_base_value(config: &GovernanceConfig, cert_type: &String): u64 {
        if (table::contains(&config.certificate_base_values, *cert_type)) {
            *table::borrow(&config.certificate_base_values, *cert_type)
        } else {
            100 // Default base value
        }
    }
    
    fun calculate_scarcity_multiplier(total_issued: u64): u64 {
        // Less holders = more valuable
        if (total_issued == 0) {
            200 // 2x multiplier for first certificate
        } else {
            std::u64::min(SCARCITY_BASE_MULTIPLIER / (total_issued + 1), 200)
        }
    }
    
    fun calculate_difficulty_multiplier(pass_rate: u64): u64 {
        // Lower pass rate = more valuable
        let difficulty = 100 - pass_rate;
        DIFFICULTY_BASE_MULTIPLIER + difficulty
    }
    
    fun calculate_domain_expertise(validator: &mut PoKValidator) {
        // Clear existing expertise
        while (table::length(&validator.domain_expertise) > 0) {
            // Note: In production, would need proper table clearing
            break
        };
        
        // Calculate expertise from certificates
        let mut i = 0;
        while (i < vector::length(&validator.certificates)) {
            let cert = vector::borrow(&validator.certificates, i);
            let domain = &cert.certificate_type; // Simplified: use cert type as domain
            
            if (table::contains(&validator.domain_expertise, *domain)) {
                let expertise = table::borrow_mut(&mut validator.domain_expertise, *domain);
                *expertise = *expertise + (cert.skill_level as u64) * 10;
            } else {
                table::add(&mut validator.domain_expertise, *domain, (cert.skill_level as u64) * 10);
            };
            
            i = i + 1;
        };
    }
    
    fun recalculate_knowledge_score(validator: &mut PoKValidator) {
        let mut total = 0u64;
        let mut i = 0;
        while (i < vector::length(&validator.certificates)) {
            let cert = vector::borrow(&validator.certificates, i);
            total = total + cert.current_value;
            i = i + 1;
        };
        validator.knowledge_score = total;
    }
    
    fun update_validators_by_weight(pool: &mut ValidatorPool, validator_address: address) {
        // In production, would maintain sorted list of validators by weight
        // For now, just track that update is needed
    }
    
    fun update_validators_by_domain(pool: &mut ValidatorPool, validator_address: address, validator: &PoKValidator) {
        // In production, would maintain mapping of validators by domain expertise
        // For now, just track that update is needed
    }
    
    fun select_validators_random(
        pool: &ValidatorPool,
        count: u64,
        clock: &Clock
    ): vector<address> {
        // Simple random selection (in production, use proper randomness)
        let validators = vector::empty<address>();
        let seed = clock::timestamp_ms(clock);
        
        // Simplified random selection
        let mut i = 0;
        let mut selected_count = 0;
        while (selected_count < count && i < table::length(&pool.active_validators)) {
            // In production, iterate through active validators properly
            i = i + 1;
            selected_count = selected_count + 1;
        };
        
        validators
    }
    
    fun select_validators_weighted(
        pool: &ValidatorPool,
        count: u64,
        clock: &Clock
    ): vector<address> {
        // Weighted selection based on validator weights
        let validators = vector::empty<address>();
        let seed = clock::timestamp_ms(clock);
        
        // In production, implement proper weighted random selection
        // using cumulative weights and binary search
        
        validators
    }
    
    fun select_validators_domain_specific(
        pool: &ValidatorPool,
        domain: &String,
        count: u64,
        clock: &Clock
    ): vector<address> {
        // Select validators with expertise in specific domain
        let mut validators = vector::empty<address>();
        
        if (table::contains(&pool.validators_by_domain, *domain)) {
            let domain_validators = table::borrow(&pool.validators_by_domain, *domain);
            // Select top validators from domain
            let mut i = 0;
            while (i < std::u64::min(count, vector::length(domain_validators) as u64)) {
                vector::push_back(&mut validators, *vector::borrow(domain_validators, i as u64));
                i = i + 1;
            };
        };
        
        validators
    }
    
    fun rebalance_all_validator_weights(pool: &mut ValidatorPool) {
        // In production, iterate through all validators and recalculate weights
        // Update pool.total_weight accordingly
    }
    
    // =============== Test Functions ===============
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
    
    // =============== View Functions ===============
    
    public fun get_validator_weight(pool: &ValidatorPool, validator: address): u64 {
        if (table::contains(&pool.active_validators, validator)) {
            let val = table::borrow(&pool.active_validators, validator);
            val.weight
        } else {
            0
        }
    }
    
    public fun get_validator_knowledge_score(pool: &ValidatorPool, validator: address): u64 {
        if (table::contains(&pool.active_validators, validator)) {
            let val = table::borrow(&pool.active_validators, validator);
            val.knowledge_score
        } else {
            0
        }
    }
    
    public fun get_validator_stake(pool: &ValidatorPool, validator: address): u64 {
        if (table::contains(&pool.active_validators, validator)) {
            let val = table::borrow(&pool.active_validators, validator);
            balance::value(&val.stake_amount)
        } else {
            0
        }
    }
    
    public fun is_genesis_validator(pool: &ValidatorPool, validator: address): bool {
        if (table::contains(&pool.active_validators, validator)) {
            let val = table::borrow(&pool.active_validators, validator);
            val.is_genesis
        } else {
            false
        }
    }
    
    public fun get_total_pool_weight(pool: &ValidatorPool): u64 {
        pool.total_weight
    }
    
    public fun get_active_validator_count(pool: &ValidatorPool): u64 {
        table::length(&pool.active_validators)
    }
    
    // =============== Proposal Management Functions ===============
    
    /// Create a new governance proposal
    public entry fun create_proposal(
        proposer: address,
        proposal_type: u8,
        title: String,
        description: String,
        target_module: Option<String>,
        parameter_key: Option<String>,
        new_value: Option<vector<u8>>,
        payment: Coin<SUI>,
        config: &GovernanceConfig,
        registry: &ValidatorRegistry,
        pool: &ValidatorPool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Validate proposal type
        assert!(
            proposal_type >= PROPOSAL_TYPE_PARAMETER && 
            proposal_type <= PROPOSAL_TYPE_ECONOMIC,
            E_INVALID_PROPOSAL_TYPE
        );

        // Check deposit amount
        assert!(
            coin::value(&payment) >= config.proposal_deposit,
            E_INSUFFICIENT_DEPOSIT
        );

        // Check if proposer is a validator (either in registry or pool)
        let is_validator = table::contains(&registry.validators, proposer) ||
                          table::contains(&pool.active_validators, proposer);
        assert!(is_validator, E_NOT_AUTHORIZED);

        let current_time = clock::timestamp_ms(clock);
        let voting_end = current_time + config.voting_period;

        // Create proposal
        let proposal = GovernanceProposal {
            id: object::new(ctx),
            proposer,
            proposal_type,
            title,
            description,
            target_module,
            parameter_key,
            new_value,
            votes_for: 0,
            votes_against: 0,
            votes_abstain: 0,
            voting_start: current_time,
            voting_end,
            execution_time: option::none(),
            status: STATUS_ACTIVE,
            deposit: coin::into_balance(payment),
        };

        let proposal_id = object::uid_to_inner(&proposal.id);

        event::emit(ProposalCreated {
            proposal_id,
            proposer,
            proposal_type,
            title,
            voting_start: current_time,
            voting_end,
        });

        transfer::share_object(proposal);
    }

    /// Cast a vote on a proposal (with PoK-weighted voting)
    public entry fun cast_vote(
        proposal: &mut GovernanceProposal,
        vote_type: u8, // 1: For, 2: Against, 3: Abstain
        registry: &ValidatorRegistry,
        pool: &ValidatorPool,
        voting_records: &mut VotingRecords,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let voter = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check voting period
        assert!(current_time >= proposal.voting_start, E_VOTING_NOT_STARTED);
        assert!(current_time <= proposal.voting_end, E_VOTING_ENDED);
        assert!(proposal.status == STATUS_ACTIVE, E_VOTING_ENDED);

        // Calculate voting power based on PoK weight or basic validator info
        let voting_power = if (table::contains(&pool.active_validators, voter)) {
            // Use PoK weight for advanced validators
            let validator = table::borrow(&pool.active_validators, voter);
            validator.weight
        } else if (table::contains(&registry.validators, voter)) {
            // Use basic voting power for legacy validators
            let validator_info = table::borrow(&registry.validators, voter);
            assert!(validator_info.is_active, E_NOT_AUTHORIZED);
            validator_info.voting_power
        } else {
            abort E_NOT_AUTHORIZED
        };

        // Check if already voted
        let proposal_id = object::uid_to_inner(&proposal.id);
        if (!table::contains(&voting_records.records, proposal_id)) {
            table::add(&mut voting_records.records, proposal_id, table::new(ctx));
        };
        
        let proposal_votes = table::borrow_mut(&mut voting_records.records, proposal_id);
        assert!(!table::contains(proposal_votes, voter), E_ALREADY_VOTED);

        // Record vote
        if (vote_type == 1) {
            proposal.votes_for = proposal.votes_for + voting_power;
        } else if (vote_type == 2) {
            proposal.votes_against = proposal.votes_against + voting_power;
        } else if (vote_type == 3) {
            proposal.votes_abstain = proposal.votes_abstain + voting_power;
        };

        // Store vote record
        let vote_record = VoteRecord {
            voter,
            proposal_id,
            vote_type,
            voting_power,
            timestamp: current_time,
        };

        table::add(proposal_votes, voter, vote_record);

        event::emit(VoteCast {
            proposal_id,
            voter,
            vote_type,
            voting_power,
            timestamp: current_time,
        });
    }

    /// Finalize voting and determine outcome
    public entry fun finalize_voting(
        proposal: &mut GovernanceProposal,
        config: &GovernanceConfig,
        registry: &ValidatorRegistry,
        pool: &ValidatorPool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if voting period has ended
        assert!(current_time > proposal.voting_end, E_VOTING_NOT_STARTED);
        assert!(proposal.status == STATUS_ACTIVE, E_VOTING_ENDED);

        // Calculate total votes
        let total_votes = proposal.votes_for + proposal.votes_against + proposal.votes_abstain;
        
        // Calculate total stake for quorum (from both registry and pool)
        let total_stake = registry.total_stake + pool.total_weight;
        
        // Check quorum
        let quorum_required = (total_stake * (config.quorum_percentage as u64)) / 100;
        if (total_votes < quorum_required) {
            proposal.status = STATUS_REJECTED;
            // Return half of deposit to proposer
            let half_deposit = balance::value(&proposal.deposit) / 2;
            let refund = balance::split(&mut proposal.deposit, half_deposit);
            transfer::public_transfer(
                coin::from_balance(refund, ctx),
                proposal.proposer
            );
            return
        };

        // Check approval threshold
        let approval_votes_required = (total_votes * (config.approval_threshold as u64)) / 100;
        if (proposal.votes_for >= approval_votes_required) {
            proposal.status = STATUS_PASSED;
            proposal.execution_time = option::some(current_time + config.execution_delay);
        } else {
            proposal.status = STATUS_REJECTED;
            // Return half of deposit to proposer
            let half_deposit = balance::value(&proposal.deposit) / 2;
            let refund = balance::split(&mut proposal.deposit, half_deposit);
            transfer::public_transfer(
                coin::from_balance(refund, ctx),
                proposal.proposer
            );
        }
    }

    /// Execute a passed proposal
    public entry fun execute_proposal(
        proposal: &mut GovernanceProposal,
        params: &mut SystemParameters,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check proposal status
        assert!(proposal.status == STATUS_PASSED, E_THRESHOLD_NOT_MET);
        
        // Check execution delay
        if (option::is_some(&proposal.execution_time)) {
            let exec_time = *option::borrow(&proposal.execution_time);
            assert!(current_time >= exec_time, E_EXECUTION_DELAY_NOT_MET);
        };

        // Execute based on proposal type
        if (proposal.proposal_type == PROPOSAL_TYPE_PARAMETER) {
            // Update system parameter
            if (option::is_some(&proposal.parameter_key) && option::is_some(&proposal.new_value)) {
                let key = *option::borrow(&proposal.parameter_key);
                let value = *option::borrow(&proposal.new_value);
                parameters::update_parameter(
                    params,
                    key,
                    value,
                    proposal.proposer,
                    current_time
                );
            }
        } else if (proposal.proposal_type == PROPOSAL_TYPE_ECONOMIC) {
            // Handle economic proposals through treasury
            // Implementation depends on specific economic actions
            // For now, just mark as executed
        } else if (proposal.proposal_type == PROPOSAL_TYPE_EXAM) {
            // Handle exam-related proposals
            // TODO: Integrate with exam module
        } else if (proposal.proposal_type == PROPOSAL_TYPE_CERTIFICATE) {
            // Handle certificate-related proposals
            // TODO: Integrate with certificate module
        };

        proposal.status = STATUS_EXECUTED;

        // Return full deposit to proposer
        let deposit = balance::withdraw_all(&mut proposal.deposit);
        transfer::public_transfer(
            coin::from_balance(deposit, ctx),
            proposal.proposer
        );

        event::emit(ProposalExecuted {
            proposal_id: object::uid_to_inner(&proposal.id),
            executor: tx_context::sender(ctx),
            timestamp: current_time,
        });
    }

    /// Cancel a proposal (only by proposer or emergency)
    public entry fun cancel_proposal(
        proposal: &mut GovernanceProposal,
        reason: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        
        // Only proposer can cancel their own proposal
        assert!(sender == proposal.proposer, E_NOT_AUTHORIZED);
        assert!(proposal.status == STATUS_ACTIVE, E_VOTING_ENDED);

        proposal.status = STATUS_CANCELLED;

        // Return 75% of deposit (25% penalty for cancellation)
        let deposit_amount = balance::value(&proposal.deposit);
        let refund_amount = deposit_amount * 3 / 4;
        let refund = balance::split(&mut proposal.deposit, refund_amount);
        
        transfer::public_transfer(
            coin::from_balance(refund, ctx),
            proposal.proposer
        );

        event::emit(ProposalCancelled {
            proposal_id: object::uid_to_inner(&proposal.id),
            reason,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Register validator (backward compatibility for tests)
    public entry fun register_validator(
        registry: &mut ValidatorRegistry,
        stake: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator = tx_context::sender(ctx);
        let stake_amount = coin::value(&stake);

        // Check if already registered
        assert!(!table::contains(&registry.validators, validator), E_NOT_AUTHORIZED);

        // Calculate voting power (simple: 1 voting power per SUI)
        let voting_power = stake_amount / 1_000_000_000;

        let validator_info = ValidatorInfo {
            stake_amount,
            voting_power,
            proposals_created: 0,
            votes_cast: 0,
            reputation: 100, // Starting reputation
            is_active: true,
        };

        table::add(&mut registry.validators, validator, validator_info);
        registry.total_stake = registry.total_stake + stake_amount;
        registry.active_validators = registry.active_validators + 1;

        // Transfer stake to treasury address (simplified)
        transfer::public_transfer(stake, @suiverse_core);
    }

    /// Update governance configuration
    public entry fun update_config(
        config: &mut GovernanceConfig,
        proposal_deposit: Option<u64>,
        voting_period: Option<u64>,
        execution_delay: Option<u64>,
        quorum_percentage: Option<u8>,
        approval_threshold: Option<u8>,
        _ctx: &TxContext,
    ) {
        // Note: In production, this should be restricted to governance execution only
        
        if (option::is_some(&proposal_deposit)) {
            config.proposal_deposit = *option::borrow(&proposal_deposit);
        };
        
        if (option::is_some(&voting_period)) {
            config.voting_period = *option::borrow(&voting_period);
        };
        
        if (option::is_some(&execution_delay)) {
            config.execution_delay = *option::borrow(&execution_delay);
        };
        
        if (option::is_some(&quorum_percentage)) {
            let value = *option::borrow(&quorum_percentage);
            assert!(value <= 100, E_INVALID_PROPOSAL_TYPE);
            config.quorum_percentage = value;
        };
        
        if (option::is_some(&approval_threshold)) {
            let value = *option::borrow(&approval_threshold);
            assert!(value <= 100, E_INVALID_PROPOSAL_TYPE);
            config.approval_threshold = value;
        };
    }

    // =============== View Functions ===============
    
    public fun get_proposal_status(proposal: &GovernanceProposal): u8 {
        proposal.status
    }

    public fun get_voting_results(proposal: &GovernanceProposal): (u64, u64, u64) {
        (proposal.votes_for, proposal.votes_against, proposal.votes_abstain)
    }

    public fun get_validator_info(registry: &ValidatorRegistry, validator: address): &ValidatorInfo {
        table::borrow(&registry.validators, validator)
    }

    public fun get_total_stake(registry: &ValidatorRegistry): u64 {
        registry.total_stake
    }

    public fun is_validator(registry: &ValidatorRegistry, address: address): bool {
        table::contains(&registry.validators, address)
    }

    public fun get_config(config: &GovernanceConfig): (u64, u64, u64, u8, u8) {
        (
            config.proposal_deposit,
            config.voting_period,
            config.execution_delay,
            config.quorum_percentage,
            config.approval_threshold
        )
    }
}
