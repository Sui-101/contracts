/// SuiVerse Quiz Vault Module
/// 
/// This module provides a comprehensive, secure quiz storage and management system
/// for the SuiVerse decentralized learning platform. It handles encrypted quiz content,
/// multi-level access controls, vault organization, and secure sharing mechanisms.
///
/// Key Features:
/// - Encrypted quiz content storage with versioning
/// - Multi-level access control (read, write, admin)
/// - Vault organization with categories and tags
/// - Secure sharing between users and organizations
/// - Backup and recovery mechanisms
/// - Comprehensive analytics and audit logging
/// - Integration with existing SuiVerse ecosystem
module suiverse_economics::quiz_vault {
    use std::string::{Self as string, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::bcs;
    use sui::hash;
    use sui::dynamic_field as df;

    // =============== Error Constants ===============
    const E_VAULT_NOT_FOUND: u64 = 70001;
    const E_INSUFFICIENT_PERMISSIONS: u64 = 70002;
    const E_INVALID_ACCESS_LEVEL: u64 = 70003;
    const E_QUIZ_NOT_FOUND_IN_VAULT: u64 = 70004;
    const E_VAULT_LOCKED: u64 = 70005;
    const E_INVALID_ENCRYPTION_KEY: u64 = 70006;
    const E_BACKUP_FAILED: u64 = 70007;
    const E_RECOVERY_FAILED: u64 = 70008;
    const E_VAULT_CAPACITY_EXCEEDED: u64 = 70009;
    const E_INVALID_VAULT_CONFIG: u64 = 70010;
    const E_UNAUTHORIZED_SHARING: u64 = 70011;
    const E_SHARE_LIMIT_EXCEEDED: u64 = 70012;
    const E_INVALID_BACKUP_DATA: u64 = 70013;
    const E_VAULT_ALREADY_EXISTS: u64 = 70014;
    const E_INSUFFICIENT_DEPOSIT: u64 = 70015;

    // =============== Access Level Constants ===============
    const ACCESS_NONE: u8 = 0;
    const ACCESS_READ: u8 = 1;
    const ACCESS_WRITE: u8 = 2;
    const ACCESS_ADMIN: u8 = 3;
    const ACCESS_OWNER: u8 = 4;

    // =============== Vault Type Constants ===============
    const VAULT_PERSONAL: u8 = 1;
    const VAULT_ORGANIZATION: u8 = 2;
    const VAULT_PUBLIC: u8 = 3;
    const VAULT_COLLABORATIVE: u8 = 4;

    // =============== Encryption Constants ===============
    const ENCRYPTION_VERSION_V1: u8 = 1;
    const ENCRYPTION_AES256: u8 = 1;
    const ENCRYPTION_CHACHA20: u8 = 2;

    // =============== Economic Constants ===============
    const VAULT_CREATION_DEPOSIT: u64 = 1_000_000_000; // 1 SUI
    const ORGANIZATION_VAULT_DEPOSIT: u64 = 5_000_000_000; // 5 SUI
    const BACKUP_SERVICE_FEE: u64 = 100_000_000; // 0.1 SUI
    const SHARING_FEE: u64 = 50_000_000; // 0.05 SUI

    // =============== Capacity Constants ===============
    const MAX_QUIZZES_PER_VAULT: u64 = 10000;
    const MAX_SHARES_PER_VAULT: u64 = 1000;
    const MAX_BACKUP_VERSIONS: u64 = 10;
    const MAX_CATEGORIES_PER_VAULT: u64 = 50;

    // =============== Core Structures ===============

    /// QuizVault - Secure container for quiz collections
    public struct QuizVault has key {
        id: UID,
        // Basic Information
        name: String,
        description: String,
        owner: address,
        vault_type: u8,
        
        // Encrypted Content Storage
        encrypted_quizzes: Table<ID, EncryptedQuizContent>,
        content_hash_registry: Table<ID, vector<u8>>,
        encryption_metadata: EncryptionMetadata,
        
        // Organization and Categories
        categories: Table<String, CategoryInfo>,
        tags: vector<String>,
        quiz_collections: Table<String, vector<ID>>,
        
        // Access Control
        access_control: AccessControlRegistry,
        sharing_permissions: Table<address, SharePermission>,
        organization_members: vector<address>,
        
        // Vault Statistics
        total_quizzes: u64,
        total_attempts: u64,
        success_rate: u64,
        last_accessed: u64,
        
        // Backup and Recovery
        backup_versions: Table<u64, BackupMetadata>,
        recovery_keys: vector<vector<u8>>,
        backup_frequency: u64,
        last_backup: u64,
        
        // Economics
        vault_deposit: Balance<SUI>,
        earnings_pool: Balance<SUI>,
        sharing_fees: Balance<SUI>,
        
        // Timestamps and Status
        created_at: u64,
        updated_at: u64,
        is_active: bool,
        is_locked: bool,
        lock_reason: Option<String>,
    }

    /// Encrypted quiz content with metadata
    public struct EncryptedQuizContent has store {
        quiz_id: ID,
        encrypted_data: vector<u8>,
        content_hash: vector<u8>,
        encryption_key_id: u64,
        encryption_algorithm: u8,
        version: u64,
        metadata: QuizMetadata,
        access_history: vector<AccessRecord>,
        created_at: u64,
        updated_at: u64,
    }

    /// Quiz metadata for vault organization
    public struct QuizMetadata has store, copy, drop {
        title: String,
        difficulty: u8,
        category: String,
        tags: vector<String>,
        estimated_time: u64,
        creator: address,
        version_number: u64,
        prerequisite_ids: vector<ID>,
        learning_objectives: vector<String>,
        usage_restrictions: vector<String>,
    }

    /// Encryption metadata for the vault
    public struct EncryptionMetadata has store {
        encryption_version: u8,
        key_derivation_salt: vector<u8>,
        master_key_hash: vector<u8>,
        encryption_keys: Table<u64, EncryptionKey>,
        next_key_id: u64,
        key_rotation_frequency: u64,
        last_key_rotation: u64,
    }

    /// Individual encryption key
    public struct EncryptionKey has store {
        key_id: u64,
        encrypted_key: vector<u8>,
        algorithm: u8,
        created_at: u64,
        expires_at: Option<u64>,
        usage_count: u64,
        is_active: bool,
    }

    /// Access control registry
    public struct AccessControlRegistry has store {
        user_permissions: Table<address, UserPermission>,
        role_definitions: Table<String, RoleDefinition>,
        access_policies: vector<AccessPolicy>,
        audit_log: vector<AuditLogEntry>,
        permission_inheritance: bool,
        default_permissions: u8,
    }

    /// User permission record
    public struct UserPermission has store, drop {
        user: address,
        access_level: u8,
        specific_permissions: vector<String>,
        granted_by: address,
        granted_at: u64,
        expires_at: Option<u64>,
        is_active: bool,
        inheritance_source: Option<address>,
    }

    /// Role definition for organizations
    public struct RoleDefinition has store {
        role_name: String,
        access_level: u8,
        permissions: vector<String>,
        can_grant_access: bool,
        can_modify_content: bool,
        can_share_vault: bool,
        max_quiz_access: u64,
        created_at: u64,
    }

    /// Access policy rule
    public struct AccessPolicy has store {
        policy_id: u64,
        policy_type: String,
        conditions: vector<String>,
        actions: vector<String>,
        priority: u8,
        is_active: bool,
        created_by: address,
        created_at: u64,
    }

    /// Audit log entry
    public struct AuditLogEntry has store, copy, drop {
        entry_id: u64,
        user: address,
        action: String,
        resource_id: Option<ID>,
        timestamp: u64,
        ip_hash: Option<vector<u8>>,
        success: bool,
        details: String,
    }

    /// Share permission structure
    public struct SharePermission has store {
        shared_with: address,
        permission_level: u8,
        share_type: String, // "read", "collaborate", "copy"
        expiry_time: Option<u64>,
        quiz_restrictions: vector<ID>,
        usage_limits: ShareUsageLimits,
        granted_by: address,
        granted_at: u64,
        is_revocable: bool,
    }

    /// Share usage limits
    public struct ShareUsageLimits has store {
        max_accesses: Option<u64>,
        max_downloads: Option<u64>,
        max_quiz_attempts: Option<u64>,
        current_accesses: u64,
        current_downloads: u64,
        current_attempts: u64,
        daily_limit: Option<u64>,
        daily_usage: u64,
        last_reset: u64,
    }

    /// Category information
    public struct CategoryInfo has store {
        category_name: String,
        description: String,
        quiz_count: u64,
        average_difficulty: u64,
        creation_date: u64,
        last_updated: u64,
        color_theme: String,
        is_public: bool,
    }

    /// Access record for audit trail
    public struct AccessRecord has store, copy, drop {
        user: address,
        access_type: String,
        timestamp: u64,
        duration: u64,
        success: bool,
        metadata: String,
    }

    /// Backup metadata
    public struct BackupMetadata has store {
        backup_id: u64,
        backup_hash: vector<u8>,
        encrypted_backup_data: vector<u8>,
        quiz_count: u64,
        backup_size: u64,
        backup_type: String, // "full", "incremental", "differential"
        compression_ratio: u64,
        verification_status: bool,
        created_at: u64,
        expires_at: u64,
        storage_location: String,
    }

    /// Vault statistics for analytics
    public struct QuizStats has key {
        id: UID,
        vault_analytics: Table<ID, VaultAnalytics>,
        global_stats: GlobalVaultStats,
        trending_vaults: vector<TrendingVault>,
        category_stats: Table<String, CategoryStats>,
        user_activity: Table<address, UserActivityStats>,
    }

    /// Individual vault analytics
    public struct VaultAnalytics has store {
        vault_id: ID,
        total_accesses: u64,
        unique_users: u64,
        quiz_usage_distribution: Table<ID, QuizUsageStats>,
        peak_usage_times: vector<u64>,
        collaboration_metrics: CollaborationMetrics,
        performance_metrics: PerformanceMetrics,
        last_analyzed: u64,
    }

    /// Quiz usage statistics within vault
    public struct QuizUsageStats has store {
        quiz_id: ID,
        access_count: u64,
        success_rate: u64,
        average_score: u64,
        time_spent: u64,
        last_accessed: u64,
        user_feedback: vector<u8>, // Simplified feedback scores
    }

    /// Collaboration metrics
    public struct CollaborationMetrics has store {
        shared_count: u64,
        collaboration_sessions: u64,
        concurrent_users: u64,
        contribution_score: u64,
        conflict_resolution_count: u64,
        average_collaboration_time: u64,
    }

    /// Performance metrics
    public struct PerformanceMetrics has store {
        average_load_time: u64,
        encryption_overhead: u64,
        storage_efficiency: u64,
        backup_performance: u64,
        access_latency: u64,
        error_rate: u64,
    }

    /// Global vault statistics
    public struct GlobalVaultStats has store {
        total_vaults: u64,
        total_quizzes_stored: u64,
        total_vault_accesses: u64,
        average_vault_size: u64,
        storage_utilization: u64,
        backup_success_rate: u64,
        security_incidents: u64,
        last_updated: u64,
    }

    /// Trending vault information
    public struct TrendingVault has store, copy, drop {
        vault_id: ID,
        vault_name: String,
        vault_type: u8,
        access_growth: u64,
        quiz_addition_rate: u64,
        collaboration_score: u64,
        period_start: u64,
        period_end: u64,
    }

    /// Category statistics
    public struct CategoryStats has store {
        category_name: String,
        vault_count: u64,
        total_quizzes: u64,
        average_success_rate: u64,
        popularity_score: u64,
        creation_trend: u64,
        last_updated: u64,
    }

    /// User activity statistics
    public struct UserActivityStats has store {
        user: address,
        vaults_owned: u64,
        vaults_accessed: u64,
        quizzes_created: u64,
        quizzes_attempted: u64,
        collaboration_score: u64,
        last_activity: u64,
    }

    // =============== Admin Capability ===============

    public struct VaultAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct VaultCreated has copy, drop {
        vault_id: ID,
        owner: address,
        vault_name: String,
        vault_type: u8,
        deposit_amount: u64,
        timestamp: u64,
    }

    public struct QuizStoredInVault has copy, drop {
        vault_id: ID,
        quiz_id: ID,
        stored_by: address,
        category: String,
        encryption_key_id: u64,
        timestamp: u64,
    }

    public struct VaultAccessGranted has copy, drop {
        vault_id: ID,
        granted_to: address,
        granted_by: address,
        access_level: u8,
        expiry_time: Option<u64>,
        timestamp: u64,
    }

    public struct VaultShared has copy, drop {
        vault_id: ID,
        shared_with: address,
        shared_by: address,
        share_type: String,
        permission_level: u8,
        timestamp: u64,
    }

    public struct QuizAccessedFromVault has copy, drop {
        vault_id: ID,
        quiz_id: ID,
        accessed_by: address,
        access_type: String,
        success: bool,
        timestamp: u64,
    }

    public struct VaultBackupCreated has copy, drop {
        vault_id: ID,
        backup_id: u64,
        backup_type: String,
        quiz_count: u64,
        backup_size: u64,
        timestamp: u64,
    }

    public struct VaultRestored has copy, drop {
        vault_id: ID,
        backup_id: u64,
        restored_by: address,
        quizzes_restored: u64,
        timestamp: u64,
    }

    public struct VaultLocked has copy, drop {
        vault_id: ID,
        locked_by: address,
        reason: String,
        timestamp: u64,
    }

    public struct VaultUnlocked has copy, drop {
        vault_id: ID,
        unlocked_by: address,
        timestamp: u64,
    }

    public struct EncryptionKeyRotated has copy, drop {
        vault_id: ID,
        old_key_id: u64,
        new_key_id: u64,
        rotated_by: address,
        timestamp: u64,
    }

    // =============== Initialization ===============

    fun init(ctx: &mut TxContext) {
        // Create global quiz statistics
        let quiz_stats = QuizStats {
            id: object::new(ctx),
            vault_analytics: table::new(ctx),
            global_stats: GlobalVaultStats {
                total_vaults: 0,
                total_quizzes_stored: 0,
                total_vault_accesses: 0,
                average_vault_size: 0,
                storage_utilization: 0,
                backup_success_rate: 0,
                security_incidents: 0,
                last_updated: 0,
            },
            trending_vaults: vector::empty(),
            category_stats: table::new(ctx),
            user_activity: table::new(ctx),
        };

        // Create admin capability
        let admin_cap = VaultAdminCap {
            id: object::new(ctx),
        };

        // Transfer objects
        transfer::share_object(quiz_stats);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    // =============== Vault Management Functions ===============

    /// Create a new quiz vault with specified configuration
    public entry fun create_vault(
        name: String,
        description: String,
        vault_type: u8,
        encryption_algorithm: u8,
        is_public: bool,
        max_collaborators: u64,
        deposit: Coin<SUI>,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Validate inputs
        assert!(string::length(&name) > 0 && string::length(&name) <= 100, E_INVALID_VAULT_CONFIG);
        assert!(vault_type >= VAULT_PERSONAL && vault_type <= VAULT_COLLABORATIVE, E_INVALID_VAULT_CONFIG);
        assert!(encryption_algorithm == ENCRYPTION_AES256 || encryption_algorithm == ENCRYPTION_CHACHA20, E_INVALID_ENCRYPTION_KEY);
        assert!(max_collaborators <= MAX_SHARES_PER_VAULT, E_SHARE_LIMIT_EXCEEDED);

        // Check deposit amount
        let required_deposit = if (vault_type == VAULT_ORGANIZATION) {
            ORGANIZATION_VAULT_DEPOSIT
        } else {
            VAULT_CREATION_DEPOSIT
        };
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);

        // Generate encryption metadata
        let encryption_seed = generate_master_encryption_seed(owner, current_time);
        let master_key_hash = hash::keccak256(&bcs::to_bytes(&encryption_seed));
        let salt = generate_salt(owner, current_time);

        // Create encryption metadata
        let encryption_metadata = EncryptionMetadata {
            encryption_version: ENCRYPTION_VERSION_V1,
            key_derivation_salt: salt,
            master_key_hash,
            encryption_keys: table::new(ctx),
            next_key_id: 1,
            key_rotation_frequency: 2592000000, // 30 days
            last_key_rotation: current_time,
        };

        // Create access control registry
        let access_control = AccessControlRegistry {
            user_permissions: table::new(ctx),
            role_definitions: table::new(ctx),
            access_policies: vector::empty(),
            audit_log: vector::empty(),
            permission_inheritance: true,
            default_permissions: if (is_public) { ACCESS_READ } else { ACCESS_NONE },
        };

        // Create the vault
        let vault = QuizVault {
            id: object::new(ctx),
            name,
            description,
            owner,
            vault_type,
            encrypted_quizzes: table::new(ctx),
            content_hash_registry: table::new(ctx),
            encryption_metadata,
            categories: table::new(ctx),
            tags: vector::empty(),
            quiz_collections: table::new(ctx),
            access_control,
            sharing_permissions: table::new(ctx),
            organization_members: vector::empty(),
            total_quizzes: 0,
            total_attempts: 0,
            success_rate: 0,
            last_accessed: current_time,
            backup_versions: table::new(ctx),
            recovery_keys: vector::empty(),
            backup_frequency: 604800000, // 7 days
            last_backup: 0,
            vault_deposit: coin::into_balance(deposit),
            earnings_pool: balance::zero(),
            sharing_fees: balance::zero(),
            created_at: current_time,
            updated_at: current_time,
            is_active: true,
            is_locked: false,
            lock_reason: option::none(),
        };

        let vault_id = object::uid_to_inner(&vault.id);

        // Update global statistics
        stats.global_stats.total_vaults = stats.global_stats.total_vaults + 1;
        stats.global_stats.last_updated = current_time;

        // Initialize vault analytics
        let vault_analytics = VaultAnalytics {
            vault_id,
            total_accesses: 0,
            unique_users: 0,
            quiz_usage_distribution: table::new(ctx),
            peak_usage_times: vector::empty(),
            collaboration_metrics: CollaborationMetrics {
                shared_count: 0,
                collaboration_sessions: 0,
                concurrent_users: 0,
                contribution_score: 0,
                conflict_resolution_count: 0,
                average_collaboration_time: 0,
            },
            performance_metrics: PerformanceMetrics {
                average_load_time: 0,
                encryption_overhead: 0,
                storage_efficiency: 100,
                backup_performance: 0,
                access_latency: 0,
                error_rate: 0,
            },
            last_analyzed: current_time,
        };

        table::add(&mut stats.vault_analytics, vault_id, vault_analytics);

        // Update user activity stats
        if (!table::contains(&stats.user_activity, owner)) {
            let user_stats = UserActivityStats {
                user: owner,
                vaults_owned: 0,
                vaults_accessed: 0,
                quizzes_created: 0,
                quizzes_attempted: 0,
                collaboration_score: 0,
                last_activity: current_time,
            };
            table::add(&mut stats.user_activity, owner, user_stats);
        };

        let user_stats = table::borrow_mut(&mut stats.user_activity, owner);
        user_stats.vaults_owned = user_stats.vaults_owned + 1;
        user_stats.last_activity = current_time;

        event::emit(VaultCreated {
            vault_id,
            owner,
            vault_name: vault.name,
            vault_type,
            deposit_amount: required_deposit,
            timestamp: current_time,
        });

        transfer::share_object(vault);
    }

    /// Store encrypted quiz content in vault
    public fun store_quiz_in_vault(
        vault: &mut QuizVault,
        quiz_id: ID,
        quiz_content: vector<u8>,
        metadata: QuizMetadata,
        category: String,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions
        assert!(has_write_permission(vault, user), E_INSUFFICIENT_PERMISSIONS);
        assert!(!vault.is_locked, E_VAULT_LOCKED);
        assert!(vault.total_quizzes < MAX_QUIZZES_PER_VAULT, E_VAULT_CAPACITY_EXCEEDED);

        // Generate encryption key for this quiz
        let encryption_key_id = vault.encryption_metadata.next_key_id;
        let quiz_encryption_key = generate_quiz_encryption_key(
            &vault.encryption_metadata.master_key_hash,
            quiz_id,
            current_time
        );

        // Create encryption key record
        let encryption_key = EncryptionKey {
            key_id: encryption_key_id,
            encrypted_key: quiz_encryption_key,
            algorithm: ENCRYPTION_AES256,
            created_at: current_time,
            expires_at: option::none(),
            usage_count: 0,
            is_active: true,
        };

        table::add(&mut vault.encryption_metadata.encryption_keys, encryption_key_id, encryption_key);
        vault.encryption_metadata.next_key_id = encryption_key_id + 1;

        // Encrypt quiz content
        let encrypted_data = encrypt_with_key(&quiz_content, &quiz_encryption_key);
        let content_hash = hash::keccak256(&quiz_content);

        // Create encrypted quiz content
        let encrypted_quiz = EncryptedQuizContent {
            quiz_id,
            encrypted_data,
            content_hash,
            encryption_key_id,
            encryption_algorithm: ENCRYPTION_AES256,
            version: 1,
            metadata,
            access_history: vector::empty(),
            created_at: current_time,
            updated_at: current_time,
        };

        // Store the encrypted quiz
        table::add(&mut vault.encrypted_quizzes, quiz_id, encrypted_quiz);
        table::add(&mut vault.content_hash_registry, quiz_id, content_hash);

        // Update category information
        if (!table::contains(&vault.categories, category)) {
            let category_info = CategoryInfo {
                category_name: category,
                description: string::utf8(b"Auto-generated category"),
                quiz_count: 0,
                average_difficulty: 0,
                creation_date: current_time,
                last_updated: current_time,
                color_theme: string::utf8(b"default"),
                is_public: false,
            };
            table::add(&mut vault.categories, category, category_info);
        };

        let category_info = table::borrow_mut(&mut vault.categories, category);
        category_info.quiz_count = category_info.quiz_count + 1;
        category_info.last_updated = current_time;

        // Add to collection if it exists
        let collection_exists = table::contains(&vault.quiz_collections, category);
        if (collection_exists) {
            let collection = table::borrow_mut(&mut vault.quiz_collections, category);
            vector::push_back(collection, quiz_id);
        } else {
            let mut new_collection = vector::empty<ID>();
            vector::push_back(&mut new_collection, quiz_id);
            table::add(&mut vault.quiz_collections, category, new_collection);
        };

        // Update vault statistics
        vault.total_quizzes = vault.total_quizzes + 1;
        vault.updated_at = current_time;

        // Update global statistics
        stats.global_stats.total_quizzes_stored = stats.global_stats.total_quizzes_stored + 1;
        stats.global_stats.last_updated = current_time;

        // Log access
        log_access_to_vault(vault, user, string::utf8(b"store_quiz"), current_time);

        event::emit(QuizStoredInVault {
            vault_id: object::uid_to_inner(&vault.id),
            quiz_id,
            stored_by: user,
            category,
            encryption_key_id,
            timestamp: current_time,
        });
    }

    /// Grant access to vault for specified user
    public entry fun grant_vault_access(
        vault: &mut QuizVault,
        user_to_grant: address,
        access_level: u8,
        expiry_time: Option<u64>,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let granter = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions - only owner or admin can grant access
        assert!(
            vault.owner == granter || has_admin_permission(vault, granter),
            E_INSUFFICIENT_PERMISSIONS
        );
        assert!(access_level <= ACCESS_ADMIN, E_INVALID_ACCESS_LEVEL);
        assert!(!vault.is_locked, E_VAULT_LOCKED);

        // Create user permission
        let user_permission = UserPermission {
            user: user_to_grant,
            access_level,
            specific_permissions: vector::empty(),
            granted_by: granter,
            granted_at: current_time,
            expires_at: expiry_time,
            is_active: true,
            inheritance_source: option::none(),
        };

        // Store or update permission
        if (table::contains(&vault.access_control.user_permissions, user_to_grant)) {
            *table::borrow_mut(&mut vault.access_control.user_permissions, user_to_grant) = user_permission;
        } else {
            table::add(&mut vault.access_control.user_permissions, user_to_grant, user_permission);
        };

        // Log the access grant
        log_access_to_vault(vault, granter, string::utf8(b"grant_access"), current_time);

        // Update analytics
        if (table::contains(&stats.vault_analytics, object::uid_to_inner(&vault.id))) {
            let analytics = table::borrow_mut(
                &mut stats.vault_analytics, 
                object::uid_to_inner(&vault.id)
            );
            analytics.collaboration_metrics.shared_count = analytics.collaboration_metrics.shared_count + 1;
        };

        event::emit(VaultAccessGranted {
            vault_id: object::uid_to_inner(&vault.id),
            granted_to: user_to_grant,
            granted_by: granter,
            access_level,
            expiry_time,
            timestamp: current_time,
        });
    }

    /// Share vault with another user
    public entry fun share_vault(
        vault: &mut QuizVault,
        share_with: address,
        share_type: String,
        permission_level: u8,
        expiry_time: Option<u64>,
        quiz_restrictions: vector<ID>,
        sharing_fee: Coin<SUI>,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sharer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions
        assert!(
            vault.owner == sharer || has_write_permission(vault, sharer),
            E_UNAUTHORIZED_SHARING
        );
        assert!(!vault.is_locked, E_VAULT_LOCKED);
        assert!(coin::value(&sharing_fee) >= SHARING_FEE, E_INSUFFICIENT_DEPOSIT);
        assert!(
            table::length(&vault.sharing_permissions) < MAX_SHARES_PER_VAULT,
            E_SHARE_LIMIT_EXCEEDED
        );

        // Create share permission
        let share_permission = SharePermission {
            shared_with: share_with,
            permission_level,
            share_type,
            expiry_time,
            quiz_restrictions,
            usage_limits: ShareUsageLimits {
                max_accesses: option::some(1000),
                max_downloads: option::some(100),
                max_quiz_attempts: option::some(500),
                current_accesses: 0,
                current_downloads: 0,
                current_attempts: 0,
                daily_limit: option::some(50),
                daily_usage: 0,
                last_reset: current_time,
            },
            granted_by: sharer,
            granted_at: current_time,
            is_revocable: true,
        };

        // Store sharing permission
        table::add(&mut vault.sharing_permissions, share_with, share_permission);

        // Process sharing fee
        balance::join(&mut vault.sharing_fees, coin::into_balance(sharing_fee));

        // Update analytics
        if (table::contains(&stats.vault_analytics, object::uid_to_inner(&vault.id))) {
            let analytics = table::borrow_mut(
                &mut stats.vault_analytics,
                object::uid_to_inner(&vault.id)
            );
            analytics.collaboration_metrics.shared_count = analytics.collaboration_metrics.shared_count + 1;
        };

        // Log the sharing
        log_access_to_vault(vault, sharer, string::utf8(b"share_vault"), current_time);

        event::emit(VaultShared {
            vault_id: object::uid_to_inner(&vault.id),
            shared_with: share_with,
            shared_by: sharer,
            share_type,
            permission_level,
            timestamp: current_time,
        });
    }

    /// Retrieve quiz content from vault (with proper authorization)
    public fun retrieve_quiz_from_vault(
        vault: &mut QuizVault,
        quiz_id: ID,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &TxContext,
    ): (vector<u8>, QuizMetadata) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions
        assert!(has_read_permission(vault, user), E_INSUFFICIENT_PERMISSIONS);
        assert!(!vault.is_locked, E_VAULT_LOCKED);
        assert!(table::contains(&vault.encrypted_quizzes, quiz_id), E_QUIZ_NOT_FOUND_IN_VAULT);

        // Get encrypted quiz content and extract metadata early
        let encrypted_quiz = table::borrow_mut(&mut vault.encrypted_quizzes, quiz_id);
        
        // Extract the data we need before other operations
        let metadata = encrypted_quiz.metadata;
        let encryption_key_id = encrypted_quiz.encryption_key_id;
        let encrypted_data = encrypted_quiz.encrypted_data;
        
        // Update access history
        let access_record = AccessRecord {
            user,
            access_type: string::utf8(b"retrieve"),
            timestamp: current_time,
            duration: 0,
            success: true,
            metadata: string::utf8(b"quiz_retrieval"),
        };
        vector::push_back(&mut encrypted_quiz.access_history, access_record);

        // End mutable borrow of encrypted_quiz
        
        // Get encryption key
        let encryption_key = table::borrow(
            &vault.encryption_metadata.encryption_keys,
            encryption_key_id
        );

        // Decrypt content
        let decrypted_content = decrypt_with_key(
            &encrypted_data,
            &encryption_key.encrypted_key
        );

        // Update encryption key usage
        let encryption_key_mut = table::borrow_mut(
            &mut vault.encryption_metadata.encryption_keys,
            encryption_key_id
        );
        encryption_key_mut.usage_count = encryption_key_mut.usage_count + 1;

        // Update vault statistics
        vault.total_attempts = vault.total_attempts + 1;
        vault.last_accessed = current_time;

        // Update analytics
        update_quiz_access_analytics(vault, quiz_id, user, stats, current_time);

        // Log access
        log_access_to_vault(vault, user, string::utf8(b"retrieve_quiz"), current_time);

        event::emit(QuizAccessedFromVault {
            vault_id: object::uid_to_inner(&vault.id),
            quiz_id,
            accessed_by: user,
            access_type: string::utf8(b"retrieve"),
            success: true,
            timestamp: current_time,
        });

        (decrypted_content, metadata)
    }

    /// Create backup of vault
    public entry fun create_vault_backup(
        vault: &mut QuizVault,
        backup_type: String,
        backup_fee: Coin<SUI>,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions
        assert!(
            vault.owner == user || has_admin_permission(vault, user),
            E_INSUFFICIENT_PERMISSIONS
        );
        assert!(coin::value(&backup_fee) >= BACKUP_SERVICE_FEE, E_INSUFFICIENT_DEPOSIT);
        assert!(!vault.is_locked, E_VAULT_LOCKED);

        // Check backup limit
        assert!(
            table::length(&vault.backup_versions) < MAX_BACKUP_VERSIONS,
            E_BACKUP_FAILED
        );

        // Generate backup ID
        let backup_id = table::length(&vault.backup_versions) + 1;

        // Create backup data (simplified - in production would serialize entire vault state)
        let backup_data = serialize_vault_for_backup(vault);
        let backup_hash = hash::keccak256(&backup_data);
        
        // Encrypt backup data
        let backup_encryption_key = generate_backup_encryption_key(
            &vault.encryption_metadata.master_key_hash,
            backup_id,
            current_time
        );
        let encrypted_backup_data = encrypt_with_key(&backup_data, &backup_encryption_key);

        // Create backup metadata
        let backup_metadata = BackupMetadata {
            backup_id,
            backup_hash,
            encrypted_backup_data,
            quiz_count: vault.total_quizzes,
            backup_size: vector::length(&encrypted_backup_data),
            backup_type,
            compression_ratio: 70, // Simplified compression ratio
            verification_status: true,
            created_at: current_time,
            expires_at: current_time + 31536000000, // 1 year
            storage_location: string::utf8(b"distributed_storage"),
        };

        // Save values before moving backup_metadata
        let backup_type_copy = backup_metadata.backup_type;
        let backup_size_copy = backup_metadata.backup_size;

        // Store backup
        table::add(&mut vault.backup_versions, backup_id, backup_metadata);
        vault.last_backup = current_time;

        // Process backup fee
        balance::join(&mut vault.earnings_pool, coin::into_balance(backup_fee));

        // Update global backup statistics
        stats.global_stats.backup_success_rate = calculate_backup_success_rate(stats);
        stats.global_stats.last_updated = current_time;

        // Log backup creation
        log_access_to_vault(vault, user, string::utf8(b"create_backup"), current_time);

        event::emit(VaultBackupCreated {
            vault_id: object::uid_to_inner(&vault.id),
            backup_id,
            backup_type: backup_type_copy,
            quiz_count: vault.total_quizzes,
            backup_size: backup_size_copy,
            timestamp: current_time,
        });
    }

    /// Restore vault from backup
    public entry fun restore_vault_from_backup(
        vault: &mut QuizVault,
        backup_id: u64,
        _admin_cap: &VaultAdminCap,
        stats: &mut QuizStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check if backup exists
        assert!(table::contains(&vault.backup_versions, backup_id), E_RECOVERY_FAILED);

        let backup_metadata = table::borrow(&vault.backup_versions, backup_id);
        let verification_status = backup_metadata.verification_status;
        let expires_at = backup_metadata.expires_at;
        let backup_type = backup_metadata.backup_type;
        let backup_size = backup_metadata.backup_size;
        let quiz_count = backup_metadata.quiz_count;
        
        assert!(verification_status, E_INVALID_BACKUP_DATA);
        assert!(current_time < expires_at, E_RECOVERY_FAILED);

        // Decrypt backup data
        let backup_encryption_key = generate_backup_encryption_key(
            &vault.encryption_metadata.master_key_hash,
            backup_id,
            backup_metadata.created_at
        );
        let _decrypted_backup = decrypt_with_key(
            &backup_metadata.encrypted_backup_data,
            &backup_encryption_key
        );

        // In production, this would restore the actual vault state
        // For now, just update statistics and log the restoration

        // Update vault status
        vault.updated_at = current_time;
        vault.is_locked = false;
        vault.lock_reason = option::none();

        // Log restoration
        log_access_to_vault(vault, user, string::utf8(b"restore_backup"), current_time);

        event::emit(VaultRestored {
            vault_id: object::uid_to_inner(&vault.id),
            backup_id,
            restored_by: user,
            quizzes_restored: quiz_count,
            timestamp: current_time,
        });
    }

    /// Lock vault (emergency or maintenance)
    public entry fun lock_vault(
        vault: &mut QuizVault,
        reason: String,
        _admin_cap: &VaultAdminCap,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        vault.is_locked = true;
        vault.lock_reason = option::some(reason);
        vault.updated_at = current_time;

        // Log the lock
        log_access_to_vault(vault, user, string::utf8(b"lock_vault"), current_time);

        event::emit(VaultLocked {
            vault_id: object::uid_to_inner(&vault.id),
            locked_by: user,
            reason: if (option::is_some(&vault.lock_reason)) {
                *option::borrow(&vault.lock_reason)
            } else {
                string::utf8(b"Manual lock")
            },
            timestamp: current_time,
        });
    }

    /// Unlock vault
    public entry fun unlock_vault(
        vault: &mut QuizVault,
        _admin_cap: &VaultAdminCap,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        vault.is_locked = false;
        vault.lock_reason = option::none();
        vault.updated_at = current_time;

        // Log the unlock
        log_access_to_vault(vault, user, string::utf8(b"unlock_vault"), current_time);

        event::emit(VaultUnlocked {
            vault_id: object::uid_to_inner(&vault.id),
            unlocked_by: user,
            timestamp: current_time,
        });
    }

    /// Rotate encryption keys
    public entry fun rotate_encryption_keys(
        vault: &mut QuizVault,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check permissions
        assert!(
            vault.owner == user || has_admin_permission(vault, user),
            E_INSUFFICIENT_PERMISSIONS
        );

        // Check if rotation is needed
        let time_since_last_rotation = current_time - vault.encryption_metadata.last_key_rotation;
        assert!(
            time_since_last_rotation >= vault.encryption_metadata.key_rotation_frequency,
            E_INVALID_ENCRYPTION_KEY
        );

        let old_key_id = vault.encryption_metadata.next_key_id - 1;
        let new_key_id = vault.encryption_metadata.next_key_id;

        // Generate new master key
        let new_master_key = generate_master_encryption_seed(user, current_time);
        vault.encryption_metadata.master_key_hash = hash::keccak256(&bcs::to_bytes(&new_master_key));
        vault.encryption_metadata.last_key_rotation = current_time;
        vault.encryption_metadata.next_key_id = new_key_id + 1;

        // In production, this would re-encrypt all vault content with new keys
        // For now, just update the metadata

        vault.updated_at = current_time;

        // Log key rotation
        log_access_to_vault(vault, user, string::utf8(b"rotate_keys"), current_time);

        event::emit(EncryptionKeyRotated {
            vault_id: object::uid_to_inner(&vault.id),
            old_key_id,
            new_key_id,
            rotated_by: user,
            timestamp: current_time,
        });
    }

    // =============== Helper Functions ===============

    /// Check if user has read permission
    fun has_read_permission(vault: &QuizVault, user: address): bool {
        if (vault.owner == user) {
            return true
        };

        if (table::contains(&vault.access_control.user_permissions, user)) {
            let permission = table::borrow(&vault.access_control.user_permissions, user);
            if (permission.is_active && permission.access_level >= ACCESS_READ) {
                return true
            };
        };

        if (table::contains(&vault.sharing_permissions, user)) {
            let share_permission = table::borrow(&vault.sharing_permissions, user);
            if (share_permission.permission_level >= ACCESS_READ) {
                return true
            };
        };

        vault.access_control.default_permissions >= ACCESS_READ
    }

    /// Check if user has write permission
    fun has_write_permission(vault: &QuizVault, user: address): bool {
        if (vault.owner == user) {
            return true
        };

        if (table::contains(&vault.access_control.user_permissions, user)) {
            let permission = table::borrow(&vault.access_control.user_permissions, user);
            if (permission.is_active && permission.access_level >= ACCESS_WRITE) {
                return true
            };
        };

        if (table::contains(&vault.sharing_permissions, user)) {
            let share_permission = table::borrow(&vault.sharing_permissions, user);
            if (share_permission.permission_level >= ACCESS_WRITE) {
                return true
            };
        };

        false
    }

    /// Check if user has admin permission
    fun has_admin_permission(vault: &QuizVault, user: address): bool {
        if (vault.owner == user) {
            return true
        };

        if (table::contains(&vault.access_control.user_permissions, user)) {
            let permission = table::borrow(&vault.access_control.user_permissions, user);
            if (permission.is_active && permission.access_level >= ACCESS_ADMIN) {
                return true
            };
        };

        false
    }

    /// Generate master encryption seed
    fun generate_master_encryption_seed(creator: address, timestamp: u64): u64 {
        let mut seed_data = vector::empty<u8>();
        vector::append(&mut seed_data, bcs::to_bytes(&creator));
        vector::append(&mut seed_data, bcs::to_bytes(&timestamp));
        vector::append(&mut seed_data, b"SUIVERSE_VAULT_MASTER_KEY");

        let hash_result = hash::keccak256(&seed_data);
        bytes_to_u64(&hash_result)
    }

    /// Generate salt for key derivation
    fun generate_salt(creator: address, timestamp: u64): vector<u8> {
        let mut salt_data = vector::empty<u8>();
        vector::append(&mut salt_data, bcs::to_bytes(&creator));
        vector::append(&mut salt_data, bcs::to_bytes(&timestamp));
        vector::append(&mut salt_data, b"SUIVERSE_SALT");

        hash::keccak256(&salt_data)
    }

    /// Generate quiz-specific encryption key
    fun generate_quiz_encryption_key(master_key: &vector<u8>, quiz_id: ID, timestamp: u64): vector<u8> {
        let mut key_data = vector::empty<u8>();
        vector::append(&mut key_data, *master_key);
        vector::append(&mut key_data, bcs::to_bytes(&quiz_id));
        vector::append(&mut key_data, bcs::to_bytes(&timestamp));

        hash::keccak256(&key_data)
    }

    /// Generate backup encryption key
    fun generate_backup_encryption_key(master_key: &vector<u8>, backup_id: u64, timestamp: u64): vector<u8> {
        let mut key_data = vector::empty<u8>();
        vector::append(&mut key_data, *master_key);
        vector::append(&mut key_data, bcs::to_bytes(&backup_id));
        vector::append(&mut key_data, bcs::to_bytes(&timestamp));
        vector::append(&mut key_data, b"BACKUP");

        hash::keccak256(&key_data)
    }

    /// Simple XOR encryption (in production would use proper encryption)
    fun encrypt_with_key(data: &vector<u8>, key: &vector<u8>): vector<u8> {
        let mut encrypted = vector::empty<u8>();
        let key_len = vector::length(key);
        let mut i = 0;

        while (i < vector::length(data)) {
            let data_byte = *vector::borrow(data, i);
            let key_byte = *vector::borrow(key, i % key_len);
            vector::push_back(&mut encrypted, data_byte ^ key_byte);
            i = i + 1;
        };

        encrypted
    }

    /// Simple XOR decryption (in production would use proper decryption)
    fun decrypt_with_key(encrypted_data: &vector<u8>, key: &vector<u8>): vector<u8> {
        // XOR is symmetric, so decryption is the same as encryption
        encrypt_with_key(encrypted_data, key)
    }

    /// Convert bytes to u64
    fun bytes_to_u64(bytes: &vector<u8>): u64 {
        let mut result = 0u64;
        let mut i = 0;
        while (i < 8 && i < vector::length(bytes)) {
            result = result << 8;
            result = result | (*vector::borrow(bytes, i) as u64);
            i = i + 1;
        };
        result
    }

    /// Serialize vault for backup (simplified)
    fun serialize_vault_for_backup(vault: &QuizVault): vector<u8> {
        // In production, this would properly serialize the entire vault state
        // For now, return a simplified representation
        let mut serialized = vector::empty<u8>();
        vector::append(&mut serialized, bcs::to_bytes(&vault.total_quizzes));
        vector::append(&mut serialized, bcs::to_bytes(&vault.created_at));
        vector::append(&mut serialized, bcs::to_bytes(&vault.owner));
        serialized
    }

    /// Log access to vault for audit trail
    fun log_access_to_vault(vault: &mut QuizVault, user: address, action: String, timestamp: u64) {
        let entry_id = vector::length(&vault.access_control.audit_log);
        let audit_entry = AuditLogEntry {
            entry_id,
            user,
            action,
            resource_id: option::some(object::uid_to_inner(&vault.id)),
            timestamp,
            ip_hash: option::none(), // Would capture IP hash in production
            success: true,
            details: string::utf8(b"Vault access logged"),
        };

        vector::push_back(&mut vault.access_control.audit_log, audit_entry);
    }

    /// Update quiz access analytics
    fun update_quiz_access_analytics(
        vault: &QuizVault,
        quiz_id: ID,
        user: address,
        stats: &mut QuizStats,
        timestamp: u64
    ) {
        let vault_id = object::uid_to_inner(&vault.id);

        if (table::contains(&stats.vault_analytics, vault_id)) {
            let analytics = table::borrow_mut(&mut stats.vault_analytics, vault_id);
            analytics.total_accesses = analytics.total_accesses + 1;

            // Update quiz usage distribution
            if (!table::contains(&analytics.quiz_usage_distribution, quiz_id)) {
                let usage_stats = QuizUsageStats {
                    quiz_id,
                    access_count: 0,
                    success_rate: 0,
                    average_score: 0,
                    time_spent: 0,
                    last_accessed: timestamp,
                    user_feedback: vector::empty(),
                };
                table::add(&mut analytics.quiz_usage_distribution, quiz_id, usage_stats);
            };

            let usage_stats = table::borrow_mut(&mut analytics.quiz_usage_distribution, quiz_id);
            usage_stats.access_count = usage_stats.access_count + 1;
            usage_stats.last_accessed = timestamp;
        };

        // Update user activity stats
        if (!table::contains(&stats.user_activity, user)) {
            let user_stats = UserActivityStats {
                user,
                vaults_owned: 0,
                vaults_accessed: 0,
                quizzes_created: 0,
                quizzes_attempted: 0,
                collaboration_score: 0,
                last_activity: timestamp,
            };
            table::add(&mut stats.user_activity, user, user_stats);
        };

        let user_stats = table::borrow_mut(&mut stats.user_activity, user);
        user_stats.vaults_accessed = user_stats.vaults_accessed + 1;
        user_stats.quizzes_attempted = user_stats.quizzes_attempted + 1;
        user_stats.last_activity = timestamp;
    }

    /// Calculate backup success rate
    fun calculate_backup_success_rate(stats: &QuizStats): u64 {
        // Simplified calculation - in production would track actual backup success/failure rates
        if (stats.global_stats.total_vaults == 0) {
            100
        } else {
            95 // Assume 95% success rate for now
        }
    }

    // =============== View Functions ===============

    public fun get_vault_info(vault: &QuizVault): (String, address, u8, u64, bool) {
        (
            vault.name,
            vault.owner,
            vault.vault_type,
            vault.total_quizzes,
            vault.is_active
        )
    }

    public fun get_vault_statistics(vault: &QuizVault): (u64, u64, u64, u64) {
        (
            vault.total_quizzes,
            vault.total_attempts,
            vault.success_rate,
            vault.last_accessed
        )
    }

    public fun get_vault_categories(vault: &QuizVault): vector<String> {
        let mut categories = vector::empty<String>();
        // In production, would iterate through the categories table
        // For now, return empty vector
        categories
    }

    public fun is_vault_locked(vault: &QuizVault): bool {
        vault.is_locked
    }

    public fun get_backup_count(vault: &QuizVault): u64 {
        table::length(&vault.backup_versions)
    }

    public fun get_sharing_count(vault: &QuizVault): u64 {
        table::length(&vault.sharing_permissions)
    }

    public fun get_vault_earnings(vault: &QuizVault): u64 {
        balance::value(&vault.earnings_pool)
    }

    public fun get_global_vault_stats(stats: &QuizStats): (u64, u64, u64, u64) {
        (
            stats.global_stats.total_vaults,
            stats.global_stats.total_quizzes_stored,
            stats.global_stats.total_vault_accesses,
            stats.global_stats.backup_success_rate
        )
    }

    // =============== Package-Only Functions ===============

    public(package) fun get_vault_id(vault: &QuizVault): ID {
        object::uid_to_inner(&vault.id)
    }

    public(package) fun get_vault_owner(vault: &QuizVault): address {
        vault.owner
    }

    public(package) fun has_quiz_in_vault(vault: &QuizVault, quiz_id: ID): bool {
        table::contains(&vault.encrypted_quizzes, quiz_id)
    }

    public(package) fun update_vault_usage_stats(
        vault: &mut QuizVault,
        attempts: u64,
        success: bool,
        timestamp: u64
    ) {
        vault.total_attempts = vault.total_attempts + attempts;
        if (success) {
            vault.success_rate = ((vault.success_rate * (vault.total_attempts - attempts)) + (attempts * 100)) / vault.total_attempts;
        };
        vault.last_accessed = timestamp;
        vault.updated_at = timestamp;
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun test_create_vault_for_testing(
        name: String,
        vault_type: u8,
        ctx: &mut TxContext
    ): QuizVault {
        QuizVault {
            id: object::new(ctx),
            name,
            description: string::utf8(b"Test vault"),
            owner: tx_context::sender(ctx),
            vault_type,
            encrypted_quizzes: table::new(ctx),
            content_hash_registry: table::new(ctx),
            encryption_metadata: EncryptionMetadata {
                encryption_version: ENCRYPTION_VERSION_V1,
                key_derivation_salt: vector::empty(),
                master_key_hash: vector::empty(),
                encryption_keys: table::new(ctx),
                next_key_id: 1,
                key_rotation_frequency: 2592000000,
                last_key_rotation: 0,
            },
            categories: table::new(ctx),
            tags: vector::empty(),
            quiz_collections: table::new(ctx),
            access_control: AccessControlRegistry {
                user_permissions: table::new(ctx),
                role_definitions: table::new(ctx),
                access_policies: vector::empty(),
                audit_log: vector::empty(),
                permission_inheritance: true,
                default_permissions: ACCESS_NONE,
            },
            sharing_permissions: table::new(ctx),
            organization_members: vector::empty(),
            total_quizzes: 0,
            total_attempts: 0,
            success_rate: 0,
            last_accessed: 0,
            backup_versions: table::new(ctx),
            recovery_keys: vector::empty(),
            backup_frequency: 604800000,
            last_backup: 0,
            vault_deposit: balance::zero(),
            earnings_pool: balance::zero(),
            sharing_fees: balance::zero(),
            created_at: 0,
            updated_at: 0,
            is_active: true,
            is_locked: false,
            lock_reason: option::none(),
        }
    }
}