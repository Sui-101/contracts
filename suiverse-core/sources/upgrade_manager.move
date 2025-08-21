module suiverse_core::upgrade_manager {
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
    const E_INVALID_VERSION: u64 = 9002;
    const E_UPGRADE_NOT_READY: u64 = 9003;

    // =============== Structs ===============
    
    /// Central upgrade management for SuiVerse Core
    public struct UpgradeManager has key {
        id: UID,
        upgrade_cap: UpgradeCap,
        current_version: u64,
        pending_version: Option<u64>,
        authorized_upgraders: vector<address>,
        upgrade_history: vector<UpgradeRecord>,
    }

    /// Record of each upgrade
    public struct UpgradeRecord has store, copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
        upgrader: address,
    }

    /// Admin capability for upgrade operations
    public struct UpgradeAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============
    
    public struct UpgradeAuthorized has copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        authorized_by: address,
        timestamp: u64,
    }

    public struct UpgradeCompleted has copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
    }

    public struct AuthorizerAdded has copy, drop {
        new_authorizer: address,
        added_by: address,
        timestamp: u64,
    }

    public struct AuthorizerRemoved has copy, drop {
        removed_authorizer: address,
        removed_by: address,
        timestamp: u64,
    }

    // =============== Initialization ===============

    /// Initialize upgrade management during package publication
    fun init(ctx: &mut TxContext) {
        let admin_cap = UpgradeAdminCap {
            id: object::new(ctx),
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    /// Setup upgrade manager after receiving the UpgradeCap
    public fun setup_upgrade_manager(
        upgrade_cap: UpgradeCap,
        __admin_cap: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        let manager = UpgradeManager {
            id: object::new(ctx),
            upgrade_cap,
            current_version: 1,
            pending_version: option::none(),
            authorized_upgraders: vector[tx_context::sender(ctx)],
            upgrade_history: vector::empty(),
        };
        
        transfer::share_object(manager);
    }

    // =============== Upgrade Functions ===============
    
    /// Authorize an upgrade (creates upgrade ticket)
    public fun authorize_upgrade(
        manager: &mut UpgradeManager,
        __admin_cap: &UpgradeAdminCap,
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
        
        event::emit(UpgradeAuthorized {
            from_version: manager.current_version,
            to_version: new_version,
            digest,
            authorized_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
        
        ticket
    }

    /// Complete the upgrade (consumes upgrade receipt)
    public fun commit_upgrade(
        manager: &mut UpgradeManager,
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
            digest: vector::empty(),
            timestamp: clock::timestamp_ms(clock),
            upgrader: sender,
        };
        
        vector::push_back(&mut manager.upgrade_history, upgrade_record);
        manager.current_version = new_version;
        
        event::emit(UpgradeCompleted {
            from_version: upgrade_record.from_version,
            to_version: new_version,
            digest: vector::empty(),
            timestamp: upgrade_record.timestamp,
        });
    }

    // =============== Admin Functions ===============
    
    /// Add authorized upgrader
    public fun add_authorized_upgrader(
        manager: &mut UpgradeManager,
        _admin_cap: &UpgradeAdminCap,
        new_upgrader: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        vector::push_back(&mut manager.authorized_upgraders, new_upgrader);
        
        event::emit(AuthorizerAdded {
            new_authorizer: new_upgrader,
            added_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Remove authorized upgrader
    public fun remove_authorized_upgrader(
        manager: &mut UpgradeManager,
        _admin_cap: &UpgradeAdminCap,
        upgrader_to_remove: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_authorized_upgrader(manager, sender), E_NOT_AUTHORIZED);
        
        let (found, index) = vector::index_of(&manager.authorized_upgraders, &upgrader_to_remove);
        if (found) {
            vector::remove(&mut manager.authorized_upgraders, index);
            
            event::emit(AuthorizerRemoved {
                removed_authorizer: upgrader_to_remove,
                removed_by: sender,
                timestamp: clock::timestamp_ms(clock),
            });
        };
    }

    // =============== View Functions ===============
    
    /// Check if address is authorized to upgrade
    public fun is_authorized_upgrader(manager: &UpgradeManager, addr: address): bool {
        vector::contains(&manager.authorized_upgraders, &addr)
    }

    /// Get current version
    public fun current_version(manager: &UpgradeManager): u64 {
        manager.current_version
    }

    /// Get pending version if any
    public fun pending_version(manager: &UpgradeManager): Option<u64> {
        manager.pending_version
    }

    /// Get upgrade history
    public fun upgrade_history(manager: &UpgradeManager): &vector<UpgradeRecord> {
        &manager.upgrade_history
    }

    /// Get authorized upgraders
    public fun authorized_upgraders(manager: &UpgradeManager): &vector<address> {
        &manager.authorized_upgraders
    }

    /// Get latest upgrade record
    public fun latest_upgrade(manager: &UpgradeManager): Option<UpgradeRecord> {
        let history = &manager.upgrade_history;
        if (vector::length(history) > 0) {
            option::some(*vector::borrow(history, vector::length(history) - 1))
        } else {
            option::none()
        }
    }

    // =============== Helper Functions ===============
    
    /// Get upgrade record details
    public fun upgrade_record_details(record: &UpgradeRecord): (u64, u64, vector<u8>, u64, address) {
        (
            record.from_version,
            record.to_version,
            record.digest,
            record.timestamp,
            record.upgrader
        )
    }
}