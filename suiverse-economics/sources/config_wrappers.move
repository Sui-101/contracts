/// Configuration Wrappers Module
/// 
/// Provides type-safe wrapper functions for accessing common configuration objects
/// in the SuiVerse economics package. This module acts as a bridge between the
/// generic ConfigManager and specific module needs, providing convenient access
/// patterns for frequently used configuration objects.
module suiverse_economics::config_wrappers {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    
    // Import other modules for type definitions
    use suiverse_economics::config_manager::{Self, ConfigManager, ConfigManagerAdminCap};
    use suiverse_economics::certificate_market::{Self, MarketRegistry};
    use suiverse_economics::learning_incentives::{Self, IncentiveRegistry};
    use suiverse_economics::dynamic_fees::{Self, FeeRegistry};
    
    // === Constants for Config Keys ===
    const SYSTEM_CLOCK_KEY: vector<u8> = b"SYSTEM_CLOCK";
    const CERTIFICATE_MARKET_REGISTRY_KEY: vector<u8> = b"CERTIFICATE_MARKET_REGISTRY";
    const INCENTIVE_REGISTRY_KEY: vector<u8> = b"INCENTIVE_REGISTRY";
    const FEE_REGISTRY_KEY: vector<u8> = b"FEE_REGISTRY";
    const STAKING_REGISTRY_KEY: vector<u8> = b"STAKING_REGISTRY";
    const VALIDATOR_POOL_KEY: vector<u8> = b"VALIDATOR_POOL";
    const ECONOMICS_HUB_KEY: vector<u8> = b"ECONOMICS_HUB";
    const TREASURY_CAP_KEY: vector<u8> = b"TREASURY_CAP";
    const GOVERNANCE_CONFIG_KEY: vector<u8> = b"GOVERNANCE_CONFIG";
    const UPGRADE_CAP_KEY: vector<u8> = b"UPGRADE_CAP";

    // === Error Codes ===
    const E_CONFIG_NOT_AVAILABLE: u64 = 1;
    const E_CONFIG_TYPE_MISMATCH: u64 = 2;
    const E_REQUIRED_CONFIG_MISSING: u64 = 3;
    const E_CONFIG_ACCESS_FAILED: u64 = 4;

    // === System Clock Functions ===

    /// Get system clock ID (Clock objects cannot be stored in DOF)
    public fun get_clock_id(manager: &ConfigManager): ID {
        assert!(config_manager::has_clock_id(manager), E_REQUIRED_CONFIG_MISSING);
        config_manager::get_clock_id(manager)
    }

    /// Check if system clock ID is available
    public fun has_clock(manager: &ConfigManager): bool {
        config_manager::has_clock_id(manager)
    }

    // Note: get_clock function cannot be implemented because Clock objects
    // cannot be stored in Dynamic Object Fields (they only have 'key' ability, not 'store')
    // All functions requiring Clock should receive it as a parameter instead

    /// Initialize system clock ID configuration
    public entry fun setup_system_clock(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        clock_id: ID,
        ctx: &mut TxContext,
    ) {
        config_manager::add_clock_id(
            admin_cap,
            manager,
            clock_id,
            ctx
        );
    }

    // === Certificate Market Registry Functions ===

    /// Get immutable reference to certificate market registry
    public fun get_certificate_market_registry(manager: &ConfigManager): &MarketRegistry {
        assert!(config_manager::has_config<MarketRegistry>(manager, 
                string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config<MarketRegistry>(
            manager, 
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY)
        )
    }

    /// Get mutable reference to certificate market registry
    public fun get_certificate_market_registry_mut(
        manager: &mut ConfigManager,
        clock: &Clock,
        ctx: &mut TxContext,
    ): &mut MarketRegistry {
        assert!(config_manager::has_config<MarketRegistry>(manager, 
                string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config_mut<MarketRegistry>(
            manager,
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY),
            clock,
            ctx
        )
    }

    /// Check if certificate market registry is available
    public fun has_certificate_market_registry(manager: &ConfigManager): bool {
        config_manager::has_config<MarketRegistry>(
            manager, 
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY)
        )
    }

    /// Setup certificate market registry configuration
    public entry fun setup_certificate_market_registry(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        registry: MarketRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY),
            registry,
            string::utf8(b"Registry for certificate marketplace operations"),
            clock,
            ctx
        );
    }

    // === Incentive Registry Functions ===

    /// Get immutable reference to incentive registry
    public fun get_incentive_registry(manager: &ConfigManager): &IncentiveRegistry {
        assert!(config_manager::has_config<IncentiveRegistry>(manager, 
                string::utf8(INCENTIVE_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config<IncentiveRegistry>(
            manager, 
            string::utf8(INCENTIVE_REGISTRY_KEY)
        )
    }

    /// Get mutable reference to incentive registry
    public fun get_incentive_registry_mut(
        manager: &mut ConfigManager,
        clock: &Clock,
        ctx: &mut TxContext,
    ): &mut IncentiveRegistry {
        assert!(config_manager::has_config<IncentiveRegistry>(manager, 
                string::utf8(INCENTIVE_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config_mut<IncentiveRegistry>(
            manager,
            string::utf8(INCENTIVE_REGISTRY_KEY),
            clock,
            ctx
        )
    }

    /// Check if incentive registry is available
    public fun has_incentive_registry(manager: &ConfigManager): bool {
        config_manager::has_config<IncentiveRegistry>(
            manager, 
            string::utf8(INCENTIVE_REGISTRY_KEY)
        )
    }

    /// Setup incentive registry configuration
    public entry fun setup_incentive_registry(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        registry: IncentiveRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(INCENTIVE_REGISTRY_KEY),
            registry,
            string::utf8(b"Registry for learning incentive management"),
            clock,
            ctx
        );
    }

    // === Fee Registry Functions ===

    /// Get immutable reference to fee registry
    public fun get_fee_registry(manager: &ConfigManager): &FeeRegistry {
        assert!(config_manager::has_config<FeeRegistry>(manager, 
                string::utf8(FEE_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config<FeeRegistry>(
            manager, 
            string::utf8(FEE_REGISTRY_KEY)
        )
    }

    /// Get mutable reference to fee registry
    public fun get_fee_registry_mut(
        manager: &mut ConfigManager,
        clock: &Clock,
        ctx: &mut TxContext,
    ): &mut FeeRegistry {
        assert!(config_manager::has_config<FeeRegistry>(manager, 
                string::utf8(FEE_REGISTRY_KEY)), E_REQUIRED_CONFIG_MISSING);
        config_manager::borrow_config_mut<FeeRegistry>(
            manager,
            string::utf8(FEE_REGISTRY_KEY),
            clock,
            ctx
        )
    }

    /// Check if fee registry is available
    public fun has_fee_registry(manager: &ConfigManager): bool {
        config_manager::has_config<FeeRegistry>(
            manager, 
            string::utf8(FEE_REGISTRY_KEY)
        )
    }

    /// Setup fee registry configuration
    public entry fun setup_fee_registry(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        registry: FeeRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(FEE_REGISTRY_KEY),
            registry,
            string::utf8(b"Registry for dynamic fee management"),
            clock,
            ctx
        );
    }

    // === Staking Registry Functions ===
    // Note: StakingRegistry functions omitted as the type is not yet implemented

    // StakingRegistry setup functions omitted until implementation is available

    // === Batch Configuration Setup ===

    /// Setup essential system configurations in one transaction (without staking registry)
    public entry fun setup_essential_configs(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        clock: &Clock,
        certificate_market_registry: MarketRegistry,
        incentive_registry: IncentiveRegistry,
        fee_registry: FeeRegistry,
        ctx: &mut TxContext,
    ) {
        let clock_ref = clock;
        
        // Setup all essential configurations (Clock storage disabled - not compatible with DOF)
        // config_manager::add_config(
        //     admin_cap,
        //     manager,
        //     string::utf8(SYSTEM_CLOCK_KEY),
        //     clock,
        //     string::utf8(b"System-wide clock for timestamp operations"),
        //     clock_ref,
        //     ctx
        // );

        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY),
            certificate_market_registry,
            string::utf8(b"Registry for certificate marketplace operations"),
            clock_ref,
            ctx
        );

        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(INCENTIVE_REGISTRY_KEY),
            incentive_registry,
            string::utf8(b"Registry for learning incentive management"),
            clock_ref,
            ctx
        );

        config_manager::add_config(
            admin_cap,
            manager,
            string::utf8(FEE_REGISTRY_KEY),
            fee_registry,
            string::utf8(b"Registry for dynamic fee management"),
            clock_ref,
            ctx
        );

        // Staking registry setup omitted until implementation is available
    }

    // === Multi-Registry Access Functions ===

    /// Get available essential registries for economics operations (without staking registry)
    public fun get_all_registries(
        manager: &ConfigManager,
    ): (&MarketRegistry, &IncentiveRegistry, &FeeRegistry) {
        (
            get_certificate_market_registry(manager),
            get_incentive_registry(manager),
            get_fee_registry(manager)
        )
    }

    /// Check if all available essential registries are present
    public fun has_all_essential_registries(manager: &ConfigManager): bool {
        has_clock(manager) &&
        has_certificate_market_registry(manager) &&
        has_incentive_registry(manager) &&
        has_fee_registry(manager)
    }

    /// Get system health based on available configurations
    public fun get_config_health_status(manager: &ConfigManager): (bool, vector<String>) {
        let mut missing_configs = vector::empty<String>();
        let mut all_available = true;

        if (!has_clock(manager)) {
            vector::push_back(&mut missing_configs, string::utf8(SYSTEM_CLOCK_KEY));
            all_available = false;
        };

        if (!has_certificate_market_registry(manager)) {
            vector::push_back(&mut missing_configs, string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY));
            all_available = false;
        };

        if (!has_incentive_registry(manager)) {
            vector::push_back(&mut missing_configs, string::utf8(INCENTIVE_REGISTRY_KEY));
            all_available = false;
        };

        if (!has_fee_registry(manager)) {
            vector::push_back(&mut missing_configs, string::utf8(FEE_REGISTRY_KEY));
            all_available = false;
        };

        // Staking registry check disabled for deployment
        // if (!has_staking_registry(manager)) {
        //     vector::push_back(&mut missing_configs, string::utf8(STAKING_REGISTRY_KEY));
        //     all_available = false;
        // };

        (all_available, missing_configs)
    }

    // === Utility Functions for Configuration Keys ===

    /// Get all standard configuration keys
    public fun get_standard_config_keys(): vector<String> {
        vector[
            string::utf8(SYSTEM_CLOCK_KEY),
            string::utf8(CERTIFICATE_MARKET_REGISTRY_KEY),
            string::utf8(INCENTIVE_REGISTRY_KEY),
            string::utf8(FEE_REGISTRY_KEY),
            string::utf8(STAKING_REGISTRY_KEY),
        ]
    }

    /// Check if a key is a standard configuration key
    public fun is_standard_config_key(key: String): bool {
        let standard_keys = get_standard_config_keys();
        let mut i = 0;
        let len = vector::length(&standard_keys);
        
        while (i < len) {
            if (vector::borrow(&standard_keys, i) == &key) {
                return true
            };
            i = i + 1;
        };
        false
    }

    // === Advanced Access Patterns ===

    // Note: Advanced access patterns with lambda functions are not supported
    // in Move. Users should access registries individually using the getter functions.

    // === Configuration Validation ===

    /// Validate that all required configurations are present and accessible
    public fun validate_configuration_completeness(manager: &ConfigManager): bool {
        // Check if manager is operational
        if (!config_manager::is_manager_operational(manager)) {
            return false
        };

        // Check essential configurations
        let (all_available, _) = get_config_health_status(manager);
        all_available
    }

    /// Get detailed configuration status report
    public fun get_configuration_status_report(
        manager: &ConfigManager
    ): (bool, bool, u64, vector<String>, vector<String>) {
        let (is_initialized, is_paused, total_configs, _) = config_manager::get_manager_health(manager);
        let (all_available, missing_configs) = get_config_health_status(manager);
        let available_configs = config_manager::get_all_config_keys(manager);

        (
            is_initialized && !is_paused,
            all_available,
            total_configs,
            available_configs,
            missing_configs
        )
    }

    // === Testing Utilities ===

    #[test_only]
    public fun setup_test_configurations(
        admin_cap: &ConfigManagerAdminCap,
        manager: &mut ConfigManager,
        ctx: &mut TxContext,
    ) {
        // This would be used in tests to quickly setup a complete configuration environment
        // Implementation would create mock objects for testing
    }

    #[test_only]
    public fun get_test_config_keys(): vector<String> {
        get_standard_config_keys()
    }
}