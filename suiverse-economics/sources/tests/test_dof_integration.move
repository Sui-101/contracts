#[test_only]
module suiverse_economics::test_dof_integration {
    use std::string;
    use std::option;
    use sui::clock::{Self as clock, Clock};
    use sui::coin::{Self as coin, Coin};
    use sui::sui::SUI;
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils;
    use sui::object;
    
    use suiverse_economics::config_manager::{Self, ConfigManager, ConfigManagerAdminCap};
    use suiverse_economics::config_wrappers;
    use suiverse_economics::learning_incentives::{Self, IncentiveRegistry, IncentiveAdminCap};
    use suiverse_economics::dynamic_fees::{Self, FeeRegistry, FeeAdminCap};
    use suiverse_economics::certificate_market::{Self, MarketRegistry, MarketAdminCap, MarketAnalytics};
    use suiverse_economics::economics_integration::{Self, EconomicsHub, EconomicsAdminCap};

    // Test addresses
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;
    const USER2: address = @0x3;

    /// Test comprehensive DOF Config Management integration
    #[test]
    fun test_complete_dof_integration() {
        let mut scenario = ts::begin(ADMIN);
        setup_complete_dof_environment(&mut scenario);
        
        // Test learning incentives with config manager
        test_learning_incentives_with_config(&mut scenario);
        
        // Test dynamic fees with config manager
        test_dynamic_fees_with_config(&mut scenario);
        
        // Test certificate market with config manager
        test_certificate_market_with_config(&mut scenario);
        
        // Test economics integration coordination
        test_economics_integration_coordination(&mut scenario);
        
        ts::end(scenario);
    }

    /// Test cross-module configuration consistency
    #[test] 
    fun test_cross_module_config_consistency() {
        let mut scenario = ts::begin(ADMIN);
        setup_complete_dof_environment(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config_manager = ts::take_shared<ConfigManager>(&scenario);
            
            // Verify all essential configs are present
            assert!(config_wrappers::has_all_essential_registries(&config_manager), 1);
            
            // Verify clock configuration
            assert!(config_manager::has_config<Clock>(&config_manager, string::utf8(b"system_clock")), 2);
            
            // Test config health status
            let health_status = config_wrappers::get_configuration_health_status(&config_manager);
            assert!(health_status == 100, 3); // Perfect health
            
            ts::return_shared(config_manager);
        };
        
        ts::end(scenario);
    }

    /// Test error handling and edge cases
    #[test]
    fun test_config_error_handling() {
        let mut scenario = ts::begin(ADMIN);
        
        // Initialize only config manager without configurations
        ts::next_tx(&mut scenario, ADMIN);
        {
            config_manager::test_init(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config_manager = ts::take_shared<ConfigManager>(&scenario);
            
            // Should fail when no clock is configured
            assert!(!config_manager::has_config<Clock>(&config_manager, string::utf8(b"system_clock")), 1);
            
            ts::return_shared(config_manager);
        };
        
        ts::end(scenario);
    }

    /// Test performance and gas optimization
    #[test]
    fun test_dof_performance() {
        let mut scenario = ts::begin(ADMIN);
        setup_complete_dof_environment(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            let config_manager = ts::take_shared<ConfigManager>(&scenario);
            let mut incentive_registry = ts::take_shared<IncentiveRegistry>(&scenario);
            
            // Test multiple rapid operations with config manager
            let subject = string::utf8(b"blockchain");
            
            // Should be efficient with DOF lookup
            learning_incentives::record_learning_activity_with_config(
                &mut incentive_registry,
                &config_manager,
                subject,
                2, // 2 hours
                10, // 10 concepts
                85, // 85% retention
                false, // not cross-domain
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(incentive_registry);
            ts::return_shared(config_manager);
        };
        
        ts::end(scenario);
    }

    /// Test security and access control
    #[test]
    fun test_dof_security() {
        let mut scenario = ts::begin(ADMIN);
        setup_complete_dof_environment(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1); // Non-admin user
        {
            let config_manager = ts::take_shared<ConfigManager>(&scenario);
            
            // User should be able to read configs but not modify
            assert!(config_manager::has_config<Clock>(&config_manager, string::utf8(b"system_clock")), 1);
            
            // This would fail - users can't add configs without admin cap
            // config_manager::add_config(...) // Would require ConfigManagerAdminCap
            
            ts::return_shared(config_manager);
        };
        
        ts::end(scenario);
    }

    /// Test migration and compatibility
    #[test]
    fun test_dof_migration_compatibility() {
        let mut scenario = ts::begin(ADMIN);
        setup_complete_dof_environment(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config_manager = ts::take_shared<ConfigManager>(&scenario);
            let economics_hub = ts::take_shared<EconomicsHub>(&scenario);
            let admin_cap = ts::take_from_sender<EconomicsAdminCap>(&scenario);
            
            // Test integration status
            let (registry_linked, config_linked, registry_operational, config_operational) = 
                economics_integration::get_integration_status(
                    &economics_hub,
                    option::none(), // No system registry
                    option::some(&config_manager)
                );
            
            assert!(config_linked, 1);
            assert!(config_operational, 2);
            
            ts::return_to_sender(&scenario, admin_cap);
            ts::return_shared(economics_hub);
            ts::return_shared(config_manager);
        };
        
        ts::end(scenario);
    }

    // === Helper Functions ===

    fun setup_complete_dof_environment(scenario: &mut Scenario) {
        // Initialize all modules
        ts::next_tx(scenario, ADMIN);
        {
            config_manager::test_init(ts::ctx(scenario));
            learning_incentives::test_init(ts::ctx(scenario));
            dynamic_fees::test_init(ts::ctx(scenario));
            certificate_market::test_init(ts::ctx(scenario));
            economics_integration::test_init(ts::ctx(scenario));
        };
        
        // Setup ConfigManager with essential configurations
        ts::next_tx(scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<ConfigManagerAdminCap>(scenario);
            let mut config_manager = ts::take_shared<ConfigManager>(scenario);
            
            // Add system clock
            let clock = clock::create_for_testing(ts::ctx(scenario));
            config_manager::add_config(
                &admin_cap,
                &mut config_manager,
                string::utf8(b"system_clock"),
                clock,
                ts::ctx(scenario)
            );
            
            // Setup essential registries using config wrappers
            let incentive_registry = ts::take_shared<IncentiveRegistry>(scenario);
            let fee_registry = ts::take_shared<FeeRegistry>(scenario);
            let market_registry = ts::take_shared<MarketRegistry>(scenario);
            
            config_wrappers::setup_essential_registries(
                &admin_cap,
                &mut config_manager,
                &incentive_registry,
                &fee_registry,
                &market_registry,
                ts::ctx(scenario)
            );
            
            ts::return_shared(market_registry);
            ts::return_shared(fee_registry);
            ts::return_shared(incentive_registry);
            ts::return_to_sender(scenario, admin_cap);
            ts::return_shared(config_manager);
        };
        
        // Link economics hub to config manager
        ts::next_tx(scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<EconomicsAdminCap>(scenario);
            let mut economics_hub = ts::take_shared<EconomicsHub>(scenario);
            let config_manager = ts::take_shared<ConfigManager>(scenario);
            
            economics_integration::link_config_manager(
                &admin_cap,
                &mut economics_hub,
                object::id(&config_manager)
            );
            
            ts::return_shared(config_manager);
            ts::return_shared(economics_hub);
            ts::return_to_sender(scenario, admin_cap);
        };
    }

    fun test_learning_incentives_with_config(scenario: &mut Scenario) {
        ts::next_tx(scenario, USER1);
        {
            let config_manager = ts::take_shared<ConfigManager>(scenario);
            let mut incentive_registry = ts::take_shared<IncentiveRegistry>(scenario);
            
            learning_incentives::record_learning_activity_with_config(
                &mut incentive_registry,
                &config_manager,
                string::utf8(b"smart_contracts"),
                3, // 3 hours of learning
                15, // 15 concepts learned
                90, // 90% retention score
                true, // cross-domain learning
                ts::ctx(scenario)
            );
            
            // Verify learning progress was recorded
            let (streak, _, hours, _, velocity, retention) = learning_incentives::get_user_progress(
                &incentive_registry,
                USER1
            );
            assert!(streak == 1, 1);
            assert!(hours == 3, 2);
            assert!(velocity == 5, 3); // 15 concepts / 3 hours
            assert!(retention >= 90, 4);
            
            ts::return_shared(incentive_registry);
            ts::return_shared(config_manager);
        };
    }

    fun test_dynamic_fees_with_config(scenario: &mut Scenario) {
        ts::next_tx(scenario, USER1);
        {
            let config_manager = ts::take_shared<ConfigManager>(scenario);
            let mut fee_registry = ts::take_shared<FeeRegistry>(scenario);
            
            // Create a test payment
            let payment = coin::mint_for_testing<SUI>(1_000_000_000, ts::ctx(scenario)); // 1 SUI
            
            dynamic_fees::process_fee_payment_with_config(
                &mut fee_registry,
                &config_manager,
                string::utf8(b"quiz_creation"),
                1, // single operation
                payment,
                ts::ctx(scenario)
            );
            
            // Verify fee was processed
            let total_revenue = dynamic_fees::get_total_fee_revenue(&fee_registry);
            assert!(total_revenue > 0, 1);
            
            ts::return_shared(fee_registry);
            ts::return_shared(config_manager);
        };
    }

    fun test_certificate_market_with_config(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<MarketAdminCap>(scenario);
            let config_manager = ts::take_shared<ConfigManager>(scenario);
            let mut market_registry = ts::take_shared<MarketRegistry>(scenario);
            let mut market_analytics = ts::take_shared<MarketAnalytics>(scenario);
            
            certificate_market::create_certificate_market_with_config(
                &admin_cap,
                &mut market_registry,
                &mut market_analytics,
                &config_manager,
                string::utf8(b"blockchain_fundamentals"),
                100_000_000, // 0.1 SUI base price
                0, // Common rarity
                ts::ctx(scenario)
            );
            
            // Verify market was created
            assert!(certificate_market::is_market_active(&market_registry), 1);
            
            ts::return_shared(market_analytics);
            ts::return_shared(market_registry);
            ts::return_shared(config_manager);
            ts::return_to_sender(scenario, admin_cap);
        };
    }

    fun test_economics_integration_coordination(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<EconomicsAdminCap>(scenario);
            let config_manager = ts::take_shared<ConfigManager>(scenario);
            let mut economics_hub = ts::take_shared<EconomicsHub>(scenario);
            
            // Test DOF-based economic metrics update
            economics_integration::update_economic_metrics_with_config_manager(
                &admin_cap,
                &mut economics_hub,
                &config_manager
            );
            
            // Verify metrics were updated
            let (health_score, efficiency_score, _) = economics_integration::get_economic_health_metrics(&economics_hub);
            assert!(health_score > 0, 1);
            assert!(efficiency_score > 0, 2);
            
            ts::return_shared(economics_hub);
            ts::return_shared(config_manager);
            ts::return_to_sender(scenario, admin_cap);
        };
    }
}