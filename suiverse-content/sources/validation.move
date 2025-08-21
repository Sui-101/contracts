module suiverse_content::validation {
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
    use sui::math;
    use sui::hash;
    use sui::transfer;
    
    // Friend modules
    use suiverse_core::treasury::{Self, Treasury};
    use suiverse_core::parameters::{Self, GlobalParameters};
    use suiverse_core::governance::{Self, ValidatorRegistry};

    // =============== Constants ===============
    const E_INVALID_CONTENT_TYPE: u64 = 3001;
    const E_INSUFFICIENT_DEPOSIT: u64 = 3002;
    const E_NOT_VALIDATOR: u64 = 3003;
    const E_ALREADY_REVIEWED: u64 = 3004;
    const E_SESSION_EXPIRED: u64 = 3005;
    const E_SESSION_NOT_COMPLETE: u64 = 3006;
    const E_INVALID_SCORE: u64 = 3007;
    const E_NOT_ASSIGNED_VALIDATOR: u64 = 3008;
    const E_SESSION_ALREADY_PROCESSED: u64 = 3009;
    const E_INVALID_SELECTION_METHOD: u64 = 3010;

    // Content types
    const CONTENT_TYPE_ARTICLE: u8 = 1;
    const CONTENT_TYPE_PROJECT: u8 = 2;
    const CONTENT_TYPE_QUIZ: u8 = 3;
    const CONTENT_TYPE_EXAM: u8 = 4;
    const CONTENT_TYPE_COLLECTION: u8 = 5;

    // Deposit status
    const DEPOSIT_STATUS_LOCKED: u8 = 0;
    const DEPOSIT_STATUS_RETURNED: u8 = 1;
    const DEPOSIT_STATUS_FORFEITED: u8 = 2;

    // Validation decision
    const DECISION_PENDING: u8 = 0;
    const DECISION_APPROVE: u8 = 1;
    const DECISION_REJECT: u8 = 2;

    // Session status
    const SESSION_STATUS_PENDING: u8 = 0;
    const SESSION_STATUS_COMPLETED: u8 = 1;
    const SESSION_STATUS_EXPIRED: u8 = 2;

    // Selection methods
    const SELECTION_METHOD_RANDOM: u8 = 1;
    const SELECTION_METHOD_EXPERTISE: u8 = 2;
    const SELECTION_METHOD_STAKE_WEIGHTED: u8 = 3;

    // =============== Structs ===============
    
    /// Global validation configuration
    public struct ValidationConfig has key {
        id: UID,
        article_approval_threshold: u8,
        project_approval_threshold: u8,
        quiz_approval_threshold: u8,
        exam_approval_threshold: u8,
        collection_approval_threshold: u8,
        
        article_validator_count: u8,
        project_validator_count: u8,
        quiz_validator_count: u8,
        exam_validator_count: u8,
        collection_validator_count: u8,
        
        article_selection_method: u8,
        project_selection_method: u8,
        quiz_selection_method: u8,
        exam_selection_method: u8,
        collection_selection_method: u8,
        
        max_review_time: u64, // in milliseconds
        min_stake_for_validation: u64,
        reward_per_review: u64,
        penalty_for_late_review: u64,
    }

    /// Content deposit for validation
    public struct ContentDeposit has key, store {
        id: UID,
        content_id: ID,
        depositor: address,
        amount: u64,
        content_type: u8,
        status: u8,
        created_at: u64,
        processed_at: Option<u64>,
    }

    /// Individual validation review
    public struct ValidationReview has store, copy, drop {
        validator: address,
        content_id: ID,
        score: u8,
        comments: String,
        criteria_scores: vector<CriteriaScore>,
        timestamp: u64,
        decision: u8,
        review_quality_score: Option<u8>, // Meta-review score
    }

    /// Criteria-based scoring
    public struct CriteriaScore has store, copy, drop {
        criteria_id: u8,
        score: u8,
        weight: u8,
    }

    /// Validation session for content
    public struct ValidationSession has key {
        id: UID,
        content_id: ID,
        content_type: u8,
        assigned_validators: vector<address>,
        reviews: Table<address, ValidationReview>,
        reviews_submitted: u64,
        required_reviews: u8,
        deadline: u64,
        final_score: Option<u8>,
        status: u8,
        created_at: u64,
        completed_at: Option<u64>,
        deposit_id: ID,
    }

    /// Validator expertise mapping
    public struct ValidatorExpertise has key, store {
        id: UID,
        validator: address,
        content_types: vector<u8>,
        categories: vector<String>,
        total_reviews: u64,
        average_quality_score: u8,
        specializations: Table<String, u8>, // category -> expertise level
    }

    /// Validation statistics
    public struct ValidationStats has key {
        id: UID,
        total_sessions: u64,
        completed_sessions: u64,
        expired_sessions: u64,
        total_deposits_collected: u64,
        total_deposits_returned: u64,
        total_deposits_forfeited: u64,
        total_rewards_distributed: u64,
        average_review_time: u64,
        approval_rate: u64,
    }

    // =============== Events ===============
    
    public struct ContentSubmittedForValidation has copy, drop {
        content_id: ID,
        content_type: u8,
        depositor: address,
        deposit_amount: u64,
        session_id: ID,
        assigned_validators: vector<address>,
        deadline: u64,
    }

    public struct ValidationReviewSubmitted has copy, drop {
        session_id: ID,
        validator: address,
        score: u8,
        decision: u8,
        timestamp: u64,
    }

    public struct ValidationSessionCompleted has copy, drop {
        session_id: ID,
        content_id: ID,
        final_score: u8,
        approved: bool,
        deposit_status: u8,
        rewards_distributed: u64,
    }

    public struct ValidatorPenalized has copy, drop {
        validator: address,
        session_id: ID,
        penalty_amount: u64,
        reason: String,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let config = ValidationConfig {
            id: object::new(ctx),
            article_approval_threshold: 70,
            project_approval_threshold: 70,
            quiz_approval_threshold: 80,
            exam_approval_threshold: 90,
            collection_approval_threshold: 75,
            
            article_validator_count: 3,
            project_validator_count: 5,
            quiz_validator_count: 3,
            exam_validator_count: 5,
            collection_validator_count: 4,
            
            article_selection_method: SELECTION_METHOD_RANDOM,
            project_selection_method: SELECTION_METHOD_EXPERTISE,
            quiz_selection_method: SELECTION_METHOD_RANDOM,
            exam_selection_method: SELECTION_METHOD_EXPERTISE,
            collection_selection_method: SELECTION_METHOD_STAKE_WEIGHTED,
            
            max_review_time: 172800000, // 48 hours
            min_stake_for_validation: 100_000_000_000, // 100 SUI
            reward_per_review: 500_000_000, // 0.5 SUI
            penalty_for_late_review: 100_000_000, // 0.1 SUI
        };

        let stats = ValidationStats {
            id: object::new(ctx),
            total_sessions: 0,
            completed_sessions: 0,
            expired_sessions: 0,
            total_deposits_collected: 0,
            total_deposits_returned: 0,
            total_deposits_forfeited: 0,
            total_rewards_distributed: 0,
            average_review_time: 0,
            approval_rate: 0,
        };

        transfer::share_object(config);
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Submit content for validation
    public entry fun submit_content_for_validation(
        content_id: ID,
        content_type: u8,
        deposit: Coin<SUI>,
        config: &ValidationConfig,
        registry: &ValidatorRegistry,
        params: &GlobalParameters,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Validate content type
        assert!(
            content_type >= CONTENT_TYPE_ARTICLE && content_type <= CONTENT_TYPE_COLLECTION,
            E_INVALID_CONTENT_TYPE
        );

        // Check deposit amount
        let required_deposit = get_required_deposit(content_type, params);
        let deposit_amount = coin::value(&deposit);
        assert!(deposit_amount >= required_deposit, E_INSUFFICIENT_DEPOSIT);

        // Create deposit record
        let deposit_record = ContentDeposit {
            id: object::new(ctx),
            content_id,
            depositor: tx_context::sender(ctx),
            amount: deposit_amount,
            content_type,
            status: DEPOSIT_STATUS_LOCKED,
            created_at: clock::timestamp_ms(clock),
            processed_at: option::none(),
        };
        let deposit_id = object::uid_to_inner(&deposit_record.id);

        // Deposit funds to treasury
        treasury::deposit_funds(
            treasury,
            deposit,
            2, // POOL_VALIDATION
            string::utf8(b"Content Validation"),
            clock,
            ctx
        );

        // Select validators
        let validator_count = get_validator_count(content_type, config);
        let selection_method = get_selection_method(content_type, config);
        let assigned_validators = select_validators(
            validator_count,
            selection_method,
            content_type,
            registry,
            clock,
            ctx
        );

        // Create validation session
        let session = ValidationSession {
            id: object::new(ctx),
            content_id,
            content_type,
            assigned_validators,
            reviews: table::new(ctx),
            reviews_submitted: 0,
            required_reviews: validator_count,
            deadline: clock::timestamp_ms(clock) + config.max_review_time,
            final_score: option::none(),
            status: SESSION_STATUS_PENDING,
            created_at: clock::timestamp_ms(clock),
            completed_at: option::none(),
            deposit_id,
        };

        let session_id = object::uid_to_inner(&session.id);

        // Emit event
        event::emit(ContentSubmittedForValidation {
            content_id,
            content_type,
            depositor: tx_context::sender(ctx),
            deposit_amount,
            session_id,
            assigned_validators: session.assigned_validators,
            deadline: session.deadline,
        });

        transfer::share_object(deposit_record);
        transfer::share_object(session);
    }

    /// Submit validation review
    public entry fun submit_validation_review(
        session: &mut ValidationSession,
        score: u8,
        comments: String,
        registry: &ValidatorRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator_addr = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Check if session is still active
        assert!(session.status == SESSION_STATUS_PENDING, E_SESSION_ALREADY_PROCESSED);
        assert!(current_time <= session.deadline, E_SESSION_EXPIRED);

        // Check if validator is assigned
        assert!(
            vector::contains(&session.assigned_validators, &validator_addr),
            E_NOT_ASSIGNED_VALIDATOR
        );

        // Check if already reviewed
        assert!(!table::contains(&session.reviews, validator_addr), E_ALREADY_REVIEWED);

        // Validate score
        assert!(score <= 100, E_INVALID_SCORE);

        // Determine decision based on score and threshold
        let decision = if (score >= get_approval_threshold(session.content_type)) {
            DECISION_APPROVE
        } else {
            DECISION_REJECT
        };

        // Create review
        let review = ValidationReview {
            validator: validator_addr,
            content_id: session.content_id,
            score,
            comments,
            criteria_scores: vector::empty(), // Initialize empty criteria scores
            timestamp: current_time,
            decision,
            review_quality_score: option::none(),
        };

        // Add review to session
        table::add(&mut session.reviews, validator_addr, review);
        session.reviews_submitted = session.reviews_submitted + 1;

        // Emit event
        event::emit(ValidationReviewSubmitted {
            session_id: object::uid_to_inner(&session.id),
            validator: validator_addr,
            score,
            decision,
            timestamp: current_time,
        });

        // Check if all reviews are submitted
        if (session.reviews_submitted >= (session.required_reviews as u64)) {
            session.status = SESSION_STATUS_COMPLETED;
            session.completed_at = option::some(current_time);
        }
    }

    /// Process validation results
    public fun process_validation_results(
        session: &mut ValidationSession,
        deposit: &mut ContentDeposit,
        config: &ValidationConfig,
        treasury: &mut Treasury,
        stats: &mut ValidationStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Check session is completed
        assert!(
            session.status == SESSION_STATUS_COMPLETED || 
            clock::timestamp_ms(clock) > session.deadline,
            E_SESSION_NOT_COMPLETE
        );

        // Calculate final score
        let final_score = calculate_final_score(session);
        session.final_score = option::some(final_score);

        // Determine if approved
        let threshold = get_approval_threshold_from_config(session.content_type, config);
        let approved = final_score >= threshold;

        // Process deposit
        if (approved) {
            // Return deposit
            deposit.status = DEPOSIT_STATUS_RETURNED;
            stats.total_deposits_returned = stats.total_deposits_returned + deposit.amount;
        } else {
            // Forfeit deposit
            deposit.status = DEPOSIT_STATUS_FORFEITED;
            stats.total_deposits_forfeited = stats.total_deposits_forfeited + deposit.amount;
        };
        deposit.processed_at = option::some(clock::timestamp_ms(clock));

        // Distribute rewards to validators
        let reward_amount = distribute_validation_rewards(
            session,
            config,
            treasury,
            clock,
            ctx
        );

        // Update statistics
        stats.completed_sessions = stats.completed_sessions + 1;
        stats.total_rewards_distributed = stats.total_rewards_distributed + reward_amount;
        if (approved) {
            stats.approval_rate = (stats.approval_rate * (stats.completed_sessions - 1) + 100) / stats.completed_sessions;
        } else {
            stats.approval_rate = (stats.approval_rate * (stats.completed_sessions - 1)) / stats.completed_sessions;
        };

        // Emit event
        event::emit(ValidationSessionCompleted {
            session_id: object::uid_to_inner(&session.id),
            content_id: session.content_id,
            final_score,
            approved,
            deposit_status: deposit.status,
            rewards_distributed: reward_amount,
        });
    }

    // =============== Internal Functions ===============
    
    /// Select validators based on method
    fun select_validators(
        count: u8,
        selection_method: u8,
        content_type: u8,
        registry: &ValidatorRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        if (selection_method == SELECTION_METHOD_RANDOM) {
            select_random_validators(count, registry, clock, ctx)
        } else if (selection_method == SELECTION_METHOD_EXPERTISE) {
            select_expertise_based_validators(count, content_type, registry, ctx)
        } else if (selection_method == SELECTION_METHOD_STAKE_WEIGHTED) {
            select_stake_weighted_validators(count, registry, ctx)
        } else {
            abort E_INVALID_SELECTION_METHOD
        }
    }

    /// Select random validators
    fun select_random_validators(
        count: u8,
        registry: &ValidatorRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        // Get active validators (simplified)
        let active_validators = vector::empty<address>();
        let total_validators = vector::length(&active_validators);
        
        assert!(total_validators >= (count as u64), E_NOT_VALIDATOR);

        let mut selected = vector::empty<address>();
        let mut seed = clock::timestamp_ms(clock) + (tx_context::epoch(ctx) as u64);
        
        while (vector::length(&selected) < (count as u64)) {
            seed = hash_seed(seed);
            let index = seed % total_validators;
            let validator = *vector::borrow(&active_validators, index);
            
            if (!vector::contains(&selected, &validator)) {
                vector::push_back(&mut selected, validator);
            }
        };

        selected
    }

    /// Select validators based on expertise
    fun select_expertise_based_validators(
        count: u8,
        content_type: u8,
        registry: &ValidatorRegistry,
        ctx: &mut TxContext,
    ): vector<address> {
        // Get active validators (simplified)
        let active_validators = vector::empty<address>();
        let mut qualified_validators = vector::empty<address>();
        let mut i = 0;
        
        // Filter validators qualified for this content type
        while (i < vector::length(&active_validators)) {
            let validator = *vector::borrow(&active_validators, i);
            if (true) { // Simplified qualification check
                vector::push_back(&mut qualified_validators, validator);
            };
            i = i + 1;
        };
        
        assert!(vector::length(&qualified_validators) >= (count as u64), E_NOT_VALIDATOR);
        
        // Select top validators by level
        let mut selected = vector::empty<address>();
        let mut j = 0;
        let select_count = if ((count as u64) < vector::length(&qualified_validators)) { 
            (count as u64) 
        } else { 
            vector::length(&qualified_validators) 
        };
        
        while (j < select_count) {
            vector::push_back(&mut selected, *vector::borrow(&qualified_validators, j));
            j = j + 1;
        };

        selected
    }

    /// Select validators weighted by stake
    fun select_stake_weighted_validators(
        count: u8,
        registry: &ValidatorRegistry,
        ctx: &mut TxContext,
    ): vector<address> {
        // Get validators with minimum stake requirement
        // Get validators by stake (simplified)
        let qualified_validators = vector::empty<address>();
        
        assert!(vector::length(&qualified_validators) >= (count as u64), E_NOT_VALIDATOR);
        
        // For weighted selection, we use top validators
        // Get top validators (simplified)
        let top_validators = vector::empty<address>();
        
        top_validators
    }

    /// Generate pseudo-random seed
    fun hash_seed(seed: u64): u64 {
        // Simple linear congruential generator
        let a = 1664525u64;
        let c = 1013904223u64;
        let m = 4294967296u64; // 2^32
        
        ((a * seed + c) % m)
    }

    /// Calculate final score from reviews
    fun calculate_final_score(session: &ValidationSession): u8 {
        let mut total_score: u64 = 0;
        let mut count: u64 = 0;
        
        let validators = &session.assigned_validators;
        let mut i = 0;
        
        while (i < vector::length(validators)) {
            let validator = vector::borrow(validators, i);
            if (table::contains(&session.reviews, *validator)) {
                let review = table::borrow(&session.reviews, *validator);
                total_score = total_score + (review.score as u64);
                count = count + 1;
            };
            i = i + 1;
        };

        if (count > 0) {
            ((total_score / count) as u8)
        } else {
            0
        }
    }

    /// Distribute rewards to validators
    fun distribute_validation_rewards(
        session: &ValidationSession,
        config: &ValidationConfig,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext,
    ): u64 {
        let mut total_rewards = 0u64;
        let reward_per_review = config.reward_per_review;
        
        let validators = &session.assigned_validators;
        let mut i = 0;
        
        while (i < vector::length(validators)) {
            let validator = vector::borrow(validators, i);
            if (table::contains(&session.reviews, *validator)) {
                // Validator completed review - send reward
                let reward = treasury::withdraw_for_validation(
                    treasury,
                    reward_per_review,
                    *validator,
                    string::utf8(b"Validation Review"),
                    0, // performance_bonus
                    clock,
                    ctx
                );
                transfer::public_transfer(reward, *validator);
                total_rewards = total_rewards + reward_per_review;
            };
            i = i + 1;
        };

        total_rewards
    }

    /// Get required deposit based on content type
    fun get_required_deposit(content_type: u8, params: &GlobalParameters): u64 {
        if (content_type == CONTENT_TYPE_ARTICLE) {
            parameters::get_article_deposit_original(params)
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            parameters::get_project_deposit(params)
        } else if (content_type == CONTENT_TYPE_QUIZ) {
            parameters::get_quiz_creation_deposit(params)
        } else if (content_type == CONTENT_TYPE_EXAM) {
            parameters::get_exam_creation_deposit(params)
        } else {
            parameters::get_article_deposit_original(params) // Default
        }
    }

    /// Get validator count for content type
    fun get_validator_count(content_type: u8, config: &ValidationConfig): u8 {
        if (content_type == CONTENT_TYPE_ARTICLE) {
            config.article_validator_count
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            config.project_validator_count
        } else if (content_type == CONTENT_TYPE_QUIZ) {
            config.quiz_validator_count
        } else if (content_type == CONTENT_TYPE_EXAM) {
            config.exam_validator_count
        } else {
            config.collection_validator_count
        }
    }

    // =============== View Functions ===============
    
    /// Check if content is approved based on validation session
    public fun get_validation_result(session: &ValidationSession): bool {
        if (session.status != SESSION_STATUS_COMPLETED) {
            return false
        };
        
        // Calculate average score
        let mut total_score = 0u64;
        let mut count = 0u64;
        let validators = &session.assigned_validators;
        let mut i = 0;
        
        while (i < vector::length(validators)) {
            let validator = vector::borrow(validators, i);
            if (table::contains(&session.reviews, *validator)) {
                let review = table::borrow(&session.reviews, *validator);
                total_score = total_score + (review.score as u64);
                count = count + 1;
            };
            i = i + 1;
        };
        
        if (count > 0) {
            let avg_score = ((total_score / count) as u8);
            avg_score >= 70 // Default threshold
        } else {
            false
        }
    }

    /// Get session approval status
    public fun is_session_approved(session: &ValidationSession): bool {
        get_validation_result(session)
    }

    /// Get selection method for content type
    fun get_selection_method(content_type: u8, config: &ValidationConfig): u8 {
        if (content_type == CONTENT_TYPE_ARTICLE) {
            config.article_selection_method
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            config.project_selection_method
        } else if (content_type == CONTENT_TYPE_QUIZ) {
            config.quiz_selection_method
        } else if (content_type == CONTENT_TYPE_EXAM) {
            config.exam_selection_method
        } else {
            config.collection_selection_method
        }
    }

    /// Get approval threshold for content type
    fun get_approval_threshold(content_type: u8): u8 {
        if (content_type == CONTENT_TYPE_ARTICLE) {
            70
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            70
        } else if (content_type == CONTENT_TYPE_QUIZ) {
            80
        } else if (content_type == CONTENT_TYPE_EXAM) {
            90
        } else {
            75
        }
    }

    /// Get approval threshold from config
    fun get_approval_threshold_from_config(content_type: u8, config: &ValidationConfig): u8 {
        if (content_type == CONTENT_TYPE_ARTICLE) {
            config.article_approval_threshold
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            config.project_approval_threshold
        } else if (content_type == CONTENT_TYPE_QUIZ) {
            config.quiz_approval_threshold
        } else if (content_type == CONTENT_TYPE_EXAM) {
            config.exam_approval_threshold
        } else {
            config.collection_approval_threshold
        }
    }

    /// Hash seed for randomness

    // =============== Read Functions ===============
    
    public fun get_session_status(session: &ValidationSession): u8 {
        session.status
    }

    public fun get_session_final_score(session: &ValidationSession): Option<u8> {
        session.final_score
    }

    public fun get_deposit_status(deposit: &ContentDeposit): u8 {
        deposit.status
    }

    public fun get_config_thresholds(config: &ValidationConfig): (u8, u8, u8, u8, u8) {
        (
            config.article_approval_threshold,
            config.project_approval_threshold,
            config.quiz_approval_threshold,
            config.exam_approval_threshold,
            config.collection_approval_threshold
        )
    }

    public fun get_stats(stats: &ValidationStats): (u64, u64, u64, u64) {
        (
            stats.total_sessions,
            stats.completed_sessions,
            stats.total_deposits_collected,
            stats.total_rewards_distributed
        )
    }
}