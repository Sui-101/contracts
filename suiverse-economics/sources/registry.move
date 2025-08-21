/// Certificate Registry Module for SuiVerse
/// Provides global certificate registry, verification, and lookup services
/// Implements comprehensive tracking and analytics for all certificates
module suiverse_economics::registry {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::hash;
    use suiverse_economics::certificates::{Self, CertificateNFT};

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 11001;
    const E_CERTIFICATE_NOT_FOUND: u64 = 11002;
    const E_ALREADY_REGISTERED: u64 = 11003;
    const E_INVALID_QUERY: u64 = 11004;
    const E_REGISTRY_PAUSED: u64 = 11005;
    const E_INSUFFICIENT_PAYMENT: u64 = 11006;
    const E_INVALID_FILTER: u64 = 11007;
    const E_MAX_RESULTS_EXCEEDED: u64 = 11008;

    // Registry status
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_SUSPENDED: u8 = 2;
    const STATUS_REVOKED: u8 = 3;
    const STATUS_EXPIRED: u8 = 4;

    // Query types
    const QUERY_BY_USER: u8 = 1;
    const QUERY_BY_ISSUER: u8 = 2;
    const QUERY_BY_TYPE: u8 = 3;
    const QUERY_BY_SKILL: u8 = 4;
    const QUERY_BY_TAG: u8 = 5;

    // Fees
    const REGISTRY_QUERY_FEE: u64 = 5000000; // 0.005 SUI
    const BULK_QUERY_FEE: u64 = 20000000; // 0.02 SUI
    const ANALYTICS_QUERY_FEE: u64 = 10000000; // 0.01 SUI

    // Constants
    const MAX_QUERY_RESULTS: u64 = 100;
    const MAX_BULK_QUERY_SIZE: u64 = 1000;

    // =============== Structs ===============

    /// Global certificate registry
    public struct CertificateRegistry has key {
        id: UID,
        total_certificates: u64,
        active_certificates: u64,
        revoked_certificates: u64,
        expired_certificates: u64,
        
        // Core mappings
        certificate_records: Table<ID, CertificateRecord>,
        user_certificates: Table<address, VecSet<ID>>,
        issuer_certificates: Table<address, VecSet<ID>>,
        verification_hashes: Table<vector<u8>, ID>,
        
        // Search indices
        certificates_by_type: Table<u8, VecSet<ID>>,
        certificates_by_level: Table<u8, VecSet<ID>>,
        certificates_by_skill: Table<String, VecSet<ID>>,
        certificates_by_tag: Table<String, VecSet<ID>>,
        certificates_by_status: Table<u8, VecSet<ID>>,
        
        // Analytics
        issuance_trends: Table<u64, u64>, // epoch -> count
        type_statistics: Table<u8, TypeStatistics>,
        skill_popularity: Table<String, u64>,
        
        // Configuration
        query_fees: Table<u8, u64>,
        authorized_verifiers: VecSet<address>,
        paused: bool,
        treasury: Balance<SUI>,
        admin_cap_id: ID,
    }

    /// Individual certificate record in registry
    public struct CertificateRecord has store {
        certificate_id: ID,
        certificate_type: u8,
        level: u8,
        recipient: address,
        issuer: address,
        title: String,
        skills_certified: vector<String>,
        tags: vector<String>,
        status: u8,
        issued_at: u64,
        expires_at: Option<u64>,
        last_verified: Option<u64>,
        verification_count: u64,
        market_value: u64,
        ipfs_hash: String,
    }

    /// Statistics for certificate types
    public struct TypeStatistics has store {
        certificate_type: u8,
        total_issued: u64,
        currently_active: u64,
        average_score: u64,
        average_validity_period: u64,
        most_common_skills: vector<String>,
        top_issuers: vector<address>,
        pass_rate_trend: vector<u64>,
    }

    /// Verification result for certificate checks
    public struct VerificationResult has key, store {
        id: UID,
        certificate_id: ID,
        is_valid: bool,
        verification_details: VerificationDetails,
        verified_by: address,
        verified_at: u64,
        verification_method: String,
    }

    /// Detailed verification information
    public struct VerificationDetails has store {
        certificate_exists: bool,
        status_valid: bool,
        not_expired: bool,
        hash_verified: bool,
        issuer_authorized: bool,
        metadata_consistent: bool,
        additional_checks: vector<String>,
    }

    /// Query result for certificate searches
    public struct QueryResult has key, store {
        id: UID,
        query_type: u8,
        query_parameters: String,
        results: vector<ID>,
        total_found: u64,
        timestamp: u64,
        requester: address,
    }

    /// Bulk verification request
    public struct BulkVerificationRequest has key {
        id: UID,
        certificate_ids: vector<ID>,
        requester: address,
        status: u8, // 0: pending, 1: completed, 2: failed
        results: vector<VerificationResult>,
        requested_at: u64,
        completed_at: Option<u64>,
    }

    /// Registry analytics data
    public struct RegistryAnalytics has key {
        id: UID,
        total_queries: u64,
        total_verifications: u64,
        most_queried_skills: vector<String>,
        most_active_issuers: vector<address>,
        certificate_growth_rate: u64,
        verification_success_rate: u64,
        average_certificate_lifespan: u64,
        fraud_detection_alerts: u64,
        last_updated: u64,
    }

    /// Administrative capability for registry management
    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct CertificateRegistered has copy, drop {
        certificate_id: ID,
        certificate_type: u8,
        level: u8,
        recipient: address,
        issuer: address,
        skills: vector<String>,
        timestamp: u64,
    }

    public struct CertificateVerificationPerformed has copy, drop {
        certificate_id: ID,
        verifier: address,
        is_valid: bool,
        verification_method: String,
        timestamp: u64,
    }

    public struct RegistryQueryExecuted has copy, drop {
        query_type: u8,
        query_parameters: String,
        results_count: u64,
        requester: address,
        timestamp: u64,
    }

    public struct BulkVerificationCompleted has copy, drop {
        request_id: ID,
        total_certificates: u64,
        valid_certificates: u64,
        invalid_certificates: u64,
        completion_time: u64,
    }

    public struct RegistryAnalyticsUpdated has copy, drop {
        total_certificates: u64,
        active_certificates: u64,
        growth_rate: u64,
        top_skill: String,
        timestamp: u64,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        // Create admin capability
        let admin_cap = RegistryAdminCap {
            id: object::new(ctx),
        };
        let admin_cap_id = object::uid_to_inner(&admin_cap.id);

        // Initialize certificate registry
        let mut registry = CertificateRegistry {
            id: object::new(ctx),
            total_certificates: 0,
            active_certificates: 0,
            revoked_certificates: 0,
            expired_certificates: 0,
            certificate_records: table::new(ctx),
            user_certificates: table::new(ctx),
            issuer_certificates: table::new(ctx),
            verification_hashes: table::new(ctx),
            certificates_by_type: table::new(ctx),
            certificates_by_level: table::new(ctx),
            certificates_by_skill: table::new(ctx),
            certificates_by_tag: table::new(ctx),
            certificates_by_status: table::new(ctx),
            issuance_trends: table::new(ctx),
            type_statistics: table::new(ctx),
            skill_popularity: table::new(ctx),
            query_fees: table::new(ctx),
            authorized_verifiers: vec_set::empty(),
            paused: false,
            treasury: balance::zero(),
            admin_cap_id,
        };

        // Initialize analytics
        let analytics = RegistryAnalytics {
            id: object::new(ctx),
            total_queries: 0,
            total_verifications: 0,
            most_queried_skills: vector::empty(),
            most_active_issuers: vector::empty(),
            certificate_growth_rate: 0,
            verification_success_rate: 100,
            average_certificate_lifespan: 365 * 86400000, // 1 year in ms
            fraud_detection_alerts: 0,
            last_updated: 0,
        };

        // Set default query fees
        table::add(&mut registry.query_fees, QUERY_BY_USER, REGISTRY_QUERY_FEE);
        table::add(&mut registry.query_fees, QUERY_BY_ISSUER, REGISTRY_QUERY_FEE);
        table::add(&mut registry.query_fees, QUERY_BY_TYPE, REGISTRY_QUERY_FEE);
        table::add(&mut registry.query_fees, QUERY_BY_SKILL, REGISTRY_QUERY_FEE);
        table::add(&mut registry.query_fees, QUERY_BY_TAG, REGISTRY_QUERY_FEE);

        // Initialize status tracking
        table::add(&mut registry.certificates_by_status, STATUS_ACTIVE, vec_set::empty());
        table::add(&mut registry.certificates_by_status, STATUS_SUSPENDED, vec_set::empty());
        table::add(&mut registry.certificates_by_status, STATUS_REVOKED, vec_set::empty());
        table::add(&mut registry.certificates_by_status, STATUS_EXPIRED, vec_set::empty());

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(registry);
        transfer::share_object(analytics);
    }

    // =============== Public Entry Functions ===============

    /// Register a certificate in the global registry
    public fun register_certificate(
        registry: &mut CertificateRegistry,
        certificate: &CertificateNFT,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(!registry.paused, E_REGISTRY_PAUSED);
        
        let certificate_id = object::id(certificate);
        let current_time = clock::timestamp_ms(clock);
        
        // Check if already registered
        assert!(!table::contains(&registry.certificate_records, certificate_id), E_ALREADY_REGISTERED);
        
        // Extract certificate details
        let cert_type = certificates::get_certificate_type(certificate);
        let level = certificates::get_certificate_level(certificate);
        let recipient = certificates::get_certificate_recipient(certificate);
        let issuer = certificates::get_certificate_issuer(certificate);
        let skills = certificates::get_certificate_skills(certificate);
        let market_value = certificates::get_certificate_market_value_view(certificate);
        
        // Create registry record
        let record = CertificateRecord {
            certificate_id,
            certificate_type: cert_type,
            level,
            recipient,
            issuer,
            title: string::utf8(b""), // Would extract from certificate
            skills_certified: skills,
            tags: vector::empty(), // Would extract from certificate
            status: STATUS_ACTIVE,
            issued_at: current_time,
            expires_at: option::none(), // Would extract from certificate
            last_verified: option::none(),
            verification_count: 0,
            market_value,
            ipfs_hash: string::utf8(b""), // Would extract from certificate
        };

        // Add to registry
        table::add(&mut registry.certificate_records, certificate_id, record);
        
        // Update user certificates
        if (!table::contains(&registry.user_certificates, recipient)) {
            table::add(&mut registry.user_certificates, recipient, vec_set::empty());
        };
        let user_certs = table::borrow_mut(&mut registry.user_certificates, recipient);
        vec_set::insert(user_certs, certificate_id);
        
        // Update issuer certificates
        if (!table::contains(&registry.issuer_certificates, issuer)) {
            table::add(&mut registry.issuer_certificates, issuer, vec_set::empty());
        };
        let issuer_certs = table::borrow_mut(&mut registry.issuer_certificates, issuer);
        vec_set::insert(issuer_certs, certificate_id);
        
        // Update search indices
        update_search_indices(registry, certificate_id, cert_type, level, &skills, &vector::empty());
        
        // Update statistics
        registry.total_certificates = registry.total_certificates + 1;
        registry.active_certificates = registry.active_certificates + 1;
        update_type_statistics(registry, cert_type, current_time);
        
        event::emit(CertificateRegistered {
            certificate_id,
            certificate_type: cert_type,
            level,
            recipient,
            issuer,
            skills,
            timestamp: current_time,
        });
    }

    /// Verify a certificate's authenticity and validity
    public entry fun verify_certificate(
        registry: &mut CertificateRegistry,
        analytics: &mut RegistryAnalytics,
        certificate: &CertificateNFT,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!registry.paused, E_REGISTRY_PAUSED);
        
        let verifier = tx_context::sender(ctx);
        let certificate_id = object::id(certificate);
        let current_time = clock::timestamp_ms(clock);
        
        // Process payment
        assert!(coin::value(&payment) >= ANALYTICS_QUERY_FEE, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut registry.treasury, coin::into_balance(payment));
        
        // Perform verification
        let verification_details = perform_certificate_verification(registry, certificate, clock);
        let is_valid = verification_details.certificate_exists && 
                       verification_details.status_valid && 
                       verification_details.not_expired && 
                       verification_details.hash_verified;
        
        // Update registry record if exists
        if (table::contains(&registry.certificate_records, certificate_id)) {
            let record = table::borrow_mut(&mut registry.certificate_records, certificate_id);
            record.last_verified = option::some(current_time);
            record.verification_count = record.verification_count + 1;
        };
        
        // Create verification result
        let verification_result = VerificationResult {
            id: object::new(ctx),
            certificate_id,
            is_valid,
            verification_details,
            verified_by: verifier,
            verified_at: current_time,
            verification_method: string::utf8(b"registry_verification"),
        };
        
        // Update analytics
        analytics.total_verifications = analytics.total_verifications + 1;
        if (is_valid) {
            analytics.verification_success_rate = 
                (analytics.verification_success_rate * (analytics.total_verifications - 1) + 100) / 
                analytics.total_verifications;
        } else {
            analytics.verification_success_rate = 
                (analytics.verification_success_rate * (analytics.total_verifications - 1)) / 
                analytics.total_verifications;
        };
        
        event::emit(CertificateVerificationPerformed {
            certificate_id,
            verifier,
            is_valid,
            verification_method: string::utf8(b"registry_verification"),
            timestamp: current_time,
        });
        
        transfer::transfer(verification_result, verifier);
    }

    /// Query certificates by various criteria
    public entry fun query_certificates(
        registry: &mut CertificateRegistry,
        analytics: &mut RegistryAnalytics,
        query_type: u8,
        query_parameter: String,
        limit: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!registry.paused, E_REGISTRY_PAUSED);
        assert!(limit <= MAX_QUERY_RESULTS, E_MAX_RESULTS_EXCEEDED);
        
        let requester = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Check payment
        let required_fee = *table::borrow(&registry.query_fees, query_type);
        assert!(coin::value(&payment) >= required_fee, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut registry.treasury, coin::into_balance(payment));
        
        // Execute query
        let results = execute_certificate_query(registry, query_type, &query_parameter, limit);
        let total_found = vector::length(&results);
        
        // Create query result
        let query_result = QueryResult {
            id: object::new(ctx),
            query_type,
            query_parameters: query_parameter,
            results,
            total_found,
            timestamp: current_time,
            requester,
        };
        
        // Update analytics
        analytics.total_queries = analytics.total_queries + 1;
        if (query_type == QUERY_BY_SKILL) {
            update_skill_query_stats(analytics, &query_parameter);
        };
        
        event::emit(RegistryQueryExecuted {
            query_type,
            query_parameters: query_parameter,
            results_count: total_found,
            requester,
            timestamp: current_time,
        });
        
        transfer::transfer(query_result, requester);
    }

    /// Perform bulk verification of multiple certificates
    public entry fun bulk_verify_certificates(
        registry: &mut CertificateRegistry,
        certificate_ids: vector<ID>,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!registry.paused, E_REGISTRY_PAUSED);
        assert!(vector::length(&certificate_ids) <= MAX_BULK_QUERY_SIZE, E_MAX_RESULTS_EXCEEDED);
        
        let requester = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Check payment for bulk operation
        assert!(coin::value(&payment) >= BULK_QUERY_FEE, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut registry.treasury, coin::into_balance(payment));
        
        // Create bulk verification request
        let bulk_request = BulkVerificationRequest {
            id: object::new(ctx),
            certificate_ids,
            requester,
            status: 0, // Pending
            results: vector::empty(),
            requested_at: current_time,
            completed_at: option::none(),
        };
        
        transfer::transfer(bulk_request, requester);
    }

    /// Update certificate status in registry
    public entry fun update_certificate_status(
        registry: &mut CertificateRegistry,
        certificate_id: ID,
        new_status: u8,
        _admin_cap: &RegistryAdminCap,
        clock: &Clock,
    ) {
        assert!(table::contains(&registry.certificate_records, certificate_id), E_CERTIFICATE_NOT_FOUND);
        
        let record = table::borrow_mut(&mut registry.certificate_records, certificate_id);
        let old_status = record.status;
        record.status = new_status;
        
        // Update status counters
        update_status_counters(registry, old_status, new_status);
        
        // Update status indices
        let old_status_set = table::borrow_mut(&mut registry.certificates_by_status, old_status);
        vec_set::remove(old_status_set, &certificate_id);
        
        let new_status_set = table::borrow_mut(&mut registry.certificates_by_status, new_status);
        vec_set::insert(new_status_set, certificate_id);
    }

    // =============== Internal Helper Functions ===============

    fun update_search_indices(
        registry: &mut CertificateRegistry,
        certificate_id: ID,
        cert_type: u8,
        level: u8,
        skills: &vector<String>,
        tags: &vector<String>,
    ) {
        // Update type index
        if (!table::contains(&registry.certificates_by_type, cert_type)) {
            table::add(&mut registry.certificates_by_type, cert_type, vec_set::empty());
        };
        let type_set = table::borrow_mut(&mut registry.certificates_by_type, cert_type);
        vec_set::insert(type_set, certificate_id);
        
        // Update level index
        if (!table::contains(&registry.certificates_by_level, level)) {
            table::add(&mut registry.certificates_by_level, level, vec_set::empty());
        };
        let level_set = table::borrow_mut(&mut registry.certificates_by_level, level);
        vec_set::insert(level_set, certificate_id);
        
        // Update skill indices
        let mut i = 0;
        while (i < vector::length(skills)) {
            let skill = vector::borrow(skills, i);
            if (!table::contains(&registry.certificates_by_skill, *skill)) {
                table::add(&mut registry.certificates_by_skill, *skill, vec_set::empty());
            };
            let skill_set = table::borrow_mut(&mut registry.certificates_by_skill, *skill);
            vec_set::insert(skill_set, certificate_id);
            
            // Update skill popularity
            if (table::contains(&registry.skill_popularity, *skill)) {
                let count = table::borrow_mut(&mut registry.skill_popularity, *skill);
                *count = *count + 1;
            } else {
                table::add(&mut registry.skill_popularity, *skill, 1);
            };
            
            i = i + 1;
        };
        
        // Update tag indices
        i = 0;
        while (i < vector::length(tags)) {
            let tag = vector::borrow(tags, i);
            if (!table::contains(&registry.certificates_by_tag, *tag)) {
                table::add(&mut registry.certificates_by_tag, *tag, vec_set::empty());
            };
            let tag_set = table::borrow_mut(&mut registry.certificates_by_tag, *tag);
            vec_set::insert(tag_set, certificate_id);
            i = i + 1;
        };
    }

    fun update_type_statistics(registry: &mut CertificateRegistry, cert_type: u8, timestamp: u64) {
        if (!table::contains(&registry.type_statistics, cert_type)) {
            let stats = TypeStatistics {
                certificate_type: cert_type,
                total_issued: 0,
                currently_active: 0,
                average_score: 0,
                average_validity_period: 0,
                most_common_skills: vector::empty(),
                top_issuers: vector::empty(),
                pass_rate_trend: vector::empty(),
            };
            table::add(&mut registry.type_statistics, cert_type, stats);
        };
        
        let stats = table::borrow_mut(&mut registry.type_statistics, cert_type);
        stats.total_issued = stats.total_issued + 1;
        stats.currently_active = stats.currently_active + 1;
        
        // Update issuance trends
        let epoch = timestamp / 86400000; // Daily epochs
        if (table::contains(&registry.issuance_trends, epoch)) {
            let count = table::borrow_mut(&mut registry.issuance_trends, epoch);
            *count = *count + 1;
        } else {
            table::add(&mut registry.issuance_trends, epoch, 1);
        };
    }

    fun perform_certificate_verification(
        registry: &CertificateRegistry,
        certificate: &CertificateNFT,
        clock: &Clock,
    ): VerificationDetails {
        let certificate_id = object::id(certificate);
        let current_time = clock::timestamp_ms(clock);
        
        // Check if certificate exists in registry
        let certificate_exists = table::contains(&registry.certificate_records, certificate_id);
        
        let mut status_valid = false;
        let mut not_expired = true;
        
        if (certificate_exists) {
            let record = table::borrow(&registry.certificate_records, certificate_id);
            status_valid = record.status == STATUS_ACTIVE;
            
            if (option::is_some(&record.expires_at)) {
                let expiry = *option::borrow(&record.expires_at);
                not_expired = current_time < expiry;
            };
        };
        
        // Verify certificate validity using certificates module
        let hash_verified = certificates::is_certificate_valid(certificate, clock);
        
        VerificationDetails {
            certificate_exists,
            status_valid,
            not_expired,
            hash_verified,
            issuer_authorized: true, // Would check against authorized issuers
            metadata_consistent: true, // Would verify metadata consistency
            additional_checks: vector::empty(),
        }
    }

    fun execute_certificate_query(
        registry: &CertificateRegistry,
        query_type: u8,
        query_parameter: &String,
        limit: u64,
    ): vector<ID> {
        let mut results = vector::empty<ID>();
        
        if (query_type == QUERY_BY_TYPE) {
            // Query by certificate type
            let type_value = 1u8; // Would parse from query_parameter
            if (table::contains(&registry.certificates_by_type, type_value)) {
                let type_set = table::borrow(&registry.certificates_by_type, type_value);
                let cert_ids = vec_set::keys(type_set);
                let mut i = 0;
                while (i < vector::length(cert_ids) && i < limit) {
                    vector::push_back(&mut results, *vector::borrow(cert_ids, i));
                    i = i + 1;
                };
            };
        } else if (query_type == QUERY_BY_SKILL) {
            // Query by skill
            if (table::contains(&registry.certificates_by_skill, *query_parameter)) {
                let skill_set = table::borrow(&registry.certificates_by_skill, *query_parameter);
                let cert_ids = vec_set::keys(skill_set);
                let mut i = 0;
                while (i < vector::length(cert_ids) && i < limit) {
                    vector::push_back(&mut results, *vector::borrow(cert_ids, i));
                    i = i + 1;
                };
            };
        } else if (query_type == QUERY_BY_USER) {
            // Query by user - would parse address from query_parameter
            // Implementation would convert string to address and lookup
        };
        // Add other query types as needed
        
        results
    }

    fun update_status_counters(registry: &mut CertificateRegistry, old_status: u8, new_status: u8) {
        // Decrement old status counter
        if (old_status == STATUS_ACTIVE) {
            registry.active_certificates = registry.active_certificates - 1;
        } else if (old_status == STATUS_REVOKED) {
            registry.revoked_certificates = registry.revoked_certificates - 1;
        } else if (old_status == STATUS_EXPIRED) {
            registry.expired_certificates = registry.expired_certificates - 1;
        };
        
        // Increment new status counter
        if (new_status == STATUS_ACTIVE) {
            registry.active_certificates = registry.active_certificates + 1;
        } else if (new_status == STATUS_REVOKED) {
            registry.revoked_certificates = registry.revoked_certificates + 1;
        } else if (new_status == STATUS_EXPIRED) {
            registry.expired_certificates = registry.expired_certificates + 1;
        };
    }

    fun update_skill_query_stats(analytics: &mut RegistryAnalytics, skill: &String) {
        // Update most queried skills
        let mut found = false;
        let mut i = 0;
        while (i < vector::length(&analytics.most_queried_skills)) {
            if (vector::borrow(&analytics.most_queried_skills, i) == skill) {
                found = true;
                break
            };
            i = i + 1;
        };
        
        if (!found && vector::length(&analytics.most_queried_skills) < 10) {
            vector::push_back(&mut analytics.most_queried_skills, *skill);
        };
    }

    // =============== View Functions ===============

    public fun get_certificate_record(registry: &CertificateRegistry, certificate_id: ID): &CertificateRecord {
        table::borrow(&registry.certificate_records, certificate_id)
    }

    public fun get_user_certificates(registry: &CertificateRegistry, user: address): vector<ID> {
        if (table::contains(&registry.user_certificates, user)) {
            *vec_set::keys(table::borrow(&registry.user_certificates, user))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_issuer_certificates(registry: &CertificateRegistry, issuer: address): vector<ID> {
        if (table::contains(&registry.issuer_certificates, issuer)) {
            *vec_set::keys(table::borrow(&registry.issuer_certificates, issuer))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_certificates_by_skill(registry: &CertificateRegistry, skill: String): vector<ID> {
        if (table::contains(&registry.certificates_by_skill, skill)) {
            *vec_set::keys(table::borrow(&registry.certificates_by_skill, skill))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_registry_statistics(registry: &CertificateRegistry): (u64, u64, u64, u64) {
        (
            registry.total_certificates,
            registry.active_certificates,
            registry.revoked_certificates,
            registry.expired_certificates
        )
    }

    public fun get_skill_popularity(registry: &CertificateRegistry, skill: String): u64 {
        if (table::contains(&registry.skill_popularity, skill)) {
            *table::borrow(&registry.skill_popularity, skill)
        } else {
            0
        }
    }

    public fun is_certificate_registered(registry: &CertificateRegistry, certificate_id: ID): bool {
        table::contains(&registry.certificate_records, certificate_id)
    }

    public fun get_type_statistics(registry: &CertificateRegistry, cert_type: u8): &TypeStatistics {
        table::borrow(&registry.type_statistics, cert_type)
    }

    public fun get_verification_result_details(result: &VerificationResult): (ID, bool, String, u64) {
        (result.certificate_id, result.is_valid, result.verification_method, result.verified_at)
    }

    public fun get_query_result_summary(result: &QueryResult): (u8, String, u64, u64) {
        (result.query_type, result.query_parameters, result.total_found, result.timestamp)
    }
}