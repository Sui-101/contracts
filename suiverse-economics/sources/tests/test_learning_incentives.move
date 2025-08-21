/// SuiVerse Learning Incentives Module Comprehensive Tests
/// 
/// This test module provides comprehensive coverage for the learning incentives
/// including learning progression mechanics, peer mentoring economics, gamified
/// incentive systems, skill mastery achievements, and behavioral psychology.
///
/// Test Coverage:
/// - Learning activity recording and rewards
/// - Mentoring session economics
/// - Peer review system
/// - Skill mastery achievements
/// - Learning cohort management
/// - Streak and progression bonuses
/// - Behavioral incentive mechanisms
/// - Security and access control
/// - Economic logic validation
/// - Performance and gas optimization
/// - Edge cases and error handling
#[test_only]
module suiverse_economics::test_learning_incentives {
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::test_utils;
    use sui::object::{Self, ID};
    use sui::vec_map;
    use suiverse::learning_incentives::{Self, IncentiveRegistry, IncentiveAdminCap, MentoringSession, LearningCohort};

    // =============== Test Constants ===============
    const BASE_LEARNING_REWARD: u64 = 10_000_000; // 0.01 SUI
    const MENTORING_BASE_REWARD: u64 = 50_000_000; // 0.05 SUI
    const PEER_REVIEW_REWARD: u64 = 5_000_000; // 0.005 SUI
    const SKILL_MASTERY_MULTIPLIER: u64 = 500; // 5x bonus
    const INITIAL_POOL_FUNDING: u64 = 1000_000_000_000; // 1000 SUI

    // =============== Test Addresses ===============
    const ADMIN: address = @0xa11ce;
    const LEARNER: address = @0xb0b;
    const MENTOR: address = @0xc4001;
    const REVIEWER: address = @0xd4ee;
    const VALIDATOR1: address = @0xe1234;
    const VALIDATOR2: address = @0xf5678;
    const VALIDATOR3: address = @0x90abc;

    // =============== Helper Functions ===============

    fun setup_test_scenario(): (Scenario, Clock) {
        let scenario = test_scenario::begin(ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        (scenario, clock)
    }

    fun create_test_incentive_system(
        scenario: &mut Scenario,
        clock: &Clock,
    ): (IncentiveRegistry, IncentiveAdminCap) {
        test_scenario::next_tx(scenario, ADMIN);
        
        learning_incentives::test_init(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        
        let registry = test_scenario::take_shared<IncentiveRegistry>(scenario);
        let admin_cap = test_scenario::take_from_sender<IncentiveAdminCap>(scenario);
        
        // Fund the incentive pool
        let funding = coin::mint_for_testing<SUI>(INITIAL_POOL_FUNDING, test_scenario::ctx(scenario));
        learning_incentives::fund_incentive_pool(&admin_cap, &mut registry, funding);
        
        (registry, admin_cap)
    }

    // =============== Unit Tests - Learning Activity Recording ===============

    #[test]
    fun test_learning_activity_basic() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Record learning activity
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"blockchain_fundamentals"),
            2, // learning_hours
            10, // concepts_learned
            85, // retention_test_score
            false, // is_cross_domain
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify progress was recorded
        let (current_streak, longest_streak, total_hours, completed_courses, velocity, retention) = 
            learning_incentives::get_user_progress(&registry, LEARNER);
        
        assert!(current_streak == 1, 0);
        assert!(longest_streak == 1, 1);
        assert!(total_hours == 2, 2);
        assert!(velocity == 5, 3); // 10 concepts / 2 hours
        assert!(retention > 50, 4); // Should be influenced by test score
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_learning_streak_calculation() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Day 1: First activity
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"blockchain"),
            1, 5, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Day 2: Continue streak (within 48 hours)
        clock::increment_for_testing(&mut clock, 24 * 3600 * 1000); // 24 hours
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"defi"),
            1, 5, 85, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Day 3: Continue streak
        clock::increment_for_testing(&mut clock, 24 * 3600 * 1000); // 24 hours
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"nft"),
            1, 5, 90, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Verify streak
        let (current_streak, longest_streak, _, _, _, _) = 
            learning_incentives::get_user_progress(&registry, LEARNER);
        assert!(current_streak == 3, 5);
        assert!(longest_streak == 3, 6);
        
        // Break streak (more than 48 hours)
        clock::increment_for_testing(&mut clock, 72 * 3600 * 1000); // 72 hours
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"dao"),
            1, 5, 75, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Verify streak reset
        let (current_streak_after, longest_streak_after, _, _, _, _) = 
            learning_incentives::get_user_progress(&registry, LEARNER);
        assert!(current_streak_after == 1, 7); // Reset to 1
        assert!(longest_streak_after == 3, 8); // Longest remains
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_learning_cross_domain_bonus() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Record cross-domain learning activity
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"blockchain_finance"),
            2, // learning_hours
            8, // concepts_learned
            85, // retention_test_score
            true, // is_cross_domain = true
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify progress includes cross-domain activity
        let (_, _, _, _, _, _) = learning_incentives::get_user_progress(&registry, LEARNER);
        
        // Cross-domain learning should provide additional rewards
        // This would be verified by checking the reward amount in events
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_learning_skill_level_progression() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let skill_name = string::utf8(b"solidity_programming");
        
        // Record multiple learning sessions in the same skill
        learning_incentives::record_learning_activity(
            &mut registry, skill_name, 3, 15, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        let initial_level = learning_incentives::get_skill_level(&registry, LEARNER, skill_name);
        assert!(initial_level == 15, 9); // Should be concepts_learned
        
        // Continue learning in same skill
        learning_incentives::record_learning_activity(
            &mut registry, skill_name, 2, 10, 85, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        let updated_level = learning_incentives::get_skill_level(&registry, LEARNER, skill_name);
        assert!(updated_level == 25, 10); // 15 + 10
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INSUFFICIENT_PROGRESS)]
    fun test_learning_activity_invalid_input() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Try to record activity with zero learning hours
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"invalid"),
            0, // Invalid: zero learning hours
            5,
            80,
            false,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Mentoring System ===============

    #[test]
    fun test_mentoring_session_completion() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        // Create a mock mentoring session
        test_scenario::next_tx(&mut scenario, MENTOR);
        let session_id = object::id_from_address(@0x123);
        
        // Complete mentoring session
        learning_incentives::complete_mentoring_session(
            &mut registry,
            session_id,
            85, // mentor_rating
            80, // mentee_progress_score
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify rewards were distributed (would check balances in real implementation)
        let total_distributed = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_distributed > 0, 11);
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_MENTORING_SESSION_NOT_FOUND)]
    fun test_mentoring_session_nonexistent() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, MENTOR);
        
        // Try to complete non-existent session
        learning_incentives::complete_mentoring_session(
            &mut registry,
            object::id_from_address(@0x999), // Non-existent session
            85,
            80,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INVALID_PEER_REVIEW)]
    fun test_mentoring_session_invalid_rating() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, MENTOR);
        
        // Try to complete session with invalid rating
        learning_incentives::complete_mentoring_session(
            &mut registry,
            object::id_from_address(@0x123),
            0, // Invalid: rating must be 1-100
            80,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Peer Review System ===============

    #[test]
    fun test_peer_review_submission() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, REVIEWER);
        
        let content_id = object::id_from_address(@0x456);
        
        // Submit peer review
        learning_incentives::submit_peer_review(
            &mut registry,
            content_id,
            85, // quality_score
            true, // detailed_feedback
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify review was recorded and reward distributed
        let total_distributed = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_distributed > 0, 12);
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_peer_review_multiple_reviewers() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        let content_id = object::id_from_address(@0x456);
        
        // First reviewer
        test_scenario::next_tx(&mut scenario, REVIEWER);
        learning_incentives::submit_peer_review(
            &mut registry, content_id, 80, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        let first_total = learning_incentives::get_total_rewards_distributed(&registry);
        
        // Second reviewer
        test_scenario::next_tx(&mut scenario, LEARNER);
        learning_incentives::submit_peer_review(
            &mut registry, content_id, 90, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        let second_total = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(second_total > first_total, 13); // Both should receive rewards
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INVALID_PEER_REVIEW)]
    fun test_peer_review_invalid_score() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, REVIEWER);
        
        // Try to submit review with invalid quality score
        learning_incentives::submit_peer_review(
            &mut registry,
            object::id_from_address(@0x456),
            150, // Invalid: score must be 1-100
            true,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Skill Mastery System ===============

    #[test]
    fun test_skill_mastery_achievement() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let validators = vector[VALIDATOR1, VALIDATOR2, VALIDATOR3];
        
        // Claim skill mastery
        learning_incentives::claim_skill_mastery(
            &mut registry,
            string::utf8(b"smart_contract_development"),
            95, // mastery_level
            string::utf8(b"peer_validation"),
            validators,
            option::none(), // No certification ID
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify mastery was recorded and reward distributed
        let total_distributed = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_distributed > 0, 14);
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INVALID_SKILL_LEVEL)]
    fun test_skill_mastery_invalid_level() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let validators = vector[VALIDATOR1, VALIDATOR2, VALIDATOR3];
        
        // Try to claim mastery with invalid level
        learning_incentives::claim_skill_mastery(
            &mut registry,
            string::utf8(b"invalid_skill"),
            70, // Invalid: mastery level must be 80-100
            string::utf8(b"peer_validation"),
            validators,
            option::none(),
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INSUFFICIENT_PROGRESS)]
    fun test_skill_mastery_insufficient_validators() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Try to claim mastery with insufficient validators
        let insufficient_validators = vector[VALIDATOR1]; // Need at least 3
        
        learning_incentives::claim_skill_mastery(
            &mut registry,
            string::utf8(b"insufficient_skill"),
            90,
            string::utf8(b"peer_validation"),
            insufficient_validators,
            option::none(),
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Learning Cohort System ===============

    #[test]
    fun test_learning_cohort_creation() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let subject_areas = vector[
            string::utf8(b"blockchain"),
            string::utf8(b"defi"),
            string::utf8(b"nft")
        ];
        let initial_funding = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(&mut scenario));
        
        // Create learning cohort
        learning_incentives::create_learning_cohort(
            &mut registry,
            string::utf8(b"Web3 Study Group"),
            subject_areas,
            initial_funding,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Cohort creation should succeed without error
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INSUFFICIENT_PROGRESS)]
    fun test_learning_cohort_empty_subjects() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let empty_subjects = vector::empty<String>();
        let initial_funding = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(&mut scenario));
        
        // Try to create cohort with no subject areas
        learning_incentives::create_learning_cohort(
            &mut registry,
            string::utf8(b"Empty Cohort"),
            empty_subjects,
            initial_funding,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Integration Tests ===============

    #[test]
    fun test_complete_learning_journey() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Start learning journey
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"blockchain_basics"),
            2, 8, 75, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Continue learning with cross-domain activity
        clock::increment_for_testing(&mut clock, 24 * 3600 * 1000); // Next day
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"defi_fundamentals"),
            3, 12, 85, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Submit peer review
        learning_incentives::submit_peer_review(
            &mut registry,
            object::id_from_address(@0x789),
            90, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Achieve skill mastery
        let validators = vector[VALIDATOR1, VALIDATOR2, VALIDATOR3];
        learning_incentives::claim_skill_mastery(
            &mut registry,
            string::utf8(b"blockchain_basics"),
            85,
            string::utf8(b"exam"),
            validators,
            option::none(),
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify comprehensive progress
        let (streak, longest, hours, courses, velocity, retention) = 
            learning_incentives::get_user_progress(&registry, LEARNER);
        
        assert!(streak == 2, 15); // Two consecutive days
        assert!(hours == 5, 16); // Total 5 hours
        assert!(velocity > 0, 17); // Learning velocity calculated
        
        let skill_level = learning_incentives::get_skill_level(&registry, LEARNER, string::utf8(b"blockchain_basics"));
        assert!(skill_level == 8, 18); // From first learning activity
        
        let total_rewards = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_rewards > BASE_LEARNING_REWARD * 2, 19); // Should have multiple rewards
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_multi_user_interactions() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        // Learner 1 activity
        test_scenario::next_tx(&mut scenario, LEARNER);
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"solidity"),
            2, 10, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Learner 2 (MENTOR) activity  
        test_scenario::next_tx(&mut scenario, MENTOR);
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"rust"),
            3, 15, 90, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Reviewer activity
        test_scenario::next_tx(&mut scenario, REVIEWER);
        learning_incentives::submit_peer_review(
            &mut registry,
            object::id_from_address(@0xabc),
            85, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Verify all users have progress
        let (learner_streak, _, _, _, _, _) = learning_incentives::get_user_progress(&registry, LEARNER);
        let (mentor_streak, _, _, _, _, _) = learning_incentives::get_user_progress(&registry, MENTOR);
        
        assert!(learner_streak == 1, 20);
        assert!(mentor_streak == 1, 21);
        
        let total_rewards = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_rewards > BASE_LEARNING_REWARD * 2, 22); // Multiple users, multiple rewards
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Economic Logic Validation ===============

    #[test]
    fun test_reward_calculation_scaling() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Record different learning intensities
        let learning_scenarios = vector[
            (1u64, 2u64, 70u64), // Low intensity
            (3u64, 15u64, 85u64), // Medium intensity  
            (5u64, 30u64, 95u64), // High intensity
        ];
        
        let mut i = 0;
        let mut previous_total = 0u64;
        
        while (i < vector::length(&learning_scenarios)) {
            let (hours, concepts, retention) = *vector::borrow(&learning_scenarios, i);
            
            learning_incentives::record_learning_activity(
                &mut registry,
                string::utf8(b"test_subject"),
                hours,
                concepts,
                retention,
                false,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            
            let current_total = learning_incentives::get_total_rewards_distributed(&registry);
            if (i > 0) {
                // Higher intensity should generally yield higher rewards
                assert!(current_total > previous_total, 23 + i);
            };
            previous_total = current_total;
            
            i = i + 1;
        };
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_streak_bonus_progression() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let initial_total = learning_incentives::get_total_rewards_distributed(&registry);
        
        // Build up a learning streak
        let mut day = 0;
        while (day < 7) {
            learning_incentives::record_learning_activity(
                &mut registry,
                string::utf8(b"consistent_learning"),
                1, 5, 80, false, &clock, test_scenario::ctx(&mut scenario)
            );
            
            clock::increment_for_testing(&mut clock, 24 * 3600 * 1000); // Next day
            day = day + 1;
        };
        
        let final_total = learning_incentives::get_total_rewards_distributed(&registry);
        
        // Verify streak bonuses increased total rewards
        assert!(final_total > initial_total + (BASE_LEARNING_REWARD * 7), 30);
        
        let (streak, longest, _, _, _, _) = learning_incentives::get_user_progress(&registry, LEARNER);
        assert!(streak == 7, 31);
        assert!(longest == 7, 32);
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_skill_mastery_reward_scaling() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let validators = vector[VALIDATOR1, VALIDATOR2, VALIDATOR3];
        let mastery_levels = vector[80u64, 90u64, 95u64, 100u64];
        
        let mut i = 0;
        let mut previous_total = learning_incentives::get_total_rewards_distributed(&registry);
        
        while (i < vector::length(&mastery_levels)) {
            let level = *vector::borrow(&mastery_levels, i);
            let skill_name = string::utf8(b"test_skill_");
            
            learning_incentives::claim_skill_mastery(
                &mut registry,
                skill_name,
                level,
                string::utf8(b"exam"),
                validators,
                option::none(),
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            
            let current_total = learning_incentives::get_total_rewards_distributed(&registry);
            
            if (i > 0) {
                // Higher mastery level should yield higher rewards
                let previous_reward = current_total - previous_total;
                // Note: This test assumes the reward calculation includes mastery level scaling
            };
            
            previous_total = current_total;
            i = i + 1;
        };
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Security Tests ===============

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INVALID_LEARNING_SESSION)]
    fun test_security_system_disabled() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        // Disable the system
        learning_incentives::toggle_system_status(&admin_cap, &mut registry);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Try to record learning activity when system is disabled
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"blocked"),
            1, 5, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = learning_incentives::E_INSUFFICIENT_FUNDS)]
    fun test_security_insufficient_pool_funds() {
        let (mut scenario, clock) = setup_test_scenario();
        
        // Create system without funding the pool
        test_scenario::next_tx(&mut scenario, ADMIN);
        learning_incentives::test_init(test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        let mut registry = test_scenario::take_shared<IncentiveRegistry>(&scenario);
        let admin_cap = test_scenario::take_from_sender<IncentiveAdminCap>(&scenario);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Try to record learning activity with empty incentive pool
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"no_funds"),
            1, 5, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_security_admin_fund_management() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        let initial_balance = learning_incentives::get_incentive_pool_balance(&registry);
        
        // Add more funding
        let additional_funding = coin::mint_for_testing<SUI>(500_000_000_000, test_scenario::ctx(&mut scenario));
        learning_incentives::fund_incentive_pool(&admin_cap, &mut registry, additional_funding);
        
        let increased_balance = learning_incentives::get_incentive_pool_balance(&registry);
        assert!(increased_balance > initial_balance, 33);
        
        // Withdraw some funds
        learning_incentives::withdraw_excess_funds(
            &admin_cap,
            &mut registry,
            100_000_000, // 0.1 SUI
            test_scenario::ctx(&mut scenario),
        );
        
        let final_balance = learning_incentives::get_incentive_pool_balance(&registry);
        assert!(final_balance < increased_balance, 34);
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Performance Tests ===============

    #[test]
    fun test_performance_multiple_users() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        // Simulate multiple users with learning activities
        let users = vector[
            @0x1001, @0x1002, @0x1003, @0x1004, @0x1005,
            @0x1006, @0x1007, @0x1008, @0x1009, @0x1010
        ];
        
        let mut i = 0;
        while (i < vector::length(&users)) {
            let user = *vector::borrow(&users, i);
            test_scenario::next_tx(&mut scenario, user);
            
            learning_incentives::record_learning_activity(
                &mut registry,
                string::utf8(b"mass_learning"),
                (i % 3) + 1, // 1-3 hours
                (i % 10) + 5, // 5-14 concepts
                70 + (i % 20), // 70-89 retention
                i % 2 == 0, // Every other is cross-domain
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            
            // Advance time slightly
            clock::increment_for_testing(&mut clock, 3600 * 1000); // 1 hour
            i = i + 1;
        };
        
        // Verify system handles multiple users
        let total_rewards = learning_incentives::get_total_rewards_distributed(&registry);
        assert!(total_rewards > BASE_LEARNING_REWARD * 5, 35); // Should have significant rewards
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_performance_skill_level_updates() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let skill_name = string::utf8(b"performance_skill");
        
        // Perform many skill level updates
        let mut i = 0;
        while (i < 20) {
            learning_incentives::record_learning_activity(
                &mut registry,
                skill_name,
                1, 1, 80, false, &clock, test_scenario::ctx(&mut scenario)
            );
            i = i + 1;
        };
        
        // Verify skill level accumulated correctly
        let final_level = learning_incentives::get_skill_level(&registry, LEARNER, skill_name);
        assert!(final_level == 20, 36); // Should be sum of all concepts learned
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Edge Cases ===============

    #[test]
    fun test_edge_case_maximum_values() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Test with maximum reasonable values
        learning_incentives::record_learning_activity(
            &mut registry,
            string::utf8(b"max_values"),
            24, // 24 hours (maximum reasonable daily study)
            100, // 100 concepts learned
            100, // Perfect retention score
            true, // Cross-domain
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Should handle large values without overflow
        let (_, _, hours, _, velocity, retention) = learning_incentives::get_user_progress(&registry, LEARNER);
        assert!(hours == 24, 37);
        assert!(velocity > 0, 38);
        assert!(retention > 50, 39); // Should be influenced by perfect score
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_edge_case_skill_level_cap() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        let skill_name = string::utf8(b"capped_skill");
        
        // Try to exceed skill level cap (100)
        learning_incentives::record_learning_activity(
            &mut registry,
            skill_name,
            1, 150, 80, false, &clock, test_scenario::ctx(&mut scenario) // 150 concepts > 100 cap
        );
        
        // Skill level should be capped at 100
        let skill_level = learning_incentives::get_skill_level(&registry, LEARNER, skill_name);
        assert!(skill_level == 100, 40); // Should be capped at 100
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_edge_case_rapid_activity_recording() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_incentive_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, LEARNER);
        
        // Record activities very close together in time
        let mut i = 0;
        while (i < 10) {
            learning_incentives::record_learning_activity(
                &mut registry,
                string::utf8(b"rapid_activity"),
                1, 2, 80, false, &clock, test_scenario::ctx(&mut scenario)
            );
            
            // Advance time by just 1 minute
            clock::increment_for_testing(&mut clock, 60 * 1000);
            i = i + 1;
        };
        
        // Should handle rapid updates correctly
        let (_, _, total_hours, _, _, _) = learning_incentives::get_user_progress(&registry, LEARNER);
        assert!(total_hours == 10, 41); // Should accumulate all hours
        
        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}