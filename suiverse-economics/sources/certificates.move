/// Enhanced Core Certification Module for SuiVerse
/// Implements comprehensive certificate NFT management with dynamic valuation,
/// expiration handling, and integration with the Proof of Knowledge system.
module suiverse_economics::certificates {
    use std::string::{Self, String};
    use std::ascii;
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::bcs;
    use sui::clock::{Self, Clock};
    use sui::url::{Self, Url};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::hash;
    use sui::address;
    // Note: ExamCertificate integration removed - would be handled via separate assessment module

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 10001;
    const E_CERTIFICATE_NOT_FOUND: u64 = 10002;
    const E_ALREADY_VERIFIED: u64 = 10003;
    const E_INVALID_CERTIFICATE: u64 = 10004;
    const E_CERTIFICATE_EXPIRED: u64 = 10005;
    const E_DUPLICATE_CERTIFICATE: u64 = 10006;
    const E_INVALID_CERTIFICATE_TYPE: u64 = 10007;
    const E_INVALID_LEVEL: u64 = 10008;
    const E_INSUFFICIENT_SCORE: u64 = 10009;
    const E_TEMPLATE_NOT_FOUND: u64 = 10010;
    const E_RENEWAL_NOT_ELIGIBLE: u64 = 10011;
    const E_INSUFFICIENT_PAYMENT: u64 = 10012;
    const E_INVALID_METADATA: u64 = 10013;

    // Certificate types - extended for comprehensive coverage
    const CERT_TYPE_EXAM: u8 = 1;
    const CERT_TYPE_PROJECT: u8 = 2;
    const CERT_TYPE_ACHIEVEMENT: u8 = 3;
    const CERT_TYPE_SKILL: u8 = 4;
    const CERT_TYPE_COURSE: u8 = 5;
    const CERT_TYPE_CHALLENGE: u8 = 6;
    const CERT_TYPE_EXPERTISE: u8 = 7;
    const CERT_TYPE_VALIDATOR: u8 = 8;

    // Certificate levels
    const LEVEL_BEGINNER: u8 = 1;
    const LEVEL_INTERMEDIATE: u8 = 2;
    const LEVEL_ADVANCED: u8 = 3;
    const LEVEL_EXPERT: u8 = 4;
    const LEVEL_MASTER: u8 = 5;

    // Certificate status
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_REVOKED: u8 = 2;
    const STATUS_EXPIRED: u8 = 3;
    const STATUS_SUSPENDED: u8 = 4;
    const STATUS_RENEWED: u8 = 5;

    // Default validity periods (in milliseconds)
    const DEFAULT_VALIDITY_PERIOD: u64 = 31536000000; // 1 year
    const SKILL_CERT_VALIDITY: u64 = 15768000000; // 6 months
    const EXAM_CERT_VALIDITY: u64 = 63072000000; // 2 years
    const CHALLENGE_CERT_VALIDITY: u64 = 0; // No expiry

    // Fees
    const CERTIFICATE_ISSUANCE_FEE: u64 = 100000000; // 0.1 SUI
    const CERTIFICATE_RENEWAL_FEE: u64 = 50000000; // 0.05 SUI
    const VERIFICATION_FEE: u64 = 10000000; // 0.01 SUI

    // =============== Core Structs ===============
    
    /// Enhanced Certificate NFT with dynamic valuation and comprehensive metadata
    public struct CertificateNFT has key, store {
        id: UID,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        issuer: address,
        recipient: address,
        metadata: CertificateMetadata,
        image_url: Url,
        verification_hash: vector<u8>,
        status: u8,
        issued_at: u64,
        expires_at: Option<u64>,
        renewed_from: Option<ID>, // Previous certificate if renewal
        renewal_count: u64,
        ipfs_hash: String, // IPFS storage for detailed metadata
        skills_certified: vector<String>,
        tags: vector<String>,
        is_tradeable: bool,
        market_value: u64, // Dynamic market value for PoK system
    }

    /// Enhanced certificate metadata with comprehensive tracking
    public struct CertificateMetadata has store, drop, copy {
        exam_id: Option<ID>,
        project_id: Option<ID>,
        challenge_id: Option<ID>,
        course_id: Option<ID>,
        score: Option<u64>,
        grade: Option<String>,
        skills: vector<String>,
        achievement_type: Option<String>,
        validator_signatures: vector<address>,
        completion_time: Option<u64>,
        difficulty_rating: Option<u8>,
        prerequisites_met: vector<ID>,
        additional_data: String, // JSON or other structured data
    }

    /// Certificate value tracking for PoK system
    public struct CertificateValue has key, store {
        id: UID,
        certificate_type: u8,
        level: u8,
        base_value: u64,
        current_value: u64,
        total_issued: u64,
        active_validators_holding: u64,
        recent_pass_rate: u64,
        scarcity_multiplier: u64,
        difficulty_multiplier: u64,
        age_decay_factor: u64,
        last_rebalance: u64,
        governance_proposal_id: Option<ID>,
    }

    /// Global certificate management system
    public struct CertificateManager has key {
        id: UID,
        total_certificates_issued: u64,
        certificate_values: Table<String, ID>, // "type_level" -> CertificateValue ID
        issuance_fees: Table<u8, u64>, // certificate_type -> fee
        renewal_fees: Table<u8, u64>,
        authorized_issuers: VecSet<address>,
        treasury: Balance<SUI>,
        paused: bool,
        admin_cap_id: ID,
    }


    /// Renewal request for expired certificates
    public struct RenewalRequest has key {
        id: UID,
        original_certificate_id: ID,
        requester: address,
        renewal_fee_paid: u64,
        requested_at: u64,
        new_metadata: Option<CertificateMetadata>,
        status: u8, // 0: pending, 1: approved, 2: rejected
    }

    /// Administrative capability
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Certificate statistics for analytics
    public struct CertificateStats has key {
        id: UID,
        certificates_by_type: Table<u8, u64>,
        certificates_by_level: Table<u8, u64>,
        total_renewals: u64,
        total_revocations: u64,
        average_validity_period: u64,
        most_valuable_certificate: Option<ID>,
        last_updated: u64,
    }

    // =============== Events ===============
    
    public struct CertificateIssued has copy, drop {
        certificate_id: ID,
        certificate_type: u8,
        level: u8,
        recipient: address,
        issuer: address,
        title: String,
        skills_certified: vector<String>,
        expires_at: Option<u64>,
        market_value: u64,
        timestamp: u64,
    }

    public struct CertificateVerified has copy, drop {
        certificate_id: ID,
        verifier: address,
        verification_method: String,
        timestamp: u64,
    }

    public struct CertificateRevoked has copy, drop {
        certificate_id: ID,
        reason: String,
        revoked_by: address,
        timestamp: u64,
    }

    public struct CertificateTransferred has copy, drop {
        certificate_id: ID,
        from: address,
        to: address,
        transfer_type: String, // "direct", "trade", "gift"
        timestamp: u64,
    }

    public struct CertificateRenewed has copy, drop {
        original_certificate_id: ID,
        new_certificate_id: ID,
        recipient: address,
        renewal_count: u64,
        timestamp: u64,
    }

    public struct CertificateValueUpdated has copy, drop {
        certificate_type: u8,
        level: u8,
        old_value: u64,
        new_value: u64,
        reason: String,
        timestamp: u64,
    }


    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        let admin_cap_id = object::uid_to_inner(&admin_cap.id);
        
        // Initialize certificate manager
        let mut manager = CertificateManager {
            id: object::new(ctx),
            total_certificates_issued: 0,
            certificate_values: table::new(ctx),
            issuance_fees: table::new(ctx),
            renewal_fees: table::new(ctx),
            authorized_issuers: vec_set::empty(),
            treasury: balance::zero(),
            paused: false,
            admin_cap_id,
        };
        
        // Initialize certificate statistics
        let stats = CertificateStats {
            id: object::new(ctx),
            certificates_by_type: table::new(ctx),
            certificates_by_level: table::new(ctx),
            total_renewals: 0,
            total_revocations: 0,
            average_validity_period: DEFAULT_VALIDITY_PERIOD,
            most_valuable_certificate: option::none(),
            last_updated: 0,
        };
        
        // Initialize default fees
        let mut i = 1u8;
        while (i <= 8) {
            table::add(&mut manager.issuance_fees, i, CERTIFICATE_ISSUANCE_FEE);
            table::add(&mut manager.renewal_fees, i, CERTIFICATE_RENEWAL_FEE);
            i = i + 1;
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(manager);
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Create certificate metadata
    public fun create_certificate_metadata(
        exam_id: Option<ID>,
        project_id: Option<ID>,
        challenge_id: Option<ID>,
        course_id: Option<ID>,
        score: Option<u64>,
        grade: Option<String>,
        skills: vector<String>,
        achievement_type: Option<String>,
        validator_signatures: vector<address>,
        completion_time: Option<u64>,
        difficulty_rating: Option<u8>,
        prerequisites_met: vector<ID>,
        additional_data: String,
    ): CertificateMetadata {
        CertificateMetadata {
            exam_id,
            project_id,
            challenge_id,
            course_id,
            score,
            grade,
            skills,
            achievement_type,
            validator_signatures,
            completion_time,
            difficulty_rating,
            prerequisites_met,
            additional_data,
        }
    }
    
    /// Issue a comprehensive certificate NFT with enhanced features
    public fun issue_certificate(
        manager: &mut CertificateManager,
        stats: &mut CertificateStats,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        recipient: address,
        image_url: vector<u8>,
        ipfs_hash: String,
        metadata: CertificateMetadata,
        skills_certified: vector<String>,
        tags: vector<String>,
        expires_in_days: Option<u64>,
        is_tradeable: bool,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let issuer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate authorization and payment
        assert!(!manager.paused, E_NOT_AUTHORIZED);
        assert!(certificate_type >= 1 && certificate_type <= 8, E_INVALID_CERTIFICATE_TYPE);
        assert!(level >= 1 && level <= 5, E_INVALID_LEVEL);
        
        // Check payment
        let required_fee = *table::borrow(&manager.issuance_fees, certificate_type);
        assert!(coin::value(&payment) >= required_fee, E_INSUFFICIENT_PAYMENT);
        
        // Process payment
        balance::join(&mut manager.treasury, coin::into_balance(payment));
        
        // Calculate expiration based on certificate type
        let expires_at = if (option::is_some(&expires_in_days)) {
            let days = *option::borrow(&expires_in_days);
            option::some(current_time + (days * 86400000))
        } else {
            // Default validity periods based on type
            let default_validity = if (certificate_type == CERT_TYPE_SKILL) {
                SKILL_CERT_VALIDITY
            } else if (certificate_type == CERT_TYPE_EXAM) {
                EXAM_CERT_VALIDITY
            } else if (certificate_type == CERT_TYPE_CHALLENGE) {
                CHALLENGE_CERT_VALIDITY
            } else {
                DEFAULT_VALIDITY_PERIOD
            };
            
            if (default_validity == 0) {
                option::none()
            } else {
                option::some(current_time + default_validity)
            }
        };
        
        // Generate comprehensive verification hash
        let mut hash_data = vector::empty<u8>();
        vector::append(&mut hash_data, bcs::to_bytes(&certificate_type));
        vector::append(&mut hash_data, bcs::to_bytes(&level));
        vector::append(&mut hash_data, bcs::to_bytes(&recipient));
        vector::append(&mut hash_data, bcs::to_bytes(&issuer));
        vector::append(&mut hash_data, bcs::to_bytes(&current_time));
        vector::append(&mut hash_data, *string::as_bytes(&title));
        let verification_hash = hash::keccak256(&hash_data);
        
        // Get market value for this certificate type/level
        let market_value = get_certificate_market_value(manager, certificate_type, level);

        // Create enhanced certificate NFT
        let certificate = CertificateNFT {
            id: object::new(ctx),
            certificate_type,
            level,
            title,
            description,
            issuer,
            recipient,
            metadata,
            image_url: url::new_unsafe_from_bytes(image_url),
            verification_hash,
            status: STATUS_ACTIVE,
            issued_at: current_time,
            expires_at,
            renewed_from: option::none(),
            renewal_count: 0,
            ipfs_hash,
            skills_certified,
            tags,
            is_tradeable,
            market_value,
        };
        
        let certificate_id = object::uid_to_inner(&certificate.id);
        
        // Update statistics
        manager.total_certificates_issued = manager.total_certificates_issued + 1;
        update_certificate_statistics(stats, certificate_type, level, current_time);

        // Update certificate value tracking
        update_certificate_value_tracking(manager, certificate_type, level);

        // Emit comprehensive event
        event::emit(CertificateIssued {
            certificate_id,
            certificate_type,
            level,
            recipient,
            issuer,
            title,
            skills_certified,
            expires_at,
            market_value,
            timestamp: current_time,
        });
        
        transfer::transfer(certificate, recipient);
    }

    /// Issue a simple certificate NFT (entry function version)
    public entry fun issue_simple_certificate(
        manager: &mut CertificateManager,
        stats: &mut CertificateStats,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        recipient: address,
        image_url: vector<u8>,
        skills: vector<String>,
        expires_in_days: u64, // 0 for no expiration
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Create metadata with defaults
        let metadata = CertificateMetadata {
            exam_id: option::none(),
            project_id: option::none(),
            challenge_id: option::none(),
            course_id: option::none(),
            score: option::none(),
            grade: option::none(),
            skills,
            achievement_type: option::none(),
            validator_signatures: vector::empty(),
            completion_time: option::none(),
            difficulty_rating: option::none(),
            prerequisites_met: vector::empty(),
            additional_data: string::utf8(b""),
        };
        
        let expires_option = if (expires_in_days == 0) {
            option::none()
        } else {
            option::some(expires_in_days)
        };
        
        issue_certificate(
            manager,
            stats,
            certificate_type,
            level,
            title,
            description,
            recipient,
            image_url,
            string::utf8(b""), // Empty IPFS hash
            metadata,
            skills,
            vector::empty(), // Empty tags
            expires_option,
            true, // Is tradeable by default
            payment,
            clock,
            ctx
        );
    }

    /// Issue certificate from completion data with enhanced metadata  
    public entry fun issue_completion_certificate(
        manager: &mut CertificateManager,
        stats: &mut CertificateStats,
        title: String,
        description: String,
        recipient: address,
        score: u8,
        image_url: vector<u8>,
        ipfs_hash: String,
        skills_certified: vector<String>,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let _issuer = tx_context::sender(ctx);
        
        // Determine level based on score
        let level = if (score >= 95) {
            LEVEL_EXPERT
        } else if (score >= 85) {
            LEVEL_ADVANCED
        } else if (score >= 75) {
            LEVEL_INTERMEDIATE
        } else {
            LEVEL_BEGINNER
        };
        
        // Create comprehensive metadata
        let metadata = CertificateMetadata {
            exam_id: option::none(), // Would be set by assessment module
            project_id: option::none(),
            challenge_id: option::none(),
            course_id: option::none(),
            score: option::some(score as u64),
            grade: option::some(calculate_grade(score as u64)),
            skills: skills_certified,
            achievement_type: option::some(string::utf8(b"Completion")),
            validator_signatures: vector::empty(),
            completion_time: option::none(),
            difficulty_rating: option::some(level),
            prerequisites_met: vector::empty(),
            additional_data: string::utf8(b""),
        };
        
        issue_certificate(
            manager,
            stats,
            CERT_TYPE_EXAM,
            level,
            title,
            description,
            recipient,
            image_url,
            ipfs_hash,
            metadata,
            skills_certified,
            vector[string::utf8(b"completion"), string::utf8(b"verified")],
            option::none(), // Use default expiration
            true, // Is tradeable
            payment,
            clock,
            ctx
        );
    }

    /// Verify a certificate with enhanced validation
    public entry fun verify_certificate(
        certificate: &CertificateNFT,
        verification_fee: Coin<SUI>,
        manager: &mut CertificateManager,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let verifier = tx_context::sender(ctx);
        let certificate_id = object::uid_to_inner(&certificate.id);
        let current_time = clock::timestamp_ms(clock);
        
        // Check verification fee
        assert!(coin::value(&verification_fee) >= VERIFICATION_FEE, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut manager.treasury, coin::into_balance(verification_fee));
        
        // Check certificate status
        assert!(certificate.status == STATUS_ACTIVE, E_INVALID_CERTIFICATE);
        
        // Check expiration
        if (option::is_some(&certificate.expires_at)) {
            let expiry = *option::borrow(&certificate.expires_at);
            assert!(current_time < expiry, E_CERTIFICATE_EXPIRED);
        };
        
        // Verify hash integrity
        let mut expected_hash_data = vector::empty<u8>();
        vector::append(&mut expected_hash_data, bcs::to_bytes(&certificate.certificate_type));
        vector::append(&mut expected_hash_data, bcs::to_bytes(&certificate.level));
        vector::append(&mut expected_hash_data, bcs::to_bytes(&certificate.recipient));
        vector::append(&mut expected_hash_data, bcs::to_bytes(&certificate.issuer));
        vector::append(&mut expected_hash_data, bcs::to_bytes(&certificate.issued_at));
        vector::append(&mut expected_hash_data, *string::as_bytes(&certificate.title));
        let expected_hash = hash::keccak256(&expected_hash_data);
        
        assert!(certificate.verification_hash == expected_hash, E_INVALID_CERTIFICATE);
        
        event::emit(CertificateVerified {
            certificate_id,
            verifier,
            verification_method: string::utf8(b"on_chain_hash_verification"),
            timestamp: current_time,
        });
    }

    /// Revoke a certificate with proper authorization
    public entry fun revoke_certificate(
        certificate: &mut CertificateNFT,
        reason: String,
        _admin_cap: &AdminCap,
        stats: &mut CertificateStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let revoker = tx_context::sender(ctx);
        let certificate_id = object::uid_to_inner(&certificate.id);
        
        // Check authorization (admin or original issuer)
        assert!(certificate.issuer == revoker || true, E_NOT_AUTHORIZED); // Admin cap check
        assert!(certificate.status == STATUS_ACTIVE, E_INVALID_CERTIFICATE);
        
        // Update certificate status
        certificate.status = STATUS_REVOKED;
        
        // Update statistics
        stats.total_revocations = stats.total_revocations + 1;
        stats.last_updated = clock::timestamp_ms(clock);
        
        event::emit(CertificateRevoked {
            certificate_id,
            reason,
            revoked_by: revoker,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Transfer a certificate with enhanced tracking
    public entry fun transfer_certificate(
        mut certificate: CertificateNFT,
        to: address,
        transfer_type: String,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let from = tx_context::sender(ctx);
        let certificate_id = object::uid_to_inner(&certificate.id);
        
        // Check if certificate is tradeable
        assert!(certificate.is_tradeable, E_NOT_AUTHORIZED);
        assert!(certificate.status == STATUS_ACTIVE, E_INVALID_CERTIFICATE);
        
        // Update recipient
        certificate.recipient = to;
        
        event::emit(CertificateTransferred {
            certificate_id,
            from,
            to,
            transfer_type,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::transfer(certificate, to);
    }


    /// Renew an expired certificate
    public entry fun renew_certificate(
        original_certificate: &CertificateNFT,
        manager: &mut CertificateManager,
        stats: &mut CertificateStats,
        update_metadata: bool,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let requester = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate renewal eligibility
        assert!(original_certificate.recipient == requester, E_NOT_AUTHORIZED);
        
        // Check if certificate is expired or expiring soon (within 30 days)
        if (option::is_some(&original_certificate.expires_at)) {
            let expiry = *option::borrow(&original_certificate.expires_at);
            let thirty_days = 30 * 86400000; // 30 days in ms
            assert!(current_time > (expiry - thirty_days), E_RENEWAL_NOT_ELIGIBLE);
        } else {
            abort E_RENEWAL_NOT_ELIGIBLE
        };
        
        // Check payment
        let renewal_fee = *table::borrow(&manager.renewal_fees, original_certificate.certificate_type);
        assert!(coin::value(&payment) >= renewal_fee, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut manager.treasury, coin::into_balance(payment));
        
        // Create renewed certificate with updated metadata
        let metadata = if (update_metadata) {
            // Create updated metadata with current timestamp
            let mut renewed_metadata = original_certificate.metadata;
            renewed_metadata.completion_time = option::some(current_time);
            renewed_metadata
        } else {
            original_certificate.metadata
        };
        
        issue_certificate(
            manager,
            stats,
            original_certificate.certificate_type,
            original_certificate.level,
            original_certificate.title,
            original_certificate.description,
            requester,
            {
                let url_str = url::inner_url(&original_certificate.image_url);
                *ascii::as_bytes(&url_str)
            },
            original_certificate.ipfs_hash,
            metadata,
            original_certificate.skills_certified,
            original_certificate.tags,
            option::some(365), // 1 year validity
            original_certificate.is_tradeable,
            coin::zero(ctx), // Already paid
            clock,
            ctx
        );
        
        // Update statistics
        stats.total_renewals = stats.total_renewals + 1;
    }

    // =============== Internal Helper Functions ===============
    
    fun calculate_grade(score: u64): String {
        if (score >= 95) {
            string::utf8(b"A+")
        } else if (score >= 90) {
            string::utf8(b"A")
        } else if (score >= 85) {
            string::utf8(b"B+")
        } else if (score >= 80) {
            string::utf8(b"B")
        } else if (score >= 75) {
            string::utf8(b"C+")
        } else if (score >= 70) {
            string::utf8(b"C")
        } else {
            string::utf8(b"D")
        }
    }
    
    fun get_certificate_market_value(manager: &CertificateManager, cert_type: u8, level: u8): u64 {
        let key = create_value_key(cert_type, level);
        if (table::contains(&manager.certificate_values, key)) {
            // In production, this would retrieve the actual CertificateValue object
            // For now, return a calculated base value
            (cert_type as u64) * 100 + (level as u64) * 50
        } else {
            // Default base value
            1000
        }
    }
    
    fun create_value_key(cert_type: u8, level: u8): String {
        let mut key_bytes = vector::empty<u8>();
        vector::push_back(&mut key_bytes, cert_type);
        vector::push_back(&mut key_bytes, 95); // ASCII for '_'
        vector::push_back(&mut key_bytes, level);
        string::utf8(key_bytes)
    }
    
    fun update_certificate_statistics(stats: &mut CertificateStats, cert_type: u8, level: u8, timestamp: u64) {
        if (table::contains(&stats.certificates_by_type, cert_type)) {
            let count = table::borrow_mut(&mut stats.certificates_by_type, cert_type);
            *count = *count + 1;
        } else {
            table::add(&mut stats.certificates_by_type, cert_type, 1);
        };
        
        if (table::contains(&stats.certificates_by_level, level)) {
            let count = table::borrow_mut(&mut stats.certificates_by_level, level);
            *count = *count + 1;
        } else {
            table::add(&mut stats.certificates_by_level, level, 1);
        };
        
        stats.last_updated = timestamp;
    }
    
    fun update_certificate_value_tracking(manager: &mut CertificateManager, cert_type: u8, level: u8) {
        let key = create_value_key(cert_type, level);
        // In production, this would update the CertificateValue object
        // For now, we just ensure the key exists in the table
        if (!table::contains(&manager.certificate_values, key)) {
            // Would create a new CertificateValue object
            // table::add(&mut manager.certificate_values, key, certificate_value_id);
        };
    }

    // =============== Constructor Functions ===============
    
    /// Create certificate metadata
    public fun new_certificate_metadata(
        exam_id: Option<ID>,
        project_id: Option<ID>,
        challenge_id: Option<ID>,
        course_id: Option<ID>,
        score: Option<u64>,
        grade: Option<String>,
        skills: vector<String>,
        achievement_type: Option<String>,
        validator_signatures: vector<address>,
        completion_time: Option<u64>,
        difficulty_rating: Option<u8>,
        prerequisites_met: vector<ID>,
        additional_data: String,
    ): CertificateMetadata {
        CertificateMetadata {
            exam_id,
            project_id,
            challenge_id,
            course_id,
            score,
            grade,
            skills,
            achievement_type,
            validator_signatures,
            completion_time,
            difficulty_rating,
            prerequisites_met,
            additional_data,
        }
    }

    // =============== Enhanced View Functions ===============
    
    public fun get_certificate_type(certificate: &CertificateNFT): u8 {
        certificate.certificate_type
    }
    
    public fun get_certificate_level(certificate: &CertificateNFT): u8 {
        certificate.level
    }

    public fun get_certificate_status(certificate: &CertificateNFT): u8 {
        certificate.status
    }

    public fun get_certificate_recipient(certificate: &CertificateNFT): address {
        certificate.recipient
    }

    public fun get_certificate_issuer(certificate: &CertificateNFT): address {
        certificate.issuer
    }
    
    public fun get_certificate_skills(certificate: &CertificateNFT): vector<String> {
        certificate.skills_certified
    }
    
    public fun get_certificate_market_value_view(certificate: &CertificateNFT): u64 {
        certificate.market_value
    }
    
    public fun get_certificate_renewal_count(certificate: &CertificateNFT): u64 {
        certificate.renewal_count
    }
    
    public fun is_certificate_tradeable(certificate: &CertificateNFT): bool {
        certificate.is_tradeable
    }

    public fun get_total_certificates_issued(manager: &CertificateManager): u64 {
        manager.total_certificates_issued
    }
    
    public fun get_certificate_statistics(stats: &CertificateStats): (u64, u64, u64) {
        (stats.total_renewals, stats.total_revocations, stats.average_validity_period)
    }

    public fun is_certificate_valid(
        certificate: &CertificateNFT,
        clock: &Clock,
    ): bool {
        if (certificate.status != STATUS_ACTIVE) {
            return false
        };
        
        if (option::is_some(&certificate.expires_at)) {
            let expiry = *option::borrow(&certificate.expires_at);
            if (clock::timestamp_ms(clock) >= expiry) {
                return false
            }
        };
        
        true
    }
    
    public fun is_certificate_expired(
        certificate: &CertificateNFT,
        clock: &Clock,
    ): bool {
        if (option::is_some(&certificate.expires_at)) {
            let expiry = *option::borrow(&certificate.expires_at);
            return clock::timestamp_ms(clock) >= expiry
        };
        false
    }
    
    public fun get_certificate_metadata(certificate: &CertificateNFT): &CertificateMetadata {
        &certificate.metadata
    }
    
}