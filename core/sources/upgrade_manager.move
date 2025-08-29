module core::upgrade_manager {
    use sui::package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::vec_set::{Self, VecSet};
    use sui::math;
    use std::option::{Self, Option};
    use std::vector;

    const E_NOT_AUTHORIZED: u64 = 9001;
    const E_INVALID_VERSION: u64 = 9002;
    const E_UPGRADE_NOT_READY: u64 = 9003;
    const E_INVALID_APPROVAL_RATE: u64 = 9004;
    const E_ALREADY_APPROVED: u64 = 9005;
    const E_INSUFFICIENT_APPROVALS: u64 = 9006;
    const E_NO_PENDING_PROPOSAL: u64 = 9007;

    const MIN_APPROVAL_RATE: u64 = 10;
    const MAX_APPROVAL_RATE: u64 = 100;
    const RATE_PRECISION: u64 = 100;

    public struct UpgradeManager has key {
        id: UID,
        upgrade_cap: UpgradeCap,
        current_version: u64,
        authorized_upgraders: VecSet<address>,
        upgrade_history: vector<UpgradeRecord>,
        pending_proposal: Option<UpgradeProposal>,
        approval_rate: u64,
    }

    public struct UpgradeProposal has store {
        id: u64,
        digest: vector<u8>,
        proposed_version: u64,
        proposer: address,
        approvals: VecSet<address>,
        created_at: u64,
        required_approvals: u64,
    }

    public struct UpgradeRecord has store, copy, drop {
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        timestamp: u64,
        approvals_count: u64,
        total_upgraders: u64,
    }

    public struct UpgradeAdminCap has key, store {
        id: UID,
    }

    public struct UpgradeProposed has copy, drop {
        proposal_id: u64,
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        proposed_by: address,
        required_approvals: u64,
        timestamp: u64,
    }

    public struct UpgradeApproved has copy, drop {
        proposal_id: u64,
        approved_by: address,
        current_approvals: u64,
        required_approvals: u64,
        timestamp: u64,
    }

    public struct UpgradeExecuted has copy, drop {
        proposal_id: u64,
        from_version: u64,
        to_version: u64,
        digest: vector<u8>,
        final_approvals: u64,
        timestamp: u64,
    }

    public struct ApprovalRateChanged has copy, drop {
        old_rate: u64,
        new_rate: u64,
        changed_by: address,
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

    fun init(ctx: &mut TxContext) {
        let admin_cap = UpgradeAdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    public fun setup_upgrade_manager(
        upgrade_cap: UpgradeCap,
        initial_approval_rate: u64,
        _admin_cap: &UpgradeAdminCap,
        ctx: &mut TxContext
    ) {
        assert!(
            initial_approval_rate >= MIN_APPROVAL_RATE && 
            initial_approval_rate <= MAX_APPROVAL_RATE, 
            E_INVALID_APPROVAL_RATE
        );

        let mut authorized_upgraders = vec_set::empty<address>();
        vec_set::insert(&mut authorized_upgraders, tx_context::sender(ctx));

        let manager = UpgradeManager {
            id: object::new(ctx),
            upgrade_cap,
            current_version: 1,
            authorized_upgraders,
            upgrade_history: vector::empty(),
            pending_proposal: option::none(),
            approval_rate: initial_approval_rate,
        };
        
        transfer::share_object(manager);
    }

    public fun propose_upgrade(
        manager: &mut UpgradeManager,
        digest: vector<u8>,
        clock: &Clock,
        ctx: &TxContext
    ): u64 {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        assert!(option::is_none(&manager.pending_proposal), E_UPGRADE_NOT_READY);
        
        let proposal_id = manager.current_version + 1;
        let required_approvals = calculate_required_approvals(manager);
        
        let mut approvals = vec_set::empty<address>();
        vec_set::insert(&mut approvals, sender);

        let proposal = UpgradeProposal {
            id: proposal_id,
            digest,
            proposed_version: proposal_id,
            proposer: sender,
            approvals,
            created_at: clock::timestamp_ms(clock),
            required_approvals,
        };
        
        manager.pending_proposal = option::some(proposal);
        
        event::emit(UpgradeProposed {
            proposal_id,
            from_version: manager.current_version,
            to_version: proposal_id,
            digest,
            proposed_by: sender,
            required_approvals,
            timestamp: clock::timestamp_ms(clock),
        });
        
        proposal_id
    }

    public fun approve_upgrade(
        manager: &mut UpgradeManager,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        assert!(option::is_some(&manager.pending_proposal), E_NO_PENDING_PROPOSAL);
        
        let proposal = option::borrow_mut(&mut manager.pending_proposal);
        assert!(!vec_set::contains(&proposal.approvals, &sender), E_ALREADY_APPROVED);
        
        vec_set::insert(&mut proposal.approvals, sender);
        
        let current_approvals = vec_set::size(&proposal.approvals);
        
        event::emit(UpgradeApproved {
            proposal_id: proposal.id,
            approved_by: sender,
            current_approvals,
            required_approvals: proposal.required_approvals,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    public fun execute_upgrade(
        manager: &mut UpgradeManager,
        clock: &Clock,
        ctx: &TxContext
    ): UpgradeTicket {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        assert!(option::is_some(&manager.pending_proposal), E_NO_PENDING_PROPOSAL);
        
        let proposal = option::borrow(&manager.pending_proposal);
        let current_approvals = vec_set::size(&proposal.approvals);
        
        assert!(current_approvals >= proposal.required_approvals, E_INSUFFICIENT_APPROVALS);
        
        let ticket = package::authorize_upgrade(
            &mut manager.upgrade_cap,
            package::compatible_policy(),
            proposal.digest
        );
        
        let proposal_id = proposal.id;
        let digest_copy = proposal.digest;
        let from_version = manager.current_version;
        
        option::extract(&mut manager.pending_proposal);
        
        event::emit(UpgradeExecuted {
            proposal_id,
            from_version,
            to_version: proposal_id,
            digest: digest_copy,
            final_approvals: current_approvals,
            timestamp: clock::timestamp_ms(clock),
        });
        
        ticket
    }

    public fun commit_upgrade(
        manager: &mut UpgradeManager,
        receipt: UpgradeReceipt,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        
        let new_version = manager.current_version + 1;
        package::commit_upgrade(&mut manager.upgrade_cap, receipt);
        
        let upgrade_record = UpgradeRecord {
            from_version: manager.current_version,
            to_version: new_version,
            digest: vector::empty(),
            timestamp: clock::timestamp_ms(clock),
            approvals_count: vec_set::size(&manager.authorized_upgraders),
            total_upgraders: vec_set::size(&manager.authorized_upgraders),
        };
        
        vector::push_back(&mut manager.upgrade_history, upgrade_record);
        manager.current_version = new_version;
    }

    public fun change_approval_rate(
        manager: &mut UpgradeManager,
        new_rate: u64,
        _admin_cap: &UpgradeAdminCap,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        assert!(
            new_rate >= MIN_APPROVAL_RATE && new_rate <= MAX_APPROVAL_RATE, 
            E_INVALID_APPROVAL_RATE
        );
        
        let old_rate = manager.approval_rate;
        manager.approval_rate = new_rate;
        
        event::emit(ApprovalRateChanged {
            old_rate,
            new_rate,
            changed_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }
    
    public fun add_authorized_upgrader(
        manager: &mut UpgradeManager,
        _admin_cap: &UpgradeAdminCap,
        new_upgrader: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        
        if (!vec_set::contains(&manager.authorized_upgraders, &new_upgrader)) {
            vec_set::insert(&mut manager.authorized_upgraders, new_upgrader);
            
            event::emit(AuthorizerAdded {
                new_authorizer: new_upgrader,
                added_by: sender,
                timestamp: clock::timestamp_ms(clock),
            });
        };
    }

    public fun remove_authorized_upgrader(
        manager: &mut UpgradeManager,
        _admin_cap: &UpgradeAdminCap,
        upgrader_to_remove: address,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(vec_set::contains(&manager.authorized_upgraders, &sender), E_NOT_AUTHORIZED);
        
        if (vec_set::contains(&manager.authorized_upgraders, &upgrader_to_remove)) {
            vec_set::remove(&mut manager.authorized_upgraders, &upgrader_to_remove);
            
            if (option::is_some(&manager.pending_proposal)) {
                let proposal = option::borrow_mut(&mut manager.pending_proposal);
                proposal.required_approvals = calculate_required_approvals(manager);
                
                if (vec_set::contains(&proposal.approvals, &upgrader_to_remove)) {
                    vec_set::remove(&mut proposal.approvals, &upgrader_to_remove);
                };
            };
            
            event::emit(AuthorizerRemoved {
                removed_authorizer: upgrader_to_remove,
                removed_by: sender,
                timestamp: clock::timestamp_ms(clock),
            });
        };
    }

    public fun is_authorized_upgrader(manager: &UpgradeManager, addr: address): bool {
        vec_set::contains(&manager.authorized_upgraders, &addr)
    }

    public fun current_version(manager: &UpgradeManager): u64 {
        manager.current_version
    }

    public fun approval_rate(manager: &UpgradeManager): u64 {
        manager.approval_rate
    }

    public fun pending_proposal(manager: &UpgradeManager): Option<UpgradeProposal> {
        manager.pending_proposal
    }

    public fun upgrade_history(manager: &UpgradeManager): &vector<UpgradeRecord> {
        &manager.upgrade_history
    }

    public fun authorized_upgraders(manager: &UpgradeManager): &VecSet<address> {
        &manager.authorized_upgraders
    }

    public fun proposal_status(manager: &UpgradeManager): (u64, u64, bool) {
        if (option::is_some(&manager.pending_proposal)) {
            let proposal = option::borrow(&manager.pending_proposal);
            let current_approvals = vec_set::size(&proposal.approvals);
            let ready = current_approvals >= proposal.required_approvals;
            (current_approvals, proposal.required_approvals, ready)
        } else {
            (0, 0, false)
        }
    }

    fun calculate_required_approvals(manager: &UpgradeManager): u64 {
        let total_upgraders = vec_set::size(&manager.authorized_upgraders);
        let required = math::divide_and_round_up(total_upgraders * manager.approval_rate, RATE_PRECISION);
        math::max(required, 1)
    }

    public fun proposal_details(proposal: &UpgradeProposal): (u64, vector<u8>, u64, address, u64, u64, u64) {
        (
            proposal.id,
            proposal.digest,
            proposal.proposed_version,
            proposal.proposer,
            vec_set::size(&proposal.approvals),
            proposal.required_approvals,
            proposal.created_at
        )
    }

    public fun has_user_approved(manager: &UpgradeManager, user: address): bool {
        if (option::is_some(&manager.pending_proposal)) {
            let proposal = option::borrow(&manager.pending_proposal);
            vec_set::contains(&proposal.approvals, &user)
        } else {
            false
        }
    }
}