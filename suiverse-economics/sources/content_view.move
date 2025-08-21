module suiverse_economics::content_view {
    use std::string::String;
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use suiverse_core::parameters::{Self, SystemParameters};
    use suiverse_core::treasury::{Self, Treasury};
    use suiverse_content::articles::{Self, OriginalArticle};
    use suiverse_content::projects::{Self, Project};
    use std::string::utf8;

    // =============== Constants ===============
    const E_INSUFFICIENT_PAYMENT: u64 = 14001;
    const E_CONTENT_NOT_FOUND: u64 = 14002;
    const E_ALREADY_VIEWED: u64 = 14003;
    const E_CONTENT_FREE: u64 = 14004;
    const E_INVALID_SPONSOR: u64 = 14005;
    const E_SPONSORSHIP_EXPIRED: u64 = 14006;
    const E_INVALID_AMOUNT: u64 = 14007;
    const E_BUDGET_EXHAUSTED: u64 = 14008;
    const E_CAMPAIGN_NOT_ACTIVE: u64 = 14009;
    const E_NOT_AUTHORIZED: u64 = 14010;

    // Content types
    const CONTENT_TYPE_ARTICLE: u8 = 1;
    const CONTENT_TYPE_PROJECT: u8 = 2;
    const CONTENT_TYPE_COLLECTION: u8 = 3;

    // Campaign status
    const CAMPAIGN_PENDING: u8 = 0;
    const CAMPAIGN_ACTIVE: u8 = 1;
    const CAMPAIGN_PAUSED: u8 = 2;
    const CAMPAIGN_COMPLETED: u8 = 3;
    const CAMPAIGN_CANCELLED: u8 = 4;

    // =============== Structs ===============
    
    /// Sponsored viewing campaign
    public struct SponsorCampaign has key, store {
        id: UID,
        sponsor: address,
        content_type: u8,
        content_ids: vector<ID>,
        budget: Balance<SUI>,
        spent: u64,
        cost_per_view: u64,
        max_views: u64,
        current_views: u64,
        unique_viewers: Table<address, bool>,
        status: u8,
        created_at: u64,
        expires_at: u64,
        metadata: CampaignMetadata,
    }

    /// Campaign metadata
    public struct CampaignMetadata has store, drop {
        title: String,
        description: String,
        target_audience: Option<String>,
        keywords: vector<String>,
        analytics_enabled: bool,
    }

    /// View tracking registry
    public struct ViewRegistry has key {
        id: UID,
        user_views: Table<address, UserViewHistory>,
        content_views: Table<ID, ContentViewStats>,
        sponsor_campaigns: Table<address, vector<ID>>,
        total_views: u64,
        total_sponsored_views: u64,
        revenue_generated: u64,
    }

    /// User view history
    public struct UserViewHistory has store {
        viewed_content: Table<ID, ViewRecord>,
        total_views: u64,
        sponsored_views: u64,
        earnings: u64,
        last_view_time: u64,
    }

    /// Individual view record
    public struct ViewRecord has store, drop {
        content_id: ID,
        content_type: u8,
        viewed_at: u64,
        sponsored: bool,
        sponsor_campaign_id: Option<ID>,
        payment_received: u64,
    }

    /// Content view statistics
    public struct ContentViewStats has store {
        content_id: ID,
        total_views: u64,
        unique_viewers: u64,
        sponsored_views: u64,
        revenue_generated: u64,
        last_viewed: u64,
        viewer_list: vector<address>,
    }

    /// View payment receipt
    public struct ViewPaymentReceipt has key, store {
        id: UID,
        viewer: address,
        content_id: ID,
        campaign_id: Option<ID>,
        amount_paid: u64,
        timestamp: u64,
    }

    // =============== Events ===============
    
    public struct ContentViewed has copy, drop {
        viewer: address,
        content_id: ID,
        content_type: u8,
        sponsored: bool,
        payment: u64,
        timestamp: u64,
    }

    public struct CampaignCreated has copy, drop {
        campaign_id: ID,
        sponsor: address,
        budget: u64,
        content_count: u64,
        timestamp: u64,
    }

    public struct CampaignCompleted has copy, drop {
        campaign_id: ID,
        total_views: u64,
        total_spent: u64,
        timestamp: u64,
    }

    public struct ViewPaymentProcessed has copy, drop {
        viewer: address,
        content_id: ID,
        amount: u64,
        sponsor: Option<address>,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let registry = ViewRegistry {
            id: object::new(ctx),
            user_views: table::new(ctx),
            content_views: table::new(ctx),
            sponsor_campaigns: table::new(ctx),
            total_views: 0,
            total_sponsored_views: 0,
            revenue_generated: 0,
        };
        
        transfer::share_object(registry);
    }

    // =============== Public Entry Functions ===============
    
    /// Create a sponsored viewing campaign
    public entry fun create_sponsor_campaign(
        content_type: u8,
        content_ids: vector<ID>,
        cost_per_view: u64,
        max_views: u64,
        expires_in_days: u64,
        title: String,
        description: String,
        payment: Coin<SUI>,
        registry: &mut ViewRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sponsor = tx_context::sender(ctx);
        let budget = coin::value(&payment);
        
        // Validate inputs
        assert!(cost_per_view > 0, E_INVALID_AMOUNT);
        assert!(max_views > 0, E_INVALID_AMOUNT);
        assert!(budget >= cost_per_view * max_views, E_INSUFFICIENT_PAYMENT);
        assert!(vector::length(&content_ids) > 0, E_CONTENT_NOT_FOUND);
        
        let metadata = CampaignMetadata {
            title,
            description,
            target_audience: option::none(),
            keywords: vector::empty(),
            analytics_enabled: true,
        };
        
        let campaign = SponsorCampaign {
            id: object::new(ctx),
            sponsor,
            content_type,
            content_ids,
            budget: coin::into_balance(payment),
            spent: 0,
            cost_per_view,
            max_views,
            current_views: 0,
            unique_viewers: table::new(ctx),
            status: CAMPAIGN_ACTIVE,
            created_at: clock::timestamp_ms(clock),
            expires_at: clock::timestamp_ms(clock) + (expires_in_days * 86400000),
            metadata,
        };
        
        let campaign_id = object::uid_to_inner(&campaign.id);
        
        // Track campaign
        if (!table::contains(&registry.sponsor_campaigns, sponsor)) {
            table::add(&mut registry.sponsor_campaigns, sponsor, vector::empty());
        };
        let campaigns = table::borrow_mut(&mut registry.sponsor_campaigns, sponsor);
        vector::push_back(campaigns, campaign_id);
        
        event::emit(CampaignCreated {
            campaign_id,
            sponsor,
            budget,
            content_count: vector::length(&content_ids),
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::share_object(campaign);
    }

    /// View sponsored content
    public entry fun view_sponsored_content(
        content_id: ID,
        content_type: u8,
        campaign: &mut SponsorCampaign,
        registry: &mut ViewRegistry,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let viewer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate campaign
        assert!(campaign.status == CAMPAIGN_ACTIVE, E_CAMPAIGN_NOT_ACTIVE);
        assert!(current_time < campaign.expires_at, E_SPONSORSHIP_EXPIRED);
        assert!(campaign.current_views < campaign.max_views, E_BUDGET_EXHAUSTED);
        
        // Check if content is in campaign
        let mut found = false;
        let mut i = 0;
        while (i < vector::length(&campaign.content_ids)) {
            if (*vector::borrow(&campaign.content_ids, i) == content_id) {
                found = true;
                break
            };
            i = i + 1;
        };
        assert!(found, E_CONTENT_NOT_FOUND);
        
        // Check if user already viewed
        if (!table::contains(&campaign.unique_viewers, viewer)) {
            table::add(&mut campaign.unique_viewers, viewer, true);
        };
        
        // Process payment to viewer
        let payment_amount = campaign.cost_per_view;
        let viewer_share = (payment_amount * 70) / 100;
        
        if (balance::value(&campaign.budget) >= payment_amount) {
            let mut payment = coin::from_balance(balance::split(&mut campaign.budget, payment_amount), ctx);
            
            // Split payment: 70% to viewer, 30% to treasury
            let treasury_share = payment_amount - viewer_share;
            
            if (viewer_share > 0) {
                let viewer_payment = coin::split(&mut payment, viewer_share, ctx);
                transfer::public_transfer(viewer_payment, viewer);
            };
            
            if (treasury_share > 0) {
                treasury::deposit_funds(treasury, payment, 2, utf8(b"Content View"), clock, ctx); // Reward pool
            } else {
                // Destroy zero coin
                coin::destroy_zero(payment);
            };
            
            campaign.spent = campaign.spent + payment_amount;
            campaign.current_views = campaign.current_views + 1;
            
            // Track view
            track_view(registry, viewer, content_id, content_type, true, option::some(object::uid_to_inner(&campaign.id)), payment_amount, current_time, ctx);
            
            // Issue receipt
            let receipt = ViewPaymentReceipt {
                id: object::new(ctx),
                viewer,
                content_id,
                campaign_id: option::some(object::uid_to_inner(&campaign.id)),
                amount_paid: viewer_share,
                timestamp: current_time,
            };
            
            transfer::transfer(receipt, viewer);
            
            event::emit(ViewPaymentProcessed {
                viewer,
                content_id,
                amount: viewer_share,
                sponsor: option::some(campaign.sponsor),
                timestamp: current_time,
            });
        };
        
        // Check if campaign is complete
        if (campaign.current_views >= campaign.max_views || balance::value(&campaign.budget) < campaign.cost_per_view) {
            campaign.status = CAMPAIGN_COMPLETED;
            
            event::emit(CampaignCompleted {
                campaign_id: object::uid_to_inner(&campaign.id),
                total_views: campaign.current_views,
                total_spent: campaign.spent,
                timestamp: current_time,
            });
        };
        
        event::emit(ContentViewed {
            viewer,
            content_id,
            content_type,
            sponsored: true,
            payment: viewer_share,
            timestamp: current_time,
        });
    }

    /// View regular content (non-sponsored)
    public entry fun view_content(
        content_id: ID,
        content_type: u8,
        registry: &mut ViewRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let viewer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        track_view(registry, viewer, content_id, content_type, false, option::none(), 0, current_time, ctx);
        
        event::emit(ContentViewed {
            viewer,
            content_id,
            content_type,
            sponsored: false,
            payment: 0,
            timestamp: current_time,
        });
    }

    /// Pause a campaign
    public entry fun pause_campaign(
        campaign: &mut SponsorCampaign,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(campaign.sponsor == sender, E_NOT_AUTHORIZED);
        assert!(campaign.status == CAMPAIGN_ACTIVE, E_CAMPAIGN_NOT_ACTIVE);
        
        campaign.status = CAMPAIGN_PAUSED;
    }

    /// Resume a campaign
    public entry fun resume_campaign(
        campaign: &mut SponsorCampaign,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(campaign.sponsor == sender, E_NOT_AUTHORIZED);
        assert!(campaign.status == CAMPAIGN_PAUSED, E_CAMPAIGN_NOT_ACTIVE);
        assert!(clock::timestamp_ms(clock) < campaign.expires_at, E_SPONSORSHIP_EXPIRED);
        
        campaign.status = CAMPAIGN_ACTIVE;
    }

    /// Cancel campaign and refund remaining budget
    public entry fun cancel_campaign(
        campaign: SponsorCampaign,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        let SponsorCampaign {
            id,
            sponsor,
            content_type: _,
            content_ids: _,
            budget,
            spent: _,
            cost_per_view: _,
            max_views: _,
            current_views: _,
            unique_viewers,
            status: _,
            created_at: _,
            expires_at: _,
            metadata: _,
        } = campaign;
        
        assert!(sponsor == sender, E_NOT_AUTHORIZED);
        
        // Refund remaining budget
        if (balance::value(&budget) > 0) {
            let refund = coin::from_balance(budget, ctx);
            transfer::public_transfer(refund, sponsor);
        } else {
            balance::destroy_zero(budget);
        };
        
        // Clean up
        table::destroy_empty(unique_viewers);
        object::delete(id);
    }

    // =============== Internal Functions ===============
    
    fun track_view(
        registry: &mut ViewRegistry,
        viewer: address,
        content_id: ID,
        content_type: u8,
        sponsored: bool,
        campaign_id: Option<ID>,
        payment: u64,
        timestamp: u64,
        ctx: &mut TxContext,
    ) {
        // Update user history
        if (!table::contains(&registry.user_views, viewer)) {
            let history = UserViewHistory {
                viewed_content: table::new(ctx),
                total_views: 0,
                sponsored_views: 0,
                earnings: 0,
                last_view_time: timestamp,
            };
            table::add(&mut registry.user_views, viewer, history);
        };
        
        let user_history = table::borrow_mut(&mut registry.user_views, viewer);
        
        let record = ViewRecord {
            content_id,
            content_type,
            viewed_at: timestamp,
            sponsored,
            sponsor_campaign_id: campaign_id,
            payment_received: payment,
        };
        
        if (!table::contains(&user_history.viewed_content, content_id)) {
            table::add(&mut user_history.viewed_content, content_id, record);
        } else {
            *table::borrow_mut(&mut user_history.viewed_content, content_id) = record;
        };
        
        user_history.total_views = user_history.total_views + 1;
        if (sponsored) {
            user_history.sponsored_views = user_history.sponsored_views + 1;
            user_history.earnings = user_history.earnings + payment;
        };
        user_history.last_view_time = timestamp;
        
        // Update content stats
        if (!table::contains(&registry.content_views, content_id)) {
            let stats = ContentViewStats {
                content_id,
                total_views: 0,
                unique_viewers: 0,
                sponsored_views: 0,
                revenue_generated: 0,
                last_viewed: timestamp,
                viewer_list: vector::empty(),
            };
            table::add(&mut registry.content_views, content_id, stats);
        };
        
        let content_stats = table::borrow_mut(&mut registry.content_views, content_id);
        content_stats.total_views = content_stats.total_views + 1;
        
        // Check if new unique viewer
        let mut is_new_viewer = true;
        let mut i = 0;
        while (i < vector::length(&content_stats.viewer_list)) {
            if (*vector::borrow(&content_stats.viewer_list, i) == viewer) {
                is_new_viewer = false;
                break
            };
            i = i + 1;
        };
        
        if (is_new_viewer) {
            vector::push_back(&mut content_stats.viewer_list, viewer);
            content_stats.unique_viewers = content_stats.unique_viewers + 1;
        };
        
        if (sponsored) {
            content_stats.sponsored_views = content_stats.sponsored_views + 1;
            content_stats.revenue_generated = content_stats.revenue_generated + payment;
        };
        content_stats.last_viewed = timestamp;
        
        // Update global stats
        registry.total_views = registry.total_views + 1;
        if (sponsored) {
            registry.total_sponsored_views = registry.total_sponsored_views + 1;
            registry.revenue_generated = registry.revenue_generated + payment;
        };
    }

    // =============== View Functions ===============
    
    public fun get_campaign_status(campaign: &SponsorCampaign): u8 {
        campaign.status
    }

    public fun get_campaign_views(campaign: &SponsorCampaign): (u64, u64) {
        (campaign.current_views, campaign.max_views)
    }

    public fun get_campaign_budget_remaining(campaign: &SponsorCampaign): u64 {
        balance::value(&campaign.budget)
    }

    public fun get_user_view_stats(registry: &ViewRegistry, user: address): (u64, u64, u64) {
        if (table::contains(&registry.user_views, user)) {
            let history = table::borrow(&registry.user_views, user);
            (history.total_views, history.sponsored_views, history.earnings)
        } else {
            (0, 0, 0)
        }
    }

    public fun get_content_view_stats(registry: &ViewRegistry, content_id: ID): (u64, u64, u64) {
        if (table::contains(&registry.content_views, content_id)) {
            let stats = table::borrow(&registry.content_views, content_id);
            (stats.total_views, stats.unique_viewers, stats.revenue_generated)
        } else {
            (0, 0, 0)
        }
    }

    public fun get_global_stats(registry: &ViewRegistry): (u64, u64, u64) {
        (registry.total_views, registry.total_sponsored_views, registry.revenue_generated)
    }

    public fun has_user_viewed_content(registry: &ViewRegistry, user: address, content_id: ID): bool {
        if (table::contains(&registry.user_views, user)) {
            let history = table::borrow(&registry.user_views, user);
            table::contains(&history.viewed_content, content_id)
        } else {
            false
        }
    }
}