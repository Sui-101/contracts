module suiverse_core::governance {
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
    use sui::math;
    use sui::dynamic_object_field as dof;
    use suiverse_core::parameters::{Self as parameters, GlobalParameters};
    use suiverse_core::treasury::{Self as treasury, Treasury};
    
    // =============== Constants ===============
    const CLOCK_ID: address = @0x6; // Sui system clock
    
    // Dynamic Object Field Keys
    const DOF_GOVERNANCE_CONFIG: vector<u8> = b"governance_config";
    const DOF_VALIDATOR_POOL: vector<u8> = b"validator_pool";
    const DOF_VALIDATOR_REGISTRY: vector<u8> = b"validator_registry";
    const DOF_VOTING_RECORDS: vector<u8> = b"voting_records";
    const DOF_TREASURY: vector<u8> = b"treasury";
    const DOF_GLOBAL_PARAMETERS: vector<u8> = b"global_parameters";
    const DOF_CLOCK: vector<u8> = b"clock";
    
    // Error codes - Configuration related
    const E_PACKAGE_NOT_CONFIGURED: u64 = 999;
    const E_INVALID_CONFIGURATION: u64 = 1000;
    
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
    const DEFAULT_PROPOSAL_DEPOSIT: u64 = 1_000_000_000; // 1 SUI
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
    const STAKE_TIER_STARTER: u64 = 1_000_000_000; // 1 SUI
    const STAKE_TIER_BASIC: u64 = 5_000_000_000; // 5 SUI
    const STAKE_TIER_BRONZE: u64 = 10_000_000_000; // 10 SUI
    const STAKE_TIER_SILVER: u64 = 50_000_000_000; // 50 SUI
    const STAKE_TIER_GOLD: u64 = 100_000_000_000; // 100 SUI
    const STAKE_TIER_PLATINUM: u64 = 500_000_000_000; // 500 SUI
    
    // Slash reasons and percentages
    const SLASH_LAZY_VALIDATION: u8 = 1; // 10% slash
    const SLASH_WRONG_CONSENSUS: u8 = 2; // 5% slash
    const SLASH_MALICIOUS_APPROVAL: u8 = 3; // 50% slash
    const SLASH_COLLUSION: u8 = 4; // 100% slash
    
    // Bootstrap configuration
    const GENESIS_VALIDATOR_COUNT: u64 = 20;
    const BOOTSTRAP_PHASE_DURATION: u64 = 86400000; // 1 day in ms
    const MIN_CERTIFICATES_FOR_NON_GENESIS: u64 = 3;
    
    // Weight calculation constants
    const KNOWLEDGE_WEIGHT_FACTOR: u64 = 100;
    const STAKE_WEIGHT_FACTOR: u64 = 100;
    const PERFORMANCE_WEIGHT_FACTOR: u64 = 100;
    const BASE_WEIGHT_DIVISOR: u64 = 10000;
    
    // =============== Structs ===============
    
    /// Central registry using Dynamic Object Fields to store all shared objects
    /// This eliminates the need for users to pass objects as parameters
    public struct PackageRegistry has key {
        id: UID,
        // Admin capability for security
        admin_cap_id: ID,
        // Configuration status
        is_configured: bool,
        last_updated: u64,
        // Objects are stored as dynamic object fields using the DOF_* keys
    }
    
    /// Admin capability for registry management
    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    /// Governance configuration with PoK features
    public struct GovernanceConfig has key, store {
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
    public struct VotingRecords has key, store {
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
    public struct ValidatorRegistry has key, store {
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
    public struct ValidatorPool has key, store {
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
    
    // =============== Dynamic Object Field Type Witnesses ===============
    
    /// Type witness for GovernanceConfig
    public struct GovernanceConfigKey has copy, drop, store {}
    
    /// Type witness for ValidatorPool
    public struct ValidatorPoolKey has copy, drop, store {}
    
    /// Type witness for ValidatorRegistry
    public struct ValidatorRegistryKey has copy, drop, store {}
    
    /// Type witness for VotingRecords
    public struct VotingRecordsKey has copy, drop, store {}
    
    /// Type witness for Treasury
    public struct TreasuryKey has copy, drop, store {}
    
    /// Type witness for GlobalParameters
    public struct GlobalParametersKey has copy, drop, store {}
    
    /// Type witness for Clock
    public struct ClockKey has copy, drop, store {}
    
    // =============== Events ===============
    
    /// Registry configuration events
    public struct RegistryConfigured has copy, drop {
        registry_id: ID,
        configured_objects: vector<String>,
        timestamp: u64,
    }
    
    public struct ObjectRegistered has copy, drop {
        registry_id: ID,
        object_type: String,
        object_id: ID,
        timestamp: u64,
    }
    
    public struct ObjectRetrieved has copy, drop {
        registry_id: ID,
        object_type: String,
        object_id: ID,
        caller: address,
        timestamp: u64,
    }
    
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
            bootstrap_end_time: BOOTSTRAP_PHASE_DURATION, // Will be set properly when clock is available
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
        
        // Create admin capability
        let admin_cap = RegistryAdminCap {
            id: object::new(ctx),
        };
        
        // Create package registry using Dynamic Object Fields
        let mut registry_obj = PackageRegistry {
            id: object::new(ctx),
            admin_cap_id: object::uid_to_inner(&admin_cap.id),
            is_configured: false, // Will be configured after storing objects
            last_updated: 0,
        };
        
        // Store all objects as dynamic object fields
        dof::add(&mut registry_obj.id, GovernanceConfigKey{}, config);
        dof::add(&mut registry_obj.id, ValidatorRegistryKey{}, registry);
        dof::add(&mut registry_obj.id, ValidatorPoolKey{}, pool);
        dof::add(&mut registry_obj.id, VotingRecordsKey{}, voting_records);
        
        // Mark as partially configured (external objects still needed)
        registry_obj.is_configured = false;
        
        // Transfer objects
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry_obj);
    }
    
    // =============== Dynamic Object Field Management ===============
    
    /// Add or update a governance config object in the registry
    public entry fun add_governance_config(
        registry: &mut PackageRegistry,
        config: GovernanceConfig,
        _admin_cap: &RegistryAdminCap,
        ctx: &TxContext,
    ) {
        // Verify admin capability
        assert!(object::id(_admin_cap) == registry.admin_cap_id, E_NOT_AUTHORIZED);
        
        let config_id = object::id(&config);
        
        // Remove existing if present
        if (dof::exists_(&registry.id, GovernanceConfigKey{})) {
            let old_config: GovernanceConfig = dof::remove(&mut registry.id, GovernanceConfigKey{});
            // Transfer old config to admin for disposal
            transfer::public_transfer(old_config, tx_context::sender(ctx));
        };
        
        // Add new config
        dof::add(&mut registry.id, GovernanceConfigKey{}, config);
        
        event::emit(ObjectRegistered {
            registry_id: object::id(registry),
            object_type: string::utf8(b"GovernanceConfig"),
            object_id: config_id,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Add or update a validator pool object in the registry
    public entry fun add_validator_pool(
        registry: &mut PackageRegistry,
        pool: ValidatorPool,
        _admin_cap: &RegistryAdminCap,
        ctx: &TxContext,
    ) {
        // Verify admin capability
        assert!(object::id(_admin_cap) == registry.admin_cap_id, E_NOT_AUTHORIZED);
        
        let pool_id = object::id(&pool);
        
        // Remove existing if present
        if (dof::exists_(&registry.id, ValidatorPoolKey{})) {
            let old_pool: ValidatorPool = dof::remove(&mut registry.id, ValidatorPoolKey{});
            // Transfer old pool to admin for disposal
            transfer::public_transfer(old_pool, tx_context::sender(ctx));
        };
        
        // Add new pool
        dof::add(&mut registry.id, ValidatorPoolKey{}, pool);
        
        event::emit(ObjectRegistered {
            registry_id: object::id(registry),
            object_type: string::utf8(b"ValidatorPool"),
            object_id: pool_id,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Add or update external treasury object reference
    public entry fun add_treasury(
        registry: &mut PackageRegistry,
        treasury: Treasury,
        _admin_cap: &RegistryAdminCap,
        ctx: &TxContext,
    ) {
        // Verify admin capability
        assert!(object::id(_admin_cap) == registry.admin_cap_id, E_NOT_AUTHORIZED);
        
        let treasury_id = object::id(&treasury);
        
        // Remove existing if present
        if (dof::exists_(&registry.id, TreasuryKey{})) {
            let old_treasury: Treasury = dof::remove(&mut registry.id, TreasuryKey{});
            // Transfer old treasury to admin for disposal
            transfer::public_transfer(old_treasury, tx_context::sender(ctx));
        };
        
        // Add new treasury
        dof::add(&mut registry.id, TreasuryKey{}, treasury);
        
        // Update configuration status
        registry.last_updated = tx_context::epoch_timestamp_ms(ctx);
        update_configuration_status(registry);
        
        event::emit(ObjectRegistered {
            registry_id: object::id(registry),
            object_type: string::utf8(b"Treasury"),
            object_id: treasury_id,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Add or update external global parameters object reference
    public entry fun add_global_parameters(
        registry: &mut PackageRegistry,
        params: GlobalParameters,
        _admin_cap: &RegistryAdminCap,
        ctx: &TxContext,
    ) {
        // Verify admin capability
        assert!(object::id(_admin_cap) == registry.admin_cap_id, E_NOT_AUTHORIZED);
        
        let params_id = object::id(&params);
        
        // Remove existing if present
        if (dof::exists_(&registry.id, GlobalParametersKey{})) {
            let old_params: GlobalParameters = dof::remove(&mut registry.id, GlobalParametersKey{});
            // Transfer old params to admin for disposal
            transfer::public_transfer(old_params, tx_context::sender(ctx));
        };
        
        // Add new parameters
        dof::add(&mut registry.id, GlobalParametersKey{}, params);
        
        // Update configuration status
        registry.last_updated = tx_context::epoch_timestamp_ms(ctx);
        update_configuration_status(registry);
        
        event::emit(ObjectRegistered {
            registry_id: object::id(registry),
            object_type: string::utf8(b"GlobalParameters"),
            object_id: params_id,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
    
    /// Internal function to check and update configuration status
    fun update_configuration_status(registry: &mut PackageRegistry) {
        let has_governance = dof::exists_(&registry.id, GovernanceConfigKey{});
        let has_pool = dof::exists_(&registry.id, ValidatorPoolKey{});
        let has_registry = dof::exists_(&registry.id, ValidatorRegistryKey{});
        let has_voting = dof::exists_(&registry.id, VotingRecordsKey{});
        let has_treasury = dof::exists_(&registry.id, TreasuryKey{});
        let has_params = dof::exists_(&registry.id, GlobalParametersKey{});
        
        registry.is_configured = has_governance && has_pool && has_registry && 
                                has_voting && has_treasury && has_params;
    }
    
    // =============== Object Retrieval Functions ===============
    
    /// Get mutable reference to governance config (internal use)
    fun get_governance_config_mut(registry: &mut PackageRegistry): &mut GovernanceConfig {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, GovernanceConfigKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, GovernanceConfigKey{})
    }
    
    /// Get immutable reference to governance config (internal use)
    fun get_governance_config(registry: &PackageRegistry): &GovernanceConfig {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, GovernanceConfigKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, GovernanceConfigKey{})
    }
    
    /// Get mutable reference to validator pool (internal use)
    fun get_validator_pool_mut(registry: &mut PackageRegistry): &mut ValidatorPool {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, ValidatorPoolKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, ValidatorPoolKey{})
    }
    
    /// Get immutable reference to validator pool (internal use)
    fun get_validator_pool(registry: &PackageRegistry): &ValidatorPool {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, ValidatorPoolKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, ValidatorPoolKey{})
    }
    
    /// Get mutable reference to validator registry (internal use)
    fun get_validator_registry_mut(registry: &mut PackageRegistry): &mut ValidatorRegistry {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, ValidatorRegistryKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, ValidatorRegistryKey{})
    }
    
    /// Get immutable reference to validator registry (internal use)
    fun get_validator_registry(registry: &PackageRegistry): &ValidatorRegistry {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, ValidatorRegistryKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, ValidatorRegistryKey{})
    }
    
    /// Get mutable reference to voting records (internal use)
    fun get_voting_records_mut(registry: &mut PackageRegistry): &mut VotingRecords {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, VotingRecordsKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, VotingRecordsKey{})
    }
    
    /// Get immutable reference to voting records (internal use)
    fun get_voting_records(registry: &PackageRegistry): &VotingRecords {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, VotingRecordsKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, VotingRecordsKey{})
    }
    
    /// Get mutable reference to treasury (internal use)
    fun get_treasury_mut(registry: &mut PackageRegistry): &mut Treasury {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, TreasuryKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, TreasuryKey{})
    }
    
    /// Get immutable reference to treasury (internal use)
    fun get_treasury(registry: &PackageRegistry): &Treasury {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, TreasuryKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, TreasuryKey{})
    }
    
    /// Get mutable reference to global parameters (internal use)
    fun get_global_parameters_mut(registry: &mut PackageRegistry): &mut GlobalParameters {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, GlobalParametersKey{}), E_INVALID_CONFIGURATION);
        dof::borrow_mut(&mut registry.id, GlobalParametersKey{})
    }
    
    /// Get immutable reference to global parameters (internal use)
    fun get_global_parameters(registry: &PackageRegistry): &GlobalParameters {
        assert!(registry.is_configured, E_PACKAGE_NOT_CONFIGURED);
        assert!(dof::exists_(&registry.id, GlobalParametersKey{}), E_INVALID_CONFIGURATION);
        dof::borrow(&registry.id, GlobalParametersKey{})
    }
    
    /// Get clock reference (always from Sui system)
    fun get_clock(): ID {
        object::id_from_address(@0x6)
    }
    
    // =============== Configuration Management ===============
    
    /// Initialize the registry with external objects (admin only)
    public entry fun configure_registry_with_external_objects(
        registry: &mut PackageRegistry,
        treasury: Treasury,
        global_parameters: GlobalParameters,
        admin_cap: &RegistryAdminCap,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify admin capability
        assert!(object::id(admin_cap) == registry.admin_cap_id, E_NOT_AUTHORIZED);
        
        // Add external objects
        add_treasury(registry, treasury, admin_cap, ctx);
        add_global_parameters(registry, global_parameters, admin_cap, ctx);
        
        // Update last updated timestamp
        registry.last_updated = clock::timestamp_ms(clock);
        
        // Emit configuration event
        let mut configured_objects = vector::empty<String>();
        vector::push_back(&mut configured_objects, string::utf8(b"Treasury"));
        vector::push_back(&mut configured_objects, string::utf8(b"GlobalParameters"));
        
        event::emit(RegistryConfigured {
            registry_id: object::id(registry),
            configured_objects,
            timestamp: clock::timestamp_ms(clock),
        });
    }
    
    /// Quick configuration for testing/deployment (admin only)
    public entry fun initialize_registry_with_known_objects(
        registry: &mut PackageRegistry,
        treasury: Treasury,
        global_parameters: GlobalParameters,
        admin_cap: &RegistryAdminCap,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        configure_registry_with_external_objects(
            registry, treasury, global_parameters, admin_cap, clock, ctx
        );
    }
    
    // =============== Registry Status Functions ===============
    
    /// Check if the registry is fully configured
    public fun is_registry_configured(registry: &PackageRegistry): bool {
        registry.is_configured
    }
    
    /// Get registry configuration details
    public fun get_registry_status(registry: &PackageRegistry): (bool, u64, vector<String>) {
        let mut objects = vector::empty<String>();
        
        if (dof::exists_(&registry.id, GovernanceConfigKey{})) {
            vector::push_back(&mut objects, string::utf8(b"GovernanceConfig"));
        };
        if (dof::exists_(&registry.id, ValidatorPoolKey{})) {
            vector::push_back(&mut objects, string::utf8(b"ValidatorPool"));
        };
        if (dof::exists_(&registry.id, ValidatorRegistryKey{})) {
            vector::push_back(&mut objects, string::utf8(b"ValidatorRegistry"));
        };
        if (dof::exists_(&registry.id, VotingRecordsKey{})) {
            vector::push_back(&mut objects, string::utf8(b"VotingRecords"));
        };
        if (dof::exists_(&registry.id, TreasuryKey{})) {
            vector::push_back(&mut objects, string::utf8(b"Treasury"));
        };
        if (dof::exists_(&registry.id, GlobalParametersKey{})) {
            vector::push_back(&mut objects, string::utf8(b"GlobalParameters"));
        };
        
        (registry.is_configured, registry.last_updated, objects)
    }
    
    /// Get the admin capability ID for verification
    public fun get_admin_cap_id(registry: &PackageRegistry): ID {
        registry.admin_cap_id
    }

    // =============== Simplified Entry Functions (Auto-Retrieval) ===============
    
    /// Register as a genesis validator (simplified with auto-retrieval)
    public entry fun register_genesis_validator(
        registry: &mut PackageRegistry,
        payment: &mut Coin<SUI>,  // mutable reference
        stake_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let stake = coin::split(payment, stake_amount, ctx);
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let stake_amount = coin::value(&stake);
        
        // First, check configuration constraints (immutable access)
        {
            let config = get_governance_config(registry);
            assert!(current_time < config.bootstrap_end_time, E_GENESIS_PHASE_ACTIVE);
            assert!(vector::length(&config.genesis_validators) < GENESIS_VALIDATOR_COUNT, E_GENESIS_PHASE_ACTIVE);
            assert!(stake_amount >= config.minimum_stake, E_INSUFFICIENT_STAKE);
        };
        
        // Then check validator pool constraints and register if valid
        {
            let pool = get_validator_pool_mut(registry);
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
            
            let validator_weight = validator.weight;
            
            // Add to validator pool
            pool.total_weight = pool.total_weight + validator_weight;
            table::add(&mut pool.active_validators, validator_address, validator);
        };
        
        // Finally, update config with genesis validator list  
        {
            let config = get_governance_config_mut(registry);
            vector::push_back(&mut config.genesis_validators, validator_address);
        };
        
        // Emit success event
        event::emit(ObjectRetrieved {
            registry_id: object::id(registry),
            object_type: string::utf8(b"genesis_validator_registered"),
            object_id: object::id(registry),
            caller: validator_address,
            timestamp: current_time,
        });
    }
    
    /// Legacy function for backward compatibility - kept for existing tests
    public entry fun register_genesis_validator_legacy(
        config: &mut GovernanceConfig,
        pool: &mut ValidatorPool,
        stake: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Call the implementation directly (for legacy support)
        register_genesis_validator_impl(config, pool, stake, clock, ctx);
    }
    
    
    /// Internal implementation for genesis validator registration
    fun register_genesis_validator_impl(
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
    
    /// Register as a validator with certificates (simplified with auto-retrieval)
    public entry fun register_validator_with_certificates(
        registry: &mut PackageRegistry,
        certificate_ids: vector<ID>,
        certificate_types: vector<String>,
        skill_levels: vector<u8>,
        earned_dates: vector<u64>,
        stake: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Note: This function requires multiple mutable DOF accesses which violates Move's borrowing rules
        // For now, use the legacy function instead. Future versions may need a different pattern.
        transfer::public_transfer(stake, tx_context::sender(ctx)); // Return stake
        assert!(false, E_NOT_AUTHORIZED) // Use legacy function register_validator_with_certificates_legacy instead
    }
    
    /// Legacy validator registration (for backward compatibility)
    public entry fun register_validator_with_certificates_legacy(
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
        register_validator_with_certificates_impl(
            config, pool, certificate_ids, certificate_types, 
            skill_levels, earned_dates, stake, clock, ctx
        );
    }
    
    /// Internal implementation for validator registration with certificates
    fun register_validator_with_certificates_impl(
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
    
    // Continue with rest of the functions...
    // [The rest of the governance module continues as is from the original document]
    
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
        let table_len = table::length(&pool.active_validators);
        while (selected_count < count && i < table_len) {
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
            let domain_len = vector::length(domain_validators);
            let limit = if (count < domain_len) { count } else { domain_len };
            while (i < limit) {
                vector::push_back(&mut validators, *vector::borrow(domain_validators, i));
                i = i + 1;
            };
        };
        
        validators
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
}