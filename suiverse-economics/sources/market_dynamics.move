module suiverse_economics::market_dynamics {
    use std::string::{Self, String};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::math;
    use sui::transfer;

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_CERTIFICATE_NOT_FOUND: u64 = 2;
    const E_INVALID_MULTIPLIER: u64 = 3;
    const E_REBALANCE_TOO_FREQUENT: u64 = 4;
    const E_INVALID_VALUE: u64 = 5;
    const E_EPOCH_NOT_READY: u64 = 6;

    // Market constants
    const MONTH_IN_MS: u64 = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds
    const REBALANCE_INTERVAL_MS: u64 = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
    const MAX_VALUE_CHANGE_PERCENTAGE: u64 = 20; // Maximum 20% change per rebalance
    const MIN_CERTIFICATE_VALUE: u64 = 10; // Minimum value to prevent certificates becoming worthless
    const MAX_CERTIFICATE_VALUE: u64 = 10000; // Maximum value cap

    // Market factors
    const SCARCITY_WEIGHT: u64 = 30; // 30% weight for scarcity
    const DIFFICULTY_WEIGHT: u64 = 25; // 25% weight for difficulty
    const AGE_DECAY_WEIGHT: u64 = 20; // 20% weight for age decay
    const DEMAND_WEIGHT: u64 = 25; // 25% weight for demand

    // Admin capability
    public struct AdminCap has key {
        id: UID,
    }

    // Market configuration
    public struct MarketConfig has key {
        id: UID,
        rebalance_interval_ms: u64,
        max_value_change_percentage: u64,
        scarcity_weight: u64,
        difficulty_weight: u64,
        age_decay_weight: u64,
        demand_weight: u64,
        min_certificate_value: u64,
        max_certificate_value: u64,
        age_decay_rate_monthly: u64, // Percentage decay per month (e.g., 5 = 5%)
        last_governance_update: ID,
    }

    // Dynamic certificate value tracking
    public struct CertificateMarketData has key, store {
        id: UID,
        certificate_type: String,
        base_value: u64,
        current_value: u64,
        
        // Supply metrics
        total_issued: u64,
        active_holders: u64,
        validator_holders: u64,
        
        // Demand metrics
        recent_exam_attempts: u64,
        recent_pass_rate: u64, // Out of 10000 (100.00%)
        recent_acquisition_count: u64,
        
        // Market factors
        scarcity_multiplier: u64,
        difficulty_multiplier: u64,
        age_decay_factor: u64,
        demand_multiplier: u64,
        
        // Timestamps
        created_at: u64,
        last_rebalance: u64,
        last_acquisition: u64,
        
        // Historical tracking
        value_history: vector<ValueSnapshot>,
        max_historical_value: u64,
        min_historical_value: u64,
    }

    // Value snapshot for historical tracking
    public struct ValueSnapshot has store, drop {
        timestamp: u64,
        value: u64,
        total_issued: u64,
        pass_rate: u64,
        scarcity_factor: u64,
        difficulty_factor: u64,
    }

    // Certificate acquisition record
    public struct CertificateAcquisition has key, store {
        id: UID,
        certificate_type: String,
        holder: address,
        acquisition_timestamp: u64,
        exam_score: u64,
        retry_count: u64,
        market_value_at_acquisition: u64,
    }

    // Market rebalancing event
    public struct MarketRebalanceEvent has copy, drop {
        certificate_type: String,
        old_value: u64,
        new_value: u64,
        scarcity_factor: u64,
        difficulty_factor: u64,
        age_decay_factor: u64,
        demand_factor: u64,
        timestamp: u64,
    }

    // Certificate value updated event
    public struct CertificateValueUpdatedEvent has copy, drop {
        certificate_type: String,
        old_value: u64,
        new_value: u64,
        holder_count: u64,
        timestamp: u64,
    }

    // Market trend analysis event
    public struct MarketTrendAnalysisEvent has copy, drop {
        certificate_type: String,
        trend_direction: u8, // 1: Up, 2: Down, 3: Stable
        price_volatility: u64,
        supply_trend: u8,
        demand_trend: u8,
        analysis_timestamp: u64,
    }

    // Global market state
    public struct MarketState has key {
        id: UID,
        total_certificates: u64,
        total_market_cap: u64,
        average_certificate_value: u64,
        most_valuable_certificate: String,
        least_valuable_certificate: String,
        market_volatility_index: u64,
        last_global_analysis: u64,
    }

    // Initialize the market dynamics system
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        let market_config = MarketConfig {
            id: object::new(ctx),
            rebalance_interval_ms: REBALANCE_INTERVAL_MS,
            max_value_change_percentage: MAX_VALUE_CHANGE_PERCENTAGE,
            scarcity_weight: SCARCITY_WEIGHT,
            difficulty_weight: DIFFICULTY_WEIGHT,
            age_decay_weight: AGE_DECAY_WEIGHT,
            demand_weight: DEMAND_WEIGHT,
            min_certificate_value: MIN_CERTIFICATE_VALUE,
            max_certificate_value: MAX_CERTIFICATE_VALUE,
            age_decay_rate_monthly: 5, // 5% decay per month
            last_governance_update: object::id_from_address(@0x0),
        };

        let market_state = MarketState {
            id: object::new(ctx),
            total_certificates: 0,
            total_market_cap: 0,
            average_certificate_value: 0,
            most_valuable_certificate: string::utf8(b""),
            least_valuable_certificate: string::utf8(b""),
            market_volatility_index: 0,
            last_global_analysis: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(market_config);
        transfer::share_object(market_state);
    }

    // Create new certificate market data
    public fun create_certificate_market_data(
        certificate_type: String,
        base_value: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): CertificateMarketData {
        let current_time = clock::timestamp_ms(clock);
        
        CertificateMarketData {
            id: object::new(ctx),
            certificate_type,
            base_value,
            current_value: base_value,
            total_issued: 0,
            active_holders: 0,
            validator_holders: 0,
            recent_exam_attempts: 0,
            recent_pass_rate: 5000, // Start with 50% pass rate
            recent_acquisition_count: 0,
            scarcity_multiplier: 10000, // 100% (no adjustment)
            difficulty_multiplier: 10000, // 100% (no adjustment)
            age_decay_factor: 10000, // 100% (no decay initially)
            demand_multiplier: 10000, // 100% (no adjustment)
            created_at: current_time,
            last_rebalance: current_time,
            last_acquisition: 0,
            value_history: vector::empty(),
            max_historical_value: base_value,
            min_historical_value: base_value,
        }
    }

    // Record certificate acquisition
    public fun record_certificate_acquisition(
        market_data: &mut CertificateMarketData,
        holder: address,
        exam_score: u64,
        retry_count: u64,
        is_validator: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ): CertificateAcquisition {
        let current_time = clock::timestamp_ms(clock);
        
        // Update market data
        market_data.total_issued = market_data.total_issued + 1;
        market_data.active_holders = market_data.active_holders + 1;
        market_data.recent_acquisition_count = market_data.recent_acquisition_count + 1;
        market_data.last_acquisition = current_time;
        
        if (is_validator) {
            market_data.validator_holders = market_data.validator_holders + 1;
        };
        
        let acquisition = CertificateAcquisition {
            id: object::new(ctx),
            certificate_type: market_data.certificate_type,
            holder,
            acquisition_timestamp: current_time,
            exam_score,
            retry_count,
            market_value_at_acquisition: market_data.current_value,
        };
        
        acquisition
    }

    // Update exam statistics
    public fun update_exam_statistics(
        market_data: &mut CertificateMarketData,
        exam_attempts: u64,
        pass_rate: u64,
    ) {
        market_data.recent_exam_attempts = exam_attempts;
        market_data.recent_pass_rate = pass_rate;
    }

    // Rebalance certificate values based on market dynamics
    public fun rebalance_certificate_value(
        config: &MarketConfig,
        market_data: &mut CertificateMarketData,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if enough time has passed since last rebalance
        assert!(
            current_time >= market_data.last_rebalance + config.rebalance_interval_ms,
            E_REBALANCE_TOO_FREQUENT
        );
        
        let old_value = market_data.current_value;
        
        // Calculate market factors
        let scarcity_factor = calculate_scarcity_factor(market_data);
        let difficulty_factor = calculate_difficulty_factor(market_data);
        let age_decay_factor = calculate_age_decay_factor(config, market_data, current_time);
        let demand_factor = calculate_demand_factor(market_data, current_time);
        
        // Update individual factors
        market_data.scarcity_multiplier = scarcity_factor;
        market_data.difficulty_multiplier = difficulty_factor;
        market_data.age_decay_factor = age_decay_factor;
        market_data.demand_multiplier = demand_factor;
        
        // Calculate weighted new value
        let weighted_value = calculate_weighted_value(
            config,
            market_data.base_value,
            scarcity_factor,
            difficulty_factor,
            age_decay_factor,
            demand_factor
        );
        
        // Apply maximum change limit
        let max_change = (old_value * config.max_value_change_percentage) / 100;
        let new_value = if (weighted_value > old_value) {
            std::u64::min(weighted_value, old_value + max_change)
        } else if (weighted_value < old_value) {
            std::u64::max(weighted_value, old_value - max_change)
        } else {
            weighted_value
        };
        
        // Apply min/max bounds
        market_data.current_value = std::u64::max(
            config.min_certificate_value,
            std::u64::min(new_value, config.max_certificate_value)
        );
        
        // Update historical tracking
        market_data.max_historical_value = std::u64::max(
            market_data.max_historical_value,
            market_data.current_value
        );
        market_data.min_historical_value = std::u64::min(
            market_data.min_historical_value,
            market_data.current_value
        );
        
        // Record value snapshot
        let snapshot = ValueSnapshot {
            timestamp: current_time,
            value: market_data.current_value,
            total_issued: market_data.total_issued,
            pass_rate: market_data.recent_pass_rate,
            scarcity_factor,
            difficulty_factor,
        };
        
        vector::push_back(&mut market_data.value_history, snapshot);
        
        // Keep only last 100 snapshots to prevent unbounded growth
        if (vector::length(&market_data.value_history) > 100) {
            vector::remove(&mut market_data.value_history, 0);
        };
        
        market_data.last_rebalance = current_time;
        
        // Emit rebalancing event
        event::emit(MarketRebalanceEvent {
            certificate_type: market_data.certificate_type,
            old_value,
            new_value: market_data.current_value,
            scarcity_factor,
            difficulty_factor,
            age_decay_factor,
            demand_factor,
            timestamp: current_time,
        });
    }

    // Calculate scarcity factor (fewer holders = higher value)
    fun calculate_scarcity_factor(market_data: &CertificateMarketData): u64 {
        if (market_data.validator_holders == 0) {
            return 15000 // 150% multiplier for very rare certificates
        };
        
        // Inverse relationship: fewer validators holding = higher multiplier
        let scarcity_score = 10000 / (market_data.validator_holders + 1);
        
        // Scale to reasonable range (50% to 150%)
        let factor = 5000 + std::u64::min(scarcity_score * 10, 10000);
        factor
    }

    // Calculate difficulty factor (lower pass rate = higher value)
    fun calculate_difficulty_factor(market_data: &CertificateMarketData): u64 {
        let pass_rate = market_data.recent_pass_rate;
        
        if (pass_rate == 0) {
            return 15000 // 150% for impossible to pass
        };
        
        // Inverse relationship: lower pass rate = higher value
        // Pass rate is out of 10000, so we invert it
        let difficulty_score = 10000 - pass_rate;
        
        // Scale to range (75% to 125%)
        let factor = 7500 + (difficulty_score * 5000) / 10000;
        factor
    }

    // Calculate age decay factor
    fun calculate_age_decay_factor(
        config: &MarketConfig,
        market_data: &CertificateMarketData,
        current_time: u64
    ): u64 {
        let age_in_ms = current_time - market_data.created_at;
        let months_old = age_in_ms / MONTH_IN_MS;
        
        // Apply monthly decay rate
        let total_decay_percentage = months_old * config.age_decay_rate_monthly;
        
        // Cap maximum decay at 50%
        let capped_decay = std::u64::min(total_decay_percentage, 50);
        
        // Return factor (100% - decay_percentage)
        10000 - (capped_decay * 100)
    }

    // Calculate demand factor based on recent acquisition activity
    fun calculate_demand_factor(market_data: &CertificateMarketData, current_time: u64): u64 {
        // If no recent acquisitions, neutral factor
        if (market_data.last_acquisition == 0 || market_data.recent_acquisition_count == 0) {
            return 10000
        };
        
        let time_since_last = current_time - market_data.last_acquisition;
        let days_since = time_since_last / (24 * 60 * 60 * 1000);
        
        // High recent activity = higher demand = higher value
        let acquisition_velocity = market_data.recent_acquisition_count;
        
        if (days_since <= 7 && acquisition_velocity >= 5) {
            12000 // 120% for high demand
        } else if (days_since <= 14 && acquisition_velocity >= 3) {
            11000 // 110% for moderate demand
        } else if (days_since <= 30 && acquisition_velocity >= 1) {
            10000 // 100% for normal demand
        } else {
            9000  // 90% for low demand
        }
    }

    // Calculate weighted value based on all factors
    fun calculate_weighted_value(
        config: &MarketConfig,
        base_value: u64,
        scarcity_factor: u64,
        difficulty_factor: u64,
        age_decay_factor: u64,
        demand_factor: u64
    ): u64 {
        // Calculate weighted average of all factors
        let weighted_multiplier = (
            (scarcity_factor * config.scarcity_weight) +
            (difficulty_factor * config.difficulty_weight) +
            (age_decay_factor * config.age_decay_weight) +
            (demand_factor * config.demand_weight)
        ) / 100;
        
        // Apply to base value
        (base_value * weighted_multiplier) / 10000
    }

    // Perform global market analysis
    public fun analyze_global_market(
        market_state: &mut MarketState,
        certificate_market_data: &vector<CertificateMarketData>,
        clock: &Clock,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let total_certificates = vector::length(certificate_market_data);
        
        let mut total_market_cap = 0u64;
        let mut max_value = 0u64;
        let mut min_value = MAX_CERTIFICATE_VALUE;
        let mut most_valuable = string::utf8(b"");
        let mut least_valuable = string::utf8(b"");
        let mut volatility_sum = 0u64;
        
        let mut i = 0;
        while (i < total_certificates) {
            let market_data = vector::borrow(certificate_market_data, i);
            let cert_market_cap = market_data.current_value * market_data.total_issued;
            total_market_cap = total_market_cap + cert_market_cap;
            
            // Track most/least valuable
            if (market_data.current_value > max_value) {
                max_value = market_data.current_value;
                most_valuable = market_data.certificate_type;
            };
            
            if (market_data.current_value < min_value) {
                min_value = market_data.current_value;
                least_valuable = market_data.certificate_type;
            };
            
            // Calculate volatility (difference between max and min historical values)
            let cert_volatility = if (market_data.min_historical_value > 0) {
                ((market_data.max_historical_value - market_data.min_historical_value) * 100) / 
                market_data.min_historical_value
            } else {
                0
            };
            volatility_sum = volatility_sum + cert_volatility;
            
            i = i + 1;
        };
        
        // Update market state
        market_state.total_certificates = total_certificates;
        market_state.total_market_cap = total_market_cap;
        market_state.average_certificate_value = if (total_certificates > 0) {
            total_market_cap / total_certificates
        } else {
            0
        };
        market_state.most_valuable_certificate = most_valuable;
        market_state.least_valuable_certificate = least_valuable;
        market_state.market_volatility_index = if (total_certificates > 0) {
            volatility_sum / total_certificates
        } else {
            0
        };
        market_state.last_global_analysis = current_time;
    }

    // Update market configuration (governance only)
    public fun update_market_config(
        _: &AdminCap,
        config: &mut MarketConfig,
        new_rebalance_interval: u64,
        new_max_change_percentage: u64,
        new_weights: vector<u64>, // [scarcity, difficulty, age_decay, demand]
        new_decay_rate: u64,
        proposal_id: ID,
    ) {
        config.rebalance_interval_ms = new_rebalance_interval;
        config.max_value_change_percentage = new_max_change_percentage;
        config.age_decay_rate_monthly = new_decay_rate;
        
        if (vector::length(&new_weights) >= 4) {
            config.scarcity_weight = *vector::borrow(&new_weights, 0);
            config.difficulty_weight = *vector::borrow(&new_weights, 1);
            config.age_decay_weight = *vector::borrow(&new_weights, 2);
            config.demand_weight = *vector::borrow(&new_weights, 3);
        };
        
        config.last_governance_update = proposal_id;
    }

    // Getter functions
    public fun get_certificate_current_value(market_data: &CertificateMarketData): u64 {
        market_data.current_value
    }

    public fun get_certificate_base_value(market_data: &CertificateMarketData): u64 {
        market_data.base_value
    }

    public fun get_certificate_total_issued(market_data: &CertificateMarketData): u64 {
        market_data.total_issued
    }

    public fun get_certificate_validator_holders(market_data: &CertificateMarketData): u64 {
        market_data.validator_holders
    }

    public fun get_certificate_pass_rate(market_data: &CertificateMarketData): u64 {
        market_data.recent_pass_rate
    }

    public fun get_market_factors(market_data: &CertificateMarketData): (u64, u64, u64, u64) {
        (
            market_data.scarcity_multiplier,
            market_data.difficulty_multiplier,
            market_data.age_decay_factor,
            market_data.demand_multiplier
        )
    }

    public fun get_global_market_cap(market_state: &MarketState): u64 {
        market_state.total_market_cap
    }

    public fun get_average_certificate_value(market_state: &MarketState): u64 {
        market_state.average_certificate_value
    }

    public fun get_market_volatility_index(market_state: &MarketState): u64 {
        market_state.market_volatility_index
    }

    public fun get_most_valuable_certificate(market_state: &MarketState): String {
        market_state.most_valuable_certificate
    }

    public fun get_value_history_length(market_data: &CertificateMarketData): u64 {
        vector::length(&market_data.value_history)
    }

    // Test functions
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_test_market_data(
        certificate_type: String,
        base_value: u64,
        ctx: &mut TxContext
    ): CertificateMarketData {
        CertificateMarketData {
            id: object::new(ctx),
            certificate_type,
            base_value,
            current_value: base_value,
            total_issued: 0,
            active_holders: 0,
            validator_holders: 0,
            recent_exam_attempts: 0,
            recent_pass_rate: 5000,
            recent_acquisition_count: 0,
            scarcity_multiplier: 10000,
            difficulty_multiplier: 10000,
            age_decay_factor: 10000,
            demand_multiplier: 10000,
            created_at: 0,
            last_rebalance: 0,
            last_acquisition: 0,
            value_history: vector::empty(),
            max_historical_value: base_value,
            min_historical_value: base_value,
        }
    }
}