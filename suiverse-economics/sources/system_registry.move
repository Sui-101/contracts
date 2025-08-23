/// System Registry Module
/// 
/// Provides centralized management of system objects to simplify entry function interfaces.
/// This module acts as a registry for commonly used system objects like Clock, various 
/// registries, and other shared objects, allowing entry functions to retrieve them 
/// internally rather than requiring users to pass them as parameters.
///
/// Key benefits:
/// - Improved UX: Users don't need to know system object IDs
/// - Enhanced security: Controlled access to system object references
/// - Simplified client integration: Fewer parameters required
/// - Centralized management: Single source of truth for system objects
module suiverse_economics::system_registry {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use sui::clock::Clock;
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;

    // === Constants ===
    const MAX_REGISTRY_ENTRIES: u64 = 100;
    const REGISTRY_UPDATE_COOLDOWN: u64 = 3600000; // 1 hour in milliseconds
    
    // === Error Codes ===
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_REGISTRY_NOT_FOUND: u64 = 2;
    const E_INVALID_OBJECT_TYPE: u64 = 3;
    const E_REGISTRY_FULL: u64 = 4;
    const E_UPDATE_COOLDOWN_ACTIVE: u64 = 5;
    const E_DUPLICATE_REGISTRY_KEY: u64 = 6;
    const E_SYSTEM_NOT_INITIALIZED: u64 = 7;
    const E_INVALID_REGISTRY_KEY: u64 = 8;

    // === Structs ===

    /// Registry entry containing object reference and metadata
    public struct RegistryEntry has store, drop {
        object_id: ID,
        object_type: String,
        description: String,
        last_updated: u64,
        update_count: u64,
        is_active: bool,
        authorized_updaters: vector<address>,
    }

    /// Central system object registry
    public struct SystemRegistry has key {
        id: UID,
        entries: Table<String, RegistryEntry>,
        registry_keys: vector<String>, // Track keys for iteration
        admin_cap: ID,
        last_global_update: u64,
        total_entries: u64,
        is_initialized: bool,
        emergency_pause: bool,
    }

    /// Admin capability for registry management
    public struct SystemRegistryAdminCap has key, store {
        id: UID,
    }

    /// Registry update ticket for controlled updates
    public struct RegistryUpdateTicket {
        registry_key: String,
        new_object_id: ID,
        updated_by: address,
        timestamp: u64,
    }

    // === Events ===

    public struct RegistryEntryUpdatedEvent has copy, drop {
        registry_key: String,
        old_object_id: Option<ID>,
        new_object_id: ID,
        object_type: String,
        updated_by: address,
        timestamp: u64,
    }

    public struct RegistryEntryRemovedEvent has copy, drop {
        registry_key: String,
        object_id: ID,
        object_type: String,
        removed_by: address,
        timestamp: u64,
    }

    public struct SystemRegistryInitializedEvent has copy, drop {
        registry_id: ID,
        admin: address,
        timestamp: u64,
    }

    public struct EmergencyPauseEvent has copy, drop {
        paused: bool,
        triggered_by: address,
        timestamp: u64,
    }

    // === Initialize Function ===

    fun init(ctx: &mut TxContext) {
        let admin_cap = SystemRegistryAdminCap {
            id: object::new(ctx),
        };

        let registry = SystemRegistry {
            id: object::new(ctx),
            entries: table::new(ctx),
            registry_keys: vector::empty(),
            admin_cap: object::id(&admin_cap),
            last_global_update: 0,
            total_entries: 0,
            is_initialized: false,
            emergency_pause: false,
        };

        let registry_id = object::id(&registry);
        let admin = tx_context::sender(ctx);

        transfer::transfer(admin_cap, admin);
        transfer::share_object(registry);

        event::emit(SystemRegistryInitializedEvent {
            registry_id,
            admin,
            timestamp: 0, // Will be set when first initialized with clock
        });
    }

    // === Core Registry Functions ===

    /// Initialize the system registry with essential system objects
    public entry fun initialize_system_registry(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        clock_id: ID,
        ctx: &mut TxContext,
    ) {
        assert!(!registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        
        let current_time = 0; // Will be updated when we have access to clock
        let admin = tx_context::sender(ctx);

        // Register essential clock object
        let clock_entry = RegistryEntry {
            object_id: clock_id,
            object_type: string::utf8(b"sui::clock::Clock"),
            description: string::utf8(b"Global system clock for timestamp operations"),
            last_updated: current_time,
            update_count: 1,
            is_active: true,
            authorized_updaters: vector[admin],
        };

        table::add(&mut registry.entries, string::utf8(b"SYSTEM_CLOCK"), clock_entry);
        vector::push_back(&mut registry.registry_keys, string::utf8(b"SYSTEM_CLOCK"));
        
        registry.total_entries = 1;
        registry.is_initialized = true;
        registry.last_global_update = current_time;
    }

    /// Register a new system object in the registry
    public fun register_system_object(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_key: String,
        object_id: ID,
        object_type: String,
        description: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(registry.total_entries < MAX_REGISTRY_ENTRIES, E_REGISTRY_FULL);
        assert!(!table::contains(&registry.entries, registry_key), E_DUPLICATE_REGISTRY_KEY);

        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);

        let entry = RegistryEntry {
            object_id,
            object_type,
            description,
            last_updated: current_time,
            update_count: 1,
            is_active: true,
            authorized_updaters: vector[admin],
        };

        table::add(&mut registry.entries, registry_key, entry);
        vector::push_back(&mut registry.registry_keys, registry_key);
        registry.total_entries = registry.total_entries + 1;
        registry.last_global_update = current_time;

        event::emit(RegistryEntryUpdatedEvent {
            registry_key,
            old_object_id: option::none(),
            new_object_id: object_id,
            object_type,
            updated_by: admin,
            timestamp: current_time,
        });
    }

    /// Update an existing registry entry
    public fun update_registry_entry(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_key: String,
        new_object_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);
        
        let entry = table::borrow_mut(&mut registry.entries, registry_key);
        assert!(current_time - entry.last_updated >= REGISTRY_UPDATE_COOLDOWN, E_UPDATE_COOLDOWN_ACTIVE);

        let old_object_id = entry.object_id;
        entry.object_id = new_object_id;
        entry.last_updated = current_time;
        entry.update_count = entry.update_count + 1;
        
        registry.last_global_update = current_time;

        event::emit(RegistryEntryUpdatedEvent {
            registry_key,
            old_object_id: option::some(old_object_id),
            new_object_id,
            object_type: entry.object_type,
            updated_by: admin,
            timestamp: current_time,
        });
    }

    /// Remove a registry entry
    public fun remove_registry_entry(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_key: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);

        let entry = table::remove(&mut registry.entries, registry_key);
        
        // Remove from keys vector
        let mut i = 0;
        let len = vector::length(&registry.registry_keys);
        while (i < len) {
            if (vector::borrow(&registry.registry_keys, i) == &registry_key) {
                vector::remove(&mut registry.registry_keys, i);
                break
            };
            i = i + 1;
        };

        registry.total_entries = registry.total_entries - 1;
        registry.last_global_update = current_time;

        event::emit(RegistryEntryRemovedEvent {
            registry_key,
            object_id: entry.object_id,
            object_type: entry.object_type,
            removed_by: admin,
            timestamp: current_time,
        });
    }

    /// Activate or deactivate a registry entry
    public fun toggle_registry_entry_status(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_key: String,
        clock: &Clock,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let current_time = sui::clock::timestamp_ms(clock);
        let entry = table::borrow_mut(&mut registry.entries, registry_key);
        
        entry.is_active = !entry.is_active;
        entry.last_updated = current_time;
        registry.last_global_update = current_time;
    }

    // === Retrieval Functions ===

    /// Get object ID for a registered system object
    public fun get_system_object_id(
        registry: &SystemRegistry,
        registry_key: String,
    ): ID {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let entry = table::borrow(&registry.entries, registry_key);
        assert!(entry.is_active, E_REGISTRY_NOT_FOUND);
        entry.object_id
    }

    /// Get clock object ID - convenience function for the most commonly used object
    public fun get_clock_id(registry: &SystemRegistry): ID {
        get_system_object_id(registry, string::utf8(b"SYSTEM_CLOCK"))
    }

    /// Get market registry object ID
    public fun get_market_registry_id(registry: &SystemRegistry): ID {
        get_system_object_id(registry, string::utf8(b"MARKET_REGISTRY"))
    }

    /// Get incentive registry object ID
    public fun get_incentive_registry_id(registry: &SystemRegistry): ID {
        get_system_object_id(registry, string::utf8(b"INCENTIVE_REGISTRY"))
    }

    /// Get fee registry object ID
    public fun get_fee_registry_id(registry: &SystemRegistry): ID {
        get_system_object_id(registry, string::utf8(b"FEE_REGISTRY"))
    }

    /// Get economics hub object ID
    public fun get_economics_hub_id(registry: &SystemRegistry): ID {
        get_system_object_id(registry, string::utf8(b"ECONOMICS_HUB"))
    }

    /// Check if a registry key exists and is active
    public fun has_active_registry_entry(
        registry: &SystemRegistry,
        registry_key: String,
    ): bool {
        if (!registry.is_initialized || registry.emergency_pause) {
            return false
        };
        
        if (!table::contains(&registry.entries, registry_key)) {
            return false
        };

        let entry = table::borrow(&registry.entries, registry_key);
        entry.is_active
    }

    /// Get registry entry information
    public fun get_registry_entry_info(
        registry: &SystemRegistry,
        registry_key: String,
    ): (ID, String, String, u64, u64, bool) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let entry = table::borrow(&registry.entries, registry_key);
        (
            entry.object_id,
            entry.object_type,
            entry.description,
            entry.last_updated,
            entry.update_count,
            entry.is_active
        )
    }

    /// Get all registry keys
    public fun get_all_registry_keys(registry: &SystemRegistry): vector<String> {
        registry.registry_keys
    }

    /// Get registry statistics
    public fun get_registry_stats(registry: &SystemRegistry): (u64, u64, bool, bool) {
        (
            registry.total_entries,
            registry.last_global_update,
            registry.is_initialized,
            registry.emergency_pause
        )
    }

    // === Emergency Functions ===

    /// Emergency pause the registry (stops all retrievals)
    public entry fun emergency_pause_registry(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);
        
        registry.emergency_pause = true;
        registry.last_global_update = current_time;

        event::emit(EmergencyPauseEvent {
            paused: true,
            triggered_by: admin,
            timestamp: current_time,
        });
    }

    /// Resume registry operations
    public entry fun resume_registry_operations(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);
        
        registry.emergency_pause = false;
        registry.last_global_update = current_time;

        event::emit(EmergencyPauseEvent {
            paused: false,
            triggered_by: admin,
            timestamp: current_time,
        });
    }

    // === Batch Operations ===

    /// Register multiple system objects in a single transaction
    public fun batch_register_system_objects(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_keys: vector<String>,
        object_ids: vector<ID>,
        object_types: vector<String>,
        descriptions: vector<String>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        
        let keys_len = vector::length(&registry_keys);
        assert!(keys_len == vector::length(&object_ids), E_INVALID_REGISTRY_KEY);
        assert!(keys_len == vector::length(&object_types), E_INVALID_REGISTRY_KEY);
        assert!(keys_len == vector::length(&descriptions), E_INVALID_REGISTRY_KEY);
        assert!(registry.total_entries + keys_len <= MAX_REGISTRY_ENTRIES, E_REGISTRY_FULL);

        let current_time = sui::clock::timestamp_ms(clock);
        let admin = tx_context::sender(ctx);

        let mut i = 0;
        while (i < keys_len) {
            let registry_key = *vector::borrow(&registry_keys, i);
            let object_id = *vector::borrow(&object_ids, i);
            let object_type = *vector::borrow(&object_types, i);
            let description = *vector::borrow(&descriptions, i);

            assert!(!table::contains(&registry.entries, registry_key), E_DUPLICATE_REGISTRY_KEY);

            let entry = RegistryEntry {
                object_id,
                object_type,
                description,
                last_updated: current_time,
                update_count: 1,
                is_active: true,
                authorized_updaters: vector[admin],
            };

            table::add(&mut registry.entries, registry_key, entry);
            vector::push_back(&mut registry.registry_keys, registry_key);

            event::emit(RegistryEntryUpdatedEvent {
                registry_key,
                old_object_id: option::none(),
                new_object_id: object_id,
                object_type,
                updated_by: admin,
                timestamp: current_time,
            });

            i = i + 1;
        };

        registry.total_entries = registry.total_entries + keys_len;
        registry.last_global_update = current_time;
    }

    // === Admin Functions ===

    /// Update authorized updaters for a registry entry
    public fun update_authorized_updaters(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        registry_key: String,
        new_updaters: vector<address>,
        clock: &Clock,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        assert!(!registry.emergency_pause, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.entries, registry_key), E_REGISTRY_NOT_FOUND);

        let current_time = sui::clock::timestamp_ms(clock);
        let entry = table::borrow_mut(&mut registry.entries, registry_key);
        
        entry.authorized_updaters = new_updaters;
        entry.last_updated = current_time;
        registry.last_global_update = current_time;
    }

    /// Clear all registry entries (admin emergency function)
    public entry fun clear_registry(
        _: &SystemRegistryAdminCap,
        registry: &mut SystemRegistry,
        clock: &Clock,
    ) {
        assert!(registry.is_initialized, E_SYSTEM_NOT_INITIALIZED);
        
        let current_time = sui::clock::timestamp_ms(clock);
        
        // Clear all entries
        while (!vector::is_empty(&registry.registry_keys)) {
            let key = vector::pop_back(&mut registry.registry_keys);
            table::remove(&mut registry.entries, key);
        };

        registry.total_entries = 0;
        registry.last_global_update = current_time;
        registry.is_initialized = false; // Will need re-initialization
    }

    // === View Functions ===

    /// Check if registry is healthy and operational
    public fun is_registry_operational(registry: &SystemRegistry): bool {
        registry.is_initialized && !registry.emergency_pause && registry.total_entries > 0
    }

    /// Get registry health information
    public fun get_registry_health(registry: &SystemRegistry): (bool, bool, u64, u64) {
        (
            registry.is_initialized,
            registry.emergency_pause,
            registry.total_entries,
            registry.last_global_update
        )
    }

    // === Testing Functions ===

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_test_registry_entry(
        object_id: ID,
        object_type: String,
        description: String,
        timestamp: u64,
        admin: address,
    ): RegistryEntry {
        RegistryEntry {
            object_id,
            object_type,
            description,
            last_updated: timestamp,
            update_count: 1,
            is_active: true,
            authorized_updaters: vector[admin],
        }
    }
}