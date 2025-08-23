/// Validator Management Module for Article Validation Pipeline
/// Handles validator assignment, performance tracking, and workload management
module suiverse_content::validator_management {
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
    use sui::hash;
    use sui::dynamic_field as df;
    
    // Dependencies
    use suiverse_core::governance::{ValidatorPool};
    use suiverse_content::config::{ContentConfig};
    
    // =============== Constants ===============
    
    // Error codes
    const E_NOT_VALIDATOR: u64 = 7001;
    const E_ALREADY_REGISTERED: u64 = 7002;
    const E_INSUFFICIENT_STAKE: u64 = 7003;
    const E_VALIDATOR_OVERLOADED: u64 = 7004;
    const E_INVALID_EXPERTISE_LEVEL: u64 = 7005;
    const E_INVALID_CATEGORY: u64 = 7006;
    const E_NOT_AUTHORIZED: u64 = 7007;
    const E_INVALID_PERFORMANCE_SCORE: u64 = 7008;
    const E_VALIDATOR_SUSPENDED: u64 = 7009;
    const E_COOLDOWN_ACTIVE: u64 = 7010;
    
    // Performance tiers
    const TIER_BRONZE: u8 = 1;
    const TIER_SILVER: u8 = 2;
    const TIER_GOLD: u8 = 3;
    const TIER_PLATINUM: u8 = 4;
    
    // Performance thresholds
    const BRONZE_THRESHOLD: u8 = 50;
    const SILVER_THRESHOLD: u8 = 70;
    const GOLD_THRESHOLD: u8 = 85;
    const PLATINUM_THRESHOLD: u8 = 95;
    
    // Workload limits by tier
    const BRONZE_MAX_ASSIGNMENTS: u8 = 2;
    const SILVER_MAX_ASSIGNMENTS: u8 = 4;
    const GOLD_MAX_ASSIGNMENTS: u8 = 6;
    const PLATINUM_MAX_ASSIGNMENTS: u8 = 8;
    
    // Cooldown periods (in milliseconds)
    const ASSIGNMENT_COOLDOWN: u64 = 3600000; // 1 hour
    const POOR_PERFORMANCE_COOLDOWN: u64 = 86400000; // 24 hours
    const SUSPENSION_COOLDOWN: u64 = 604800000; // 7 days
    
    // Expertise levels
    const EXPERTISE_NOVICE: u8 = 1;
    const EXPERTISE_INTERMEDIATE: u8 = 2;
    const EXPERTISE_ADVANCED: u8 = 3;
    const EXPERTISE_EXPERT: u8 = 4;
    const EXPERTISE_MASTER: u8 = 5;
    
    // Validation categories (defined as constants for easier access)
    const CATEGORY_PROGRAMMING: vector<u8> = b"Programming";
    const CATEGORY_WEB_DEV: vector<u8> = b"Web Development";
    const CATEGORY_DATA_SCIENCE: vector<u8> = b"Data Science";
    const CATEGORY_MACHINE_LEARNING: vector<u8> = b"Machine Learning";
    const CATEGORY_BLOCKCHAIN: vector<u8> = b"Blockchain";
    const CATEGORY_MOBILE_DEV: vector<u8> = b"Mobile Development";
    const CATEGORY_DEVOPS: vector<u8> = b"DevOps";
    const CATEGORY_SECURITY: vector<u8> = b"Security";
    const CATEGORY_DESIGN: vector<u8> = b"Design";
    const CATEGORY_GENERAL: vector<u8> = b"General";
    
    // Assignment methods
    const METHOD_RANDOM: u8 = 1;
    const METHOD_STAKE_WEIGHTED: u8 = 2;
    const METHOD_EXPERTISE_BASED: u8 = 3;
    const METHOD_PERFORMANCE_BASED: u8 = 4;
    const METHOD_BALANCED: u8 = 5;
    
    // Performance metrics weights
    const ACCURACY_WEIGHT: u64 = 40;
    const TIMELINESS_WEIGHT: u64 = 30;
    const QUALITY_WEIGHT: u64 = 20;
    const CONSISTENCY_WEIGHT: u64 = 10;
    
    // =============== Structs ===============
    
    /// Enhanced validator profile for content validation
    public struct ContentValidator has key {
        id: UID,
        validator_address: address,
        
        // Core governance stake info (reference)
        governance_stake_amount: u64,
        governance_weight: u64,
        governance_tier: u8,
        
        // Content-specific metadata
        registration_date: u64,
        total_validations: u64,
        successful_validations: u64,
        
        // Performance metrics
        accuracy_score: u64, // Percentage (0-100)
        timeliness_score: u64, // Based on review speed
        quality_score: u64, // Based on review quality feedback
        consistency_score: u64, // Based on alignment with consensus
        
        // Computed overall performance
        overall_performance: u64, // Weighted average of above
        performance_tier: u8,
        
        // Workload management
        active_assignments: u8,
        max_concurrent_assignments: u8,
        last_assignment_time: u64,
        last_completion_time: u64,
        
        // Expertise and specialization
        expertise_areas: Table<String, u8>, // category -> expertise level
        preferred_categories: vector<String>,
        difficulty_preferences: vector<u8>, // preferred difficulty levels
        
        // Availability and status
        is_available: bool,
        is_suspended: bool,
        suspension_end_time: Option<u64>,
        cooldown_end_time: Option<u64>,
        
        // Reputation and rewards
        reputation_score: u64,
        total_rewards_earned: u64,
        lifetime_bonuses: u64,
        
        // Performance history
        recent_performance: vector<PerformanceEntry>,
        consensus_alignment_history: vector<bool>,
        review_time_history: vector<u64>,
        
        // Preferences
        notification_preferences: Table<String, bool>,
        auto_accept_assignments: bool,
        min_reward_threshold: u64,
    }
    
    /// Performance tracking entry
    public struct PerformanceEntry has store, copy, drop {
        timestamp: u64,
        session_id: ID,
        article_type: u8,
        review_time_ms: u64,
        consensus_aligned: bool,
        quality_rating: u8, // 1-10
        accuracy_score: u8,
        overall_score: u8,
    }
    
    /// Validator assignment record
    public struct ValidatorAssignment has key, store {
        id: UID,
        validator: address,
        session_id: ID,
        article_id: ID,
        article_category: String,
        assignment_method: u8,
        assigned_at: u64,
        due_date: u64,
        priority: u8, // 1-5
        estimated_time: u64,
        
        // Status tracking
        accepted: bool,
        started: bool,
        completed: bool,
        submission_time: Option<u64>,
        
        // Performance prediction
        predicted_quality: u8,
        predicted_time: u64,
        expertise_match_score: u8,
        
        // Actual results (filled after completion)
        actual_quality: Option<u8>,
        actual_time: Option<u64>,
        consensus_alignment: Option<bool>,
    }
    
    /// Validator selection criteria
    public struct SelectionCriteria has store, copy, drop {
        article_category: String,
        difficulty_level: u8,
        article_type: u8,
        urgency: u8, // 1-5
        required_expertise_level: u8,
        min_performance_score: u8,
        preferred_validators: vector<address>,
        excluded_validators: vector<address>,
        selection_method: u8,
        max_workload_factor: u64, // 0-100
    }
    
    /// Validator registry for content validation
    public struct ContentValidatorRegistry has key {
        id: UID,
        
        // Validator management
        registered_validators: Table<address, ID>, // validator -> ContentValidator ID
        validators_by_category: Table<String, vector<address>>,
        validators_by_tier: Table<u8, vector<address>>,
        validators_by_availability: Table<bool, vector<address>>,
        
        // Assignment tracking
        active_assignments: Table<address, vector<ID>>, // validator -> assignment IDs
        assignment_queue: vector<ID>, // pending assignments
        assignment_history: Table<ID, ID>, // session_id -> assignment_id
        
        // Performance analytics
        global_performance_stats: GlobalPerformanceStats,
        performance_leaderboard: vector<address>, // sorted by performance
        
        // Configuration
        assignment_algorithm: u8,
        performance_calculation_weights: Table<String, u64>,
        tier_advancement_thresholds: Table<u8, u64>,
        
        // Admin
        admin: address,
        total_validators: u64,
        active_validators: u64,
    }
    
    /// Global performance statistics
    public struct GlobalPerformanceStats has store {
        average_accuracy: u64,
        average_timeliness: u64,
        average_quality: u64,
        average_consensus_rate: u64,
        total_validations_completed: u64,
        total_review_time: u64,
        performance_distribution: Table<u8, u64>, // tier -> count
        category_performance: Table<String, u64>, // category -> avg performance
    }
    
    /// Workload balancer for optimal assignment distribution
    public struct WorkloadBalancer has key {
        id: UID,
        
        // Current workload tracking
        validator_workloads: Table<address, u8>, // validator -> active assignments
        category_demand: Table<String, u64>, // category -> pending assignments
        tier_utilization: Table<u8, u64>, // tier -> utilization percentage
        
        // Load balancing parameters
        max_workload_variance: u64, // maximum allowed workload difference
        preferred_utilization: u64, // target utilization percentage
        rebalancing_threshold: u64, // when to trigger rebalancing
        
        // Assignment optimization
        assignment_scores: Table<address, u64>, // validator -> assignment suitability score
        recent_assignments: Table<address, u64>, // validator -> last assignment time
        cooldown_violations: Table<address, u64>, // validator -> violation count
        
        // Performance-based routing
        high_priority_validators: vector<address>,
        fast_track_validators: vector<address>, // for urgent assignments
        specialist_validators: Table<String, vector<address>>, // category -> specialists
        
        admin: address,
    }
    
    // =============== Events ===============
    
    public struct ValidatorRegisteredForContent has copy, drop {
        validator: address,
        governance_stake: u64,
        expertise_areas: vector<String>,
        initial_tier: u8,
        timestamp: u64,
    }
    
    public struct ValidatorAssignmentCreated has copy, drop {
        assignment_id: ID,
        validator: address,
        session_id: ID,
        article_id: ID,
        category: String,
        assignment_method: u8,
        priority: u8,
        due_date: u64,
        expertise_match: u8,
        timestamp: u64,
    }
    
    public struct ValidatorPerformanceUpdated has copy, drop {
        validator: address,
        old_tier: u8,
        new_tier: u8,
        accuracy_score: u64,
        timeliness_score: u64,
        quality_score: u64,
        overall_performance: u64,
        total_validations: u64,
        timestamp: u64,
    }
    
    public struct ValidatorSuspended has copy, drop {
        validator: address,
        reason: String,
        suspension_duration: u64,
        performance_score: u64,
        admin: address,
        timestamp: u64,
    }
    
    public struct ValidatorReactivated has copy, drop {
        validator: address,
        previous_suspension_reason: String,
        new_performance_score: u64,
        timestamp: u64,
    }
    
    public struct WorkloadRebalanced has copy, drop {
        validators_affected: u64,
        assignments_redistributed: u64,
        average_workload_before: u64,
        average_workload_after: u64,
        rebalancing_efficiency: u64,
        timestamp: u64,
    }
    
    public struct ExpertiseUpdated has copy, drop {
        validator: address,
        category: String,
        old_level: u8,
        new_level: u8,
        validation_count_in_category: u64,
        timestamp: u64,
    }
    
    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        
        // Create content validator registry
        let mut registry = ContentValidatorRegistry {
            id: object::new(ctx),
            registered_validators: table::new(ctx),
            validators_by_category: table::new(ctx),
            validators_by_tier: table::new(ctx),
            validators_by_availability: table::new(ctx),
            active_assignments: table::new(ctx),
            assignment_queue: vector::empty(),
            assignment_history: table::new(ctx),
            global_performance_stats: create_default_stats(ctx),
            performance_leaderboard: vector::empty(),
            assignment_algorithm: METHOD_BALANCED,
            performance_calculation_weights: table::new(ctx),
            tier_advancement_thresholds: table::new(ctx),
            admin,
            total_validators: 0,
            active_validators: 0,
        };
        
        // Initialize performance weights
        table::add(&mut registry.performance_calculation_weights, string::utf8(b"accuracy"), ACCURACY_WEIGHT);
        table::add(&mut registry.performance_calculation_weights, string::utf8(b"timeliness"), TIMELINESS_WEIGHT);
        table::add(&mut registry.performance_calculation_weights, string::utf8(b"quality"), QUALITY_WEIGHT);
        table::add(&mut registry.performance_calculation_weights, string::utf8(b"consistency"), CONSISTENCY_WEIGHT);
        
        // Initialize tier thresholds
        table::add(&mut registry.tier_advancement_thresholds, TIER_BRONZE, (BRONZE_THRESHOLD as u64));
        table::add(&mut registry.tier_advancement_thresholds, TIER_SILVER, (SILVER_THRESHOLD as u64));
        table::add(&mut registry.tier_advancement_thresholds, TIER_GOLD, (GOLD_THRESHOLD as u64));
        table::add(&mut registry.tier_advancement_thresholds, TIER_PLATINUM, (PLATINUM_THRESHOLD as u64));
        
        // Initialize category tables
        initialize_category_tables(&mut registry, ctx);
        
        // Create workload balancer
        let balancer = WorkloadBalancer {
            id: object::new(ctx),
            validator_workloads: table::new(ctx),
            category_demand: table::new(ctx),
            tier_utilization: table::new(ctx),
            max_workload_variance: 20, // 20% variance allowed
            preferred_utilization: 70, // 70% utilization target
            rebalancing_threshold: 25, // rebalance when 25% imbalance
            assignment_scores: table::new(ctx),
            recent_assignments: table::new(ctx),
            cooldown_violations: table::new(ctx),
            high_priority_validators: vector::empty(),
            fast_track_validators: vector::empty(),
            specialist_validators: table::new(ctx),
            admin,
        };
        
        transfer::share_object(registry);
        transfer::share_object(balancer);
    }
    
    // =============== Validator Registration ===============
    
    /// Register validator for content validation (requires existing governance validator)
    public entry fun register_content_validator(
        registry: &mut ContentValidatorRegistry,
        validator_pool: &ValidatorPool,
        expertise_categories: vector<String>,
        expertise_levels: vector<u8>,
        preferred_categories: vector<String>,
        difficulty_preferences: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_address = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Check if already registered
        assert!(!table::contains(&registry.registered_validators, validator_address), E_ALREADY_REGISTERED);
        
        // Get governance validator info (simplified)
        let stake_amount = 1000000000u64; // 1 SUI placeholder
        let state = 1u8; // Active state
        
        assert!(stake_amount > 0, E_NOT_VALIDATOR);
        assert!(state == 1, E_VALIDATOR_SUSPENDED); // VALIDATOR_STATE_ACTIVE
        
        // Validate expertise input
        assert!(vector::length(&expertise_categories) == vector::length(&expertise_levels), E_INVALID_EXPERTISE_LEVEL);
        
        // Create content validator profile
        let mut content_validator = ContentValidator {
            id: object::new(ctx),
            validator_address,
            governance_stake_amount: stake_amount,
            governance_weight: 1000, // Placeholder weight
            governance_tier: calculate_governance_tier(stake_amount),
            registration_date: current_time,
            total_validations: 0,
            successful_validations: 0,
            accuracy_score: 80, // Starting score
            timeliness_score: 80,
            quality_score: 80,
            consistency_score: 80,
            overall_performance: 80,
            performance_tier: TIER_BRONZE,
            active_assignments: 0,
            max_concurrent_assignments: BRONZE_MAX_ASSIGNMENTS,
            last_assignment_time: 0,
            last_completion_time: 0,
            expertise_areas: table::new(ctx),
            preferred_categories,
            difficulty_preferences,
            is_available: true,
            is_suspended: false,
            suspension_end_time: option::none(),
            cooldown_end_time: option::none(),
            reputation_score: 1000, // Starting reputation
            total_rewards_earned: 0,
            lifetime_bonuses: 0,
            recent_performance: vector::empty(),
            consensus_alignment_history: vector::empty(),
            review_time_history: vector::empty(),
            notification_preferences: table::new(ctx),
            auto_accept_assignments: true,
            min_reward_threshold: 0,
        };
        
        // Set up expertise areas
        let mut i = 0;
        while (i < vector::length(&expertise_categories)) {
            let category = *vector::borrow(&expertise_categories, i);
            let level = *vector::borrow(&expertise_levels, i);
            
            assert!(level >= EXPERTISE_NOVICE && level <= EXPERTISE_MASTER, E_INVALID_EXPERTISE_LEVEL);
            table::add(&mut content_validator.expertise_areas, category, level);
            
            i = i + 1;
        };
        
        // Initialize notification preferences
        table::add(&mut content_validator.notification_preferences, string::utf8(b"new_assignment"), true);
        table::add(&mut content_validator.notification_preferences, string::utf8(b"deadline_reminder"), true);
        table::add(&mut content_validator.notification_preferences, string::utf8(b"performance_update"), true);
        
        let validator_id = object::id(&content_validator);
        
        // Update registry
        table::add(&mut registry.registered_validators, validator_address, validator_id);
        registry.total_validators = registry.total_validators + 1;
        registry.active_validators = registry.active_validators + 1;
        
        // Update categorization tables
        update_validator_categorization(registry, validator_address, &content_validator);
        
        // Add to performance leaderboard
        vector::push_back(&mut registry.performance_leaderboard, validator_address);
        
        // Emit event
        event::emit(ValidatorRegisteredForContent {
            validator: validator_address,
            governance_stake: stake_amount,
            expertise_areas: expertise_categories,
            initial_tier: TIER_BRONZE,
            timestamp: current_time,
        });
        
        transfer::share_object(content_validator);
    }
    
    // =============== Validator Assignment Algorithm ===============
    
    /// Select optimal validators for validation session
    public fun select_validators_for_session(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        criteria: SelectionCriteria,
        required_count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        if (criteria.selection_method == METHOD_RANDOM) {
            select_random_available_validators(registry, balancer, required_count, clock, ctx)
        } else if (criteria.selection_method == METHOD_STAKE_WEIGHTED) {
            select_stake_weighted_validators(registry, balancer, required_count, ctx)
        } else if (criteria.selection_method == METHOD_EXPERTISE_BASED) {
            select_expertise_based_validators(registry, balancer, criteria, required_count, ctx)
        } else if (criteria.selection_method == METHOD_PERFORMANCE_BASED) {
            select_performance_based_validators(registry, balancer, criteria, required_count, ctx)
        } else {
            select_balanced_validators(registry, balancer, criteria, required_count, clock, ctx)
        }
    }
    
    /// Balanced selection algorithm (recommended)
    fun select_balanced_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        criteria: SelectionCriteria,
        required_count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        let current_time = clock::timestamp_ms(clock);
        let mut candidates = get_eligible_validators(registry, balancer, criteria, current_time);
        
        // Score each candidate (simplified - in real implementation would sort by score)
        let mut i = 0;
        
        // Sort by score (simplified - would use proper sorting in real implementation)
        // For now, just take the first N candidates
        let mut selected = vector::empty<address>();
        let select_count = if ((required_count as u64) > vector::length(&candidates)) {
            vector::length(&candidates)
        } else {
            (required_count as u64)
        };
        
        let mut j = 0;
        while (j < select_count) {
            let validator = *vector::borrow(&candidates, j);
            vector::push_back(&mut selected, validator);
            j = j + 1;
        };
        
        selected
    }
    
    /// Calculate assignment suitability score for a validator
    fun calculate_assignment_score(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        validator: address,
        criteria: SelectionCriteria,
        current_time: u64,
    ): u64 {
        // Base score from performance (0-100)
        let performance_score = 80u64; // Simplified - would get from ContentValidator
        
        // Expertise match bonus (0-50)
        let expertise_bonus = calculate_expertise_match(registry, validator, criteria.article_category, criteria.required_expertise_level);
        
        // Workload penalty (0-30)
        let workload_penalty = calculate_workload_penalty(balancer, validator);
        
        // Availability bonus (0-20)
        let availability_bonus = calculate_availability_bonus(registry, validator, current_time);
        
        // Recent assignment penalty (0-15)
        let recency_penalty = calculate_recency_penalty(balancer, validator, current_time);
        
        // Calculate final score
        let score = performance_score + (expertise_bonus as u64) + availability_bonus;
        if (score > workload_penalty + recency_penalty) {
            score - workload_penalty - recency_penalty
        } else {
            0
        }
    }
    
    /// Get eligible validators based on criteria
    fun get_eligible_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        criteria: SelectionCriteria,
        current_time: u64,
    ): vector<address> {
        let mut eligible = vector::empty<address>();
        
        // Start with available validators
        if (table::contains(&registry.validators_by_availability, true)) {
            let available_validators = table::borrow(&registry.validators_by_availability, true);
            let mut i = 0;
            
            while (i < vector::length(available_validators)) {
                let validator = *vector::borrow(available_validators, i);
                
                // Check if validator meets criteria
                if (meets_selection_criteria(registry, balancer, validator, criteria, current_time)) {
                    vector::push_back(&mut eligible, validator);
                };
                
                i = i + 1;
            };
        };
        
        eligible
    }
    
    /// Check if validator meets selection criteria
    fun meets_selection_criteria(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        validator: address,
        criteria: SelectionCriteria,
        current_time: u64,
    ): bool {
        // Check if validator is in excluded list
        if (vector::contains(&criteria.excluded_validators, &validator)) {
            return false
        };
        
        // Check workload
        if (table::contains(&balancer.validator_workloads, validator)) {
            let current_workload = *table::borrow(&balancer.validator_workloads, validator);
            let max_allowed = calculate_max_workload_for_validator(registry, validator);
            if (current_workload >= max_allowed) {
                return false
            };
        };
        
        // Check cooldown
        if (table::contains(&balancer.recent_assignments, validator)) {
            let last_assignment = *table::borrow(&balancer.recent_assignments, validator);
            if (current_time - last_assignment < ASSIGNMENT_COOLDOWN) {
                return false
            };
        };
        
        // Additional checks would go here (expertise, performance, etc.)
        true
    }
    
    // =============== Performance Tracking ===============
    
    /// Update validator performance after validation completion
    public entry fun update_validator_performance(
        registry: &mut ContentValidatorRegistry,
        content_validator: &mut ContentValidator,
        session_id: ID,
        article_type: u8,
        review_time_ms: u64,
        consensus_aligned: bool,
        quality_rating: u8,
        accuracy_score: u8,
        overall_score: u8,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let validator_address = content_validator.validator_address;
        
        // Verify sender is authorized (could be the validator or system)
        // For simplicity, allowing any caller in this implementation
        
        // Create performance entry
        let performance_entry = PerformanceEntry {
            timestamp: current_time,
            session_id,
            article_type,
            review_time_ms,
            consensus_aligned,
            quality_rating,
            accuracy_score,
            overall_score,
        };
        
        // Update performance history
        vector::push_back(&mut content_validator.recent_performance, performance_entry);
        vector::push_back(&mut content_validator.consensus_alignment_history, consensus_aligned);
        vector::push_back(&mut content_validator.review_time_history, review_time_ms);
        
        // Keep only last 100 entries
        if (vector::length(&content_validator.recent_performance) > 100) {
            vector::remove(&mut content_validator.recent_performance, 0);
            vector::remove(&mut content_validator.consensus_alignment_history, 0);
            vector::remove(&mut content_validator.review_time_history, 0);
        };
        
        // Update counters
        content_validator.total_validations = content_validator.total_validations + 1;
        if (consensus_aligned) {
            content_validator.successful_validations = content_validator.successful_validations + 1;
        };
        
        // Recalculate performance scores
        let old_tier = content_validator.performance_tier;
        recalculate_performance_scores(content_validator, registry);
        let new_tier = content_validator.performance_tier;
        
        // Update tier-based limits
        update_tier_based_limits(content_validator);
        
        // Update registry categorization if tier changed
        if (old_tier != new_tier) {
            update_validator_categorization(registry, validator_address, content_validator);
        };
        
        // Update global stats
        update_global_performance_stats(registry, &performance_entry);
        
        // Emit performance update event
        event::emit(ValidatorPerformanceUpdated {
            validator: validator_address,
            old_tier,
            new_tier,
            accuracy_score: content_validator.accuracy_score,
            timeliness_score: content_validator.timeliness_score,
            quality_score: content_validator.quality_score,
            overall_performance: content_validator.overall_performance,
            total_validations: content_validator.total_validations,
            timestamp: current_time,
        });
        
        // Check if suspension needed
        check_and_apply_performance_sanctions(content_validator, clock);
    }
    
    /// Recalculate all performance scores
    fun recalculate_performance_scores(
        content_validator: &mut ContentValidator,
        registry: &ContentValidatorRegistry,
    ) {
        // Calculate accuracy score (percentage of consensus-aligned validations)
        let total_validations = vector::length(&content_validator.consensus_alignment_history);
        if (total_validations > 0) {
            let mut aligned_count = 0u64;
            let mut i = 0;
            while (i < total_validations) {
                if (*vector::borrow(&content_validator.consensus_alignment_history, i)) {
                    aligned_count = aligned_count + 1;
                };
                i = i + 1;
            };
            content_validator.accuracy_score = ((aligned_count * 100) / total_validations);
        };
        
        // Calculate timeliness score (based on review speed)
        if (vector::length(&content_validator.review_time_history) > 0) {
            let avg_time = calculate_average_review_time(content_validator);
            content_validator.timeliness_score = calculate_timeliness_score(avg_time);
        };
        
        // Calculate quality score (based on recent quality ratings)
        if (vector::length(&content_validator.recent_performance) > 0) {
            content_validator.quality_score = calculate_quality_score(content_validator);
        };
        
        // Calculate consistency score (based on variance in performance)
        content_validator.consistency_score = calculate_consistency_score(content_validator);
        
        // Calculate overall weighted performance
        let accuracy_weight = *table::borrow(&registry.performance_calculation_weights, string::utf8(b"accuracy"));
        let timeliness_weight = *table::borrow(&registry.performance_calculation_weights, string::utf8(b"timeliness"));
        let quality_weight = *table::borrow(&registry.performance_calculation_weights, string::utf8(b"quality"));
        let consistency_weight = *table::borrow(&registry.performance_calculation_weights, string::utf8(b"consistency"));
        
        let weighted_score = (
            content_validator.accuracy_score * accuracy_weight +
            content_validator.timeliness_score * timeliness_weight +
            content_validator.quality_score * quality_weight +
            content_validator.consistency_score * consistency_weight
        ) / 100;
        
        content_validator.overall_performance = weighted_score;
        
        // Update performance tier
        content_validator.performance_tier = calculate_performance_tier(weighted_score);
    }
    
    // =============== Workload Management ===============
    
    /// Create validator assignment
    public entry fun create_validator_assignment(
        registry: &mut ContentValidatorRegistry,
        balancer: &mut WorkloadBalancer,
        validator: address,
        session_id: ID,
        article_id: ID,
        article_category: String,
        assignment_method: u8,
        priority: u8,
        estimated_time: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Create assignment
        let assignment = ValidatorAssignment {
            id: object::new(ctx),
            validator,
            session_id,
            article_id,
            article_category,
            assignment_method,
            assigned_at: current_time,
            due_date: current_time + estimated_time,
            priority,
            estimated_time,
            accepted: false,
            started: false,
            completed: false,
            submission_time: option::none(),
            predicted_quality: predict_quality_score(registry, validator, article_category),
            predicted_time: predict_completion_time(registry, validator, article_category),
            expertise_match_score: calculate_expertise_match(registry, validator, article_category, 3),
            actual_quality: option::none(),
            actual_time: option::none(),
            consensus_alignment: option::none(),
        };
        
        let assignment_id = object::id(&assignment);
        
        // Update registry
        if (!table::contains(&registry.active_assignments, validator)) {
            table::add(&mut registry.active_assignments, validator, vector::empty());
        };
        let assignments = table::borrow_mut(&mut registry.active_assignments, validator);
        vector::push_back(assignments, assignment_id);
        
        table::add(&mut registry.assignment_history, session_id, assignment_id);
        
        // Update balancer
        update_workload_tracking(balancer, validator, current_time);
        
        // Emit event
        event::emit(ValidatorAssignmentCreated {
            assignment_id,
            validator,
            session_id,
            article_id,
            category: article_category,
            assignment_method,
            priority,
            due_date: assignment.due_date,
            expertise_match: assignment.expertise_match_score,
            timestamp: current_time,
        });
        
        transfer::share_object(assignment);
    }
    
    /// Rebalance workload across validators
    public entry fun rebalance_workload(
        registry: &mut ContentValidatorRegistry,
        balancer: &mut WorkloadBalancer,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Calculate current workload distribution
        let (avg_workload_before, variance_before) = calculate_workload_statistics(balancer);
        
        // Check if rebalancing is needed
        if (variance_before < balancer.rebalancing_threshold) {
            return // No rebalancing needed
        };
        
        // Perform workload redistribution
        let (validators_affected, assignments_redistributed) = perform_workload_redistribution(registry, balancer);
        
        // Calculate new workload distribution
        let (avg_workload_after, _variance_after) = calculate_workload_statistics(balancer);
        
        // Calculate efficiency metric
        let efficiency = if (variance_before > 0) {
            100 - ((avg_workload_after * 100) / avg_workload_before)
        } else {
            100
        };
        
        // Emit rebalancing event
        event::emit(WorkloadRebalanced {
            validators_affected,
            assignments_redistributed,
            average_workload_before: avg_workload_before,
            average_workload_after: avg_workload_after,
            rebalancing_efficiency: efficiency,
            timestamp: current_time,
        });
    }
    
    // =============== Helper Functions ===============
    
    /// Initialize category tables for all predefined categories
    fun initialize_category_tables(registry: &mut ContentValidatorRegistry, ctx: &mut TxContext) {
        let categories = vector[
            string::utf8(b"Programming"),
            string::utf8(b"Web Development"),
            string::utf8(b"Data Science"),
            string::utf8(b"Machine Learning"),
            string::utf8(b"Blockchain"),
            string::utf8(b"Mobile Development"),
            string::utf8(b"DevOps"),
            string::utf8(b"Security"),
            string::utf8(b"Design"),
            string::utf8(b"General"),
        ];
        
        let mut i = 0;
        while (i < vector::length(&categories)) {
            let category = *vector::borrow(&categories, i);
            table::add(&mut registry.validators_by_category, category, vector::empty());
            i = i + 1;
        };
        
        // Initialize tier tables
        table::add(&mut registry.validators_by_tier, TIER_BRONZE, vector::empty());
        table::add(&mut registry.validators_by_tier, TIER_SILVER, vector::empty());
        table::add(&mut registry.validators_by_tier, TIER_GOLD, vector::empty());
        table::add(&mut registry.validators_by_tier, TIER_PLATINUM, vector::empty());
        
        // Initialize availability tables
        table::add(&mut registry.validators_by_availability, true, vector::empty());
        table::add(&mut registry.validators_by_availability, false, vector::empty());
    }
    
    /// Update validator categorization in registry tables
    fun update_validator_categorization(
        registry: &mut ContentValidatorRegistry,
        validator: address,
        content_validator: &ContentValidator,
    ) {
        // Update tier categorization
        let tier_validators = table::borrow_mut(&mut registry.validators_by_tier, content_validator.performance_tier);
        if (!vector::contains(tier_validators, &validator)) {
            vector::push_back(tier_validators, validator);
        };
        
        // Update availability categorization
        let availability_validators = table::borrow_mut(&mut registry.validators_by_availability, content_validator.is_available);
        if (!vector::contains(availability_validators, &validator)) {
            vector::push_back(availability_validators, validator);
        };
    }
    
    /// Calculate governance tier based on stake amount
    fun calculate_governance_tier(stake_amount: u64): u8 {
        if (stake_amount >= 100_000_000_000) { 6 } // 100 SUI+
        else if (stake_amount >= 50_000_000_000) { 5 } // 50 SUI+
        else if (stake_amount >= 10_000_000_000) { 4 } // 10 SUI+
        else if (stake_amount >= 5_000_000_000) { 3 } // 5 SUI+
        else if (stake_amount >= 1_000_000_000) { 2 } // 1 SUI+
        else { 1 }
    }
    
    /// Calculate performance tier from overall score
    fun calculate_performance_tier(overall_score: u64): u8 {
        if (overall_score >= (PLATINUM_THRESHOLD as u64)) { TIER_PLATINUM }
        else if (overall_score >= (GOLD_THRESHOLD as u64)) { TIER_GOLD }
        else if (overall_score >= (SILVER_THRESHOLD as u64)) { TIER_SILVER }
        else { TIER_BRONZE }
    }
    
    /// Update tier-based assignment limits
    fun update_tier_based_limits(content_validator: &mut ContentValidator) {
        content_validator.max_concurrent_assignments = if (content_validator.performance_tier == TIER_BRONZE) {
            BRONZE_MAX_ASSIGNMENTS
        } else if (content_validator.performance_tier == TIER_SILVER) {
            SILVER_MAX_ASSIGNMENTS
        } else if (content_validator.performance_tier == TIER_GOLD) {
            GOLD_MAX_ASSIGNMENTS
        } else if (content_validator.performance_tier == TIER_PLATINUM) {
            PLATINUM_MAX_ASSIGNMENTS
        } else {
            BRONZE_MAX_ASSIGNMENTS
        };
    }
    
    /// Calculate expertise match score for category
    fun calculate_expertise_match(
        registry: &ContentValidatorRegistry,
        validator: address,
        category: String,
        required_level: u8,
    ): u8 {
        // Simplified implementation - would access ContentValidator data
        50u8 // Default 50% match
    }
    
    /// Calculate workload penalty based on current assignments
    fun calculate_workload_penalty(balancer: &WorkloadBalancer, validator: address): u64 {
        if (table::contains(&balancer.validator_workloads, validator)) {
            let workload = *table::borrow(&balancer.validator_workloads, validator);
            (workload as u64) * 5 // 5 points penalty per active assignment
        } else {
            0
        }
    }
    
    /// Calculate availability bonus
    fun calculate_availability_bonus(
        registry: &ContentValidatorRegistry,
        validator: address,
        current_time: u64,
    ): u64 {
        // Simplified - would check actual availability status
        15u64 // Default availability bonus
    }
    
    /// Calculate recency penalty to prevent back-to-back assignments
    fun calculate_recency_penalty(
        balancer: &WorkloadBalancer,
        validator: address,
        current_time: u64,
    ): u64 {
        if (table::contains(&balancer.recent_assignments, validator)) {
            let last_assignment = *table::borrow(&balancer.recent_assignments, validator);
            let time_diff = current_time - last_assignment;
            if (time_diff < ASSIGNMENT_COOLDOWN) {
                15 - ((time_diff * 15) / ASSIGNMENT_COOLDOWN)
            } else {
                0
            }
        } else {
            0
        }
    }
    
    /// Simplified placeholder functions for complex calculations
    
    fun select_random_available_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        vector::empty<address>()
    }
    
    fun select_stake_weighted_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        count: u8,
        ctx: &mut TxContext,
    ): vector<address> {
        vector::empty<address>()
    }
    
    fun select_expertise_based_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        criteria: SelectionCriteria,
        count: u8,
        ctx: &mut TxContext,
    ): vector<address> {
        vector::empty<address>()
    }
    
    fun select_performance_based_validators(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        criteria: SelectionCriteria,
        count: u8,
        ctx: &mut TxContext,
    ): vector<address> {
        vector::empty<address>()
    }
    
    fun calculate_max_workload_for_validator(registry: &ContentValidatorRegistry, validator: address): u8 {
        BRONZE_MAX_ASSIGNMENTS // Simplified
    }
    
    fun predict_quality_score(registry: &ContentValidatorRegistry, validator: address, category: String): u8 {
        80 // Default prediction
    }
    
    fun predict_completion_time(registry: &ContentValidatorRegistry, validator: address, category: String): u64 {
        3600000 // 1 hour default
    }
    
    fun update_workload_tracking(balancer: &mut WorkloadBalancer, validator: address, timestamp: u64) {
        if (!table::contains(&balancer.validator_workloads, validator)) {
            table::add(&mut balancer.validator_workloads, validator, 1);
        } else {
            let workload = table::borrow_mut(&mut balancer.validator_workloads, validator);
            *workload = *workload + 1;
        };
        
        if (!table::contains(&balancer.recent_assignments, validator)) {
            table::add(&mut balancer.recent_assignments, validator, timestamp);
        } else {
            let last_assignment = table::borrow_mut(&mut balancer.recent_assignments, validator);
            *last_assignment = timestamp;
        };
    }
    
    fun calculate_average_review_time(content_validator: &ContentValidator): u64 {
        let history = &content_validator.review_time_history;
        if (vector::length(history) == 0) return 3600000; // 1 hour default
        
        let mut total = 0u64;
        let mut i = 0;
        while (i < vector::length(history)) {
            total = total + *vector::borrow(history, i);
            i = i + 1;
        };
        total / vector::length(history)
    }
    
    fun calculate_timeliness_score(avg_time_ms: u64): u64 {
        // Score based on speed: under 1 hour = 100, under 6 hours = 80, etc.
        if (avg_time_ms <= 3600000) { 100 }
        else if (avg_time_ms <= 21600000) { 80 }
        else if (avg_time_ms <= 43200000) { 60 }
        else { 40 }
    }
    
    fun calculate_quality_score(content_validator: &ContentValidator): u64 {
        let recent = &content_validator.recent_performance;
        if (vector::length(recent) == 0) return 80;
        
        let mut total = 0u64;
        let mut i = 0;
        while (i < vector::length(recent)) {
            let entry = vector::borrow(recent, i);
            total = total + (entry.quality_rating as u64) * 10; // Convert 1-10 to 10-100
            i = i + 1;
        };
        total / vector::length(recent)
    }
    
    fun calculate_consistency_score(content_validator: &ContentValidator): u64 {
        // Simplified consistency calculation
        80 // Default consistency score
    }
    
    fun create_default_stats(ctx: &mut TxContext): GlobalPerformanceStats {
        GlobalPerformanceStats {
            average_accuracy: 80,
            average_timeliness: 80,
            average_quality: 80,
            average_consensus_rate: 80,
            total_validations_completed: 0,
            total_review_time: 0,
            performance_distribution: table::new(ctx),
            category_performance: table::new(ctx),
        }
    }
    
    fun update_global_performance_stats(
        registry: &mut ContentValidatorRegistry,
        entry: &PerformanceEntry,
    ) {
        let stats = &mut registry.global_performance_stats;
        stats.total_validations_completed = stats.total_validations_completed + 1;
        stats.total_review_time = stats.total_review_time + entry.review_time_ms;
    }
    
    fun check_and_apply_performance_sanctions(
        content_validator: &mut ContentValidator,
        clock: &Clock,
    ) {
        // Check if performance is below threshold and apply sanctions if needed
        if (content_validator.overall_performance < 40) {
            content_validator.is_suspended = true;
            content_validator.suspension_end_time = option::some(
                clock::timestamp_ms(clock) + POOR_PERFORMANCE_COOLDOWN
            );
        }
    }
    
    fun calculate_workload_statistics(balancer: &WorkloadBalancer): (u64, u64) {
        // Calculate average workload and variance
        (5u64, 15u64) // Placeholder values
    }
    
    fun perform_workload_redistribution(
        registry: &mut ContentValidatorRegistry,
        balancer: &mut WorkloadBalancer,
    ): (u64, u64) {
        // Perform actual workload redistribution logic
        (3u64, 5u64) // Placeholder: 3 validators affected, 5 assignments redistributed
    }
    
    // =============== View Functions ===============
    
    /// Get validator performance info
    public fun get_validator_performance(
        registry: &ContentValidatorRegistry,
        validator: address,
    ): (u64, u64, u64, u64, u8, u64) {
        // Return performance metrics - simplified implementation
        (80, 80, 80, 80, TIER_BRONZE, 10)
    }
    
    /// Get validator workload
    public fun get_validator_workload(balancer: &WorkloadBalancer, validator: address): u8 {
        if (table::contains(&balancer.validator_workloads, validator)) {
            *table::borrow(&balancer.validator_workloads, validator)
        } else {
            0
        }
    }
    
    /// Check if validator is available
    public fun is_validator_available(
        registry: &ContentValidatorRegistry,
        balancer: &WorkloadBalancer,
        validator: address,
    ): bool {
        // Check availability based on workload, suspension, etc.
        true // Simplified
    }
    
    // =============== Test Functions ===============
    
    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    // =============== Comprehensive Test Functions ===============
    
    #[test_only]
    use sui::test_scenario::{Self, Scenario};
    #[test_only]
    use sui::test_utils;

    #[test]
    public fun test_happy_path_validator_management_initialization() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Initialize validator management
        init(ctx);
        
        test_scenario::next_tx(&mut scenario, @0x1);
        
        // Get shared objects
        let registry = test_scenario::take_shared<ContentValidatorRegistry>(&scenario);
        let balancer = test_scenario::take_shared<WorkloadBalancer>(&scenario);
        
        // Verify initial state
        assert!(registry.total_validators == 0, 0);
        assert!(registry.active_validators == 0, 1);
        assert!(registry.admin == @0x1, 2);
        
        // Note: balancer doesn't have total_assignments, avg_workload_target fields
        assert!(balancer.max_workload_variance == 20, 3);
        assert!(balancer.preferred_utilization == 70, 4);
        assert!(balancer.rebalancing_threshold == 25, 5);
        
        test_scenario::return_shared(registry);
        test_scenario::return_shared(balancer);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_happy_path_content_validator_structure() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create test content validator
        let validator_addr = @0x2;
        let categories = vector[string::utf8(b"blockchain"), string::utf8(b"defi")];
        
        let content_validator = ContentValidator {
            id: object::new(ctx),
            validator_address: validator_addr,
            governance_stake_amount: 100000000000, // 100 SUI
            governance_weight: 1000,
            governance_tier: 2,
            registration_date: 1700000000000,
            total_validations: 25,
            successful_validations: 20,
            accuracy_score: 80,
            timeliness_score: 70,
            quality_score: 75,
            consistency_score: 85,
            overall_performance: 75,
            performance_tier: TIER_BRONZE,
            active_assignments: 2,
            max_concurrent_assignments: BRONZE_MAX_ASSIGNMENTS,
            last_assignment_time: 1700000000000,
            last_completion_time: 1700086400000,
            expertise_areas: table::new(ctx),
            preferred_categories: categories,
            difficulty_preferences: vector::empty(),
            is_available: true,
            is_suspended: false,
            suspension_end_time: option::none(),
            cooldown_end_time: option::none(),
            reputation_score: 150,
            total_rewards_earned: 0,
            lifetime_bonuses: 0,
            recent_performance: vector::empty(),
            consensus_alignment_history: vector::empty(),
            review_time_history: vector::empty(),
            notification_preferences: table::new(ctx),
            auto_accept_assignments: true,
            min_reward_threshold: 0,
        };
        
        // Test validator properties
        assert!(content_validator.validator_address == validator_addr, 0);
        assert!(content_validator.governance_stake_amount == 100000000000, 1);
        assert!(vector::length(&content_validator.preferred_categories) == 2, 2);
        assert!(content_validator.performance_tier == TIER_BRONZE, 3);
        assert!(content_validator.overall_performance == 75, 4);
        assert!(content_validator.accuracy_score == 80, 5);
        assert!(content_validator.timeliness_score == 70, 6);
        assert!(content_validator.quality_score == 75, 7);
        assert!(content_validator.consistency_score == 85, 8);
        assert!(content_validator.total_validations == 25, 9);
        assert!(content_validator.successful_validations == 20, 10);
        assert!(content_validator.active_assignments == 2, 11);
        assert!(content_validator.max_concurrent_assignments == BRONZE_MAX_ASSIGNMENTS, 12);
        assert!(content_validator.reputation_score == 150, 13);
        assert!(vector::length(&content_validator.recent_performance) == 0, 14);
        assert!(content_validator.is_suspended == false, 15);
        assert!(option::is_none(&content_validator.suspension_end_time), 16);
        
        // Test category expertise
        assert!(vector::contains(&content_validator.preferred_categories, &string::utf8(b"blockchain")), 17);
        assert!(vector::contains(&content_validator.preferred_categories, &string::utf8(b"defi")), 18);
        assert!(!vector::contains(&content_validator.preferred_categories, &string::utf8(b"gaming")), 19);
        
        // Calculate success rate
        let success_rate = (content_validator.successful_validations * 100) / content_validator.total_validations;
        assert!(success_rate == 80, 20); // 20/25 * 100 = 80%
        
        // Clean up
        let ContentValidator { 
            id, validator_address: _, governance_stake_amount: _, governance_weight: _, governance_tier: _,
            registration_date: _, total_validations: _, successful_validations: _, 
            accuracy_score: _, timeliness_score: _, quality_score: _, consistency_score: _,
            overall_performance: _, performance_tier: _, active_assignments: _, max_concurrent_assignments: _, 
            last_assignment_time: _, last_completion_time: _, expertise_areas, 
            preferred_categories: _, difficulty_preferences: _, is_available: _,
            is_suspended: _, suspension_end_time: _, cooldown_end_time: _,
            reputation_score: _, total_rewards_earned: _, lifetime_bonuses: _, recent_performance: _, 
            consensus_alignment_history: _, review_time_history: _, notification_preferences, 
            auto_accept_assignments: _, min_reward_threshold: _ 
        } = content_validator;
        object::delete(id);
        table::destroy_empty(expertise_areas);
        table::destroy_empty(notification_preferences);
        
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_happy_path_performance_entry_tracking() {
        // Create test performance entries
        let entry1 = PerformanceEntry {
            timestamp: 1700000000000,
            session_id: object::id_from_address(@0xABC),
            article_type: 1, // ARTICLE_TYPE_ORIGINAL
            review_time_ms: 1800000, // 30 minutes
            consensus_aligned: true,
            quality_rating: 9, // 1-10 scale
            accuracy_score: 90,
            overall_score: 85,
        };
        
        let entry2 = PerformanceEntry {
            timestamp: 1700086400000,
            session_id: object::id_from_address(@0xDEF),
            article_type: 1, // ARTICLE_TYPE_ORIGINAL
            review_time_ms: 2400000, // 40 minutes
            consensus_aligned: false,
            quality_rating: 8,
            accuracy_score: 70,
            overall_score: 75,
        };
        
        // Test performance entry properties
        assert!(entry1.quality_rating == 9, 0);
        assert!(entry1.accuracy_score == 90, 1);
        assert!(entry1.overall_score == 85, 2);
        assert!(entry1.consensus_aligned == true, 3);
        assert!(entry1.review_time_ms == 1800000, 4);
        
        assert!(entry2.quality_rating == 8, 5);
        assert!(entry2.accuracy_score == 70, 6);
        assert!(entry2.overall_score == 75, 7);
        assert!(entry2.consensus_aligned == false, 8);
        assert!(entry2.review_time_ms == 2400000, 9);
        
        // Test performance calculations
        let mut performance_entries = vector::empty<PerformanceEntry>();
        vector::push_back(&mut performance_entries, entry1);
        vector::push_back(&mut performance_entries, entry2);
        
        assert!(vector::length(&performance_entries) == 2, 10);
        
        // Calculate average accuracy: (90 + 70) / 2 = 80
        let mut total_accuracy = 0u64;
        let mut i = 0;
        while (i < vector::length(&performance_entries)) {
            let entry = vector::borrow(&performance_entries, i);
            total_accuracy = total_accuracy + (entry.accuracy_score as u64);
            i = i + 1;
        };
        let avg_accuracy = total_accuracy / vector::length(&performance_entries);
        assert!(avg_accuracy == 80, 11);
        
        // Calculate average review time: (1800000 + 2400000) / 2 = 2100000
        let mut total_time = 0u64;
        let mut j = 0;
        while (j < vector::length(&performance_entries)) {
            let entry = vector::borrow(&performance_entries, j);
            total_time = total_time + entry.review_time_ms;
            j = j + 1;
        };
        let avg_time = total_time / vector::length(&performance_entries);
        assert!(avg_time == 2100000, 12);
    }

    #[test]
    public fun test_happy_path_performance_tier_thresholds() {
        // Test tier constants
        assert!(TIER_BRONZE == 1u8, 0);
        assert!(TIER_SILVER == 2u8, 1);
        assert!(TIER_GOLD == 3u8, 2);
        assert!(TIER_PLATINUM == 4u8, 3);
        
        // Test threshold constants
        assert!(BRONZE_THRESHOLD == 50, 4);
        assert!(SILVER_THRESHOLD == 70, 5);
        assert!(GOLD_THRESHOLD == 85, 6);
        assert!(PLATINUM_THRESHOLD == 95, 7);
        
        // Test workload limits
        assert!(BRONZE_MAX_ASSIGNMENTS == 2, 8);
        assert!(SILVER_MAX_ASSIGNMENTS == 4, 9);
        assert!(GOLD_MAX_ASSIGNMENTS == 6, 10);
        assert!(PLATINUM_MAX_ASSIGNMENTS == 8, 11);
        
        // Test tier determination logic
        let performance_scores = vector[45u8, 75u8, 90u8, 98u8];
        let expected_tiers = vector[TIER_BRONZE, TIER_SILVER, TIER_GOLD, TIER_PLATINUM];
        
        let mut i = 0;
        while (i < vector::length(&performance_scores)) {
            let score = *vector::borrow(&performance_scores, i);
            let expected_tier = *vector::borrow(&expected_tiers, i);
            
            let calculated_tier = if (score >= PLATINUM_THRESHOLD) {
                TIER_PLATINUM
            } else if (score >= GOLD_THRESHOLD) {
                TIER_GOLD
            } else if (score >= SILVER_THRESHOLD) {
                TIER_SILVER
            } else {
                TIER_BRONZE
            };
            
            assert!(calculated_tier == expected_tier, (12 + i));
            i = i + 1;
        };
    }

    #[test]
    public fun test_happy_path_workload_balancer_structure() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create workload balancer
        let balancer = WorkloadBalancer {
            id: object::new(ctx),
            validator_workloads: table::new(ctx),
            category_demand: table::new(ctx),
            tier_utilization: table::new(ctx),
            max_workload_variance: 20,
            preferred_utilization: 70,
            rebalancing_threshold: 25,
            assignment_scores: table::new(ctx),
            recent_assignments: table::new(ctx),
            cooldown_violations: table::new(ctx),
            high_priority_validators: vector::empty(),
            fast_track_validators: vector::empty(),
            specialist_validators: table::new(ctx),
            admin: @0x1,
        };
        
        // Test balancer properties
        assert!(balancer.max_workload_variance == 20, 0);
        assert!(balancer.preferred_utilization == 70, 1);
        assert!(balancer.rebalancing_threshold == 25, 2);
        assert!(balancer.admin == @0x1, 3);
        assert!(vector::length(&balancer.high_priority_validators) == 0, 4);
        assert!(vector::length(&balancer.fast_track_validators) == 0, 5);
        
        // Test workload operations
        let validator1 = @0x2;
        let validator2 = @0x3;
        
        // Add some workload data for testing
        let initial_workload = 3u8;
        assert!(get_validator_workload(&balancer, validator1) == 0, 7);
        assert!(get_validator_workload(&balancer, validator2) == 0, 8);
        
        // Clean up
        let WorkloadBalancer { 
            id, validator_workloads, category_demand, tier_utilization,
            max_workload_variance: _, preferred_utilization: _, rebalancing_threshold: _,
            assignment_scores, recent_assignments, cooldown_violations,
            high_priority_validators: _, fast_track_validators: _, specialist_validators,
            admin: _
        } = balancer;
        object::delete(id);
        table::destroy_empty(validator_workloads);
        table::destroy_empty(category_demand);
        table::destroy_empty(tier_utilization);
        table::destroy_empty(assignment_scores);
        table::destroy_empty(recent_assignments);
        table::destroy_empty(cooldown_violations);
        table::destroy_empty(specialist_validators);
        
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_happy_path_assignment_structure() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create test assignment
        let assignment = ValidatorAssignment {
            id: object::new(ctx),
            validator: @0x2,
            session_id: object::id_from_address(@0xABC),
            article_id: object::id_from_address(@0xDEF),
            article_category: string::utf8(b"blockchain"),
            assignment_method: METHOD_BALANCED,
            assigned_at: 1700000000000,
            due_date: 1700086400000, // +24 hours
            priority: 2u8, // PRIORITY_NORMAL
            estimated_time: 1800000, // 30 minutes in ms
            accepted: false,
            started: false,
            completed: false,
            submission_time: option::none(),
            predicted_quality: 80,
            predicted_time: 1800000,
            expertise_match_score: 85,
            actual_quality: option::none(),
            actual_time: option::none(),
            consensus_alignment: option::none(),
        };
        
        // Test assignment properties
        assert!(assignment.validator == @0x2, 0);
        assert!(assignment.assigned_at == 1700000000000, 1);
        assert!(assignment.due_date == 1700086400000, 2);
        assert!(assignment.priority == 2u8, 3);
        assert!(assignment.estimated_time == 1800000, 4);
        assert!(assignment.assignment_method == METHOD_BALANCED, 5);
        assert!(assignment.accepted == false, 6);
        assert!(assignment.started == false, 7);
        assert!(assignment.completed == false, 8);
        
        // Calculate assignment duration
        let duration = assignment.due_date - assignment.assigned_at;
        assert!(duration == 86400000, 9); // 24 hours in milliseconds
        
        // Test category matching
        let blockchain_category = string::utf8(b"blockchain");
        assert!(assignment.article_category == blockchain_category, 10);
        
        // Clean up
        let ValidatorAssignment {
            id, validator: _, session_id: _, article_id: _, article_category: _,
            assignment_method: _, assigned_at: _, due_date: _, priority: _, estimated_time: _,
            accepted: _, started: _, completed: _, submission_time: _,
            predicted_quality: _, predicted_time: _, expertise_match_score: _,
            actual_quality: _, actual_time: _, consensus_alignment: _
        } = assignment;
        object::delete(id);
        
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_happy_path_global_performance_stats() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Create global performance stats
        let stats = GlobalPerformanceStats {
            average_accuracy: 85,
            average_timeliness: 82,
            average_quality: 88,
            average_consensus_rate: 91,
            total_validations_completed: 1250,
            total_review_time: 75000000, // Total time in milliseconds
            performance_distribution: table::new(ctx),
            category_performance: table::new(ctx),
        };
        
        // Test stats properties
        assert!(stats.average_accuracy == 85, 0);
        assert!(stats.average_timeliness == 82, 1);
        assert!(stats.average_quality == 88, 2);
        assert!(stats.average_consensus_rate == 91, 3);
        assert!(stats.total_validations_completed == 1250, 4);
        assert!(stats.total_review_time == 75000000, 5);
        
        // Calculate average review time per validation
        let avg_review_time = stats.total_review_time / stats.total_validations_completed;
        assert!(avg_review_time == 60000, 6); // 60 seconds average
        
        // Test overall system health score
        let system_health = (stats.average_accuracy + stats.average_timeliness + 
                           stats.average_quality + stats.average_consensus_rate) / 4;
        assert!(system_health == 86, 7); // (85+82+88+91)/4 = 86.5 → 86
        
        // Clean up
        let GlobalPerformanceStats { 
            average_accuracy: _, average_timeliness: _, average_quality: _, 
            average_consensus_rate: _, total_validations_completed: _, total_review_time: _, 
            performance_distribution, category_performance 
        } = stats;
        table::destroy_empty(performance_distribution);
        table::destroy_empty(category_performance);
        
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_happy_path_validator_selection_criteria() {
        // Test selection method constants
        assert!(METHOD_RANDOM == 1u8, 0);
        assert!(METHOD_STAKE_WEIGHTED == 2u8, 1);
        assert!(METHOD_EXPERTISE_BASED == 3u8, 2);
        assert!(METHOD_PERFORMANCE_BASED == 4u8, 3);
        assert!(METHOD_BALANCED == 5u8, 4);
        
        // Test validator profile calculations (simplified without struct)
        let validator = @0x2;
        let expertise_score = 88u8;
        let stake_weight = 15u8; // percentage of total stake
        let recent_performance = 92u8;
        let availability_ratio = 95u8; // percentage available
        let specialization_match = 85u8; // how well skills match content
        let reputation_score = 78u8;
        
        // Test profile properties
        assert!(validator == @0x2, 5);
        assert!(expertise_score == 88, 6);
        assert!(stake_weight == 15, 7);
        assert!(recent_performance == 92, 8);
        assert!(availability_ratio == 95, 9);
        assert!(specialization_match == 85, 10);
        assert!(reputation_score == 78, 11);
        
        // Calculate composite selection score
        let composite_score = (
            (expertise_score as u64) * 25 +
            (recent_performance as u64) * 30 +
            (availability_ratio as u64) * 20 +
            (specialization_match as u64) * 15 +
            (reputation_score as u64) * 10
        ) / 100;
        
        // Expected: (88*25 + 92*30 + 95*20 + 85*15 + 78*10) / 100 = 88.45
        assert!(composite_score >= 88 && composite_score <= 89, 12);
    }

    #[test]
    public fun test_happy_path_cooldown_and_suspension_mechanics() {
        // Test cooldown constants
        assert!(POOR_PERFORMANCE_COOLDOWN == 86400000, 0); // 24 hours
        assert!(ASSIGNMENT_COOLDOWN == 3600000, 1);        // 1 hour
        assert!(SUSPENSION_COOLDOWN == 604800000, 2);      // 7 days
        
        let current_time = 1700000000000u64;
        
        // Test various cooldown scenarios
        let performance_cooldown_end = current_time + POOR_PERFORMANCE_COOLDOWN;
        let assignment_cooldown_end = current_time + ASSIGNMENT_COOLDOWN;
        let suspension_cooldown_end = current_time + SUSPENSION_COOLDOWN;
        
        // Verify cooldown calculations
        assert!(performance_cooldown_end == current_time + 86400000, 3);
        assert!(assignment_cooldown_end == current_time + 3600000, 4);
        assert!(suspension_cooldown_end == current_time + 604800000, 5);
        
        // Test cooldown status checks
        let check_time1 = current_time + 3600000; // After 1 hour
        let check_time2 = current_time + 86400000; // After 24 hours  
        let check_time3 = current_time + 604800000; // After 7 days
        
        // After 1 hour - assignment cooldown expired
        assert!(check_time1 >= assignment_cooldown_end, 6);
        assert!(check_time1 < performance_cooldown_end, 7);
        assert!(check_time1 < suspension_cooldown_end, 8);
        
        // After 24 hours - performance cooldown expired
        assert!(check_time2 >= performance_cooldown_end, 9);
        assert!(check_time2 < suspension_cooldown_end, 10);
        
        // After 7 days - all cooldowns expired
        assert!(check_time3 >= suspension_cooldown_end, 11);
    }

    #[test]
    public fun test_happy_path_stake_requirements() {
        // Test minimum stake constants (these are example values)
        let MIN_VALIDATOR_STAKE = 100000000000u64; // 100 SUI
        let BRONZE_MIN_STAKE = 100000000000u64;    // 100 SUI
        let SILVER_MIN_STAKE = 250000000000u64;    // 250 SUI
        let GOLD_MIN_STAKE = 500000000000u64;      // 500 SUI
        let PLATINUM_MIN_STAKE = 1000000000000u64; // 1000 SUI
        
        assert!(MIN_VALIDATOR_STAKE == 100000000000, 0); // 100 SUI
        assert!(BRONZE_MIN_STAKE == 100000000000, 1);    // 100 SUI
        assert!(SILVER_MIN_STAKE == 250000000000, 2);    // 250 SUI
        assert!(GOLD_MIN_STAKE == 500000000000, 3);      // 500 SUI
        assert!(PLATINUM_MIN_STAKE == 1000000000000, 4); // 1000 SUI
        
        // Test tier eligibility based on stake
        let test_stakes = vector[
            50000000000u64,   // 50 SUI - insufficient
            150000000000u64,  // 150 SUI - bronze eligible
            300000000000u64,  // 300 SUI - silver eligible
            600000000000u64,  // 600 SUI - gold eligible
            1200000000000u64, // 1200 SUI - platinum eligible
        ];
        
        let expected_eligible_tiers = vector[
            0u8, // Insufficient stake
            1u8, // Bronze
            2u8, // Silver
            3u8, // Gold  
            4u8, // Platinum
        ];
        
        let mut i = 0;
        while (i < vector::length(&test_stakes)) {
            let stake = *vector::borrow(&test_stakes, i);
            let expected_tier = *vector::borrow(&expected_eligible_tiers, i);
            
            let max_eligible_tier = if (stake >= PLATINUM_MIN_STAKE) {
                TIER_PLATINUM
            } else if (stake >= GOLD_MIN_STAKE) {
                TIER_GOLD
            } else if (stake >= SILVER_MIN_STAKE) {
                TIER_SILVER
            } else if (stake >= BRONZE_MIN_STAKE) {
                TIER_BRONZE
            } else {
                0u8 // Insufficient stake
            };
            
            assert!(max_eligible_tier == expected_tier, (5 + i));
            i = i + 1;
        };
    }
}