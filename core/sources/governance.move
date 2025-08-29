module core::governance {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::math;
    use core::parameters::GlobalParameters;
    use core::treasury::Treasury;
    
    // Error codes - Configuration
    const E_NOT_AUTHORIZED: u64 = 1002;
    const E_PROPOSAL_NOT_FOUND: u64 = 1003;
    const E_VOTING_NOT_STARTED: u64 = 1004;
    const E_VOTING_ENDED: u64 = 1005;
    const E_ALREADY_VOTED: u64 = 1006;
    const E_QUORUM_NOT_MET: u64 = 1007;
    const E_THRESHOLD_NOT_MET: u64 = 1008;
    const E_EXECUTION_DELAY_NOT_MET: u64 = 1009;
    const E_ALREADY_EXECUTED: u64 = 1010;
    
    // Error codes - Validator
    const E_INSUFFICIENT_STAKE: u64 = 2001;
    const E_NOT_VALIDATOR: u64 = 2002;
    const E_ALREADY_VALIDATOR: u64 = 2003;
    const E_INSUFFICIENT_KNOWLEDGE_SCORE: u64 = 2006;
    const E_VALIDATOR_SUSPENDED: u64 = 2007;
    const E_GENESIS_PHASE_ACTIVE: u64 = 2009;
    const E_GENESIS_PHASE_ENDED: u64 = 2010;
    const E_INSUFFICIENT_COIN_VALUE: u64 = 2021;
    const E_STAKE_BELOW_MINIMUM: u64 = 2014;
    
    // Proposal types
    const PROPOSAL_TYPE_PARAMETER: u8 = 1;
    const PROPOSAL_TYPE_CERTIFICATE: u8 = 3;
    const PROPOSAL_TYPE_ECONOMIC: u8 = 4;
    
    // Proposal status
    const STATUS_PENDING: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_PASSED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_EXECUTED: u8 = 4;
    const STATUS_CANCELLED: u8 = 5;
    
    // Vote types
    const VOTE_FOR: u8 = 1;
    const VOTE_AGAINST: u8 = 2;
    const VOTE_ABSTAIN: u8 = 3;
    
    // Default governance values
    const DEFAULT_PROPOSAL_DEPOSIT: u64 = 1_000_000_000; // 1 SUI
    const DEFAULT_VOTING_PERIOD: u64 = 604800000; // 7 days in ms
    const DEFAULT_EXECUTION_DELAY: u64 = 86400000; // 24 hours in ms
    const DEFAULT_QUORUM_PERCENTAGE: u8 = 20; // 20%
    const DEFAULT_APPROVAL_THRESHOLD: u8 = 66; // 66%
    
    // Validator states
    const VALIDATOR_STATE_ACTIVE: u8 = 1;
    const VALIDATOR_STATE_SUSPENDED: u8 = 2;
    const VALIDATOR_STATE_SLASHED: u8 = 3;
    
    // Genesis configuration
    const GENESIS_VALIDATOR_COUNT: u64 = 20;
    const BOOTSTRAP_PHASE_DURATION: u64 = 86400000; // 1 day in ms
    const MIN_CERTIFICATES_FOR_NON_GENESIS: u64 = 3;
    
    // Stake tiers
    const STAKE_TIER_STARTER: u64 = 100_000_000; // 0.1 SUI
    const STAKE_TIER_BASIC: u64 = 1_000_000_000; // 1 SUI
    const STAKE_TIER_BRONZE: u64 = 5_000_000_000; // 5 SUI
    const STAKE_TIER_SILVER: u64 = 10_000_000_000; // 10 SUI
    const STAKE_TIER_GOLD: u64 = 50_000_000_000; // 50 SUI
    const STAKE_TIER_PLATINUM: u64 = 100_000_000_000; // 100 SUI
    
    // Weight calculation
    const KNOWLEDGE_WEIGHT_FACTOR: u64 = 100;
    const STAKE_WEIGHT_FACTOR: u64 = 100;
    const PERFORMANCE_WEIGHT_FACTOR: u64 = 100;
    const BASE_WEIGHT_DIVISOR: u64 = 10000;
    
    // Certificate scoring
    const BASE_CERTIFICATE_SCORE: u64 = 50;
    const CERTIFICATE_MULTIPLIER: u64 = 25;
    
    /// Main governance configuration (shared object)
    public struct GovernanceConfig has key {
        id: UID,
        // Proposal parameters
        proposal_deposit: u64,
        voting_period: u64,
        execution_delay: u64,
        quorum_percentage: u8,
        approval_threshold: u8,
        
        // Genesis parameters
        minimum_stake: u64,
        bootstrap_end_time: u64,
        genesis_validators: vector<address>,
        
        // Certificate base values
        certificate_base_values: Table<String, u64>,
        
        // Admin
        admin: address,
        
        // Counters
        next_proposal_id: u64,
    }
    
    /// Validator pool with PoK features (shared object)
    public struct ValidatorPool has key {
        id: UID,
        active_validators: Table<address, PoKValidator>,
        total_weight: u64,
        total_stake: u64,
        admin: address,
    }
    
    /// Governance proposals (shared object)
    public struct ProposalRegistry has key {
        id: UID,
        proposals: Table<u64, GovernanceProposal>,
        voting_records: Table<u64, Table<address, VoteRecord>>,
        admin: address,
    }
    
    /// Enhanced validator with PoK features
    public struct PoKValidator has store {
        address: address,
        
        // Economic stake
        stake_amount: Balance<SUI>,
        stake_tier: u8,
        
        // Knowledge proof
        certificates: vector<CertificateInfo>,
        knowledge_score: u64,
        
        // Performance metrics
        validation_count: u64,
        consensus_accuracy: u64,
        
        // Status
        state: u8,
        weight: u64,
        last_validation: u64,
        
        // Genesis flag
        is_genesis: bool,
        registration_time: u64,
    }
    
    /// Certificate information
    public struct CertificateInfo has store, copy, drop {
        certificate_id: ID,
        certificate_type: String,
        skill_level: u8,
        earned_date: u64,
        base_value: u64,
        current_value: u64,
    }
    
    /// Governance proposal
    public struct GovernanceProposal has store {
        id: u64,
        proposer: address,
        proposal_type: u8,
        title: String,
        description: String,
        target_parameter: Option<String>,
        new_value: Option<vector<u8>>,
        
        // Voting results
        votes_for: u64,
        votes_against: u64,
        votes_abstain: u64,
        
        // Timing
        voting_start: u64,
        voting_end: u64,
        execution_time: Option<u64>,
        
        // Status
        status: u8,
        deposit: Balance<SUI>,
    }
    
    /// Individual vote record
    public struct VoteRecord has store {
        voter: address,
        proposal_id: u64,
        vote_type: u8,
        voting_power: u64,
        timestamp: u64,
    }
    
    /// Admin capability
    public struct GovernanceAdminCap has key, store {
        id: UID,
    }
    
    // =============== Events ===============
    
    public struct GovernanceInitialized has copy, drop {
        config_id: ID,
        pool_id: ID,
        proposal_registry_id: ID,
        admin: address,
        timestamp: u64,
    }
    
    public struct ValidatorRegistered has copy, drop {
        validator: address,
        stake_amount: u64,
        knowledge_score: u64,
        is_genesis: bool,
        timestamp: u64,
    }
    
    public struct ProposalCreated has copy, drop {
        proposal_id: u64,
        proposer: address,
        proposal_type: u8,
        title: String,
        voting_start: u64,
        voting_end: u64,
    }
    
    public struct VoteCast has copy, drop {
        proposal_id: u64,
        voter: address,
        vote_type: u8,
        voting_power: u64,
        timestamp: u64,
    }
    
    public struct ProposalExecuted has copy, drop {
        proposal_id: u64,
        executor: address,
        result: String,
        timestamp: u64,
    }
    
    public struct StakeUpdated has copy, drop {
        validator: address,
        old_stake: u64,
        new_stake: u64,
        old_weight: u64,
        new_weight: u64,
    }
    
    public struct CertificateAdded has copy, drop {
        validator: address,
        certificate_id: ID,
        certificate_type: String,
        value_added: u64,
        new_knowledge_score: u64,
    }
    
    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        
        // Create governance configuration
        let mut config = GovernanceConfig {
            id: object::new(ctx),
            proposal_deposit: DEFAULT_PROPOSAL_DEPOSIT,
            voting_period: DEFAULT_VOTING_PERIOD,
            execution_delay: DEFAULT_EXECUTION_DELAY,
            quorum_percentage: DEFAULT_QUORUM_PERCENTAGE,
            approval_threshold: DEFAULT_APPROVAL_THRESHOLD,
            minimum_stake: STAKE_TIER_STARTER,
            bootstrap_end_time: 0,
            genesis_validators: vector::empty(),
            certificate_base_values: table::new(ctx),
            admin,
            next_proposal_id: 1,
        };
        
        // Initialize default certificate values
        table::add(&mut config.certificate_base_values, string::utf8(b"Basic"), 100);
        table::add(&mut config.certificate_base_values, string::utf8(b"Advanced"), 200);
        table::add(&mut config.certificate_base_values, string::utf8(b"Expert"), 500);
        
        // Create validator pool
        let pool = ValidatorPool {
            id: object::new(ctx),
            active_validators: table::new(ctx),
            total_weight: 0,
            total_stake: 0,
            admin,
        };
        
        // Create proposal registry
        let proposal_registry = ProposalRegistry {
            id: object::new(ctx),
            proposals: table::new(ctx),
            voting_records: table::new(ctx),
            admin,
        };
        
        // Create admin capability
        let admin_cap = GovernanceAdminCap {
            id: object::new(ctx),
        };
        
        // Share the objects first
        transfer::share_object(config);
        transfer::share_object(pool);
        transfer::share_object(proposal_registry);
        transfer::public_transfer(admin_cap, admin);
        
        // Emit event with placeholder IDs to avoid circular references
        event::emit(GovernanceInitialized {
            config_id: object::id_from_address(@0x0),
            pool_id: object::id_from_address(@0x0),
            proposal_registry_id: object::id_from_address(@0x0),
            admin,
            timestamp: 0,
        });
    }
    
    // =============== Admin Functions ===============
    
    /// Initialize governance with clock (admin only)
    public entry fun initialize_governance(
        config: &mut GovernanceConfig,
        _admin_cap: &GovernanceAdminCap,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        
        let current_time = clock::timestamp_ms(clock);
        config.bootstrap_end_time = current_time + BOOTSTRAP_PHASE_DURATION;
    }
    
    /// Update governance parameters (admin only)
    public entry fun update_governance_parameters(
        config: &mut GovernanceConfig,
        new_minimum_stake: u64,
        new_proposal_deposit: u64,
        new_voting_period: u64,
        new_quorum: u8,
        new_threshold: u8,
        _admin_cap: &GovernanceAdminCap,
        ctx: &TxContext,
    ) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        
        config.minimum_stake = new_minimum_stake;
        config.proposal_deposit = new_proposal_deposit;
        config.voting_period = new_voting_period;
        config.quorum_percentage = new_quorum;
        config.approval_threshold = new_threshold;
    }
    
    /// Add or update certificate base value (admin only)
    public entry fun update_certificate_value(
        config: &mut GovernanceConfig,
        certificate_type: String,
        base_value: u64,
        _admin_cap: &GovernanceAdminCap,
        ctx: &TxContext,
    ) {
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        
        if (table::contains(&config.certificate_base_values, certificate_type)) {
            let value_ref = table::borrow_mut(&mut config.certificate_base_values, certificate_type);
            *value_ref = base_value;
        } else {
            table::add(&mut config.certificate_base_values, certificate_type, base_value);
        };
    }
    
    // =============== Validator Registration ===============
    
    /// Register as genesis validator with treasury integration
    public entry fun register_genesis_validator(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        treasury: &mut Treasury,
        stake_amount: u64,
        payment: &mut Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate conditions
        assert!(current_time < config.bootstrap_end_time, E_GENESIS_PHASE_ENDED);
        assert!(vector::length(&config.genesis_validators) < GENESIS_VALIDATOR_COUNT, E_GENESIS_PHASE_ACTIVE);
        assert!(stake_amount >= config.minimum_stake, E_INSUFFICIENT_STAKE);
        assert!(coin::value(payment) >= stake_amount, E_INSUFFICIENT_COIN_VALUE);
        assert!(!table::contains(&pool.active_validators, validator_address), E_ALREADY_VALIDATOR);
        
        // Extract stake from payment
        let stake = coin::split(payment, stake_amount, ctx);
        
        // Create validator
        let validator = PoKValidator {
            address: validator_address,
            stake_amount: coin::into_balance(stake),
            stake_tier: calculate_stake_tier(stake_amount),
            certificates: vector::empty(),
            knowledge_score: 100, // Base score for genesis validators
            validation_count: 0,
            consensus_accuracy: 100,
            state: VALIDATOR_STATE_ACTIVE,
            weight: calculate_weight(100, stake_amount, 100),
            last_validation: current_time,
            is_genesis: true,
            registration_time: current_time,
        };
        
        // Record staking position in treasury
        core::treasury::create_validator_staking_position(
            treasury,
            validator_address,
            stake_amount,
            ctx
        );
        
        // Update state
        vector::push_back(&mut config.genesis_validators, validator_address);
        pool.total_weight = pool.total_weight + validator.weight;
        pool.total_stake = pool.total_stake + stake_amount;
        table::add(&mut pool.active_validators, validator_address, validator);
        
        event::emit(ValidatorRegistered {
            validator: validator_address,
            stake_amount,
            knowledge_score: 100,
            is_genesis: true,
            timestamp: current_time,
        });
    }
    
    /// Register as regular validator with certificates and treasury integration
    public entry fun register_validator_with_certificates(
        config: &GovernanceConfig,
        pool: &mut ValidatorPool,
        treasury: &mut Treasury,
        certificate_ids: vector<ID>,
        certificate_types: vector<String>,
        skill_levels: vector<u8>,
        earned_dates: vector<u64>,
        stake_amount: u64,
        payment: &mut Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate conditions
        assert!(current_time >= config.bootstrap_end_time, E_GENESIS_PHASE_ACTIVE);
        assert!(vector::length(&certificate_ids) >= MIN_CERTIFICATES_FOR_NON_GENESIS, E_INSUFFICIENT_KNOWLEDGE_SCORE);
        assert!(stake_amount >= config.minimum_stake, E_INSUFFICIENT_STAKE);
        assert!(coin::value(payment) >= stake_amount, E_INSUFFICIENT_COIN_VALUE);
        assert!(!table::contains(&pool.active_validators, validator_address), E_ALREADY_VALIDATOR);
        
        // Validate certificate arrays have same length
        let cert_count = vector::length(&certificate_ids);
        assert!(vector::length(&certificate_types) == cert_count, E_INSUFFICIENT_KNOWLEDGE_SCORE);
        assert!(vector::length(&skill_levels) == cert_count, E_INSUFFICIENT_KNOWLEDGE_SCORE);
        assert!(vector::length(&earned_dates) == cert_count, E_INSUFFICIENT_KNOWLEDGE_SCORE);
        
        // Extract stake from payment
        let stake = coin::split(payment, stake_amount, ctx);
        
        // Process certificates
        let (certificates, knowledge_score) = process_certificates(
            config,
            certificate_ids,
            certificate_types,
            skill_levels,
            earned_dates,
            current_time
        );
        
        // Create validator
        let validator = PoKValidator {
            address: validator_address,
            stake_amount: coin::into_balance(stake),
            stake_tier: calculate_stake_tier(stake_amount),
            certificates,
            knowledge_score,
            validation_count: 0,
            consensus_accuracy: 100,
            state: VALIDATOR_STATE_ACTIVE,
            weight: calculate_weight(knowledge_score, stake_amount, 100),
            last_validation: current_time,
            is_genesis: false,
            registration_time: current_time,
        };
        
        // Record staking position in treasury (for non-genesis validators)
        core::treasury::create_validator_staking_position(
            treasury,
            validator_address,
            stake_amount,
            ctx
        );
        
        // Update state
        pool.total_weight = pool.total_weight + validator.weight;
        pool.total_stake = pool.total_stake + stake_amount;
        table::add(&mut pool.active_validators, validator_address, validator);
        
        event::emit(ValidatorRegistered {
            validator: validator_address,
            stake_amount,
            knowledge_score,
            is_genesis: false,
            timestamp: current_time,
        });
    }
    
    /// Add additional stake to existing validator with treasury integration
    public entry fun add_stake(
        pool: &mut ValidatorPool,
        treasury: &mut Treasury,
        additional_amount: u64,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        assert!(coin::value(payment) >= additional_amount, E_INSUFFICIENT_COIN_VALUE);
        
        // Extract additional stake
        let additional_stake = coin::split(payment, additional_amount, ctx);
        
        // Update validator
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        let old_stake = balance::value(&validator.stake_amount);
        let old_weight = validator.weight;
        
        balance::join(&mut validator.stake_amount, coin::into_balance(additional_stake));
        
        let new_stake_amount = balance::value(&validator.stake_amount);
        validator.stake_tier = calculate_stake_tier(new_stake_amount);
        validator.weight = calculate_weight(validator.knowledge_score, new_stake_amount, validator.consensus_accuracy);
        
        // Update treasury staking position
        core::treasury::update_staking_position_stake(
            treasury,
            validator_address,
            additional_amount,
            ctx
        );
        
        // Update pool totals
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        pool.total_stake = pool.total_stake + additional_amount;
        
        event::emit(StakeUpdated {
            validator: validator_address,
            old_stake,
            new_stake: new_stake_amount,
            old_weight,
            new_weight: validator.weight,
        });
    }
    
    /// Withdraw stake (partial or full) with treasury integration
    public entry fun withdraw_stake(
        pool: &mut ValidatorPool,
        treasury: &mut Treasury,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        assert!(balance::value(&validator.stake_amount) >= amount, E_INSUFFICIENT_STAKE);
        
        let old_stake = balance::value(&validator.stake_amount);
        let old_weight = validator.weight;
        
        let withdrawn = balance::split(&mut validator.stake_amount, amount);
        
        let new_stake_amount = balance::value(&validator.stake_amount);
        validator.stake_tier = calculate_stake_tier(new_stake_amount);
        validator.weight = calculate_weight(validator.knowledge_score, new_stake_amount, validator.consensus_accuracy);
        
        // Update treasury staking position
        core::treasury::reduce_staking_position_stake(
            treasury,
            validator_address,
            amount,
            ctx
        );
        
        // Update pool totals
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        pool.total_stake = pool.total_stake - amount;
        
        // Transfer withdrawn stake
        let withdrawn_coin = coin::from_balance(withdrawn, ctx);
        transfer::public_transfer(withdrawn_coin, validator_address);
        
        event::emit(StakeUpdated {
            validator: validator_address,
            old_stake,
            new_stake: new_stake_amount,
            old_weight,
            new_weight: validator.weight,
        });
    }
    
    /// Claim staking rewards as validator
    public entry fun claim_validator_staking_rewards(
        pool: &ValidatorPool,
        treasury: &mut Treasury,
        auto_compound: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        
        // Claim rewards through treasury
        let reward_coin = core::treasury::withdraw_staking_rewards(
            treasury,
            validator_address,
            auto_compound,
            clock,
            ctx
        );
        
        // If not auto-compounding, transfer rewards to validator
        if (!auto_compound && coin::value(&reward_coin) > 0) {
            transfer::public_transfer(reward_coin, validator_address);
        } else {
            // If auto-compounding or zero rewards, destroy the zero coin
            coin::destroy_zero(reward_coin);
        };
    }

    /// Add certificate to existing validator
    public entry fun add_certificate(
        config: &GovernanceConfig,
        pool: &mut ValidatorPool,
        certificate_id: ID,
        certificate_type: String,
        skill_level: u8,
        earned_date: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        assert!(table::contains(&pool.active_validators, validator_address), E_NOT_VALIDATOR);
        
        let current_time = clock::timestamp_ms(clock);
        let validator = table::borrow_mut(&mut pool.active_validators, validator_address);
        
        // Calculate certificate value
        let base_value = get_certificate_base_value(config, &certificate_type);
        let current_value = base_value * (skill_level as u64);
        
        // Create certificate info
        let cert_info = CertificateInfo {
            certificate_id,
            certificate_type,
            skill_level,
            earned_date,
            base_value,
            current_value,
        };
        
        // Add to validator
        vector::push_back(&mut validator.certificates, cert_info);
        
        let old_knowledge_score = validator.knowledge_score;
        let old_weight = validator.weight;
        
        validator.knowledge_score = validator.knowledge_score + current_value;
        validator.weight = calculate_weight(
            validator.knowledge_score,
            balance::value(&validator.stake_amount),
            validator.consensus_accuracy
        );
        
        // Update pool weight
        pool.total_weight = pool.total_weight - old_weight + validator.weight;
        
        event::emit(CertificateAdded {
            validator: validator_address,
            certificate_id,
            certificate_type,
            value_added: current_value,
            new_knowledge_score: validator.knowledge_score,
        });
    }
    
    // =============== Proposal System ===============
    
    /// Create a new governance proposal
    public entry fun create_proposal(
        config: &mut GovernanceConfig,
        registry: &mut ProposalRegistry,
        pool: &ValidatorPool,
        proposal_type: u8,
        title: String,
        description: String,
        target_parameter: Option<String>,
        new_value: Option<vector<u8>>,
        payment: &mut Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let proposer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate proposer is a validator
        assert!(table::contains(&pool.active_validators, proposer), E_NOT_VALIDATOR);
        
        // Validate deposit
        assert!(coin::value(payment) >= config.proposal_deposit, E_INSUFFICIENT_COIN_VALUE);
        let deposit = coin::split(payment, config.proposal_deposit, ctx);
        
        // Create proposal
        let proposal_id = config.next_proposal_id;
        config.next_proposal_id = proposal_id + 1;
        
        let proposal = GovernanceProposal {
            id: proposal_id,
            proposer,
            proposal_type,
            title,
            description,
            target_parameter,
            new_value,
            votes_for: 0,
            votes_against: 0,
            votes_abstain: 0,
            voting_start: current_time,
            voting_end: current_time + config.voting_period,
            execution_time: option::none(),
            status: STATUS_ACTIVE,
            deposit: coin::into_balance(deposit),
        };
        
        // Store proposal and initialize voting records
        table::add(&mut registry.proposals, proposal_id, proposal);
        table::add(&mut registry.voting_records, proposal_id, table::new(ctx));
        
        event::emit(ProposalCreated {
            proposal_id,
            proposer,
            proposal_type,
            title,
            voting_start: current_time,
            voting_end: current_time + config.voting_period,
        });
    }
    
    /// Vote on a proposal
    public entry fun vote(
        registry: &mut ProposalRegistry,
        pool: &ValidatorPool,
        proposal_id: u64,
        vote_type: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let voter = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate voter is a validator
        assert!(table::contains(&pool.active_validators, voter), E_NOT_VALIDATOR);
        
        // Validate proposal exists
        assert!(table::contains(&registry.proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        
        // Get validator voting power
        let validator = table::borrow(&pool.active_validators, voter);
        let voting_power = validator.weight;
        
        // Get proposal and validate timing
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        assert!(current_time >= proposal.voting_start, E_VOTING_NOT_STARTED);
        assert!(current_time <= proposal.voting_end, E_VOTING_ENDED);
        
        // Check if already voted
        let votes = table::borrow_mut(&mut registry.voting_records, proposal_id);
        assert!(!table::contains(votes, voter), E_ALREADY_VOTED);
        
        // Record vote
        let vote_record = VoteRecord {
            voter,
            proposal_id,
            vote_type,
            voting_power,
            timestamp: current_time,
        };
        
        table::add(votes, voter, vote_record);
        
        // Update proposal vote counts
        if (vote_type == VOTE_FOR) {
            proposal.votes_for = proposal.votes_for + voting_power;
        } else if (vote_type == VOTE_AGAINST) {
            proposal.votes_against = proposal.votes_against + voting_power;
        } else if (vote_type == VOTE_ABSTAIN) {
            proposal.votes_abstain = proposal.votes_abstain + voting_power;
        };
        
        event::emit(VoteCast {
            proposal_id,
            voter,
            vote_type,
            voting_power,
            timestamp: current_time,
        });
    }
    
    /// Execute a passed proposal
    public entry fun execute_proposal(
        config: &mut GovernanceConfig,
        registry: &mut ProposalRegistry,
        pool: &ValidatorPool,
        proposal_id: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let executor = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate proposal exists
        assert!(table::contains(&registry.proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        
        let proposal = table::borrow_mut(&mut registry.proposals, proposal_id);
        
        // Validate timing
        assert!(current_time > proposal.voting_end, E_VOTING_NOT_STARTED);
        assert!(proposal.status == STATUS_ACTIVE, E_ALREADY_EXECUTED);
        
        // Check if execution delay has passed
        if (option::is_some(&proposal.execution_time)) {
            assert!(current_time >= *option::borrow(&proposal.execution_time), E_EXECUTION_DELAY_NOT_MET);
        };
        
        // Calculate total votes and check quorum
        let total_votes = proposal.votes_for + proposal.votes_against + proposal.votes_abstain;
        let quorum_required = (pool.total_weight * (config.quorum_percentage as u64)) / 100;
        assert!(total_votes >= quorum_required, E_QUORUM_NOT_MET);
        
        // Check approval threshold
        let approval_threshold = (total_votes * (config.approval_threshold as u64)) / 100;
        
        if (proposal.votes_for >= approval_threshold) {
            // Proposal passed
            proposal.status = STATUS_PASSED;
            
            // Execute based on proposal type
            if (proposal.proposal_type == PROPOSAL_TYPE_PARAMETER) {
                execute_parameter_change(config, proposal);
            };
            
            proposal.status = STATUS_EXECUTED;
            proposal.execution_time = option::some(current_time);
            
            event::emit(ProposalExecuted {
                proposal_id,
                executor,
                result: string::utf8(b"PASSED"),
                timestamp: current_time,
            });
        } else {
            // Proposal rejected
            proposal.status = STATUS_REJECTED;
            
            event::emit(ProposalExecuted {
                proposal_id,
                executor,
                result: string::utf8(b"REJECTED"),
                timestamp: current_time,
            });
        };
        
        // Return deposit to proposer
        let deposit = balance::withdraw_all(&mut proposal.deposit);
        let deposit_coin = coin::from_balance(deposit, ctx);
        transfer::public_transfer(deposit_coin, proposal.proposer);
    }
    
    // =============== Helper Functions ===============
    
    fun calculate_stake_tier(stake_amount: u64): u8 {
        if (stake_amount >= STAKE_TIER_PLATINUM) { 6 }
        else if (stake_amount >= STAKE_TIER_GOLD) { 5 }
        else if (stake_amount >= STAKE_TIER_SILVER) { 4 }
        else if (stake_amount >= STAKE_TIER_BRONZE) { 3 }
        else if (stake_amount >= STAKE_TIER_BASIC) { 2 }
        else { 1 }
    }
    
    fun calculate_weight(knowledge_score: u64, stake_amount: u64, consensus_accuracy: u64): u64 {
        // Knowledge component
        let knowledge = knowledge_score * KNOWLEDGE_WEIGHT_FACTOR;
        
        // Stake component (logarithmic growth)
        let stake_multiplier = math::sqrt(stake_amount / 1_000_000_000) * 100;
        let stake = stake_multiplier * STAKE_WEIGHT_FACTOR;
        
        // Performance component
        let performance = consensus_accuracy * PERFORMANCE_WEIGHT_FACTOR;
        
        (knowledge + stake + performance) / BASE_WEIGHT_DIVISOR
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
            let cert_type = *vector::borrow(&certificate_types, i);
            let skill_level = *vector::borrow(&skill_levels, i);
            let base_value = get_certificate_base_value(config, &cert_type);
            let current_value = base_value * (skill_level as u64);
            
            let cert = CertificateInfo {
                certificate_id: *vector::borrow(&certificate_ids, i),
                certificate_type: cert_type,
                skill_level,
                earned_date: *vector::borrow(&earned_dates, i),
                base_value,
                current_value,
            };
            
            vector::push_back(&mut certificates, cert);
            total_score = total_score + current_value;
            
            i = i + 1;
        };
        
        (certificates, total_score)
    }
    
    fun get_certificate_base_value(config: &GovernanceConfig, cert_type: &String): u64 {
        if (table::contains(&config.certificate_base_values, *cert_type)) {
            *table::borrow(&config.certificate_base_values, *cert_type)
        } else {
            100 // Default base value
        }
    }
    
    fun execute_parameter_change(config: &mut GovernanceConfig, proposal: &GovernanceProposal) {
        if (option::is_some(&proposal.target_parameter) && option::is_some(&proposal.new_value)) {
            let param_name = option::borrow(&proposal.target_parameter);
            // let new_value = option::borrow(&proposal.new_value);
            
            // Example parameter updates
            if (param_name == &string::utf8(b"minimum_stake")) {
                // Would decode new_value and update minimum_stake
                // For now, just a placeholder
            };
        };
    }
    
    // =============== Integration Functions ===============
    
    /// Function for working with Treasury
    public entry fun governance_treasury_action(
        config: &GovernanceConfig,
        pool: &ValidatorPool,
        treasury: &mut Treasury,
        _global_params: &GlobalParameters,
        ctx: &TxContext,
    ) {
        // Example function showing shared object integration
        assert!(tx_context::sender(ctx) == config.admin, E_NOT_AUTHORIZED);
        
        // Treasury operations would go here
        let _ = pool.total_weight; // Use pool to avoid unused variable warning
        let _ = object::id(treasury); // Use treasury to avoid unused variable warning
    }
    
    // =============== View Functions ===============
    
    public fun get_validator_info(pool: &ValidatorPool, validator: address): (u64, u64, u64, u8, bool) {
        if (table::contains(&pool.active_validators, validator)) {
            let val = table::borrow(&pool.active_validators, validator);
            (
                balance::value(&val.stake_amount),
                val.knowledge_score,
                val.weight,
                val.state,
                val.is_genesis
            )
        } else {
            (0, 0, 0, 0, false)
        }
    }
    
    public fun get_proposal_info(registry: &ProposalRegistry, proposal_id: u64): (u8, u64, u64, u64, u64, u64) {
        if (table::contains(&registry.proposals, proposal_id)) {
            let proposal = table::borrow(&registry.proposals, proposal_id);
            (
                proposal.status,
                proposal.votes_for,
                proposal.votes_against,
                proposal.votes_abstain,
                proposal.voting_start,
                proposal.voting_end
            )
        } else {
            (0, 0, 0, 0, 0, 0)
        }
    }
    
    public fun get_pool_stats(pool: &ValidatorPool): (u64, u64, u64) {
        (
            table::length(&pool.active_validators),
            pool.total_weight,
            pool.total_stake
        )
    }
    
    public fun get_governance_config(config: &GovernanceConfig): (u64, u64, u64, u8, u8) {
        (
            config.minimum_stake,
            config.proposal_deposit,
            config.voting_period,
            config.quorum_percentage,
            config.approval_threshold
        )
    }
    
    public fun is_bootstrap_phase(config: &GovernanceConfig, clock: &Clock): bool {
        clock::timestamp_ms(clock) < config.bootstrap_end_time
    }
    
    public fun get_genesis_validators(config: &GovernanceConfig): &vector<address> {
        &config.genesis_validators
    }
    
    /// Get validator staking information from treasury
    public fun get_validator_staking_info(
        pool: &ValidatorPool,
        treasury: &Treasury,
        validator: address
    ): (bool, u64, u64, u64) {
        if (table::contains(&pool.active_validators, validator)) {
            let (stake_amount, start_epoch, accumulated_rewards, reward_rate) = 
                core::treasury::get_staking_position(treasury, validator);
            (true, stake_amount, accumulated_rewards, reward_rate)
        } else {
            (false, 0, 0, 0)
        }
    }
    
    /// Check if validator has pending staking rewards
    public fun get_validator_pending_rewards(
        treasury: &Treasury,
        validator: address,
        current_epoch: u64
    ): u64 {
        let (stake_amount, start_epoch, accumulated_rewards, reward_rate) = 
            core::treasury::get_staking_position(treasury, validator);
        
        if (stake_amount == 0) {
            return 0
        };
        
        // Calculate theoretical pending rewards (simplified calculation)
        let epochs_staked = if (current_epoch > start_epoch) {
            current_epoch - start_epoch
        } else {
            0
        };
        
        let annual_epochs = 365; // Approximate epochs per year
        let basis_points = 10000;
        let epoch_reward_rate = reward_rate / annual_epochs;
        let calculated_rewards = (stake_amount * epoch_reward_rate * epochs_staked) / basis_points;
        
        accumulated_rewards + calculated_rewards
    }
    
    // =============== Test Functions ===============
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
    
    #[test_only]
    public fun create_test_validator(
        pool: &mut ValidatorPool,
        validator_addr: address,
        stake_amount: u64,
        knowledge_score: u64,
        is_genesis: bool,
        ctx: &mut TxContext,
    ) {
        let validator = PoKValidator {
            address: validator_addr,
            stake_amount: balance::create_for_testing(stake_amount),
            stake_tier: calculate_stake_tier(stake_amount),
            certificates: vector::empty(),
            knowledge_score,
            validation_count: 0,
            consensus_accuracy: 100,
            state: VALIDATOR_STATE_ACTIVE,
            weight: calculate_weight(knowledge_score, stake_amount, 100),
            last_validation: 0,
            is_genesis,
            registration_time: 0,
        };
        
        pool.total_weight = pool.total_weight + validator.weight;
        pool.total_stake = pool.total_stake + stake_amount;
        table::add(&mut pool.active_validators, validator_addr, validator);
    }
}