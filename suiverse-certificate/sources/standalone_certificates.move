/// Standalone Certificate Module for testing DOF Config Management
/// Simplified version without external dependencies
module suiverse_certificate::standalone_certificates {
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 10001;
    const E_CERTIFICATE_NOT_FOUND: u64 = 10002;
    const E_ALREADY_VERIFIED: u64 = 10003;
    const E_INVALID_CERTIFICATE: u64 = 10004;

    // Certificate types
    const CERT_TYPE_EXAM: u8 = 1;
    const CERT_TYPE_PROJECT: u8 = 2;
    const CERT_TYPE_ACHIEVEMENT: u8 = 3;
    const CERT_TYPE_SKILL: u8 = 4;

    // Certificate levels
    const LEVEL_BEGINNER: u8 = 1;
    const LEVEL_INTERMEDIATE: u8 = 2;
    const LEVEL_ADVANCED: u8 = 3;
    const LEVEL_EXPERT: u8 = 4;

    // =============== Core Structs ===============
    
    /// Simplified Certificate NFT
    public struct CertificateNFT has key, store {
        id: UID,
        certificate_type: u8,
        level: u8,
        title: String,
        description: String,
        issuer: address,
        recipient: address,
        skills_certified: vector<String>,
        issued_at: u64,
        expires_at: Option<u64>,
    }

    /// Certificate manager
    public struct CertificateManager has key, store {
        id: UID,
        total_certificates_issued: u64,
        treasury: Balance<SUI>,
        paused: bool,
    }

    /// Certificate statistics
    public struct CertificateStats has key, store {
        id: UID,
        certificates_by_type: Table<u8, u64>,
        certificates_by_level: Table<u8, u64>,
        total_renewals: u64,
        total_revocations: u64,
    }

    /// Administrative capability
    public struct AdminCap has key, store {
        id: UID,
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
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        
        let manager = CertificateManager {
            id: object::new(ctx),
            total_certificates_issued: 0,
            treasury: balance::zero(),
            paused: false,
        };
        
        let stats = CertificateStats {
            id: object::new(ctx),
            certificates_by_type: table::new(ctx),
            certificates_by_level: table::new(ctx),
            total_renewals: 0,
            total_revocations: 0,
        };
        
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(manager);
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Issue a simple certificate NFT
    public entry fun issue_simple_certificate(
        manager: &mut CertificateManager,
        stats: &mut CertificateStats,
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
        let issuer = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(!manager.paused, E_NOT_AUTHORIZED);
        assert!(certificate_type >= 1 && certificate_type <= 4, E_INVALID_CERTIFICATE);
        assert!(level >= 1 && level <= 4, E_INVALID_CERTIFICATE);
        
        // Process payment (simplified)
        let payment_amount = coin::value(&payment);
        balance::join(&mut manager.treasury, coin::into_balance(payment));
        
        // Calculate expiration
        let expires_at = if (expires_in_days == 0) {
            option::none()
        } else {
            option::some(current_time + (expires_in_days * 86400000))
        };
        
        // Create certificate NFT
        let certificate = CertificateNFT {
            id: object::new(ctx),
            certificate_type,
            level,
            title,
            description,
            issuer,
            recipient,
            skills_certified: skills,
            issued_at: current_time,
            expires_at,
        };
        
        let certificate_id = object::uid_to_inner(&certificate.id);
        
        // Update statistics
        manager.total_certificates_issued = manager.total_certificates_issued + 1;
        update_certificate_statistics(stats, certificate_type, level);
        
        // Emit event
        event::emit(CertificateIssued {
            certificate_id,
            certificate_type,
            level,
            recipient,
            issuer,
            title,
            skills_certified: skills,
            timestamp: current_time,
        });
        
        transfer::transfer(certificate, recipient);
    }

    // =============== Helper Functions ===============
    
    fun update_certificate_statistics(stats: &mut CertificateStats, cert_type: u8, level: u8) {
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
    }

    // =============== View Functions ===============
    
    public fun get_certificate_type(certificate: &CertificateNFT): u8 {
        certificate.certificate_type
    }
    
    public fun get_certificate_level(certificate: &CertificateNFT): u8 {
        certificate.level
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

    public fun get_total_certificates_issued(manager: &CertificateManager): u64 {
        manager.total_certificates_issued
    }

    public fun get_certificate_manager_total(manager: &CertificateManager): u64 {
        manager.total_certificates_issued
    }
}