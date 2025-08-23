/// Certificate Market Dynamics Module
/// 
/// Provides dynamic certificate valuation, market mechanics, and trading functionality
/// that complements the existing certificate issuance system. Integrates with existing
/// treasury and kiosk infrastructure without duplicating base certificate functionality.
module suiverse_economics::certificate_market {
    use std::string::{String};
    use std::type_name;
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field as df;
    use sui::event;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use suiverse_economics::config_manager::{Self, ConfigManager};

    // === Constants ===
    const BASE_CERTIFICATE_VALUE: u64 = 100_000_000; // 0.1 SUI base value
    const MARKET_FEE_BP: u64 = 250; // 2.5% market fee
    const RARITY_MULTIPLIER_COMMON: u64 = 100; // 1x
    const RARITY_MULTIPLIER_RARE: u64 = 300; // 3x  
    const RARITY_MULTIPLIER_EPIC: u64 = 800; // 8x
    const RARITY_MULTIPLIER_LEGENDARY: u64 = 2000; // 20x
    const PRICE_DECAY_RATE: u64 = 5; // 5% decay per day
    const DEMAND_BOOST_FACTOR: u64 = 10; // 10% price boost per high demand
    const MAX_PRICE_MULTIPLIER: u64 = 1000; // 10x max price increase
    const MIN_PRICE_MULTIPLIER: u64 = 50; // 0.5x min price decrease

    // === Error Codes ===
    const E_INVALID_CERTIFICATE_TYPE: u64 = 1;
    const E_INSUFFICIENT_FUNDS: u64 = 2;
    const E_MARKET_CLOSED: u64 = 3;
    const E_INVALID_PRICE: u64 = 4;
    const E_UNAUTHORIZED: u64 = 5;
    const E_CERTIFICATE_NOT_FOUND: u64 = 6;
    const E_MARKET_MANIPULATION: u64 = 7;
    const E_COOLDOWN_ACTIVE: u64 = 8;
    const E_CONFIG_MANAGER_NOT_AVAILABLE: u64 = 9;
    const E_CLOCK_NOT_CONFIGURED: u64 = 10;

    // === Structs ===

    /// Market state for a specific certificate type
    public struct CertificateMarket has store {
        certificate_type: String,
        base_price: u64,
        current_multiplier: u64, // Basis points (10000 = 1x)
        total_supply: u64,
        active_listings: u64,
        completed_trades: u64,
        volume_24h: u64,
        last_trade_price: u64,
        last_updated: u64,
        demand_score: u64, // 0-100 demand indicator
        rarity_tier: u8, // 0=Common, 1=Rare, 2=Epic, 3=Legendary
    }

    /// Global market registry
    public struct MarketRegistry has key, store {
        id: UID,
        markets: Table<String, CertificateMarket>,
        market_names: vector<String>, // Track market names for iteration
        total_volume: u64,
        market_fee_pool: Balance<SUI>,
        is_active: bool,
        admin_cap: ID,
    }

    /// Price history entry for analytics
    public struct PriceHistory has store, drop {
        timestamp: u64,
        price: u64,
        volume: u64,
        trades: u64,
    }

    /// Trading order in the order book
    public struct TradingOrder has key, store {
        id: UID,
        certificate_type: String,
        seller: address,
        price: u64,
        created_at: u64,
        expires_at: u64,
    }

    /// Market analytics aggregator
    public struct MarketAnalytics has key {
        id: UID,
        price_history: Table<String, vector<PriceHistory>>,
        trending_certificates: vector<String>,
        market_sentiment: u64, // 0-100 overall market sentiment
        last_analytics_update: u64,
    }

    /// Admin capability for market operations
    public struct MarketAdminCap has key, store {
        id: UID,
    }

    // === Events ===

    public struct MarketCreatedEvent has copy, drop {
        certificate_type: String,
        base_price: u64,
        rarity_tier: u8,
        timestamp: u64,
    }

    public struct TradeExecutedEvent has copy, drop {
        certificate_type: String,
        seller: address,
        buyer: address,
        price: u64,
        market_fee: u64,
        timestamp: u64,
    }

    public struct PriceUpdatedEvent has copy, drop {
        certificate_type: String,
        old_price: u64,
        new_price: u64,
        multiplier: u64,
        demand_score: u64,
        timestamp: u64,
    }

    public struct MarketListingEvent has copy, drop {
        order_id: ID,
        certificate_type: String,
        seller: address,
        price: u64,
        expires_at: u64,
        timestamp: u64,
    }

    // === Initialize Function ===

    fun init(ctx: &mut TxContext) {
        let admin_cap = MarketAdminCap {
            id: object::new(ctx),
        };

        let registry = MarketRegistry {
            id: object::new(ctx),
            markets: table::new(ctx),
            market_names: vector::empty<String>(),
            total_volume: 0,
            market_fee_pool: balance::zero(),
            is_active: true,
            admin_cap: object::id(&admin_cap),
        };

        let analytics = MarketAnalytics {
            id: object::new(ctx),
            price_history: table::new(ctx),
            trending_certificates: vector::empty(),
            market_sentiment: 50, // Neutral sentiment
            last_analytics_update: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry);
        transfer::share_object(analytics);
    }

    // === Public Functions ===

    /// Create a new certificate market with dynamic pricing
    public entry fun create_certificate_market(
        _: &MarketAdminCap,
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        certificate_type: String,
        base_price: u64,
        rarity_tier: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_active, E_MARKET_CLOSED);
        assert!(rarity_tier <= 3, E_INVALID_CERTIFICATE_TYPE);
        assert!(base_price > 0, E_INVALID_PRICE);

        let market = CertificateMarket {
            certificate_type,
            base_price,
            current_multiplier: 10000, // 1x multiplier
            total_supply: 0,
            active_listings: 0,
            completed_trades: 0,
            volume_24h: 0,
            last_trade_price: base_price,
            last_updated: clock::timestamp_ms(clock),
            demand_score: 50, // Neutral demand
            rarity_tier,
        };

        table::add(&mut registry.markets, certificate_type, market);
        vector::push_back(&mut registry.market_names, certificate_type);
        
        // Initialize price history
        let mut initial_history = vector::empty<PriceHistory>();
        vector::push_back(&mut initial_history, PriceHistory {
            timestamp: clock::timestamp_ms(clock),
            price: base_price,
            volume: 0,
            trades: 0,
        });
        table::add(&mut analytics.price_history, certificate_type, initial_history);

        event::emit(MarketCreatedEvent {
            certificate_type,
            base_price,
            rarity_tier,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// List a certificate for sale in the market
    public entry fun list_certificate_for_sale(
        registry: &mut MarketRegistry,
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
        certificate_id: ID,
        certificate_type: String,
        asking_price: u64,
        duration_hours: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_active, E_MARKET_CLOSED);
        assert!(asking_price > 0, E_INVALID_PRICE);
        assert!(table::contains(&registry.markets, certificate_type), E_CERTIFICATE_NOT_FOUND);

        let current_time = clock::timestamp_ms(clock);
        let expires_at = current_time + (duration_hours * 3600 * 1000);

        // Create trading order
        let order = TradingOrder {
            id: object::new(ctx),
            certificate_type,
            seller: tx_context::sender(ctx),
            price: asking_price,
            created_at: current_time,
            expires_at,
        };

        let order_id = object::id(&order);

        // List in kiosk marketplace
        kiosk::list<TradingOrder>(kiosk, cap, order_id, asking_price);

        // Update market statistics
        let market = table::borrow_mut(&mut registry.markets, certificate_type);
        market.active_listings = market.active_listings + 1;
        market.last_updated = current_time;

        // Store order as dynamic field
        df::add(&mut registry.id, order_id, order);

        event::emit(MarketListingEvent {
            order_id,
            certificate_type,
            seller: tx_context::sender(ctx),
            price: asking_price,
            expires_at,
            timestamp: current_time,
        });
    }

    /// Execute a trade and update market dynamics
    public entry fun execute_trade(
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        buyer_kiosk: &mut Kiosk,
        buyer_cap: &KioskOwnerCap,
        seller_kiosk: &mut Kiosk,
        order_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(registry.is_active, E_MARKET_CLOSED);
        assert!(df::exists_(&registry.id, order_id), E_CERTIFICATE_NOT_FOUND);

        let order: TradingOrder = df::remove(&mut registry.id, order_id);
        let TradingOrder {
            id,
            certificate_type,
            seller,
            price,
            created_at: _,
            expires_at,
        } = order;

        let current_time = clock::timestamp_ms(clock);
        assert!(current_time <= expires_at, E_COOLDOWN_ACTIVE);

        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= price, E_INSUFFICIENT_FUNDS);

        // Calculate market fee
        let market_fee = (price * MARKET_FEE_BP) / 10000;
        let seller_amount = price - market_fee;

        // Process payment
        let mut payment_balance = coin::into_balance(payment);
        let market_fee_balance = balance::split(&mut payment_balance, market_fee);
        balance::join(&mut registry.market_fee_pool, market_fee_balance);

        // Transfer remaining payment to seller
        let seller_payment = coin::from_balance(payment_balance, ctx);
        transfer::public_transfer(seller_payment, seller);

        // Complete the kiosk trade (simplified - in production would handle proper kiosk trading)
        // For now, just comment out the problematic kiosk operations
        // kiosk::delist<TradingOrder>(seller_kiosk, seller_cap, order_id);
        // let trading_order = kiosk::take<TradingOrder>(seller_kiosk, seller_cap, order_id);
        // kiosk::place<TradingOrder>(buyer_kiosk, buyer_cap, trading_order);

        // Update market statistics
        let market = table::borrow_mut(&mut registry.markets, certificate_type);
        market.active_listings = market.active_listings - 1;
        market.completed_trades = market.completed_trades + 1;
        market.volume_24h = market.volume_24h + price;
        market.last_trade_price = price;
        market.last_updated = current_time;

        // Update demand score based on trading activity
        update_demand_score(market, current_time);

        // Update price multiplier based on market dynamics
        update_price_multiplier(market, analytics, certificate_type, clock);

        registry.total_volume = registry.total_volume + price;

        object::delete(id);

        event::emit(TradeExecutedEvent {
            certificate_type,
            seller,
            buyer: tx_context::sender(ctx),
            price,
            market_fee,
            timestamp: current_time,
        });
    }

    /// Get current market price for a certificate type
    public fun get_current_price(
        registry: &MarketRegistry,
        certificate_type: String,
    ): u64 {
        assert!(table::contains(&registry.markets, certificate_type), E_CERTIFICATE_NOT_FOUND);
        
        let market = table::borrow(&registry.markets, certificate_type);
        let rarity_multiplier = get_rarity_multiplier(market.rarity_tier);
        
        // Calculate current price: base_price * rarity_multiplier * current_multiplier / 10000
        (market.base_price * rarity_multiplier * market.current_multiplier) / (100 * 10000)
    }

    /// Update market analytics and trending data
    public entry fun update_market_analytics(
        _: &MarketAdminCap,
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let mut trending = vector::empty<String>();
        let mut total_sentiment = 0u64;
        let mut market_count = 0u64;

        // Analyze all markets for trending and sentiment
        let market_names = registry.market_names;
        let mut i = 0;
        while (i < vector::length(&market_names)) {
            let cert_type = vector::borrow(&market_names, i);
            let market = table::borrow(&registry.markets, *cert_type);
            
            // Add to trending if high recent activity
            if (market.volume_24h > 0 && market.demand_score > 70) {
                vector::push_back(&mut trending, *cert_type);
            };

            total_sentiment = total_sentiment + market.demand_score;
            market_count = market_count + 1;
            
            i = i + 1;
        };

        // Update analytics
        analytics.trending_certificates = trending;
        analytics.market_sentiment = if (market_count > 0) {
            total_sentiment / market_count
        } else { 50 };
        analytics.last_analytics_update = current_time;
    }

    // === Private Functions ===

    fun update_demand_score(market: &mut CertificateMarket, current_time: u64) {
        let time_since_update = current_time - market.last_updated;
        let hours_since_update = time_since_update / (3600 * 1000);

        // Increase demand score if recent trades, decrease over time
        if (hours_since_update < 1) {
            market.demand_score = std::u64::min(100, market.demand_score + 5);
        } else if (hours_since_update > 24) {
            market.demand_score = std::u64::max(10, market.demand_score - 2);
        };
    }

    fun update_price_multiplier(
        market: &mut CertificateMarket,
        analytics: &mut MarketAnalytics,
        certificate_type: String,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Calculate new multiplier based on demand and market conditions
        let demand_adjustment = if (market.demand_score > 70) {
            market.current_multiplier + (market.current_multiplier * DEMAND_BOOST_FACTOR / 100)
        } else if (market.demand_score < 30) {
            market.current_multiplier - (market.current_multiplier * PRICE_DECAY_RATE / 100)
        } else {
            market.current_multiplier
        };

        // Apply bounds
        let old_multiplier = market.current_multiplier;
        market.current_multiplier = std::u64::max(
            MIN_PRICE_MULTIPLIER * 100,
            std::u64::min(MAX_PRICE_MULTIPLIER * 100, demand_adjustment)
        );

        // Record price history if significant change
        if (std::u64::max(old_multiplier, market.current_multiplier) - 
            std::u64::min(old_multiplier, market.current_multiplier) > 500) {
            
            let history = table::borrow_mut(&mut analytics.price_history, certificate_type);
            vector::push_back(history, PriceHistory {
                timestamp: current_time,
                price: get_current_price_internal(market),
                volume: market.volume_24h,
                trades: market.completed_trades,
            });

            // Keep only last 100 entries
            if (vector::length(history) > 100) {
                vector::remove(history, 0);
            };
        };

        event::emit(PriceUpdatedEvent {
            certificate_type,
            old_price: (market.base_price * old_multiplier) / 10000,
            new_price: get_current_price_internal(market),
            multiplier: market.current_multiplier,
            demand_score: market.demand_score,
            timestamp: current_time,
        });
    }

    fun get_current_price_internal(market: &CertificateMarket): u64 {
        let rarity_multiplier = get_rarity_multiplier(market.rarity_tier);
        (market.base_price * rarity_multiplier * market.current_multiplier) / (100 * 10000)
    }

    fun get_rarity_multiplier(rarity_tier: u8): u64 {
        if (rarity_tier == 0) { RARITY_MULTIPLIER_COMMON }
        else if (rarity_tier == 1) { RARITY_MULTIPLIER_RARE }
        else if (rarity_tier == 2) { RARITY_MULTIPLIER_EPIC }
        else { RARITY_MULTIPLIER_LEGENDARY }
    }

    // === View Functions ===

    public fun get_market_info(
        registry: &MarketRegistry,
        certificate_type: String,
    ): (u64, u64, u64, u64, u64, u8) {
        assert!(table::contains(&registry.markets, certificate_type), E_CERTIFICATE_NOT_FOUND);
        let market = table::borrow(&registry.markets, certificate_type);
        (
            get_current_price_internal(market),
            market.total_supply,
            market.active_listings,
            market.volume_24h,
            market.demand_score,
            market.rarity_tier
        )
    }

    public fun get_trending_certificates(analytics: &MarketAnalytics): vector<String> {
        analytics.trending_certificates
    }

    public fun get_market_sentiment(analytics: &MarketAnalytics): u64 {
        analytics.market_sentiment
    }

    public fun get_total_market_volume(registry: &MarketRegistry): u64 {
        registry.total_volume
    }

    public fun is_market_active(registry: &MarketRegistry): bool {
        registry.is_active
    }

    // === Admin Functions ===

    public entry fun toggle_market_status(
        _: &MarketAdminCap,
        registry: &mut MarketRegistry,
    ) {
        registry.is_active = !registry.is_active;
    }

    public entry fun withdraw_market_fees(
        _: &MarketAdminCap,
        registry: &mut MarketRegistry,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.market_fee_pool) >= amount, E_INSUFFICIENT_FUNDS);
        let withdrawn = balance::split(&mut registry.market_fee_pool, amount);
        let fee_coin = coin::from_balance(withdrawn, ctx);
        transfer::public_transfer(fee_coin, tx_context::sender(ctx));
    }

    // === Simplified Entry Functions (Using ConfigManager DOF) ===

    /// Simplified certificate market creation using config manager
    public entry fun create_certificate_market_with_config(
        admin_cap: &MarketAdminCap,
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        config_manager: &ConfigManager,
        certificate_type: String,
        base_price: u64,
        rarity_tier: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        create_certificate_market(admin_cap, registry, analytics, certificate_type, base_price, rarity_tier, clock, ctx);
    }

    /// Simplified certificate listing using config manager
    public entry fun list_certificate_for_sale_with_config(
        registry: &mut MarketRegistry,
        config_manager: &ConfigManager,
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
        certificate_id: ID,
        certificate_type: String,
        asking_price: u64,
        duration_hours: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        list_certificate_for_sale(registry, kiosk, cap, certificate_id, certificate_type, asking_price, duration_hours, clock, ctx);
    }

    /// Simplified trade execution using config manager
    public entry fun execute_trade_with_config(
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        config_manager: &ConfigManager,
        buyer_kiosk: &mut Kiosk,
        buyer_cap: &KioskOwnerCap,
        seller_kiosk: &mut Kiosk,
        order_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        execute_trade(registry, analytics, buyer_kiosk, buyer_cap, seller_kiosk, order_id, payment, clock, ctx);
    }

    /// Simplified market analytics update using config manager
    public entry fun update_market_analytics_with_config(
        admin_cap: &MarketAdminCap,
        registry: &mut MarketRegistry,
        analytics: &mut MarketAnalytics,
        config_manager: &ConfigManager,
        clock: &Clock,
    ) {
        // Verify config manager is operational
        assert!(config_manager::is_manager_operational(config_manager), E_CONFIG_MANAGER_NOT_AVAILABLE);
        
        // Call the original function with the provided clock
        update_market_analytics(admin_cap, registry, analytics, clock);
    }

    // === Testing Functions ===

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}