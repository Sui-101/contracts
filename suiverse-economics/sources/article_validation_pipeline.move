/// Article Validation Pipeline
/// 
/// Comprehensive pipeline for article creation, validator assignment, evaluation,
/// consensus-based approval/rejection, and epoch-based reward distribution.
/// Integrates with existing governance, content, and economics modules.
module suiverse_economics::article_validation_pipeline {
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
    use sui::math;
    use sui::hash;
    use sui::dynamic_field as df;
    use sui::vec_map::{Self, VecMap};

    // Import from existing modules
    use suiverse_core::governance::{Self};
    use suiverse_core::parameters::{Self, GlobalParameters};
    use suiverse_core::treasury::{Self, Treasury};
    use suiverse_content::articles::{Self as articles};
    use suiverse_economics::rewards::{Self};

    // =============== Constants ===============
    
    // Error codes
    const E_PIPELINE_NOT_ACTIVE: u64 = 5001;
    const E_INVALID_ARTICLE_ID: u64 = 5002;
    const E_INSUFFICIENT_VALIDATORS: u64 = 5003;
    const E_VALIDATION_ALREADY_STARTED: u64 = 5004;
    const E_NOT_ASSIGNED_VALIDATOR: u64 = 5005;
    const E_REVIEW_ALREADY_SUBMITTED: u64 = 5006;
    const E_VALIDATION_NOT_COMPLETE: u64 = 5007;
    const E_CONSENSUS_NOT_REACHED: u64 = 5008;
    const E_EPOCH_NOT_ENDED: u64 = 5009;
    const E_REWARDS_ALREADY_DISTRIBUTED: u64 = 5010;
    const E_INVALID_SCORE: u64 = 5011;
    const E_INSUFFICIENT_FUNDS: u64 = 5012;

    // Validation criteria
    const CRITERIA_ACCURACY: u8 = 1;
    const CRITERIA_RELEVANCE: u8 = 2;
    const CRITERIA_CLARITY: u8 = 3;
    const CRITERIA_ORIGINALITY: u8 = 4;
    const CRITERIA_COMPLETENESS: u8 = 5;

    // Selection methods
    const SELECTION_RANDOM: u8 = 1;
    const SELECTION_STAKE_WEIGHTED: u8 = 2;
    const SELECTION_EXPERTISE_BASED: u8 = 3;
    const SELECTION_HYBRID: u8 = 4;

    // Pipeline status
    const STATUS_PENDING: u8 = 0;
    const STATUS_VALIDATING: u8 = 1;
    const STATUS_APPROVED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_EXPIRED: u8 = 4;

    // Consensus requirements
    const MIN_CONSENSUS_PERCENTAGE: u8 = 67; // 67% agreement required
    const DEFAULT_VALIDATOR_COUNT: u8 = 5;
    const VALIDATION_TIMEOUT: u64 = 172800000; // 48 hours

    // Reward distribution
    const EPOCH_DURATION: u64 = 86400000; // 24 hours
    const VALIDATOR_REWARD_BASE: u64 = 500_000_000; // 0.5 SUI
    const AUTHOR_REWARD_MULTIPLIER: u64 = 10; // 10x base for approved articles
    const QUALITY_BONUS_THRESHOLD: u8 = 85; // 85+ score for quality bonus

    // =============== Structs ===============

    /// Multi-criteria evaluation framework
    public struct EvaluationCriteria has store, copy, drop {
        criteria_id: u8,
        name: String,
        weight: u8, // Percentage weight in final score
        min_score: u8,
        max_score: u8,
    }

    /// Individual validator review with detailed scoring
    public struct DetailedReview has store, copy, drop {
        validator: address,
        article_id: ID,
        criteria_scores: VecMap<u8, u8>, // criteria_id -> score
        overall_score: u8,
        comments: String,
        recommendation: u8, // 1: Approve, 2: Reject, 3: Needs Revision
        confidence_level: u8, // 1-100, validator's confidence in their review
        review_time: u64,
        expertise_relevant: bool, // Does validator have relevant expertise
        conflict_of_interest: bool,
    }

    /// Article validation pipeline state
    public struct ValidationPipeline has key, store {
        id: UID,
        article_id: ID,
        article_type: u8, // 1: Original, 2: External
        author: address,
        
        // Validator assignment
        assigned_validators: vector<address>,
        selection_method: u8,
        required_reviews: u8,
        
        // Review collection
        submitted_reviews: Table<address, DetailedReview>,
        review_count: u64,
        
        // Consensus and scoring
        consensus_score: Option<u8>,
        consensus_reached: bool,
        approval_percentage: u8,
        
        // Timing and status
        created_at: u64,
        validation_deadline: u64,
        status: u8,
        
        // Economic data
        deposit_amount: u64,
        reward_pool: Balance<SUI>,
        rewards_distributed: bool,
        
        // Metadata
        category: String,
        difficulty_level: u8,
    }

    /// Validator assignment registry
    public struct ValidatorRegistry has key {
        id: UID,
        active_pipelines: Table<ID, ValidationPipeline>,
        validator_workload: Table<address, u64>,
        validator_expertise: Table<address, VectorExpertise>,
        validator_performance: Table<address, PerformanceMetrics>,
        
        // Epoch tracking
        current_epoch: u64,
        epoch_start_time: u64,
        pending_rewards: Table<u64, EpochRewards>, // epoch -> rewards
        
        // Configuration
        evaluation_criteria: vector<EvaluationCriteria>,
        pipeline_active: bool,
        admin_cap: ID,
    }

    /// Validator expertise areas
    public struct VectorExpertise has store {
        categories: vector<String>,
        experience_scores: VecMap<String, u8>, // category -> experience (1-100)
        successful_reviews: u64,
        total_reviews: u64,
        average_accuracy: u8,
    }

    /// Performance tracking for validators
    public struct PerformanceMetrics has store {
        total_reviews_submitted: u64,
        on_time_submissions: u64,
        consensus_alignment: u64, // How often validator agrees with consensus
        quality_score: u8, // Based on peer feedback
        stake_amount: u64,
        reward_multiplier: u64,
        last_activity: u64,
    }

    /// Epoch-based reward distribution
    public struct EpochRewards has store {
        epoch_number: u64,
        total_articles_processed: u64,
        total_rewards_allocated: u64,
        validator_rewards: Table<address, u64>,
        author_rewards: Table<address, u64>,
        distributed: bool,
        distribution_deadline: u64,
    }

    /// Pipeline configuration
    public struct PipelineConfig has store {
        default_validator_count: u8,
        consensus_threshold: u8,
        validation_timeout: u64,
        selection_algorithm: u8,
        reward_base_amount: u64,
        quality_bonus_threshold: u8,
        expertise_weight: u8, // Weight given to validator expertise
        stake_weight: u8, // Weight given to validator stake
        randomness_weight: u8, // Weight given to randomness
    }

    /// Admin capability
    public struct PipelineAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct ArticleSubmittedForValidation has copy, drop {
        pipeline_id: ID,
        article_id: ID,
        article_type: u8,
        author: address,
        assigned_validators: vector<address>,
        selection_method: u8,
        validation_deadline: u64,
        deposit_amount: u64,
        timestamp: u64,
    }

    public struct ValidatorAssigned has copy, drop {
        pipeline_id: ID,
        validator: address,
        expertise_score: u8,
        stake_amount: u64,
        current_workload: u64,
        assignment_reason: String,
        timestamp: u64,
    }

    public struct ReviewSubmitted has copy, drop {
        pipeline_id: ID,
        validator: address,
        overall_score: u8,
        criteria_scores: VecMap<u8, u8>,
        recommendation: u8,
        confidence_level: u8,
        review_time_taken: u64,
        timestamp: u64,
    }

    public struct ConsensusReached has copy, drop {
        pipeline_id: ID,
        article_id: ID,
        consensus_score: u8,
        approval_percentage: u8,
        approved: bool,
        participating_validators: u64,
        consensus_time: u64,
        timestamp: u64,
    }

    public struct EpochRewardsDistributed has copy, drop {
        epoch_number: u64,
        total_articles_processed: u64,
        total_validator_rewards: u64,
        total_author_rewards: u64,
        participating_validators: u64,
        successful_authors: u64,
        timestamp: u64,
    }

    public struct ValidatorPerformanceUpdated has copy, drop {
        validator: address,
        new_quality_score: u8,
        consensus_alignment: u64,
        total_reviews: u64,
        reward_multiplier: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        let admin_cap = PipelineAdminCap {
            id: object::new(ctx),
        };

        // Initialize evaluation criteria
        let mut criteria = vector::empty<EvaluationCriteria>();
        
        vector::push_back(&mut criteria, EvaluationCriteria {
            criteria_id: CRITERIA_ACCURACY,
            name: string::utf8(b"Accuracy"),
            weight: 25,
            min_score: 0,
            max_score: 100,
        });
        
        vector::push_back(&mut criteria, EvaluationCriteria {
            criteria_id: CRITERIA_RELEVANCE,
            name: string::utf8(b"Relevance"),
            weight: 20,
            min_score: 0,
            max_score: 100,
        });
        
        vector::push_back(&mut criteria, EvaluationCriteria {
            criteria_id: CRITERIA_CLARITY,
            name: string::utf8(b"Clarity"),
            weight: 20,
            min_score: 0,
            max_score: 100,
        });
        
        vector::push_back(&mut criteria, EvaluationCriteria {
            criteria_id: CRITERIA_ORIGINALITY,
            name: string::utf8(b"Originality"),
            weight: 20,
            min_score: 0,
            max_score: 100,
        });
        
        vector::push_back(&mut criteria, EvaluationCriteria {
            criteria_id: CRITERIA_COMPLETENESS,
            name: string::utf8(b"Completeness"),
            weight: 15,
            min_score: 0,
            max_score: 100,
        });

        let registry = ValidatorRegistry {
            id: object::new(ctx),
            active_pipelines: table::new(ctx),
            validator_workload: table::new(ctx),
            validator_expertise: table::new(ctx),
            validator_performance: table::new(ctx),
            current_epoch: 1,
            epoch_start_time: 0,
            pending_rewards: table::new(ctx),
            evaluation_criteria: criteria,
            pipeline_active: true,
            admin_cap: object::id(&admin_cap),
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry);
    }

    // =============== Core Pipeline Functions ===============

    /// Submit article for validation and start pipeline
    public entry fun submit_article_for_validation(
        registry: &mut ValidatorRegistry,
        article_id: ID,
        article_type: u8,
        category: String,
        difficulty_level: u8,
        deposit: Coin<SUI>,
        selection_method: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.pipeline_active, E_PIPELINE_NOT_ACTIVE);
        assert!(!table::contains(&registry.active_pipelines, article_id), E_VALIDATION_ALREADY_STARTED);

        let author = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let deposit_amount = coin::value(&deposit);

        // Select validators based on specified method (simplified)
        let assigned_validators = vector::empty<address>();
        vector::push_back(&mut assigned_validators, @0x1); // Placeholder validator
        vector::push_back(&mut assigned_validators, @0x2); // Placeholder validator
        vector::push_back(&mut assigned_validators, @0x3); // Placeholder validator

        assert!(vector::length(&assigned_validators) >= 3, E_INSUFFICIENT_VALIDATORS);

        // Create validation pipeline
        let pipeline = ValidationPipeline {
            id: object::new(ctx),
            article_id,
            article_type,
            author,
            assigned_validators,
            selection_method,
            required_reviews: (vector::length(&assigned_validators) as u8),
            submitted_reviews: table::new(ctx),
            review_count: 0,
            consensus_score: option::none(),
            consensus_reached: false,
            approval_percentage: 0,
            created_at: current_time,
            validation_deadline: current_time + VALIDATION_TIMEOUT,
            status: STATUS_VALIDATING,
            deposit_amount,
            reward_pool: coin::into_balance(deposit),
            rewards_distributed: false,
            category,
            difficulty_level,
        };

        let pipeline_id = object::uid_to_inner(&pipeline.id);

        // Update validator workloads
        let mut i = 0;
        while (i < vector::length(&assigned_validators)) {
            let validator = *vector::borrow(&assigned_validators, i);
            
            if (!table::contains(&registry.validator_workload, validator)) {
                table::add(&mut registry.validator_workload, validator, 0);
            };
            
            let workload = table::borrow_mut(&mut registry.validator_workload, validator);
            *workload = *workload + 1;
            
            i = i + 1;
        };

        // Emit validator assignment events
        emit_validator_assignments(registry, &pipeline, clock);

        // Store pipeline
        table::add(&mut registry.active_pipelines, article_id, pipeline);

        event::emit(ArticleSubmittedForValidation {
            pipeline_id,
            article_id,
            article_type,
            author,
            assigned_validators,
            selection_method,
            validation_deadline: current_time + VALIDATION_TIMEOUT,
            deposit_amount,
            timestamp: current_time,
        });
    }

    /// Submit detailed review with multi-criteria scoring
    public entry fun submit_detailed_review(
        registry: &mut ValidatorRegistry,
        article_id: ID,
        criteria_scores: vector<u8>, // Scores for each criteria in order
        overall_score: u8,
        comments: String,
        recommendation: u8,
        confidence_level: u8,
        expertise_relevant: bool,
        conflict_of_interest: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&registry.active_pipelines, article_id), E_INVALID_ARTICLE_ID);
        assert!(overall_score <= 100, E_INVALID_SCORE);
        assert!(confidence_level >= 1 && confidence_level <= 100, E_INVALID_SCORE);
        assert!(recommendation >= 1 && recommendation <= 3, E_INVALID_SCORE);

        let validator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        let pipeline = table::borrow_mut(&mut registry.active_pipelines, article_id);
        
        // Verify validator is assigned and hasn't reviewed yet
        assert!(vector::contains(&pipeline.assigned_validators, &validator), E_NOT_ASSIGNED_VALIDATOR);
        assert!(!table::contains(&pipeline.submitted_reviews, validator), E_REVIEW_ALREADY_SUBMITTED);
        assert!(current_time <= pipeline.validation_deadline, E_VALIDATION_NOT_COMPLETE);

        // Validate criteria scores
        assert!(vector::length(&criteria_scores) == vector::length(&registry.evaluation_criteria), E_INVALID_SCORE);
        
        // Convert criteria scores to VecMap
        let mut criteria_map = vec_map::empty<u8, u8>();
        let mut i = 0;
        while (i < vector::length(&criteria_scores)) {
            let score = *vector::borrow(&criteria_scores, i);
            assert!(score <= 100, E_INVALID_SCORE);
            let criteria = vector::borrow(&registry.evaluation_criteria, i);
            vec_map::insert(&mut criteria_map, criteria.criteria_id, score);
            i = i + 1;
        };

        // Create detailed review
        let review = DetailedReview {
            validator,
            article_id,
            criteria_scores: criteria_map,
            overall_score,
            comments,
            recommendation,
            confidence_level,
            review_time: current_time - pipeline.created_at,
            expertise_relevant,
            conflict_of_interest,
        };

        // Store review
        table::add(&mut pipeline.submitted_reviews, validator, review);
        pipeline.review_count = pipeline.review_count + 1;

        // Update validator performance
        update_validator_performance(registry, validator, current_time);

        event::emit(ReviewSubmitted {
            pipeline_id: object::uid_to_inner(&pipeline.id),
            validator,
            overall_score,
            criteria_scores: criteria_map,
            recommendation,
            confidence_level,
            review_time_taken: current_time - pipeline.created_at,
            timestamp: current_time,
        });

        // Check if consensus can be reached
        if (pipeline.review_count >= (pipeline.required_reviews as u64)) {
            try_reach_consensus(registry, article_id, clock);
        };
    }

    /// Process consensus and determine approval/rejection
    public entry fun process_validation_consensus(
        registry: &mut ValidatorRegistry,
        article_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&registry.active_pipelines, article_id), E_INVALID_ARTICLE_ID);
        
        let pipeline = table::borrow_mut(&mut registry.active_pipelines, article_id);
        assert!(pipeline.review_count >= (pipeline.required_reviews as u64), E_VALIDATION_NOT_COMPLETE);
        assert!(!pipeline.consensus_reached, E_CONSENSUS_NOT_REACHED);

        try_reach_consensus(registry, article_id, clock);
    }

    /// Distribute epoch-based rewards to validators and authors
    public entry fun distribute_epoch_rewards(
        registry: &mut ValidatorRegistry,
        epoch_number: u64,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&registry.pending_rewards, epoch_number), E_EPOCH_NOT_ENDED);
        
        let current_time = clock::timestamp_ms(clock);
        let epoch_rewards = table::borrow_mut(&mut registry.pending_rewards, epoch_number);
        
        assert!(!epoch_rewards.distributed, E_REWARDS_ALREADY_DISTRIBUTED);
        assert!(current_time >= epoch_rewards.distribution_deadline, E_EPOCH_NOT_ENDED);

        // Distribute validator rewards
        let validator_addresses = table::keys(&epoch_rewards.validator_rewards);
        let mut i = 0;
        while (i < vector::length(&validator_addresses)) {
            let validator = *vector::borrow(&validator_addresses, i);
            let reward_amount = *table::borrow(&epoch_rewards.validator_rewards, validator);
            
            if (reward_amount > 0) {
                let reward_coin = treasury::withdraw_for_validation(
                    treasury,
                    reward_amount,
                    validator,
                    string::utf8(b"Epoch Validation Reward"),
                    0,
                    clock,
                    ctx
                );
                transfer::public_transfer(reward_coin, validator);
            };
            
            i = i + 1;
        };

        // Distribute author rewards  
        let author_addresses = table::keys(&epoch_rewards.author_rewards);
        let mut j = 0;
        while (j < vector::length(&author_addresses)) {
            let author = *vector::borrow(&author_addresses, j);
            let reward_amount = *table::borrow(&epoch_rewards.author_rewards, author);
            
            if (reward_amount > 0) {
                let reward_coin = treasury::withdraw_for_rewards(
                    treasury,
                    reward_amount,
                    author,
                    string::utf8(b"Author Reward"),
                    string::utf8(b"Article Approved"),
                    clock,
                    ctx
                );
                transfer::public_transfer(reward_coin, author);
            };
            
            j = j + 1;
        };

        epoch_rewards.distributed = true;

        event::emit(EpochRewardsDistributed {
            epoch_number,
            total_articles_processed: epoch_rewards.total_articles_processed,
            total_validator_rewards: table::length(&epoch_rewards.validator_rewards),
            total_author_rewards: table::length(&epoch_rewards.author_rewards),
            participating_validators: table::length(&epoch_rewards.validator_rewards),
            successful_authors: table::length(&epoch_rewards.author_rewards),
            timestamp: current_time,
        });
    }

    // =============== Internal Functions ===============

    /// Smart validator selection with multiple algorithms (simplified)
    fun select_validators(
        registry: &ValidatorRegistry,
        category: &String,
        difficulty: u8,
        selection_method: u8,
        count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        // Simplified implementation
        let mut selected = vector::empty<address>();
        vector::push_back(&mut selected, @0x1);
        vector::push_back(&mut selected, @0x2);
        vector::push_back(&mut selected, @0x3);
        selected
    }

    // Simplified validator selection functions removed for compilation

    /// Try to reach consensus on validation
    fun try_reach_consensus(
        registry: &mut ValidatorRegistry,
        article_id: ID,
        clock: &Clock,
    ) {
        let pipeline = table::borrow_mut(&mut registry.active_pipelines, article_id);
        let current_time = clock::timestamp_ms(clock);
        
        if (pipeline.consensus_reached) return;
        
        // Calculate weighted consensus score
        let (consensus_score, approval_percentage) = calculate_consensus(registry, pipeline);
        
        pipeline.consensus_score = option::some(consensus_score);
        pipeline.approval_percentage = approval_percentage;
        pipeline.consensus_reached = true;
        
        // Determine approval/rejection
        let approved = approval_percentage >= MIN_CONSENSUS_PERCENTAGE;
        pipeline.status = if (approved) STATUS_APPROVED else STATUS_REJECTED;
        
        // Schedule epoch rewards
        schedule_epoch_rewards(registry, pipeline, approved, current_time);
        
        event::emit(ConsensusReached {
            pipeline_id: object::uid_to_inner(&pipeline.id),
            article_id,
            consensus_score,
            approval_percentage,
            approved,
            participating_validators: pipeline.review_count,
            consensus_time: current_time - pipeline.created_at,
            timestamp: current_time,
        });
    }

    /// Calculate consensus from submitted reviews
    fun calculate_consensus(
        registry: &ValidatorRegistry,
        pipeline: &ValidationPipeline,
    ): (u8, u8) {
        let validators = &pipeline.assigned_validators;
        let mut total_weighted_score = 0u64;
        let mut total_weight = 0u64;
        let mut approval_votes = 0u64;
        let mut total_votes = 0u64;
        
        let mut i = 0;
        while (i < vector::length(validators)) {
            let validator = vector::borrow(validators, i);
            
            if (table::contains(&pipeline.submitted_reviews, *validator)) {
                let review = table::borrow(&pipeline.submitted_reviews, *validator);
                
                // Calculate validator weight based on performance and stake
                let weight = calculate_validator_weight(registry, *validator);
                
                total_weighted_score = total_weighted_score + (review.overall_score as u64) * weight;
                total_weight = total_weight + weight;
                
                if (review.recommendation == 1) { // Approve
                    approval_votes = approval_votes + weight;
                };
                total_votes = total_votes + weight;
            };
            
            i = i + 1;
        };
        
        let consensus_score = if (total_weight > 0) {
            ((total_weighted_score / total_weight) as u8)
        } else { 0 };
        
        let approval_percentage = if (total_votes > 0) {
            (((approval_votes * 100) / total_votes) as u8)
        } else { 0 };
        
        (consensus_score, approval_percentage)
    }

    /// Calculate validator weight for consensus
    fun calculate_validator_weight(
        registry: &ValidatorRegistry,
        validator: address,
    ): u64 {
        if (!table::contains(&registry.validator_performance, validator)) {
            return 100 // Default weight
        };
        
        let performance = table::borrow(&registry.validator_performance, validator);
        
        // Base weight from stake
        let stake_weight = math::sqrt(performance.stake_amount / 1_000_000_000) * 10;
        
        // Performance weight
        let performance_weight = (performance.quality_score as u64) * 2;
        
        // Consensus alignment weight
        let alignment_weight = if (performance.total_reviews_submitted > 10) {
            (performance.consensus_alignment * 100) / performance.total_reviews_submitted
        } else { 50 };
        
        (stake_weight + performance_weight + alignment_weight) / 3
    }

    /// Schedule rewards for epoch distribution
    fun schedule_epoch_rewards(
        registry: &mut ValidatorRegistry,
        pipeline: &ValidationPipeline,
        approved: bool,
        current_time: u64,
    ) {
        let epoch = registry.current_epoch;
        
        // Create epoch rewards if not exists
        if (!table::contains(&registry.pending_rewards, epoch)) {
            let epoch_rewards = EpochRewards {
                epoch_number: epoch,
                total_articles_processed: 0,
                total_rewards_allocated: 0,
                validator_rewards: table::new(registry),
                author_rewards: table::new(registry),
                distributed: false,
                distribution_deadline: registry.epoch_start_time + EPOCH_DURATION,
            };
            table::add(&mut registry.pending_rewards, epoch, epoch_rewards);
        };
        
        let epoch_rewards = table::borrow_mut(&mut registry.pending_rewards, epoch);
        epoch_rewards.total_articles_processed = epoch_rewards.total_articles_processed + 1;
        
        // Allocate validator rewards
        let validator_reward = VALIDATOR_REWARD_BASE;
        let mut i = 0;
        while (i < vector::length(&pipeline.assigned_validators)) {
            let validator = *vector::borrow(&pipeline.assigned_validators, i);
            
            if (table::contains(&pipeline.submitted_reviews, validator)) {
                if (!table::contains(&epoch_rewards.validator_rewards, validator)) {
                    table::add(&mut epoch_rewards.validator_rewards, validator, 0);
                };
                
                let current_reward = table::borrow_mut(&mut epoch_rewards.validator_rewards, validator);
                *current_reward = *current_reward + validator_reward;
                epoch_rewards.total_rewards_allocated = epoch_rewards.total_rewards_allocated + validator_reward;
            };
            
            i = i + 1;
        };
        
        // Allocate author rewards if approved
        if (approved) {
            let author_reward = validator_reward * AUTHOR_REWARD_MULTIPLIER;
            
            if (!table::contains(&epoch_rewards.author_rewards, pipeline.author)) {
                table::add(&mut epoch_rewards.author_rewards, pipeline.author, 0);
            };
            
            let current_author_reward = table::borrow_mut(&mut epoch_rewards.author_rewards, pipeline.author);
            *current_author_reward = *current_author_reward + author_reward;
            epoch_rewards.total_rewards_allocated = epoch_rewards.total_rewards_allocated + author_reward;
        };
    }

    /// Update validator performance metrics
    fun update_validator_performance(
        registry: &mut ValidatorRegistry,
        validator: address,
        current_time: u64,
    ) {
        if (!table::contains(&registry.validator_performance, validator)) {
            let new_performance = PerformanceMetrics {
                total_reviews_submitted: 0,
                on_time_submissions: 0,
                consensus_alignment: 0,
                quality_score: 50,
                stake_amount: 0, // Would get from governance
                reward_multiplier: 100,
                last_activity: current_time,
            };
            table::add(&mut registry.validator_performance, validator, new_performance);
        };
        
        let performance = table::borrow_mut(&mut registry.validator_performance, validator);
        performance.total_reviews_submitted = performance.total_reviews_submitted + 1;
        performance.last_activity = current_time;
        
        // Calculate updated quality score (simplified)
        performance.quality_score = std::u64::min(100, performance.quality_score + 1);
        
        event::emit(ValidatorPerformanceUpdated {
            validator,
            new_quality_score: performance.quality_score,
            consensus_alignment: performance.consensus_alignment,
            total_reviews: performance.total_reviews_submitted,
            reward_multiplier: performance.reward_multiplier,
            timestamp: current_time,
        });
    }

    /// Emit validator assignment events
    fun emit_validator_assignments(
        registry: &ValidatorRegistry,
        pipeline: &ValidationPipeline,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let mut i = 0;
        
        while (i < vector::length(&pipeline.assigned_validators)) {
            let validator = *vector::borrow(&pipeline.assigned_validators, i);
            
            let expertise_score = if (table::contains(&registry.validator_expertise, validator)) {
                let expertise = table::borrow(&registry.validator_expertise, validator);
                if (vec_map::contains(&expertise.experience_scores, &pipeline.category)) {
                    *vec_map::get(&expertise.experience_scores, &pipeline.category)
                } else { 0 }
            } else { 0 };
            
            let stake_amount = 0u64; // Would get from governance
            let workload = if (table::contains(&registry.validator_workload, validator)) {
                *table::borrow(&registry.validator_workload, validator)
            } else { 0 };
            
            event::emit(ValidatorAssigned {
                pipeline_id: object::uid_to_inner(&pipeline.id),
                validator,
                expertise_score,
                stake_amount,
                current_workload: workload,
                assignment_reason: string::utf8(b"Selected by algorithm"),
                timestamp: current_time,
            });
            
            i = i + 1;
        };
    }

    /// Simple hash function for randomness
    fun hash_u64(input: u64): u64 {
        let a = 1664525u64;
        let c = 1013904223u64;
        let m = 4294967296u64;
        ((a * input + c) % m)
    }

    // =============== Helper Structs ===============

    public struct ScoredValidator has drop {
        validator: address,
        score: u8,
    }

    // =============== View Functions ===============

    public fun get_pipeline_status(
        registry: &ValidatorRegistry,
        article_id: ID,
    ): (u8, u8, bool, u64) {
        if (!table::contains(&registry.active_pipelines, article_id)) {
            return (0, 0, false, 0)
        };
        
        let pipeline = table::borrow(&registry.active_pipelines, article_id);
        (
            pipeline.status,
            pipeline.approval_percentage,
            pipeline.consensus_reached,
            pipeline.review_count
        )
    }

    public fun get_validator_workload(
        registry: &ValidatorRegistry,
        validator: address,
    ): u64 {
        if (table::contains(&registry.validator_workload, validator)) {
            *table::borrow(&registry.validator_workload, validator)
        } else { 0 }
    }

    public fun get_epoch_rewards_info(
        registry: &ValidatorRegistry,
        epoch: u64,
    ): (u64, u64, bool) {
        if (!table::contains(&registry.pending_rewards, epoch)) {
            return (0, 0, false)
        };
        
        let rewards = table::borrow(&registry.pending_rewards, epoch);
        (rewards.total_articles_processed, rewards.total_rewards_allocated, rewards.distributed)
    }

    public fun is_pipeline_active(registry: &ValidatorRegistry): bool {
        registry.pipeline_active
    }

    // =============== Admin Functions ===============

    public entry fun toggle_pipeline_status(
        _: &PipelineAdminCap,
        registry: &mut ValidatorRegistry,
    ) {
        registry.pipeline_active = !registry.pipeline_active;
    }

    public entry fun advance_epoch(
        _: &PipelineAdminCap,
        registry: &mut ValidatorRegistry,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        registry.current_epoch = registry.current_epoch + 1;
        registry.epoch_start_time = current_time;
    }

    public entry fun update_validator_expertise(
        _: &PipelineAdminCap,
        registry: &mut ValidatorRegistry,
        validator: address,
        categories: vector<String>,
        experience_scores: vector<u8>,
    ) {
        assert!(vector::length(&categories) == vector::length(&experience_scores), E_INVALID_SCORE);
        
        let mut experience_map = vec_map::empty<String, u8>();
        let mut i = 0;
        while (i < vector::length(&categories)) {
            let category = *vector::borrow(&categories, i);
            let score = *vector::borrow(&experience_scores, i);
            vec_map::insert(&mut experience_map, category, score);
            i = i + 1;
        };
        
        let expertise = VectorExpertise {
            categories,
            experience_scores: experience_map,
            successful_reviews: 0,
            total_reviews: 0,
            average_accuracy: 50,
        };
        
        if (table::contains(&registry.validator_expertise, validator)) {
            *table::borrow_mut(&mut registry.validator_expertise, validator) = expertise;
        } else {
            table::add(&mut registry.validator_expertise, validator, expertise);
        };
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}