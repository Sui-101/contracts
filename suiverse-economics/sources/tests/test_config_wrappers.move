/// Tests for Configuration Wrappers Module
/// 
/// Tests cover:
/// - Type-safe wrapper functions for common config types
/// - Batch configuration setup
/// - Configuration health status monitoring
/// - Integration with ConfigManager
/// - Error handling for missing configurations
/// - Configuration validation and completeness checks
#[test_only]
module suiverse_economics::test_config_wrappers {
    use std::string::{Self, String};
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::test_scenario::{Self, Scenario, next_tx, ctx};
    use sui::transfer;
    use sui::tx_context::TxContext;

    // Import modules under test
    use suiverse_economics::config_manager::{Self, ConfigManager, ConfigManagerAdminCap};
    use suiverse_economics::config_wrappers;

    // Mock registries for testing (simplified versions)
    public struct MockCertificateMarketRegistry has key, store {
        id: UID,
        active_markets: u64,
        total_volume: u64,
    }

    public struct MockIncentiveRegistry has key, store {
        id: UID,
        total_rewards: u64,
        active_incentives: u64,
    }

    public struct MockFeeRegistry has key, store {
        id: UID,
        base_fee: u64,
        total_revenue: u64,
    }

    public struct MockStakingRegistry has key, store {
        id: UID,
        total_staked: u64,
        validator_count: u64,
    }

    // === Test Constants ===
    const ADMIN: address = @0x1;
    const USER: address = @0x2;

    // === Setup Functions ===

    fun setup_test_scenario(): Scenario {
        let mut scenario = test_scenario::begin(ADMIN);
        
        // Initialize config manager
        next_tx(&mut scenario, ADMIN);
        {
            config_manager::test_init(ctx(&mut scenario));
        };

        scenario
    }

    fun create_mock_certificate_market_registry(ctx: &mut TxContext): MockCertificateMarketRegistry {
        MockCertificateMarketRegistry {
            id: object::new(ctx),
            active_markets: 5,
            total_volume: 1000000,
        }
    }

    fun create_mock_incentive_registry(ctx: &mut TxContext): MockIncentiveRegistry {
        MockIncentiveRegistry {
            id: object::new(ctx),
            total_rewards: 500000,
            active_incentives: 10,
        }
    }

    fun create_mock_fee_registry(ctx: &mut TxContext): MockFeeRegistry {
        MockFeeRegistry {
            id: object::new(ctx),
            base_fee: 1000,
            total_revenue: 250000,
        }
    }

    fun create_mock_staking_registry(ctx: &mut TxContext): MockStakingRegistry {
        MockStakingRegistry {
            id: object::new(ctx),
            total_staked: 10000000,
            validator_count: 25,
        }
    }

    // === Basic Wrapper Function Tests ===

    #[test]
    fun test_clock_wrapper_functions() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Test that clock is not available initially
            assert!(!config_wrappers::has_clock(&manager), 0);

            // Setup system clock using wrapper
            config_wrappers::setup_system_clock(&admin_cap, &mut manager, clock, ctx(&mut scenario));

            // Test that clock is now available
            assert!(config_wrappers::has_clock(&manager), 1);

            // Test clock retrieval
            let clock_ref = config_wrappers::get_clock(&manager);
            let timestamp = clock::timestamp_ms(clock_ref);
            // Clock should have a valid timestamp (0 or positive)
            assert!(timestamp >= 0, 2);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_registry_wrapper_functions() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager with clock
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            config_wrappers::setup_system_clock(&admin_cap, &mut manager, clock, ctx(&mut scenario));

            // Create mock registries
            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            // Test individual setup functions
            config_wrappers::setup_certificate_market_registry(
                &admin_cap, &mut manager, cert_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(config_wrappers::has_certificate_market_registry(&manager), 0);

            config_wrappers::setup_incentive_registry(
                &admin_cap, &mut manager, incentive_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(config_wrappers::has_incentive_registry(&manager), 1);

            config_wrappers::setup_fee_registry(
                &admin_cap, &mut manager, fee_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(config_wrappers::has_fee_registry(&manager), 2);

            config_wrappers::setup_staking_registry(
                &admin_cap, &mut manager, staking_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(config_wrappers::has_staking_registry(&manager), 3);

            // Test that all essential registries are now available
            assert!(config_wrappers::has_all_essential_registries(&manager), 4);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_batch_essential_configs_setup() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Create mock registries
            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            // Use batch setup function
            config_wrappers::setup_essential_configs(
                &admin_cap,
                &mut manager,
                clock,
                cert_registry,
                incentive_registry,
                fee_registry,
                staking_registry,
                ctx(&mut scenario)
            );

            // Verify all essential configurations are available
            assert!(config_wrappers::has_clock(&manager), 0);
            assert!(config_wrappers::has_certificate_market_registry(&manager), 1);
            assert!(config_wrappers::has_incentive_registry(&manager), 2);
            assert!(config_wrappers::has_fee_registry(&manager), 3);
            assert!(config_wrappers::has_staking_registry(&manager), 4);
            assert!(config_wrappers::has_all_essential_registries(&manager), 5);

            // Test manager stats
            let (_, _, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(total_configs == 5, 6); // Clock + 4 registries

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_config_health_status_monitoring() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Initially, no essential configs are available
            let (all_available, missing_configs) = config_wrappers::get_config_health_status(&manager);
            assert!(!all_available, 0);
            assert!(vector::length(&missing_configs) == 5, 1); // All 5 essential configs missing

            // Add clock
            config_wrappers::setup_system_clock(&admin_cap, &mut manager, clock, ctx(&mut scenario));

            // Check health status - clock available, others missing
            let (all_available, missing_configs) = config_wrappers::get_config_health_status(&manager);
            assert!(!all_available, 2);
            assert!(vector::length(&missing_configs) == 4, 3); // 4 registries still missing

            // Add all other essential configs
            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            config_wrappers::setup_certificate_market_registry(
                &admin_cap, &mut manager, cert_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            config_wrappers::setup_incentive_registry(
                &admin_cap, &mut manager, incentive_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            config_wrappers::setup_fee_registry(
                &admin_cap, &mut manager, fee_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            config_wrappers::setup_staking_registry(
                &admin_cap, &mut manager, staking_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );

            // Now all essential configs should be available
            let (all_available, missing_configs) = config_wrappers::get_config_health_status(&manager);
            assert!(all_available, 4);
            assert!(vector::length(&missing_configs) == 0, 5);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_configuration_status_report() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager with all essential configs
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            config_wrappers::setup_essential_configs(
                &admin_cap,
                &mut manager,
                clock,
                cert_registry,
                incentive_registry,
                fee_registry,
                staking_registry,
                ctx(&mut scenario)
            );

            // Get comprehensive status report
            let (is_operational, all_essential_available, total_configs, available_configs, missing_configs) = 
                config_wrappers::get_configuration_status_report(&manager);

            // Verify status report
            assert!(is_operational, 0);
            assert!(all_essential_available, 1);
            assert!(total_configs == 5, 2);
            assert!(vector::length(&available_configs) == 5, 3);
            assert!(vector::length(&missing_configs) == 0, 4);

            // Verify configuration completeness
            assert!(config_wrappers::validate_configuration_completeness(&manager), 5);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_all_registries() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager with all essential configs
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            config_wrappers::setup_essential_configs(
                &admin_cap,
                &mut manager,
                clock,
                cert_registry,
                incentive_registry,
                fee_registry,
                staking_registry,
                ctx(&mut scenario)
            );

            // Test getting all registries at once
            let (cert_ref, incentive_ref, fee_ref, staking_ref) = config_wrappers::get_all_registries(&manager);

            // Verify registry references are valid by checking their fields
            assert!(cert_ref.active_markets == 5, 0);
            assert!(incentive_ref.total_rewards == 500000, 1);
            assert!(fee_ref.base_fee == 1000, 2);
            assert!(staking_ref.validator_count == 25, 3);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_standard_config_keys() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            // Test standard config keys function
            let standard_keys = config_wrappers::get_standard_config_keys();
            assert!(vector::length(&standard_keys) == 5, 0);

            // Test key validation
            assert!(config_wrappers::is_standard_config_key(std::string::utf8(b"SYSTEM_CLOCK")), 1);
            assert!(config_wrappers::is_standard_config_key(std::string::utf8(b"CERTIFICATE_MARKET_REGISTRY")), 2);
            assert!(config_wrappers::is_standard_config_key(std::string::utf8(b"INCENTIVE_REGISTRY")), 3);
            assert!(config_wrappers::is_standard_config_key(std::string::utf8(b"FEE_REGISTRY")), 4);
            assert!(config_wrappers::is_standard_config_key(std::string::utf8(b"STAKING_REGISTRY")), 5);

            // Test non-standard key
            assert!(!config_wrappers::is_standard_config_key(std::string::utf8(b"CUSTOM_CONFIG")), 6);
        };

        test_scenario::end(scenario);
    }

    // === Error Handling Tests ===

    #[test]
    #[expected_failure(abort_code = config_wrappers::E_REQUIRED_CONFIG_MISSING)]
    fun test_access_missing_clock() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager but don't add clock
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // This should fail - trying to access non-existent clock
            let _clock_ref = config_wrappers::get_clock(&manager);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config_wrappers::E_REQUIRED_CONFIG_MISSING)]
    fun test_access_missing_registry() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager with clock only
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            config_wrappers::setup_system_clock(&admin_cap, &mut manager, clock, ctx(&mut scenario));

            // This should fail - trying to access non-existent registry
            let _registry_ref = config_wrappers::get_certificate_market_registry(&manager);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Integration Tests ===

    #[test]
    fun test_mutable_registry_access() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager with all essential configs
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            config_wrappers::setup_essential_configs(
                &admin_cap,
                &mut manager,
                clock,
                cert_registry,
                incentive_registry,
                fee_registry,
                staking_registry,
                ctx(&mut scenario)
            );

            // Test mutable access to registries
            let cert_registry_mut = config_wrappers::get_certificate_market_registry_mut(
                &mut manager, 
                config_wrappers::get_clock(&manager), 
                ctx(&mut scenario)
            );
            
            // Modify the registry
            cert_registry_mut.active_markets = 10;

            // Verify the change persisted
            let cert_registry_ref = config_wrappers::get_certificate_market_registry(&manager);
            assert!(cert_registry_ref.active_markets == 10, 0);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_configuration_completeness_validation() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Initialize manager
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Initially not complete
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 0);

            // Add essential configs gradually and test completeness
            config_wrappers::setup_system_clock(&admin_cap, &mut manager, clock, ctx(&mut scenario));
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 1);

            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            config_wrappers::setup_certificate_market_registry(
                &admin_cap, &mut manager, cert_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 2);

            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            config_wrappers::setup_incentive_registry(
                &admin_cap, &mut manager, incentive_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 3);

            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            config_wrappers::setup_fee_registry(
                &admin_cap, &mut manager, fee_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 4);

            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));
            config_wrappers::setup_staking_registry(
                &admin_cap, &mut manager, staking_registry, config_wrappers::get_clock(&manager), ctx(&mut scenario)
            );

            // Now should be complete
            assert!(config_wrappers::validate_configuration_completeness(&manager), 5);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_emergency_pause_impact_on_wrappers() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);

            // Setup complete configuration
            let clock = clock::create_for_testing(ctx(&mut scenario));
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            let cert_registry = create_mock_certificate_market_registry(ctx(&mut scenario));
            let incentive_registry = create_mock_incentive_registry(ctx(&mut scenario));
            let fee_registry = create_mock_fee_registry(ctx(&mut scenario));
            let staking_registry = create_mock_staking_registry(ctx(&mut scenario));

            config_wrappers::setup_essential_configs(
                &admin_cap,
                &mut manager,
                clock,
                cert_registry,
                incentive_registry,
                fee_registry,
                staking_registry,
                ctx(&mut scenario)
            );

            // Verify everything works normally
            assert!(config_wrappers::validate_configuration_completeness(&manager), 0);

            // Trigger emergency pause
            config_manager::emergency_pause(
                &admin_cap,
                &mut manager,
                std::string::utf8(b"Testing emergency pause impact"),
                config_wrappers::get_clock(&manager),
                ctx(&mut scenario)
            );

            // Configuration completeness should fail when paused
            assert!(!config_wrappers::validate_configuration_completeness(&manager), 1);

            // Resume operations
            config_manager::resume_operations(&admin_cap, &mut manager, config_wrappers::get_clock(&manager), ctx(&mut scenario));

            // Should work again after resume
            assert!(config_wrappers::validate_configuration_completeness(&manager), 2);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }
}