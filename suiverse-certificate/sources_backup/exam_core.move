/// SuiVerse Exam Core Module
/// 
/// This module handles the core exam management functionality including
/// exam creation, configuration, activation, and integration with other
/// assessment modules.
///
/// Key Features:
/// - Exam creation with governance validation
/// - Economic model configuration (40/60 revenue split)
/// - Exam activation when quiz threshold is met
/// - Integration with session management and analytics
/// - Certificate generation coordination
module suiverse_certificate::exam_core {
    use std::string::{Self as string, String};
    // use std::option; // Implicit import
    use sui::object;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;

    // =============== Error Constants ===============
    const E_INSUFFICIENT_DEPOSIT: u64 = 80001;
    const E_INVALID_EXAM_CONFIG: u64 = 80002;
    const E_EXAM_NOT_FOUND: u64 = 80003;
    const E_NOT_AUTHORIZED: u64 = 80004;
    const E_EXAM_NOT_ACTIVE: u64 = 80005;
    const E_INSUFFICIENT_QUIZ_COUNT: u64 = 80006;
    const E_INVALID_PARAMETERS: u64 = 80007;

    // =============== Exam Constants ===============
    const EXAM_CREATION_DEPOSIT: u64 = 500_000_000_000; // 500 SUI
    const DEFAULT_EXAM_FEE: u64 = 5_000_000_000; // 5 SUI
    const DEFAULT_RETRY_FEE: u64 = 3_000_000_000; // 3 SUI
    const DEFAULT_RETRY_COOLDOWN: u64 = 604800000; // 7 days
    const MIN_PASS_THRESHOLD: u8 = 50;
    const MAX_PASS_THRESHOLD: u8 = 95;
    const MIN_QUIZ_COUNT: u64 = 10;
    const MAX_QUIZ_COUNT: u64 = 1000;
    const CREATOR_REVENUE_PERCENT: u8 = 40;
    const PLATFORM_REVENUE_PERCENT: u8 = 60;

    // =============== Exam Status Constants ===============
    const EXAM_STATUS_DISABLED: u8 = 0;
    const EXAM_STATUS_ACTIVE: u8 = 1;
    const EXAM_STATUS_SUSPENDED: u8 = 2;

    // =============== Core Structures ===============

    /// Exam management system
    public struct ExamManager has key {
        id: object::UID,
        // Statistics
        total_exams_created: u64,
        total_exam_attempts: u64,
        total_certificates_issued: u64,
        total_revenue_collected: u64,
        // Configuration
        exam_creation_deposit: u64,
        min_quiz_threshold: u64,
        // Treasury
        platform_treasury: Balance<SUI>,
        // Admin
        admin: address,
    }

    /// Comprehensive exam configuration
    public struct Exam has key, store {
        id: object::UID,
        // Basic Information
        name: String,
        description: String,
        creator: address,
        // Quiz Requirements
        required_quiz_count: u64,
        quiz_categories: vector<String>,
        difficulty_distribution: vector<u8>, // [easy%, medium%, hard%]
        // Exam Parameters
        total_questions: u64,
        time_limit_minutes: u64,
        pass_threshold: u8, // percentage
        retry_cooldown_hours: u64,
        // Economic Settings
        exam_fee: u64,
        retry_fee: u64,
        creator_revenue_percentage: u8,
        // Status and Analytics
        status: u8,
        current_quiz_count: u64,
        total_attempts: u64,
        total_passes: u64,
        average_score: u64,
        // Revenue Tracking
        total_revenue: u64,
        creator_earnings: u64,
        // Timestamps
        created_at: u64,
        activated_at: Option<u64>,
        last_updated: u64,
    }

    /// Exam creation request for governance validation
    public struct ExamCreationRequest has key {
        id: object::UID,
        creator: address,
        name: String,
        description: String,
        deposit: Balance<SUI>,
        // Proposed Configuration
        proposed_quiz_count: u64,
        proposed_questions: u64,
        proposed_time_limit: u64,
        proposed_pass_threshold: u8,
        proposed_exam_fee: u64,
        proposed_retry_fee: u64,
        proposed_categories: vector<String>,
        proposed_difficulty_distribution: vector<u8>,
        // Governance
        status: u8, // 0: pending, 1: approved, 2: rejected
        created_at: u64,
        validation_deadline: u64,
    }

    /// Revenue distribution record
    public struct RevenueDistribution has store, drop {
        exam_id: object::ID,
        session_id: object::ID,
        total_amount: u64,
        creator_share: u64,
        platform_share: u64,
        quiz_creators_share: u64,
        distribution_timestamp: u64,
    }

    // =============== Events ===============

    public struct ExamCreationRequestSubmitted has copy, drop {
        request_id: object::ID,
        creator: address,
        name: String,
        proposed_quiz_count: u64,
        deposit_amount: u64,
        timestamp: u64,
    }

    public struct ExamCreated has copy, drop {
        exam_id: object::ID,
        creator: address,
        name: String,
        total_questions: u64,
        exam_fee: u64,
        required_quiz_count: u64,
        timestamp: u64,
    }

    public struct ExamActivated has copy, drop {
        exam_id: object::ID,
        quiz_count_reached: u64,
        activation_timestamp: u64,
    }

    public struct RevenueDistributed has copy, drop {
        exam_id: object::ID,
        session_id: object::ID,
        total_amount: u64,
        creator_share: u64,
        platform_share: u64,
        quiz_creators_share: u64,
        timestamp: u64,
    }

    public struct ExamUpdated has copy, drop {
        exam_id: object::ID,
        update_type: String,
        old_value: u64,
        new_value: u64,
        timestamp: u64,
    }

    // =============== Initialization ===============

    fun init(ctx: &mut TxContext) {
        let exam_manager = ExamManager {
            id: object::new(ctx),
            total_exams_created: 0,
            total_exam_attempts: 0,
            total_certificates_issued: 0,
            total_revenue_collected: 0,
            exam_creation_deposit: EXAM_CREATION_DEPOSIT,
            min_quiz_threshold: MIN_QUIZ_COUNT,
            platform_treasury: balance::zero(),
            admin: tx_context::sender(ctx),
        };

        transfer::share_object(exam_manager);
    }

    // =============== Exam Creation and Management ===============

    /// Submit exam creation request with deposit
    public entry fun create_exam_request(
        manager: &mut ExamManager,
        name: String,
        description: String,
        proposed_quiz_count: u64,
        proposed_questions: u64,
        proposed_time_limit: u64,
        proposed_pass_threshold: u8,
        proposed_exam_fee: u64,
        proposed_retry_fee: u64,
        proposed_categories: vector<String>,
        proposed_difficulty_distribution: vector<u8>,
        deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Validate deposit
        assert!(
            coin::value(&deposit) >= manager.exam_creation_deposit,
            E_INSUFFICIENT_DEPOSIT
        );

        // Validate parameters
        validate_exam_parameters(
            proposed_quiz_count,
            proposed_questions,
            proposed_time_limit,
            proposed_pass_threshold,
            &proposed_categories,
            &proposed_difficulty_distribution,
        );

        let request = ExamCreationRequest {
            id: object::new(ctx),
            creator,
            name,
            description,
            deposit: coin::into_balance(deposit),
            proposed_quiz_count,
            proposed_questions,
            proposed_time_limit,
            proposed_pass_threshold,
            proposed_exam_fee,
            proposed_retry_fee,
            proposed_categories,
            proposed_difficulty_distribution,
            status: 0, // Pending
            created_at: current_time,
            validation_deadline: current_time + 2592000000, // 30 days
        };

        let request_id = object::uid_to_inner(&request.id);

        event::emit(ExamCreationRequestSubmitted {
            request_id,
            creator,
            name: request.name,
            proposed_quiz_count,
            deposit_amount: manager.exam_creation_deposit,
            timestamp: current_time,
        });

        transfer::share_object(request);
    }

    /// Approve exam creation request (governance function)
    public fun approve_exam_creation(
        manager: &mut ExamManager,
        request: ExamCreationRequest,
        clock: &Clock,
        ctx: &mut TxContext,
    ): ID {
        // Only admin can approve (in production, this would integrate with governance)
        assert!(tx_context::sender(ctx) == manager.admin, E_NOT_AUTHORIZED);

        let ExamCreationRequest {
            id: request_id,
            creator,
            name,
            description,
            deposit,
            proposed_quiz_count,
            proposed_questions,
            proposed_time_limit,
            proposed_pass_threshold,
            proposed_exam_fee,
            proposed_retry_fee,
            proposed_categories,
            proposed_difficulty_distribution,
            status: _,
            created_at: _,
            validation_deadline: _,
        } = request;

        let current_time = clock::timestamp_ms(clock);

        // Create exam
        let exam = Exam {
            id: object::new(ctx),
            name,
            description,
            creator,
            required_quiz_count: proposed_quiz_count,
            quiz_categories: proposed_categories,
            difficulty_distribution: proposed_difficulty_distribution,
            total_questions: proposed_questions,
            time_limit_minutes: proposed_time_limit,
            pass_threshold: proposed_pass_threshold,
            retry_cooldown_hours: DEFAULT_RETRY_COOLDOWN / 3600000, // Convert to hours
            exam_fee: proposed_exam_fee,
            retry_fee: proposed_retry_fee,
            creator_revenue_percentage: CREATOR_REVENUE_PERCENT,
            status: EXAM_STATUS_DISABLED, // Disabled until quiz threshold met
            current_quiz_count: 0,
            total_attempts: 0,
            total_passes: 0,
            average_score: 0,
            total_revenue: 0,
            creator_earnings: 0,
            created_at: current_time,
            activated_at: option::none(),
            last_updated: current_time,
        };

        let exam_id = object::uid_to_inner(&exam.id);

        // Return deposit to creator
        let refund = coin::from_balance(deposit, ctx);
        transfer::public_transfer(refund, creator);

        // Update manager statistics
        manager.total_exams_created = manager.total_exams_created + 1;

        event::emit(ExamCreated {
            exam_id,
            creator,
            name: exam.name,
            total_questions: exam.total_questions,
            exam_fee: exam.exam_fee,
            required_quiz_count: exam.required_quiz_count,
            timestamp: current_time,
        });

        // Clean up request
        object::delete(request_id);

        // Transfer exam ownership
        transfer::share_object(exam);

        exam_id
    }

    /// Activate exam when quiz threshold is met
    public entry fun activate_exam_if_ready(
        exam: &mut Exam,
        current_quiz_count: u64,
        clock: &Clock,
    ) {
        if (exam.status == EXAM_STATUS_DISABLED && 
            current_quiz_count >= exam.required_quiz_count) {
            
            let current_time = clock::timestamp_ms(clock);
            exam.status = EXAM_STATUS_ACTIVE;
            exam.current_quiz_count = current_quiz_count;
            exam.activated_at = option::some(current_time);
            exam.last_updated = current_time;

            event::emit(ExamActivated {
                exam_id: object::uid_to_inner(&exam.id),
                quiz_count_reached: current_quiz_count,
                activation_timestamp: current_time,
            });
        }
    }

    /// Update exam statistics after session completion
    public entry fun update_exam_completion_stats(
        manager: &mut ExamManager,
        exam: &mut Exam,
        score: u64,
        passed: bool,
        _time_taken: u64,
        revenue_amount: u64,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);

        // Update exam statistics
        exam.total_attempts = exam.total_attempts + 1;
        if (passed) {
            exam.total_passes = exam.total_passes + 1;
        };

        // Update average score
        exam.average_score = ((exam.average_score * (exam.total_attempts - 1)) + score) / exam.total_attempts;

        // Update revenue
        exam.total_revenue = exam.total_revenue + revenue_amount;
        let creator_share = (revenue_amount * (exam.creator_revenue_percentage as u64)) / 100;
        exam.creator_earnings = exam.creator_earnings + creator_share;

        exam.last_updated = current_time;

        // Update manager statistics
        manager.total_exam_attempts = manager.total_exam_attempts + 1;
        manager.total_revenue_collected = manager.total_revenue_collected + revenue_amount;

        if (passed) {
            manager.total_certificates_issued = manager.total_certificates_issued + 1;
        };

        event::emit(ExamUpdated {
            exam_id: object::uid_to_inner(&exam.id),
            update_type: string::utf8(b"completion_stats"),
            old_value: exam.total_attempts - 1,
            new_value: exam.total_attempts,
            timestamp: current_time,
        });
    }

    /// Process revenue distribution for completed exam
    public fun distribute_exam_revenue(
        _manager: &mut ExamManager,
        exam: &Exam,
        session_id: object::ID,
        payment_amount: u64,
        quiz_creators: vector<address>,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let exam_id = object::uid_to_inner(&exam.id);

        // Calculate distribution
        let creator_share = (payment_amount * (exam.creator_revenue_percentage as u64)) / 100;
        let platform_share = payment_amount - creator_share;
        
        // For simplicity, quiz creators share comes from platform portion
        let quiz_creators_count = vector::length(&quiz_creators);
        let quiz_creators_share = if (quiz_creators_count > 0) {
            platform_share / 4 // 25% of platform share to quiz creators
        } else {
            0
        };

        let actual_platform_share = platform_share - quiz_creators_share;

        // Store revenue distribution record
        let _distribution = RevenueDistribution {
            exam_id,
            session_id,
            total_amount: payment_amount,
            creator_share,
            platform_share: actual_platform_share,
            quiz_creators_share,
            distribution_timestamp: current_time,
        };

        // In production, this would handle actual token transfers
        // For now, just emit the event
        event::emit(RevenueDistributed {
            exam_id,
            session_id,
            total_amount: payment_amount,
            creator_share,
            platform_share: actual_platform_share,
            quiz_creators_share,
            timestamp: current_time,
        });
    }

    // =============== Helper Functions ===============

    fun validate_exam_parameters(
        quiz_count: u64,
        questions: u64,
        time_limit: u64,
        pass_threshold: u8,
        categories: &vector<String>,
        difficulty_distribution: &vector<u8>,
    ) {
        assert!(questions > 0, E_INVALID_EXAM_CONFIG);
        assert!(time_limit > 0, E_INVALID_EXAM_CONFIG);
        assert!(
            pass_threshold >= MIN_PASS_THRESHOLD && 
            pass_threshold <= MAX_PASS_THRESHOLD,
            E_INVALID_EXAM_CONFIG
        );
        assert!(
            quiz_count >= MIN_QUIZ_COUNT && 
            quiz_count <= MAX_QUIZ_COUNT,
            E_INVALID_EXAM_CONFIG
        );
        assert!(vector::length(categories) > 0, E_INVALID_EXAM_CONFIG);
        assert!(vector::length(difficulty_distribution) == 3, E_INVALID_EXAM_CONFIG);

        // Validate difficulty distribution sums to 100
        let sum = *vector::borrow(difficulty_distribution, 0) +
                 *vector::borrow(difficulty_distribution, 1) +
                 *vector::borrow(difficulty_distribution, 2);
        assert!(sum == 100, E_INVALID_EXAM_CONFIG);
    }

    // =============== View Functions ===============

    public fun get_exam_status(exam: &Exam): u8 {
        exam.status
    }

    public fun get_exam_config(exam: &Exam): (u64, u64, u8, u64, u64) {
        (
            exam.total_questions,
            exam.time_limit_minutes,
            exam.pass_threshold,
            exam.exam_fee,
            exam.retry_fee
        )
    }

    public fun get_exam_statistics(exam: &Exam): (u64, u64, u64, u64) {
        (
            exam.total_attempts,
            exam.total_passes,
            exam.average_score,
            exam.total_revenue
        )
    }

    public fun get_quiz_requirements(exam: &Exam): (u64, u64, vector<String>) {
        (
            exam.required_quiz_count,
            exam.current_quiz_count,
            exam.quiz_categories
        )
    }

    public fun is_exam_active(exam: &Exam): bool {
        exam.status == EXAM_STATUS_ACTIVE
    }

    public fun is_exam_ready_for_activation(exam: &Exam): bool {
        exam.status == EXAM_STATUS_DISABLED && 
        exam.current_quiz_count >= exam.required_quiz_count
    }

    public fun get_manager_statistics(manager: &ExamManager): (u64, u64, u64, u64) {
        (
            manager.total_exams_created,
            manager.total_exam_attempts,
            manager.total_certificates_issued,
            manager.total_revenue_collected
        )
    }

    public fun get_exam_revenue_config(exam: &Exam): (u8, u64, u64) {
        (
            exam.creator_revenue_percentage,
            exam.total_revenue,
            exam.creator_earnings
        )
    }

    // =============== Friend Functions for Module Integration ===============

    public(package) fun update_quiz_count(exam: &mut Exam, new_count: u64) {
        exam.current_quiz_count = new_count;
        exam.last_updated = 0; // Would use actual timestamp in production
    }

    public(package) fun get_exam_creator(exam: &Exam): address {
        exam.creator
    }

    public(package) fun get_exam_id(exam: &Exam): ID {
        object::uid_to_inner(&exam.id)
    }

    public(package) fun get_exam_fee_info(exam: &Exam, is_retry: bool): u64 {
        if (is_retry) {
            exam.retry_fee
        } else {
            exam.exam_fee
        }
    }

    // =============== Test Functions ===============

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}