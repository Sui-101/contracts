/// Upgrade Manager for SuiVerse Economics Package
/// 
/// Comprehensive upgrade management system for the economics package with:
/// - Multi-signature upgrade authorization
/// - Cross-package coordination with core and content packages  
/// - Migration framework with rollback capabilities
/// - Emergency controls and circuit breakers
/// - Version tracking and compatibility checks
/// - Integration with governance system for upgrade proposals
module suiverse_economics::upgrade_manager {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};
    // Cross-package integration (imports available for future use)
    // use suiverse_core::governance;
    // use suiverse_core::parameters;
    // use suiverse_content::validation;

    // =============== Error Constants ===============
    
    // Authorization errors (10000-10099)
    const E_NOT_AUTHORIZED: u64 = 10001;
    const E_INSUFFICIENT_SIGNATURES: u64 = 10002;
    const E_INVALID_SIGNER: u64 = 10003;
    const E_SIGNATURE_EXPIRED: u64 = 10004;
    const E_DUPLICATE_SIGNATURE: u64 = 10005;
    
    // Upgrade errors (10100-10199)
    const E_UPGRADE_IN_PROGRESS: u64 = 10101;
    const E_INVALID_VERSION: u64 = 10102;
    const E_VERSION_DOWNGRADE_NOT_ALLOWED: u64 = 10103;
    const E_UPGRADE_COOLDOWN_ACTIVE: u64 = 10104;
    const E_DEPENDENCY_VERSION_MISMATCH: u64 = 10105;
    const E_UPGRADE_NOT_READY: u64 = 10106;
    const E_MAX_UPGRADES_EXCEEDED: u64 = 10107;
    
    // Migration errors (10200-10299)
    const E_MIGRATION_IN_PROGRESS: u64 = 10201;
    const E_MIGRATION_FAILED: u64 = 10202;
    const E_ROLLBACK_NOT_AVAILABLE: u64 = 10203;
    const E_MIGRATION_TIMEOUT: u64 = 10204;
    const E_INVALID_MIGRATION_STATE: u64 = 10205;
    const E_MIGRATION_DATA_CORRUPTED: u64 = 10206;
    
    // Emergency errors (10300-10399)
    const E_EMERGENCY_PAUSE_ACTIVE: u64 = 10301;
    const E_NOT_EMERGENCY_ADMIN: u64 = 10302;
    const E_EMERGENCY_UPGRADE_CONDITIONS_NOT_MET: u64 = 10303;
    const E_CIRCUIT_BREAKER_TRIGGERED: u64 = 10304;
    
    // Configuration errors (10400-10499)
    const E_INVALID_THRESHOLD: u64 = 10401;
    const E_INVALID_TIMELOCK_DURATION: u64 = 10402;
    const E_INVALID_MODULE_CONFIG: u64 = 10403;
    const E_PROPOSAL_NOT_FOUND: u64 = 10404;

    // =============== Constants ===============
    
    // Version tracking
    const CURRENT_PACKAGE_VERSION: u64 = 1;
    const MIN_COMPATIBLE_CORE_VERSION: u64 = 1;
    const MIN_COMPATIBLE_CONTENT_VERSION: u64 = 1;
    
    // Timing constraints
    const UPGRADE_COOLDOWN_PERIOD: u64 = 604800000; // 7 days in milliseconds
    const MIGRATION_TIMEOUT: u64 = 2592000000; // 30 days in milliseconds
    const EMERGENCY_UPGRADE_DELAY: u64 = 86400000; // 1 day in milliseconds
    const SIGNATURE_EXPIRY: u64 = 3600000; // 1 hour in milliseconds
    
    // Limits
    const MAX_SIGNATURES_REQUIRED: u64 = 10;
    const MIN_SIGNATURES_REQUIRED: u64 = 2;
    const MAX_MODULES_PER_MIGRATION: u64 = 50;
    const MAX_UPGRADES_PER_MONTH: u64 = 4;
    
    // Migration states
    const MIGRATION_STATE_IDLE: u8 = 0;
    const MIGRATION_STATE_PREPARING: u8 = 1;
    const MIGRATION_STATE_IN_PROGRESS: u8 = 2;
    const MIGRATION_STATE_VALIDATING: u8 = 3;
    const MIGRATION_STATE_COMPLETED: u8 = 4;
    const MIGRATION_STATE_FAILED: u8 = 5;
    const MIGRATION_STATE_ROLLED_BACK: u8 = 6;

    // =============== Core Structs ===============

    /// Central upgrade management system for economics package
    public struct UpgradeManager has key {
        id: UID,
        // Upgrade capabilities
        upgrade_cap: UpgradeCap,
        emergency_cap: Option<UpgradeCap>, // For emergency upgrades
        
        // Version tracking
        current_version: u64,
        pending_version: Option<u64>,
        version_history: vector<VersionRecord>,
        
        // Multi-sig configuration
        required_signatures: u64,
        authorized_signers: vector<address>,
        signature_threshold: u64, // Percentage (0-100)
        
        // Upgrade constraints
        upgrade_cooldown_until: u64,
        upgrades_this_month: u64,
        last_upgrade_timestamp: u64,
        
        // Migration state
        migration_state: MigrationState,
        
        // Emergency controls
        emergency_pause: bool,
        emergency_admin: address,
        circuit_breaker_triggered: bool,
        
        // Cross-package coordination
        dependency_versions: VecMap<String, u64>,
        compatibility_matrix: Table<String, CompatibilityInfo>,
        
        // Governance integration
        governance_proposals: Table<ID, UpgradeProposal>,
        proposal_execution_delay: u64,
    }

    /// Proposal for governance-driven upgrades
    public struct UpgradeProposal has store {
        id: ID,
        title: String,
        description: String,
        proposed_version: u64,
        digest: vector<u8>,
        proposer: address,
        proposal_timestamp: u64,
        execution_timestamp: u64,
        signatures_collected: vector<UpgradeSignature>,
        governance_approved: bool,
        status: u8, // 0=pending, 1=approved, 2=executed, 3=rejected
    }

    /// Migration state tracking
    public struct MigrationState has store {
        current_state: u8,
        migration_id: Option<ID>,
        affected_modules: vector<String>,
        migration_timestamp: u64,
        timeout_timestamp: u64,
        rollback_data: Option<RollbackData>,
        progress_checkpoints: vector<MigrationCheckpoint>,
        validation_results: vector<ValidationResult>,
    }

    /// Version information record
    public struct VersionRecord has store, copy, drop {
        version: u64,
        digest: vector<u8>,
        timestamp: u64,
        upgrader: address,
        migration_summary: String,
        affected_modules: vector<String>,
    }

    /// Upgrade signature from authorized signer
    public struct UpgradeSignature has store, copy, drop {
        signer: address,
        signature_timestamp: u64,
        version_hash: vector<u8>,
        expiry_timestamp: u64,
    }

    /// Compatibility information between packages
    public struct CompatibilityInfo has store {
        package_name: String,
        min_version: u64,
        max_version: u64,
        compatibility_notes: String,
        last_verified: u64,
    }

    /// Rollback data for failed migrations
    public struct RollbackData has store, drop {
        backup_timestamp: u64,
        affected_objects: vector<ID>,
        state_snapshots: vector<vector<u8>>, // Serialized state snapshots 
        rollback_instructions: vector<String>,
    }

    /// Migration progress checkpoint
    public struct MigrationCheckpoint has store, copy, drop {
        checkpoint_id: u64,
        module_name: String,
        timestamp: u64,
        status: String,
        data_migrated: u64,
        validation_passed: bool,
    }

    /// Migration validation result
    public struct ValidationResult has store, copy, drop {
        module_name: String,
        validation_type: String,
        passed: bool,
        error_message: String,
        timestamp: u64,
    }

    /// Admin capability for upgrade operations
    public struct UpgradeAdminCap has key, store {
        id: UID,
        authority_level: u8, // 1=standard, 2=emergency, 3=super_admin
    }

    /// Emergency admin capability
    public struct EmergencyAdminCap has key, store {
        id: UID,
    }

    /// Multi-signature authorization ticket
    public struct MultiSigTicket has key, store {
        id: UID,
        proposal_id: ID,
        required_signatures: u64,
        collected_signatures: vector<UpgradeSignature>,
        expiry_timestamp: u64,
        status: u8, // 0=collecting, 1=ready, 2=expired
    }

    // =============== Events ===============

    public struct UpgradeManagerInitialized has copy, drop {
        manager_id: ID,
        initial_version: u64,
        required_signatures: u64,
        emergency_admin: address,
        timestamp: u64,
    }

    public struct UpgradeProposed has copy, drop {
        proposal_id: ID,
        title: String,
        proposed_version: u64,
        proposer: address,
        timestamp: u64,
        requires_governance: bool,
    }

    public struct SignatureAdded has copy, drop {
        proposal_id: ID,
        signer: address,
        timestamp: u64,
        signatures_collected: u64,
        signatures_required: u64,
    }

    public struct UpgradeAuthorized has copy, drop {
        proposal_id: ID,
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        authorized_by: address,
        timestamp: u64,
    }

    public struct MigrationStarted has copy, drop {
        migration_id: ID,
        from_version: u64,
        to_version: u64,
        affected_modules: vector<String>,
        timestamp: u64,
        timeout_timestamp: u64,
    }

    public struct MigrationCheckpointReached has copy, drop {
        migration_id: ID,
        checkpoint_id: u64,
        module_name: String,
        status: String,
        timestamp: u64,
    }

    public struct MigrationCompleted has copy, drop {
        migration_id: ID,
        from_version: u64,
        to_version: u64,
        duration_ms: u64,
        modules_migrated: u64,
        timestamp: u64,
    }

    public struct MigrationFailed has copy, drop {
        migration_id: ID,
        error_message: String,
        rollback_initiated: bool,
        timestamp: u64,
    }

    public struct UpgradeCompleted has copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
        migration_duration: u64,
    }

    public struct EmergencyUpgradeExecuted has copy, drop {
        from_version: u64,
        to_version: u64,
        emergency_reason: String,
        executor: address,
        timestamp: u64,
    }

    public struct CircuitBreakerTriggered has copy, drop {
        trigger_reason: String,
        triggered_by: address,
        timestamp: u64,
        auto_recovery_enabled: bool,
    }

    public struct DependencyVersionUpdated has copy, drop {
        package_name: String,
        old_version: u64,
        new_version: u64,
        compatibility_verified: bool,
        timestamp: u64,
    }

    // =============== Initialization ===============

    /// Initialize upgrade management system
    fun init(ctx: &mut TxContext) {
        let admin_cap = UpgradeAdminCap {
            id: object::new(ctx),
            authority_level: 3, // Super admin
        };
        
        let emergency_cap = EmergencyAdminCap {
            id: object::new(ctx),
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::transfer(emergency_cap, tx_context::sender(ctx));
    }

    /// Setup upgrade manager with initial configuration
    public fun setup_upgrade_manager(
        upgrade_cap: UpgradeCap,
        admin_cap: &UpgradeAdminCap,
        initial_signers: vector<address>,
        signature_threshold: u64,
        ctx: &mut TxContext
    ) {
        assert!(admin_cap.authority_level >= 3, E_NOT_AUTHORIZED);
        assert!(signature_threshold >= MIN_SIGNATURES_REQUIRED, E_INVALID_THRESHOLD);
        assert!(signature_threshold <= MAX_SIGNATURES_REQUIRED, E_INVALID_THRESHOLD);
        assert!(vector::length(&initial_signers) >= signature_threshold, E_INSUFFICIENT_SIGNATURES);

        let manager_id = object::new(ctx);
        let sender = tx_context::sender(ctx);

        // Initialize dependency version tracking
        let mut dependency_versions = vec_map::empty<String, u64>();
        vec_map::insert(&mut dependency_versions, string::utf8(b"suiverse_core"), MIN_COMPATIBLE_CORE_VERSION);
        vec_map::insert(&mut dependency_versions, string::utf8(b"suiverse_content"), MIN_COMPATIBLE_CONTENT_VERSION);

        let manager = UpgradeManager {
            id: manager_id,
            upgrade_cap,
            emergency_cap: option::none(),
            current_version: CURRENT_PACKAGE_VERSION,
            pending_version: option::none(),
            version_history: vector::empty(),
            required_signatures: signature_threshold,
            authorized_signers: initial_signers,
            signature_threshold,
            upgrade_cooldown_until: 0,
            upgrades_this_month: 0,
            last_upgrade_timestamp: 0,
            migration_state: MigrationState {
                current_state: MIGRATION_STATE_IDLE,
                migration_id: option::none(),
                affected_modules: vector::empty(),
                migration_timestamp: 0,
                timeout_timestamp: 0,
                rollback_data: option::none(),
                progress_checkpoints: vector::empty(),
                validation_results: vector::empty(),
            },
            emergency_pause: false,
            emergency_admin: sender,
            circuit_breaker_triggered: false,
            dependency_versions,
            compatibility_matrix: table::new(ctx),
            governance_proposals: table::new(ctx),
            proposal_execution_delay: EMERGENCY_UPGRADE_DELAY,
        };

        event::emit(UpgradeManagerInitialized {
            manager_id: object::uid_to_inner(&manager.id),
            initial_version: CURRENT_PACKAGE_VERSION,
            required_signatures: signature_threshold,
            emergency_admin: sender,
            timestamp: 0, // Clock not available in init
        });

        transfer::share_object(manager);
    }

    // =============== Upgrade Proposal Functions ===============

    /// Create upgrade proposal
    public fun create_upgrade_proposal(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        title: String,
        description: String,
        proposed_version: u64,
        digest: vector<u8>,
        requires_governance: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ): ID {
        assert!(!manager.emergency_pause, E_EMERGENCY_PAUSE_ACTIVE);
        assert!(!manager.circuit_breaker_triggered, E_CIRCUIT_BREAKER_TRIGGERED);
        assert!(admin_cap.authority_level >= 1, E_NOT_AUTHORIZED);
        assert!(proposed_version > manager.current_version, E_VERSION_DOWNGRADE_NOT_ALLOWED);
        
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= manager.upgrade_cooldown_until, E_UPGRADE_COOLDOWN_ACTIVE);

        let proposal_id = object::new(ctx);
        let proposal_id_inner = object::uid_to_inner(&proposal_id);
        object::delete(proposal_id);

        let proposal = UpgradeProposal {
            id: proposal_id_inner,
            title,
            description,
            proposed_version,
            digest,
            proposer: tx_context::sender(ctx),
            proposal_timestamp: current_time,
            execution_timestamp: current_time + manager.proposal_execution_delay,
            signatures_collected: vector::empty(),
            governance_approved: !requires_governance,
            status: 0, // pending
        };

        table::add(&mut manager.governance_proposals, proposal_id_inner, proposal);

        event::emit(UpgradeProposed {
            proposal_id: proposal_id_inner,
            title,
            proposed_version,
            proposer: tx_context::sender(ctx),
            timestamp: current_time,
            requires_governance,
        });

        proposal_id_inner
    }

    /// Add signature to upgrade proposal
    public fun add_upgrade_signature(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        proposal_id: ID,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(!manager.emergency_pause, E_EMERGENCY_PAUSE_ACTIVE);
        assert!(table::contains(&manager.governance_proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        
        let signer = tx_context::sender(ctx);
        assert!(vector::contains(&manager.authorized_signers, &signer), E_INVALID_SIGNER);

        let proposal = table::borrow_mut(&mut manager.governance_proposals, proposal_id);
        // Check proposal status (0 = pending)

        let current_time = clock::timestamp_ms(clock);
        
        // Check if signer already signed
        let signatures = &proposal.signatures_collected;
        let mut i = 0;
        let len = vector::length(signatures);
        while (i < len) {
            let sig = vector::borrow(signatures, i);
            assert!(sig.signer != signer, E_DUPLICATE_SIGNATURE);
            i = i + 1;
        };

        let signature = UpgradeSignature {
            signer,
            signature_timestamp: current_time,
            version_hash: proposal.digest,
            expiry_timestamp: current_time + SIGNATURE_EXPIRY,
        };

        vector::push_back(&mut proposal.signatures_collected, signature);

        let signatures_count = vector::length(&proposal.signatures_collected);
        
        event::emit(SignatureAdded {
            proposal_id,
            signer,
            timestamp: current_time,
            signatures_collected: signatures_count,
            signatures_required: manager.required_signatures,
        });

        // Auto-approve if enough signatures collected
        if (signatures_count >= manager.required_signatures && proposal.governance_approved) {
            proposal.status = 1; // approved
        };
    }

    /// Execute approved upgrade proposal
    public fun execute_upgrade_proposal(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        proposal_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ): UpgradeTicket {
        assert!(!manager.emergency_pause, E_EMERGENCY_PAUSE_ACTIVE);
        assert!(table::contains(&manager.governance_proposals, proposal_id), E_PROPOSAL_NOT_FOUND);
        assert!(admin_cap.authority_level >= 2, E_NOT_AUTHORIZED);

        let current_time = clock::timestamp_ms(clock);
        
        // Extract proposal data first to avoid borrow checker issues
        let (proposed_version, digest, signatures) = {
            let proposal = table::borrow(&manager.governance_proposals, proposal_id);
            assert!(proposal.status == 1, E_UPGRADE_NOT_READY);
            (proposal.proposed_version, proposal.digest, proposal.signatures_collected)
        };

        // Verify signatures are still valid
        let mut valid_signatures = 0;
        let mut i = 0;
        let len = vector::length(&signatures);
        while (i < len) {
            let sig = vector::borrow(&signatures, i);
            if (current_time <= sig.expiry_timestamp) {
                valid_signatures = valid_signatures + 1;
            };
            i = i + 1;
        };

        assert!(valid_signatures >= manager.required_signatures, E_INSUFFICIENT_SIGNATURES);

        // Start migration process
        let _migration_id = start_migration(manager, proposed_version, clock, ctx);

        let ticket = package::authorize_upgrade(
            &mut manager.upgrade_cap,
            package::compatible_policy(),
            digest
        );

        manager.pending_version = option::some(proposed_version);
        
        // Update proposal status
        let proposal = table::borrow_mut(&mut manager.governance_proposals, proposal_id);
        proposal.status = 2; // executed

        event::emit(UpgradeAuthorized {
            proposal_id,
            from_version: manager.current_version,
            to_version: proposed_version,
            digest,
            authorized_by: tx_context::sender(ctx),
            timestamp: current_time,
        });

        ticket
    }

    // =============== Migration Functions ===============

    /// Start migration process
    fun start_migration(
        manager: &mut UpgradeManager,
        target_version: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): ID {
        let current_time = clock::timestamp_ms(clock);
        let migration_id = object::new(ctx);
        let migration_id_inner = object::uid_to_inner(&migration_id);
        object::delete(migration_id);

        manager.migration_state.current_state = MIGRATION_STATE_PREPARING;
        manager.migration_state.migration_id = option::some(migration_id_inner);
        manager.migration_state.migration_timestamp = current_time;
        manager.migration_state.timeout_timestamp = current_time + MIGRATION_TIMEOUT;
        manager.migration_state.progress_checkpoints = vector::empty();
        manager.migration_state.validation_results = vector::empty();

        // Initialize affected modules list (would be populated based on upgrade content)
        let mut affected_modules = vector::empty<String>();
        vector::push_back(&mut affected_modules, string::utf8(b"economics_integration"));
        vector::push_back(&mut affected_modules, string::utf8(b"certificate_market"));
        vector::push_back(&mut affected_modules, string::utf8(b"learning_incentives"));
        // Add other modules as needed

        manager.migration_state.affected_modules = affected_modules;

        event::emit(MigrationStarted {
            migration_id: migration_id_inner,
            from_version: manager.current_version,
            to_version: target_version,
            affected_modules,
            timestamp: current_time,
            timeout_timestamp: manager.migration_state.timeout_timestamp,
        });

        migration_id_inner
    }

    /// Add migration checkpoint
    public fun add_migration_checkpoint(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        module_name: String,
        status: String,
        data_migrated: u64,
        validation_passed: bool,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(admin_cap.authority_level >= 2, E_NOT_AUTHORIZED);
        assert!(manager.migration_state.current_state == MIGRATION_STATE_IN_PROGRESS, E_MIGRATION_IN_PROGRESS);

        let current_time = clock::timestamp_ms(clock);
        let checkpoint_id = vector::length(&manager.migration_state.progress_checkpoints);

        let checkpoint = MigrationCheckpoint {
            checkpoint_id,
            module_name,
            timestamp: current_time,
            status,
            data_migrated,
            validation_passed,
        };

        vector::push_back(&mut manager.migration_state.progress_checkpoints, checkpoint);

        if (option::is_some(&manager.migration_state.migration_id)) {
            event::emit(MigrationCheckpointReached {
                migration_id: *option::borrow(&manager.migration_state.migration_id),
                checkpoint_id,
                module_name,
                status,
                timestamp: current_time,
            });
        };
    }

    /// Complete upgrade with migration
    public fun commit_upgrade_with_migration(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        receipt: UpgradeReceipt,
        migration_summary: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(admin_cap.authority_level >= 2, E_NOT_AUTHORIZED);
        assert!(option::is_some(&manager.pending_version), E_UPGRADE_NOT_READY);
        assert!(manager.migration_state.current_state == MIGRATION_STATE_VALIDATING, E_INVALID_MIGRATION_STATE);

        let current_time = clock::timestamp_ms(clock);
        let new_version = option::extract(&mut manager.pending_version);
        package::commit_upgrade(&mut manager.upgrade_cap, receipt);

        // Create version record
        let version_record = VersionRecord {
            version: new_version,
            digest: vector::empty(),
            timestamp: current_time,
            upgrader: tx_context::sender(ctx),
            migration_summary,
            affected_modules: manager.migration_state.affected_modules,
        };

        vector::push_back(&mut manager.version_history, version_record);
        manager.current_version = new_version;
        manager.last_upgrade_timestamp = current_time;
        manager.upgrade_cooldown_until = current_time + UPGRADE_COOLDOWN_PERIOD;
        manager.upgrades_this_month = manager.upgrades_this_month + 1;

        // Reset migration state
        manager.migration_state.current_state = MIGRATION_STATE_COMPLETED;
        let migration_duration = current_time - manager.migration_state.migration_timestamp;
        let modules_count = vector::length(&manager.migration_state.affected_modules);

        if (option::is_some(&manager.migration_state.migration_id)) {
            event::emit(MigrationCompleted {
                migration_id: *option::borrow(&manager.migration_state.migration_id),
                from_version: version_record.version - 1,
                to_version: new_version,
                duration_ms: migration_duration,
                modules_migrated: modules_count,
                timestamp: current_time,
            });
        };

        event::emit(UpgradeCompleted {
            from_version: version_record.version - 1,
            to_version: new_version,
            digest: vector::empty(),
            timestamp: current_time,
            migration_duration,
        });

        // Reset migration state to idle after completion
        reset_migration_state(manager);
    }

    // =============== Emergency Functions ===============

    /// Emergency upgrade execution
    public fun execute_emergency_upgrade(
        manager: &mut UpgradeManager,
        emergency_cap: &EmergencyAdminCap,
        digest: vector<u8>,
        emergency_reason: String,
        clock: &Clock,
        ctx: &TxContext
    ): UpgradeTicket {
        let sender = tx_context::sender(ctx);
        assert!(sender == manager.emergency_admin, E_NOT_EMERGENCY_ADMIN);

        let current_time = clock::timestamp_ms(clock);
        let new_version = manager.current_version + 1;

        let ticket = package::authorize_upgrade(
            &mut manager.upgrade_cap,
            package::compatible_policy(),
            digest
        );

        manager.pending_version = option::some(new_version);

        event::emit(EmergencyUpgradeExecuted {
            from_version: manager.current_version,
            to_version: new_version,
            emergency_reason,
            executor: sender,
            timestamp: current_time,
        });

        ticket
    }

    /// Trigger emergency pause
    public fun trigger_emergency_pause(
        manager: &mut UpgradeManager,
        emergency_cap: &EmergencyAdminCap,
        pause_reason: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == manager.emergency_admin, E_NOT_EMERGENCY_ADMIN);

        manager.emergency_pause = true;

        event::emit(CircuitBreakerTriggered {
            trigger_reason: pause_reason,
            triggered_by: sender,
            timestamp: clock::timestamp_ms(clock),
            auto_recovery_enabled: false,
        });
    }

    /// Disable emergency pause
    public fun disable_emergency_pause(
        manager: &mut UpgradeManager,
        emergency_cap: &EmergencyAdminCap,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == manager.emergency_admin, E_NOT_EMERGENCY_ADMIN);
        
        manager.emergency_pause = false;
    }

    // =============== Administrative Functions ===============

    /// Add authorized signer
    public fun add_authorized_signer(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        new_signer: address,
        ctx: &TxContext
    ) {
        assert!(admin_cap.authority_level >= 3, E_NOT_AUTHORIZED);
        assert!(!vector::contains(&manager.authorized_signers, &new_signer), E_DUPLICATE_SIGNATURE);
        
        vector::push_back(&mut manager.authorized_signers, new_signer);
    }

    /// Remove authorized signer
    public fun remove_authorized_signer(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        signer_to_remove: address,
        ctx: &TxContext
    ) {
        assert!(admin_cap.authority_level >= 3, E_NOT_AUTHORIZED);
        
        let (found, index) = vector::index_of(&manager.authorized_signers, &signer_to_remove);
        if (found) {
            vector::remove(&mut manager.authorized_signers, index);
            
            // Ensure we still have enough signers
            let remaining_signers = vector::length(&manager.authorized_signers);
            if (remaining_signers < manager.required_signatures) {
                manager.required_signatures = remaining_signers;
            };
        };
    }

    /// Update dependency version
    public fun update_dependency_version(
        manager: &mut UpgradeManager,
        admin_cap: &UpgradeAdminCap,
        package_name: String,
        new_version: u64,
        compatibility_verified: bool,
        clock: &Clock,
        ctx: &TxContext
    ) {
        assert!(admin_cap.authority_level >= 2, E_NOT_AUTHORIZED);
        
        let old_version = if (vec_map::contains(&manager.dependency_versions, &package_name)) {
            *vec_map::get(&manager.dependency_versions, &package_name)
        } else {
            0
        };

        if (vec_map::contains(&manager.dependency_versions, &package_name)) {
            *vec_map::get_mut(&mut manager.dependency_versions, &package_name) = new_version;
        } else {
            vec_map::insert(&mut manager.dependency_versions, package_name, new_version);
        };

        event::emit(DependencyVersionUpdated {
            package_name,
            old_version,
            new_version,
            compatibility_verified,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Helper Functions ===============

    /// Reset migration state to idle
    fun reset_migration_state(manager: &mut UpgradeManager) {
        manager.migration_state.current_state = MIGRATION_STATE_IDLE;
        manager.migration_state.migration_id = option::none();
        manager.migration_state.affected_modules = vector::empty();
        manager.migration_state.migration_timestamp = 0;
        manager.migration_state.timeout_timestamp = 0;
        manager.migration_state.rollback_data = option::none();
        manager.migration_state.progress_checkpoints = vector::empty();
        manager.migration_state.validation_results = vector::empty();
    }

    // =============== View Functions ===============

    /// Get current version
    public fun current_version(manager: &UpgradeManager): u64 {
        manager.current_version
    }

    /// Get pending version
    public fun pending_version(manager: &UpgradeManager): Option<u64> {
        manager.pending_version
    }

    /// Check if address is authorized signer
    public fun is_authorized_signer(manager: &UpgradeManager, addr: address): bool {
        vector::contains(&manager.authorized_signers, &addr)
    }

    /// Get migration state
    public fun migration_state(manager: &UpgradeManager): u8 {
        manager.migration_state.current_state
    }

    /// Check if emergency pause is active
    public fun is_emergency_paused(manager: &UpgradeManager): bool {
        manager.emergency_pause
    }

    /// Get required signatures count
    public fun required_signatures(manager: &UpgradeManager): u64 {
        manager.required_signatures
    }

    /// Get authorized signers
    public fun authorized_signers(manager: &UpgradeManager): &vector<address> {
        &manager.authorized_signers
    }

    /// Get upgrade cooldown status
    public fun upgrade_cooldown_until(manager: &UpgradeManager): u64 {
        manager.upgrade_cooldown_until
    }

    /// Get version history
    public fun version_history(manager: &UpgradeManager): &vector<VersionRecord> {
        &manager.version_history
    }

    /// Get dependency version
    public fun dependency_version(manager: &UpgradeManager, package_name: String): Option<u64> {
        if (vec_map::contains(&manager.dependency_versions, &package_name)) {
            option::some(*vec_map::get(&manager.dependency_versions, &package_name))
        } else {
            option::none()
        }
    }

    /// Check if upgrade proposal exists
    public fun proposal_exists(manager: &UpgradeManager, proposal_id: ID): bool {
        table::contains(&manager.governance_proposals, proposal_id)
    }

    /// Get proposal status
    public fun proposal_status(manager: &UpgradeManager, proposal_id: ID): u8 {
        if (table::contains(&manager.governance_proposals, proposal_id)) {
            table::borrow(&manager.governance_proposals, proposal_id).status
        } else {
            255 // Not found
        }
    }
}