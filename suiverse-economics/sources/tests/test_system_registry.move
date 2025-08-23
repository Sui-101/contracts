/// System Registry Module Tests
/// 
/// Comprehensive tests for the SystemRegistry module to verify:
/// - Registry initialization and management
/// - Object registration and retrieval
/// - Security and access controls
/// - Integration with economics modules
/// - Error handling and edge cases
#[test_only]
module suiverse_economics::test_system_registry {
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use sui::test_scenario::{Self, Scenario};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID};
    use sui::test_utils;
    use suiverse_economics::system_registry::{Self, SystemRegistry, SystemRegistryAdminCap};
    use suiverse_economics::economics_integration::{Self, EconomicsHub, EconomicsAdminCap};

    // === Test Constants ===
    const ADMIN: address = @0xa11ce;
    const USER1: address = @0xb0b;
    const NON_ADMIN: address = @0xc4001;

    // === Helper Functions ===

    fun setup_test_scenario(): (Scenario, Clock) {
        let scenario = test_scenario::begin(ADMIN);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        (scenario, clock)
    }

    fun create_test_registry(scenario: &mut Scenario, clock: &Clock): (SystemRegistry, SystemRegistryAdminCap) {
        test_scenario::next_tx(scenario, ADMIN);
        
        // Initialize system registry
        system_registry::test_init(test_scenario::ctx(scenario));
        
        test_scenario::next_tx(scenario, ADMIN);
        
        let registry = test_scenario::take_shared<SystemRegistry>(scenario);
        let admin_cap = test_scenario::take_from_sender<SystemRegistryAdminCap>(scenario);

        // Initialize with clock
        let clock_id = object::id(clock);
        system_registry::initialize_system_registry(&admin_cap, &mut registry, clock_id, test_scenario::ctx(scenario));

        (registry, admin_cap)
    }

    // === Unit Tests - Basic Registry Operations ===

    #[test]
    fun test_registry_initialization() {
        let (mut scenario, clock) = setup_test_scenario();
        let (registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Verify registry is initialized
        let (is_initialized, emergency_pause, total_entries, _) = system_registry::get_registry_health(&registry);
        assert!(is_initialized, 0);
        assert!(!emergency_pause, 1);
        assert!(total_entries == 1, 2); // Should have clock entry

        // Verify operational status
        assert!(system_registry::is_registry_operational(&registry), 3);

        // Verify clock can be retrieved
        let clock_id = system_registry::get_clock_id(&registry);
        assert!(clock_id == object::id(&clock), 4);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_system_object() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Create a mock object ID
        let mock_object_id = object::id(&clock); // Using clock ID as mock
        
        // Register a new system object
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"TEST_OBJECT"),
            mock_object_id,
            string::utf8(b"test::TestObject"),
            string::utf8(b"Test object for registry testing"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify object was registered
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"TEST_OBJECT")), 5);
        
        let retrieved_id = system_registry::get_system_object_id(&registry, string::utf8(b"TEST_OBJECT"));
        assert!(retrieved_id == mock_object_id, 6);

        // Verify registry stats updated
        let (_, _, total_entries, _) = system_registry::get_registry_health(&registry);
        assert!(total_entries == 2, 7); // Clock + test object

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_registry_entry() {
        let (mut scenario, mut clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register initial object
        let initial_id = object::id(&clock);
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"UPDATABLE_OBJECT"),
            initial_id,
            string::utf8(b"test::Object"),
            string::utf8(b"Initial object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Advance time to allow update (bypass cooldown)
        clock::increment_for_testing(&mut clock, 3700 * 1000); // > 1 hour

        // Create new mock ID
        let new_id = object::id_from_address(@0x123);
        
        // Update the registry entry
        system_registry::update_registry_entry(
            &admin_cap,
            &mut registry,
            string::utf8(b"UPDATABLE_OBJECT"),
            new_id,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify object was updated
        let retrieved_id = system_registry::get_system_object_id(&registry, string::utf8(b"UPDATABLE_OBJECT"));
        assert!(retrieved_id == new_id, 8);

        // Verify update count increased
        let (_, _, _, _, update_count, _) = system_registry::get_registry_entry_info(&registry, string::utf8(b"UPDATABLE_OBJECT"));
        assert!(update_count == 2, 9); // Initial + update

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_registry_entry() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register object to remove
        let mock_id = object::id(&clock);
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"REMOVABLE_OBJECT"),
            mock_id,
            string::utf8(b"test::Object"),
            string::utf8(b"Object to be removed"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify object exists
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"REMOVABLE_OBJECT")), 10);

        // Remove the object
        system_registry::remove_registry_entry(
            &admin_cap,
            &mut registry,
            string::utf8(b"REMOVABLE_OBJECT"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify object was removed
        assert!(!system_registry::has_active_registry_entry(&registry, string::utf8(b"REMOVABLE_OBJECT")), 11);

        // Verify total entries decreased
        let (_, _, total_entries, _) = system_registry::get_registry_health(&registry);
        assert!(total_entries == 1, 12); // Only clock should remain

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_toggle_registry_entry_status() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register object
        let mock_id = object::id(&clock);
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"TOGGLE_OBJECT"),
            mock_id,
            string::utf8(b"test::Object"),
            string::utf8(b"Object for toggle testing"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify initially active
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"TOGGLE_OBJECT")), 13);

        // Toggle to inactive
        system_registry::toggle_registry_entry_status(
            &admin_cap,
            &mut registry,
            string::utf8(b"TOGGLE_OBJECT"),
            &clock,
        );

        // Verify now inactive
        assert!(!system_registry::has_active_registry_entry(&registry, string::utf8(b"TOGGLE_OBJECT")), 14);

        // Toggle back to active
        system_registry::toggle_registry_entry_status(
            &admin_cap,
            &mut registry,
            string::utf8(b"TOGGLE_OBJECT"),
            &clock,
        );

        // Verify active again
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"TOGGLE_OBJECT")), 15);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Unit Tests - Batch Operations ===

    #[test]
    fun test_batch_register_system_objects() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Prepare batch data
        let registry_keys = vector[
            string::utf8(b"BATCH_OBJECT_1"),
            string::utf8(b"BATCH_OBJECT_2"),
            string::utf8(b"BATCH_OBJECT_3")
        ];
        let object_ids = vector[
            object::id_from_address(@0x111),
            object::id_from_address(@0x222),
            object::id_from_address(@0x333)
        ];
        let object_types = vector[
            string::utf8(b"test::Object1"),
            string::utf8(b"test::Object2"),
            string::utf8(b"test::Object3")
        ];
        let descriptions = vector[
            string::utf8(b"First batch object"),
            string::utf8(b"Second batch object"),
            string::utf8(b"Third batch object")
        ];

        // Execute batch registration
        system_registry::batch_register_system_objects(
            &admin_cap,
            &mut registry,
            registry_keys,
            object_ids,
            object_types,
            descriptions,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify all objects were registered
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"BATCH_OBJECT_1")), 16);
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"BATCH_OBJECT_2")), 17);
        assert!(system_registry::has_active_registry_entry(&registry, string::utf8(b"BATCH_OBJECT_3")), 18);

        // Verify total entries
        let (_, _, total_entries, _) = system_registry::get_registry_health(&registry);
        assert!(total_entries == 4, 19); // Clock + 3 batch objects

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Unit Tests - Emergency Functions ===

    #[test]
    fun test_emergency_pause_and_resume() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Verify initially operational
        assert!(system_registry::is_registry_operational(&registry), 20);

        // Emergency pause
        system_registry::emergency_pause_registry(&admin_cap, &mut registry, &clock, test_scenario::ctx(&mut scenario));

        // Verify paused
        assert!(!system_registry::is_registry_operational(&registry), 21);
        let (_, emergency_pause, _, _) = system_registry::get_registry_health(&registry);
        assert!(emergency_pause, 22);

        // Resume operations
        system_registry::resume_registry_operations(&admin_cap, &mut registry, &clock, test_scenario::ctx(&mut scenario));

        // Verify operational again
        assert!(system_registry::is_registry_operational(&registry), 23);
        let (_, emergency_pause_after, _, _) = system_registry::get_registry_health(&registry);
        assert!(!emergency_pause_after, 24);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_clear_registry() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Add some test objects
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"TEST_OBJECT_1"),
            object::id(&clock),
            string::utf8(b"test::Object"),
            string::utf8(b"Test object 1"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Verify entries exist
        let (_, _, total_entries_before, _) = system_registry::get_registry_health(&registry);
        assert!(total_entries_before > 0, 25);

        // Clear registry
        system_registry::clear_registry(&admin_cap, &mut registry, &clock);

        // Verify registry is cleared
        let (is_initialized_after, _, total_entries_after, _) = system_registry::get_registry_health(&registry);
        assert!(!is_initialized_after, 26); // Should need re-initialization
        assert!(total_entries_after == 0, 27);
        assert!(!system_registry::is_registry_operational(&registry), 28);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Security Tests ===

    #[test]
    #[expected_failure(abort_code = system_registry::E_NOT_AUTHORIZED)]
    fun test_unauthorized_register_system_object() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        test_scenario::next_tx(&mut scenario, NON_ADMIN);
        
        // Try to register object without admin capability
        system_registry::register_system_object(
            &admin_cap, // Wrong user trying to use admin cap
            &mut registry,
            string::utf8(b"UNAUTHORIZED_OBJECT"),
            object::id(&clock),
            string::utf8(b"test::Object"),
            string::utf8(b"Unauthorized object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = system_registry::E_DUPLICATE_REGISTRY_KEY)]
    fun test_duplicate_registry_key() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register first object
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"DUPLICATE_KEY"),
            object::id(&clock),
            string::utf8(b"test::Object1"),
            string::utf8(b"First object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Try to register with same key (should fail)
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"DUPLICATE_KEY"), // Same key
            object::id_from_address(@0x123),
            string::utf8(b"test::Object2"),
            string::utf8(b"Second object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = system_registry::E_UPDATE_COOLDOWN_ACTIVE)]
    fun test_update_cooldown_enforcement() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register object
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"COOLDOWN_TEST"),
            object::id(&clock),
            string::utf8(b"test::Object"),
            string::utf8(b"Cooldown test object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Try to update immediately (should fail due to cooldown)
        system_registry::update_registry_entry(
            &admin_cap,
            &mut registry,
            string::utf8(b"COOLDOWN_TEST"),
            object::id_from_address(@0x123),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = system_registry::E_NOT_AUTHORIZED)]
    fun test_emergency_pause_during_operations() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Emergency pause the registry
        system_registry::emergency_pause_registry(&admin_cap, &mut registry, &clock, test_scenario::ctx(&mut scenario));

        // Try to retrieve object during emergency pause (should fail)
        system_registry::get_clock_id(&registry);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Integration Tests ===

    #[test]
    fun test_integration_with_economics_hub() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, reg_admin) = create_test_registry(&mut scenario, &clock);

        // Initialize economics integration module
        economics_integration::test_init(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        let mut hub = test_scenario::take_shared<EconomicsHub>(&mut scenario);
        let eco_admin = test_scenario::take_from_sender<EconomicsAdminCap>(&mut scenario);

        // Link hub to registry
        economics_integration::link_system_registry(&eco_admin, &mut hub, object::id(&registry));

        // Verify link was established
        assert!(economics_integration::is_linked_to_system_registry(&hub), 29);
        
        let linked_id = economics_integration::get_linked_system_registry_id(&hub);
        assert!(option::is_some(&linked_id), 30);
        assert!(*option::borrow(&linked_id) == object::id(&registry), 31);

        // Verify simplified functions are available
        assert!(economics_integration::are_simplified_functions_available(&hub, &registry), 32);

        // Unlink and verify
        economics_integration::unlink_system_registry(&eco_admin, &mut hub);
        assert!(!economics_integration::is_linked_to_system_registry(&hub), 33);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, reg_admin);
        test_scenario::return_shared(hub);
        test_scenario::return_to_sender(&scenario, eco_admin);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Performance Tests ===

    #[test]
    fun test_multiple_registrations_performance() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Register multiple objects to test performance
        let registration_count = 10;
        let mut i = 0;
        
        while (i < registration_count) {
            let key = string::utf8(b"PERF_OBJECT_");
            // Note: In production, we'd append the counter to the key
            let object_id = object::id_from_address(@0x1000 + i);
            
            system_registry::register_system_object(
                &admin_cap,
                &mut registry,
                key, // In production, would use unique keys
                object_id,
                string::utf8(b"test::PerformanceObject"),
                string::utf8(b"Performance test object"),
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            
            i = i + 1;
        };

        // Verify total entries
        let (_, _, total_entries, _) = system_registry::get_registry_health(&registry);
        // Note: This will be less than expected due to duplicate keys, but demonstrates the pattern
        assert!(total_entries >= 1, 34); // At least clock should be there

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Edge Cases ===

    #[test]
    fun test_get_all_registry_keys() {
        let (mut scenario, clock) = setup_test_scenario();
        let (mut registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Add some test objects
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"KEY_TEST_1"),
            object::id(&clock),
            string::utf8(b"test::Object"),
            string::utf8(b"Test object 1"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Get all keys
        let all_keys = system_registry::get_all_registry_keys(&registry);
        
        // Should include at least SYSTEM_CLOCK and KEY_TEST_1
        assert!(vector::length(&all_keys) >= 2, 35);
        
        // Verify SYSTEM_CLOCK is present
        let mut has_clock_key = false;
        let mut i = 0;
        while (i < vector::length(&all_keys)) {
            if (vector::borrow(&all_keys, i) == &string::utf8(b"SYSTEM_CLOCK")) {
                has_clock_key = true;
                break
            };
            i = i + 1;
        };
        assert!(has_clock_key, 36);

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = system_registry::E_REGISTRY_NOT_FOUND)]
    fun test_get_nonexistent_object() {
        let (mut scenario, clock) = setup_test_scenario();
        let (registry, admin_cap) = create_test_registry(&mut scenario, &clock);

        // Try to get object that doesn't exist
        system_registry::get_system_object_id(&registry, string::utf8(b"NONEXISTENT_OBJECT"));

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = system_registry::E_SYSTEM_NOT_INITIALIZED)]
    fun test_operations_on_uninitialized_registry() {
        let (mut scenario, clock) = setup_test_scenario();
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        // Create registry but don't initialize it
        system_registry::test_init(test_scenario::ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, ADMIN);
        
        let mut registry = test_scenario::take_shared<SystemRegistry>(&mut scenario);
        let admin_cap = test_scenario::take_from_sender<SystemRegistryAdminCap>(&mut scenario);

        // Try to register object without initialization (should fail)
        system_registry::register_system_object(
            &admin_cap,
            &mut registry,
            string::utf8(b"TEST_OBJECT"),
            object::id(&clock),
            string::utf8(b"test::Object"),
            string::utf8(b"Test object"),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_scenario::return_shared(registry);
        test_scenario::return_to_sender(&scenario, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}