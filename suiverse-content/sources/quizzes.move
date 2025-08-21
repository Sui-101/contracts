module suiverse_content::quizzes {
    use std::string::{Self, String};
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
    
    // Dependencies
    use suiverse_core::parameters::{Self, GlobalParameters};
    use suiverse_content::validation::{Self, ValidationReview};
    use suiverse_content::tags::{Self, TagRegistry, ContentTagMapping, TagStats};

    // =============== Constants ===============
    const E_INSUFFICIENT_DEPOSIT: u64 = 9001;
    const E_INVALID_DIFFICULTY: u64 = 9002;
    const E_INVALID_CATEGORY: u64 = 9003;
    const E_QUIZ_NOT_APPROVED: u64 = 9004;
    const E_NOT_CREATOR: u64 = 9005;
    const E_VARIATION_LIMIT_EXCEEDED: u64 = 9006;
    const E_INVALID_ANSWER_FORMAT: u64 = 9007;
    const E_QUIZ_LOCKED: u64 = 9008;
    const E_INVALID_ENCRYPTION: u64 = 9009;
    const E_VARIATION_GENERATION_FAILED: u64 = 9010;

    // Quiz status
    const STATUS_DRAFT: u8 = 0;
    const STATUS_PENDING: u8 = 1;
    const STATUS_APPROVED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_ARCHIVED: u8 = 4;

    // Difficulty levels
    const DIFFICULTY_BEGINNER: u8 = 1;
    const DIFFICULTY_INTERMEDIATE: u8 = 2;
    const DIFFICULTY_ADVANCED: u8 = 3;
    const DIFFICULTY_EXPERT: u8 = 4;

    // Answer formats
    const FORMAT_MULTIPLE_CHOICE: u8 = 1;
    const FORMAT_TRUE_FALSE: u8 = 2;
    const FORMAT_SHORT_ANSWER: u8 = 3;
    const FORMAT_NUMERIC: u8 = 4;

    // Variation constants
    const MAX_VARIATIONS_PER_QUIZ: u64 = 50;
    const VARIATION_COMPLEXITY_BASIC: u8 = 1;
    const VARIATION_COMPLEXITY_INTERMEDIATE: u8 = 2;
    const VARIATION_COMPLEXITY_ADVANCED: u8 = 3;

    // =============== Structs ===============
    
    /// Enhanced quiz with encryption and variation support
    public struct Quiz has key, store {
        id: UID,
        title: String,
        description: String,
        creator: address,
        
        // Encrypted content
        encrypted_content: vector<u8>, // Complete quiz in encrypted format
        content_hash: vector<u8>, // Hash for integrity verification
        encryption_version: u8,
        
        // Metadata
        category: String,
        difficulty: u8,
        answer_format: u8,
        tags: vector<ID>,
        
        // Variation system
        variation_count: u64,
        variation_complexity: u8,
        max_variations: u64,
        variation_seeds: vector<u64>,
        
        // Status and validation
        status: u8,
        deposit_amount: u64,
        validator_reviews: vector<ValidationReview>,
        
        // Usage and economics
        usage_count: u64,
        success_rate: u64,
        total_attempts: u64,
        earnings: Balance<SUI>,
        
        // Timestamps
        created_at: u64,
        updated_at: u64,
        approved_at: Option<u64>,
        
        // Additional metadata
        estimated_time: u64, // in seconds
        prerequisites: vector<ID>, // prerequisite quiz IDs
        learning_objectives: vector<String>,
    }

    /// Quiz variation parameters
    public struct VariationParams has store, copy, drop {
        seed: u64,
        complexity_level: u8,
        parameter_changes: vector<ParameterChange>,
        generated_at: u64,
    }

    /// Parameter change for variations
    public struct ParameterChange has store, copy, drop {
        parameter_type: u8, // 1: Number, 2: Text, 3: Option order
        old_value: vector<u8>,
        new_value: vector<u8>,
        change_weight: u8,
    }

    /// Quiz bundle for thematic grouping
    public struct QuizBundle has key, store {
        id: UID,
        title: String,
        description: String,
        creator: address,
        quiz_ids: vector<ID>,
        category: String,
        total_difficulty_score: u64,
        completion_certificate_id: Option<ID>,
        bundle_type: u8, // 1: Course, 2: Assessment, 3: Practice
        created_at: u64,
    }

    /// Quiz usage analytics
    public struct QuizAnalytics has key {
        id: UID,
        quiz_usage: Table<ID, QuizUsageData>,
        daily_stats: Table<u64, DailyQuizStats>,
        trending_quizzes: vector<TrendingQuiz>,
        difficulty_distribution: Table<u8, u64>,
        category_performance: Table<String, CategoryPerformance>,
    }

    /// Individual quiz usage data
    public struct QuizUsageData has store {
        quiz_id: ID,
        total_attempts: u64,
        unique_users: u64,
        success_rate: u64,
        average_time: u64,
        difficulty_rating: u8,
        user_feedback_score: u64,
        last_used: u64,
    }

    /// Daily quiz statistics
    public struct DailyQuizStats has store {
        date: u64,
        quizzes_created: u64,
        quizzes_attempted: u64,
        unique_users: u64,
        total_success_rate: u64,
        total_earnings_distributed: u64,
    }

    /// Trending quiz information
    public struct TrendingQuiz has store, copy, drop {
        quiz_id: ID,
        title: String,
        category: String,
        usage_growth: u64,
        success_rate: u64,
        period_start: u64,
        period_end: u64,
    }

    /// Category performance metrics
    public struct CategoryPerformance has store {
        category: String,
        total_quizzes: u64,
        average_success_rate: u64,
        total_attempts: u64,
        trending_score: u64,
        last_updated: u64,
    }

    // =============== Events ===============
    
    public struct QuizCreated has copy, drop {
        quiz_id: ID,
        creator: address,
        title: String,
        category: String,
        difficulty: u8,
        deposit_amount: u64,
        estimated_time: u64,
        timestamp: u64,
    }

    public struct QuizApproved has copy, drop {
        quiz_id: ID,
        final_score: u8,
        validator_count: u64,
        timestamp: u64,
    }

    public struct QuizVariationGenerated has copy, drop {
        quiz_id: ID,
        variation_seed: u64,
        complexity_level: u8,
        parameter_count: u64,
        timestamp: u64,
    }

    public struct QuizAttempted has copy, drop {
        quiz_id: ID,
        user: address,
        variation_seed: u64,
        correct: bool,
        time_taken: u64,
        timestamp: u64,
    }

    public struct QuizBundleCreated has copy, drop {
        bundle_id: ID,
        creator: address,
        title: String,
        quiz_count: u64,
        bundle_type: u8,
        timestamp: u64,
    }

    public struct QuizEarningsDistributed has copy, drop {
        quiz_id: ID,
        creator: address,
        amount: u64,
        usage_count: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let analytics = QuizAnalytics {
            id: object::new(ctx),
            quiz_usage: table::new(ctx),
            daily_stats: table::new(ctx),
            trending_quizzes: vector::empty(),
            difficulty_distribution: table::new(ctx),
            category_performance: table::new(ctx),
        };
        
        transfer::share_object(analytics);
    }

    // =============== Public Entry Functions ===============
    
    /// Create a new quiz with encryption
    public entry fun create_quiz(
        title: String,
        description: String,
        quiz_content: vector<u8>, // JSON or structured content
        category: String,
        difficulty: u8,
        answer_format: u8,
        tags: vector<ID>,
        estimated_time: u64,
        learning_objectives: vector<String>,
        prerequisites: vector<ID>,
        max_variations: u64,
        deposit: Coin<SUI>,
        params: &GlobalParameters,
        analytics: &mut QuizAnalytics,
        tag_registry: &mut TagRegistry,
        tag_mapping: &mut ContentTagMapping,
        tag_stats: &mut TagStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        
        // Validate inputs
        assert!(string::length(&title) > 0 && string::length(&title) <= 200, E_INVALID_CATEGORY);
        assert!(difficulty >= DIFFICULTY_BEGINNER && difficulty <= DIFFICULTY_EXPERT, E_INVALID_DIFFICULTY);
        assert!(answer_format >= FORMAT_MULTIPLE_CHOICE && answer_format <= FORMAT_NUMERIC, E_INVALID_ANSWER_FORMAT);
        assert!(vector::length(&quiz_content) > 0, E_INVALID_ENCRYPTION);
        assert!(max_variations <= MAX_VARIATIONS_PER_QUIZ, E_VARIATION_LIMIT_EXCEEDED);
        
        // Check deposit amount
        let required_deposit = parameters::get_quiz_creation_deposit(params);
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);
        
        // Encrypt quiz content
        let encryption_seed = generate_encryption_seed(creator, clock);
        let encrypted_content = encrypt_quiz_content(&quiz_content, encryption_seed);
        let content_hash = bcs::to_bytes(&quiz_content); // Simplified hash for now
        
        // Create quiz
        let quiz = Quiz {
            id: object::new(ctx),
            title,
            description,
            creator,
            encrypted_content,
            content_hash,
            encryption_version: 1,
            category,
            difficulty,
            answer_format,
            tags,
            variation_count: 0,
            variation_complexity: VARIATION_COMPLEXITY_BASIC,
            max_variations,
            variation_seeds: vector::empty(),
            status: STATUS_PENDING,
            deposit_amount: coin::value(&deposit),
            validator_reviews: vector::empty(),
            usage_count: 0,
            success_rate: 0,
            total_attempts: 0,
            earnings: balance::zero(),
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
            approved_at: option::none(),
            estimated_time,
            prerequisites,
            learning_objectives,
        };
        
        let quiz_id = object::uid_to_inner(&quiz.id);
        
        // Add tags to content
        if (vector::length(&tags) > 0) {
            tags::add_tags_to_content(
                quiz_id,
                tags,
                3, // CONTENT_TYPE_QUIZ
                tag_registry,
                tag_mapping,
                tag_stats,
                clock,
                ctx
            );
        };
        
        // Update analytics
        update_analytics_on_creation(analytics, &quiz, clock);
        
        // Store deposit
        transfer::public_transfer(deposit, @suiverse_content);
        
        event::emit(QuizCreated {
            quiz_id,
            creator,
            title: quiz.title,
            category: quiz.category,
            difficulty,
            deposit_amount: quiz.deposit_amount,
            estimated_time,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::share_object(quiz);
    }

    /// Generate quiz variation
    public entry fun generate_quiz_variation(
        quiz: &mut Quiz,
        complexity_level: u8,
        analytics: &mut QuizAnalytics,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(quiz.status == STATUS_APPROVED, E_QUIZ_NOT_APPROVED);
        assert!(quiz.variation_count < quiz.max_variations, E_VARIATION_LIMIT_EXCEEDED);
        
        // Generate variation seed
        let variation_seed = generate_variation_seed(
            object::uid_to_inner(&quiz.id),
            complexity_level,
            clock::timestamp_ms(clock),
            tx_context::sender(ctx)
        );
        
        // Create variation parameters
        let variation_params = create_variation_parameters(
            variation_seed,
            complexity_level,
            &quiz.encrypted_content
        );
        
        // Store variation seed
        vector::push_back(&mut quiz.variation_seeds, variation_seed);
        quiz.variation_count = quiz.variation_count + 1;
        quiz.variation_complexity = if (complexity_level > quiz.variation_complexity) {
            complexity_level
        } else {
            quiz.variation_complexity
        };
        quiz.updated_at = clock::timestamp_ms(clock);
        
        event::emit(QuizVariationGenerated {
            quiz_id: object::uid_to_inner(&quiz.id),
            variation_seed,
            complexity_level,
            parameter_count: vector::length(&variation_params.parameter_changes),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Attempt a quiz (with variation)
    public entry fun attempt_quiz(
        quiz: &mut Quiz,
        variation_seed: Option<u64>,
        user_answers: vector<u8>, // Encrypted user answers
        time_taken: u64,
        analytics: &mut QuizAnalytics,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(quiz.status == STATUS_APPROVED, E_QUIZ_NOT_APPROVED);
        
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Determine variation seed
        let actual_seed = if (option::is_some(&variation_seed)) {
            let seed = *option::borrow(&variation_seed);
            assert!(vector::contains(&quiz.variation_seeds, &seed), E_VARIATION_GENERATION_FAILED);
            seed
        } else {
            // Use base quiz (seed 0)
            0
        };
        
        // Verify answers (simplified - in production would decrypt and compare)
        let correct = verify_quiz_answers(&quiz.encrypted_content, &user_answers, actual_seed);
        
        // Update quiz statistics
        quiz.total_attempts = quiz.total_attempts + 1;
        quiz.usage_count = quiz.usage_count + 1;
        
        if (correct) {
            // Update success rate
            let previous_correct = (quiz.success_rate * (quiz.total_attempts - 1)) / 100;
            quiz.success_rate = ((previous_correct + 100) * 100) / quiz.total_attempts;
        } else {
            let previous_correct = (quiz.success_rate * (quiz.total_attempts - 1)) / 100;
            quiz.success_rate = (previous_correct * 100) / quiz.total_attempts;
        };
        
        quiz.updated_at = current_time;
        
        // Update analytics
        update_analytics_on_attempt(analytics, quiz, user, correct, time_taken, current_time);
        
        event::emit(QuizAttempted {
            quiz_id: object::uid_to_inner(&quiz.id),
            user,
            variation_seed: actual_seed,
            correct,
            time_taken,
            timestamp: current_time,
        });
    }

    /// Create quiz bundle
    public entry fun create_quiz_bundle(
        title: String,
        description: String,
        quiz_ids: vector<ID>,
        bundle_type: u8,
        analytics: &mut QuizAnalytics,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        
        // Calculate total difficulty score
        let total_difficulty_score = vector::length(&quiz_ids) * 100; // Simplified calculation
        
        let bundle = QuizBundle {
            id: object::new(ctx),
            title,
            description,
            creator,
            quiz_ids,
            category: string::utf8(b"Bundle"),
            total_difficulty_score,
            completion_certificate_id: option::none(),
            bundle_type,
            created_at: clock::timestamp_ms(clock),
        };
        
        let bundle_id = object::uid_to_inner(&bundle.id);
        
        event::emit(QuizBundleCreated {
            bundle_id,
            creator,
            title: bundle.title,
            quiz_count: vector::length(&bundle.quiz_ids),
            bundle_type,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::share_object(bundle);
    }

    /// Update quiz after validation
    public fun update_quiz_validation_status(
        quiz: &mut Quiz,
        approved: bool,
        final_score: u8,
        validator_count: u64,
        analytics: &mut QuizAnalytics,
        clock: &Clock,
    ) {
        if (approved) {
            quiz.status = STATUS_APPROVED;
            quiz.approved_at = option::some(clock::timestamp_ms(clock));
            
            // Update analytics
            update_difficulty_distribution(analytics, quiz.difficulty, true);
            
            event::emit(QuizApproved {
                quiz_id: object::uid_to_inner(&quiz.id),
                final_score,
                validator_count,
                timestamp: clock::timestamp_ms(clock),
            });
        } else {
            quiz.status = STATUS_REJECTED;
        };
        
        quiz.updated_at = clock::timestamp_ms(clock);
    }

    /// Distribute earnings to quiz creator (package access)
    public(package) fun distribute_quiz_earnings(
        quiz: &mut Quiz,
        earnings: Balance<SUI>,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        // This would be called by the rewards system
        let amount = balance::value(&earnings);
        balance::join(&mut quiz.earnings, earnings);
        
        event::emit(QuizEarningsDistributed {
            quiz_id: object::uid_to_inner(&quiz.id),
            creator: quiz.creator,
            amount,
            usage_count: quiz.usage_count,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Withdraw quiz earnings
    public entry fun withdraw_quiz_earnings(
        quiz: &mut Quiz,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        assert!(quiz.creator == creator, E_NOT_CREATOR);
        
        let amount = balance::value(&quiz.earnings);
        if (amount > 0) {
            let earnings = balance::withdraw_all(&mut quiz.earnings);
            let earnings_coin = coin::from_balance(earnings, ctx);
            transfer::public_transfer(earnings_coin, creator);
        }
    }

    // =============== Internal Functions ===============
    
    /// Generate encryption seed
    fun generate_encryption_seed(creator: address, clock: &Clock): u64 {
        let creator_bytes = bcs::to_bytes(&creator);
        let time_bytes = bcs::to_bytes(&clock::timestamp_ms(clock));
        
        let mut combined = vector::empty<u8>();
        vector::append(&mut combined, creator_bytes);
        vector::append(&mut combined, time_bytes);
        
        let combined_length = vector::length(&combined);
        
        // Simple hash function using length and first few bytes
        let mut seed = (combined_length as u64);
        let mut i = 0;
        while (i < 8 && i < combined_length) {
            seed = (seed << 8) + (*vector::borrow(&combined, i) as u64);
            i = i + 1;
        };
        
        seed
    }

    /// Encrypt quiz content
    fun encrypt_quiz_content(content: &vector<u8>, seed: u64): vector<u8> {
        let mut encrypted = vector::empty<u8>();
        let key_bytes = bcs::to_bytes(&seed);
        let key_len = vector::length(&key_bytes);
        
        let mut i = 0;
        while (i < vector::length(content)) {
            let byte = *vector::borrow(content, i);
            let key_byte = *vector::borrow(&key_bytes, i % key_len);
            vector::push_back(&mut encrypted, byte ^ key_byte);
            i = i + 1;
        };
        
        encrypted
    }

    /// Generate variation seed
    fun generate_variation_seed(quiz_id: ID, complexity: u8, timestamp: u64, user: address): u64 {
        let mut combined = vector::empty<u8>();
        vector::append(&mut combined, bcs::to_bytes(&quiz_id));
        vector::append(&mut combined, bcs::to_bytes(&complexity));
        vector::append(&mut combined, bcs::to_bytes(&timestamp));
        vector::append(&mut combined, bcs::to_bytes(&user));
        
        let combined_length = vector::length(&combined);
        
        // Simple hash using combined data
        let mut seed = (combined_length as u64);
        let mut i = 0;
        while (i < 8 && i < combined_length) {
            seed = (seed << 8) + (*vector::borrow(&combined, i) as u64);
            i = i + 1;
        };
        
        seed
    }

    /// Create variation parameters
    fun create_variation_parameters(seed: u64, complexity: u8, _content: &vector<u8>): VariationParams {
        let mut parameter_changes = vector::empty<ParameterChange>();
        
        // Generate parameter changes based on complexity
        let change_count = if (complexity == VARIATION_COMPLEXITY_BASIC) { 1 }
                          else if (complexity == VARIATION_COMPLEXITY_INTERMEDIATE) { 3 }
                          else { 5 };
        
        let mut i = 0;
        while (i < change_count) {
            let change = ParameterChange {
                parameter_type: ((seed + (i as u64)) % 3 + 1) as u8,
                old_value: vector::empty(),
                new_value: vector::empty(),
                change_weight: ((seed + (i as u64)) % 100) as u8,
            };
            vector::push_back(&mut parameter_changes, change);
            i = i + 1;
        };
        
        VariationParams {
            seed,
            complexity_level: complexity,
            parameter_changes,
            generated_at: 0, // Would use current timestamp in production
        }
    }

    /// Verify quiz answers (simplified implementation)
    fun verify_quiz_answers(_encrypted_content: &vector<u8>, _user_answers: &vector<u8>, _seed: u64): bool {
        // In production, this would decrypt content, apply variation, and compare answers
        // For now, return random result based on seed
        (_seed % 3) != 0 // 66% success rate for testing
    }

    /// Update analytics on quiz creation
    fun update_analytics_on_creation(analytics: &mut QuizAnalytics, quiz: &Quiz, clock: &Clock) {
        let current_day = clock::timestamp_ms(clock) / 86400000;
        
        // Update daily stats
        if (!table::contains(&analytics.daily_stats, current_day)) {
            let daily_stats = DailyQuizStats {
                date: current_day,
                quizzes_created: 0,
                quizzes_attempted: 0,
                unique_users: 0,
                total_success_rate: 0,
                total_earnings_distributed: 0,
            };
            table::add(&mut analytics.daily_stats, current_day, daily_stats);
        };
        
        let daily_stats = table::borrow_mut(&mut analytics.daily_stats, current_day);
        daily_stats.quizzes_created = daily_stats.quizzes_created + 1;
        
        // Update difficulty distribution
        update_difficulty_distribution(analytics, quiz.difficulty, false);
    }

    /// Update analytics on quiz attempt
    fun update_analytics_on_attempt(
        analytics: &mut QuizAnalytics,
        quiz: &Quiz,
        _user: address,
        correct: bool,
        time_taken: u64,
        timestamp: u64
    ) {
        let quiz_id = object::uid_to_inner(&quiz.id);
        let current_day = timestamp / 86400000;
        
        // Update quiz usage data
        if (!table::contains(&analytics.quiz_usage, quiz_id)) {
            let usage_data = QuizUsageData {
                quiz_id,
                total_attempts: 0,
                unique_users: 0,
                success_rate: 0,
                average_time: 0,
                difficulty_rating: quiz.difficulty,
                user_feedback_score: 50, // Default neutral score
                last_used: timestamp,
            };
            table::add(&mut analytics.quiz_usage, quiz_id, usage_data);
        };
        
        let usage_data = table::borrow_mut(&mut analytics.quiz_usage, quiz_id);
        usage_data.total_attempts = usage_data.total_attempts + 1;
        usage_data.last_used = timestamp;
        
        // Update average time
        usage_data.average_time = ((usage_data.average_time * (usage_data.total_attempts - 1)) + time_taken) / usage_data.total_attempts;
        
        // Update success rate
        if (correct) {
            let previous_correct = (usage_data.success_rate * (usage_data.total_attempts - 1)) / 100;
            usage_data.success_rate = ((previous_correct + 100) * 100) / usage_data.total_attempts;
        } else {
            let previous_correct = (usage_data.success_rate * (usage_data.total_attempts - 1)) / 100;
            usage_data.success_rate = (previous_correct * 100) / usage_data.total_attempts;
        };
        
        // Update daily stats
        if (!table::contains(&analytics.daily_stats, current_day)) {
            let daily_stats = DailyQuizStats {
                date: current_day,
                quizzes_created: 0,
                quizzes_attempted: 0,
                unique_users: 0,
                total_success_rate: 0,
                total_earnings_distributed: 0,
            };
            table::add(&mut analytics.daily_stats, current_day, daily_stats);
        };
        
        let daily_stats = table::borrow_mut(&mut analytics.daily_stats, current_day);
        daily_stats.quizzes_attempted = daily_stats.quizzes_attempted + 1;
    }

    /// Update difficulty distribution
    fun update_difficulty_distribution(analytics: &mut QuizAnalytics, difficulty: u8, approved: bool) {
        if (approved) {
            if (table::contains(&analytics.difficulty_distribution, difficulty)) {
                let count = table::borrow_mut(&mut analytics.difficulty_distribution, difficulty);
                *count = *count + 1;
            } else {
                table::add(&mut analytics.difficulty_distribution, difficulty, 1);
            };
        }
    }

    // =============== View Functions ===============
    
    public fun get_quiz_status(quiz: &Quiz): u8 {
        quiz.status
    }

    public fun get_quiz_difficulty(quiz: &Quiz): u8 {
        quiz.difficulty
    }

    public fun get_quiz_category(quiz: &Quiz): String {
        quiz.category
    }

    public fun get_quiz_usage_stats(quiz: &Quiz): (u64, u64, u64) {
        (quiz.usage_count, quiz.total_attempts, quiz.success_rate)
    }

    public fun get_quiz_variation_count(quiz: &Quiz): u64 {
        quiz.variation_count
    }

    public fun get_quiz_earnings(quiz: &Quiz): u64 {
        balance::value(&quiz.earnings)
    }

    public fun is_quiz_approved(quiz: &Quiz): bool {
        quiz.status == STATUS_APPROVED
    }

    public fun get_quiz_prerequisites(quiz: &Quiz): &vector<ID> {
        &quiz.prerequisites
    }

    public fun get_quiz_learning_objectives(quiz: &Quiz): &vector<String> {
        &quiz.learning_objectives
    }

    public fun get_bundle_quizzes(bundle: &QuizBundle): &vector<ID> {
        &bundle.quiz_ids
    }

    public fun get_bundle_type(bundle: &QuizBundle): u8 {
        bundle.bundle_type
    }

    public fun get_analytics_summary(analytics: &QuizAnalytics): (u64, u64) {
        (
            table::length(&analytics.quiz_usage),
            vector::length(&analytics.trending_quizzes)
        )
    }
}