/// Enhanced Kiosk Integration Module for SuiVerse
/// Provides comprehensive NFT marketplace integration for certificates
/// Implements trading, royalties, and display functionality using Sui's Kiosk framework
module suiverse_certificate::kiosk_integration {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap, PurchaseCap};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::package;
    use sui::display;
    use sui::hash;
    use sui::address;
    use sui::bcs;
    use sui::url::{Self, Url};
    use suiverse_certificate::certificates::{Self, CertificateNFT};
    use suiverse_core::treasury;

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 14001;
    const E_KIOSK_NOT_FOUND: u64 = 14002;
    const E_CERTIFICATE_NOT_TRADEABLE: u64 = 14003;
    const E_INSUFFICIENT_PAYMENT: u64 = 14004;
    const E_INVALID_PRICE: u64 = 14005;
    const E_LISTING_NOT_FOUND: u64 = 14006;
    const E_AUCTION_NOT_ACTIVE: u64 = 14007;
    const E_BID_TOO_LOW: u64 = 14008;
    const E_AUCTION_ENDED: u64 = 14009;
    const E_TRANSFER_POLICY_VIOLATION: u64 = 14010;
    const E_ROYALTY_CALCULATION_ERROR: u64 = 14011;
    const E_DISPLAY_FEE_NOT_PAID: u64 = 14012;

    // Default values
    const DEFAULT_ROYALTY_RATE: u64 = 500; // 5% in basis points
    const PLATFORM_FEE_RATE: u64 = 250; // 2.5% in basis points
    const DISPLAY_FEE: u64 = 1000000; // 0.001 SUI per day
    const AUCTION_DURATION: u64 = 604800000; // 7 days in ms
    const BID_INCREMENT: u64 = 5; // 5% minimum increment
    
    // Treasury pool types (matching treasury module)
    const POOL_OPERATIONS: u8 = 4;
    const POOL_ROYALTIES: u8 = 7;

    // Listing types
    const LISTING_TYPE_FIXED_PRICE: u8 = 1;
    const LISTING_TYPE_AUCTION: u8 = 2;
    const LISTING_TYPE_DISPLAY_ONLY: u8 = 3;

    // Auction status
    const AUCTION_STATUS_ACTIVE: u8 = 1;
    const AUCTION_STATUS_ENDED: u8 = 2;
    const AUCTION_STATUS_CANCELLED: u8 = 3;

    // =============== Core Structs ===============
    
    /// Enhanced certificate kiosk with comprehensive marketplace features
    public struct CertificateKiosk has key {
        id: UID,
        owner: address,
        kiosk_id: ID,
        display_name: String,
        description: String,
        
        // Trading statistics
        total_sales: u64,
        total_revenue: u64,
        certificates_listed: u64,
        successful_sales: u64,
        
        // Active listings
        fixed_price_listings: Table<ID, FixedPriceListing>,
        auction_listings: Table<ID, AuctionListing>,
        display_listings: Table<ID, DisplayListing>,
        
        // Revenue tracking
        pending_royalties: Balance<SUI>,
        lifetime_earnings: u64,
        
        // Configuration
        default_royalty_rate: u64,
        auto_accept_offers: bool,
        verification_required: bool,
        
        // Timestamps
        created_at: u64,
        last_activity: u64,
    }

    /// Fixed price listing for immediate sale
    public struct FixedPriceListing has store {
        certificate_id: ID,
        seller: address,
        price: u64,
        royalty_rate: u64,
        description: String,
        tags: vector<String>,
        listed_at: u64,
        expires_at: Option<u64>,
        view_count: u64,
        inquiry_count: u64,
    }

    /// Auction listing for competitive bidding
    public struct AuctionListing has key, store {
        id: UID,
        certificate_id: ID,
        seller: address,
        starting_price: u64,
        current_bid: u64,
        highest_bidder: Option<address>,
        royalty_rate: u64,
        description: String,
        auction_end: u64,
        status: u8,
        bid_history: vector<BidRecord>,
        reserve_price: Option<u64>,
        auto_extend: bool, // Extend if bid in last 10 minutes
    }

    /// Display-only listing for showcasing (no sale)
    public struct DisplayListing has store {
        certificate_id: ID,
        owner: address,
        display_fee_paid: u64,
        display_until: u64,
        description: String,
        contact_info: Option<String>,
        view_count: u64,
    }

    /// Individual bid record
    public struct BidRecord has store, drop, copy {
        bidder: address,
        amount: u64,
        timestamp: u64,
    }

    /// Transfer policy for certificate trading
    public struct CertificateTransferPolicy has key {
        id: UID,
        royalty_rates: Table<u8, u64>, // certificate_type -> royalty_rate
        platform_fee_rate: u64,
        min_listing_price: u64,
        max_listing_duration: u64,
        verification_required_for_high_value: bool,
        high_value_threshold: u64,
    }

    /// Marketplace for certificate discovery and trading
    public struct CertificateMarketplace has key {
        id: UID,
        total_kiosks: u64,
        total_listings: u64,
        total_sales: u64,
        total_volume: u64,
        
        // Discovery indices
        kiosks_by_owner: Table<address, ID>,
        listings_by_type: Table<u8, VecSet<ID>>,
        listings_by_price_range: Table<u64, VecSet<ID>>, // price_bucket -> listings
        trending_certificates: vector<ID>,
        
        // Economic tracking
        total_royalties_paid: u64,
        platform_revenue: u64,
        average_sale_price: u64,
        
        // Platform configuration
        treasury: Balance<SUI>,
        admin_cap_id: ID,
        is_paused: bool,
    }

    /// Certificate offer from potential buyers
    public struct CertificateOffer has key {
        id: UID,
        certificate_id: ID,
        kiosk_id: ID,
        buyer: address,
        amount: u64,
        message: String,
        expires_at: u64,
        deposit: Balance<SUI>,
        status: u8, // 0: pending, 1: accepted, 2: rejected, 3: expired
    }

    /// Analytics for marketplace insights
    public struct MarketplaceAnalytics has key {
        id: UID,
        sales_by_day: Table<u64, u64>, // epoch -> volume
        popular_certificate_types: Table<u8, u64>,
        price_trends: Table<u64, u64>, // timestamp -> avg_price
        top_sellers: vector<address>,
        most_traded_certificates: vector<ID>,
        market_cap_by_type: Table<u8, u64>,
        last_updated: u64,
    }

    /// Administrative capability for kiosk system
    public struct KioskAdminCap has key, store {
        id: UID,
    }
    
    // Escrow metadata removed - using simplified escrow in treasury

    /// One-time witness for package publishing
    public struct KIOSK_INTEGRATION has drop {}

    // =============== Events ===============
    
    public struct KioskCreated has copy, drop {
        kiosk_id: ID,
        owner: address,
        display_name: String,
        timestamp: u64,
    }

    public struct CertificateListedForSale has copy, drop {
        certificate_id: ID,
        kiosk_id: ID,
        listing_type: u8,
        price: u64,
        seller: address,
        timestamp: u64,
    }

    public struct CertificateSold has copy, drop {
        certificate_id: ID,
        kiosk_id: ID,
        seller: address,
        buyer: address,
        sale_price: u64,
        royalty_paid: u64,
        platform_fee: u64,
        timestamp: u64,
    }

    public struct AuctionStarted has copy, drop {
        certificate_id: ID,
        kiosk_id: ID,
        seller: address,
        starting_price: u64,
        auction_end: u64,
        timestamp: u64,
    }

    public struct BidPlaced has copy, drop {
        certificate_id: ID,
        auction_id: ID,
        bidder: address,
        bid_amount: u64,
        previous_bid: u64,
        timestamp: u64,
    }

    public struct AuctionEnded has copy, drop {
        certificate_id: ID,
        auction_id: ID,
        winner: Option<address>,
        winning_bid: u64,
        total_bids: u64,
        timestamp: u64,
    }

    public struct OfferMade has copy, drop {
        offer_id: ID,
        certificate_id: ID,
        buyer: address,
        amount: u64,
        expires_at: u64,
        timestamp: u64,
    }

    public struct OfferAccepted has copy, drop {
        offer_id: ID,
        certificate_id: ID,
        seller: address,
        buyer: address,
        amount: u64,
        timestamp: u64,
    }

    public struct CertificateDisplayed has copy, drop {
        certificate_id: ID,
        kiosk_id: ID,
        owner: address,
        display_fee: u64,
        display_until: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(otw: KIOSK_INTEGRATION, ctx: &mut TxContext) {
        // Create admin capability
        let admin_cap = KioskAdminCap {
            id: object::new(ctx),
        };
        let admin_cap_id = object::uid_to_inner(&admin_cap.id);
        
        // Initialize marketplace
        let marketplace = CertificateMarketplace {
            id: object::new(ctx),
            total_kiosks: 0,
            total_listings: 0,
            total_sales: 0,
            total_volume: 0,
            kiosks_by_owner: table::new(ctx),
            listings_by_type: table::new(ctx),
            listings_by_price_range: table::new(ctx),
            trending_certificates: vector::empty(),
            total_royalties_paid: 0,
            platform_revenue: 0,
            average_sale_price: 0,
            treasury: balance::zero(),
            admin_cap_id,
            is_paused: false,
        };
        
        // Initialize transfer policy
        let transfer_policy = CertificateTransferPolicy {
            id: object::new(ctx),
            royalty_rates: table::new(ctx),
            platform_fee_rate: PLATFORM_FEE_RATE,
            min_listing_price: 1000000, // 0.001 SUI
            max_listing_duration: 2592000000, // 30 days
            verification_required_for_high_value: true,
            high_value_threshold: 100000000000, // 100 SUI
        };
        
        // Initialize analytics
        let analytics = MarketplaceAnalytics {
            id: object::new(ctx),
            sales_by_day: table::new(ctx),
            popular_certificate_types: table::new(ctx),
            price_trends: table::new(ctx),
            top_sellers: vector::empty(),
            most_traded_certificates: vector::empty(),
            market_cap_by_type: table::new(ctx),
            last_updated: 0,
        };
        
        // Create publisher for display metadata
        let publisher = package::claim(otw, ctx);
        
        // Set up display for CertificateNFT in kiosk context
        let mut display = display::new<CertificateNFT>(&publisher, ctx);
        display::add(&mut display, string::utf8(b"name"), string::utf8(b"SuiVerse Certificate: {title}"));
        display::add(&mut display, string::utf8(b"description"), string::utf8(b"Verified educational certificate: {description}"));
        display::add(&mut display, string::utf8(b"image_url"), string::utf8(b"{image_url}"));
        display::add(&mut display, string::utf8(b"attributes"), string::utf8(b"Type: {certificate_type}, Level: {level}, Skills: {skills_certified}"));
        display::add(&mut display, string::utf8(b"creator"), string::utf8(b"SuiVerse Platform"));
        display::update_version(&mut display);
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
        transfer::share_object(marketplace);
        transfer::share_object(transfer_policy);
        transfer::share_object(analytics);
    }

    // =============== Public Entry Functions ===============

    /// Create a new certificate kiosk for trading
    public entry fun create_certificate_kiosk(
        marketplace: &mut CertificateMarketplace,
        display_name: String,
        description: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(!marketplace.is_paused, E_NOT_AUTHORIZED);
        assert!(!table::contains(&marketplace.kiosks_by_owner, owner), E_KIOSK_NOT_FOUND);
        
        // Create actual Sui kiosk
        let (kiosk, kiosk_owner_cap) = kiosk::new(ctx);
        let kiosk_id = object::id(&kiosk);
        
        // Create certificate kiosk wrapper
        let cert_kiosk = CertificateKiosk {
            id: object::new(ctx),
            owner,
            kiosk_id,
            display_name,
            description,
            total_sales: 0,
            total_revenue: 0,
            certificates_listed: 0,
            successful_sales: 0,
            fixed_price_listings: table::new(ctx),
            auction_listings: table::new(ctx),
            display_listings: table::new(ctx),
            pending_royalties: balance::zero(),
            lifetime_earnings: 0,
            default_royalty_rate: DEFAULT_ROYALTY_RATE,
            auto_accept_offers: false,
            verification_required: false,
            created_at: current_time,
            last_activity: current_time,
        };
        
        let cert_kiosk_id = object::uid_to_inner(&cert_kiosk.id);
        
        // Update marketplace
        table::add(&mut marketplace.kiosks_by_owner, owner, cert_kiosk_id);
        marketplace.total_kiosks = marketplace.total_kiosks + 1;
        
        event::emit(KioskCreated {
            kiosk_id: cert_kiosk_id,
            owner,
            display_name,
            timestamp: current_time,
        });
        
        transfer::public_share_object(kiosk);
        transfer::public_transfer(kiosk_owner_cap, owner);
        transfer::share_object(cert_kiosk);
    }

    /// List certificate for fixed price sale
    public entry fun list_certificate_fixed_price(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate: CertificateNFT,
        price: u64,
        description: String,
        tags: vector<String>,
        expires_in_days: u64, // 0 for no expiration
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let seller = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(cert_kiosk.owner == seller, E_NOT_AUTHORIZED);
        assert!(!marketplace.is_paused, E_NOT_AUTHORIZED);
        assert!(price > 0, E_INVALID_PRICE);
        assert!(certificates::is_certificate_tradeable(&certificate), E_CERTIFICATE_NOT_TRADEABLE);
        
        let certificate_id = object::id(&certificate);
        let certificate_type = certificates::get_certificate_type(&certificate);
        
        // Calculate expiration
        let expires_at = if (expires_in_days > 0) {
            option::some(current_time + (expires_in_days * 86400000))
        } else {
            option::none()
        };
        
        // Place certificate in kiosk
        kiosk::place(kiosk, kiosk_cap, certificate);
        kiosk::list<CertificateNFT>(kiosk, kiosk_cap, certificate_id, price);
        
        // Create listing record
        let listing = FixedPriceListing {
            certificate_id,
            seller,
            price,
            royalty_rate: cert_kiosk.default_royalty_rate,
            description,
            tags,
            listed_at: current_time,
            expires_at,
            view_count: 0,
            inquiry_count: 0,
        };
        
        // Update kiosk and marketplace
        table::add(&mut cert_kiosk.fixed_price_listings, certificate_id, listing);
        cert_kiosk.certificates_listed = cert_kiosk.certificates_listed + 1;
        cert_kiosk.last_activity = current_time;
        
        marketplace.total_listings = marketplace.total_listings + 1;
        update_marketplace_indices(marketplace, certificate_id, certificate_type, price);
        
        event::emit(CertificateListedForSale {
            certificate_id,
            kiosk_id: cert_kiosk.kiosk_id,
            listing_type: LISTING_TYPE_FIXED_PRICE,
            price,
            seller,
            timestamp: current_time,
        });
    }

    /// Purchase certificate from fixed price listing
    public entry fun purchase_certificate_fixed_price(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        analytics: &mut MarketplaceAnalytics,
        kiosk: &mut Kiosk,
        transfer_policy: &CertificateTransferPolicy,
        certificate_id: ID,
        mut payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let buyer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(!marketplace.is_paused, E_NOT_AUTHORIZED);
        assert!(table::contains(&cert_kiosk.fixed_price_listings, certificate_id), E_LISTING_NOT_FOUND);
        
        // Get listing details and destructure it to consume it
        let listing = table::remove(&mut cert_kiosk.fixed_price_listings, certificate_id);
        assert!(coin::value(&payment) >= listing.price, E_INSUFFICIENT_PAYMENT);
        
        // Check expiration
        if (option::is_some(&listing.expires_at)) {
            let expiry = *option::borrow(&listing.expires_at);
            assert!(current_time < expiry, E_AUCTION_ENDED);
        };
        
        // Extract listing details to consume the struct
        let FixedPriceListing {
            certificate_id: _,
            seller,
            price,
            royalty_rate,
            description: _,
            tags: _,
            listed_at: _,
            expires_at: _,
            view_count: _,
            inquiry_count: _,
        } = listing;
        
        // Calculate fees
        let royalty_amount = (price * royalty_rate) / 10000;
        let platform_fee = (price * transfer_policy.platform_fee_rate) / 10000;
        let seller_amount = price - royalty_amount - platform_fee;
        
        // Process payments first
        let royalty_coin = coin::split(&mut payment, royalty_amount, ctx);
        let platform_coin = coin::split(&mut payment, platform_fee, ctx);
        let seller_coin = coin::split(&mut payment, seller_amount, ctx);
        
        // Check if there's excess payment before purchase
        let excess_amount = coin::value(&payment) - price;
        let mut excess_payment = if (excess_amount > 0) {
            option::some(coin::split(&mut payment, excess_amount, ctx))
        } else {
            option::none()
        };
        
        // TODO: This function needs proper kiosk integration with transfer policies
        // For now, we abort as this feature is not fully implemented
        // In production, this would:
        // 1. Use kiosk::purchase with proper TransferRequest handling
        // 2. Integrate with Sui's transfer policy system
        // 3. Handle royalties and platform fees through the policy system
        abort(E_TRANSFER_POLICY_VIOLATION)
    }

    /// Start auction for certificate
    public entry fun start_certificate_auction(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate: CertificateNFT,
        starting_price: u64,
        reserve_price: u64, // 0 for no reserve
        description: String,
        auction_duration_hours: u64,
        auto_extend: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let seller = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(cert_kiosk.owner == seller, E_NOT_AUTHORIZED);
        assert!(!marketplace.is_paused, E_NOT_AUTHORIZED);
        assert!(starting_price > 0, E_INVALID_PRICE);
        assert!(certificates::is_certificate_tradeable(&certificate), E_CERTIFICATE_NOT_TRADEABLE);
        assert!(auction_duration_hours >= 1 && auction_duration_hours <= 168, E_INVALID_PRICE); // 1 hour to 7 days
        
        let certificate_id = object::id(&certificate);
        let auction_end = current_time + (auction_duration_hours * 3600000); // Convert to ms
        
        // Place certificate in kiosk (but don't list for fixed price)
        kiosk::place(kiosk, kiosk_cap, certificate);
        
        // Create auction listing
        let auction = AuctionListing {
            id: object::new(ctx),
            certificate_id,
            seller,
            starting_price,
            current_bid: 0,
            highest_bidder: option::none(),
            royalty_rate: cert_kiosk.default_royalty_rate,
            description,
            auction_end,
            status: AUCTION_STATUS_ACTIVE,
            bid_history: vector::empty(),
            reserve_price: if (reserve_price > 0) { option::some(reserve_price) } else { option::none() },
            auto_extend,
        };
        
        // Update kiosk and marketplace
        table::add(&mut cert_kiosk.auction_listings, certificate_id, auction);
        cert_kiosk.certificates_listed = cert_kiosk.certificates_listed + 1;
        cert_kiosk.last_activity = current_time;
        
        marketplace.total_listings = marketplace.total_listings + 1;
        
        event::emit(AuctionStarted {
            certificate_id,
            kiosk_id: cert_kiosk.kiosk_id,
            seller,
            starting_price,
            auction_end,
            timestamp: current_time,
        });
    }

    /// Place bid on certificate auction
    public entry fun place_bid(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        certificate_id: ID,
        bid_amount: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let bidder = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(table::contains(&cert_kiosk.auction_listings, certificate_id), E_LISTING_NOT_FOUND);
        assert!(coin::value(&payment) >= bid_amount, E_INSUFFICIENT_PAYMENT);
        
        let auction = table::borrow_mut(&mut cert_kiosk.auction_listings, certificate_id);
        assert!(auction.status == AUCTION_STATUS_ACTIVE, E_AUCTION_NOT_ACTIVE);
        assert!(current_time < auction.auction_end, E_AUCTION_ENDED);
        
        // Validate bid amount
        let min_bid = if (auction.current_bid == 0) {
            auction.starting_price
        } else {
            auction.current_bid + ((auction.current_bid * BID_INCREMENT) / 100)
        };
        assert!(bid_amount >= min_bid, E_BID_TOO_LOW);
        
        // Return previous highest bid if exists
        if (option::is_some(&auction.highest_bidder)) {
            let previous_bidder = *option::borrow(&auction.highest_bidder);
            let return_amount = auction.current_bid;
            // Would return the previous bid to the previous bidder
            // This is simplified - in production, bids would be held in escrow
        };
        
        // Update auction with new bid
        auction.current_bid = bid_amount;
        auction.highest_bidder = option::some(bidder);
        
        // Record bid in history
        let bid_record = BidRecord {
            bidder,
            amount: bid_amount,
            timestamp: current_time,
        };
        vector::push_back(&mut auction.bid_history, bid_record);
        
        // Auto-extend if bid placed in last 10 minutes and auto_extend is enabled
        if (auction.auto_extend && (auction.auction_end - current_time) < 600000) { // 10 minutes
            auction.auction_end = current_time + 600000; // Extend by 10 minutes
        };
        
        // Hold the bid payment in escrow system (simplified - in production would use proper escrow)
        let escrow_balance = coin::into_balance(payment);
        balance::join(&mut marketplace.treasury, escrow_balance);
        
        event::emit(BidPlaced {
            certificate_id,
            auction_id: object::id(auction),
            bidder,
            bid_amount,
            previous_bid: if (vector::length(&auction.bid_history) > 1) {
                vector::borrow(&auction.bid_history, vector::length(&auction.bid_history) - 2).amount
            } else {
                0
            },
            timestamp: current_time,
        });
    }

    /// End auction and finalize sale
    public entry fun end_auction(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        analytics: &mut MarketplaceAnalytics,
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        transfer_policy: &CertificateTransferPolicy,
        certificate_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        assert!(table::contains(&cert_kiosk.auction_listings, certificate_id), E_LISTING_NOT_FOUND);
        
        let auction = table::remove(&mut cert_kiosk.auction_listings, certificate_id);
        assert!(current_time >= auction.auction_end, E_AUCTION_NOT_ACTIVE);
        assert!(auction.status == AUCTION_STATUS_ACTIVE, E_AUCTION_NOT_ACTIVE);
        
        let total_bids = vector::length(&auction.bid_history);
        
        // Extract auction data for later use and delete the auction object
        let AuctionListing {
            id,
            certificate_id: _,
            seller,
            starting_price: _,
            current_bid,
            highest_bidder,
            royalty_rate,
            description: _,
            auction_end: _,
            status: _,
            bid_history: _,
            reserve_price,
            auto_extend: _,
        } = auction;
        
        let auction_id = object::uid_to_inner(&id);
        object::delete(id);
        
        if (option::is_some(&highest_bidder) && current_bid > 0) {
            // Check reserve price if set
            let reserve_met = if (option::is_some(&reserve_price)) {
                current_bid >= *option::borrow(&reserve_price)
            } else {
                true
            };
            
            if (reserve_met) {
                // Successful auction - process sale
                let winner = *option::borrow(&highest_bidder);
                let winning_bid = current_bid;
                
                // Calculate fees (same as fixed price sale)
                let royalty_amount = (winning_bid * royalty_rate) / 10000;
                let platform_fee = (winning_bid * transfer_policy.platform_fee_rate) / 10000;
                let seller_amount = winning_bid - royalty_amount - platform_fee;
                
                // Take certificate from kiosk using proper ownership transfer
                let certificate = kiosk::take<CertificateNFT>(kiosk, kiosk_cap, certificate_id);
                
                // Process payments (simplified - would use proper escrow)
                // In production, the winning bid would already be held in escrow
                
                // Update statistics
                cert_kiosk.total_sales = cert_kiosk.total_sales + 1;
                cert_kiosk.successful_sales = cert_kiosk.successful_sales + 1;
                cert_kiosk.total_revenue = cert_kiosk.total_revenue + winning_bid;
                cert_kiosk.lifetime_earnings = cert_kiosk.lifetime_earnings + seller_amount;
                
                marketplace.total_sales = marketplace.total_sales + 1;
                marketplace.total_volume = marketplace.total_volume + winning_bid;
                update_average_sale_price(marketplace, winning_bid);
                
                // Update analytics
                update_sales_analytics(analytics, certificates::get_certificate_type(&certificate), winning_bid, current_time);
                
                event::emit(AuctionEnded {
                    certificate_id,
                    auction_id,
                    winner: option::some(winner),
                    winning_bid,
                    total_bids,
                    timestamp: current_time,
                });
                
                // Transfer certificate to winner
                transfer::public_transfer(certificate, winner);
            } else {
                // Reserve not met - return certificate to seller
                let certificate = kiosk::take<CertificateNFT>(kiosk, kiosk_cap, certificate_id);
                transfer::public_transfer(certificate, seller);
                
                event::emit(AuctionEnded {
                    certificate_id,
                    auction_id,
                    winner: option::none(),
                    winning_bid: 0,
                    total_bids,
                    timestamp: current_time,
                });
            };
        } else {
            // No bids - return certificate to seller
            let certificate = kiosk::take<CertificateNFT>(kiosk, kiosk_cap, certificate_id);
            transfer::public_transfer(certificate, seller);
            
            event::emit(AuctionEnded {
                certificate_id,
                auction_id,
                winner: option::none(),
                winning_bid: 0,
                total_bids,
                timestamp: current_time,
            });
        };
        
        cert_kiosk.last_activity = current_time;
    }

    /// Display certificate without selling (for showcase)
    public entry fun display_certificate(
        cert_kiosk: &mut CertificateKiosk,
        marketplace: &mut CertificateMarketplace,
        kiosk: &mut Kiosk,
        kiosk_cap: &KioskOwnerCap,
        certificate: CertificateNFT,
        description: String,
        contact_info: String,
        display_days: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(cert_kiosk.owner == owner, E_NOT_AUTHORIZED);
        assert!(display_days > 0 && display_days <= 365, E_INVALID_PRICE);
        
        let total_display_fee = DISPLAY_FEE * display_days;
        assert!(coin::value(&payment) >= total_display_fee, E_DISPLAY_FEE_NOT_PAID);
        
        let certificate_id = object::id(&certificate);
        let display_until = current_time + (display_days * 86400000);
        
        // Place certificate in kiosk for display only
        kiosk::place(kiosk, kiosk_cap, certificate);
        
        // Create display listing
        let display_listing = DisplayListing {
            certificate_id,
            owner,
            display_fee_paid: total_display_fee,
            display_until,
            description,
            contact_info: if (string::is_empty(&contact_info)) { option::none() } else { option::some(contact_info) },
            view_count: 0,
        };
        
        // Update kiosk
        table::add(&mut cert_kiosk.display_listings, certificate_id, display_listing);
        cert_kiosk.last_activity = current_time;
        
        // Process payment - send to platform treasury
        let treasury_payment = coin::into_balance(payment);
        balance::join(&mut marketplace.treasury, treasury_payment);
        
        event::emit(CertificateDisplayed {
            certificate_id,
            kiosk_id: cert_kiosk.kiosk_id,
            owner,
            display_fee: total_display_fee,
            display_until,
            timestamp: current_time,
        });
    }

    // =============== Internal Helper Functions ===============
    
    fun update_marketplace_indices(
        marketplace: &mut CertificateMarketplace,
        certificate_id: ID,
        certificate_type: u8,
        price: u64,
    ) {
        // Update type index
        if (!table::contains(&marketplace.listings_by_type, certificate_type)) {
            table::add(&mut marketplace.listings_by_type, certificate_type, vec_set::empty());
        };
        let type_set = table::borrow_mut(&mut marketplace.listings_by_type, certificate_type);
        vec_set::insert(type_set, certificate_id);
        
        // Update price range index (simplified buckets)
        let price_bucket = get_price_bucket(price);
        if (!table::contains(&marketplace.listings_by_price_range, price_bucket)) {
            table::add(&mut marketplace.listings_by_price_range, price_bucket, vec_set::empty());
        };
        let price_set = table::borrow_mut(&mut marketplace.listings_by_price_range, price_bucket);
        vec_set::insert(price_set, certificate_id);
    }
    
    fun get_price_bucket(price: u64): u64 {
        // Simple price buckets: 0-1 SUI, 1-10 SUI, 10-100 SUI, 100+ SUI
        if (price < 1000000000) { // < 1 SUI
            0
        } else if (price < 10000000000) { // < 10 SUI
            1
        } else if (price < 100000000000) { // < 100 SUI
            2
        } else {
            3
        }
    }
    
    fun update_average_sale_price(marketplace: &mut CertificateMarketplace, sale_price: u64) {
        if (marketplace.total_sales == 0) {
            marketplace.average_sale_price = sale_price;
        } else {
            marketplace.average_sale_price = 
                (marketplace.average_sale_price * (marketplace.total_sales - 1) + sale_price) / 
                marketplace.total_sales;
        };
    }
    
    fun update_sales_analytics(
        analytics: &mut MarketplaceAnalytics,
        certificate_type: u8,
        sale_price: u64,
        timestamp: u64,
    ) {
        // Update daily sales volume
        let day_epoch = timestamp / 86400000;
        if (table::contains(&analytics.sales_by_day, day_epoch)) {
            let volume = table::borrow_mut(&mut analytics.sales_by_day, day_epoch);
            *volume = *volume + sale_price;
        } else {
            table::add(&mut analytics.sales_by_day, day_epoch, sale_price);
        };
        
        // Update certificate type popularity
        if (table::contains(&analytics.popular_certificate_types, certificate_type)) {
            let count = table::borrow_mut(&mut analytics.popular_certificate_types, certificate_type);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.popular_certificate_types, certificate_type, 1);
        };
        
        // Update price trends
        if (table::contains(&analytics.price_trends, timestamp)) {
            let avg_price = table::borrow_mut(&mut analytics.price_trends, timestamp);
            *avg_price = (*avg_price + sale_price) / 2;
        } else {
            table::add(&mut analytics.price_trends, timestamp, sale_price);
        };
        
        analytics.last_updated = timestamp;
    }

    // =============== View Functions ===============
    
    public fun get_kiosk_info(cert_kiosk: &CertificateKiosk): (String, address, u64, u64, u64) {
        (
            cert_kiosk.display_name,
            cert_kiosk.owner,
            cert_kiosk.total_sales,
            cert_kiosk.total_revenue,
            cert_kiosk.certificates_listed
        )
    }
    
    public fun get_kiosk_statistics(cert_kiosk: &CertificateKiosk): (u64, u64, u64, u64) {
        (
            cert_kiosk.total_sales,
            cert_kiosk.successful_sales,
            cert_kiosk.total_revenue,
            cert_kiosk.lifetime_earnings
        )
    }
    
    public fun get_fixed_price_listing(cert_kiosk: &CertificateKiosk, certificate_id: ID): &FixedPriceListing {
        table::borrow(&cert_kiosk.fixed_price_listings, certificate_id)
    }
    
    public fun get_auction_listing(cert_kiosk: &CertificateKiosk, certificate_id: ID): &AuctionListing {
        table::borrow(&cert_kiosk.auction_listings, certificate_id)
    }
    
    public fun get_display_listing(cert_kiosk: &CertificateKiosk, certificate_id: ID): &DisplayListing {
        table::borrow(&cert_kiosk.display_listings, certificate_id)
    }
    
    public fun get_marketplace_stats(marketplace: &CertificateMarketplace): (u64, u64, u64, u64) {
        (
            marketplace.total_kiosks,
            marketplace.total_listings,
            marketplace.total_sales,
            marketplace.total_volume
        )
    }
    
    public fun get_marketplace_economics(marketplace: &CertificateMarketplace): (u64, u64, u64) {
        (
            marketplace.total_royalties_paid,
            marketplace.platform_revenue,
            marketplace.average_sale_price
        )
    }
    
    public fun get_certificates_by_price_range(marketplace: &CertificateMarketplace, price_bucket: u64): vector<ID> {
        if (table::contains(&marketplace.listings_by_price_range, price_bucket)) {
            *vec_set::keys(table::borrow(&marketplace.listings_by_price_range, price_bucket))
        } else {
            vector::empty<ID>()
        }
    }
    
    public fun get_certificates_by_type(marketplace: &CertificateMarketplace, certificate_type: u8): vector<ID> {
        if (table::contains(&marketplace.listings_by_type, certificate_type)) {
            *vec_set::keys(table::borrow(&marketplace.listings_by_type, certificate_type))
        } else {
            vector::empty<ID>()
        }
    }
    
    public fun get_auction_details(auction: &AuctionListing): (u64, u64, Option<address>, u8, u64) {
        (
            auction.starting_price,
            auction.current_bid,
            auction.highest_bidder,
            auction.status,
            auction.auction_end
        )
    }
    
    public fun get_bid_history(auction: &AuctionListing): &vector<BidRecord> {
        &auction.bid_history
    }
    
    public fun is_auction_active(auction: &AuctionListing, clock: &Clock): bool {
        auction.status == AUCTION_STATUS_ACTIVE && clock::timestamp_ms(clock) < auction.auction_end
    }
    
    public fun get_listing_price_info(listing: &FixedPriceListing): (u64, u64, u64) {
        (listing.price, listing.royalty_rate, listing.listed_at)
    }
    
    public fun get_transfer_policy_info(policy: &CertificateTransferPolicy): (u64, u64, u64) {
        (policy.platform_fee_rate, policy.min_listing_price, policy.max_listing_duration)
    }
    
    public fun get_analytics_summary(analytics: &MarketplaceAnalytics): (vector<address>, vector<ID>, u64) {
        (
            analytics.top_sellers,
            analytics.most_traded_certificates,
            analytics.last_updated
        )
    }
    
    public fun get_daily_volume(analytics: &MarketplaceAnalytics, day_epoch: u64): u64 {
        if (table::contains(&analytics.sales_by_day, day_epoch)) {
            *table::borrow(&analytics.sales_by_day, day_epoch)
        } else {
            0
        }
    }
    
    public fun get_user_kiosk_id(marketplace: &CertificateMarketplace, user: address): Option<ID> {
        if (table::contains(&marketplace.kiosks_by_owner, user)) {
            option::some(*table::borrow(&marketplace.kiosks_by_owner, user))
        } else {
            option::none()
        }
    }
}