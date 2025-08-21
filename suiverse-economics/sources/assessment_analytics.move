/// SuiVerse Assessment Analytics Module
/// 
/// This module provides comprehensive analytics and performance tracking for the
/// assessment system, enabling data-driven insights into learning outcomes,
/// content quality, and platform performance optimization.
///
/// Key Features:
/// - Real-time performance metrics and trend analysis
/// - Question quality assessment and optimization recommendations
/// - User learning progress tracking and personalized insights
/// - Platform-wide analytics for administrators and content creators
/// - Integration with session management and quiz variation systems
module suiverse_economics::assessment_analytics {
    use std::string::{Self, String};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;

    // =============== Error Constants ===============
    const E_ANALYTICS_NOT_FOUND: u64 = 70001;
    const E_INSUFFICIENT_DATA: u64 = 70002;
    const E_INVALID_TIME_RANGE: u64 = 70003;
    const E_UNAUTHORIZED_ACCESS: u64 = 70004;
    const E_METRIC_CALCULATION_ERROR: u64 = 70005;
    const E_INVALID_PARAMETERS: u64 = 70006;

    // =============== Analytics Constants ===============
    const MIN_SAMPLE_SIZE: u64 = 5;
    const TREND_ANALYSIS_WINDOW: u64 = 30; // 30 days
    const PERFORMANCE_THRESHOLD: u64 = 70; // 70% pass rate
    const QUALITY_THRESHOLD: u16 = 7000; // 70% quality score
    const UPDATE_INTERVAL: u64 = 3600000; // 1 hour

    // =============== Metric Types ===============
    const METRIC_PERFORMANCE: u8 = 1;
    const METRIC_ENGAGEMENT: u8 = 2;
    const METRIC_QUALITY: u8 = 3;
    const METRIC_LEARNING_OUTCOME: u8 = 4;

    // =============== Trend Directions ===============
    const TREND_IMPROVING: u8 = 1;
    const TREND_STABLE: u8 = 2;
    const TREND_DECLINING: u8 = 3;

    // =============== Core Structures ===============

    /// Central analytics engine
    public struct AnalyticsEngine has key {
        id: UID,
        // Core Analytics
        performance_tracker: PerformanceTracker,
        quality_analyzer: QualityAnalyzer,
        learning_analytics: LearningAnalytics,
        platform_metrics: PlatformMetrics,
        // Configuration
        analytics_config: AnalyticsConfig,
        last_update: u64,
    }

    /// Performance tracking and metrics
    public struct PerformanceTracker has store {
        // Real-time Metrics
        total_sessions: u64,
        completed_sessions: u64,
        average_score: u64,
        completion_rate: u64,
        // Time-based Analytics
        daily_metrics: Table<u64, DailyMetrics>,
        weekly_summaries: Table<u64, WeeklyMetrics>,
        // Trend Analysis
        performance_trends: Table<ID, PerformanceTrend>,
        // Exam-specific Metrics
        exam_analytics: Table<ID, ExamAnalytics>,
    }

    /// Daily performance metrics
    public struct DailyMetrics has store, drop {
        date: u64, // Timestamp at start of day
        sessions_started: u64,
        sessions_completed: u64,
        total_score: u64,
        average_score: u64,
        pass_rate: u64,
        unique_users: u64,
        total_time_spent: u64,
        average_session_time: u64,
    }

    /// Weekly performance summary
    public struct WeeklyMetrics has store, drop {
        week_start: u64,
        total_sessions: u64,
        completion_rate: u64,
        average_score: u64,
        score_improvement: u64, // Change from previous week (stored as abs value)
        user_retention: u64,
        most_popular_exams: vector<ID>,
        performance_distribution: vector<u64>, // [A, B, C, D, F] grade counts
    }

    /// Performance trend analysis
    public struct PerformanceTrend has store, drop {
        entity_id: ID, // Could be exam_id, user_id, etc.
        trend_type: u8,
        data_points: vector<TrendPoint>,
        trend_direction: u8,
        trend_strength: u64, // 0-100 scale
        confidence_level: u8,
        last_calculated: u64,
    }

    /// Individual trend data point
    public struct TrendPoint has store, drop, copy {
        timestamp: u64,
        value: u64,
        sample_size: u64,
    }

    /// Exam-specific analytics
    public struct ExamAnalytics has store {
        exam_id: ID,
        total_attempts: u64,
        successful_completions: u64,
        average_score: u64,
        average_time: u64,
        difficulty_rating: u64, // Calculated from performance
        question_analytics: Table<u64, QuestionAnalytics>, // question_index -> analytics
        improvement_areas: vector<String>,
        last_updated: u64,
    }

    /// Question-level analytics
    public struct QuestionAnalytics has store {
        question_index: u64,
        original_quiz_id: ID,
        attempts: u64,
        correct_answers: u64,
        success_rate: u64,
        average_time: u64,
        difficulty_score: u64,
        discrimination_index: u64, // How well it differentiates ability levels
        variation_performance: Table<u8, VariationPerformance>, // variation_type -> performance
    }

    /// Variation performance metrics
    public struct VariationPerformance has store, drop {
        variation_type: u8,
        attempts: u64,
        success_rate: u64,
        average_time: u64,
        quality_rating: u64,
        user_feedback: u64,
    }

    /// Quality analysis system
    public struct QualityAnalyzer has store {
        // Content Quality Metrics
        content_quality_scores: Table<ID, ContentQualityScore>,
        variation_quality_trends: Table<u8, QualityTrend>,
        // Quality Improvement Tracking
        quality_interventions: Table<ID, QualityIntervention>,
        content_recommendations: Table<ID, vector<String>>,
        // System Health
        overall_quality_score: u64,
        quality_distribution: vector<u64>, // [Poor, Fair, Good, Excellent] counts
    }

    /// Content quality assessment
    public struct ContentQualityScore has store, drop {
        content_id: ID,
        overall_score: u64,
        semantic_quality: u64,
        grammatical_quality: u64,
        educational_value: u64,
        user_engagement: u64,
        difficulty_appropriateness: u64,
        assessment_count: u64,
        last_assessed: u64,
    }

    /// Quality trend for variation types
    public struct QualityTrend has store, drop {
        variation_type: u8,
        quality_history: vector<TrendPoint>,
        improvement_rate: u64, // Positive value indicates improvement
        stability_score: u64,
        intervention_effectiveness: u64,
    }

    /// Quality improvement intervention
    public struct QualityIntervention has store, drop {
        intervention_id: ID,
        target_content: ID,
        intervention_type: String,
        implementation_date: u64,
        expected_improvement: u64,
        actual_improvement: u64, // Store absolute improvement value
        effectiveness_score: u64,
        status: u8, // 0: planned, 1: active, 2: completed, 3: cancelled
    }

    /// Learning analytics and insights
    public struct LearningAnalytics has store {
        // User Progress Tracking
        user_progress: Table<address, UserLearningProfile>,
        cohort_analytics: Table<String, CohortAnalytics>,
        // Learning Outcome Analysis
        skill_development_tracking: Table<address, SkillDevelopment>,
        knowledge_retention_analysis: Table<address, RetentionAnalysis>,
        // Personalization Data
        learning_patterns: Table<address, LearningPattern>,
        recommendation_effectiveness: Table<address, RecommendationMetrics>,
    }

    /// User learning profile and progress
    public struct UserLearningProfile has store, drop {
        user: address,
        // Performance Metrics
        total_exams_taken: u64,
        exams_passed: u64,
        current_streak: u64,
        best_streak: u64,
        average_score: u64,
        // Learning Velocity
        improvement_rate: u64, // Positive value indicates improvement // Change in performance over time
        learning_consistency: u64, // How consistent performance is
        time_investment: u64, // Total time spent learning
        // Difficulty Progression
        comfort_level: u8, // 1-10 scale
        challenge_readiness: u8,
        skill_gaps: vector<String>,
        strength_areas: vector<String>,
        // Engagement Metrics
        session_frequency: u64, // Sessions per week
        average_session_length: u64,
        last_activity: u64,
    }

    /// Cohort-based analytics
    public struct CohortAnalytics has store, drop {
        cohort_id: String,
        member_count: u64,
        active_members: u64,
        // Performance Comparison
        average_performance: u64,
        performance_variance: u64,
        top_performers: vector<address>,
        struggling_learners: vector<address>,
        // Collaborative Learning
        peer_interactions: u64,
        knowledge_sharing_score: u64,
        group_improvement_rate: u64, // Positive indicates improvement
        // Retention and Engagement
        retention_rate: u64,
        engagement_score: u64,
        completion_rate: u64,
    }

    /// Skill development tracking
    public struct SkillDevelopment has store {
        user: address,
        skill_assessments: Table<String, SkillAssessment>,
        development_milestones: vector<Milestone>,
        competency_progression: vector<CompetencyLevel>,
        personalized_goals: vector<LearningGoal>,
        mastery_predictions: Table<String, MasteryPrediction>,
    }

    /// Individual skill assessment
    public struct SkillAssessment has store, drop {
        skill_name: String,
        current_level: u8, // 1-10 scale
        assessment_confidence: u8,
        evidence_quality: u64,
        assessment_date: u64,
        improvement_trajectory: vector<TrendPoint>,
        next_milestone: Option<String>,
    }

    /// Learning milestone
    public struct Milestone has store, drop, copy {
        milestone_id: String,
        skill_area: String,
        achievement_level: u8,
        achieved_date: u64,
        evidence_exams: vector<ID>,
        peer_recognition: u64,
    }

    /// Competency level tracking
    public struct CompetencyLevel has store, drop, copy {
        competency_name: String,
        current_level: u8,
        target_level: u8,
        progress_percentage: u64,
        estimated_completion: u64,
        development_path: vector<String>,
    }

    /// Personalized learning goal
    public struct LearningGoal has store, drop, copy {
        goal_id: String,
        description: String,
        target_completion: u64,
        progress_percentage: u64,
        success_criteria: vector<String>,
        priority_level: u8,
        status: u8, // 0: active, 1: completed, 2: paused, 3: cancelled
    }

    /// Mastery prediction
    public struct MasteryPrediction has store, drop {
        skill_name: String,
        predicted_mastery_date: u64,
        confidence_level: u8,
        required_practice_time: u64,
        recommended_resources: vector<String>,
        success_probability: u8,
    }

    /// Knowledge retention analysis
    public struct RetentionAnalysis has store {
        user: address,
        retention_curve: vector<RetentionPoint>,
        forgetting_patterns: Table<String, ForgettingPattern>,
        optimal_review_schedule: ReviewSchedule,
        retention_interventions: vector<RetentionIntervention>,
    }

    /// Knowledge retention measurement
    public struct RetentionPoint has store, drop, copy {
        assessment_date: u64,
        time_since_learning: u64,
        retention_percentage: u64,
        topic_area: String,
        context: String,
    }

    /// Forgetting pattern for specific topics
    public struct ForgettingPattern has store, drop {
        topic: String,
        decay_rate: u64, // How quickly knowledge fades
        half_life: u64, // Time for 50% retention
        stability_factors: vector<String>,
        reinforcement_effectiveness: u64,
    }

    /// Review schedule optimization
    public struct ReviewSchedule has store {
        user: address,
        scheduled_reviews: Table<String, u64>, // topic -> next_review_time
        review_intervals: Table<String, u64>, // topic -> interval_ms
        priority_topics: vector<String>,
        schedule_optimization_score: u64,
    }

    /// Retention intervention
    public struct RetentionIntervention has store, drop, copy {
        intervention_type: String,
        target_topic: String,
        implementation_date: u64,
        effectiveness_score: u64,
        user_compliance: u8,
        outcome_measurement: u64,
    }

    /// Learning pattern analysis
    public struct LearningPattern has store, drop {
        user: address,
        optimal_study_times: vector<u64>, // Hours of day (0-23)
        preferred_session_length: u64,
        learning_style_indicators: vector<String>,
        motivation_patterns: MotivationPattern,
        challenge_preferences: ChallengePreference,
        social_learning_preference: u8, // 1-10 scale
    }

    /// Motivation pattern analysis
    public struct MotivationPattern has store, drop, copy {
        intrinsic_motivation: u8, // 1-10 scale
        extrinsic_motivation: u8,
        competition_drive: u8,
        achievement_orientation: u8,
        growth_mindset_score: u8,
        persistence_level: u8,
    }

    /// Challenge preference analysis
    public struct ChallengePreference has store, drop, copy {
        preferred_difficulty: u8, // 1-10 scale
        risk_tolerance: u8,
        novelty_seeking: u8,
        structured_vs_exploratory: u8, // Low = structured, High = exploratory
        feedback_frequency_preference: u8,
    }

    /// Recommendation effectiveness tracking
    public struct RecommendationMetrics has store, drop {
        user: address,
        total_recommendations: u64,
        accepted_recommendations: u64,
        successful_outcomes: u64,
        recommendation_accuracy: u64,
        user_satisfaction: u8,
        improvement_attribution: u64, // How much improvement is due to recommendations
    }

    /// Platform-wide metrics
    public struct PlatformMetrics has store {
        // Usage Statistics
        total_users: u64,
        active_users_daily: u64,
        active_users_weekly: u64,
        active_users_monthly: u64,
        // Content Statistics
        total_content_items: u64,
        content_utilization_rate: u64,
        content_quality_average: u64,
        // Performance Indicators
        platform_engagement_score: u64,
        learning_effectiveness_score: u64,
        user_satisfaction_average: u8,
        // Growth Metrics
        user_growth_rate: u64,
        content_growth_rate: u64,
        engagement_growth_rate: u64,
        // Health Indicators
        system_health_score: u64,
        data_quality_score: u64,
        last_health_check: u64,
    }

    /// Analytics configuration
    public struct AnalyticsConfig has store {
        // Update Frequencies
        real_time_updates: bool,
        batch_update_interval: u64,
        trend_calculation_interval: u64,
        // Data Retention
        raw_data_retention_days: u64,
        summary_data_retention_days: u64,
        // Quality Thresholds
        min_sample_size: u64,
        confidence_threshold: u8,
        // Privacy Settings
        anonymization_enabled: bool,
        data_minimization: bool,
    }

    // =============== Events ===============

    public struct AnalyticsUpdated has copy, drop {
        metric_type: u8,
        entity_id: ID,
        old_value: u64,
        new_value: u64,
        change_percentage: u64,
        timestamp: u64,
    }

    public struct TrendDetected has copy, drop {
        entity_id: ID,
        trend_type: u8,
        trend_direction: u8,
        trend_strength: u64,
        confidence_level: u8,
        timestamp: u64,
    }

    public struct QualityAlert has copy, drop {
        content_id: ID,
        quality_score: u64,
        threshold: u64,
        alert_type: String,
        recommended_action: String,
        timestamp: u64,
    }

    public struct LearningInsight has copy, drop {
        user: address,
        insight_type: String,
        insight_description: String,
        confidence_level: u8,
        actionable_recommendations: vector<String>,
        timestamp: u64,
    }

    // =============== Initialization ===============

    fun init(ctx: &mut TxContext) {
        let analytics_engine = AnalyticsEngine {
            id: object::new(ctx),
            performance_tracker: PerformanceTracker {
                total_sessions: 0,
                completed_sessions: 0,
                average_score: 0,
                completion_rate: 0,
                daily_metrics: table::new(ctx),
                weekly_summaries: table::new(ctx),
                performance_trends: table::new(ctx),
                exam_analytics: table::new(ctx),
            },
            quality_analyzer: QualityAnalyzer {
                content_quality_scores: table::new(ctx),
                variation_quality_trends: table::new(ctx),
                quality_interventions: table::new(ctx),
                content_recommendations: table::new(ctx),
                overall_quality_score: 8500, // Start with good baseline
                quality_distribution: vector[10, 20, 40, 30], // [Poor, Fair, Good, Excellent]
            },
            learning_analytics: LearningAnalytics {
                user_progress: table::new(ctx),
                cohort_analytics: table::new(ctx),
                skill_development_tracking: table::new(ctx),
                knowledge_retention_analysis: table::new(ctx),
                learning_patterns: table::new(ctx),
                recommendation_effectiveness: table::new(ctx),
            },
            platform_metrics: PlatformMetrics {
                total_users: 0,
                active_users_daily: 0,
                active_users_weekly: 0,
                active_users_monthly: 0,
                total_content_items: 0,
                content_utilization_rate: 0,
                content_quality_average: 8500,
                platform_engagement_score: 8000,
                learning_effectiveness_score: 7500,
                user_satisfaction_average: 8,
                user_growth_rate: 0,
                content_growth_rate: 0,
                engagement_growth_rate: 0,
                system_health_score: 9500,
                data_quality_score: 9000,
                last_health_check: 0,
            },
            analytics_config: AnalyticsConfig {
                real_time_updates: true,
                batch_update_interval: UPDATE_INTERVAL,
                trend_calculation_interval: UPDATE_INTERVAL * 24, // Daily trend updates
                raw_data_retention_days: 90,
                summary_data_retention_days: 365,
                min_sample_size: MIN_SAMPLE_SIZE,
                confidence_threshold: 85,
                anonymization_enabled: true,
                data_minimization: true,
            },
            last_update: 0,
        };

        transfer::share_object(analytics_engine);
    }

    // =============== Core Analytics Functions ===============

    /// Record session completion data
    public fun record_session_completion(
        engine: &mut AnalyticsEngine,
        exam_id: ID,
        participant: address,
        score: u64,
        time_spent: u64,
        questions_correct: u64,
        total_questions: u64,
        passed: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let day_key = get_day_key(current_time);

        // Update performance tracker
        engine.performance_tracker.total_sessions = engine.performance_tracker.total_sessions + 1;
        engine.performance_tracker.completed_sessions = engine.performance_tracker.completed_sessions + 1;

        // Update completion rate
        engine.performance_tracker.completion_rate = 
            (engine.performance_tracker.completed_sessions * 100) / engine.performance_tracker.total_sessions;

        // Update average score
        let total_completed = engine.performance_tracker.completed_sessions;
        engine.performance_tracker.average_score = 
            ((engine.performance_tracker.average_score * (total_completed - 1)) + score) / total_completed;

        // Update daily metrics
        update_daily_metrics(engine, day_key, score, time_spent, passed, current_time);

        // Update exam-specific analytics
        update_exam_analytics(engine, exam_id, score, time_spent, questions_correct, total_questions, current_time, ctx);

        // Update user learning profile
        update_user_learning_profile(engine, participant, score, time_spent, passed, current_time);

        // Emit analytics event
        event::emit(AnalyticsUpdated {
            metric_type: METRIC_PERFORMANCE,
            entity_id: exam_id,
            old_value: total_completed - 1,
            new_value: total_completed,
            change_percentage: 1,
            timestamp: current_time,
        });
    }

    /// Update question-level analytics
    public fun record_question_performance(
        engine: &mut AnalyticsEngine,
        exam_id: ID,
        question_index: u64,
        original_quiz_id: ID,
        variation_type: u8,
        correct: bool,
        time_spent: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);

        // Get or create exam analytics
        if (!table::contains(&engine.performance_tracker.exam_analytics, exam_id)) {
            let new_analytics = ExamAnalytics {
                exam_id,
                total_attempts: 0,
                successful_completions: 0,
                average_score: 0,
                average_time: 0,
                difficulty_rating: 5000, // Default medium difficulty
                question_analytics: table::new(ctx),
                improvement_areas: vector::empty(),
                last_updated: current_time,
            };
            table::add(&mut engine.performance_tracker.exam_analytics, exam_id, new_analytics);
        };

        let exam_analytics = table::borrow_mut(&mut engine.performance_tracker.exam_analytics, exam_id);

        // Update question analytics
        if (!table::contains(&exam_analytics.question_analytics, question_index)) {
            let new_question_analytics = QuestionAnalytics {
                question_index,
                original_quiz_id,
                attempts: 0,
                correct_answers: 0,
                success_rate: 0,
                average_time: 0,
                difficulty_score: 5000,
                discrimination_index: 5000,
                variation_performance: table::new(ctx),
            };
            table::add(&mut exam_analytics.question_analytics, question_index, new_question_analytics);
        };

        let question_analytics = table::borrow_mut(&mut exam_analytics.question_analytics, question_index);
        
        // Update question metrics
        question_analytics.attempts = question_analytics.attempts + 1;
        if (correct) {
            question_analytics.correct_answers = question_analytics.correct_answers + 1;
        };
        question_analytics.success_rate = (question_analytics.correct_answers * 100) / question_analytics.attempts;
        
        // Update average time
        question_analytics.average_time = 
            ((question_analytics.average_time * (question_analytics.attempts - 1)) + time_spent) / 
            question_analytics.attempts;

        // Update variation performance
        update_variation_performance(question_analytics, variation_type, correct, time_spent);

        // Calculate difficulty based on success rate
        question_analytics.difficulty_score = calculate_difficulty_from_performance(question_analytics.success_rate);
    }

    /// Analyze content quality
    public fun analyze_content_quality(
        engine: &mut AnalyticsEngine,
        content_id: ID,
        semantic_quality: u64,
        grammatical_quality: u64,
        educational_value: u64,
        user_engagement: u64,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);

        // Calculate overall quality score
        let overall_score = (semantic_quality + grammatical_quality + educational_value + user_engagement) / 4;

        // Update quality analyzer
        let quality_score = ContentQualityScore {
            content_id,
            overall_score,
            semantic_quality,
            grammatical_quality,
            educational_value,
            user_engagement,
            difficulty_appropriateness: 8000, // Default good rating
            assessment_count: 1,
            last_assessed: current_time,
        };

        if (table::contains(&engine.quality_analyzer.content_quality_scores, content_id)) {
            let existing_score = table::borrow_mut(&mut engine.quality_analyzer.content_quality_scores, content_id);
            // Update with running average
            let count = existing_score.assessment_count + 1;
            existing_score.overall_score = ((existing_score.overall_score * existing_score.assessment_count) + overall_score) / count;
            existing_score.semantic_quality = ((existing_score.semantic_quality * existing_score.assessment_count) + semantic_quality) / count;
            existing_score.grammatical_quality = ((existing_score.grammatical_quality * existing_score.assessment_count) + grammatical_quality) / count;
            existing_score.educational_value = ((existing_score.educational_value * existing_score.assessment_count) + educational_value) / count;
            existing_score.user_engagement = ((existing_score.user_engagement * existing_score.assessment_count) + user_engagement) / count;
            existing_score.assessment_count = count;
            existing_score.last_assessed = current_time;
        } else {
            table::add(&mut engine.quality_analyzer.content_quality_scores, content_id, quality_score);
        };

        // Check if quality alert is needed
        if (overall_score < (QUALITY_THRESHOLD as u64)) {
            event::emit(QualityAlert {
                content_id,
                quality_score: overall_score,
                threshold: (QUALITY_THRESHOLD as u64),
                alert_type: string::utf8(b"Low Quality Content"),
                recommended_action: string::utf8(b"Review and improve content quality"),
                timestamp: current_time,
            });
        };

        // Update overall platform quality
        update_platform_quality_metrics(engine, overall_score);
    }

    /// Generate learning insights for user
    public fun generate_learning_insights(
        engine: &mut AnalyticsEngine,
        user: address,
        clock: &Clock,
    ): vector<String> {
        let current_time = clock::timestamp_ms(clock);
        let mut insights = vector::empty<String>();

        if (table::contains(&engine.learning_analytics.user_progress, user)) {
            let profile = table::borrow(&engine.learning_analytics.user_progress, user);
            
            // Generate insights based on user data
            if (profile.current_streak > 5) {
                vector::push_back(&mut insights, string::utf8(b"Excellent consistency! Your learning streak shows great dedication."));
            };

            if (profile.improvement_rate > 10) {
                vector::push_back(&mut insights, string::utf8(b"Your performance is improving rapidly. Keep up the great work!"));
            } else if (profile.improvement_rate == 0) {
                vector::push_back(&mut insights, string::utf8(b"Consider reviewing fundamental concepts to strengthen your foundation."));
            };

            if (profile.average_score > 85) {
                vector::push_back(&mut insights, string::utf8(b"You're ready for more challenging content. Consider advancing to the next level."));
            };

            if (vector::length(&profile.skill_gaps) > 0) {
                vector::push_back(&mut insights, string::utf8(b"Focus on addressing identified skill gaps for balanced improvement."));
            };

            // Emit learning insight event
            event::emit(LearningInsight {
                user,
                insight_type: string::utf8(b"Performance Analysis"),
                insight_description: string::utf8(b"Generated from user learning profile"),
                confidence_level: 85,
                actionable_recommendations: insights,
                timestamp: current_time,
            });
        };

        insights
    }

    // =============== Helper Functions ===============

    fun update_daily_metrics(
        engine: &mut AnalyticsEngine,
        day_key: u64,
        score: u64,
        time_spent: u64,
        passed: bool,
        timestamp: u64,
    ) {
        if (!table::contains(&engine.performance_tracker.daily_metrics, day_key)) {
            let new_metrics = DailyMetrics {
                date: day_key,
                sessions_started: 0,
                sessions_completed: 0,
                total_score: 0,
                average_score: 0,
                pass_rate: 0,
                unique_users: 0,
                total_time_spent: 0,
                average_session_time: 0,
            };
            table::add(&mut engine.performance_tracker.daily_metrics, day_key, new_metrics);
        };

        let daily_metrics = table::borrow_mut(&mut engine.performance_tracker.daily_metrics, day_key);
        daily_metrics.sessions_completed = daily_metrics.sessions_completed + 1;
        daily_metrics.total_score = daily_metrics.total_score + score;
        daily_metrics.average_score = daily_metrics.total_score / daily_metrics.sessions_completed;
        daily_metrics.total_time_spent = daily_metrics.total_time_spent + time_spent;
        daily_metrics.average_session_time = daily_metrics.total_time_spent / daily_metrics.sessions_completed;

        if (passed) {
            daily_metrics.pass_rate = ((daily_metrics.pass_rate * (daily_metrics.sessions_completed - 1)) + 100) / daily_metrics.sessions_completed;
        } else {
            daily_metrics.pass_rate = (daily_metrics.pass_rate * (daily_metrics.sessions_completed - 1)) / daily_metrics.sessions_completed;
        };
    }

    fun update_exam_analytics(
        engine: &mut AnalyticsEngine,
        exam_id: ID,
        score: u64,
        time_spent: u64,
        questions_correct: u64,
        total_questions: u64,
        timestamp: u64,
        ctx: &mut TxContext,
    ) {
        if (!table::contains(&engine.performance_tracker.exam_analytics, exam_id)) {
            let new_analytics = ExamAnalytics {
                exam_id,
                total_attempts: 0,
                successful_completions: 0,
                average_score: 0,
                average_time: 0,
                difficulty_rating: 5000,
                question_analytics: table::new(ctx),
                improvement_areas: vector::empty(),
                last_updated: timestamp,
            };
            table::add(&mut engine.performance_tracker.exam_analytics, exam_id, new_analytics);
        };

        let exam_analytics = table::borrow_mut(&mut engine.performance_tracker.exam_analytics, exam_id);
        exam_analytics.total_attempts = exam_analytics.total_attempts + 1;
        
        if (score >= PERFORMANCE_THRESHOLD) {
            exam_analytics.successful_completions = exam_analytics.successful_completions + 1;
        };

        // Update averages
        exam_analytics.average_score = 
            ((exam_analytics.average_score * (exam_analytics.total_attempts - 1)) + score) / exam_analytics.total_attempts;
        exam_analytics.average_time = 
            ((exam_analytics.average_time * (exam_analytics.total_attempts - 1)) + time_spent) / exam_analytics.total_attempts;

        // Update difficulty rating based on performance
        let success_rate = (questions_correct * 100) / total_questions;
        exam_analytics.difficulty_rating = calculate_difficulty_from_performance(success_rate);
        exam_analytics.last_updated = timestamp;
    }

    fun update_user_learning_profile(
        engine: &mut AnalyticsEngine,
        user: address,
        score: u64,
        time_spent: u64,
        passed: bool,
        timestamp: u64,
    ) {
        if (!table::contains(&engine.learning_analytics.user_progress, user)) {
            let new_profile = UserLearningProfile {
                user,
                total_exams_taken: 0,
                exams_passed: 0,
                current_streak: 0,
                best_streak: 0,
                average_score: 0,
                improvement_rate: 0,
                learning_consistency: 8000,
                time_investment: 0,
                comfort_level: 5,
                challenge_readiness: 5,
                skill_gaps: vector::empty(),
                strength_areas: vector::empty(),
                session_frequency: 0,
                average_session_length: 0,
                last_activity: timestamp,
            };
            table::add(&mut engine.learning_analytics.user_progress, user, new_profile);
        };

        let profile = table::borrow_mut(&mut engine.learning_analytics.user_progress, user);
        profile.total_exams_taken = profile.total_exams_taken + 1;
        
        if (passed) {
            profile.exams_passed = profile.exams_passed + 1;
            profile.current_streak = profile.current_streak + 1;
            if (profile.current_streak > profile.best_streak) {
                profile.best_streak = profile.current_streak;
            };
        } else {
            profile.current_streak = 0;
        };

        // Update average score
        profile.average_score = 
            ((profile.average_score * (profile.total_exams_taken - 1)) + score) / profile.total_exams_taken;

        // Calculate improvement rate (simplified)
        if (profile.total_exams_taken > 1) {
            let previous_avg = (profile.average_score * profile.total_exams_taken - score) / (profile.total_exams_taken - 1);
            profile.improvement_rate = if (profile.average_score >= previous_avg) {
                profile.average_score - previous_avg
            } else {
                0 // Represent decline as 0 for now, or use a different approach
            };
        };

        profile.time_investment = profile.time_investment + time_spent;
        profile.average_session_length = profile.time_investment / profile.total_exams_taken;
        profile.last_activity = timestamp;

        // Update comfort level based on recent performance
        if (score > 85) {
            profile.comfort_level = if (profile.comfort_level < 10) { profile.comfort_level + 1 } else { 10 };
        } else if (score < 60) {
            profile.comfort_level = if (profile.comfort_level > 1) { profile.comfort_level - 1 } else { 1 };
        };
    }

    fun update_variation_performance(
        question_analytics: &mut QuestionAnalytics,
        variation_type: u8,
        correct: bool,
        time_spent: u64,
    ) {
        if (!table::contains(&question_analytics.variation_performance, variation_type)) {
            let new_performance = VariationPerformance {
                variation_type,
                attempts: 0,
                success_rate: 0,
                average_time: 0,
                quality_rating: 8000,
                user_feedback: 8000,
            };
            table::add(&mut question_analytics.variation_performance, variation_type, new_performance);
        };

        let performance = table::borrow_mut(&mut question_analytics.variation_performance, variation_type);
        performance.attempts = performance.attempts + 1;
        
        if (correct) {
            performance.success_rate = ((performance.success_rate * (performance.attempts - 1)) + 100) / performance.attempts;
        } else {
            performance.success_rate = (performance.success_rate * (performance.attempts - 1)) / performance.attempts;
        };

        performance.average_time = 
            ((performance.average_time * (performance.attempts - 1)) + time_spent) / performance.attempts;
    }

    fun update_platform_quality_metrics(engine: &mut AnalyticsEngine, quality_score: u64) {
        // Update overall quality score as running average
        let total_assessments = table::length(&engine.quality_analyzer.content_quality_scores);
        if (total_assessments > 0) {
            engine.quality_analyzer.overall_quality_score = 
                ((engine.quality_analyzer.overall_quality_score * (total_assessments - 1)) + quality_score) / total_assessments;
        };

        // Update quality distribution
        let quality_index = if (quality_score < 5000) { 0 }      // Poor
        else if (quality_score < 7000) { 1 }                    // Fair  
        else if (quality_score < 8500) { 2 }                    // Good
        else { 3 };                                              // Excellent

        if (quality_index < vector::length(&engine.quality_analyzer.quality_distribution)) {
            let count = vector::borrow_mut(&mut engine.quality_analyzer.quality_distribution, quality_index);
            *count = *count + 1;
        };
    }

    fun calculate_difficulty_from_performance(success_rate: u64): u64 {
        // Convert success rate to difficulty score (inverse relationship)
        if (success_rate > 90) {
            2000 // Very easy
        } else if (success_rate > 80) {
            4000 // Easy
        } else if (success_rate > 60) {
            6000 // Medium
        } else if (success_rate > 40) {
            8000 // Hard
        } else {
            9500 // Very hard
        }
    }

    fun get_day_key(timestamp: u64): u64 {
        timestamp / 86400000 // Convert to day granularity
    }

    // =============== View Functions ===============

    public fun get_performance_summary(engine: &AnalyticsEngine): (u64, u64, u64, u64) {
        (
            engine.performance_tracker.total_sessions,
            engine.performance_tracker.completed_sessions,
            engine.performance_tracker.completion_rate,
            engine.performance_tracker.average_score
        )
    }

    public fun get_exam_analytics(engine: &AnalyticsEngine, exam_id: ID): (bool, u64, u64, u64, u64, u64) {
        if (table::contains(&engine.performance_tracker.exam_analytics, exam_id)) {
            let analytics = table::borrow(&engine.performance_tracker.exam_analytics, exam_id);
            (
                true, // found
                analytics.total_attempts,
                analytics.successful_completions,
                analytics.average_score,
                analytics.average_time,
                analytics.difficulty_rating
            )
        } else {
            (false, 0, 0, 0, 0, 0) // not found
        }
    }

    public fun get_user_learning_profile(engine: &AnalyticsEngine, user: address): (bool, u64, u64, u64, u64, u64) {
        if (table::contains(&engine.learning_analytics.user_progress, user)) {
            let profile = table::borrow(&engine.learning_analytics.user_progress, user);
            (
                true, // found
                profile.total_exams_taken,
                profile.exams_passed,
                profile.current_streak,
                profile.average_score,
                profile.improvement_rate
            )
        } else {
            (false, 0, 0, 0, 0, 0) // not found
        }
    }

    public fun get_platform_metrics(engine: &AnalyticsEngine): (u64, u64, u64, u64, u64) {
        (
            engine.platform_metrics.total_users,
            engine.platform_metrics.active_users_daily,
            engine.platform_metrics.platform_engagement_score,
            engine.platform_metrics.learning_effectiveness_score,
            engine.platform_metrics.system_health_score
        )
    }

    public fun get_quality_overview(engine: &AnalyticsEngine): (u64, vector<u64>) {
        (
            engine.quality_analyzer.overall_quality_score,
            engine.quality_analyzer.quality_distribution
        )
    }

    // =============== Friend Functions for Module Integration ===============

    public(package) fun update_daily_active_users(engine: &mut AnalyticsEngine, count: u64) {
        engine.platform_metrics.active_users_daily = count;
    }

    public(package) fun increment_total_users(engine: &mut AnalyticsEngine) {
        engine.platform_metrics.total_users = engine.platform_metrics.total_users + 1;
    }

    public(package) fun get_analytics_config(engine: &AnalyticsEngine): &AnalyticsConfig {
        &engine.analytics_config
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}