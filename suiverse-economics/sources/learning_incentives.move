/// Advanced Learning Incentives Module
/// 
/// Provides sophisticated learning progression mechanics, peer mentoring economics,
/// and gamified incentive systems that complement the existing basic reward distribution.
/// Focuses on behavioral psychology and long-term engagement patterns.
module suiverse_economics::learning_incentives {
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self as vec_map, VecMap};
    use suiverse_economics::config_manager::{Self, ConfigManager};

    // === Constants ===
    const BASE_LEARNING_REWARD: u64 = 10_000_000; // 0.01 SUI base learning reward
    const STREAK_BONUS_MULTIPLIER: u64 = 5; // 5% per day streak
    const MAX_STREAK_BONUS: u64 = 200; // 200% max streak bonus
    const MENTORING_BASE_REWARD: u64 = 50_000_000; // 0.05 SUI per mentoring session
    const PEER_REVIEW_REWARD: u64 = 5_000_000; // 0.005 SUI per review
    const MILESTONE_REWARD_MULTIPLIER: u64 = 1000; // 10x for milestones
    const COMMUNITY_CONTRIBUTION_BONUS: u64 = 20; // 20% bonus for community activities
    const SKILL_MASTERY_BONUS: u64 = 500; // 5x bonus for skill mastery
    const CROSS_DOMAIN_LEARNING_BONUS: u64 = 150; // 1.5x for cross-domain learning
    const TEACHING_EFFECTIVENESS_THRESHOLD: u64 = 80; // 80% student success rate for bonuses
    const LEARNING_VELOCITY_BONUS: u64 = 100; // 1x bonus for fast learning
    const KNOWLEDGE_RETENTION_BONUS: u64 = 75; // 0.75x bonus for retention
    const SOCIAL_LEARNING_MULTIPLIER: u64 = 125; // 1.25x for group learning

    // === Error Codes ===
    const E_INVALID_LEARNING_SESSION: u64 = 1;
    const E_INSUFFICIENT_PROGRESS: u64 = 2;
    const E_MENTORING_SESSION_NOT_FOUND: u64 = 3;
    const E_UNAUTHORIZED_CLAIM: u64 = 4;
    const E_STREAK_BROKEN: u64 = 5;
    const E_INVALID_SKILL_LEVEL: u64 = 6;
    const E_MILESTONE_NOT_REACHED: u64 = 7;
    const E_COOLDOWN_ACTIVE: u64 = 8;
    const E_INVALID_PEER_REVIEW: u64 = 9;
    const E_INSUFFICIENT_FUNDS: u64 = 10;
    const E_CONFIG_MANAGER_NOT_AVAILABLE: u64 = 11;
    const E_CLOCK_NOT_CONFIGURED: u64 = 12;

    // === Structs ===

    /// Learning progression tracker for individual users
    public struct LearningProgress has store {
        user: address,
        current_streak: u64,
        longest_streak: u64,
        last_activity: u64,
        total_learning_hours: u64,
        completed_courses: u64,
        skill_levels: VecMap<String, u64>, // skill -> level (0-100)
        learning_velocity: u64, // concepts per hour
        retention_score: u64, // percentage retained over time
        cross_domain_activities: u64,
        milestone_achievements: vector<String>,
        last_reward_claim: u64,
    }

    /// Mentoring session economics and tracking
    public struct MentoringSession has key, store {
        id: UID,
        mentor: address,
        mentee: address,
        subject_area: String,
        duration_hours: u64,
        mentor_rating: u64, // 1-100
        mentee_progress: u64, // 1-100
        session_effectiveness: u64, // calculated metric
        completed_at: u64,
        payment_claimed: bool,
        bonus_eligible: bool,
    }

    /// Peer review system for content validation
    public struct PeerReview has store {
        reviewer: address,
        content_id: ID,
        quality_score: u64, // 1-100
        detailed_feedback: bool,
        helpful_votes: u64,
        review_timestamp: u64,
        reward_claimed: bool,
    }

    /// Skill mastery achievement tracking
    public struct SkillMastery has store {
        skill_name: String,
        user: address,
        mastery_level: u64, // 1-100
        validation_method: String, // "exam", "project", "peer_validation"
        validator_count: u64,
        achieved_at: u64,
        certification_id: Option<ID>,
    }

    /// Learning cohort for group activities
    public struct LearningCohort has key, store {
        id: UID,
        name: String,
        members: vector<address>,
        coordinator: address,
        subject_areas: vector<String>,
        created_at: u64,
        completion_rate: u64,
        group_performance_score: u64,
        reward_pool: Balance<SUI>,
    }

    /// Global incentive system registry
    public struct IncentiveRegistry has key, store {
        id: UID,
        user_progress: Table<address, LearningProgress>,
        active_mentoring: Table<ID, MentoringSession>,
        peer_reviews: Table<ID, vector<PeerReview>>,
        skill_masteries: Table<address, vector<SkillMastery>>,
        learning_cohorts: Table<ID, LearningCohort>,
        total_rewards_distributed: u64,
        incentive_pool: Balance<SUI>,
        admin_cap: ID,
        system_active: bool,
    }

    /// Milestone achievement definition
    public struct Milestone has store {
        name: String,
        description: String,
        requirements: VecMap<String, u64>, // requirement -> threshold
        reward_multiplier: u64,
        badge_id: Option<ID>,
        is_repeatable: bool,
    }

    /// Behavioral economics parameters
    public struct BehaviorParameters has store {
        diminishing_returns_factor: u64, // Prevents reward farming
        social_proof_bonus: u64, // Bonus for community engagement
        commitment_device_reward: u64, // Reward for setting learning goals
        loss_aversion_penalty: u64, // Penalty for breaking streaks
        gamification_multiplier: u64, // Boost for competitive elements
        intrinsic_motivation_bonus: u64, // Bonus for self-directed learning
    }

    /// Admin capability for incentive management
    public struct IncentiveAdminCap has key, store {
        id: UID,
    }

    // === Events ===

    public struct LearningRewardClaimedEvent has copy, drop {
        user: address,
        reward_type: String,
        base_amount: u64,
        bonus_amount: u64,
        total_reward: u64,
        streak_count: u64,
        timestamp: u64,
    }

    public struct MentoringCompletedEvent has copy, drop {
        session_id: ID,
        mentor: address,
        mentee: address,
        effectiveness_score: u64,
        mentor_reward: u64,
        mentee_progress_bonus: u64,
        timestamp: u64,
    }

    public struct SkillMasteryAchievedEvent has copy, drop {
        user: address,
        skill_name: String,
        mastery_level: u64,
        validation_method: String,
        reward_amount: u64,
        certification_id: Option<ID>,
        timestamp: u64,
    }

    public struct MilestoneReachedEvent has copy, drop {
        user: address,
        milestone_name: String,
        achievement_count: u64,
        reward_multiplier: u64,
        total_reward: u64,
        timestamp: u64,
    }

    public struct CohortCompletedEvent has copy, drop {
        cohort_id: ID,
        completion_rate: u64,
        group_performance: u64,
        members_count: u64,
        reward_per_member: u64,
        timestamp: u64,
    }

    // === Initialize Function ===

    fun init(ctx: &mut TxContext) {
        let admin_cap = IncentiveAdminCap {
            id: object::new(ctx),
        };

        let registry = IncentiveRegistry {
            id: object::new(ctx),
            user_progress: table::new(ctx),
            active_mentoring: table::new(ctx),
            peer_reviews: table::new(ctx),
            skill_masteries: table::new(ctx),
            learning_cohorts: table::new(ctx),
            total_rewards_distributed: 0,
            incentive_pool: balance::zero(),
            admin_cap: object::id(&admin_cap),
            system_active: true,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry);
    }

    // === Core Learning Functions ===

    /// Record learning activity and calculate progressive rewards
    public entry fun record_learning_activity(
        registry: &mut IncentiveRegistry,
        subject_area: String,
        learning_hours: u64,
        concepts_learned: u64,
        retention_test_score: u64,
        is_cross_domain: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.system_active, E_INVALID_LEARNING_SESSION);
        assert!(learning_hours > 0 && concepts_learned > 0, E_INSUFFICIENT_PROGRESS);

        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Get or create user progress
        if (!table::contains(&registry.user_progress, user)) {
            let new_progress = LearningProgress {
                user,
                current_streak: 0,
                longest_streak: 0,
                last_activity: 0,
                total_learning_hours: 0,
                completed_courses: 0,
                skill_levels: vec_map::empty(),
                learning_velocity: 0,
                retention_score: 50, // Start with neutral retention
                cross_domain_activities: 0,
                milestone_achievements: vector::empty(),
                last_reward_claim: 0,
            };
            table::add(&mut registry.user_progress, user, new_progress);
        };

        let progress = table::borrow_mut(&mut registry.user_progress, user);

        // Update streak calculation
        let hours_since_last = (current_time - progress.last_activity) / (3600 * 1000);
        if (hours_since_last <= 48) { // Within 48 hours maintains streak
            progress.current_streak = progress.current_streak + 1;
        } else {
            progress.current_streak = 1; // Reset streak
        };

        if (progress.current_streak > progress.longest_streak) {
            progress.longest_streak = progress.current_streak;
        };

        // Update learning metrics
        progress.total_learning_hours = progress.total_learning_hours + learning_hours;
        progress.learning_velocity = concepts_learned / learning_hours;
        progress.retention_score = (progress.retention_score + retention_test_score) / 2;
        progress.last_activity = current_time;

        // Update skill level
        if (!vec_map::contains(&progress.skill_levels, &subject_area)) {
            vec_map::insert(&mut progress.skill_levels, subject_area, 0);
        };
        let current_level = vec_map::get_mut(&mut progress.skill_levels, &subject_area);
        *current_level = std::u64::min(100, *current_level + concepts_learned);

        if (is_cross_domain) {
            progress.cross_domain_activities = progress.cross_domain_activities + 1;
        };

        // Calculate and distribute reward
        let reward_amount = calculate_learning_reward(progress, learning_hours, is_cross_domain);
        distribute_learning_reward(registry, user, reward_amount, progress.current_streak, clock, ctx);
    }

    /// Complete a mentoring session with economic incentives
    public entry fun complete_mentoring_session(
        registry: &mut IncentiveRegistry,
        session_id: ID,
        mentor_rating: u64,
        mentee_progress_score: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&registry.active_mentoring, session_id), E_MENTORING_SESSION_NOT_FOUND);
        assert!(mentor_rating >= 1 && mentor_rating <= 100, E_INVALID_PEER_REVIEW);
        assert!(mentee_progress_score >= 1 && mentee_progress_score <= 100, E_INSUFFICIENT_PROGRESS);

        let session = table::borrow_mut(&mut registry.active_mentoring, session_id);
        let current_time = clock::timestamp_ms(clock);

        // Only mentor or mentee can complete
        let caller = tx_context::sender(ctx);
        assert!(caller == session.mentor || caller == session.mentee, E_UNAUTHORIZED_CLAIM);

        // Extract the addresses we need before other registry operations
        let mentor_address = session.mentor;
        let mentee_address = session.mentee;
        
        session.mentor_rating = mentor_rating;
        session.mentee_progress = mentee_progress_score;
        session.completed_at = current_time;

        // Calculate session effectiveness
        let session_effectiveness = (mentor_rating + mentee_progress_score) / 2;
        session.session_effectiveness = session_effectiveness;
        session.bonus_eligible = session_effectiveness >= TEACHING_EFFECTIVENESS_THRESHOLD;

        // Calculate rewards
        let base_mentor_reward = MENTORING_BASE_REWARD * session.duration_hours;
        let effectiveness_bonus = if (session.bonus_eligible) {
            base_mentor_reward * COMMUNITY_CONTRIBUTION_BONUS / 100
        } else { 0 };

        let mentor_reward = base_mentor_reward + effectiveness_bonus;
        let mentee_progress_bonus = (BASE_LEARNING_REWARD * mentee_progress_score) / 100;

        session.payment_claimed = true;
        
        // End the borrow of session before calling distribute_mentoring_rewards
        
        // Distribute rewards
        distribute_mentoring_rewards(
            registry,
            mentor_address,
            mentee_address,
            mentor_reward,
            mentee_progress_bonus,
            clock,
            ctx
        );

        event::emit(MentoringCompletedEvent {
            session_id,
            mentor: mentor_address,
            mentee: mentee_address,
            effectiveness_score: session_effectiveness,
            mentor_reward,
            mentee_progress_bonus,
            timestamp: current_time,
        });
    }

    /// Submit peer review and earn rewards
    public entry fun submit_peer_review(
        registry: &mut IncentiveRegistry,
        content_id: ID,
        quality_score: u64,
        detailed_feedback: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.system_active, E_INVALID_LEARNING_SESSION);
        assert!(quality_score >= 1 && quality_score <= 100, E_INVALID_PEER_REVIEW);

        let reviewer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        let review = PeerReview {
            reviewer,
            content_id,
            quality_score,
            detailed_feedback,
            helpful_votes: 0,
            review_timestamp: current_time,
            reward_claimed: false,
        };

        // Add to reviews table
        if (!table::contains(&registry.peer_reviews, content_id)) {
            table::add(&mut registry.peer_reviews, content_id, vector::empty());
        };
        let reviews = table::borrow_mut(&mut registry.peer_reviews, content_id);
        vector::push_back(reviews, review);

        // Calculate review reward
        let base_reward = PEER_REVIEW_REWARD;
        let quality_bonus = (base_reward * quality_score) / 100;
        let detail_bonus = if (detailed_feedback) { base_reward / 2 } else { 0 };
        let total_reward = base_reward + quality_bonus + detail_bonus;

        // Distribute reward
        distribute_peer_review_reward(registry, reviewer, total_reward, clock, ctx);
    }

    /// Achieve skill mastery and claim rewards
    public entry fun claim_skill_mastery(
        registry: &mut IncentiveRegistry,
        skill_name: String,
        mastery_level: u64,
        validation_method: String,
        validator_addresses: vector<address>,
        certification_id: Option<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(mastery_level >= 80 && mastery_level <= 100, E_INVALID_SKILL_LEVEL);
        assert!(vector::length(&validator_addresses) >= 3, E_INSUFFICIENT_PROGRESS);

        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        let mastery = SkillMastery {
            skill_name,
            user,
            mastery_level,
            validation_method,
            validator_count: vector::length(&validator_addresses),
            achieved_at: current_time,
            certification_id,
        };

        // Add to user's masteries
        if (!table::contains(&registry.skill_masteries, user)) {
            table::add(&mut registry.skill_masteries, user, vector::empty());
        };
        let masteries = table::borrow_mut(&mut registry.skill_masteries, user);
        vector::push_back(masteries, mastery);

        // Calculate mastery reward
        let base_reward = BASE_LEARNING_REWARD * SKILL_MASTERY_BONUS / 100;
        let mastery_bonus = (base_reward * mastery_level) / 100;
        let validator_bonus = (base_reward * vector::length(&validator_addresses)) / 10;
        let total_reward = base_reward + mastery_bonus + validator_bonus;

        // Distribute reward
        distribute_skill_mastery_reward(registry, user, total_reward, clock, ctx);

        event::emit(SkillMasteryAchievedEvent {
            user,
            skill_name,
            mastery_level,
            validation_method,
            reward_amount: total_reward,
            certification_id,
            timestamp: current_time,
        });
    }

    /// Create learning cohort for group incentives
    public entry fun create_learning_cohort(
        registry: &mut IncentiveRegistry,
        name: String,
        subject_areas: vector<String>,
        initial_funding: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.system_active, E_INVALID_LEARNING_SESSION);
        assert!(vector::length(&subject_areas) > 0, E_INSUFFICIENT_PROGRESS);

        let cohort = LearningCohort {
            id: object::new(ctx),
            name,
            members: vector::empty(),
            coordinator: tx_context::sender(ctx),
            subject_areas,
            created_at: clock::timestamp_ms(clock),
            completion_rate: 0,
            group_performance_score: 0,
            reward_pool: coin::into_balance(initial_funding),
        };

        let cohort_id = object::id(&cohort);
        table::add(&mut registry.learning_cohorts, cohort_id, cohort);
    }

    // === Private Helper Functions ===

    fun calculate_learning_reward(
        progress: &LearningProgress,
        learning_hours: u64,
        is_cross_domain: bool,
    ): u64 {
        let mut base_reward = BASE_LEARNING_REWARD * learning_hours;

        // Streak bonus
        let streak_bonus = std::u64::min(
            MAX_STREAK_BONUS,
            progress.current_streak * STREAK_BONUS_MULTIPLIER
        );
        base_reward = base_reward + (base_reward * streak_bonus / 100);

        // Learning velocity bonus
        if (progress.learning_velocity > 5) { // Fast learner
            base_reward = base_reward + (base_reward * LEARNING_VELOCITY_BONUS / 100);
        };

        // Retention bonus
        if (progress.retention_score > 80) {
            base_reward = base_reward + (base_reward * KNOWLEDGE_RETENTION_BONUS / 100);
        };

        // Cross-domain learning bonus
        if (is_cross_domain) {
            base_reward = base_reward + (base_reward * CROSS_DOMAIN_LEARNING_BONUS / 100);
        };

        base_reward
    }

    fun distribute_learning_reward(
        registry: &mut IncentiveRegistry,
        user: address,
        amount: u64,
        streak: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.incentive_pool) >= amount, E_INSUFFICIENT_FUNDS);

        let reward_balance = balance::split(&mut registry.incentive_pool, amount);
        let reward_coin = coin::from_balance(reward_balance, ctx);
        transfer::public_transfer(reward_coin, user);

        registry.total_rewards_distributed = registry.total_rewards_distributed + amount;

        event::emit(LearningRewardClaimedEvent {
            user,
            reward_type: string::utf8(b"learning_activity"),
            base_amount: BASE_LEARNING_REWARD,
            bonus_amount: amount - BASE_LEARNING_REWARD,
            total_reward: amount,
            streak_count: streak,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    fun distribute_mentoring_rewards(
        registry: &mut IncentiveRegistry,
        mentor: address,
        mentee: address,
        mentor_reward: u64,
        mentee_bonus: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let total_amount = mentor_reward + mentee_bonus;
        assert!(balance::value(&registry.incentive_pool) >= total_amount, E_INSUFFICIENT_FUNDS);

        // Transfer mentor reward
        let mentor_balance = balance::split(&mut registry.incentive_pool, mentor_reward);
        let mentor_coin = coin::from_balance(mentor_balance, ctx);
        transfer::public_transfer(mentor_coin, mentor);

        // Transfer mentee bonus
        let mentee_balance = balance::split(&mut registry.incentive_pool, mentee_bonus);
        let mentee_coin = coin::from_balance(mentee_balance, ctx);
        transfer::public_transfer(mentee_coin, mentee);

        registry.total_rewards_distributed = registry.total_rewards_distributed + total_amount;
    }

    fun distribute_peer_review_reward(
        registry: &mut IncentiveRegistry,
        reviewer: address,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.incentive_pool) >= amount, E_INSUFFICIENT_FUNDS);

        let reward_balance = balance::split(&mut registry.incentive_pool, amount);
        let reward_coin = coin::from_balance(reward_balance, ctx);
        transfer::public_transfer(reward_coin, reviewer);

        registry.total_rewards_distributed = registry.total_rewards_distributed + amount;
    }

    fun distribute_skill_mastery_reward(
        registry: &mut IncentiveRegistry,
        user: address,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.incentive_pool) >= amount, E_INSUFFICIENT_FUNDS);

        let reward_balance = balance::split(&mut registry.incentive_pool, amount);
        let reward_coin = coin::from_balance(reward_balance, ctx);
        transfer::public_transfer(reward_coin, user);

        registry.total_rewards_distributed = registry.total_rewards_distributed + amount;
    }

    // === View Functions ===

    public fun get_user_progress(
        registry: &IncentiveRegistry,
        user: address,
    ): (u64, u64, u64, u64, u64, u64) {
        if (!table::contains(&registry.user_progress, user)) {
            return (0, 0, 0, 0, 0, 0)
        };

        let progress = table::borrow(&registry.user_progress, user);
        (
            progress.current_streak,
            progress.longest_streak,
            progress.total_learning_hours,
            progress.completed_courses,
            progress.learning_velocity,
            progress.retention_score
        )
    }

    public fun get_skill_level(
        registry: &IncentiveRegistry,
        user: address,
        skill: String,
    ): u64 {
        if (!table::contains(&registry.user_progress, user)) {
            return 0
        };

        let progress = table::borrow(&registry.user_progress, user);
        if (!vec_map::contains(&progress.skill_levels, &skill)) {
            return 0
        };

        *vec_map::get(&progress.skill_levels, &skill)
    }

    public fun get_total_rewards_distributed(registry: &IncentiveRegistry): u64 {
        registry.total_rewards_distributed
    }

    public fun get_incentive_pool_balance(registry: &IncentiveRegistry): u64 {
        balance::value(&registry.incentive_pool)
    }

    // === Admin Functions ===

    public entry fun fund_incentive_pool(
        _: &IncentiveAdminCap,
        registry: &mut IncentiveRegistry,
        funding: Coin<SUI>,
    ) {
        let funding_balance = coin::into_balance(funding);
        balance::join(&mut registry.incentive_pool, funding_balance);
    }

    public entry fun toggle_system_status(
        _: &IncentiveAdminCap,
        registry: &mut IncentiveRegistry,
    ) {
        registry.system_active = !registry.system_active;
    }

    public entry fun withdraw_excess_funds(
        _: &IncentiveAdminCap,
        registry: &mut IncentiveRegistry,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.incentive_pool) >= amount, E_INSUFFICIENT_FUNDS);
        let withdrawn = balance::split(&mut registry.incentive_pool, amount);
        let withdrawal_coin = coin::from_balance(withdrawn, ctx);
        transfer::public_transfer(withdrawal_coin, tx_context::sender(ctx));
    }

    // === Simplified Entry Functions (Using ConfigManager DOF) ===

    /// Simplified learning activity recording using config manager
    public entry fun record_learning_activity_with_config(
        registry: &mut IncentiveRegistry,
        config_manager: &ConfigManager,
        subject_area: String,
        learning_hours: u64,
        concepts_learned: u64,
        retention_test_score: u64,
        is_cross_domain: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        record_learning_activity(registry, subject_area, learning_hours, concepts_learned, retention_test_score, is_cross_domain, clock, ctx);
    }

    /// Simplified mentoring session completion using config manager
    public entry fun complete_mentoring_session_with_config(
        registry: &mut IncentiveRegistry,
        config_manager: &ConfigManager,
        session_id: ID,
        mentor_rating: u64,
        mentee_progress_score: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        complete_mentoring_session(registry, session_id, mentor_rating, mentee_progress_score, clock, ctx);
    }

    /// Simplified peer review submission using config manager
    public entry fun submit_peer_review_with_config(
        registry: &mut IncentiveRegistry,
        config_manager: &ConfigManager,
        content_id: ID,
        quality_score: u64,
        detailed_feedback: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        submit_peer_review(registry, content_id, quality_score, detailed_feedback, clock, ctx);
    }

    /// Simplified skill mastery claim using config manager
    public entry fun claim_skill_mastery_with_config(
        registry: &mut IncentiveRegistry,
        config_manager: &ConfigManager,
        skill_name: String,
        mastery_level: u64,
        validation_method: String,
        validator_addresses: vector<address>,
        certification_id: Option<ID>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        claim_skill_mastery(registry, skill_name, mastery_level, validation_method, validator_addresses, certification_id, clock, ctx);
    }

    /// Simplified cohort creation using config manager
    public entry fun create_learning_cohort_with_config(
        registry: &mut IncentiveRegistry,
        config_manager: &ConfigManager,
        name: String,
        subject_areas: vector<String>,
        initial_funding: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        create_learning_cohort(registry, name, subject_areas, initial_funding, clock, ctx);
    }

    // === Testing Functions ===

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}