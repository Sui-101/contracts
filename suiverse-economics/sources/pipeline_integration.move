/// Pipeline Integration Layer
/// 
/// Provides seamless integration between the article validation pipeline
/// and existing SuiVerse modules across all three packages.
/// Handles cross-package communication and state synchronization.
module suiverse_economics::pipeline_integration {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::dynamic_field as df;

    // Import from all packages (simplified)
    use suiverse_core::governance::{Self};
    use suiverse_core::parameters::{Self, GlobalParameters};
    use suiverse_core::treasury::{Self, Treasury};
    use suiverse_content::articles::{Self as articles};
    use suiverse_content::config::{ContentConfig};
    use suiverse_economics::article_validation_pipeline::{Self, ValidatorRegistry};
    use suiverse_economics::rewards::{Self, RewardPool};
    use suiverse_economics::learning_incentives::{Self, IncentiveRegistry};
    use suiverse_economics::economics_integration::{Self, EconomicsHub};

    // =============== Constants ===============

    // Error codes
    const E_INTEGRATION_NOT_ACTIVE: u64 = 6001;
    const E_INVALID_PACKAGE_STATE: u64 = 6002;
    const E_CROSS_PACKAGE_SYNC_FAILED: u64 = 6003;
    const E_INSUFFICIENT_PERMISSIONS: u64 = 6004;
    const E_PIPELINE_CONFLICT: u64 = 6005;
    const E_OBJECT_NOT_FOUND: u64 = 6006;
    const E_EPOCH_MISMATCH: u64 = 6007;
    const E_VALIDATION_ALREADY_EXISTS: u64 = 6008;

    // Integration status
    const STATUS_INITIALIZING: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_MAINTENANCE: u8 = 2;
    const STATUS_EMERGENCY: u8 = 3;

    // Article types
    const ARTICLE_TYPE_ORIGINAL: u8 = 1;
    const ARTICLE_TYPE_EXTERNAL: u8 = 2;

    // Validation outcomes
    const OUTCOME_APPROVED: u8 = 1;
    const OUTCOME_REJECTED: u8 = 2;
    const OUTCOME_PENDING: u8 = 3;

    // =============== Structs ===============

    /// Central integration hub coordinating all packages
    public struct IntegrationHub has key {
        id: UID,
        
        // Status and configuration
        integration_status: u8,
        last_sync_timestamp: u64,
        sync_failures: u64,
        
        // Package object references
        validator_registry_id: Option<ID>,
        economics_hub_id: Option<ID>,
        treasury_id: Option<ID>,
        content_config_id: Option<ID>,
        governance_config_id: Option<ID>,
        
        // Cross-package state tracking
        active_validations: Table<ID, ValidationState>,
        epoch_sync_status: Table<u64, EpochSyncStatus>,
        pending_cross_package_actions: Table<ID, CrossPackageAction>,
        
        // Metrics and monitoring
        total_articles_processed: u64,
        total_rewards_distributed: u64,
        integration_pool: Balance<SUI>,
        
        admin_cap: ID,
    }

    /// Tracks validation state across packages
    public struct ValidationState has store {
        article_id: ID,
        article_type: u8,
        author: address,
        current_package: String, // Which package currently owns the state
        validation_stage: String, // Current stage in pipeline
        created_timestamp: u64,
        last_update: u64,
        
        // Cross-package data
        content_metadata: Option<ContentMetadata>,
        validation_data: Option<ValidationData>,
        economic_data: Option<EconomicData>,
    }

    /// Content package metadata
    public struct ContentMetadata has store {
        title: String,
        category: String,
        difficulty: u8,
        content_hash: vector<u8>,
        deposit_amount: u64,
        status: u8,
    }

    /// Validation package data
    public struct ValidationData has store {
        assigned_validators: vector<address>,
        reviews_submitted: u64,
        consensus_score: Option<u8>,
        approval_status: u8,
        validation_deadline: u64,
    }

    /// Economics package data
    public struct EconomicData has store {
        reward_pool_allocated: u64,
        validator_rewards: u64,
        author_rewards: u64,
        quality_bonus: u64,
        incentive_multiplier: u64,
    }

    /// Epoch synchronization status
    public struct EpochSyncStatus has store {
        epoch_number: u64,
        content_synced: bool,
        validation_synced: bool,
        economics_synced: bool,
        rewards_distributed: bool,
        sync_timestamp: u64,
    }

    /// Cross-package action tracking
    public struct CrossPackageAction has store {
        action_id: ID,
        action_type: String,
        source_package: String,
        target_package: String,
        payload: vector<u8>,
        scheduled_time: u64,
        executed: bool,
        retry_count: u64,
    }

    /// Integration admin capability
    public struct IntegrationAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct ArticleValidationStarted has copy, drop {
        article_id: ID,
        article_type: u8,
        author: address,
        assigned_validators: vector<address>,
        validation_deadline: u64,
        deposit_amount: u64,
        integration_timestamp: u64,
    }

    public struct ValidationCompleted has copy, drop {
        article_id: ID,
        approved: bool,
        consensus_score: u8,
        participating_validators: u64,
        validation_duration: u64,
        rewards_scheduled: bool,
        integration_timestamp: u64,
    }

    public struct CrossPackageSyncCompleted has copy, drop {
        epoch_number: u64,
        articles_processed: u64,
        rewards_distributed: u64,
        sync_duration: u64,
        sync_timestamp: u64,
    }

    public struct IntegrationErrorEvent has copy, drop {
        error_type: String,
        error_code: u64,
        affected_article: Option<ID>,
        error_details: String,
        retry_scheduled: bool,
        timestamp: u64,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        let admin_cap = IntegrationAdminCap {
            id: object::new(ctx),
        };

        let hub = IntegrationHub {
            id: object::new(ctx),
            integration_status: STATUS_INITIALIZING,
            last_sync_timestamp: 0,
            sync_failures: 0,
            validator_registry_id: option::none(),
            economics_hub_id: option::none(),
            treasury_id: option::none(),
            content_config_id: option::none(),
            governance_config_id: option::none(),
            active_validations: table::new(ctx),
            epoch_sync_status: table::new(ctx),
            pending_cross_package_actions: table::new(ctx),
            total_articles_processed: 0,
            total_rewards_distributed: 0,
            integration_pool: balance::zero(),
            admin_cap: object::id(&admin_cap),
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(hub);
    }

    // =============== Core Integration Functions ===============

    /// Complete article creation and validation workflow
    public entry fun submit_article_and_start_validation(
        hub: &mut IntegrationHub,
        validator_registry: &mut ValidatorRegistry,
        global_params: &GlobalParameters,
        
        // Article data
        title: String,
        content_hash: vector<u8>,
        tags: vector<ID>,
        category: String,
        difficulty: u8,
        word_count: u64,
        language: String,
        preview: String,
        cover_image: Option<String>,
        
        // Payment and settings
        payment: &mut Coin<SUI>,
        selection_method: u8,
        
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(hub.integration_status == STATUS_ACTIVE, E_INTEGRATION_NOT_ACTIVE);
        
        let author = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Step 1: Create article in content package (simplified)
        let deposit_amount = parameters::get_article_deposit_original(global_params);
        
        // Get the article ID (simplified - in real implementation would track creation)
        let article_id = object::id_from_bytes(content_hash); // Placeholder
        
        // Step 2: Submit for validation pipeline
        article_validation_pipeline::submit_article_for_validation(
            validator_registry,
            article_id,
            ARTICLE_TYPE_ORIGINAL,
            category,
            difficulty,
            coin::split(payment, 0, ctx), // Additional deposit if needed
            selection_method,
            clock,
            ctx,
        );
        
        // Step 3: Track in integration hub
        let validation_state = ValidationState {
            article_id,
            article_type: ARTICLE_TYPE_ORIGINAL,
            author,
            current_package: string::utf8(b"validation"),
            validation_stage: string::utf8(b"validator_assignment"),
            created_timestamp: current_time,
            last_update: current_time,
            content_metadata: option::some(ContentMetadata {
                title,
                category,
                difficulty,
                content_hash,
                deposit_amount,
                status: 0, // Pending
            }),
            validation_data: option::none(),
            economic_data: option::none(),
        };
        
        table::add(&mut hub.active_validations, article_id, validation_state);
        
        event::emit(ArticleValidationStarted {
            article_id,
            article_type: ARTICLE_TYPE_ORIGINAL,
            author,
            assigned_validators: vector::empty(), // Will be populated by pipeline
            validation_deadline: current_time + 172800000, // 48 hours
            deposit_amount,
            integration_timestamp: current_time,
        });
    }

    /// Handle validation completion and trigger rewards
    public entry fun complete_validation_and_distribute_rewards(
        hub: &mut IntegrationHub,
        validator_registry: &mut ValidatorRegistry,
        content_config: &mut ContentConfig,
        economics_hub: &mut EconomicsHub,
        treasury: &mut Treasury,
        reward_pool: &mut RewardPool,
        incentive_registry: &mut IncentiveRegistry,
        
        article_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&hub.active_validations, article_id), E_OBJECT_NOT_FOUND);
        
        let current_time = clock::timestamp_ms(clock);
        let validation_state = table::borrow_mut(&mut hub.active_validations, article_id);
        
        // Step 1: Get validation results from pipeline
        let (status, approval_percentage, consensus_reached, review_count) = 
            article_validation_pipeline::get_pipeline_status(validator_registry, article_id);
        
        assert!(consensus_reached, E_VALIDATION_ALREADY_EXISTS);
        
        let approved = status == 2; // STATUS_APPROVED
        
        // Step 2: Update article status in content package
        articles::update_article_status(
            content_config,
            article_id,
            true, // is_original
            approved,
            clock,
            ctx,
        );
        
        // Step 3: Process rewards based on outcome
        if (approved) {
            // Record successful content creation activity
            rewards::record_content_activity(
                validation_state.author,
                reward_pool,
                reward_pool, // config placeholder
                clock,
                ctx,
            );
            
            // Record learning incentives
            learning_incentives::record_learning_activity(
                incentive_registry,
                validation_state.content_metadata.category,
                2, // learning_hours
                5, // concepts_learned
                85, // retention_test_score
                false, // is_cross_domain
                clock,
                ctx,
            );
        };
        
        // Step 4: Update integration state
        validation_state.current_package = string::utf8(b"completed");
        validation_state.validation_stage = if (approved) {
            string::utf8(b"approved")
        } else {
            string::utf8(b"rejected")
        };
        validation_state.last_update = current_time;
        
        // Update economic data
        validation_state.economic_data = option::some(EconomicData {
            reward_pool_allocated: 1000_000_000, // 1 SUI
            validator_rewards: 500_000_000 * review_count,
            author_rewards: if (approved) 5_000_000_000 else 0,
            quality_bonus: if (approval_percentage > 85) 1_000_000_000 else 0,
            incentive_multiplier: 100,
        });
        
        hub.total_articles_processed = hub.total_articles_processed + 1;
        
        event::emit(ValidationCompleted {
            article_id,
            approved,
            consensus_score: approval_percentage,
            participating_validators: review_count,
            validation_duration: current_time - validation_state.created_timestamp,
            rewards_scheduled: true,
            integration_timestamp: current_time,
        });
    }

    /// Synchronize epoch data across all packages
    public entry fun synchronize_epoch_data(
        hub: &mut IntegrationHub,
        validator_registry: &mut ValidatorRegistry,
        economics_hub: &mut EconomicsHub,
        reward_pool: &mut RewardPool,
        
        epoch_number: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Create or update epoch sync status
        if (!table::contains(&hub.epoch_sync_status, epoch_number)) {
            let sync_status = EpochSyncStatus {
                epoch_number,
                content_synced: false,
                validation_synced: false,
                economics_synced: false,
                rewards_distributed: false,
                sync_timestamp: current_time,
            };
            table::add(&mut hub.epoch_sync_status, epoch_number, sync_status);
        };
        
        let sync_status = table::borrow_mut(&mut hub.epoch_sync_status, epoch_number);
        
        // Step 1: Sync validation data
        if (!sync_status.validation_synced) {
            let (total_processed, total_allocated, distributed) = 
                article_validation_pipeline::get_epoch_rewards_info(validator_registry, epoch_number);
            
            if (total_processed > 0) {
                sync_status.validation_synced = true;
            };
        };
        
        // Step 2: Sync economics data
        if (!sync_status.economics_synced) {
            let economics_health = economics_integration::get_economic_health_score(economics_hub);
            
            if (economics_health > 50) {
                sync_status.economics_synced = true;
            };
        };
        
        // Step 3: Distribute epoch rewards if all synced
        if (sync_status.validation_synced && 
            sync_status.economics_synced && 
            !sync_status.rewards_distributed) {
            
            // Trigger epoch reward distribution
            sync_status.rewards_distributed = true;
            hub.total_rewards_distributed = hub.total_rewards_distributed + 1000_000_000; // Placeholder
        };
        
        sync_status.sync_timestamp = current_time;
        hub.last_sync_timestamp = current_time;
        
        event::emit(CrossPackageSyncCompleted {
            epoch_number,
            articles_processed: hub.total_articles_processed,
            rewards_distributed: hub.total_rewards_distributed,
            sync_duration: 1000, // Placeholder
            sync_timestamp: current_time,
        });
    }

    /// Handle validation review submission with integration
    public entry fun submit_integrated_review(
        hub: &mut IntegrationHub,
        validator_registry: &mut ValidatorRegistry,
        incentive_registry: &mut IncentiveRegistry,
        
        article_id: ID,
        criteria_scores: vector<u8>,
        overall_score: u8,
        comments: String,
        recommendation: u8,
        confidence_level: u8,
        
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&hub.active_validations, article_id), E_OBJECT_NOT_FOUND);
        
        let validator = tx_context::sender(ctx);
        
        // Step 1: Submit review to validation pipeline
        article_validation_pipeline::submit_detailed_review(
            validator_registry,
            article_id,
            criteria_scores,
            overall_score,
            comments,
            recommendation,
            confidence_level,
            true, // expertise_relevant
            false, // conflict_of_interest
            clock,
            ctx,
        );
        
        // Step 2: Record validation activity for incentives
        learning_incentives::record_learning_activity(
            incentive_registry,
            string::utf8(b"content_validation"),
            1, // learning_hours
            3, // concepts_learned
            (overall_score as u64), // retention_test_score
            false, // is_cross_domain
            clock,
            ctx,
        );
        
        // Step 3: Update integration tracking
        let validation_state = table::borrow_mut(&hub.active_validations, article_id);
        validation_state.last_update = clock::timestamp_ms(clock);
        validation_state.validation_stage = string::utf8(b"review_submitted");
    }

    /// Batch process multiple articles
    public entry fun batch_process_articles(
        hub: &mut IntegrationHub,
        validator_registry: &mut ValidatorRegistry,
        content_config: &mut ContentConfig,
        
        article_ids: vector<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let mut i = 0;
        let batch_size = vector::length(&article_ids);
        
        while (i < batch_size && i < 10) { // Limit batch size for gas efficiency
            let article_id = *vector::borrow(&article_ids, i);
            
            if (table::contains(&hub.active_validations, article_id)) {
                let validation_state = table::borrow(&hub.active_validations, article_id);
                
                // Check if validation is complete and needs processing
                let (status, _, consensus_reached, _) = 
                    article_validation_pipeline::get_pipeline_status(validator_registry, article_id);
                
                if (consensus_reached && validation_state.current_package == string::utf8(b"validation")) {
                    // Update article status
                    articles::update_article_status(
                        content_config,
                        article_id,
                        validation_state.article_type == ARTICLE_TYPE_ORIGINAL,
                        status == 2, // approved
                        clock,
                        ctx,
                    );
                };
            };
            
            i = i + 1;
        };
    }

    // =============== View Functions ===============

    public fun get_validation_state(
        hub: &IntegrationHub,
        article_id: ID,
    ): (u8, String, u64, bool) {
        if (!table::contains(&hub.active_validations, article_id)) {
            return (0, string::utf8(b"not_found"), 0, false)
        };
        
        let state = table::borrow(&hub.active_validations, article_id);
        (
            state.article_type,
            state.validation_stage,
            state.last_update,
            option::is_some(&state.economic_data)
        )
    }

    public fun get_integration_stats(hub: &IntegrationHub): (u8, u64, u64, u64) {
        (
            hub.integration_status,
            hub.total_articles_processed,
            hub.total_rewards_distributed,
            hub.sync_failures
        )
    }

    public fun get_epoch_sync_status(
        hub: &IntegrationHub,
        epoch: u64,
    ): (bool, bool, bool, bool) {
        if (!table::contains(&hub.epoch_sync_status, epoch)) {
            return (false, false, false, false)
        };
        
        let status = table::borrow(&hub.epoch_sync_status, epoch);
        (
            status.content_synced,
            status.validation_synced,
            status.economics_synced,
            status.rewards_distributed
        )
    }

    // =============== Admin Functions ===============

    public entry fun link_package_objects(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
        validator_registry_id: Option<ID>,
        economics_hub_id: Option<ID>,
        treasury_id: Option<ID>,
        content_config_id: Option<ID>,
        governance_config_id: Option<ID>,
    ) {
        hub.validator_registry_id = validator_registry_id;
        hub.economics_hub_id = economics_hub_id;
        hub.treasury_id = treasury_id;
        hub.content_config_id = content_config_id;
        hub.governance_config_id = governance_config_id;
    }

    public entry fun update_integration_status(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
        new_status: u8,
    ) {
        hub.integration_status = new_status;
    }

    public entry fun fund_integration_pool(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
        funding: Coin<SUI>,
    ) {
        let funding_balance = coin::into_balance(funding);
        balance::join(&mut hub.integration_pool, funding_balance);
    }

    public entry fun cleanup_completed_validations(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
        max_cleanup: u64,
    ) {
        // Remove old completed validations to prevent table growth
        // Implementation would iterate through active_validations and remove old entries
        let _ = max_cleanup; // Placeholder to avoid unused parameter warning
    }

    // =============== Emergency Functions ===============

    public entry fun emergency_halt_integration(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
    ) {
        hub.integration_status = STATUS_EMERGENCY;
    }

    public entry fun emergency_resume_integration(
        _: &IntegrationAdminCap,
        hub: &mut IntegrationHub,
    ) {
        hub.integration_status = STATUS_ACTIVE;
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun test_create_validation_state(
        hub: &mut IntegrationHub,
        article_id: ID,
        author: address,
        ctx: &mut TxContext,
    ) {
        let validation_state = ValidationState {
            article_id,
            article_type: ARTICLE_TYPE_ORIGINAL,
            author,
            current_package: string::utf8(b"test"),
            validation_stage: string::utf8(b"test"),
            created_timestamp: 0,
            last_update: 0,
            content_metadata: option::none(),
            validation_data: option::none(),
            economic_data: option::none(),
        };
        
        table::add(&mut hub.active_validations, article_id, validation_state);
    }
}