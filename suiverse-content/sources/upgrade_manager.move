#[allow(duplicate_alias)]
module suiverse_content::upgrade_manager {
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::clock::{Self, Clock};
    use std::option::{Self, Option};
    use std::vector;

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 9001;
    #[allow(unused_const)]
    const E_INVALID_VERSION: u64 = 9002;
    const E_UPGRADE_NOT_READY: u64 = 9003;

    // =============== Structs ===============
    
    /// Central upgrade management for SuiVerse Content
    public struct ContentUpgradeManager has key {
        id: UID,
        upgrade_cap: UpgradeCap,
        current_version: u64,
        pending_version: Option<u64>,
        authorized_upgraders: vector<address>,
        upgrade_history: vector<UpgradeRecord>,
        core_package_version: u64, // Track compatible core package version
    }

    /// Record of each upgrade
    public struct UpgradeRecord has store, copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
        upgrader: address,
        core_version_at_upgrade: u64,
    }

    /// Admin capability for content upgrade operations
    public struct ContentUpgradeAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============
    
    public struct ContentUpgradeAuthorized has copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        authorized_by: address,
        timestamp: u64,
        core_version: u64,
    }

    public struct ContentUpgradeCompleted has copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
        core_version: u64,
    }

    public struct ContentAuthorizerAdded has copy, drop {
        new_authorizer: address,
        added_by: address,
        timestamp: u64,
    }

    public struct ContentAuthorizerRemoved has copy, drop {
        removed_authorizer: address,
        removed_by: address,
        timestamp: u64,
    }

    public struct CoreVersionUpdated has copy, drop {
        old_version: u64,
        new_version: u64,
        updated_by: address,
        timestamp: u64,
    }

    // =============== Initialization ===============

    /// Initialize upgrade management during package publication
    fun init(ctx: &mut TxContext) {
        let admin_cap = ContentUpgradeAdminCap {
            id: object::new(ctx),
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    /// Setup content upgrade manager after receiving the UpgradeCap
    public fun setup_content_upgrade_manager(
        upgrade_cap: UpgradeCap,
        _admin_cap: &ContentUpgradeAdminCap,
        initial_core_version: u64,
        ctx: &mut TxContext
    ) {
        let manager = ContentUpgradeManager {
            id: object::new(ctx),
            upgrade_cap,
            current_version: 1,
            pending_version: option::none(),
            authorized_upgraders: vector[tx_context::sender(ctx)],
            upgrade_history: vector::empty(),
            core_package_version: initial_core_version,
        };
        
        transfer::share_object(manager);
    }

    // =============== Upgrade Functions ===============
    
    /// Authorize a content package upgrade
    public fun authorize_content_upgrade(
        manager: &mut ContentUpgradeManager,
        _admin_cap: &ContentUpgradeAdminCap,
        digest: vector<u8>,
        clock: &Clock,
        ctx: &TxContext
    ): UpgradeTicket {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        let ticket = package::authorize_upgrade(
            &mut manager.upgrade_cap,
            package::compatible_policy(),
            digest
        );
        
        let new_version = manager.current_version + 1;
        manager.pending_version = option::some(new_version);
        
        event::emit(ContentUpgradeAuthorized {
            from_version: manager.current_version,
            to_version: new_version,
            digest,
            authorized_by: sender,
            timestamp: clock::timestamp_ms(clock),
            core_version: manager.core_package_version,
        });
        
        ticket
    }

    /// Complete the content package upgrade
    public fun commit_content_upgrade(
        manager: &mut ContentUpgradeManager,
        receipt: UpgradeReceipt,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        assert!(option::is_some(&manager.pending_version), E_UPGRADE_NOT_READY);
        
        let new_version = option::extract(&mut manager.pending_version);
        package::commit_upgrade(&mut manager.upgrade_cap, receipt);
        
        let upgrade_record = UpgradeRecord {
            from_version: manager.current_version,
            to_version: new_version,
            digest: vector::empty(), // Will be filled by the commit_upgrade
            timestamp: clock::timestamp_ms(clock),
            upgrader: sender,
            core_version_at_upgrade: manager.core_package_version,
        };
        
        vector::push_back(&mut manager.upgrade_history, upgrade_record);
        manager.current_version = new_version;
        
        event::emit(ContentUpgradeCompleted {
            from_version: upgrade_record.from_version,
            to_version: new_version,
            digest: vector::empty(),
            timestamp: upgrade_record.timestamp,
            core_version: manager.core_package_version,
        });
    }

    // =============== Core Package Integration ===============
    
    /// Update the tracked core package version
    public fun update_core_version(
        manager: &mut ContentUpgradeManager,
        _admin_cap: &ContentUpgradeAdminCap,
        new_core_version: u64,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        let old_version = manager.core_package_version;
        manager.core_package_version = new_core_version;
        
        event::emit(CoreVersionUpdated {
            old_version,
            new_version: new_core_version,
            updated_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // =============== Admin Functions ===============
    
    /// Add authorized upgrader for content package
    public fun add_content_authorized_upgrader(
        manager: &mut ContentUpgradeManager,
        _admin_cap: &ContentUpgradeAdminCap,
        new_upgrader: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        vector::push_back(&mut manager.authorized_upgraders, new_upgrader);
        
        event::emit(ContentAuthorizerAdded {
            new_authorizer: new_upgrader,
            added_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Remove authorized upgrader for content package
    public fun remove_content_authorized_upgrader(
        manager: &mut ContentUpgradeManager,
        _admin_cap: &ContentUpgradeAdminCap,
        upgrader_to_remove: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        let (found, index) = vector::index_of(&manager.authorized_upgraders, &upgrader_to_remove);
        if (found) {
            vector::remove(&mut manager.authorized_upgraders, index);
            
            event::emit(ContentAuthorizerRemoved {
                removed_authorizer: upgrader_to_remove,
                removed_by: sender,
                timestamp: clock::timestamp_ms(clock),
            });
        };
    }

    // =============== View Functions ===============
    
    /// Check if address is authorized to upgrade content
    public fun is_authorized_upgrader(manager: &ContentUpgradeManager, addr: address): bool {
        vector::contains(&manager.authorized_upgraders, &addr)
    }

    /// Get current content version
    public fun current_version(manager: &ContentUpgradeManager): u64 {
        manager.current_version
    }

    /// Get pending content version if any
    public fun pending_version(manager: &ContentUpgradeManager): Option<u64> {
        manager.pending_version
    }

    /// Get content upgrade history
    public fun upgrade_history(manager: &ContentUpgradeManager): &vector<UpgradeRecord> {
        &manager.upgrade_history
    }

    /// Get authorized upgraders for content
    public fun authorized_upgraders(manager: &ContentUpgradeManager): &vector<address> {
        &manager.authorized_upgraders
    }

    /// Get tracked core package version
    public fun core_package_version(manager: &ContentUpgradeManager): u64 {
        manager.core_package_version
    }

    /// Get latest content upgrade record
    public fun latest_upgrade(manager: &ContentUpgradeManager): Option<UpgradeRecord> {
        let history = &manager.upgrade_history;
        if (vector::length(history) > 0) {
            option::some(*vector::borrow(history, vector::length(history) - 1))
        } else {
            option::none()
        }
    }

    /// Check compatibility with core version
    public fun is_compatible_with_core(manager: &ContentUpgradeManager, core_version: u64): bool {
        // Simple compatibility check - content should be compatible with same or newer core
        manager.core_package_version <= core_version
    }

    // =============== Helper Functions ===============
    
    /// Get content upgrade record details
    public fun upgrade_record_details(record: &UpgradeRecord): (u64, u64, vector<u8>, u64, address, u64) {
        (
            record.from_version,
            record.to_version,
            record.digest,
            record.timestamp,
            record.upgrader,
            record.core_version_at_upgrade
        )
    }
}