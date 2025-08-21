module suiverse_core::parameters {
    use std::string::{Self as string, String};
    use std::option::{Self as option, Option};
    use sui::object::{ID, UID};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::table::{Self as table, Table};
    use sui::bcs;
    use sui::transfer;

    // =============== Constants ===============
    
    // Error codes
    const E_INVALID_KEY: u64 = 1001;
    const E_INVALID_VALUE: u64 = 1002;
    const E_NOT_AUTHORIZED: u64 = 1003;
    const E_PARAMETER_NOT_FOUND: u64 = 1004;
    const E_VALUE_OUT_OF_RANGE: u64 = 1005;
    const E_INVALID_BATCH_SIZE: u64 = 1006;
    const E_BATCH_VALIDATION_FAILED: u64 = 1007;
    const E_PARAMETER_LOCKED: u64 = 1008;
    const E_INVALID_CERTIFICATE_VALUE: u64 = 1009;
    const E_INVALID_STAKE_TIER: u64 = 1010;
    const E_INVALID_PROPOSAL_ID: u64 = 1011;

    // Default economic parameters (aligned with spec)
    const DEFAULT_QUIZ_CREATION_DEPOSIT: u64 = 2_000_000_000; // 2 SUI
    const DEFAULT_ARTICLE_DEPOSIT_ORIGINAL: u64 = 500_000_000; // 0.5 SUI  
    const DEFAULT_ARTICLE_DEPOSIT_EXTERNAL: u64 = 500_000_000; // 0.5 SUI
    const DEFAULT_PROJECT_DEPOSIT: u64 = 1_000_000_000; // 1 SUI
    const DEFAULT_EXAM_CREATION_DEPOSIT: u64 = 500_000_000_000; // 500 SUI
    const DEFAULT_EXAM_FEE: u64 = 5_000_000_000; // 5 SUI
    const DEFAULT_RETRY_FEE: u64 = 3_000_000_000; // 3 SUI
    const DEFAULT_SKILL_SEARCH_FEE: u64 = 1_000_000_000; // 1 SUI per profile
    const DEFAULT_CONTACT_PURCHASE_FEE: u64 = 2_000_000_000; // 2 SUI
    const DEFAULT_PROPOSAL_DEPOSIT: u64 = 100_000_000_000; // 100 SUI
    const DEFAULT_PROPOSAL_BONUS: u64 = 10_000_000_000; // 10 SUI bonus

    // Validation parameters (aligned with spec)
    const DEFAULT_ARTICLE_APPROVAL_THRESHOLD: u8 = 7; // 7/10 score
    const DEFAULT_PROJECT_APPROVAL_THRESHOLD: u8 = 7; // 7/10 score
    const DEFAULT_QUIZ_APPROVAL_THRESHOLD: u8 = 8; // 8/10 score
    const DEFAULT_EXAM_APPROVAL_THRESHOLD: u8 = 9; // 9/10 score
    const DEFAULT_ARTICLE_VALIDATOR_COUNT: u8 = 3;
    const DEFAULT_PROJECT_VALIDATOR_COUNT: u8 = 5;
    const DEFAULT_QUIZ_VALIDATOR_COUNT: u8 = 3;
    const DEFAULT_EXAM_VALIDATOR_COUNT: u8 = 5;
    const DEFAULT_VALIDATION_TIME_LIMIT: u64 = 172800000; // 48 hours in ms
    const DEFAULT_CONSENSUS_THRESHOLD: u8 = 2; // Minimum validators to agree

    // Content reward parameters (aligned with spec)
    const DEFAULT_ORIGINAL_ARTICLE_VIEW_REWARD: u64 = 1_000_000; // 0.001 SUI
    const DEFAULT_EXTERNAL_ARTICLE_VIEW_REWARD: u64 = 500_000; // 0.0005 SUI
    const DEFAULT_PROJECT_VIEW_REWARD: u64 = 800_000; // 0.0008 SUI
    const DEFAULT_QUIZ_USAGE_REWARD: u64 = 20_000_000; // 0.02 SUI
    const DEFAULT_VALIDATOR_REVIEW_REWARD: u64 = 500_000_000; // 0.5 SUI
    const DEFAULT_QUALITY_BONUS_ARTICLE: u64 = 10_000_000; // 0.01 SUI for rating >4.5
    const DEFAULT_QUALITY_BONUS_QUIZ: u64 = 50_000_000; // 0.05 SUI for top 10%
    const DEFAULT_COMPLETION_BONUS_PROJECT: u64 = 5_000_000; // 0.005 SUI
    const DEFAULT_CONTACT_REFERRAL_RATE: u64 = 70; // 70% to candidate, 30% to platform
    const DEFAULT_CERTIFICATE_ROYALTY_RATE: u64 = 5; // 5% royalty on trades

    // System parameters
    const DEFAULT_EPOCH_DURATION: u64 = 86400000; // 24 hours in ms
    const DEFAULT_MAX_PROPOSALS_PER_USER: u64 = 3;
    const DEFAULT_CONTENT_VIEW_GAS_COST: u64 = 1000;
    const DEFAULT_MIN_CERTIFICATES_FOR_VALIDATOR: u64 = 3; // Non-genesis validators
    
    // PoK-specific parameters
    const DEFAULT_MINIMUM_STAKE: u64 = 10_000_000_000; // 10 SUI starter tier
    const DEFAULT_GENESIS_VALIDATOR_COUNT: u64 = 20;
    const DEFAULT_BOOTSTRAP_DURATION: u64 = 2592000000; // 30 days
    const DEFAULT_CERTIFICATE_REBALANCE_INTERVAL: u64 = 86400000; // 24 hours
    const DEFAULT_VALIDATOR_SELECTION_ALGORITHM: u8 = 2; // Weighted by default
    const DEFAULT_MAX_VALIDATORS_PER_CONTENT: u8 = 5;
    
    // Certificate value parameters
    const DEFAULT_CERTIFICATE_BASE_VALUE: u64 = 100;
    const DEFAULT_CERTIFICATE_AGE_DECAY_MONTHLY: u64 = 5; // 5% per month
    const DEFAULT_CERTIFICATE_MAX_DECAY: u64 = 50; // Maximum 50% decay
    const DEFAULT_CERTIFICATE_BOOST_MULTIPLIER: u64 = 150; // 50% boost when staked
    const DEFAULT_SCARCITY_BASE_MULTIPLIER: u64 = 10000;
    const DEFAULT_DIFFICULTY_BASE_MULTIPLIER: u64 = 100;
    
    // Slashing parameters
    const DEFAULT_SLASH_LAZY_VALIDATION: u64 = 10; // 10% for random approvals
    const DEFAULT_SLASH_WRONG_CONSENSUS: u64 = 5; // 5% for honest mistakes
    const DEFAULT_SLASH_MALICIOUS_APPROVAL: u64 = 50; // 50% for approving plagiarism
    const DEFAULT_SLASH_COLLUSION: u64 = 100; // 100% for coordinated attacks
    const DEFAULT_MAX_SLASH_CAP: u64 = 50; // Bootstrap phase protection
    
    // Weight calculation parameters
    const DEFAULT_KNOWLEDGE_WEIGHT_FACTOR: u64 = 100;
    const DEFAULT_STAKE_WEIGHT_FACTOR: u64 = 100;
    const DEFAULT_PERFORMANCE_WEIGHT_FACTOR: u64 = 100;
    const DEFAULT_BASE_WEIGHT_DIVISOR: u64 = 10000;

    // Parameter categories (expanded for PoK)
    const CATEGORY_ECONOMIC: u8 = 1;
    const CATEGORY_VALIDATION: u8 = 2;
    const CATEGORY_REWARD: u8 = 3;
    const CATEGORY_SYSTEM: u8 = 4;
    const CATEGORY_GOVERNANCE: u8 = 5;
    const CATEGORY_POK_CERTIFICATE: u8 = 6;
    const CATEGORY_POK_STAKE: u8 = 7;
    const CATEGORY_POK_SLASHING: u8 = 8;
    const CATEGORY_POK_WEIGHT: u8 = 9;
    
    // Batch operation limits
    const MAX_BATCH_UPDATE_SIZE: u64 = 20;
    
    // Parameter lock types
    const LOCK_TYPE_NONE: u8 = 0;
    const LOCK_TYPE_GOVERNANCE_ONLY: u8 = 1;
    const LOCK_TYPE_EMERGENCY: u8 = 2;
    const LOCK_TYPE_BOOTSTRAP: u8 = 3;
    
    // Stake tier levels
    const STAKE_TIER_STARTER: u8 = 1;
    const STAKE_TIER_BASIC: u8 = 2;
    const STAKE_TIER_BRONZE: u8 = 3;
    const STAKE_TIER_SILVER: u8 = 4;
    const STAKE_TIER_GOLD: u8 = 5;
    const STAKE_TIER_PLATINUM: u8 = 6;

    // =============== Structs ===============
    
    /// Economic parameters for deposits, fees, and bonuses
    public struct EconomicParameters has store {
        quiz_creation_deposit: u64,
        article_deposit_original: u64,
        article_deposit_external: u64,
        project_deposit: u64,
        exam_creation_deposit: u64,
        exam_fee: u64,
        retry_fee: u64,
        skill_search_fee: u64,
        contact_purchase_fee: u64,
        proposal_deposit: u64,
        proposal_bonus: u64,
    }
    
    /// Validation thresholds and validator counts
    public struct ValidationParameters has store {
        article_approval_threshold: u8,
        project_approval_threshold: u8,
        quiz_approval_threshold: u8,
        exam_approval_threshold: u8,
        article_validator_count: u8,
        project_validator_count: u8,
        quiz_validator_count: u8,
        exam_validator_count: u8,
        validation_time_limit: u64,
        consensus_threshold: u8,
    }
    
    /// Content reward and referral parameters
    public struct RewardParameters has store {
        original_article_view_reward: u64,
        external_article_view_reward: u64,
        project_view_reward: u64,
        quiz_usage_reward: u64,
        validator_review_reward: u64,
        quality_bonus_article: u64,
        quality_bonus_quiz: u64,
        completion_bonus_project: u64,
        contact_referral_rate: u64,
        certificate_royalty_rate: u64,
    }
    
    /// System-level configuration parameters
    public struct SystemParameters has store {
        epoch_duration: u64,
        max_proposals_per_user: u64,
        content_view_gas_cost: u64,
        min_certificates_for_validator: u64,
    }
    
    /// Governance and voting parameters
    public struct GovernanceParameters has store {
        voting_period: u64,
        execution_delay: u64,
        quorum_threshold: u64,
    }
    
    /// Proof of Knowledge core parameters
    public struct PoKCoreParameters has store {
        minimum_stake: u64,
        genesis_validator_count: u64,
        bootstrap_duration: u64,
        certificate_rebalance_interval: u64,
        validator_selection_algorithm: u8,
        max_validators_per_content: u8,
    }
    
    /// Certificate value and decay parameters
    public struct CertificateParameters has store {
        certificate_base_value: u64,
        certificate_age_decay_monthly: u64,
        certificate_max_decay: u64,
        certificate_boost_multiplier: u64,
        scarcity_base_multiplier: u64,
        difficulty_base_multiplier: u64,
    }
    
    /// Slashing penalties and caps
    public struct SlashingParameters has store {
        slash_lazy_validation: u64,
        slash_wrong_consensus: u64,
        slash_malicious_approval: u64,
        slash_collusion: u64,
        max_slash_cap: u64,
    }
    
    /// Weight calculation factors
    public struct WeightParameters has store {
        knowledge_weight_factor: u64,
        stake_weight_factor: u64,
        performance_weight_factor: u64,
        base_weight_divisor: u64,
    }
    
    /// Main system parameters container with smaller sub-structs
    public struct GlobalParameters has key {
        id: UID,
        
        // Parameter groups
        economic: EconomicParameters,
        validation: ValidationParameters,
        rewards: RewardParameters,
        system: SystemParameters,
        governance: GovernanceParameters,
        pok_core: PoKCoreParameters,
        certificates: CertificateParameters,
        slashing: SlashingParameters,
        weights: WeightParameters,
        
        // Dynamic data tables
        stake_tiers: Table<u8, StakeTierConfig>,
        certificate_values: Table<String, u64>,
        parameter_locks: Table<String, ParameterLock>,
        pending_batch_updates: Table<ID, BatchUpdate>,
        extended_params: Table<String, vector<u8>>,
        parameter_history: Table<String, vector<ParameterChange>>,
        
        // Version tracking
        version: u64,
        last_major_update: u64,
    }

    /// Enhanced parameter change record for auditing
    public struct ParameterChange has copy, drop, store {
        key: String,
        old_value: vector<u8>,
        new_value: vector<u8>,
        changed_by: address,
        timestamp: u64,
        category: u8,
        proposal_id: Option<ID>,
        validation_passed: bool,
        impact_level: u8, // 1: Low, 2: Medium, 3: High, 4: Critical
    }
    
    /// Stake tier configuration
    public struct StakeTierConfig has copy, drop, store {
        tier_name: String,
        minimum_stake: u64,
        weight_multiplier: u64,
        slash_protection: u64, // Percentage protection
        reward_multiplier: u64,
        tier_level: u8,
    }
    
    /// Parameter access control
    public struct ParameterLock has store, drop {
        lock_type: u8,
        locked_until: Option<u64>,
        locked_by: address,
        reason: String,
    }
    
    /// Batch parameter update
    public struct BatchUpdate has store {
        updates: vector<ParameterUpdate>,
        proposer: address,
        proposal_id: ID,
        created_at: u64,
        executed: bool,
    }
    
    /// Individual parameter update in batch
    public struct ParameterUpdate has copy, drop, store {
        key: String,
        value: vector<u8>,
        category: u8,
    }

    // =============== Events ===============
    
    public struct ParameterUpdated has copy, drop {
        key: String,
        old_value: vector<u8>,
        new_value: vector<u8>,
        changed_by: address,
        timestamp: u64,
        category: u8,
        proposal_id: Option<ID>,
    }
    
    public struct ParameterBatchUpdated has copy, drop {
        batch_id: ID,
        parameter_count: u64,
        proposer: address,
        proposal_id: ID,
        timestamp: u64,
    }
    
    public struct StakeTierUpdated has copy, drop {
        tier_level: u8,
        old_config: StakeTierConfig,
        new_config: StakeTierConfig,
        updated_by: address,
        timestamp: u64,
    }
    
    public struct CertificateValueUpdated has copy, drop {
        certificate_type: String,
        old_value: u64,
        new_value: u64,
        updated_by: address,
        timestamp: u64,
    }
    
    public struct ParameterLocked has copy, drop {
        key: String,
        lock_type: u8,
        locked_until: Option<u64>,
        locked_by: address,
        reason: String,
    }
    
    public struct ParameterUnlocked has copy, drop {
        key: String,
        unlocked_by: address,
        timestamp: u64,
    }

    public struct ParametersInitialized has copy, drop {
        parameters_id: address,
        version: u64,
        bootstrap_end_time: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let params = initialize_parameters(ctx);
        let params_address = object::uid_to_address(&params.id);
        let bootstrap_end_time = params.pok_core.bootstrap_duration;
        
        event::emit(ParametersInitialized {
            parameters_id: params_address,
            version: 1,
            bootstrap_end_time,
        });
        
        transfer::share_object(params);
    }

    // =============== Public Functions ===============
    
    /// Initialize enhanced system parameters with PoK defaults
    public fun initialize_parameters(ctx: &mut TxContext): GlobalParameters {
        let mut params = GlobalParameters {
            id: object::new(ctx),
            
            // Economic Parameters
            economic: EconomicParameters {
                quiz_creation_deposit: DEFAULT_QUIZ_CREATION_DEPOSIT,
                article_deposit_original: DEFAULT_ARTICLE_DEPOSIT_ORIGINAL,
                article_deposit_external: DEFAULT_ARTICLE_DEPOSIT_EXTERNAL,
                project_deposit: DEFAULT_PROJECT_DEPOSIT,
                exam_creation_deposit: DEFAULT_EXAM_CREATION_DEPOSIT,
                exam_fee: DEFAULT_EXAM_FEE,
                retry_fee: DEFAULT_RETRY_FEE,
                skill_search_fee: DEFAULT_SKILL_SEARCH_FEE,
                contact_purchase_fee: DEFAULT_CONTACT_PURCHASE_FEE,
                proposal_deposit: DEFAULT_PROPOSAL_DEPOSIT,
                proposal_bonus: DEFAULT_PROPOSAL_BONUS,
            },
            
            // Validation Parameters
            validation: ValidationParameters {
                article_approval_threshold: DEFAULT_ARTICLE_APPROVAL_THRESHOLD,
                project_approval_threshold: DEFAULT_PROJECT_APPROVAL_THRESHOLD,
                quiz_approval_threshold: DEFAULT_QUIZ_APPROVAL_THRESHOLD,
                exam_approval_threshold: DEFAULT_EXAM_APPROVAL_THRESHOLD,
                article_validator_count: DEFAULT_ARTICLE_VALIDATOR_COUNT,
                project_validator_count: DEFAULT_PROJECT_VALIDATOR_COUNT,
                quiz_validator_count: DEFAULT_QUIZ_VALIDATOR_COUNT,
                exam_validator_count: DEFAULT_EXAM_VALIDATOR_COUNT,
                validation_time_limit: DEFAULT_VALIDATION_TIME_LIMIT,
                consensus_threshold: DEFAULT_CONSENSUS_THRESHOLD,
            },
            
            // Content Reward Parameters
            rewards: RewardParameters {
                original_article_view_reward: DEFAULT_ORIGINAL_ARTICLE_VIEW_REWARD,
                external_article_view_reward: DEFAULT_EXTERNAL_ARTICLE_VIEW_REWARD,
                project_view_reward: DEFAULT_PROJECT_VIEW_REWARD,
                quiz_usage_reward: DEFAULT_QUIZ_USAGE_REWARD,
                validator_review_reward: DEFAULT_VALIDATOR_REVIEW_REWARD,
                quality_bonus_article: DEFAULT_QUALITY_BONUS_ARTICLE,
                quality_bonus_quiz: DEFAULT_QUALITY_BONUS_QUIZ,
                completion_bonus_project: DEFAULT_COMPLETION_BONUS_PROJECT,
                contact_referral_rate: DEFAULT_CONTACT_REFERRAL_RATE,
                certificate_royalty_rate: DEFAULT_CERTIFICATE_ROYALTY_RATE,
            },
            
            // System Parameters
            system: SystemParameters {
                epoch_duration: DEFAULT_EPOCH_DURATION,
                max_proposals_per_user: DEFAULT_MAX_PROPOSALS_PER_USER,
                content_view_gas_cost: DEFAULT_CONTENT_VIEW_GAS_COST,
                min_certificates_for_validator: DEFAULT_MIN_CERTIFICATES_FOR_VALIDATOR,
            },

            // Governance Parameters
            governance: GovernanceParameters {
                voting_period: 604800000, // 7 days in ms
                execution_delay: 86400000, // 24 hours in ms
                quorum_threshold: 20, // 20% of total voting power
            },
            
            // PoK Core Parameters
            pok_core: PoKCoreParameters {
                minimum_stake: DEFAULT_MINIMUM_STAKE,
                genesis_validator_count: DEFAULT_GENESIS_VALIDATOR_COUNT,
                bootstrap_duration: DEFAULT_BOOTSTRAP_DURATION,
                certificate_rebalance_interval: DEFAULT_CERTIFICATE_REBALANCE_INTERVAL,
                validator_selection_algorithm: DEFAULT_VALIDATOR_SELECTION_ALGORITHM,
                max_validators_per_content: DEFAULT_MAX_VALIDATORS_PER_CONTENT,
            },
            
            // Certificate Value Parameters
            certificates: CertificateParameters {
                certificate_base_value: DEFAULT_CERTIFICATE_BASE_VALUE,
                certificate_age_decay_monthly: DEFAULT_CERTIFICATE_AGE_DECAY_MONTHLY,
                certificate_max_decay: DEFAULT_CERTIFICATE_MAX_DECAY,
                certificate_boost_multiplier: DEFAULT_CERTIFICATE_BOOST_MULTIPLIER,
                scarcity_base_multiplier: DEFAULT_SCARCITY_BASE_MULTIPLIER,
                difficulty_base_multiplier: DEFAULT_DIFFICULTY_BASE_MULTIPLIER,
            },
            
            // Slashing Parameters
            slashing: SlashingParameters {
                slash_lazy_validation: DEFAULT_SLASH_LAZY_VALIDATION,
                slash_wrong_consensus: DEFAULT_SLASH_WRONG_CONSENSUS,
                slash_malicious_approval: DEFAULT_SLASH_MALICIOUS_APPROVAL,
                slash_collusion: DEFAULT_SLASH_COLLUSION,
                max_slash_cap: DEFAULT_MAX_SLASH_CAP,
            },
            
            // Weight Calculation Parameters
            weights: WeightParameters {
                knowledge_weight_factor: DEFAULT_KNOWLEDGE_WEIGHT_FACTOR,
                stake_weight_factor: DEFAULT_STAKE_WEIGHT_FACTOR,
                performance_weight_factor: DEFAULT_PERFORMANCE_WEIGHT_FACTOR,
                base_weight_divisor: DEFAULT_BASE_WEIGHT_DIVISOR,
            },
            
            // Initialize tables
            stake_tiers: table::new(ctx),
            certificate_values: table::new(ctx),
            parameter_locks: table::new(ctx),
            pending_batch_updates: table::new(ctx),
            extended_params: table::new(ctx),
            parameter_history: table::new(ctx),
            
            version: 1,
            last_major_update: 0,
        };
        
        // Initialize default stake tiers
        initialize_default_stake_tiers(&mut params);
        
        // Initialize default certificate values
        initialize_default_certificate_values(&mut params);
        
        params
    }
    
    /// Initialize default stake tier configurations
    fun initialize_default_stake_tiers(params: &mut GlobalParameters) {
        // Starter tier
        table::add(&mut params.stake_tiers, STAKE_TIER_STARTER, StakeTierConfig {
            tier_name: string::utf8(b"Starter"),
            minimum_stake: 10_000_000_000, // 10 SUI
            weight_multiplier: 100, // 1.0x
            slash_protection: 0, // 0% protection
            reward_multiplier: 100, // 1.0x
            tier_level: 1,
        });
        
        // Basic tier
        table::add(&mut params.stake_tiers, STAKE_TIER_BASIC, StakeTierConfig {
            tier_name: string::utf8(b"Basic"),
            minimum_stake: 50_000_000_000, // 50 SUI
            weight_multiplier: 130, // 1.3x
            slash_protection: 10, // 10% protection
            reward_multiplier: 110, // 1.1x
            tier_level: 2,
        });
        
        // Bronze tier
        table::add(&mut params.stake_tiers, STAKE_TIER_BRONZE, StakeTierConfig {
            tier_name: string::utf8(b"Bronze"),
            minimum_stake: 100_000_000_000, // 100 SUI
            weight_multiplier: 150, // 1.5x
            slash_protection: 20, // 20% protection
            reward_multiplier: 120, // 1.2x
            tier_level: 3,
        });
        
        // Silver tier
        table::add(&mut params.stake_tiers, STAKE_TIER_SILVER, StakeTierConfig {
            tier_name: string::utf8(b"Silver"),
            minimum_stake: 500_000_000_000, // 500 SUI
            weight_multiplier: 200, // 2.0x
            slash_protection: 30, // 30% protection
            reward_multiplier: 150, // 1.5x
            tier_level: 4,
        });
        
        // Gold tier
        table::add(&mut params.stake_tiers, STAKE_TIER_GOLD, StakeTierConfig {
            tier_name: string::utf8(b"Gold"),
            minimum_stake: 1_000_000_000_000, // 1,000 SUI
            weight_multiplier: 250, // 2.5x
            slash_protection: 40, // 40% protection
            reward_multiplier: 180, // 1.8x
            tier_level: 5,
        });
        
        // Platinum tier
        table::add(&mut params.stake_tiers, STAKE_TIER_PLATINUM, StakeTierConfig {
            tier_name: string::utf8(b"Platinum"),
            minimum_stake: 5_000_000_000_000, // 5,000 SUI
            weight_multiplier: 300, // 3.0x
            slash_protection: 50, // 50% protection
            reward_multiplier: 200, // 2.0x
            tier_level: 6,
        });
    }
    
    /// Initialize default certificate base values
    fun initialize_default_certificate_values(params: &mut GlobalParameters) {
        // Blockchain Development certificates
        table::add(&mut params.certificate_values, string::utf8(b"Sui Developer"), 200);
        table::add(&mut params.certificate_values, string::utf8(b"Move Expert"), 300);
        table::add(&mut params.certificate_values, string::utf8(b"DeFi Specialist"), 250);
        table::add(&mut params.certificate_values, string::utf8(b"NFT Creator"), 150);
        
        // Web3 General certificates
        table::add(&mut params.certificate_values, string::utf8(b"Web3 Fundamentals"), 100);
        table::add(&mut params.certificate_values, string::utf8(b"Blockchain Basics"), 80);
        table::add(&mut params.certificate_values, string::utf8(b"Crypto Economics"), 120);
        table::add(&mut params.certificate_values, string::utf8(b"DAO Governance"), 180);
        
        // Advanced certificates
        table::add(&mut params.certificate_values, string::utf8(b"Security Auditor"), 400);
        table::add(&mut params.certificate_values, string::utf8(b"Protocol Designer"), 350);
        table::add(&mut params.certificate_values, string::utf8(b"Tokenomics Expert"), 300);
        table::add(&mut params.certificate_values, string::utf8(b"Validator Operator"), 250);
    }

    // =============== Friend Functions (for governance module) ===============
    
    /// Update a parameter value (only callable by governance module)
    public(package) fun update_parameter(
        params: &mut GlobalParameters,
        key: String,
        value: vector<u8>,
        changed_by: address,
        timestamp: u64,
    ) {
        update_parameter_with_proposal(params, key, value, changed_by, timestamp, option::none());
    }
    
    /// Update a parameter value with proposal tracking
    public(package) fun update_parameter_with_proposal(
        params: &mut GlobalParameters,
        key: String,
        value: vector<u8>,
        changed_by: address,
        timestamp: u64,
        proposal_id: Option<ID>,
    ) {
        // Check if parameter is locked
        assert!(!is_parameter_locked(params, &key, timestamp), E_PARAMETER_LOCKED);
        
        // Validate parameter value
        assert!(validate_parameter_value(key, value), E_VALUE_OUT_OF_RANGE);
        
        let category = get_parameter_category(key);
        let impact_level = calculate_impact_level(&key);
        
        let old_value = get_parameter_internal(params, &key);
        
        // Update the parameter
        update_parameter_internal(params, &key, &value);
        
        // Record change in history
        let change = ParameterChange {
            key,
            old_value,
            new_value: value,
            changed_by,
            timestamp,
            category,
            proposal_id,
            validation_passed: true,
            impact_level,
        };
        
        add_parameter_history(params, &key, change);
        
        event::emit(ParameterUpdated {
            key,
            old_value,
            new_value: value,
            changed_by,
            timestamp,
            category,
            proposal_id,
        });
    }
    
    /// Update multiple parameters in a batch
    public(package) fun update_parameters_batch(
        params: &mut GlobalParameters,
        updates: vector<ParameterUpdate>,
        proposer: address,
        proposal_id: ID,
        timestamp: u64,
    ) {
        assert!(vector::length(&updates) <= MAX_BATCH_UPDATE_SIZE, E_INVALID_BATCH_SIZE);
        
        // Validate all updates first
        let mut i = 0;
        let len = vector::length(&updates);
        while (i < len) {
            let update = vector::borrow(&updates, i);
            assert!(validate_parameter_value(update.key, update.value), E_BATCH_VALIDATION_FAILED);
            assert!(!is_parameter_locked(params, &update.key, timestamp), E_PARAMETER_LOCKED);
            i = i + 1;
        };
        
        // Apply all updates
        i = 0;
        while (i < len) {
            let update = vector::borrow(&updates, i);
            update_parameter_with_proposal(
                params,
                update.key,
                update.value,
                proposer,
                timestamp,
                option::some(proposal_id)
            );
            i = i + 1;
        };
        
        // Create batch record
        let batch = BatchUpdate {
            updates,
            proposer,
            proposal_id,
            created_at: timestamp,
            executed: true,
        };
        
        table::add(&mut params.pending_batch_updates, proposal_id, batch);
        
        event::emit(ParameterBatchUpdated {
            batch_id: proposal_id,
            parameter_count: len,
            proposer,
            proposal_id,
            timestamp,
        });
    }
    
    /// Internal parameter update function
    fun update_parameter_internal(
        params: &mut GlobalParameters,
        key: &String,
        value: &vector<u8>,
    ) {
        let key_str = *string::as_bytes(key);
        
        // Handle each parameter by key
        if (key_str == b"quiz_creation_deposit") {
            params.economic.quiz_creation_deposit = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"article_deposit_original") {
            params.economic.article_deposit_original = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"article_deposit_external") {
            params.economic.article_deposit_external = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"project_deposit") {
            params.economic.project_deposit = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"exam_creation_deposit") {
            params.economic.exam_creation_deposit = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"exam_fee") {
            params.economic.exam_fee = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"retry_fee") {
            params.economic.retry_fee = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"skill_search_fee") {
            params.economic.skill_search_fee = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"contact_purchase_fee") {
            params.economic.contact_purchase_fee = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"proposal_deposit") {
            params.economic.proposal_deposit = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"proposal_bonus") {
            params.economic.proposal_bonus = bcs::peel_u64(&mut bcs::new(*value));
        
        // Validation parameters
        } else if (key_str == b"article_approval_threshold") {
            params.validation.article_approval_threshold = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"project_approval_threshold") {
            params.validation.project_approval_threshold = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"quiz_approval_threshold") {
            params.validation.quiz_approval_threshold = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"exam_approval_threshold") {
            params.validation.exam_approval_threshold = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"article_validator_count") {
            params.validation.article_validator_count = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"project_validator_count") {
            params.validation.project_validator_count = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"quiz_validator_count") {
            params.validation.quiz_validator_count = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"exam_validator_count") {
            params.validation.exam_validator_count = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"validation_time_limit") {
            params.validation.validation_time_limit = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"consensus_threshold") {
            params.validation.consensus_threshold = bcs::peel_u8(&mut bcs::new(*value));
        
        // Reward parameters
        } else if (key_str == b"original_article_view_reward") {
            params.rewards.original_article_view_reward = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"external_article_view_reward") {
            params.rewards.external_article_view_reward = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"project_view_reward") {
            params.rewards.project_view_reward = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"quiz_usage_reward") {
            params.rewards.quiz_usage_reward = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"validator_review_reward") {
            params.rewards.validator_review_reward = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"quality_bonus_article") {
            params.rewards.quality_bonus_article = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"quality_bonus_quiz") {
            params.rewards.quality_bonus_quiz = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"completion_bonus_project") {
            params.rewards.completion_bonus_project = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"contact_referral_rate") {
            params.rewards.contact_referral_rate = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"certificate_royalty_rate") {
            params.rewards.certificate_royalty_rate = bcs::peel_u64(&mut bcs::new(*value));
        
        // System parameters
        } else if (key_str == b"epoch_duration") {
            params.system.epoch_duration = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"max_proposals_per_user") {
            params.system.max_proposals_per_user = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"content_view_gas_cost") {
            params.system.content_view_gas_cost = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"min_certificates_for_validator") {
            params.system.min_certificates_for_validator = bcs::peel_u64(&mut bcs::new(*value));
        
        // Governance parameters
        } else if (key_str == b"voting_period") {
            params.governance.voting_period = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"execution_delay") {
            params.governance.execution_delay = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"quorum_threshold") {
            params.governance.quorum_threshold = bcs::peel_u64(&mut bcs::new(*value));
        
        // PoK Core parameters
        } else if (key_str == b"minimum_stake") {
            params.pok_core.minimum_stake = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"genesis_validator_count") {
            params.pok_core.genesis_validator_count = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"bootstrap_duration") {
            params.pok_core.bootstrap_duration = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"certificate_rebalance_interval") {
            params.pok_core.certificate_rebalance_interval = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"validator_selection_algorithm") {
            params.pok_core.validator_selection_algorithm = bcs::peel_u8(&mut bcs::new(*value));
        } else if (key_str == b"max_validators_per_content") {
            params.pok_core.max_validators_per_content = bcs::peel_u8(&mut bcs::new(*value));
        
        // Certificate value parameters
        } else if (key_str == b"certificate_base_value") {
            params.certificates.certificate_base_value = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"certificate_age_decay_monthly") {
            params.certificates.certificate_age_decay_monthly = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"certificate_max_decay") {
            params.certificates.certificate_max_decay = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"certificate_boost_multiplier") {
            params.certificates.certificate_boost_multiplier = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"scarcity_base_multiplier") {
            params.certificates.scarcity_base_multiplier = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"difficulty_base_multiplier") {
            params.certificates.difficulty_base_multiplier = bcs::peel_u64(&mut bcs::new(*value));
        
        // Slashing parameters
        } else if (key_str == b"slash_lazy_validation") {
            params.slashing.slash_lazy_validation = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"slash_wrong_consensus") {
            params.slashing.slash_wrong_consensus = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"slash_malicious_approval") {
            params.slashing.slash_malicious_approval = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"slash_collusion") {
            params.slashing.slash_collusion = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"max_slash_cap") {
            params.slashing.max_slash_cap = bcs::peel_u64(&mut bcs::new(*value));
        
        // Weight calculation parameters
        } else if (key_str == b"knowledge_weight_factor") {
            params.weights.knowledge_weight_factor = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"stake_weight_factor") {
            params.weights.stake_weight_factor = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"performance_weight_factor") {
            params.weights.performance_weight_factor = bcs::peel_u64(&mut bcs::new(*value));
        } else if (key_str == b"base_weight_divisor") {
            params.weights.base_weight_divisor = bcs::peel_u64(&mut bcs::new(*value));
        } else {
            // Handle extended parameters
            if (table::contains(&params.extended_params, *key)) {
                *table::borrow_mut(&mut params.extended_params, *key) = *value;
            } else {
                table::add(&mut params.extended_params, *key, *value);
            }
        };
    }
    
    /// Get parameter value internally
    fun get_parameter_internal(params: &GlobalParameters, key: &String): vector<u8> {
        let key_str = *string::as_bytes(key);
        
        if (key_str == b"quiz_creation_deposit") {
            bcs::to_bytes(&params.economic.quiz_creation_deposit)
        } else if (key_str == b"article_deposit_original") {
            bcs::to_bytes(&params.economic.article_deposit_original)
        } else if (key_str == b"article_deposit_external") {
            bcs::to_bytes(&params.economic.article_deposit_external)
        } else if (key_str == b"project_deposit") {
            bcs::to_bytes(&params.economic.project_deposit)
        } else if (key_str == b"exam_creation_deposit") {
            bcs::to_bytes(&params.economic.exam_creation_deposit)
        } else if (key_str == b"exam_fee") {
            bcs::to_bytes(&params.economic.exam_fee)
        } else if (key_str == b"retry_fee") {
            bcs::to_bytes(&params.economic.retry_fee)
        } else if (key_str == b"skill_search_fee") {
            bcs::to_bytes(&params.economic.skill_search_fee)
        } else if (key_str == b"contact_purchase_fee") {
            bcs::to_bytes(&params.economic.contact_purchase_fee)
        } else if (key_str == b"proposal_deposit") {
            bcs::to_bytes(&params.economic.proposal_deposit)
        } else if (key_str == b"proposal_bonus") {
            bcs::to_bytes(&params.economic.proposal_bonus)
        } else {
            *table::borrow(&params.extended_params, *key)
        }
    }

    // =============== Public Read Functions ===============
    
    /// Get a parameter value by key
    public fun get_parameter(params: &GlobalParameters, key: String): vector<u8> {
        let key_str = *string::as_bytes(&key);
        
        if (key_str == b"quiz_creation_deposit") {
            bcs::to_bytes(&params.economic.quiz_creation_deposit)
        } else if (key_str == b"article_deposit_original") {
            bcs::to_bytes(&params.economic.article_deposit_original)
        } else if (key_str == b"article_deposit_external") {
            bcs::to_bytes(&params.economic.article_deposit_external)
        } else if (key_str == b"project_deposit") {
            bcs::to_bytes(&params.economic.project_deposit)
        } else if (key_str == b"exam_creation_deposit") {
            bcs::to_bytes(&params.economic.exam_creation_deposit)
        } else if (key_str == b"exam_fee") {
            bcs::to_bytes(&params.economic.exam_fee)
        } else if (key_str == b"retry_fee") {
            bcs::to_bytes(&params.economic.retry_fee)
        } else if (key_str == b"skill_search_fee") {
            bcs::to_bytes(&params.economic.skill_search_fee)
        } else if (key_str == b"contact_purchase_fee") {
            bcs::to_bytes(&params.economic.contact_purchase_fee)
        } else if (key_str == b"article_approval_threshold") {
            bcs::to_bytes(&params.validation.article_approval_threshold)
        } else if (key_str == b"project_approval_threshold") {
            bcs::to_bytes(&params.validation.project_approval_threshold)
        } else if (key_str == b"quiz_approval_threshold") {
            bcs::to_bytes(&params.validation.quiz_approval_threshold)
        } else if (key_str == b"exam_approval_threshold") {
            bcs::to_bytes(&params.validation.exam_approval_threshold)
        } else if (key_str == b"article_validator_count") {
            bcs::to_bytes(&params.validation.article_validator_count)
        } else if (key_str == b"project_validator_count") {
            bcs::to_bytes(&params.validation.project_validator_count)
        } else if (key_str == b"quiz_validator_count") {
            bcs::to_bytes(&params.validation.quiz_validator_count)
        } else if (key_str == b"validation_time_limit") {
            bcs::to_bytes(&params.validation.validation_time_limit)
        } else if (key_str == b"original_article_view_reward") {
            bcs::to_bytes(&params.rewards.original_article_view_reward)
        } else if (key_str == b"external_article_view_reward") {
            bcs::to_bytes(&params.rewards.external_article_view_reward)
        } else if (key_str == b"project_view_reward") {
            bcs::to_bytes(&params.rewards.project_view_reward)
        } else if (key_str == b"quiz_usage_reward") {
            bcs::to_bytes(&params.rewards.quiz_usage_reward)
        } else if (key_str == b"validator_review_reward") {
            bcs::to_bytes(&params.rewards.validator_review_reward)
        } else if (key_str == b"epoch_duration") {
            bcs::to_bytes(&params.system.epoch_duration)
        } else if (key_str == b"max_proposals_per_user") {
            bcs::to_bytes(&params.system.max_proposals_per_user)
        } else if (key_str == b"content_view_gas_cost") {
            bcs::to_bytes(&params.system.content_view_gas_cost)
        } else if (key_str == b"minimum_stake") {
            bcs::to_bytes(&params.pok_core.minimum_stake)
        } else if (key_str == b"min_certificates_for_validator") {
            bcs::to_bytes(&params.system.min_certificates_for_validator)
        } else if (key_str == b"voting_period") {
            bcs::to_bytes(&params.governance.voting_period)
        } else if (key_str == b"execution_delay") {
            bcs::to_bytes(&params.governance.execution_delay)
        } else if (key_str == b"quorum_threshold") {
            bcs::to_bytes(&params.governance.quorum_threshold)
        } else if (key_str == b"genesis_validator_count") {
            bcs::to_bytes(&params.pok_core.genesis_validator_count)
        } else if (key_str == b"bootstrap_duration") {
            bcs::to_bytes(&params.pok_core.bootstrap_duration)
        } else if (key_str == b"certificate_rebalance_interval") {
            bcs::to_bytes(&params.pok_core.certificate_rebalance_interval)
        } else if (key_str == b"validator_selection_algorithm") {
            bcs::to_bytes(&params.pok_core.validator_selection_algorithm)
        } else if (key_str == b"max_validators_per_content") {
            bcs::to_bytes(&params.pok_core.max_validators_per_content)
        } else if (key_str == b"certificate_base_value") {
            bcs::to_bytes(&params.certificates.certificate_base_value)
        } else if (key_str == b"certificate_age_decay_monthly") {
            bcs::to_bytes(&params.certificates.certificate_age_decay_monthly)
        } else if (key_str == b"certificate_max_decay") {
            bcs::to_bytes(&params.certificates.certificate_max_decay)
        } else if (key_str == b"certificate_boost_multiplier") {
            bcs::to_bytes(&params.certificates.certificate_boost_multiplier)
        } else if (key_str == b"scarcity_base_multiplier") {
            bcs::to_bytes(&params.certificates.scarcity_base_multiplier)
        } else if (key_str == b"difficulty_base_multiplier") {
            bcs::to_bytes(&params.certificates.difficulty_base_multiplier)
        } else if (key_str == b"slash_lazy_validation") {
            bcs::to_bytes(&params.slashing.slash_lazy_validation)
        } else if (key_str == b"slash_wrong_consensus") {
            bcs::to_bytes(&params.slashing.slash_wrong_consensus)
        } else if (key_str == b"slash_malicious_approval") {
            bcs::to_bytes(&params.slashing.slash_malicious_approval)
        } else if (key_str == b"slash_collusion") {
            bcs::to_bytes(&params.slashing.slash_collusion)
        } else if (key_str == b"max_slash_cap") {
            bcs::to_bytes(&params.slashing.max_slash_cap)
        } else if (key_str == b"knowledge_weight_factor") {
            bcs::to_bytes(&params.weights.knowledge_weight_factor)
        } else if (key_str == b"stake_weight_factor") {
            bcs::to_bytes(&params.weights.stake_weight_factor)
        } else if (key_str == b"performance_weight_factor") {
            bcs::to_bytes(&params.weights.performance_weight_factor)
        } else if (key_str == b"base_weight_divisor") {
            bcs::to_bytes(&params.weights.base_weight_divisor)
        } else {
            assert!(table::contains(&params.extended_params, key), E_PARAMETER_NOT_FOUND);
            *table::borrow(&params.extended_params, key)
        }
    }

    // Direct getter functions for commonly used parameters
    public fun get_quiz_creation_deposit(params: &GlobalParameters): u64 {
        params.economic.quiz_creation_deposit
    }

    public fun get_article_deposit_original(params: &GlobalParameters): u64 {
        params.economic.article_deposit_original
    }

    public fun get_article_deposit_external(params: &GlobalParameters): u64 {
        params.economic.article_deposit_external
    }

    public fun get_project_deposit(params: &GlobalParameters): u64 {
        params.economic.project_deposit
    }

    public fun get_exam_creation_deposit(params: &GlobalParameters): u64 {
        params.economic.exam_creation_deposit
    }

    public fun get_exam_fee(params: &GlobalParameters): u64 {
        params.economic.exam_fee
    }

    public fun get_retry_fee(params: &GlobalParameters): u64 {
        params.economic.retry_fee
    }

    public fun get_skill_search_fee(params: &GlobalParameters): u64 {
        params.economic.skill_search_fee
    }

    public fun get_contact_purchase_fee(params: &GlobalParameters): u64 {
        params.economic.contact_purchase_fee
    }

    public fun get_article_approval_threshold(params: &GlobalParameters): u8 {
        params.validation.article_approval_threshold
    }

    public fun get_project_approval_threshold(params: &GlobalParameters): u8 {
        params.validation.project_approval_threshold
    }

    public fun get_quiz_approval_threshold(params: &GlobalParameters): u8 {
        params.validation.quiz_approval_threshold
    }

    public fun get_exam_approval_threshold(params: &GlobalParameters): u8 {
        params.validation.exam_approval_threshold
    }

    public fun get_article_validator_count(params: &GlobalParameters): u8 {
        params.validation.article_validator_count
    }

    public fun get_project_validator_count(params: &GlobalParameters): u8 {
        params.validation.project_validator_count
    }

    public fun get_quiz_validator_count(params: &GlobalParameters): u8 {
        params.validation.quiz_validator_count
    }

    public fun get_validation_time_limit(params: &GlobalParameters): u64 {
        params.validation.validation_time_limit
    }

    public fun get_original_article_view_reward(params: &GlobalParameters): u64 {
        params.rewards.original_article_view_reward
    }

    public fun get_external_article_view_reward(params: &GlobalParameters): u64 {
        params.rewards.external_article_view_reward
    }

    public fun get_project_view_reward(params: &GlobalParameters): u64 {
        params.rewards.project_view_reward
    }

    public fun get_quiz_usage_reward(params: &GlobalParameters): u64 {
        params.rewards.quiz_usage_reward
    }

    public fun get_validator_review_reward(params: &GlobalParameters): u64 {
        params.rewards.validator_review_reward
    }

    public fun get_epoch_duration(params: &GlobalParameters): u64 {
        params.system.epoch_duration
    }

    public fun get_max_proposals_per_user(params: &GlobalParameters): u64 {
        params.system.max_proposals_per_user
    }

    public fun get_content_view_gas_cost(params: &GlobalParameters): u64 {
        params.system.content_view_gas_cost
    }

    public fun get_minimum_stake(params: &GlobalParameters): u64 {
        params.pok_core.minimum_stake
    }

    public fun get_min_certificates_for_validator(params: &GlobalParameters): u64 {
        params.system.min_certificates_for_validator
    }

    public fun get_voting_period(params: &GlobalParameters): u64 {
        params.governance.voting_period
    }

    public fun get_execution_delay(params: &GlobalParameters): u64 {
        params.governance.execution_delay
    }

    public fun get_quorum_threshold(params: &GlobalParameters): u64 {
        params.governance.quorum_threshold
    }

    public fun get_version(params: &GlobalParameters): u64 {
        params.version
    }

    // =============== PoK-specific Parameter Getters ===============
    
    public fun get_genesis_validator_count(params: &GlobalParameters): u64 {
        params.pok_core.genesis_validator_count
    }

    public fun get_bootstrap_duration(params: &GlobalParameters): u64 {
        params.pok_core.bootstrap_duration
    }

    public fun get_certificate_rebalance_interval(params: &GlobalParameters): u64 {
        params.pok_core.certificate_rebalance_interval
    }

    public fun get_validator_selection_algorithm(params: &GlobalParameters): u8 {
        params.pok_core.validator_selection_algorithm
    }

    public fun get_max_validators_per_content(params: &GlobalParameters): u8 {
        params.pok_core.max_validators_per_content
    }

    public fun get_certificate_base_value(params: &GlobalParameters): u64 {
        params.certificates.certificate_base_value
    }

    public fun get_certificate_age_decay_monthly(params: &GlobalParameters): u64 {
        params.certificates.certificate_age_decay_monthly
    }

    public fun get_certificate_max_decay(params: &GlobalParameters): u64 {
        params.certificates.certificate_max_decay
    }

    public fun get_certificate_boost_multiplier(params: &GlobalParameters): u64 {
        params.certificates.certificate_boost_multiplier
    }

    public fun get_scarcity_base_multiplier(params: &GlobalParameters): u64 {
        params.certificates.scarcity_base_multiplier
    }

    public fun get_difficulty_base_multiplier(params: &GlobalParameters): u64 {
        params.certificates.difficulty_base_multiplier
    }

    public fun get_slash_lazy_validation(params: &GlobalParameters): u64 {
        params.slashing.slash_lazy_validation
    }

    public fun get_slash_wrong_consensus(params: &GlobalParameters): u64 {
        params.slashing.slash_wrong_consensus
    }

    public fun get_slash_malicious_approval(params: &GlobalParameters): u64 {
        params.slashing.slash_malicious_approval
    }

    public fun get_slash_collusion(params: &GlobalParameters): u64 {
        params.slashing.slash_collusion
    }

    public fun get_max_slash_cap(params: &GlobalParameters): u64 {
        params.slashing.max_slash_cap
    }

    public fun get_knowledge_weight_factor(params: &GlobalParameters): u64 {
        params.weights.knowledge_weight_factor
    }

    public fun get_stake_weight_factor(params: &GlobalParameters): u64 {
        params.weights.stake_weight_factor
    }

    public fun get_performance_weight_factor(params: &GlobalParameters): u64 {
        params.weights.performance_weight_factor
    }

    public fun get_base_weight_divisor(params: &GlobalParameters): u64 {
        params.weights.base_weight_divisor
    }

    public fun get_proposal_deposit(params: &GlobalParameters): u64 {
        params.economic.proposal_deposit
    }

    public fun get_proposal_bonus(params: &GlobalParameters): u64 {
        params.economic.proposal_bonus
    }

    public fun get_consensus_threshold(params: &GlobalParameters): u8 {
        params.validation.consensus_threshold
    }

    public fun get_exam_validator_count(params: &GlobalParameters): u8 {
        params.validation.exam_validator_count
    }

    public fun get_quality_bonus_article(params: &GlobalParameters): u64 {
        params.rewards.quality_bonus_article
    }

    public fun get_quality_bonus_quiz(params: &GlobalParameters): u64 {
        params.rewards.quality_bonus_quiz
    }

    public fun get_completion_bonus_project(params: &GlobalParameters): u64 {
        params.rewards.completion_bonus_project
    }

    public fun get_contact_referral_rate(params: &GlobalParameters): u64 {
        params.rewards.contact_referral_rate
    }

    public fun get_certificate_royalty_rate(params: &GlobalParameters): u64 {
        params.rewards.certificate_royalty_rate
    }

    // =============== Stake Tier Functions ===============
    
    /// Get stake tier configuration
    public fun get_stake_tier_config(params: &GlobalParameters, tier: u8): &StakeTierConfig {
        table::borrow(&params.stake_tiers, tier)
    }

    /// Check if stake tier exists
    public fun has_stake_tier(params: &GlobalParameters, tier: u8): bool {
        table::contains(&params.stake_tiers, tier)
    }

    /// Get certificate value by type
    public fun get_certificate_value(params: &GlobalParameters, cert_type: String): u64 {
        if (table::contains(&params.certificate_values, cert_type)) {
            *table::borrow(&params.certificate_values, cert_type)
        } else {
            params.certificates.certificate_base_value // Default base value
        }
    }

    /// Check if certificate type has custom value
    public fun has_certificate_value(params: &GlobalParameters, cert_type: String): bool {
        table::contains(&params.certificate_values, cert_type)
    }

    // =============== Admin Functions ===============
    
    /// Add a new extended parameter (for future extensibility)
    public(package) fun add_extended_parameter(
        params: &mut GlobalParameters,
        key: String,
        value: vector<u8>,
    ) {
        assert!(!table::contains(&params.extended_params, key), E_INVALID_KEY);
        table::add(&mut params.extended_params, key, value);
    }

    /// Update system version
    public(package) fun update_version(params: &mut GlobalParameters, new_version: u64) {
        params.version = new_version;
    }

    /// Update stake tier configuration
    public(package) fun update_stake_tier(
        params: &mut GlobalParameters,
        tier: u8,
        config: StakeTierConfig,
        updated_by: address,
        timestamp: u64,
    ) {
        assert!(tier >= STAKE_TIER_STARTER && tier <= STAKE_TIER_PLATINUM, E_INVALID_STAKE_TIER);
        
        let old_config = if (table::contains(&params.stake_tiers, tier)) {
            *table::borrow(&params.stake_tiers, tier)
        } else {
            StakeTierConfig {
                tier_name: string::utf8(b"Unknown"),
                minimum_stake: 0,
                weight_multiplier: 0,
                slash_protection: 0,
                reward_multiplier: 0,
                tier_level: 0,
            }
        };

        if (table::contains(&params.stake_tiers, tier)) {
            *table::borrow_mut(&mut params.stake_tiers, tier) = config;
        } else {
            table::add(&mut params.stake_tiers, tier, config);
        };

        event::emit(StakeTierUpdated {
            tier_level: tier,
            old_config,
            new_config: config,
            updated_by,
            timestamp,
        });
    }

    /// Update certificate base value
    public(package) fun update_certificate_value(
        params: &mut GlobalParameters,
        cert_type: String,
        value: u64,
        updated_by: address,
        timestamp: u64,
    ) {
        assert!(value > 0, E_INVALID_CERTIFICATE_VALUE);
        
        let old_value = if (table::contains(&params.certificate_values, cert_type)) {
            *table::borrow(&params.certificate_values, cert_type)
        } else {
            params.certificates.certificate_base_value
        };

        if (table::contains(&params.certificate_values, cert_type)) {
            *table::borrow_mut(&mut params.certificate_values, cert_type) = value;
        } else {
            table::add(&mut params.certificate_values, cert_type, value);
        };

        event::emit(CertificateValueUpdated {
            certificate_type: cert_type,
            old_value,
            new_value: value,
            updated_by,
            timestamp,
        });
    }

    /// Lock a parameter (emergency use)
    public(package) fun lock_parameter(
        params: &mut GlobalParameters,
        key: String,
        lock_type: u8,
        locked_until: Option<u64>,
        locked_by: address,
        reason: String,
    ) {
        let lock = ParameterLock {
            lock_type,
            locked_until,
            locked_by,
            reason,
        };

        if (table::contains(&params.parameter_locks, key)) {
            *table::borrow_mut(&mut params.parameter_locks, key) = lock;
        } else {
            table::add(&mut params.parameter_locks, key, lock);
        };

        event::emit(ParameterLocked {
            key,
            lock_type,
            locked_until,
            locked_by,
            reason,
        });
    }

    /// Unlock a parameter
    public(package) fun unlock_parameter(
        params: &mut GlobalParameters,
        key: String,
        unlocked_by: address,
        timestamp: u64,
    ) {
        assert!(table::contains(&params.parameter_locks, key), E_PARAMETER_NOT_FOUND);
        let _lock = table::remove(&mut params.parameter_locks, key);

        event::emit(ParameterUnlocked {
            key,
            unlocked_by,
            timestamp,
        });
    }

    // =============== Test Functions ===============
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
    
    // =============== Helper Functions ===============
    
    /// Get parameter category by key
    public fun get_parameter_category(key: String): u8 {
        let key_str = *string::as_bytes(&key);
        
        if (key_str == b"quiz_creation_deposit" || 
            key_str == b"article_deposit_original" ||
            key_str == b"article_deposit_external" ||
            key_str == b"project_deposit" ||
            key_str == b"exam_creation_deposit" ||
            key_str == b"exam_fee" ||
            key_str == b"retry_fee" ||
            key_str == b"skill_search_fee" ||
            key_str == b"contact_purchase_fee") {
            CATEGORY_ECONOMIC
        } else if (key_str == b"article_approval_threshold" ||
                   key_str == b"project_approval_threshold" ||
                   key_str == b"quiz_approval_threshold" ||
                   key_str == b"exam_approval_threshold" ||
                   key_str == b"article_validator_count" ||
                   key_str == b"project_validator_count" ||
                   key_str == b"quiz_validator_count" ||
                   key_str == b"validation_time_limit") {
            CATEGORY_VALIDATION
        } else if (key_str == b"original_article_view_reward" ||
                   key_str == b"external_article_view_reward" ||
                   key_str == b"project_view_reward" ||
                   key_str == b"quiz_usage_reward" ||
                   key_str == b"validator_review_reward") {
            CATEGORY_REWARD
        } else if (key_str == b"epoch_duration" ||
                   key_str == b"max_proposals_per_user" ||
                   key_str == b"content_view_gas_cost") {
            CATEGORY_SYSTEM
        } else if (key_str == b"minimum_stake" ||
                   key_str == b"min_certificates_for_validator" ||
                   key_str == b"voting_period" ||
                   key_str == b"execution_delay" ||
                   key_str == b"quorum_threshold") {
            CATEGORY_GOVERNANCE
        } else {
            0 // Unknown category
        }
    }

    /// Validate parameter value range
    public fun validate_parameter_value(key: String, value: vector<u8>): bool {
        let key_str = *string::as_bytes(&key);
        
        // Validate threshold parameters (must be <= 100)
        if (key_str == b"article_approval_threshold" ||
            key_str == b"project_approval_threshold" ||
            key_str == b"quiz_approval_threshold" ||
            key_str == b"exam_approval_threshold" ||
            key_str == b"slash_lazy_validation" ||
            key_str == b"quorum_threshold") {
            let val = bcs::peel_u8(&mut bcs::new(value));
            val <= 100
        } else if (key_str == b"article_validator_count" ||
                   key_str == b"project_validator_count" ||
                   key_str == b"quiz_validator_count") {
            let val = bcs::peel_u8(&mut bcs::new(value));
            val > 0
        } else if (key_str == b"epoch_duration" ||
                   key_str == b"voting_period") {
            let val = bcs::peel_u64(&mut bcs::new(value));
            val > 0
        } else {
            true // No specific validation for other parameters
        }
    }

    /// Check if parameter is locked
    fun is_parameter_locked(params: &GlobalParameters, key: &String, current_time: u64): bool {
        if (!table::contains(&params.parameter_locks, *key)) {
            return false
        };

        let lock = table::borrow(&params.parameter_locks, *key);
        
        // Check if lock has expired
        if (option::is_some(&lock.locked_until)) {
            let unlock_time = *option::borrow(&lock.locked_until);
            if (current_time >= unlock_time) {
                return false
            }
        };

        true
    }

    /// Calculate impact level of parameter change
    fun calculate_impact_level(key: &String): u8 {
        let key_str = *string::as_bytes(key);
        
        // Critical impact (4) - affects security or fundamental economics
        if (key_str == b"minimum_stake" ||
            key_str == b"slash_collusion" ||
            key_str == b"slash_malicious_approval" ||
            key_str == b"max_slash_cap") {
            4
        // High impact (3) - affects major platform operations
        } else if (key_str == b"exam_creation_deposit" ||
                   key_str == b"proposal_deposit" ||
                   key_str == b"validator_selection_algorithm" ||
                   key_str == b"quorum_threshold") {
            3
        // Medium impact (2) - affects user experience or economics
        } else if (key_str == b"exam_fee" ||
                   key_str == b"retry_fee" ||
                   key_str == b"contact_purchase_fee" ||
                   key_str == b"quiz_creation_deposit") {
            2
        // Low impact (1) - minor adjustments
        } else {
            1
        }
    }

    /// Add parameter change to history
    fun add_parameter_history(params: &mut GlobalParameters, key: &String, change: ParameterChange) {
        if (!table::contains(&params.parameter_history, *key)) {
            table::add(&mut params.parameter_history, *key, vector::empty());
        };
        
        let history = table::borrow_mut(&mut params.parameter_history, *key);
        vector::push_back(history, change);
        
        // Keep only last 50 changes per parameter
        if (vector::length(history) > 50) {
            vector::remove(history, 0);
        };
    }
}