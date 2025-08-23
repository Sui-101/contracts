/// Comprehensive tests for the Dynamic Object Fields-based Configuration Manager
/// 
/// Tests cover:
/// - Basic configuration operations (add, update, remove)
/// - Type-safe access patterns
/// - Batch operations
/// - Configuration locking mechanisms
/// - Emergency pause functionality
/// - Integration with wrapper functions
/// - Security and access control
/// - Error handling and edge cases
#[test_only]
module suiverse_economics::test_config_manager {
    use std::string::{Self, String};
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID};
    use sui::test_scenario::{Self, Scenario, next_tx, ctx};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    // Import modules under test
    use suiverse_economics::config_manager::{Self, ConfigManager, ConfigManagerAdminCap};
    use suiverse_economics::config_wrappers;

    // === Test Constants ===
    const ADMIN: address = @0x1;
    const USER: address = @0x2;
    const UNAUTHORIZED: address = @0x3;

    // === Test Structs ===

    /// Mock configuration object for testing
    public struct MockConfig has key, store {
        id: UID,
        value: u64,
        name: String,
    }

    /// Another mock configuration object to test type safety
    public struct AnotherMockConfig has key, store {
        id: UID,
        data: vector<u8>,
        enabled: bool,
    }

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

    fun create_test_clock(ctx: &mut TxContext): Clock {
        clock::create_for_testing(ctx)
    }

    fun create_mock_config(value: u64, name: String, ctx: &mut TxContext): MockConfig {
        MockConfig {
            id: object::new(ctx),
            value,
            name,
        }
    }

    fun create_another_mock_config(data: vector<u8>, enabled: bool, ctx: &mut TxContext): AnotherMockConfig {
        AnotherMockConfig {
            id: object::new(ctx),
            data,
            enabled,
        }
    }

    // === Basic Configuration Operations Tests ===

    #[test]
    fun test_config_manager_initialization() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initially not initialized
            let (is_initialized, is_paused, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(!is_initialized, 0);
            assert!(!is_paused, 1);
            assert!(total_configs == 0, 2);

            // Initialize the manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Check initialization status
            let (is_initialized, is_paused, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(is_initialized, 3);
            assert!(!is_paused, 4);
            assert!(total_configs == 0, 5);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_and_retrieve_config() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Create test config
            let config = create_mock_config(42, string::utf8(b"test_config"), ctx(&mut scenario));
            let config_key = string::utf8(b"TEST_CONFIG");

            // Add configuration
            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config,
                string::utf8(b"Test configuration object"),
                &clock,
                ctx(&mut scenario)
            );

            // Check if config exists
            assert!(config_manager::has_config<MockConfig>(&manager, config_key), 0);

            // Retrieve config and check values
            let config_ref = config_manager::borrow_config<MockConfig>(&manager, config_key);
            assert!(config_ref.value == 42, 1);
            assert!(config_ref.name == string::utf8(b"test_config"), 2);

            // Check manager stats
            let (_, _, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(total_configs == 1, 3);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_config() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize and add initial config
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            
            let initial_config = create_mock_config(10, string::utf8(b"initial"), ctx(&mut scenario));
            let config_key = string::utf8(b"UPDATE_TEST");

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                initial_config,
                string::utf8(b"Initial configuration"),
                &clock,
                ctx(&mut scenario)
            );

            // Advance time to bypass update cooldown
            clock::increment_for_testing(&mut clock, 2000000); // 2000 seconds

            // Update with new config
            let new_config = create_mock_config(20, string::utf8(b"updated"), ctx(&mut scenario));
            let old_config = config_manager::update_config(
                &admin_cap,
                &mut manager,
                config_key,
                new_config,
                &clock,
                ctx(&mut scenario)
            );

            // Check old config values
            assert!(old_config.value == 10, 0);
            assert!(old_config.name == string::utf8(b"initial"), 1);

            // Check new config values
            let updated_config_ref = config_manager::borrow_config<MockConfig>(&manager, config_key);
            assert!(updated_config_ref.value == 20, 2);
            assert!(updated_config_ref.name == string::utf8(b"updated"), 3);

            // Clean up old config
            let MockConfig { id, value: _, name: _ } = old_config;
            object::delete(id);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_config() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize and add config
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            
            let config = create_mock_config(99, string::utf8(b"to_remove"), ctx(&mut scenario));
            let config_key = string::utf8(b"REMOVE_TEST");

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config,
                string::utf8(b"Config to be removed"),
                &clock,
                ctx(&mut scenario)
            );

            // Verify config exists
            assert!(config_manager::has_config<MockConfig>(&manager, config_key), 0);

            // Remove config
            let removed_config = config_manager::remove_config<MockConfig>(
                &admin_cap,
                &mut manager,
                config_key,
                &clock,
                ctx(&mut scenario)
            );

            // Verify config no longer exists
            assert!(!config_manager::has_config<MockConfig>(&manager, config_key), 1);

            // Check removed config values
            assert!(removed_config.value == 99, 2);
            assert!(removed_config.name == string::utf8(b"to_remove"), 3);

            // Check manager stats
            let (_, _, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(total_configs == 0, 4);

            // Clean up removed config
            let MockConfig { id, value: _, name: _ } = removed_config;
            object::delete(id);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Type Safety Tests ===

    #[test]
    fun test_type_safety() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Add two different types of configs
            let mock_config = create_mock_config(42, string::utf8(b"mock"), ctx(&mut scenario));
            let another_config = create_another_mock_config(b"test_data", true, ctx(&mut scenario));

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                string::utf8(b"MOCK_CONFIG"),
                mock_config,
                string::utf8(b"Mock configuration"),
                &clock,
                ctx(&mut scenario)
            );

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                string::utf8(b"ANOTHER_CONFIG"),
                another_config,
                string::utf8(b"Another configuration"),
                &clock,
                ctx(&mut scenario)
            );

            // Test type-safe access
            assert!(config_manager::has_config<MockConfig>(&manager, string::utf8(b"MOCK_CONFIG")), 0);
            assert!(config_manager::has_config<AnotherMockConfig>(&manager, string::utf8(b"ANOTHER_CONFIG")), 1);

            // Test cross-type access returns false
            assert!(!config_manager::has_config<AnotherMockConfig>(&manager, string::utf8(b"MOCK_CONFIG")), 2);
            assert!(!config_manager::has_config<MockConfig>(&manager, string::utf8(b"ANOTHER_CONFIG")), 3);

            // Test successful retrieval
            let mock_ref = config_manager::borrow_config<MockConfig>(&manager, string::utf8(b"MOCK_CONFIG"));
            assert!(mock_ref.value == 42, 4);

            let another_ref = config_manager::borrow_config<AnotherMockConfig>(&manager, string::utf8(b"ANOTHER_CONFIG"));
            assert!(another_ref.enabled == true, 5);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Batch Operations Tests ===

    #[test]
    fun test_batch_add_configs() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Prepare batch data
            let config_keys = vector[
                string::utf8(b"BATCH_1"),
                string::utf8(b"BATCH_2"),
                string::utf8(b"BATCH_3")
            ];

            let mut config_objects = vector::empty<MockConfig>();
            vector::push_back(&mut config_objects, create_mock_config(1, string::utf8(b"first"), ctx(&mut scenario)));
            vector::push_back(&mut config_objects, create_mock_config(2, string::utf8(b"second"), ctx(&mut scenario)));
            vector::push_back(&mut config_objects, create_mock_config(3, string::utf8(b"third"), ctx(&mut scenario)));

            let descriptions = vector[
                string::utf8(b"First batch config"),
                string::utf8(b"Second batch config"),
                string::utf8(b"Third batch config")
            ];

            // Execute batch add
            config_manager::batch_add_configs(
                &admin_cap,
                &mut manager,
                config_keys,
                config_objects,
                descriptions,
                &clock,
                ctx(&mut scenario)
            );

            // Verify all configs were added
            assert!(config_manager::has_config<MockConfig>(&manager, string::utf8(b"BATCH_1")), 0);
            assert!(config_manager::has_config<MockConfig>(&manager, string::utf8(b"BATCH_2")), 1);
            assert!(config_manager::has_config<MockConfig>(&manager, string::utf8(b"BATCH_3")), 2);

            // Verify values
            let config1 = config_manager::borrow_config<MockConfig>(&manager, string::utf8(b"BATCH_1"));
            assert!(config1.value == 1, 3);

            let config2 = config_manager::borrow_config<MockConfig>(&manager, string::utf8(b"BATCH_2"));
            assert!(config2.value == 2, 4);

            let config3 = config_manager::borrow_config<MockConfig>(&manager, string::utf8(b"BATCH_3"));
            assert!(config3.value == 3, 5);

            // Check total count
            let (_, _, total_configs, _) = config_manager::get_manager_health(&manager);
            assert!(total_configs == 3, 6);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Configuration Locking Tests ===

    #[test]
    fun test_config_locking() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize and add config
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            
            let config = create_mock_config(100, string::utf8(b"lockable"), ctx(&mut scenario));
            let config_key = string::utf8(b"LOCK_TEST");

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config,
                string::utf8(b"Lockable configuration"),
                &clock,
                ctx(&mut scenario)
            );

            // Lock the configuration
            config_manager::lock_config(
                &admin_cap,
                &mut manager,
                config_key,
                3600000, // 1 hour
                string::utf8(b"Testing lock functionality"),
                &clock,
                ctx(&mut scenario)
            );

            // Verify config is locked by checking metadata
            let (_, _, _, _, _, _, is_locked, _) = config_manager::get_config_metadata(&manager, config_key);
            assert!(is_locked, 0);

            // Unlock the configuration
            config_manager::unlock_config(&admin_cap, &mut manager, config_key, &clock);

            // Verify config is unlocked
            let (_, _, _, _, _, _, is_locked, _) = config_manager::get_config_metadata(&manager, config_key);
            assert!(!is_locked, 1);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Emergency Pause Tests ===

    #[test]
    fun test_emergency_pause() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Add a config before pause
            let config = create_mock_config(50, string::utf8(b"pre_pause"), ctx(&mut scenario));
            config_manager::add_config(
                &admin_cap,
                &mut manager,
                string::utf8(b"PRE_PAUSE"),
                config,
                string::utf8(b"Config added before pause"),
                &clock,
                ctx(&mut scenario)
            );

            // Trigger emergency pause
            config_manager::emergency_pause(
                &admin_cap,
                &mut manager,
                string::utf8(b"Testing emergency pause"),
                &clock,
                ctx(&mut scenario)
            );

            // Verify manager is paused
            let (is_initialized, is_paused, _, _) = config_manager::get_manager_health(&manager);
            assert!(is_initialized, 0);
            assert!(is_paused, 1);

            // Resume operations
            config_manager::resume_operations(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Verify manager is operational again
            let (is_initialized, is_paused, _, _) = config_manager::get_manager_health(&manager);
            assert!(is_initialized, 2);
            assert!(!is_paused, 3);

            // Verify config is still accessible after resume
            assert!(config_manager::has_config<MockConfig>(&manager, string::utf8(b"PRE_PAUSE")), 4);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Wrapper Functions Tests ===

    #[test]
    fun test_config_health_status() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Check initial health status (no essential configs)
            let (all_available, missing_configs) = config_wrappers::get_config_health_status(&manager);
            assert!(!all_available, 0);
            assert!(vector::length(&missing_configs) > 0, 1);

            // Add system clock
            config_manager::add_config(
                &admin_cap,
                &mut manager,
                string::utf8(b"SYSTEM_CLOCK"),
                clock,
                string::utf8(b"System clock for testing"),
                config_manager::borrow_config<Clock>(&manager, string::utf8(b"SYSTEM_CLOCK")),
                ctx(&mut scenario)
            );

            // Check if clock is detected
            assert!(config_wrappers::has_clock(&manager), 2);

            // Get comprehensive status report
            let (is_operational, all_essential_available, total_configs, available_configs, missing_configs) = 
                config_wrappers::get_configuration_status_report(&manager);
            
            assert!(is_operational, 3);
            assert!(total_configs >= 1, 4);
            assert!(vector::length(&available_configs) >= 1, 5);

            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Access Control Tests ===

    #[test]
    #[expected_failure(abort_code = config_manager::E_NOT_AUTHORIZED)]
    fun test_unauthorized_access() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, UNAUTHORIZED);
        {
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));
            
            // This should fail - unauthorized user trying to initialize
            let fake_cap = ConfigManagerAdminCap { id: object::new(ctx(&mut scenario)) };
            config_manager::initialize_config_manager(&fake_cap, &mut manager, &clock, ctx(&mut scenario));

            // Clean up
            let ConfigManagerAdminCap { id } = fake_cap;
            object::delete(id);
            transfer::public_transfer(clock, UNAUTHORIZED);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Error Handling Tests ===

    #[test]
    #[expected_failure(abort_code = config_manager::E_CONFIG_ALREADY_EXISTS)]
    fun test_duplicate_config_key() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize and add first config
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            
            let config1 = create_mock_config(1, string::utf8(b"first"), ctx(&mut scenario));
            let config_key = string::utf8(b"DUPLICATE_KEY");

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config1,
                string::utf8(b"First config"),
                &clock,
                ctx(&mut scenario)
            );

            // Try to add second config with same key - should fail
            let config2 = create_mock_config(2, string::utf8(b"second"), ctx(&mut scenario));
            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config2,
                string::utf8(b"Duplicate config"),
                &clock,
                ctx(&mut scenario)
            );

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config_manager::E_CONFIG_NOT_FOUND)]
    fun test_access_nonexistent_config() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Try to access non-existent config - should fail
            config_manager::borrow_config<MockConfig>(&manager, string::utf8(b"NONEXISTENT"));

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Performance and Limits Tests ===

    #[test]
    fun test_config_metadata_tracking() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize and add config
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));
            
            let config = create_mock_config(123, string::utf8(b"metadata_test"), ctx(&mut scenario));
            let config_key = string::utf8(b"METADATA_TEST");

            config_manager::add_config(
                &admin_cap,
                &mut manager,
                config_key,
                config,
                string::utf8(b"Testing metadata tracking"),
                &clock,
                ctx(&mut scenario)
            );

            // Get metadata
            let (config_type, description, created_at, last_updated, update_count, is_active, is_locked, access_count) = 
                config_manager::get_config_metadata(&manager, config_key);

            // Verify metadata
            assert!(description == string::utf8(b"Testing metadata tracking"), 0);
            assert!(update_count == 1, 1);
            assert!(is_active, 2);
            assert!(!is_locked, 3);
            assert!(access_count == 0, 4);
            assert!(created_at == last_updated, 5);

            // Access config to increment access count
            let _ = config_manager::borrow_config_mut<MockConfig>(&mut manager, config_key, &clock, ctx(&mut scenario));

            // Check updated metadata
            let (_, _, _, _, _, _, _, access_count) = config_manager::get_config_metadata(&manager, config_key);
            assert!(access_count == 1, 6);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // === Integration Tests ===

    #[test]
    fun test_manager_operational_status() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initially not operational (not initialized)
            assert!(!config_manager::is_manager_operational(&manager), 0);

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Still not operational (no configs)
            assert!(!config_manager::is_manager_operational(&manager), 1);

            // Add a config
            let config = create_mock_config(1, string::utf8(b"operational_test"), ctx(&mut scenario));
            config_manager::add_config(
                &admin_cap,
                &mut manager,
                string::utf8(b"OPERATIONAL_TEST"),
                config,
                string::utf8(b"Testing operational status"),
                &clock,
                ctx(&mut scenario)
            );

            // Now should be operational
            assert!(config_manager::is_manager_operational(&manager), 2);

            // Pause and check again
            config_manager::emergency_pause(
                &admin_cap,
                &mut manager,
                string::utf8(b"Testing operational status"),
                &clock,
                ctx(&mut scenario)
            );

            // Should not be operational when paused
            assert!(!config_manager::is_manager_operational(&manager), 3);

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_config_keys_management() {
        let mut scenario = setup_test_scenario();
        
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test_scenario::take_from_sender<ConfigManagerAdminCap>(&scenario);
            let mut manager = test_scenario::take_shared<ConfigManager>(&scenario);
            let clock = create_test_clock(ctx(&mut scenario));

            // Initialize manager
            config_manager::initialize_config_manager(&admin_cap, &mut manager, &clock, ctx(&mut scenario));

            // Add multiple configs
            let configs_to_add = vector[
                string::utf8(b"CONFIG_A"),
                string::utf8(b"CONFIG_B"),
                string::utf8(b"CONFIG_C")
            ];

            let mut i = 0;
            while (i < vector::length(&configs_to_add)) {
                let key = *vector::borrow(&configs_to_add, i);
                let config = create_mock_config(i, key, ctx(&mut scenario));
                config_manager::add_config(
                    &admin_cap,
                    &mut manager,
                    key,
                    config,
                    string::utf8(b"Test config"),
                    &clock,
                    ctx(&mut scenario)
                );
                i = i + 1;
            };

            // Get all keys
            let all_keys = config_manager::get_all_config_keys(&manager);
            assert!(vector::length(&all_keys) == 3, 0);

            // Verify all keys are present
            let mut j = 0;
            while (j < vector::length(&configs_to_add)) {
                let expected_key = vector::borrow(&configs_to_add, j);
                let mut found = false;
                let mut k = 0;
                while (k < vector::length(&all_keys)) {
                    if (vector::borrow(&all_keys, k) == expected_key) {
                        found = true;
                        break
                    };
                    k = k + 1;
                };
                assert!(found, j + 1);
                j = j + 1;
            };

            transfer::public_transfer(clock, ADMIN);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }
}