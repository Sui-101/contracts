/// Content Configuration Module using Dynamic Fields Pattern
/// 
/// This module provides configuration management for the content package
/// using the DF pattern for modularity and upgradability.
module suiverse_content::config {
    use std::string::{Self, String};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::dynamic_field as df;  // Changed from DOF to DF
    
    // Core module imports
    use suiverse_core::parameters::{GlobalParameters};
    
    // === Error Codes ===
    const E_NOT_AUTHORIZED: u64 = 5001;
    const E_ALREADY_INITIALIZED: u64 = 5002;
    const E_NOT_INITIALIZED: u64 = 5003;
    const E_INVALID_CONFIG_KEY: u64 = 5004;
    const E_CONFIG_NOT_FOUND: u64 = 5005;
    const E_CONFIG_ALREADY_EXISTS: u64 = 5006;
    #[allow(unused_const)]
    const E_EMERGENCY_PAUSED: u64 = 5007;
    
    // === DF Config Keys ===
    const GLOBAL_PARAMETERS_KEY: vector<u8> = b"GLOBAL_PARAMETERS";
    const ARTICLE_STATS_KEY: vector<u8> = b"ARTICLE_STATS";
    const PROJECT_STATS_KEY: vector<u8> = b"PROJECT_STATS";
    const VALIDATION_CONFIG_KEY: vector<u8> = b"VALIDATION_CONFIG";
    
    #[allow(unused_const)]
    const EMERGENCY_PAUSE_KEY: vector<u8> = b"EMERGENCY_PAUSE";
    
    // === Main Config Struct ===
    
    /// Main content configuration object
    public struct ContentConfig has key {
        id: UID,
        version: u64,
        last_updated: u64,
        is_initialized: bool,
        emergency_paused: bool,
    }
    
    /// Admin capability for config management
    public struct ConfigAdminCap has key, store {
        id: UID,
    }
    
    // === Reference Structs ===
    
    /// GlobalParameters reference (store only, no key)
    public struct GlobalParametersRef has store, copy, drop {
        params_id: ID,
    }
    
    // === Statistics Structs (store only, no key) ===
    
    /// Article statistics
    public struct ArticleStats has store, drop {
        total_original_articles: u64,
        total_external_articles: u64,
        total_approved: u64,
        total_rejected: u64,
        total_views: u64,
        articles_this_epoch: u64,
        views_this_epoch: u64,
        last_epoch_reset: u64,
    }
    
    /// Project statistics
    public struct ProjectStats has store {
        total_projects: u64,
        total_approved: u64,
        total_rejected: u64,
        total_views: u64,
        projects_this_epoch: u64,
        views_this_epoch: u64,
        last_epoch_reset: u64,
        active_projects: u64,
        completed_projects: u64,
        total_stars: u64,
        approved_projects: u64,
    }
    
    /// Validation configuration
    public struct ValidationConfig has store {
        min_validators_required: u64,
        validation_timeout_ms: u64,
        min_validator_stake: u64,
        validation_reward_rate: u64,
        auto_approve_threshold: u64,
    }
    
    // === Events ===
    
    public struct ContentConfigInitialized has copy, drop {
        config_id: ID,
        admin: address,
        timestamp: u64,
    }
    
    public struct EmergencyPauseToggled has copy, drop {
        config_id: ID,
        paused: bool,
        admin: address,
        timestamp: u64,
    }
    
    public struct StatsUpdated has copy, drop {
        config_id: ID,
        stats_type: String,
        timestamp: u64,
    }
    
    // === Init Function ===
    
    fun init(ctx: &mut TxContext) {
        let admin_cap = ConfigAdminCap {
            id: object::new(ctx),
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }
    
    // === Public Entry Functions ===
    
    /// Initialize the content configuration
    #[allow(lint(public_entry))]
    public entry fun initialize_content_config(
        _admin_cap: &ConfigAdminCap,
        global_params: &GlobalParameters,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let timestamp = clock::timestamp_ms(clock);
        
        // Create main config object
        let mut config = ContentConfig {
            id: object::new(ctx),
            version: 1,
            last_updated: timestamp,
            is_initialized: true,
            emergency_paused: false,
        };
        
        // Create GlobalParameters reference
        let params_ref = GlobalParametersRef {
            params_id: object::id(global_params),
        };
        
        // Attach global parameters reference using DF
        df::add(&mut config.id, string::utf8(GLOBAL_PARAMETERS_KEY), params_ref);
        
        // Create and attach default statistics (no ID field needed)
        let article_stats = ArticleStats {
            total_original_articles: 0,
            total_external_articles: 0,
            total_approved: 0,
            total_rejected: 0,
            total_views: 0,
            articles_this_epoch: 0,
            views_this_epoch: 0,
            last_epoch_reset: timestamp,
        };
        
        let project_stats = ProjectStats {
            total_projects: 0,
            total_approved: 0,
            total_rejected: 0,
            total_views: 0,
            projects_this_epoch: 0,
            views_this_epoch: 0,
            last_epoch_reset: timestamp,
            active_projects: 0,
            completed_projects: 0,
            total_stars: 0,
            approved_projects: 0,
        };
        
        let validation_config = ValidationConfig {
            min_validators_required: 3,
            validation_timeout_ms: 24 * 60 * 60 * 1000, // 24 hours
            min_validator_stake: 1000000, // 1 SUI in MIST
            validation_reward_rate: 100, // 0.1%
            auto_approve_threshold: 80, // 80% approval rate
        };
        
        // Attach statistics to config using DF
        df::add(&mut config.id, string::utf8(ARTICLE_STATS_KEY), article_stats);
        df::add(&mut config.id, string::utf8(PROJECT_STATS_KEY), project_stats);
        df::add(&mut config.id, string::utf8(VALIDATION_CONFIG_KEY), validation_config);
        
        let config_object_id = object::uid_to_inner(&config.id);
        
        // Emit initialization event
        sui::event::emit(ContentConfigInitialized {
            config_id: config_object_id,
            admin: tx_context::sender(ctx),
            timestamp,
        });
        
        transfer::share_object(config);
    }
    
    /// Toggle emergency pause
    #[allow(lint(public_entry))]
    public entry fun toggle_emergency_pause(
        _admin_cap: &ConfigAdminCap,
        config: &mut ContentConfig,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        config.emergency_paused = !config.emergency_paused;
        config.last_updated = clock::timestamp_ms(clock);
        config.version = config.version + 1;
        
        sui::event::emit(EmergencyPauseToggled {
            config_id: object::uid_to_inner(&config.id),
            paused: config.emergency_paused,
            admin: tx_context::sender(ctx),
            timestamp: config.last_updated,
        });
    }
    
    /// Update validation configuration
    #[allow(lint(public_entry))]
    public entry fun update_validation_config(
        _admin_cap: &ConfigAdminCap,
        config: &mut ContentConfig,
        min_validators: u64,
        timeout_ms: u64,
        min_stake: u64,
        reward_rate: u64,
        auto_approve_threshold: u64,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        let validation_config = df::borrow_mut<String, ValidationConfig>(
            &mut config.id, 
            string::utf8(VALIDATION_CONFIG_KEY)
        );
        
        validation_config.min_validators_required = min_validators;
        validation_config.validation_timeout_ms = timeout_ms;
        validation_config.min_validator_stake = min_stake;
        validation_config.validation_reward_rate = reward_rate;
        validation_config.auto_approve_threshold = auto_approve_threshold;
        
        config.last_updated = clock::timestamp_ms(clock);
        config.version = config.version + 1;
    }
    
    // === DF Accessor Functions ===
    
    /// Get global parameters reference
    public fun get_global_parameters_ref(config: &ContentConfig): &GlobalParametersRef {
        df::borrow<String, GlobalParametersRef>(&config.id, string::utf8(GLOBAL_PARAMETERS_KEY))
    }
    
    /// Get global parameters ID
    public fun get_global_parameters_id(config: &ContentConfig): ID {
        let params_ref = get_global_parameters_ref(config);
        params_ref.params_id
    }
    
    /// Get article stats (immutable)
    public fun get_article_stats(config: &ContentConfig): &ArticleStats {
        df::borrow<String, ArticleStats>(&config.id, string::utf8(ARTICLE_STATS_KEY))
    }
    
    /// Get article stats (mutable)
    public fun get_article_stats_mut(config: &mut ContentConfig): &mut ArticleStats {
        df::borrow_mut<String, ArticleStats>(&mut config.id, string::utf8(ARTICLE_STATS_KEY))
    }
    
    /// Get project stats (immutable)
    public fun get_project_stats(config: &ContentConfig): &ProjectStats {
        df::borrow<String, ProjectStats>(&config.id, string::utf8(PROJECT_STATS_KEY))
    }
    
    /// Get project stats (mutable)
    public fun get_project_stats_mut(config: &mut ContentConfig): &mut ProjectStats {
        df::borrow_mut<String, ProjectStats>(&mut config.id, string::utf8(PROJECT_STATS_KEY))
    }
    
    /// Get validation config (immutable)
    public fun get_validation_config(config: &ContentConfig): &ValidationConfig {
        df::borrow<String, ValidationConfig>(&config.id, string::utf8(VALIDATION_CONFIG_KEY))
    }
    
    /// Get validation config (mutable)
    public fun get_validation_config_mut(config: &mut ContentConfig): &mut ValidationConfig {
        df::borrow_mut<String, ValidationConfig>(&mut config.id, string::utf8(VALIDATION_CONFIG_KEY))
    }
    
    // === Admin Functions ===
    
    /// Attach article stats (for migration)
    #[allow(lint(public_entry))]
    public entry fun attach_article_stats(
        config: &mut ContentConfig,
        _admin_cap: &ConfigAdminCap,
        total_original: u64,
        total_external: u64,
        total_approved: u64,
        total_rejected: u64,
        total_views: u64,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        // Remove existing if present
        if (df::exists_<String>(&config.id, string::utf8(ARTICLE_STATS_KEY))) {
            let _old_stats: ArticleStats = df::remove<String, ArticleStats>(
                &mut config.id, 
                string::utf8(ARTICLE_STATS_KEY)
            );
            // No need to delete ID as ArticleStats no longer has one
        };
        
        let timestamp = clock::timestamp_ms(clock);
        let new_stats = ArticleStats {
            total_original_articles: total_original,
            total_external_articles: total_external,
            total_approved,
            total_rejected,
            total_views,
            articles_this_epoch: 0,
            views_this_epoch: 0,
            last_epoch_reset: timestamp,
        };
        
        // Add new stats
        df::add(&mut config.id, string::utf8(ARTICLE_STATS_KEY), new_stats);
        config.last_updated = timestamp;
        config.version = config.version + 1;
    }
    
    // === Status Functions ===
    
    /// Check if config is initialized
    public fun is_initialized(config: &ContentConfig): bool {
        config.is_initialized
    }
    
    /// Check if emergency paused
    public fun is_emergency_paused(config: &ContentConfig): bool {
        config.emergency_paused
    }
    
    /// Get config version
    public fun get_version(config: &ContentConfig): u64 {
        config.version
    }
    
    /// Get last updated timestamp
    public fun get_last_updated(config: &ContentConfig): u64 {
        config.last_updated
    }
    
    // === Validation Config Getters ===
    
    /// Get minimum validators required
    public fun get_min_validators_required(config: &ContentConfig): u64 {
        let validation_config = get_validation_config(config);
        validation_config.min_validators_required
    }
    
    /// Get validation timeout
    public fun get_validation_timeout_ms(config: &ContentConfig): u64 {
        let validation_config = get_validation_config(config);
        validation_config.validation_timeout_ms
    }
    
    /// Get minimum validator stake
    public fun get_min_validator_stake(config: &ContentConfig): u64 {
        let validation_config = get_validation_config(config);
        validation_config.min_validator_stake
    }
    
    /// Get validation reward rate
    public fun get_validation_reward_rate(config: &ContentConfig): u64 {
        let validation_config = get_validation_config(config);
        validation_config.validation_reward_rate
    }
    
    /// Get auto approve threshold
    public fun get_auto_approve_threshold(config: &ContentConfig): u64 {
        let validation_config = get_validation_config(config);
        validation_config.auto_approve_threshold
    }
    
    // === Statistics Getters ===
    
    /// Get article statistics summary
    public fun get_article_stats_summary(config: &ContentConfig): (u64, u64, u64, u64, u64) {
        let stats = get_article_stats(config);
        (
            stats.total_original_articles,
            stats.total_external_articles,
            stats.total_approved,
            stats.total_views,
            stats.articles_this_epoch
        )
    }
    
    /// Get project statistics summary
    public fun get_project_stats_summary(config: &ContentConfig): (u64, u64, u64, u64) {
        let stats = get_project_stats(config);
        (
            stats.total_projects,
            stats.total_approved,
            stats.total_views,
            stats.projects_this_epoch
        )
    }
    
    // === Project Statistics Management Functions ===
    
    /// Increment total projects
    public fun increment_total_projects(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.total_projects = stats.total_projects + 1;
    }
    
    /// Increment projects this epoch
    public fun increment_projects_this_epoch(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.projects_this_epoch = stats.projects_this_epoch + 1;
    }
    
    /// Update project field - approved projects
    public fun increment_approved_projects(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.approved_projects = stats.approved_projects + 1;
    }
    
    /// Update project field - active projects
    public fun increment_active_projects(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.active_projects = stats.active_projects + 1;
    }
    
    /// Decrement active projects
    public fun decrement_active_projects(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        if (stats.active_projects > 0) {
            stats.active_projects = stats.active_projects - 1;
        }
    }
    
    /// Update project field - completed projects
    public fun increment_completed_projects(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.completed_projects = stats.completed_projects + 1;
    }
    
    /// Update project field - total views
    public fun increment_project_views(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.total_views = stats.total_views + 1;
    }
    
    /// Update project field - total stars
    public fun increment_project_stars(config: &mut ContentConfig) {
        let stats = get_project_stats_mut(config);
        stats.total_stars = stats.total_stars + 1;
    }
    
    // === Article Statistics Management Functions ===
    
    /// Increment total original articles
    public fun increment_total_original_articles(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.total_original_articles = stats.total_original_articles + 1;
    }
    
    /// Increment total external articles
    public fun increment_total_external_articles(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.total_external_articles = stats.total_external_articles + 1;
    }
    
    /// Increment articles this epoch
    public fun increment_articles_this_epoch(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.articles_this_epoch = stats.articles_this_epoch + 1;
    }
    
    /// Increment total approved articles
    public fun increment_total_approved_articles(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.total_approved = stats.total_approved + 1;
    }
    
    /// Increment total rejected articles
    public fun increment_total_rejected_articles(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.total_rejected = stats.total_rejected + 1;
    }
    
    /// Increment article views
    public fun increment_article_views(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.total_views = stats.total_views + 1;
    }
    
    /// Increment views this epoch
    public fun increment_views_this_epoch(config: &mut ContentConfig) {
        let stats = get_article_stats_mut(config);
        stats.views_this_epoch = stats.views_this_epoch + 1;
    }
    
    /// Get config UID for dynamic field operations (internal use)
    public fun get_config_uid(config: &ContentConfig): &UID {
        &config.id
    }

    /// Get mutable config UID for dynamic field operations (internal use)
    public fun get_config_uid_mut(config: &mut ContentConfig): &mut UID {
        &mut config.id
    }

    /// Add dynamic field to config
    public fun add_dynamic_field<K: copy + drop + store, V: store>(
        config: &mut ContentConfig,
        key: K,
        value: V,
    ) {
        df::add(&mut config.id, key, value);
    }

    /// Check if dynamic field exists
    public fun exists_dynamic_field<K: copy + drop + store>(
        config: &ContentConfig,
        key: K,
    ): bool {
        df::exists_(&config.id, key)
    }

    /// Borrow dynamic field
    public fun borrow_dynamic_field<K: copy + drop + store, V: store>(
        config: &ContentConfig,
        key: K,
    ): &V {
        df::borrow(&config.id, key)
    }

    /// Borrow mutable dynamic field
    public fun borrow_mut_dynamic_field<K: copy + drop + store, V: store>(
        config: &mut ContentConfig,
        key: K,
    ): &mut V {
        df::borrow_mut(&mut config.id, key)
    }

    // === Test Functions ===
    
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
    
    #[test_only]
    public fun create_test_config(ctx: &mut TxContext): (ContentConfig, ConfigAdminCap) {
        let admin_cap = ConfigAdminCap {
            id: object::new(ctx),
        };
        
        let config = ContentConfig {
            id: object::new(ctx),
            version: 1,
            last_updated: 0,
            is_initialized: true,
            emergency_paused: false,
        };
        
        (config, admin_cap)
    }
}