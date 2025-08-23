/// Simple Certificate Interface using DOF Config Management
/// Demonstrates the core concept with simplified implementation
module suiverse_certificate::simple_interface {
    use std::string::{Self as string, String};
    use sui::tx_context::TxContext;
    use sui::event;
    use sui::clock::{Self as clock, Clock};
    use sui::coin::{Coin};
    use sui::sui::SUI;
    use suiverse_certificate::simple_config_manager::{Self, SimpleConfigManager};
    use suiverse_certificate::standalone_certificates::{Self as certificates, CertificateNFT};

    // =============== Error Constants ===============
    const E_SYSTEM_NOT_READY: u64 = 21001;
    const E_FEATURE_DISABLED: u64 = 21002;

    // =============== Events ===============

    public struct SimplifiedFunctionCalled has copy, drop {
        function_name: String,
        caller: address,
        timestamp: u64,
    }

    // =============== Simplified Entry Functions ===============

    /// Issue a certificate with automatic object resolution
    public entry fun issue_certificate(
        config_manager: &mut SimpleConfigManager,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        recipient: address,
        skills: vector<String>,
        expires_in_days: u64, // 0 for no expiration
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // System health checks
        assert!(simple_config_manager::is_system_healthy(config_manager), E_SYSTEM_NOT_READY);
        assert!(simple_config_manager::are_critical_objects_available(config_manager), E_SYSTEM_NOT_READY);
        
        let current_time = clock::timestamp_ms(clock);
        let caller = tx_context::sender(ctx);

        // Emit simplified function call event
        event::emit(SimplifiedFunctionCalled {
            function_name: string::utf8(b"issue_certificate"),
            caller,
            timestamp: current_time,
        });

        // Use config manager to issue certificate (handles DOF internally)
        simple_config_manager::issue_certificate_through_config(
            config_manager,
            certificate_type,
            level,
            title,
            description,
            recipient,
            skills,
            expires_in_days,
            payment,
            clock,
            ctx
        );
    }

    /// Auto-register certificate (placeholder for registry functionality)
    public entry fun auto_register_certificate(
        _config_manager: &mut SimpleConfigManager,
        _certificate: &CertificateNFT,
        _clock: &Clock,
        _ctx: &TxContext,
    ) {
        // Placeholder - in full implementation would register with registry
        // This demonstrates the concept without external dependencies
    }

    /// Batch issue two certificates (simplified version)
    public entry fun batch_issue_two_certificates(
        config_manager: &mut SimpleConfigManager,
        cert1_type: u8, cert1_level: u8, cert1_title: String, cert1_description: String, 
        cert1_recipient: address, cert1_skills: vector<String>, cert1_expires_in_days: u64,
        cert2_type: u8, cert2_level: u8, cert2_title: String, cert2_description: String, 
        cert2_recipient: address, cert2_skills: vector<String>, cert2_expires_in_days: u64,
        payment1: Coin<SUI>, payment2: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // System health checks
        assert!(simple_config_manager::is_system_healthy(config_manager), E_SYSTEM_NOT_READY);
        assert!(simple_config_manager::are_critical_objects_available(config_manager), E_SYSTEM_NOT_READY);
        
        let current_time = clock::timestamp_ms(clock);
        let caller = tx_context::sender(ctx);

        // Emit batch operation event
        event::emit(SimplifiedFunctionCalled {
            function_name: string::utf8(b"batch_issue_two_certificates"),
            caller,
            timestamp: current_time,
        });

        // Use config manager to batch issue certificates
        simple_config_manager::batch_issue_two_certificates(
            config_manager,
            cert1_type, cert1_level, cert1_title, cert1_description, 
            cert1_recipient, cert1_skills, cert1_expires_in_days,
            cert2_type, cert2_level, cert2_title, cert2_description, 
            cert2_recipient, cert2_skills, cert2_expires_in_days,
            payment1, payment2, clock, ctx
        );
    }

    /// Verify certificate validity
    public entry fun verify_certificate(
        config_manager: &SimpleConfigManager,
        certificate_id: address,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        // System health checks
        assert!(simple_config_manager::is_system_healthy(config_manager), E_SYSTEM_NOT_READY);
        
        let current_time = clock::timestamp_ms(clock);

        // Emit verification event
        event::emit(SimplifiedFunctionCalled {
            function_name: string::utf8(b"verify_certificate"),
            caller: certificate_id, // Use certificate_id as caller for verification
            timestamp: current_time,
        });

        // Perform verification through config manager
        let (_is_valid, _objects_available, _system_healthy) = simple_config_manager::verify_certificate_through_config(
            config_manager,
            certificate_id,
            clock
        );
    }

    /// Get detailed certificate statistics
    public fun get_certificate_statistics(
        config_manager: &SimpleConfigManager,
    ): (u64, u64, u64, u64) {
        simple_config_manager::get_certificate_statistics(config_manager)
    }

    /// Issue certificate with automatic registry registration
    public entry fun issue_and_register_certificate(
        config_manager: &mut SimpleConfigManager,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        recipient: address,
        skills: vector<String>,
        expires_in_days: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // System health checks
        assert!(simple_config_manager::is_system_healthy(config_manager), E_SYSTEM_NOT_READY);
        assert!(simple_config_manager::are_critical_objects_available(config_manager), E_SYSTEM_NOT_READY);
        
        let current_time = clock::timestamp_ms(clock);
        let caller = tx_context::sender(ctx);

        // Emit function call event
        event::emit(SimplifiedFunctionCalled {
            function_name: string::utf8(b"issue_and_register_certificate"),
            caller,
            timestamp: current_time,
        });

        // Use config manager to issue and register certificate
        simple_config_manager::issue_and_register_certificate(
            config_manager,
            certificate_type,
            level,
            title,
            description,
            recipient,
            skills,
            expires_in_days,
            payment,
            clock,
            ctx
        );
    }

    /// Comprehensive certificate verification
    public entry fun comprehensive_verify_certificate(
        config_manager: &SimpleConfigManager,
        certificate_owner: address,
        skill_to_verify: String,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        // System health checks
        assert!(simple_config_manager::is_system_healthy(config_manager), E_SYSTEM_NOT_READY);
        
        let current_time = clock::timestamp_ms(clock);
        let caller = tx_context::sender(ctx);

        // Emit verification event
        event::emit(SimplifiedFunctionCalled {
            function_name: string::utf8(b"comprehensive_verify_certificate"),
            caller,
            timestamp: current_time,
        });

        // Perform comprehensive verification
        let (_is_healthy, _has_skill, _owner_certs, _skill_cert_count) = 
            simple_config_manager::comprehensive_certificate_verification(
                config_manager,
                certificate_owner,
                skill_to_verify,
                clock
            );
    }

    /// Get comprehensive system analytics
    public fun get_comprehensive_analytics(
        config_manager: &SimpleConfigManager,
    ): (u64, u64, u64, bool, bool, u64) {
        simple_config_manager::get_comprehensive_analytics(config_manager)
    }

    /// Check if registry is available
    public fun is_registry_available(
        config_manager: &SimpleConfigManager,
    ): bool {
        simple_config_manager::is_registry_available(config_manager)
    }

    /// Get system status and configuration summary
    public fun get_system_status(
        config_manager: &SimpleConfigManager
    ): (bool, bool, bool, bool, u64, u64) {
        let is_healthy = simple_config_manager::is_system_healthy(config_manager);
        let objects_available = simple_config_manager::are_critical_objects_available(config_manager);
        let (cert_enabled, registry_enabled, verify_enabled, max_batch, rate_limit, _) = 
            simple_config_manager::get_system_config_summary(config_manager);
        
        (is_healthy, objects_available, cert_enabled, registry_enabled, max_batch, rate_limit)
    }

    /// Check if a specific operation is allowed
    public fun is_operation_allowed(
        config_manager: &SimpleConfigManager,
        operation: String,
    ): bool {
        if (!simple_config_manager::is_system_healthy(config_manager)) {
            return false
        };

        let (cert_enabled, registry_enabled, verify_enabled, _, _, _) = 
            simple_config_manager::get_system_config_summary(config_manager);
        
        if (string::bytes(&operation) == b"issue_certificate") {
            cert_enabled
        } else if (string::bytes(&operation) == b"verify_certificate") {
            verify_enabled
        } else if (string::bytes(&operation) == b"query_certificates") {
            registry_enabled
        } else {
            true // Allow other operations by default
        }
    }
}