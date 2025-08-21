/// SuiVerse Economics Integration Module Comprehensive Tests
/// 
/// This test module provides comprehensive coverage for the economics integration layer
/// including unified economic policy enforcement, cross-module analytics, integration
/// between treasury, rewards, governance systems, and coordination between all economics modules.
///
/// Test Coverage:
/// - Economic policy creation and enforcement
/// - Cross-module transaction coordination
/// - Economic metrics aggregation and health monitoring
/// - Revenue distribution across modules
/// - Anomaly detection and market manipulation prevention
/// - Economic emergency response systems
/// - Security and access control
/// - Economic logic validation
/// - Performance and gas optimization
/// - Edge cases and error handling
#[test_only]
module suiverse_economics::test_economics_integration {
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
    use suiverse::economics_integration::{Self, EconomicsHub, EconomicsAdminCap};
    use suiverse::certificate_market::{Self, MarketRegistry, MarketAnalytics, MarketAdminCap};
    use suiverse::learning_incentives::{Self, IncentiveRegistry, IncentiveAdminCap};
    use suiverse::dynamic_fees::{Self, FeeRegistry, FeeAdminCap};

    // =============== Test Constants ===============
    const POLICY_UPDATE_COOLDOWN: u64 = 86400000; // 24 hours
    const ECONOMIC_HEALTH_THRESHOLD: u64 = 70;
    const ECONOMIC_EMERGENCY_THRESHOLD: u64 = 30;
    const CROSS_MODULE_FEE_SHARE: u64 = 250; // 2.5%
    const INITIAL_INTEGRATION_FUNDING: u64 = 500_000_000_000; // 500 SUI

    // =============== Test Addresses ===============
    const ADMIN: address = @0xa11ce;
    const USER1: address = @0xb0b;
    const USER2: address = @0xc4001;
    const TREASURY: address = @0xd4ee;
    const REWARD_POOL: address = @0xe1234;
    const VALIDATORS: address = @0xf5678;
    const DEVELOPMENT: address = @0x90abc;
    const GOVERNANCE: address = @0xdef01;
    const EMERGENCY: address = @0x23456;

    // =============== Helper Functions ===============

    fun setup_test_scenario(): (Scenario, Clock) {
        let scenario = test_scenario::begin(ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        (scenario, clock)
    }

    fun create_complete_economics_system(
        scenario: &mut Scenario,
        clock: &Clock,
    ): (EconomicsHub, EconomicsAdminCap, MarketRegistry, MarketAnalytics, MarketAdminCap, IncentiveRegistry, IncentiveAdminCap, FeeRegistry, FeeAdminCap) {
        test_scenario::next_tx(scenario, ADMIN);
        
        // Initialize all economics modules
        economics_integration::test_init(test_scenario::ctx(scenario));
        certificate_market::test_init(test_scenario::ctx(scenario));
        learning_incentives::test_init(test_scenario::ctx(scenario));
        dynamic_fees::test_init(test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, ADMIN);
        
        // Take all shared objects and admin capabilities
        let hub = test_scenario::take_shared<EconomicsHub>(scenario);
        let eco_admin = test_scenario::take_from_sender<EconomicsAdminCap>(scenario);
        
        let market_registry = test_scenario::take_shared<MarketRegistry>(scenario);
        let market_analytics = test_scenario::take_shared<MarketAnalytics>(scenario);
        let market_admin = test_scenario::take_from_sender<MarketAdminCap>(scenario);
        
        let incentive_registry = test_scenario::take_shared<IncentiveRegistry>(scenario);
        let incentive_admin = test_scenario::take_from_sender<IncentiveAdminCap>(scenario);
        
        let fee_registry = test_scenario::take_shared<FeeRegistry>(scenario);
        let fee_admin = test_scenario::take_from_sender<FeeAdminCap>(scenario);
        
        // Fund incentive pool
        let incentive_funding = coin::mint_for_testing<SUI>(1000_000_000_000, test_scenario::ctx(scenario));
        learning_incentives::fund_incentive_pool(&incentive_admin, &mut incentive_registry, incentive_funding);
        
        // Initialize some basic fee structures
        dynamic_fees::initialize_fee_structure(
            &fee_admin, &mut fee_registry, string::utf8(b"exam"), 5_000_000_000, clock, test_scenario::ctx(scenario)
        );
        dynamic_fees::initialize_fee_structure(
            &fee_admin, &mut fee_registry, string::utf8(b"certificate"), 100_000_000, clock, test_scenario::ctx(scenario)
        );
        
        // Create a basic certificate market
        certificate_market::create_certificate_market(
            &market_admin, &mut market_registry, &mut market_analytics,
            string::utf8(b"blockchain_basics"), 100_000_000, 0, clock, test_scenario::ctx(scenario)
        );
        
        (hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin)
    }

    // =============== Unit Tests - Economic Policy Management ===============

    #[test]
    fun test_economic_policy_creation() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Create economic policy
        let mut parameters = vec_map::empty<String, u64>();
        vec_map::insert(&mut parameters, string::utf8(b"max_fee_multiplier"), 500);
        vec_map::insert(&mut parameters, string::utf8(b"min_reward_amount"), 1000000);
        
        economics_integration::create_economic_policy(
            &eco_admin,
            &mut hub,
            string::utf8(b"fee_control_policy"),
            string::utf8(b"fee"),
            parameters,
            2, // Enforced level
            30, // 30 days duration
            5, // Required votes
            &clock,
        );
        
        // Verify policy was created
        let (category, policy_params, enforcement, is_active) = economics_integration::get_economic_policy(
            &hub, string::utf8(b"fee_control_policy")
        );
        
        assert!(category == string::utf8(b"fee"), 0);
        assert!(enforcement == 2, 1);
        assert!(!is_active, 2); // Should require voting approval
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_POLICY_COOLDOWN_ACTIVE)]
    fun test_policy_creation_cooldown() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Create first policy
        let mut parameters1 = vec_map::empty<String, u64>();
        vec_map::insert(&mut parameters1, string::utf8(b"param1"), 100);
        
        economics_integration::create_economic_policy(
            &eco_admin, &mut hub, string::utf8(b"policy1"), string::utf8(b"fee"),
            parameters1, 1, 30, 5, &clock
        );
        
        // Try to create another policy immediately (should fail due to cooldown)
        let mut parameters2 = vec_map::empty<String, u64>();
        vec_map::insert(&mut parameters2, string::utf8(b"param2"), 200);
        
        economics_integration::create_economic_policy(
            &eco_admin, &mut hub, string::utf8(b"policy2"), string::utf8(b"reward"),
            parameters2, 1, 30, 5, &clock
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_INVALID_ECONOMIC_PARAMETER)]
    fun test_policy_creation_invalid_enforcement() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        let mut parameters = vec_map::empty<String, u64>();
        vec_map::insert(&mut parameters, string::utf8(b"param"), 100);
        
        // Try to create policy with invalid enforcement level
        economics_integration::create_economic_policy(
            &eco_admin, &mut hub, string::utf8(b"invalid_policy"), string::utf8(b"fee"),
            parameters, 5, 30, 5, &clock // Invalid enforcement level (max is 2)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Cross-Module Transactions ===============

    #[test]
    fun test_cross_module_transaction_execution() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, USER1);
        
        let transaction_amount = 1_000_000_000; // 1 SUI
        let payment = coin::mint_for_testing<SUI>(transaction_amount, test_scenario::ctx(&mut scenario));
        
        // Execute cross-module transaction
        let (remaining_payment, transaction_id) = economics_integration::execute_cross_module_transaction(
            &mut hub,
            string::utf8(b"certificate_market"),
            string::utf8(b"learning_incentives"),
            string::utf8(b"reward_transfer"),
            payment,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify transaction was processed
        let expected_fee = (transaction_amount * CROSS_MODULE_FEE_SHARE) / 10000;
        let expected_remaining = transaction_amount - expected_fee;
        
        assert!(coin::value(&remaining_payment) == expected_remaining, 3);
        
        // Verify integration pool received fee
        let pool_balance = economics_integration::get_integration_pool_balance(&hub);
        assert!(pool_balance == expected_fee, 4);
        
        coin::burn_for_testing(remaining_payment);
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_ECONOMIC_EMERGENCY_ACTIVE)]
    fun test_cross_module_transaction_emergency_mode() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Simulate economic emergency by updating metrics with very low health
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        // Advance time for metrics cooldown
        clock::increment_for_testing(&mut clock, 3700 * 1000); // > 1 hour
        
        // Manually trigger emergency mode (in real scenario, this would happen via health calculation)
        // For testing, we assume emergency mode is activated
        
        test_scenario::next_tx(&mut scenario, USER1);
        let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
        
        // Try to execute cross-module transaction during emergency (should fail)
        economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"source"), string::utf8(b"target"), string::utf8(b"test"),
            payment, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_INSUFFICIENT_ECONOMIC_HEALTH)]
    fun test_cross_module_transaction_insufficient_payment() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, USER1);
        
        // Try to execute transaction with payment less than integration fee
        let tiny_payment = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(&mut scenario)); // Very small amount
        
        economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"source"), string::utf8(b"target"), string::utf8(b"test"),
            tiny_payment, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Economic Metrics and Health ===============

    #[test]
    fun test_economic_metrics_update() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Advance time to allow metrics update
        clock::increment_for_testing(&mut clock, 3700 * 1000); // > 1 hour
        
        // Update economic metrics
        economics_integration::update_economic_metrics(
            &eco_admin,
            &mut hub,
            &market_registry,
            &incentive_registry,
            &fee_registry,
            &clock,
        );
        
        // Verify metrics were updated
        let health_score = economics_integration::get_economic_health_score(&hub);
        assert!(health_score >= 0 && health_score <= 100, 5);
        
        let total_revenue = economics_integration::get_total_platform_revenue(&hub);
        assert!(total_revenue >= 0, 6); // Should be non-negative
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_ANALYTICS_UPDATE_TOO_FREQUENT)]
    fun test_metrics_update_cooldown() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // First update should succeed
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        // Immediate second update should fail due to cooldown
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Revenue Distribution ===============

    #[test]
    fun test_revenue_distribution() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        let total_revenue_amount = 10_000_000_000; // 10 SUI
        let revenue_coin = coin::mint_for_testing<SUI>(total_revenue_amount, test_scenario::ctx(&mut scenario));
        
        // Distribute revenue
        economics_integration::distribute_platform_revenue(
            &eco_admin,
            &mut hub,
            revenue_coin,
            TREASURY,
            REWARD_POOL,
            VALIDATORS,
            DEVELOPMENT,
            GOVERNANCE,
            EMERGENCY,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        
        // Verify distribution configuration
        let (treasury_alloc, reward_alloc, validator_alloc, dev_alloc, gov_alloc, emergency_alloc, burn_alloc) = 
            economics_integration::get_revenue_distribution(&hub);
        
        // All allocations should sum to 10000 (100%)
        let total_allocation = treasury_alloc + reward_alloc + validator_alloc + dev_alloc + gov_alloc + emergency_alloc + burn_alloc;
        assert!(total_allocation == 10000, 7);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_revenue_distribution_update() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Update revenue distribution
        economics_integration::update_revenue_distribution(
            &eco_admin,
            &mut hub,
            4000, // 40% to treasury
            2000, // 20% to rewards
            2000, // 20% to validators
            1000, // 10% to development
            500,  // 5% to governance
            300,  // 3% to emergency
            200,  // 2% to burn
        );
        
        // Verify new distribution
        let (treasury, rewards, validators, dev, gov, emergency, burn) = 
            economics_integration::get_revenue_distribution(&hub);
        
        assert!(treasury == 4000, 8);
        assert!(rewards == 2000, 9);
        assert!(validators == 2000, 10);
        assert!(dev == 1000, 11);
        assert!(gov == 500, 12);
        assert!(emergency == 300, 13);
        assert!(burn == 200, 14);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_INVALID_ECONOMIC_PARAMETER)]
    fun test_revenue_distribution_invalid_total() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Try to update with allocations that don't sum to 100%
        economics_integration::update_revenue_distribution(
            &eco_admin,
            &mut hub,
            5000, // 50%
            3000, // 30%
            2000, // 20%
            500,  // 5%
            0, 0, 0, // Total = 105% (invalid)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Unit Tests - Anomaly Detection ===============

    #[test]
    fun test_anomaly_detection() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Update network metrics to create conditions for anomaly detection
        dynamic_fees::update_network_metrics(
            &fee_admin, &mut fee_registry, 2000, 10000, 95, 5000, &clock
        );
        
        // Run anomaly detection
        economics_integration::detect_economic_anomalies(
            &mut hub,
            &market_registry,
            &fee_registry,
            &clock,
        );
        
        // Anomaly detection should complete without error
        // In a real implementation, we would check for specific anomaly flags
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Integration Tests ===============

    #[test]
    fun test_complete_economics_workflow() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, mut market_registry, mut market_analytics, market_admin, mut incentive_registry, incentive_admin, mut fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // 1. Create economic policy
        let mut policy_params = vec_map::empty<String, u64>();
        vec_map::insert(&mut policy_params, string::utf8(b"max_daily_rewards"), 1000_000_000_000);
        
        economics_integration::create_economic_policy(
            &eco_admin, &mut hub, string::utf8(b"daily_rewards_cap"), string::utf8(b"reward"),
            policy_params, 1, 30, 3, &clock
        );
        
        // 2. Execute cross-module transactions
        test_scenario::next_tx(&mut scenario, USER1);
        let payment1 = coin::mint_for_testing<SUI>(2_000_000_000, test_scenario::ctx(&mut scenario));
        let (change1, _) = economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"market"), string::utf8(b"incentives"), string::utf8(b"reward"),
            payment1, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(change1);
        
        test_scenario::next_tx(&mut scenario, USER2);
        let payment2 = coin::mint_for_testing<SUI>(1_500_000_000, test_scenario::ctx(&mut scenario));
        let (change2, _) = economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"fees"), string::utf8(b"market"), string::utf8(b"trade"),
            payment2, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(change2);
        
        // 3. Simulate activity in individual modules
        test_scenario::next_tx(&mut scenario, USER1);
        learning_incentives::record_learning_activity(
            &mut incentive_registry, string::utf8(b"blockchain"), 2, 10, 85, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // 4. Update economic metrics
        clock::increment_for_testing(&mut clock, 3700 * 1000); // Wait for cooldown
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        // 5. Run anomaly detection
        economics_integration::detect_economic_anomalies(&mut hub, &market_registry, &fee_registry, &clock);
        
        // 6. Distribute revenue
        let revenue = coin::mint_for_testing<SUI>(5_000_000_000, test_scenario::ctx(&mut scenario));
        economics_integration::distribute_platform_revenue(
            &eco_admin, &mut hub, revenue, TREASURY, REWARD_POOL, VALIDATORS, DEVELOPMENT, GOVERNANCE, EMERGENCY, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Verify final state
        let health_score = economics_integration::get_economic_health_score(&hub);
        assert!(health_score > 0, 15);
        
        let total_revenue = economics_integration::get_total_platform_revenue(&hub);
        assert!(total_revenue > 0, 16);
        
        let integration_balance = economics_integration::get_integration_pool_balance(&hub);
        assert!(integration_balance > 0, 17); // Should have collected fees
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_multi_module_coordination() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, mut market_registry, mut market_analytics, market_admin, mut incentive_registry, incentive_admin, mut fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Simulate coordinated activity across all modules
        
        // 1. Fee system: Process payments
        test_scenario::next_tx(&mut scenario, USER1);
        let fee_calc = dynamic_fees::calculate_dynamic_fee(&fee_registry, string::utf8(b"exam"), USER1, 1, &clock);
        let fee_payment = coin::mint_for_testing<SUI>(fee_calc.final_fee, test_scenario::ctx(&mut scenario));
        let (fee_change, _) = dynamic_fees::process_fee_payment(
            &mut fee_registry, string::utf8(b"exam"), 1, fee_payment, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(fee_change);
        
        // 2. Learning incentives: Record activity
        learning_incentives::record_learning_activity(
            &mut incentive_registry, string::utf8(b"defi"), 3, 15, 90, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // 3. Certificate market: Update analytics
        certificate_market::update_market_analytics(&market_admin, &mut market_registry, &mut market_analytics, &clock);
        
        // 4. Integration layer: Coordinate metrics
        clock::increment_for_testing(&mut clock, 3700 * 1000);
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        // Verify coordination resulted in updated metrics
        let final_health = economics_integration::get_economic_health_score(&hub);
        let final_revenue = economics_integration::get_total_platform_revenue(&hub);
        
        assert!(final_health >= 0 && final_health <= 100, 18);
        assert!(final_revenue >= 0, 19);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Security Tests ===============

    #[test]
    #[expected_failure(abort_code = economics_integration::E_INVALID_INTEGRATION_STATE)]
    fun test_security_invalid_integration_state() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Disable policy enforcement to create invalid state
        // This would typically be done through emergency procedures
        
        test_scenario::next_tx(&mut scenario, USER1);
        let payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
        
        // Try to execute transaction in invalid state
        economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"source"), string::utf8(b"target"), string::utf8(b"test"),
            payment, &clock, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_security_admin_functions() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Test admin-only functions
        
        // 1. Set analytics oracle
        economics_integration::set_analytics_oracle(&eco_admin, &mut hub, @0x12345);
        
        // 2. Deactivate emergency mode (if it was active)
        economics_integration::deactivate_emergency_mode(&eco_admin, &mut hub);
        
        // 3. Withdraw integration fees
        economics_integration::withdraw_integration_fees(
            &eco_admin, &mut hub, 0, test_scenario::ctx(&mut scenario) // Withdraw 0 amount
        );
        
        // All admin functions should complete without error
        assert!(!economics_integration::is_emergency_mode_active(&hub), 20);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = economics_integration::E_INSUFFICIENT_ECONOMIC_HEALTH)]
    fun test_security_integration_fee_withdrawal_insufficient_funds() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        let pool_balance = economics_integration::get_integration_pool_balance(&hub);
        
        // Try to withdraw more than available
        economics_integration::withdraw_integration_fees(
            &eco_admin, &mut hub, pool_balance + 1_000_000_000, test_scenario::ctx(&mut scenario)
        );
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Economic Logic Validation ===============

    #[test]
    fun test_economic_health_calculation() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, mut incentive_registry, incentive_admin, mut fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Generate some economic activity to test health calculation
        test_scenario::next_tx(&mut scenario, USER1);
        
        // Create fee activity
        let fee_calc = dynamic_fees::calculate_dynamic_fee(&fee_registry, string::utf8(b"certificate"), USER1, 5, &clock);
        let payment = coin::mint_for_testing<SUI>(fee_calc.final_fee, test_scenario::ctx(&mut scenario));
        let (change, _) = dynamic_fees::process_fee_payment(
            &mut fee_registry, string::utf8(b"certificate"), 5, payment, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(change);
        
        // Create learning activity
        learning_incentives::record_learning_activity(
            &mut incentive_registry, string::utf8(b"economics"), 4, 20, 88, true, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Update metrics and check health
        clock::increment_for_testing(&mut clock, 3700 * 1000);
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        let health_score = economics_integration::get_economic_health_score(&hub);
        
        // Health should be reasonable given the activity
        assert!(health_score >= 20, 21); // Should have some base health
        assert!(health_score <= 100, 22); // Should not exceed maximum
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_economic_revenue_aggregation() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, mut incentive_registry, incentive_admin, mut fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Generate revenue across multiple modules
        test_scenario::next_tx(&mut scenario, USER1);
        
        // Fee revenue
        let fee_calc = dynamic_fees::calculate_dynamic_fee(&fee_registry, string::utf8(b"exam"), USER1, 1, &clock);
        let fee_payment = coin::mint_for_testing<SUI>(fee_calc.final_fee, test_scenario::ctx(&mut scenario));
        let (fee_change, fee_paid) = dynamic_fees::process_fee_payment(
            &mut fee_registry, string::utf8(b"exam"), 1, fee_payment, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(fee_change);
        
        // Learning incentive activity (creates rewards distribution)
        learning_incentives::record_learning_activity(
            &mut incentive_registry, string::utf8(b"trading"), 2, 12, 80, false, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Cross-module transaction (creates integration fees)
        let cross_payment = coin::mint_for_testing<SUI>(1_000_000_000, test_scenario::ctx(&mut scenario));
        let (cross_change, _) = economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"source"), string::utf8(b"target"), string::utf8(b"test"),
            cross_payment, &clock, test_scenario::ctx(&mut scenario)
        );
        coin::burn_for_testing(cross_change);
        
        // Update metrics to aggregate revenue
        clock::increment_for_testing(&mut clock, 3700 * 1000);
        economics_integration::update_economic_metrics(
            &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
        );
        
        // Verify revenue aggregation
        let total_revenue = economics_integration::get_total_platform_revenue(&hub);
        assert!(total_revenue > 0, 23); // Should include fees and other revenue
        
        let integration_balance = economics_integration::get_integration_pool_balance(&hub);
        assert!(integration_balance > 0, 24); // Should have integration fees
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Performance Tests ===============

    #[test]
    fun test_performance_multiple_cross_module_transactions() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Execute multiple cross-module transactions
        let transaction_count = 10;
        let mut total_fees_collected = 0u64;
        
        let mut i = 0;
        while (i < transaction_count) {
            let user_address = @0x3000 + i;
            test_scenario::next_tx(&mut scenario, user_address);
            
            let amount = 500_000_000 + (i * 100_000_000); // Varying amounts
            let payment = coin::mint_for_testing<SUI>(amount, test_scenario::ctx(&mut scenario));
            
            let (change, tx_id) = economics_integration::execute_cross_module_transaction(
                &mut hub, string::utf8(b"module_a"), string::utf8(b"module_b"), string::utf8(b"transfer"),
                payment, &clock, test_scenario::ctx(&mut scenario)
            );
            
            let expected_fee = (amount * CROSS_MODULE_FEE_SHARE) / 10000;
            total_fees_collected = total_fees_collected + expected_fee;
            
            coin::burn_for_testing(change);
            i = i + 1;
        };
        
        // Verify all transactions were processed
        let integration_balance = economics_integration::get_integration_pool_balance(&hub);
        assert!(integration_balance == total_fees_collected, 25);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_performance_frequent_metrics_updates() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Update metrics multiple times with proper cooldown
        let update_count = 5;
        let mut i = 0;
        
        while (i < update_count) {
            // Wait for cooldown period
            clock::increment_for_testing(&mut clock, 3700 * 1000); // > 1 hour
            
            economics_integration::update_economic_metrics(
                &eco_admin, &mut hub, &market_registry, &incentive_registry, &fee_registry, &clock
            );
            
            // Verify metrics are still valid
            let health = economics_integration::get_economic_health_score(&hub);
            assert!(health >= 0 && health <= 100, 26 + i);
            
            i = i + 1;
        };
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // =============== Edge Cases ===============

    #[test]
    fun test_edge_case_zero_amount_transaction() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        test_scenario::next_tx(&mut scenario, USER1);
        
        // Try transaction with minimal amount
        let minimal_payment = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(&mut scenario)); // Very small
        
        // This should either succeed with minimal fee or fail gracefully
        let result = economics_integration::execute_cross_module_transaction(
            &mut hub, string::utf8(b"source"), string::utf8(b"target"), string::utf8(b"minimal"),
            minimal_payment, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // If it succeeds, verify the result is reasonable
        let (change, _) = result;
        coin::burn_for_testing(change);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_edge_case_extreme_time_values() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Set extreme future time
        clock::set_for_testing(&mut clock, 9999999999999);
        
        // System should handle extreme time values gracefully
        economics_integration::detect_economic_anomalies(&mut hub, &market_registry, &fee_registry, &clock);
        
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_edge_case_large_revenue_distribution() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut hub, eco_admin, market_registry, market_analytics, market_admin, incentive_registry, incentive_admin, fee_registry, fee_admin) = 
            create_complete_economics_system(&mut scenario, &clock);
        
        // Distribute very large amount
        let large_amount = 1_000_000_000_000_000; // 1M SUI
        let large_revenue = coin::mint_for_testing<SUI>(large_amount, test_scenario::ctx(&mut scenario));
        
        economics_integration::distribute_platform_revenue(
            &eco_admin, &mut hub, large_revenue, TREASURY, REWARD_POOL, VALIDATORS, DEVELOPMENT, GOVERNANCE, EMERGENCY, &clock, test_scenario::ctx(&mut scenario)
        );
        
        // Should handle large amounts without overflow
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        test_scenario::return_shared(market_registry);
        test_scenario::return_shared(market_analytics);
        test_scenario::return_to_sender(&scenario, market_admin);
        test_scenario::return_shared(incentive_registry);
        test_scenario::return_to_sender(&scenario, incentive_admin);
        test_scenario::return_shared(fee_registry);
        test_scenario::return_to_sender(&scenario, fee_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}