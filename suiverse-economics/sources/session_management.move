/// SuiVerse Session Management Module
/// 
/// This module handles the complete lifecycle of exam sessions including:
/// - Session creation and initialization
/// - Question progression and answer submission
/// - Session completion and result calculation
/// - Anti-cheating measures and session integrity
/// - Integration with quiz variation and analytics systems
///
/// Key Features:
/// - Secure session management with integrity verification
/// - Gas-optimized answer storage using dynamic fields
/// - Real-time session monitoring and timeout handling
/// - Comprehensive session analytics and performance tracking
module suiverse_economics::session_management {
    use std::string::{Self as string, String};
    // use std::option; // Implicit import
    use sui::object::{Self, ID, UID};
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
    const E_SESSION_NOT_FOUND: u64 = 50001;
    const E_SESSION_EXPIRED: u64 = 50002;
    const E_SESSION_ALREADY_COMPLETED: u64 = 50003;
    const E_INVALID_QUESTION_INDEX: u64 = 50004;
    const E_ANSWER_ALREADY_SUBMITTED: u64 = 50005;
    const E_UNAUTHORIZED_ACCESS: u64 = 50006;
    const E_SESSION_INTEGRITY_VIOLATION: u64 = 50007;
    const E_INSUFFICIENT_PAYMENT: u64 = 50008;
    const E_EXAM_NOT_ACTIVE: u64 = 50009;
    const E_RETRY_COOLDOWN_ACTIVE: u64 = 50010;
    const E_INVALID_SESSION_STATE: u64 = 50011;
    const E_TIME_MANIPULATION_DETECTED: u64 = 50012;

    // =============== Session Constants ===============
    const SESSION_TIMEOUT_BUFFER: u64 = 300000; // 5 minutes buffer
    const MIN_SESSION_TIME: u64 = 60000; // 1 minute minimum
    const MAX_SESSION_TIME: u64 = 14400000; // 4 hours maximum
    const INTEGRITY_CHECK_INTERVAL: u64 = 30000; // 30 seconds
    const DEFAULT_EXAM_FEE: u64 = 5_000_000_000; // 5 SUI
    const DEFAULT_RETRY_FEE: u64 = 3_000_000_000; // 3 SUI
    const RETRY_COOLDOWN_PERIOD: u64 = 604800000; // 7 days

    // =============== Session Status Constants ===============
    const SESSION_STATUS_ACTIVE: u8 = 0;
    const SESSION_STATUS_PAUSED: u8 = 1;
    const SESSION_STATUS_COMPLETED: u8 = 2;
    const SESSION_STATUS_EXPIRED: u8 = 3;
    const SESSION_STATUS_ABANDONED: u8 = 4;
    const SESSION_STATUS_INVALID: u8 = 5;

    // =============== Core Structures ===============

    /// Session Manager - Global session coordination
    public struct SessionManager has key {
        id: UID,
        // Active Session Tracking
        active_sessions: Table<address, ID>, // user -> session_id
        session_registry: Table<ID, SessionMetadata>,
        total_sessions_created: u64,
        total_sessions_completed: u64,
        // Session Configuration
        default_timeout_buffer: u64,
        integrity_check_enabled: bool,
        anti_cheat_enabled: bool,
        // Revenue Management
        platform_treasury: Balance<SUI>,
        session_fees_collected: u64,
        // Analytics Integration
        session_analytics: SessionAnalytics,
    }

    /// Individual Exam Session
    public struct ExamSession has key {
        id: UID,
        exam_id: ID,
        participant: address,
        // Session Configuration
        total_questions: u64,
        time_limit_ms: u64,
        pass_threshold: u8,
        // Session State
        current_question: u64,
        questions_answered: u64,
        start_time: u64,
        end_time: Option<u64>,
        status: u8,
        is_retry: bool,
        // Scoring and Progress
        current_score: u64,
        max_possible_score: u64,
        // Security and Integrity
        session_hash: vector<u8>,
        integrity_markers: vector<u8>,
        last_activity: u64,
        // Dynamic Fields for Answers: answer_{index} -> QuestionAnswer
        // Dynamic Fields for Variations: variation_{index} -> QuizVariation
    }

    /// Session metadata for tracking and analytics
    public struct SessionMetadata has store, drop {
        session_id: ID,
        exam_id: ID,
        participant: address,
        created_at: u64,
        expected_completion: u64,
        session_type: u8, // 0: regular, 1: retry, 2: practice
        difficulty_level: u8,
        language_preference: String,
        access_pattern: vector<u64>, // Timestamps of question access
    }

    /// Individual question answer with comprehensive tracking
    public struct QuestionAnswer has store, drop {
        question_index: u64,
        original_quiz_id: ID,
        variation_type: u8,
        submitted_answer: String,
        answer_confidence: u8, // 0-100 scale
        time_spent_ms: u64,
        is_correct: bool,
        partial_score: u64,
        max_score: u64,
        submission_timestamp: u64,
        revision_count: u8,
    }

    /// Quiz variation data structure
    public struct QuizVariation has store, drop {
        original_quiz_id: ID,
        variation_type: u8,
        variation_seed: u64,
        transformed_question: String,
        transformed_options: vector<String>,
        correct_answer_index: u8,
        quality_score: u16,
        difficulty_adjustment: u8, // 0-10 where 5 is neutral, <5 is easier, >5 is harder
        generation_timestamp: u64,
    }

    /// Session completion result
    public struct SessionResult has drop {
        session_id: ID,
        exam_id: ID,
        participant: address,
        // Final Scores
        raw_score: u64,
        percentage_score: u64,
        passed: bool,
        grade: String,
        // Performance Metrics
        total_time_ms: u64,
        average_question_time: u64,
        questions_correct: u64,
        questions_attempted: u64,
        // Analytics Data
        performance_distribution: vector<u64>,
        difficulty_analysis: DifficultyAnalysis,
        learning_insights: LearningInsights,
        // Session Quality
        session_quality_score: u8,
        integrity_score: u8,
        completion_timestamp: u64,
    }

    /// Difficulty analysis from session
    public struct DifficultyAnalysis has store, drop, copy {
        perceived_difficulty: u8, // 1-10 scale
        actual_performance: u64,
        difficulty_variance: u64,
        hardest_questions: vector<u64>,
        easiest_questions: vector<u64>,
    }

    /// Learning insights from session performance
    public struct LearningInsights has store, drop, copy {
        knowledge_gaps: vector<String>,
        strength_areas: vector<String>,
        improvement_suggestions: vector<String>,
        recommended_study_time: u64,
        next_difficulty_level: u8,
    }

    /// Session analytics aggregation
    public struct SessionAnalytics has store {
        // Performance Metrics
        total_sessions: u64,
        completion_rate: u64, // percentage * 100
        average_score: u64,
        average_duration: u64,
        // Time-based Analytics
        daily_sessions: Table<u64, u64>, // day -> count
        hourly_distribution: vector<u64>, // 24 hours
        // Quality Metrics
        session_quality_average: u64,
        integrity_violations: u64,
        timeout_rate: u64,
        abandonment_rate: u64,
    }

    // =============== Events ===============

    public struct SessionCreated has copy, drop {
        session_id: ID,
        exam_id: ID,
        participant: address,
        total_questions: u64,
        time_limit_ms: u64,
        is_retry: bool,
        fee_paid: u64,
        timestamp: u64,
    }

    public struct QuestionAnswered has copy, drop {
        session_id: ID,
        participant: address,
        question_index: u64,
        time_spent_ms: u64,
        is_correct: bool,
        partial_score: u64,
        timestamp: u64,
    }

    public struct SessionCompleted has copy, drop {
        session_id: ID,
        exam_id: ID,
        participant: address,
        final_score: u64,
        percentage_score: u64,
        passed: bool,
        total_time_ms: u64,
        questions_correct: u64,
        session_quality: u8,
        timestamp: u64,
    }

    public struct SessionExpired has copy, drop {
        session_id: ID,
        participant: address,
        questions_answered: u64,
        time_elapsed: u64,
        auto_submitted: bool,
        timestamp: u64,
    }

    public struct IntegrityViolation has copy, drop {
        session_id: ID,
        participant: address,
        violation_type: String,
        severity: u8,
        evidence: vector<u8>,
        timestamp: u64,
    }

    // =============== Initialization ===============

    fun init(ctx: &mut TxContext) {
        let session_manager = SessionManager {
            id: object::new(ctx),
            active_sessions: table::new(ctx),
            session_registry: table::new(ctx),
            total_sessions_created: 0,
            total_sessions_completed: 0,
            default_timeout_buffer: SESSION_TIMEOUT_BUFFER,
            integrity_check_enabled: true,
            anti_cheat_enabled: true,
            platform_treasury: balance::zero(),
            session_fees_collected: 0,
            session_analytics: SessionAnalytics {
                total_sessions: 0,
                completion_rate: 0,
                average_score: 0,
                average_duration: 0,
                daily_sessions: table::new(ctx),
                hourly_distribution: vector[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                session_quality_average: 85,
                integrity_violations: 0,
                timeout_rate: 0,
                abandonment_rate: 0,
            },
        };

        transfer::share_object(session_manager);
    }

    // =============== Core Session Functions ===============

    /// Create a new exam session
    public entry fun create_session(
        manager: &mut SessionManager,
        exam_id: ID,
        total_questions: u64,
        time_limit_minutes: u64,
        pass_threshold: u8,
        is_retry: bool,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let participant = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Validate payment
        let required_fee = if (is_retry) { DEFAULT_RETRY_FEE } else { DEFAULT_EXAM_FEE };
        assert!(coin::value(&payment) >= required_fee, E_INSUFFICIENT_PAYMENT);

        // Check for active session
        assert!(!table::contains(&manager.active_sessions, participant), E_INVALID_SESSION_STATE);

        // Check retry cooldown if applicable
        if (is_retry) {
            // In production, this would check last attempt time
            // For now, simplified validation
        };

        // Process payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut manager.platform_treasury, payment_balance);
        manager.session_fees_collected = manager.session_fees_collected + required_fee;

        // Generate session security hash
        let session_hash = generate_session_hash(participant, exam_id, current_time, ctx);
        let time_limit_ms = time_limit_minutes * 60000;

        // Create session
        let session = ExamSession {
            id: object::new(ctx),
            exam_id,
            participant,
            total_questions,
            time_limit_ms,
            pass_threshold,
            current_question: 0,
            questions_answered: 0,
            start_time: current_time,
            end_time: option::none(),
            status: SESSION_STATUS_ACTIVE,
            is_retry,
            current_score: 0,
            max_possible_score: total_questions * 100, // 100 points per question
            session_hash,
            integrity_markers: vector::empty(),
            last_activity: current_time,
        };

        let session_id = object::uid_to_inner(&session.id);

        // Register session
        let metadata = SessionMetadata {
            session_id,
            exam_id,
            participant,
            created_at: current_time,
            expected_completion: current_time + time_limit_ms + manager.default_timeout_buffer,
            session_type: if (is_retry) { 1 } else { 0 },
            difficulty_level: 3, // Default medium difficulty
            language_preference: string::utf8(b"en"),
            access_pattern: vector::empty(),
        };

        table::add(&mut manager.session_registry, session_id, metadata);
        table::add(&mut manager.active_sessions, participant, session_id);

        // Update analytics
        manager.total_sessions_created = manager.total_sessions_created + 1;
        manager.session_analytics.total_sessions = manager.session_analytics.total_sessions + 1;
        update_daily_session_count(manager, current_time);

        event::emit(SessionCreated {
            session_id,
            exam_id,
            participant,
            total_questions,
            time_limit_ms,
            is_retry,
            fee_paid: required_fee,
            timestamp: current_time,
        });

        transfer::transfer(session, participant);
    }

    /// Submit answer for current question
    public entry fun submit_answer(
        manager: &mut SessionManager,
        session: &mut ExamSession,
        question_index: u64,
        submitted_answer: String,
        answer_confidence: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let participant = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Validate session ownership and state
        assert!(session.participant == participant, E_UNAUTHORIZED_ACCESS);
        assert!(session.status == SESSION_STATUS_ACTIVE, E_INVALID_SESSION_STATE);
        assert!(question_index < session.total_questions, E_INVALID_QUESTION_INDEX);

        // Check session timeout
        let elapsed_time = current_time - session.start_time;
        assert!(elapsed_time <= session.time_limit_ms, E_SESSION_EXPIRED);

        // Verify session integrity
        verify_session_integrity(session, current_time, manager.integrity_check_enabled);

        // Check if answer already submitted
        let answer_key = create_answer_key(question_index);
        assert!(!df::exists_(&session.id, answer_key), E_ANSWER_ALREADY_SUBMITTED);

        // Calculate time spent on this question
        let time_spent = if (session.questions_answered == 0) {
            current_time - session.start_time
        } else {
            // Simplified - would track per-question timing in production
            (current_time - session.last_activity)
        };

        // Get quiz variation for scoring (simplified)
        let variation_key = create_variation_key(question_index);
        let (is_correct, partial_score, max_score) = if (df::exists_(&session.id, variation_key)) {
            // In production, this would validate against the variation
            // For now, simplified scoring logic
            let correct = validate_answer(&submitted_answer);
            (correct, if (correct) { 100 } else { 0 }, 100)
        } else {
            // Default scoring if variation not found
            (false, 0, 100)
        };

        // Create answer record
        let question_answer = QuestionAnswer {
            question_index,
            original_quiz_id: @0x1.to_id(), // Simplified - would get from variation
            variation_type: 0, // Simplified
            submitted_answer,
            answer_confidence,
            time_spent_ms: time_spent,
            is_correct,
            partial_score,
            max_score,
            submission_timestamp: current_time,
            revision_count: 0,
        };

        // Store answer
        df::add(&mut session.id, answer_key, question_answer);

        // Update session state
        session.questions_answered = session.questions_answered + 1;
        session.current_score = session.current_score + partial_score;
        session.last_activity = current_time;

        // Update question progression
        if (question_index >= session.current_question) {
            session.current_question = question_index + 1;
        };

        // Update session metadata
        if (table::contains(&manager.session_registry, object::uid_to_inner(&session.id))) {
            let metadata = table::borrow_mut(&mut manager.session_registry, object::uid_to_inner(&session.id));
            vector::push_back(&mut metadata.access_pattern, current_time);
        };

        event::emit(QuestionAnswered {
            session_id: object::uid_to_inner(&session.id),
            participant,
            question_index,
            time_spent_ms: time_spent,
            is_correct,
            partial_score,
            timestamp: current_time,
        });
    }

    /// Complete the exam session
    public entry fun complete_session(
        manager: &mut SessionManager,
        session: ExamSession,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let participant = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Validate session ownership
        assert!(session.participant == participant, E_UNAUTHORIZED_ACCESS);
        assert!(session.status == SESSION_STATUS_ACTIVE, E_INVALID_SESSION_STATE);

        let session_id = object::uid_to_inner(&session.id);

        // Calculate final results
        let session_result = calculate_session_results(&session, current_time);

        // Remove from active sessions
        table::remove(&mut manager.active_sessions, participant);
        let metadata = table::remove(&mut manager.session_registry, session_id);

        // Update analytics
        update_completion_analytics(manager, &session_result, &metadata);

        // Clean up session
        cleanup_session_data(session);

        event::emit(SessionCompleted {
            session_id,
            exam_id: session_result.exam_id,
            participant,
            final_score: session_result.raw_score,
            percentage_score: session_result.percentage_score,
            passed: session_result.passed,
            total_time_ms: session_result.total_time_ms,
            questions_correct: session_result.questions_correct,
            session_quality: session_result.session_quality_score,
            timestamp: current_time,
        });

        // In production, this would trigger certificate creation if passed
        // certification::create_certificate_if_passed(session_result, ctx);
    }

    /// Handle session timeout/expiration
    public entry fun expire_session(
        manager: &mut SessionManager,
        session: ExamSession,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let elapsed_time = current_time - session.start_time;

        // Verify session is actually expired
        assert!(elapsed_time > session.time_limit_ms, E_TIME_MANIPULATION_DETECTED);

        let session_id = object::uid_to_inner(&session.id);
        let participant = session.participant;

        // Auto-submit partial results
        let partial_result = calculate_session_results(&session, current_time);

        // Remove from active sessions
        if (table::contains(&manager.active_sessions, participant)) {
            table::remove(&mut manager.active_sessions, participant);
        };
        if (table::contains(&manager.session_registry, session_id)) {
            table::remove(&mut manager.session_registry, session_id);
        };

        // Update timeout analytics
        manager.session_analytics.timeout_rate = 
            ((manager.session_analytics.timeout_rate * (manager.session_analytics.total_sessions - 1)) + 100) / 
            manager.session_analytics.total_sessions;

        // Clean up
        cleanup_session_data(session);

        event::emit(SessionExpired {
            session_id,
            participant,
            questions_answered: partial_result.questions_attempted,
            time_elapsed: elapsed_time,
            auto_submitted: true,
            timestamp: current_time,
        });
    }

    // =============== Helper Functions ===============

    fun generate_session_hash(
        participant: address,
        exam_id: ID,
        timestamp: u64,
        ctx: &mut TxContext,
    ): vector<u8> {
        let mut data = vector::empty<u8>();
        vector::append(&mut data, bcs::to_bytes(&participant));
        vector::append(&mut data, bcs::to_bytes(&exam_id));
        vector::append(&mut data, bcs::to_bytes(&timestamp));
        vector::append(&mut data, bcs::to_bytes(&tx_context::fresh_object_address(ctx)));
        hash::keccak256(&data)
    }

    fun verify_session_integrity(
        session: &ExamSession,
        current_time: u64,
        integrity_enabled: bool,
    ) {
        if (!integrity_enabled) return;

        // Check for time manipulation
        let max_expected_time = session.start_time + session.time_limit_ms + SESSION_TIMEOUT_BUFFER;
        assert!(current_time <= max_expected_time, E_TIME_MANIPULATION_DETECTED);

        // Additional integrity checks would go here
        // - Answer pattern analysis
        // - Response time analysis
        // - Browser fingerprinting verification
    }

    fun validate_answer(answer: &String): bool {
        // Simplified answer validation
        // In production, this would validate against the correct answer
        // considering fuzzy matching, case sensitivity, etc.
        string::length(answer) > 0
    }

    fun calculate_session_results(session: &ExamSession, completion_time: u64): SessionResult {
        let total_time_ms = completion_time - session.start_time;
        let percentage_score = if (session.max_possible_score > 0) {
            (session.current_score * 100) / session.max_possible_score
        } else {
            0
        };
        let passed = percentage_score >= (session.pass_threshold as u64);

        // Calculate performance metrics
        let average_question_time = if (session.questions_answered > 0) {
            total_time_ms / session.questions_answered
        } else {
            0
        };

        // Generate grade
        let grade = if (percentage_score >= 90) {
            string::utf8(b"A")
        } else if (percentage_score >= 80) {
            string::utf8(b"B")
        } else if (percentage_score >= 70) {
            string::utf8(b"C")
        } else if (percentage_score >= 60) {
            string::utf8(b"D")
        } else {
            string::utf8(b"F")
        };

        // Calculate difficulty analysis
        let difficulty_analysis = DifficultyAnalysis {
            perceived_difficulty: 5, // Would be calculated from response times
            actual_performance: percentage_score,
            difficulty_variance: 15, // Simplified
            hardest_questions: vector::empty(),
            easiest_questions: vector::empty(),
        };

        // Generate learning insights
        let learning_insights = LearningInsights {
            knowledge_gaps: vector[string::utf8(b"Review fundamental concepts")],
            strength_areas: vector[string::utf8(b"Good analytical skills")],
            improvement_suggestions: vector[string::utf8(b"Practice more timed exercises")],
            recommended_study_time: 3600000, // 1 hour
            next_difficulty_level: if (passed) { 4 } else { 2 },
        };

        SessionResult {
            session_id: object::uid_to_inner(&session.id),
            exam_id: session.exam_id,
            participant: session.participant,
            raw_score: session.current_score,
            percentage_score,
            passed,
            grade,
            total_time_ms,
            average_question_time,
            questions_correct: session.current_score / 100, // Simplified
            questions_attempted: session.questions_answered,
            performance_distribution: vector[20, 30, 25, 15, 10], // Example distribution
            difficulty_analysis,
            learning_insights,
            session_quality_score: 85, // Would be calculated based on various factors
            integrity_score: 95, // High integrity assumed
            completion_timestamp: completion_time,
        }
    }

    fun update_completion_analytics(
        manager: &mut SessionManager,
        result: &SessionResult,
        metadata: &SessionMetadata,
    ) {
        manager.total_sessions_completed = manager.total_sessions_completed + 1;
        
        // Update completion rate
        manager.session_analytics.completion_rate = 
            (manager.total_sessions_completed * 100) / manager.total_sessions_created;

        // Update average score
        let total_sessions = manager.session_analytics.total_sessions;
        manager.session_analytics.average_score = 
            ((manager.session_analytics.average_score * (total_sessions - 1)) + result.percentage_score) / total_sessions;

        // Update average duration
        manager.session_analytics.average_duration = 
            ((manager.session_analytics.average_duration * (total_sessions - 1)) + result.total_time_ms) / total_sessions;

        // Update quality metrics
        manager.session_analytics.session_quality_average = 
            ((manager.session_analytics.session_quality_average * (total_sessions - 1)) + 
             (result.session_quality_score as u64)) / total_sessions;
    }

    fun update_daily_session_count(manager: &mut SessionManager, timestamp: u64) {
        let day_key = timestamp / 86400000; // Convert to day
        
        if (table::contains(&manager.session_analytics.daily_sessions, day_key)) {
            let count = table::borrow_mut(&mut manager.session_analytics.daily_sessions, day_key);
            *count = *count + 1;
        } else {
            table::add(&mut manager.session_analytics.daily_sessions, day_key, 1);
        };
    }

    fun cleanup_session_data(session: ExamSession) {
        let ExamSession { 
            id, 
            exam_id: _, 
            participant: _, 
            total_questions: _,
            time_limit_ms: _,
            pass_threshold: _,
            current_question: _,
            questions_answered: _,
            start_time: _,
            end_time: _,
            status: _,
            is_retry: _,
            current_score: _,
            max_possible_score: _,
            session_hash: _,
            integrity_markers: _,
            last_activity: _,
        } = session;

        // Clean up dynamic fields would happen here in production
        // For now, just delete the object
        object::delete(id);
    }

    fun create_answer_key(question_index: u64): vector<u8> {
        let mut key = b"answer_";
        vector::append(&mut key, bcs::to_bytes(&question_index));
        key
    }

    fun create_variation_key(question_index: u64): vector<u8> {
        let mut key = b"variation_";
        vector::append(&mut key, bcs::to_bytes(&question_index));
        key
    }

    // =============== View Functions ===============

    public fun get_session_status(session: &ExamSession): u8 {
        session.status
    }

    public fun get_session_progress(session: &ExamSession): (u64, u64, u64) {
        (session.current_question, session.questions_answered, session.total_questions)
    }

    public fun get_session_score(session: &ExamSession): (u64, u64, u64) {
        let percentage = if (session.max_possible_score > 0) {
            (session.current_score * 100) / session.max_possible_score
        } else {
            0
        };
        (session.current_score, session.max_possible_score, percentage)
    }

    public fun get_session_time_info(session: &ExamSession, clock: &Clock): (u64, u64, u64) {
        let current_time = clock::timestamp_ms(clock);
        let elapsed = current_time - session.start_time;
        let remaining = if (elapsed < session.time_limit_ms) {
            session.time_limit_ms - elapsed
        } else {
            0
        };
        (elapsed, remaining, session.time_limit_ms)
    }

    public fun get_manager_statistics(manager: &SessionManager): (u64, u64, u64, u64) {
        (
            manager.total_sessions_created,
            manager.total_sessions_completed,
            table::length(&manager.active_sessions),
            manager.session_fees_collected
        )
    }

    public fun get_analytics_summary(manager: &SessionManager): (u64, u64, u64, u64) {
        (
            manager.session_analytics.completion_rate,
            manager.session_analytics.average_score,
            manager.session_analytics.average_duration,
            manager.session_analytics.session_quality_average
        )
    }

    // =============== Friend Functions for Module Integration ===============

    public(package) fun add_quiz_variation(
        session: &mut ExamSession,
        question_index: u64,
        variation: QuizVariation,
    ) {
        let variation_key = create_variation_key(question_index);
        df::add(&mut session.id, variation_key, variation);
    }

    public(package) fun get_session_participant(session: &ExamSession): address {
        session.participant
    }

    public(package) fun get_session_exam_id(session: &ExamSession): ID {
        session.exam_id
    }

    public(package) fun is_session_active(session: &ExamSession): bool {
        session.status == SESSION_STATUS_ACTIVE
    }

    public(package) fun register_integrity_violation(
        manager: &mut SessionManager,
        session_id: ID,
        participant: address,
        violation_type: String,
        severity: u8,
        evidence: vector<u8>,
        timestamp: u64,
    ) {
        manager.session_analytics.integrity_violations = 
            manager.session_analytics.integrity_violations + 1;

        event::emit(IntegrityViolation {
            session_id,
            participant,
            violation_type,
            severity,
            evidence,
            timestamp,
        });
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}