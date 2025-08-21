/// Certificate Verification Module for SuiVerse
/// Provides third-party verification services for certificates
/// Implements comprehensive verification workflows and analytics
module suiverse_economics::verification {
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
    use sui::url::{Self, Url};
    use suiverse_economics::certificates::{Self, CertificateNFT};
    use suiverse::registry::{Self, CertificateRegistry};

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 13001;
    const E_VERIFIER_NOT_APPROVED: u64 = 13002;
    const E_VERIFICATION_REQUEST_NOT_FOUND: u64 = 13003;
    const E_INSUFFICIENT_PAYMENT: u64 = 13004;
    const E_INVALID_VERIFICATION_METHOD: u64 = 13005;
    const E_CERTIFICATE_ALREADY_VERIFIED: u64 = 13006;
    const E_VERIFICATION_EXPIRED: u64 = 13007;
    const E_INVALID_VERIFICATION_DATA: u64 = 13008;
    const E_SERVICE_SUSPENDED: u64 = 13009;
    const E_FRAUD_DETECTED: u64 = 13010;

    // Verification status
    const STATUS_PENDING: u8 = 0;
    const STATUS_IN_PROGRESS: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_FAILED: u8 = 3;
    const STATUS_DISPUTED: u8 = 4;
    const STATUS_CANCELLED: u8 = 5;

    // Verification methods
    const METHOD_BASIC_CHECK: u8 = 1;
    const METHOD_COMPREHENSIVE: u8 = 2;
    const METHOD_FORENSIC: u8 = 3;
    const METHOD_THIRD_PARTY: u8 = 4;
    const METHOD_EMPLOYER_VERIFICATION: u8 = 5;

    // Verifier types
    const VERIFIER_TYPE_INDIVIDUAL: u8 = 1;
    const VERIFIER_TYPE_ORGANIZATION: u8 = 2;
    const VERIFIER_TYPE_GOVERNMENT: u8 = 3;
    const VERIFIER_TYPE_EDUCATIONAL: u8 = 4;
    const VERIFIER_TYPE_CORPORATE: u8 = 5;

    // Risk levels
    const RISK_LEVEL_LOW: u8 = 1;
    const RISK_LEVEL_MEDIUM: u8 = 2;
    const RISK_LEVEL_HIGH: u8 = 3;
    const RISK_LEVEL_CRITICAL: u8 = 4;

    // Fees (in MIST, 1 SUI = 1,000,000,000 MIST)
    const BASIC_VERIFICATION_FEE: u64 = 10000000; // 0.01 SUI
    const COMPREHENSIVE_VERIFICATION_FEE: u64 = 50000000; // 0.05 SUI
    const FORENSIC_VERIFICATION_FEE: u64 = 200000000; // 0.2 SUI
    const THIRD_PARTY_VERIFICATION_FEE: u64 = 100000000; // 0.1 SUI
    const EMPLOYER_VERIFICATION_FEE: u64 = 30000000; // 0.03 SUI

    // Time limits
    const VERIFICATION_TIMEOUT: u64 = 604800000; // 7 days in ms
    const DISPUTE_PERIOD: u64 = 259200000; // 3 days in ms

    // =============== Structs ===============

    /// Third-party verification service provider
    public struct VerificationService has key {
        id: UID,
        name: String,
        description: String,
        service_type: u8, // Individual, Organization, etc.
        owner: address,
        
        // Service capabilities
        supported_methods: VecSet<u8>,
        verification_levels: VecSet<u8>,
        specializations: vector<String>, // Skills/areas of expertise
        
        // Reputation and metrics
        total_verifications: u64,
        successful_verifications: u64,
        disputed_verifications: u64,
        average_completion_time: u64,
        reputation_score: u64, // 0-1000
        
        // Service configuration
        service_fees: Table<u8, u64>, // method -> fee
        turnaround_times: Table<u8, u64>, // method -> estimated time
        is_active: bool,
        is_verified: bool, // Verified by platform admins
        
        // Contact and credentials
        contact_info: String,
        credentials: vector<String>,
        verification_methodology: String,
        
        // Economics
        total_earnings: u64,
        pending_payments: Balance<SUI>,
        
        // Timestamps
        created_at: u64,
        last_active: u64,
        verified_at: Option<u64>,
    }

    /// Verification request from users/organizations
    public struct VerificationRequest has key {
        id: UID,
        certificate_id: ID,
        requester: address,
        verifier_service_id: Option<ID>,
        
        // Request details
        verification_method: u8,
        urgency_level: u8, // 1-5 scale
        purpose: String,
        additional_context: String,
        required_completion_date: Option<u64>,
        
        // Payment and fees
        payment: Balance<SUI>,
        service_fee: u64,
        platform_fee: u64,
        refund_policy: String,
        
        // Status tracking
        status: u8,
        assigned_verifier: Option<address>,
        estimated_completion: Option<u64>,
        actual_completion: Option<u64>,
        
        // Results
        verification_result: Option<VerificationResult>,
        verifier_notes: String,
        confidence_score: u8, // 0-100
        
        // Timestamps
        requested_at: u64,
        assigned_at: Option<u64>,
        completed_at: Option<u64>,
        expires_at: u64,
    }

    /// Comprehensive verification result
    public struct VerificationResult has store, drop, copy {
        is_authentic: bool,
        is_valid: bool,
        confidence_level: u8, // 0-100
        risk_assessment: u8,
        
        // Detailed checks
        certificate_integrity: bool,
        issuer_verification: bool,
        recipient_verification: bool,
        metadata_consistency: bool,
        blockchain_validation: bool,
        third_party_confirmation: bool,
        
        // Additional findings
        anomalies_detected: vector<String>,
        verification_method_used: String,
        external_references: vector<String>,
        
        // Forensic data (if applicable)
        digital_fingerprint: Option<vector<u8>>,
        creation_metadata: String,
        modification_history: vector<String>,
        
        // Recommendations
        recommendations: vector<String>,
        follow_up_required: bool,
        validity_period: Option<u64>,
    }

    /// Verification dispute for contested results
    public struct VerificationDispute has key {
        id: UID,
        verification_request_id: ID,
        disputer: address, // Who raised the dispute
        dispute_reason: String,
        evidence: vector<String>,
        
        // Resolution process
        assigned_arbitrator: Option<address>,
        arbitrator_decision: Option<String>,
        resolution_status: u8, // 0: pending, 1: resolved_favor_requester, 2: resolved_favor_verifier, 3: dismissed
        
        // Financial implications
        refund_amount: u64,
        penalty_amount: u64,
        
        // Timestamps
        filed_at: u64,
        resolved_at: Option<u64>,
        expires_at: u64,
    }

    /// Verification marketplace for service discovery
    public struct VerificationMarketplace has key {
        id: UID,
        total_services: u64,
        active_services: u64,
        total_requests: u64,
        completed_verifications: u64,
        
        // Service discovery
        services_by_type: Table<u8, VecSet<ID>>,
        services_by_specialization: Table<String, VecSet<ID>>,
        top_rated_services: vector<ID>,
        
        // Economic metrics
        total_volume: u64,
        platform_revenue: u64,
        service_provider_earnings: u64,
        
        // Quality metrics
        average_completion_time: u64,
        success_rate: u64,
        dispute_rate: u64,
        
        // Platform configuration
        platform_fee_rate: u64, // Basis points
        minimum_service_bond: u64,
        maximum_verification_fee: u64,
        
        // Treasury and governance
        treasury: Balance<SUI>,
        admin_cap_id: ID,
        is_paused: bool,
    }

    /// Analytics for verification patterns and fraud detection
    public struct VerificationAnalytics has key {
        id: UID,
        
        // Usage patterns
        verifications_by_method: Table<u8, u64>,
        verifications_by_day: Table<u64, u64>, // epoch -> count
        popular_certificate_types: Table<u8, u64>,
        
        // Fraud detection
        suspicious_patterns: vector<String>,
        fraud_alerts: u64,
        blacklisted_certificates: VecSet<ID>,
        high_risk_verifications: VecSet<ID>,
        
        // Performance metrics
        average_verification_time: Table<u8, u64>, // by method
        verifier_performance: Table<ID, VerifierMetrics>,
        success_rates_by_type: Table<u8, u64>,
        
        // Market insights
        pricing_trends: Table<u64, u64>, // timestamp -> average fee
        demand_forecast: vector<u64>,
        seasonal_patterns: Table<u64, u64>,
        
        last_updated: u64,
    }

    /// Individual verifier performance metrics
    public struct VerifierMetrics has store {
        total_requests: u64,
        completed_requests: u64,
        average_time: u64,
        accuracy_score: u64,
        dispute_count: u64,
        satisfaction_score: u64,
        specialization_scores: Table<String, u64>,
    }

    /// Administrative capability for verification system
    public struct VerificationAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct VerificationServiceRegistered has copy, drop {
        service_id: ID,
        name: String,
        service_type: u8,
        owner: address,
        supported_methods: vector<u8>,
        timestamp: u64,
    }

    public struct VerificationRequested has copy, drop {
        request_id: ID,
        certificate_id: ID,
        requester: address,
        verification_method: u8,
        payment_amount: u64,
        timestamp: u64,
    }

    public struct VerificationAssigned has copy, drop {
        request_id: ID,
        verifier_service_id: ID,
        assigned_verifier: address,
        estimated_completion: u64,
        timestamp: u64,
    }

    public struct VerificationCompleted has copy, drop {
        request_id: ID,
        certificate_id: ID,
        verifier: address,
        is_authentic: bool,
        confidence_level: u8,
        completion_time: u64,
        timestamp: u64,
    }

    public struct VerificationDisputed has copy, drop {
        dispute_id: ID,
        verification_request_id: ID,
        disputer: address,
        reason: String,
        timestamp: u64,
    }

    public struct FraudDetected has copy, drop {
        certificate_id: ID,
        fraud_type: String,
        confidence_level: u8,
        detected_by: address,
        timestamp: u64,
    }

    public struct ServiceSuspended has copy, drop {
        service_id: ID,
        reason: String,
        suspended_by: address,
        timestamp: u64,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        // Create admin capability
        let admin_cap = VerificationAdminCap {
            id: object::new(ctx),
        };
        let admin_cap_id = object::uid_to_inner(&admin_cap.id);

        // Initialize verification marketplace
        let marketplace = VerificationMarketplace {
            id: object::new(ctx),
            total_services: 0,
            active_services: 0,
            total_requests: 0,
            completed_verifications: 0,
            services_by_type: table::new(ctx),
            services_by_specialization: table::new(ctx),
            top_rated_services: vector::empty(),
            total_volume: 0,
            platform_revenue: 0,
            service_provider_earnings: 0,
            average_completion_time: 86400000, // 1 day default
            success_rate: 95, // 95% default
            dispute_rate: 2, // 2% default
            platform_fee_rate: 500, // 5%
            minimum_service_bond: 1000000000, // 1 SUI
            maximum_verification_fee: 10000000000, // 10 SUI
            treasury: balance::zero(),
            admin_cap_id,
            is_paused: false,
        };

        // Initialize analytics
        let analytics = VerificationAnalytics {
            id: object::new(ctx),
            verifications_by_method: table::new(ctx),
            verifications_by_day: table::new(ctx),
            popular_certificate_types: table::new(ctx),
            suspicious_patterns: vector::empty(),
            fraud_alerts: 0,
            blacklisted_certificates: vec_set::empty(),
            high_risk_verifications: vec_set::empty(),
            average_verification_time: table::new(ctx),
            verifier_performance: table::new(ctx),
            success_rates_by_type: table::new(ctx),
            pricing_trends: table::new(ctx),
            demand_forecast: vector::empty(),
            seasonal_patterns: table::new(ctx),
            last_updated: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(marketplace);
        transfer::share_object(analytics);
    }

    // =============== Public Entry Functions ===============

    /// Register as a verification service provider
    public entry fun register_verification_service(
        marketplace: &mut VerificationMarketplace,
        name: String,
        description: String,
        service_type: u8,
        supported_methods: vector<u8>,
        specializations: vector<String>,
        contact_info: String,
        credentials: vector<String>,
        verification_methodology: String,
        service_bond: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(!marketplace.is_paused, E_SERVICE_SUSPENDED);
        assert!(coin::value(&service_bond) >= marketplace.minimum_service_bond, E_INSUFFICIENT_PAYMENT);
        
        // Create service
        let mut service = VerificationService {
            id: object::new(ctx),
            name,
            description,
            service_type,
            owner,
            supported_methods: vec_set::empty(),
            verification_levels: vec_set::empty(),
            specializations,
            total_verifications: 0,
            successful_verifications: 0,
            disputed_verifications: 0,
            average_completion_time: 0,
            reputation_score: 500, // Start with middle score
            service_fees: table::new(ctx),
            turnaround_times: table::new(ctx),
            is_active: true,
            is_verified: false,
            contact_info,
            credentials,
            verification_methodology,
            total_earnings: 0,
            pending_payments: coin::into_balance(service_bond),
            created_at: current_time,
            last_active: current_time,
            verified_at: option::none(),
        };
        
        // Add supported methods
        let mut i = 0;
        while (i < vector::length(&supported_methods)) {
            let method = *vector::borrow(&supported_methods, i);
            vec_set::insert(&mut service.supported_methods, method);
            
            // Set default fees for each method
            let default_fee = get_default_fee_for_method(method);
            table::add(&mut service.service_fees, method, default_fee);
            table::add(&mut service.turnaround_times, method, 86400000); // 1 day default
            
            i = i + 1;
        };
        
        let service_id = object::uid_to_inner(&service.id);
        
        // Update marketplace indices
        update_service_indices(marketplace, service_id, service_type, &specializations);
        marketplace.total_services = marketplace.total_services + 1;
        marketplace.active_services = marketplace.active_services + 1;
        
        event::emit(VerificationServiceRegistered {
            service_id,
            name,
            service_type,
            owner,
            supported_methods,
            timestamp: current_time,
        });
        
        transfer::share_object(service);
    }

    /// Request verification for a certificate
    public entry fun request_verification(
        marketplace: &mut VerificationMarketplace,
        analytics: &mut VerificationAnalytics,
        certificate_id: ID,
        verification_method: u8,
        urgency_level: u8,
        purpose: String,
        additional_context: String,
        required_completion_date: u64, // 0 if no specific date
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let requester = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(!marketplace.is_paused, E_SERVICE_SUSPENDED);
        
        // Calculate fees
        let service_fee = get_verification_fee(verification_method);
        let platform_fee = (service_fee * marketplace.platform_fee_rate) / 10000;
        let total_fee = service_fee + platform_fee;
        
        assert!(coin::value(&payment) >= total_fee, E_INSUFFICIENT_PAYMENT);
        
        // Create verification request
        let request = VerificationRequest {
            id: object::new(ctx),
            certificate_id,
            requester,
            verifier_service_id: option::none(),
            verification_method,
            urgency_level,
            purpose,
            additional_context,
            required_completion_date: if (required_completion_date > 0) { 
                option::some(required_completion_date) 
            } else { 
                option::none() 
            },
            payment: coin::into_balance(payment),
            service_fee,
            platform_fee,
            refund_policy: string::utf8(b"Full refund if verification fails"),
            status: STATUS_PENDING,
            assigned_verifier: option::none(),
            estimated_completion: option::none(),
            actual_completion: option::none(),
            verification_result: option::none(),
            verifier_notes: string::utf8(b""),
            confidence_score: 0,
            requested_at: current_time,
            assigned_at: option::none(),
            completed_at: option::none(),
            expires_at: current_time + VERIFICATION_TIMEOUT,
        };
        
        let request_id = object::uid_to_inner(&request.id);
        
        // Update marketplace statistics
        marketplace.total_requests = marketplace.total_requests + 1;
        marketplace.total_volume = marketplace.total_volume + total_fee;
        
        // Update analytics
        update_verification_analytics(analytics, verification_method, certificate_id, current_time);
        
        event::emit(VerificationRequested {
            request_id,
            certificate_id,
            requester,
            verification_method,
            payment_amount: total_fee,
            timestamp: current_time,
        });
        
        transfer::share_object(request);
    }

    /// Assign verification request to a service provider
    public entry fun assign_verification_request(
        request: &mut VerificationRequest,
        service: &mut VerificationService,
        marketplace: &mut VerificationMarketplace,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let verifier = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(service.owner == verifier, E_NOT_AUTHORIZED);
        assert!(service.is_active && service.is_verified, E_VERIFIER_NOT_APPROVED);
        assert!(request.status == STATUS_PENDING, E_VERIFICATION_REQUEST_NOT_FOUND);
        assert!(vec_set::contains(&service.supported_methods, &request.verification_method), E_INVALID_VERIFICATION_METHOD);
        
        // Assign request
        request.assigned_verifier = option::some(verifier);
        request.verifier_service_id = option::some(object::uid_to_inner(&service.id));
        request.status = STATUS_IN_PROGRESS;
        request.assigned_at = option::some(current_time);
        
        // Calculate estimated completion
        let estimated_duration = *table::borrow(&service.turnaround_times, request.verification_method);
        let estimated_completion = current_time + estimated_duration;
        request.estimated_completion = option::some(estimated_completion);
        
        // Update service metrics
        service.last_active = current_time;
        
        event::emit(VerificationAssigned {
            request_id: object::uid_to_inner(&request.id),
            verifier_service_id: object::uid_to_inner(&service.id),
            assigned_verifier: verifier,
            estimated_completion,
            timestamp: current_time,
        });
    }

    /// Complete verification and submit results
    public entry fun complete_verification(
        request: &mut VerificationRequest,
        service: &mut VerificationService,
        marketplace: &mut VerificationMarketplace,
        analytics: &mut VerificationAnalytics,
        certificate: &CertificateNFT,
        registry: &CertificateRegistry,
        is_authentic: bool,
        confidence_level: u8,
        risk_assessment: u8,
        verifier_notes: String,
        anomalies_detected: vector<String>,
        recommendations: vector<String>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let verifier = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(service.owner == verifier, E_NOT_AUTHORIZED);
        assert!(option::contains(&request.assigned_verifier, &verifier), E_NOT_AUTHORIZED);
        assert!(request.status == STATUS_IN_PROGRESS, E_VERIFICATION_REQUEST_NOT_FOUND);
        assert!(confidence_level <= 100, E_INVALID_VERIFICATION_DATA);
        
        // Perform comprehensive verification checks
        let verification_result = perform_comprehensive_verification(
            certificate,
            registry,
            request.verification_method,
            is_authentic,
            confidence_level,
            risk_assessment,
            anomalies_detected,
            recommendations,
            clock,
        );
        
        // Update request with results
        request.verification_result = option::some(verification_result);
        request.verifier_notes = verifier_notes;
        request.confidence_score = confidence_level;
        request.status = STATUS_COMPLETED;
        request.completed_at = option::some(current_time);
        request.actual_completion = option::some(current_time);
        
        // Calculate completion time
        let completion_time = if (option::is_some(&request.assigned_at)) {
            current_time - *option::borrow(&request.assigned_at)
        } else {
            0
        };
        
        // Update service metrics
        service.total_verifications = service.total_verifications + 1;
        if (is_authentic) {
            service.successful_verifications = service.successful_verifications + 1;
        };
        update_service_completion_time(service, completion_time);
        
        // Process payment
        let service_payment = balance::split(&mut request.payment, request.service_fee);
        balance::join(&mut service.pending_payments, service_payment);
        balance::join(&mut marketplace.treasury, balance::withdraw_all(&mut request.payment));
        
        service.total_earnings = service.total_earnings + request.service_fee;
        marketplace.platform_revenue = marketplace.platform_revenue + request.platform_fee;
        marketplace.service_provider_earnings = marketplace.service_provider_earnings + request.service_fee;
        marketplace.completed_verifications = marketplace.completed_verifications + 1;
        
        // Update analytics
        update_completion_analytics(analytics, request.verification_method, completion_time, is_authentic);
        
        // Fraud detection
        if (risk_assessment >= RISK_LEVEL_HIGH || !is_authentic) {
            handle_fraud_detection(analytics, request.certificate_id, risk_assessment, verifier);
        };
        
        event::emit(VerificationCompleted {
            request_id: object::uid_to_inner(&request.id),
            certificate_id: request.certificate_id,
            verifier,
            is_authentic,
            confidence_level,
            completion_time,
            timestamp: current_time,
        });
    }

    /// Dispute a verification result
    public entry fun dispute_verification(
        request: &VerificationRequest,
        dispute_reason: String,
        evidence: vector<String>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let disputer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(request.requester == disputer, E_NOT_AUTHORIZED);
        assert!(request.status == STATUS_COMPLETED, E_VERIFICATION_REQUEST_NOT_FOUND);
        assert!(current_time <= (*option::borrow(&request.completed_at) + DISPUTE_PERIOD), E_VERIFICATION_EXPIRED);
        
        let dispute = VerificationDispute {
            id: object::new(ctx),
            verification_request_id: object::uid_to_inner(&request.id),
            disputer,
            dispute_reason,
            evidence,
            assigned_arbitrator: option::none(),
            arbitrator_decision: option::none(),
            resolution_status: 0, // Pending
            refund_amount: 0,
            penalty_amount: 0,
            filed_at: current_time,
            resolved_at: option::none(),
            expires_at: current_time + (DISPUTE_PERIOD * 2), // 6 days to resolve
        };
        
        let dispute_id = object::uid_to_inner(&dispute.id);
        
        event::emit(VerificationDisputed {
            dispute_id,
            verification_request_id: object::uid_to_inner(&request.id),
            disputer,
            reason: dispute_reason,
            timestamp: current_time,
        });
        
        transfer::share_object(dispute);
    }

    // =============== Internal Helper Functions ===============

    fun update_service_indices(
        marketplace: &mut VerificationMarketplace,
        service_id: ID,
        service_type: u8,
        specializations: &vector<String>,
    ) {
        // Update type index
        if (!table::contains(&marketplace.services_by_type, service_type)) {
            table::add(&mut marketplace.services_by_type, service_type, vec_set::empty());
        };
        let type_set = table::borrow_mut(&mut marketplace.services_by_type, service_type);
        vec_set::insert(type_set, service_id);
        
        // Update specialization indices
        let mut i = 0;
        while (i < vector::length(specializations)) {
            let specialization = vector::borrow(specializations, i);
            if (!table::contains(&marketplace.services_by_specialization, *specialization)) {
                table::add(&mut marketplace.services_by_specialization, *specialization, vec_set::empty());
            };
            let spec_set = table::borrow_mut(&mut marketplace.services_by_specialization, *specialization);
            vec_set::insert(spec_set, service_id);
            i = i + 1;
        };
    }

    fun get_default_fee_for_method(method: u8): u64 {
        if (method == METHOD_BASIC_CHECK) {
            BASIC_VERIFICATION_FEE
        } else if (method == METHOD_COMPREHENSIVE) {
            COMPREHENSIVE_VERIFICATION_FEE
        } else if (method == METHOD_FORENSIC) {
            FORENSIC_VERIFICATION_FEE
        } else if (method == METHOD_THIRD_PARTY) {
            THIRD_PARTY_VERIFICATION_FEE
        } else if (method == METHOD_EMPLOYER_VERIFICATION) {
            EMPLOYER_VERIFICATION_FEE
        } else {
            BASIC_VERIFICATION_FEE
        }
    }

    fun get_verification_fee(method: u8): u64 {
        get_default_fee_for_method(method)
    }

    fun update_verification_analytics(
        analytics: &mut VerificationAnalytics,
        method: u8,
        certificate_id: ID,
        timestamp: u64,
    ) {
        // Update method usage
        if (table::contains(&analytics.verifications_by_method, method)) {
            let count = table::borrow_mut(&mut analytics.verifications_by_method, method);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.verifications_by_method, method, 1);
        };
        
        // Update daily trends
        let day_epoch = timestamp / 86400000;
        if (table::contains(&analytics.verifications_by_day, day_epoch)) {
            let count = table::borrow_mut(&mut analytics.verifications_by_day, day_epoch);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.verifications_by_day, day_epoch, 1);
        };
        
        analytics.last_updated = timestamp;
    }

    fun perform_comprehensive_verification(
        certificate: &CertificateNFT,
        registry: &CertificateRegistry,
        method: u8,
        is_authentic: bool,
        confidence_level: u8,
        risk_assessment: u8,
        anomalies_detected: vector<String>,
        recommendations: vector<String>,
        clock: &Clock,
    ): VerificationResult {
        // Basic certificate validation
        let certificate_integrity = certificates::is_certificate_valid(certificate, clock);
        let issuer_verification = true; // Would check against authorized issuers
        let recipient_verification = true; // Would verify recipient identity
        let metadata_consistency = true; // Would check metadata consistency
        let blockchain_validation = registry::is_certificate_registered(registry, object::id(certificate));
        let third_party_confirmation = method >= METHOD_THIRD_PARTY;
        
        VerificationResult {
            is_authentic,
            is_valid: certificate_integrity && blockchain_validation,
            confidence_level,
            risk_assessment,
            certificate_integrity,
            issuer_verification,
            recipient_verification,
            metadata_consistency,
            blockchain_validation,
            third_party_confirmation,
            anomalies_detected,
            verification_method_used: get_method_name(method),
            external_references: vector::empty(),
            digital_fingerprint: option::none(),
            creation_metadata: string::utf8(b""),
            modification_history: vector::empty(),
            recommendations,
            follow_up_required: risk_assessment >= RISK_LEVEL_HIGH,
            validity_period: option::some(31536000000), // 1 year
        }
    }

    fun get_method_name(method: u8): String {
        if (method == METHOD_BASIC_CHECK) {
            string::utf8(b"Basic Verification")
        } else if (method == METHOD_COMPREHENSIVE) {
            string::utf8(b"Comprehensive Verification")
        } else if (method == METHOD_FORENSIC) {
            string::utf8(b"Forensic Analysis")
        } else if (method == METHOD_THIRD_PARTY) {
            string::utf8(b"Third-Party Verification")
        } else if (method == METHOD_EMPLOYER_VERIFICATION) {
            string::utf8(b"Employer Verification")
        } else {
            string::utf8(b"Unknown Method")
        }
    }

    fun update_service_completion_time(service: &mut VerificationService, completion_time: u64) {
        if (service.total_verifications == 0) {
            service.average_completion_time = completion_time;
        } else {
            service.average_completion_time = 
                (service.average_completion_time * (service.total_verifications - 1) + completion_time) / 
                service.total_verifications;
        };
    }

    fun update_completion_analytics(
        analytics: &mut VerificationAnalytics,
        method: u8,
        completion_time: u64,
        success: bool,
    ) {
        // Update average completion time by method
        if (table::contains(&analytics.average_verification_time, method)) {
            let current_avg = table::borrow_mut(&mut analytics.average_verification_time, method);
            *current_avg = (*current_avg + completion_time) / 2; // Simplified average
        } else {
            table::add(&mut analytics.average_verification_time, method, completion_time);
        };
        
        // Update success rates
        if (table::contains(&analytics.success_rates_by_type, method)) {
            let current_rate = table::borrow_mut(&mut analytics.success_rates_by_type, method);
            if (success) {
                *current_rate = (*current_rate + 100) / 2; // Simplified success rate calculation
            } else {
                *current_rate = (*current_rate + 0) / 2;
            };
        } else {
            table::add(&mut analytics.success_rates_by_type, method, if (success) { 100 } else { 0 });
        };
    }

    fun handle_fraud_detection(
        analytics: &mut VerificationAnalytics,
        certificate_id: ID,
        risk_level: u8,
        detector: address,
    ) {
        if (risk_level >= RISK_LEVEL_CRITICAL) {
            vec_set::insert(&mut analytics.blacklisted_certificates, certificate_id);
        };
        
        if (risk_level >= RISK_LEVEL_HIGH) {
            vec_set::insert(&mut analytics.high_risk_verifications, certificate_id);
        };
        
        analytics.fraud_alerts = analytics.fraud_alerts + 1;
        
        let fraud_type = if (risk_level == RISK_LEVEL_CRITICAL) {
            string::utf8(b"Critical_Fraud")
        } else if (risk_level == RISK_LEVEL_HIGH) {
            string::utf8(b"High_Risk_Activity")
        } else {
            string::utf8(b"Suspicious_Pattern")
        };
        
        event::emit(FraudDetected {
            certificate_id,
            fraud_type,
            confidence_level: (risk_level as u8) * 25, // Convert to percentage
            detected_by: detector,
            timestamp: 0, // Would use actual timestamp
        });
    }

    // =============== View Functions ===============

    public fun get_service_info(service: &VerificationService): (String, u8, u64, u64, bool) {
        (
            service.name,
            service.service_type,
            service.total_verifications,
            service.reputation_score,
            service.is_active
        )
    }

    public fun get_service_fees(service: &VerificationService, method: u8): u64 {
        if (table::contains(&service.service_fees, method)) {
            *table::borrow(&service.service_fees, method)
        } else {
            0
        }
    }

    public fun get_verification_request_status(request: &VerificationRequest): (u8, Option<address>, Option<u64>) {
        (request.status, request.assigned_verifier, request.completed_at)
    }

    public fun get_verification_result(request: &VerificationRequest): &Option<VerificationResult> {
        &request.verification_result
    }

    public fun get_marketplace_stats(marketplace: &VerificationMarketplace): (u64, u64, u64, u64) {
        (
            marketplace.total_services,
            marketplace.active_services,
            marketplace.total_requests,
            marketplace.completed_verifications
        )
    }

    public fun get_services_by_type(marketplace: &VerificationMarketplace, service_type: u8): vector<ID> {
        if (table::contains(&marketplace.services_by_type, service_type)) {
            vec_set::into_keys(*table::borrow(&marketplace.services_by_type, service_type))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_fraud_statistics(analytics: &VerificationAnalytics): (u64, u64, u64) {
        (
            analytics.fraud_alerts,
            vec_set::size(&analytics.blacklisted_certificates),
            vec_set::size(&analytics.high_risk_verifications)
        )
    }

    public fun is_certificate_blacklisted(analytics: &VerificationAnalytics, certificate_id: ID): bool {
        vec_set::contains(&analytics.blacklisted_certificates, &certificate_id)
    }

    public fun get_verification_method_stats(analytics: &VerificationAnalytics, method: u8): (u64, u64) {
        let usage_count = if (table::contains(&analytics.verifications_by_method, method)) {
            *table::borrow(&analytics.verifications_by_method, method)
        } else {
            0
        };
        
        let avg_time = if (table::contains(&analytics.average_verification_time, method)) {
            *table::borrow(&analytics.average_verification_time, method)
        } else {
            0
        };
        
        (usage_count, avg_time)
    }
}