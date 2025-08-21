/// Dynamic Fee Adjustment Module
/// 
/// Provides intelligent fee optimization based on network demand, usage patterns,
/// and real-time platform metrics. Complements existing static fee structures
/// in assessment, certification, and content modules with adaptive pricing.
module suiverse_economics::dynamic_fees {
    use std::string::{Self, String};
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};

    // === Constants ===
    const BASE_EXAM_FEE: u64 = 5_000_000_000; // 5 SUI base exam fee
    const BASE_CERTIFICATE_FEE: u64 = 100_000_000; // 0.1 SUI base certificate fee
    const BASE_CONTENT_FEE: u64 = 50_000_000; // 0.05 SUI base content fee
    const BASE_VALIDATION_FEE: u64 = 10_000_000; // 0.01 SUI base validation fee
    
    // Static fee amounts from fee_management.move
    const QUIZ_CREATION_DEPOSIT: u64 = 2_000_000_000; // 2 SUI
    const ARTICLE_CREATION_DEPOSIT: u64 = 500_000_000; // 0.5 SUI
    const PROJECT_CREATION_DEPOSIT: u64 = 1_000_000_000; // 1 SUI
    const EXAM_RETRY_FEE: u64 = 3_000_000_000; // 3 SUI
    const SKILL_SEARCH_FEE: u64 = 1_000_000_000; // 1 SUI
    const CONTACT_REQUEST_FEE: u64 = 2_000_000_000; // 2 SUI
    const GOVERNANCE_PROPOSAL_DEPOSIT: u64 = 100_000_000_000; // 100 SUI
    
    const MAX_FEE_MULTIPLIER: u64 = 500; // 5x max fee increase
    const MIN_FEE_MULTIPLIER: u64 = 20; // 0.2x min fee decrease
    const DEMAND_ADJUSTMENT_RATE: u64 = 10; // 10% adjustment per demand level
    const NETWORK_CONGESTION_MULTIPLIER: u64 = 150; // 1.5x during high congestion
    const OFF_PEAK_DISCOUNT: u64 = 80; // 20% discount during off-peak
    const BULK_DISCOUNT_THRESHOLD: u64 = 10; // 10+ operations for bulk pricing
    const BULK_DISCOUNT_RATE: u64 = 85; // 15% bulk discount
    const PREMIUM_USER_DISCOUNT: u64 = 90; // 10% discount for premium users
    const LOYALTY_DISCOUNT_RATE: u64 = 95; // 5% loyalty discount
    const FLASH_SALE_DISCOUNT: u64 = 70; // 30% flash sale discount
    const SURGE_PRICING_THRESHOLD: u64 = 80; // 80% capacity triggers surge pricing

    // === Error Codes ===
    const E_INVALID_FEE_TYPE: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 2;
    const E_INVALID_MULTIPLIER: u64 = 3;
    const E_UNAUTHORIZED_ACCESS: u64 = 4;
    const E_SYSTEM_PAUSED: u64 = 5;
    const E_INVALID_DEMAND_LEVEL: u64 = 6;
    const E_COOLDOWN_ACTIVE: u64 = 7;
    const E_INVALID_TIME_PERIOD: u64 = 8;
    const E_INSUFFICIENT_FUNDS: u64 = 9;

    // === Structs ===

    /// Fee structure for different service types
    public struct FeeStructure has store {
        service_type: String,
        base_fee: u64,
        current_multiplier: u64, // Basis points (10000 = 1x)
        demand_level: u64, // 0-100 current demand
        last_updated: u64,
        total_transactions_24h: u64,
        revenue_24h: u64,
        peak_hour_multiplier: u64,
        off_peak_multiplier: u64,
        surge_pricing_active: bool,
    }

    /// Network utilization metrics
    public struct NetworkMetrics has store {
        current_tps: u64, // Transactions per second
        avg_gas_price: u64,
        network_congestion: u64, // 0-100 percentage
        active_users_24h: u64,
        peak_usage_hours: vector<u64>, // Hours of day (0-23)
        seasonal_demand_factor: u64, // Basis points for seasonal adjustments
        last_metrics_update: u64,
    }

    /// User-specific fee preferences and history
    public struct UserFeeProfile has store {
        user: address,
        tier: u8, // 0=Basic, 1=Premium, 2=VIP
        total_fees_paid: u64,
        transaction_count: u64,
        loyalty_score: u64, // 0-100 based on usage patterns
        bulk_operations_count: u64,
        preferred_payment_method: String,
        fee_sensitivity: u64, // 0-100, affects dynamic adjustments
        last_transaction: u64,
    }

    /// Fee promotion and discount system
    public struct FeePromotion has store {
        promotion_id: String,
        service_types: vector<String>,
        discount_percentage: u64, // Basis points
        start_time: u64,
        end_time: u64,
        max_uses: u64,
        current_uses: u64,
        eligible_tiers: vector<u8>,
        conditions: VecMap<String, u64>, // condition -> threshold
        is_active: bool,
    }

    /// Dynamic fee registry and management
    public struct FeeRegistry has key {
        id: UID,
        fee_structures: Table<String, FeeStructure>,
        network_metrics: NetworkMetrics,
        user_profiles: Table<address, UserFeeProfile>,
        active_promotions: Table<String, FeePromotion>,
        fee_collection_pool: Balance<SUI>,
        emergency_multiplier: u64, // Emergency fee adjustment
        system_active: bool,
        admin_cap: ID,
        last_adjustment: u64,
    }

    /// Fee calculation result with breakdown
    public struct FeeCalculation has drop {
        base_fee: u64,
        demand_adjustment: u64,
        network_adjustment: u64,
        user_discount: u64,
        promotion_discount: u64,
        final_fee: u64,
        fee_breakdown: VecMap<String, u64>,
    }

    /// Admin capability for fee management
    public struct FeeAdminCap has key, store {
        id: UID,
    }

    // === Events ===

    public struct FeeAdjustmentEvent has copy, drop {
        service_type: String,
        old_multiplier: u64,
        new_multiplier: u64,
        demand_level: u64,
        network_congestion: u64,
        adjustment_reason: String,
        timestamp: u64,
    }

    public struct FeePaymentEvent has copy, drop {
        user: address,
        service_type: String,
        base_fee: u64,
        final_fee: u64,
        discounts_applied: u64,
        payment_method: String,
        transaction_id: ID,
        timestamp: u64,
    }

    public struct PromotionActivatedEvent has copy, drop {
        promotion_id: String,
        user: address,
        service_type: String,
        discount_amount: u64,
        remaining_uses: u64,
        timestamp: u64,
    }

    public struct SurgePricingEvent has copy, drop {
        service_type: String,
        demand_level: u64,
        surge_multiplier: u64,
        estimated_duration: u64,
        timestamp: u64,
    }

    // === Initialize Function ===

    fun init(ctx: &mut TxContext) {
        let admin_cap = FeeAdminCap {
            id: object::new(ctx),
        };

        let network_metrics = NetworkMetrics {
            current_tps: 0,
            avg_gas_price: 1000, // Default gas price
            network_congestion: 30, // Low initial congestion
            active_users_24h: 0,
            peak_usage_hours: vector::empty(),
            seasonal_demand_factor: 10000, // 1x seasonal factor
            last_metrics_update: 0,
        };

        let registry = FeeRegistry {
            id: object::new(ctx),
            fee_structures: table::new(ctx),
            network_metrics,
            user_profiles: table::new(ctx),
            active_promotions: table::new(ctx),
            fee_collection_pool: balance::zero(),
            emergency_multiplier: 10000, // 1x emergency multiplier
            system_active: true,
            admin_cap: object::id(&admin_cap),
            last_adjustment: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry);
    }

    // === Core Fee Functions ===

    /// Calculate dynamic fee for a service with full optimization
    public fun calculate_dynamic_fee(
        registry: &FeeRegistry,
        service_type: String,
        user: address,
        bulk_count: u64,
        clock: &Clock,
    ): FeeCalculation {
        assert!(registry.system_active, E_SYSTEM_PAUSED);
        assert!(table::contains(&registry.fee_structures, service_type), E_INVALID_FEE_TYPE);

        let fee_structure = table::borrow(&registry.fee_structures, service_type);
        let current_time = clock::timestamp_ms(clock);
        let mut breakdown = vec_map::empty<String, u64>();

        // Base fee calculation
        let base_fee = fee_structure.base_fee;
        vec_map::insert(&mut breakdown, string::utf8(b"base_fee"), base_fee);

        // Demand-based adjustment
        let demand_adjustment = calculate_demand_adjustment(fee_structure);
        vec_map::insert(&mut breakdown, string::utf8(b"demand_adjustment"), demand_adjustment);

        // Network congestion adjustment
        let network_adjustment = calculate_network_adjustment(&registry.network_metrics, base_fee);
        vec_map::insert(&mut breakdown, string::utf8(b"network_adjustment"), network_adjustment);

        // Time-based adjustment (peak/off-peak)
        let time_adjustment = calculate_time_adjustment(fee_structure, current_time);
        vec_map::insert(&mut breakdown, string::utf8(b"time_adjustment"), time_adjustment);

        // User-specific discounts
        let user_discount = calculate_user_discount(registry, user, base_fee);
        vec_map::insert(&mut breakdown, string::utf8(b"user_discount"), user_discount);

        // Bulk operation discount
        let bulk_discount = calculate_bulk_discount(base_fee, bulk_count);
        vec_map::insert(&mut breakdown, string::utf8(b"bulk_discount"), bulk_discount);

        // Promotion discounts
        let promotion_discount = calculate_promotion_discount(registry, service_type, user, base_fee);
        vec_map::insert(&mut breakdown, string::utf8(b"promotion_discount"), promotion_discount);

        // Emergency adjustment
        let emergency_adjustment = (base_fee * registry.emergency_multiplier) / 10000;
        vec_map::insert(&mut breakdown, string::utf8(b"emergency_adjustment"), emergency_adjustment);

        // Calculate final fee
        let adjusted_fee = base_fee + demand_adjustment + network_adjustment + time_adjustment + emergency_adjustment;
        let total_discounts = user_discount + bulk_discount + promotion_discount;
        let final_fee = if (adjusted_fee > total_discounts) {
            adjusted_fee - total_discounts
        } else {
            base_fee / 10 // Minimum 10% of base fee
        };

        FeeCalculation {
            base_fee,
            demand_adjustment,
            network_adjustment,
            user_discount,
            promotion_discount,
            final_fee,
            fee_breakdown: breakdown,
        }
    }

    /// Process fee payment with dynamic pricing
    public entry fun process_fee_payment(
        registry: &mut FeeRegistry,
        service_type: String,
        bulk_count: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let user = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Calculate required fee
        let fee_calc = calculate_dynamic_fee(registry, service_type, user, bulk_count, clock);
        let payment_amount = coin::value(&payment);
        
        assert!(payment_amount >= fee_calc.final_fee, E_INSUFFICIENT_PAYMENT);

        // Process payment
        let mut payment_balance = coin::into_balance(payment);
        let fee_balance = balance::split(&mut payment_balance, fee_calc.final_fee);
        balance::join(&mut registry.fee_collection_pool, fee_balance);

        // Return change if any
        let change = coin::from_balance(payment_balance, ctx);

        // Update user profile
        update_user_profile(registry, user, fee_calc.final_fee, current_time);

        // Update fee structure metrics
        update_fee_structure_metrics(registry, service_type, fee_calc.final_fee, current_time);

        // Return change to user if any
        if (coin::value(&change) > 0) {
            transfer::public_transfer(change, user);
        } else {
            coin::destroy_zero(change);
        };

        // Emit payment event
        event::emit(FeePaymentEvent {
            user,
            service_type,
            base_fee: fee_calc.base_fee,
            final_fee: fee_calc.final_fee,
            discounts_applied: fee_calc.user_discount + fee_calc.promotion_discount,
            payment_method: string::utf8(b"SUI"),
            transaction_id: {
                let uid = object::new(ctx);
                let id = object::uid_to_inner(&uid);
                object::delete(uid);
                id
            },
            timestamp: current_time,
        });
    }

    /// Update network metrics for dynamic fee adjustments
    public entry fun update_network_metrics(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
        current_tps: u64,
        avg_gas_price: u64,
        network_congestion: u64,
        active_users_24h: u64,
        clock: &Clock,
    ) {
        assert!(network_congestion <= 100, E_INVALID_DEMAND_LEVEL);

        let current_time = clock::timestamp_ms(clock);
        let metrics = &mut registry.network_metrics;

        metrics.current_tps = current_tps;
        metrics.avg_gas_price = avg_gas_price;
        metrics.network_congestion = network_congestion;
        metrics.active_users_24h = active_users_24h;
        metrics.last_metrics_update = current_time;

        // Trigger automatic fee adjustments if needed
        if (network_congestion > SURGE_PRICING_THRESHOLD) {
            activate_surge_pricing(registry, clock);
        };
    }

    /// Create fee promotion with conditions
    public entry fun create_fee_promotion(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
        promotion_id: String,
        service_types: vector<String>,
        discount_percentage: u64,
        duration_hours: u64,
        max_uses: u64,
        eligible_tiers: vector<u8>,
        clock: &Clock,
    ) {
        assert!(discount_percentage <= 9000, E_INVALID_MULTIPLIER); // Max 90% discount

        let current_time = clock::timestamp_ms(clock);
        let end_time = current_time + (duration_hours * 3600 * 1000);

        let promotion = FeePromotion {
            promotion_id,
            service_types,
            discount_percentage,
            start_time: current_time,
            end_time,
            max_uses,
            current_uses: 0,
            eligible_tiers,
            conditions: vec_map::empty(),
            is_active: true,
        };

        table::add(&mut registry.active_promotions, promotion_id, promotion);
    }

    // === Private Helper Functions ===

    fun calculate_demand_adjustment(fee_structure: &FeeStructure): u64 {
        let demand_factor = fee_structure.demand_level;
        if (demand_factor > 70) {
            // High demand - increase fee
            (fee_structure.base_fee * DEMAND_ADJUSTMENT_RATE * (demand_factor - 50)) / (100 * 100)
        } else if (demand_factor < 30) {
            // Low demand - no additional charge
            0
        } else {
            // Normal demand - slight increase
            (fee_structure.base_fee * DEMAND_ADJUSTMENT_RATE * (demand_factor - 30)) / (100 * 100)
        }
    }

    fun calculate_network_adjustment(metrics: &NetworkMetrics, base_fee: u64): u64 {
        if (metrics.network_congestion > 60) {
            (base_fee * NETWORK_CONGESTION_MULTIPLIER - base_fee) / 100
        } else {
            0
        }
    }

    fun calculate_time_adjustment(fee_structure: &FeeStructure, current_time: u64): u64 {
        let hour_of_day = ((current_time / (3600 * 1000)) % 24);
        
        // Peak hours: 8-10 AM, 2-4 PM, 7-9 PM (UTC)
        let is_peak = (hour_of_day >= 8 && hour_of_day <= 10) ||
                     (hour_of_day >= 14 && hour_of_day <= 16) ||
                     (hour_of_day >= 19 && hour_of_day <= 21);

        if (is_peak) {
            (fee_structure.base_fee * fee_structure.peak_hour_multiplier - fee_structure.base_fee) / 10000
        } else {
            // Off-peak discount
            let discount = (fee_structure.base_fee * (10000 - OFF_PEAK_DISCOUNT)) / 10000;
            fee_structure.base_fee - discount
        }
    }

    fun calculate_user_discount(registry: &FeeRegistry, user: address, base_fee: u64): u64 {
        if (!table::contains(&registry.user_profiles, user)) {
            return 0
        };

        let profile = table::borrow(&registry.user_profiles, user);
        let mut discount = 0u64;

        // Tier-based discount
        if (profile.tier == 1) { // Premium
            discount = discount + (base_fee * (10000 - PREMIUM_USER_DISCOUNT) / 10000);
        } else if (profile.tier == 2) { // VIP
            discount = discount + (base_fee * (10000 - PREMIUM_USER_DISCOUNT + 50) / 10000);
        };

        // Loyalty discount
        if (profile.loyalty_score > 80) {
            discount = discount + (base_fee * (10000 - LOYALTY_DISCOUNT_RATE) / 10000);
        };

        discount
    }

    fun calculate_bulk_discount(base_fee: u64, bulk_count: u64): u64 {
        if (bulk_count >= BULK_DISCOUNT_THRESHOLD) {
            (base_fee * bulk_count * (10000 - BULK_DISCOUNT_RATE)) / 10000
        } else {
            0
        }
    }

    fun calculate_promotion_discount(
        registry: &FeeRegistry,
        service_type: String,
        user: address,
        base_fee: u64
    ): u64 {
        // Simplified implementation - promotion system disabled for now
        // In production, this would use a vector or other iterable structure
        let _ = registry;
        let _ = service_type;
        let _ = user;
        let _ = base_fee;
        0
    }

    fun update_user_profile(
        registry: &mut FeeRegistry,
        user: address,
        fee_paid: u64,
        current_time: u64,
    ) {
        if (!table::contains(&registry.user_profiles, user)) {
            let new_profile = UserFeeProfile {
                user,
                tier: 0, // Basic tier
                total_fees_paid: 0,
                transaction_count: 0,
                loyalty_score: 50, // Start with neutral loyalty
                bulk_operations_count: 0,
                preferred_payment_method: string::utf8(b"SUI"),
                fee_sensitivity: 50, // Average sensitivity
                last_transaction: 0,
            };
            table::add(&mut registry.user_profiles, user, new_profile);
        };

        let profile = table::borrow_mut(&mut registry.user_profiles, user);
        profile.total_fees_paid = profile.total_fees_paid + fee_paid;
        profile.transaction_count = profile.transaction_count + 1;
        profile.last_transaction = current_time;

        // Update loyalty score based on usage frequency
        let days_since_last = (current_time - profile.last_transaction) / (24 * 3600 * 1000);
        if (days_since_last <= 7) { // Regular user
            profile.loyalty_score = std::u64::min(100, profile.loyalty_score + 1);
        } else if (days_since_last > 30) { // Inactive user
            profile.loyalty_score = std::u64::max(10, profile.loyalty_score - 2);
        };

        // Auto-upgrade tier based on usage
        if (profile.total_fees_paid > 100_000_000_000 && profile.tier == 0) { // 100 SUI
            profile.tier = 1; // Premium
        } else if (profile.total_fees_paid > 500_000_000_000 && profile.tier == 1) { // 500 SUI
            profile.tier = 2; // VIP
        };
    }

    fun update_fee_structure_metrics(
        registry: &mut FeeRegistry,
        service_type: String,
        fee_paid: u64,
        current_time: u64,
    ) {
        let fee_structure = table::borrow_mut(&mut registry.fee_structures, service_type);
        fee_structure.total_transactions_24h = fee_structure.total_transactions_24h + 1;
        fee_structure.revenue_24h = fee_structure.revenue_24h + fee_paid;
        fee_structure.last_updated = current_time;

        // Update demand level based on transaction frequency
        let hours_since_update = (current_time - fee_structure.last_updated) / (3600 * 1000);
        if (hours_since_update <= 1 && fee_structure.total_transactions_24h > 100) {
            fee_structure.demand_level = std::u64::min(100, fee_structure.demand_level + 5);
        } else if (hours_since_update > 6 && fee_structure.total_transactions_24h < 10) {
            fee_structure.demand_level = std::u64::max(10, fee_structure.demand_level - 3);
        };
    }

    fun activate_surge_pricing(registry: &mut FeeRegistry, clock: &Clock) {
        let current_time = clock::timestamp_ms(clock);
        
        // Since table::keys doesn't exist, we'll use a predefined list of service types
        let service_types = vector[
            string::utf8(b"quiz_creation"),
            string::utf8(b"exam_attempt"),
            string::utf8(b"certificate_issuance"),
            string::utf8(b"validation_review"),
            string::utf8(b"content_sharing")
        ];

        let mut i = 0;
        while (i < vector::length(&service_types)) {
            let service_type = vector::borrow(&service_types, i);
            if (table::contains(&registry.fee_structures, *service_type)) {
                let fee_structure = table::borrow_mut(&mut registry.fee_structures, *service_type);
            
                if (!fee_structure.surge_pricing_active) {
                    fee_structure.surge_pricing_active = true;
                    fee_structure.current_multiplier = std::u64::min(
                        MAX_FEE_MULTIPLIER * 100,
                        fee_structure.current_multiplier * 150 / 100
                    );

                    event::emit(SurgePricingEvent {
                        service_type: *service_type,
                        demand_level: fee_structure.demand_level,
                        surge_multiplier: fee_structure.current_multiplier,
                        estimated_duration: 3600 * 1000, // 1 hour estimated
                        timestamp: current_time,
                    });
                };
            };

            i = i + 1;
        };
    }

    // === View Functions ===

    public fun get_current_fee_structure(
        registry: &FeeRegistry,
        service_type: String,
    ): (u64, u64, u64, bool) {
        assert!(table::contains(&registry.fee_structures, service_type), E_INVALID_FEE_TYPE);
        let structure = table::borrow(&registry.fee_structures, service_type);
        (
            structure.base_fee,
            structure.current_multiplier,
            structure.demand_level,
            structure.surge_pricing_active
        )
    }

    public fun get_user_tier_and_loyalty(
        registry: &FeeRegistry,
        user: address,
    ): (u8, u64, u64) {
        if (!table::contains(&registry.user_profiles, user)) {
            return (0, 0, 50)
        };

        let profile = table::borrow(&registry.user_profiles, user);
        (profile.tier, profile.total_fees_paid, profile.loyalty_score)
    }

    public fun get_network_metrics(registry: &FeeRegistry): (u64, u64, u64, u64) {
        (
            registry.network_metrics.current_tps,
            registry.network_metrics.avg_gas_price,
            registry.network_metrics.network_congestion,
            registry.network_metrics.active_users_24h
        )
    }

    public fun get_total_fee_revenue(registry: &FeeRegistry): u64 {
        balance::value(&registry.fee_collection_pool)
    }

    // === Admin Functions ===

    public entry fun initialize_fee_structure(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
        service_type: String,
        base_fee: u64,
        clock: &Clock,
    ) {
        let structure = FeeStructure {
            service_type,
            base_fee,
            current_multiplier: 10000, // 1x multiplier
            demand_level: 50, // Neutral demand
            last_updated: clock::timestamp_ms(clock),
            total_transactions_24h: 0,
            revenue_24h: 0,
            peak_hour_multiplier: 11000, // 1.1x during peak
            off_peak_multiplier: 9000, // 0.9x during off-peak
            surge_pricing_active: false,
        };

        table::add(&mut registry.fee_structures, service_type, structure);
    }

    public entry fun adjust_emergency_multiplier(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
        new_multiplier: u64,
    ) {
        assert!(new_multiplier >= MIN_FEE_MULTIPLIER * 100 && 
                new_multiplier <= MAX_FEE_MULTIPLIER * 100, E_INVALID_MULTIPLIER);
        
        registry.emergency_multiplier = new_multiplier;
    }

    public entry fun withdraw_fee_revenue(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&registry.fee_collection_pool) >= amount, E_INSUFFICIENT_FUNDS);
        let withdrawn = balance::split(&mut registry.fee_collection_pool, amount);
        let revenue_coin = coin::from_balance(withdrawn, ctx);
        transfer::public_transfer(revenue_coin, tx_context::sender(ctx));
    }

    public entry fun toggle_system_status(
        _: &FeeAdminCap,
        registry: &mut FeeRegistry,
    ) {
        registry.system_active = !registry.system_active;
    }
}