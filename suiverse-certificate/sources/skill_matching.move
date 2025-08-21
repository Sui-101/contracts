/// Comprehensive P2P Skill Matching Module for SuiVerse
/// Implements certificate-based talent discovery and contact facilitation
/// Follows Clean Architecture and SOLID principles
module suiverse_certificate::skill_matching {
    use std::string::{Self as string, String};
    // use std::option; // Implicit import
    use sui::object::{ID, UID};
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::random::{Self, Random};
    use sui::bcs;
    use suiverse_certificate::certificates::{Self as certificates, CertificateNFT};
    use suiverse_certificate::registry::{Self as registry, CertificateRegistry};

    // ===== Constants =====
    
    // Error codes
    const E_NOT_AUTHORIZED: u64 = 9001;
    const E_INSUFFICIENT_PAYMENT: u64 = 9002;
    const E_PROFILE_NOT_FOUND: u64 = 9003;
    const E_SEARCH_NOT_FOUND: u64 = 9004;
    const E_CONTACT_ALREADY_PURCHASED: u64 = 9005;
    const E_INVALID_CRITERIA: u64 = 9006;
    const E_DISCOVERY_DISABLED: u64 = 9007;
    const E_INVALID_AVAILABILITY: u64 = 9008;
    const E_NO_MATCHING_CANDIDATES: u64 = 9009;
    const E_CONTACT_REQUEST_NOT_FOUND: u64 = 9010;
    const E_INVALID_EXPERIENCE_LEVEL: u64 = 9011;

    // Economic parameters
    const SEARCH_FEE: u64 = 1000000000; // 1 SUI
    const CONTACT_FEE: u64 = 2000000000; // 2 SUI
    const PLATFORM_SHARE_PERCENTAGE: u8 = 30; // 30% to platform, 70% to candidate
    const CANDIDATE_SHARE_PERCENTAGE: u8 = 70;

    // Limits and defaults
    const MAX_SEARCH_RESULTS: u8 = 3;
    const MAX_SKILLS_PER_PROFILE: u8 = 20;
    const SEARCH_EXPIRY_TIME_MS: u64 = 86400000; // 24 hours
    const MAX_CONTACT_INFO_LENGTH: u64 = 500;

    // Availability status
    const AVAILABILITY_AVAILABLE: u8 = 1;
    const AVAILABILITY_BUSY: u8 = 2;
    const AVAILABILITY_NOT_AVAILABLE: u8 = 3;

    // Search and contact status
    const SEARCH_STATUS_ACTIVE: u8 = 1;
    const SEARCH_STATUS_COMPLETED: u8 = 2;
    const SEARCH_STATUS_EXPIRED: u8 = 3;

    const CONTACT_STATUS_PENDING: u8 = 1;
    const CONTACT_STATUS_FULFILLED: u8 = 2;

    // ===== Data Structures =====
    
    /// Discoverable skill profile for talent matching
    public struct SkillProfile has key, store {
        id: UID,
        owner: address,
        certificate_ids: vector<ID>, // Earned certificate NFT IDs
        skills: vector<String>, // Self-declared skills
        experience_level: u8, // 1-5 scale (1: Beginner, 5: Expert)
        availability: u8, // Current availability status
        hourly_rate: Option<u64>, // Optional hourly rate in SUI
        contact_info_encrypted: vector<u8>, // Encrypted contact details
        discovery_enabled: bool, // Opt-in for matching
        total_contacts_sold: u64,
        earnings: Balance<SUI>,
        profile_views: u64,
        created_at: u64,
        updated_at: u64,
    }

    /// Search criteria for finding candidates
    public struct SearchCriteria has store, copy, drop {
        required_certificates: vector<String>, // Certificate names/types
        min_experience_level: u8,
        max_results: u8, // Default 3
        additional_skills: vector<String>, // Optional skill keywords
        min_hourly_rate: Option<u64>,
        max_hourly_rate: Option<u64>,
        availability_required: Option<u8>,
    }

    /// Employer/recruiter search session
    public struct SkillSearch has key, store {
        id: UID,
        searcher: address,
        search_criteria: SearchCriteria,
        selected_candidates: vector<address>, // Randomly selected candidates
        anonymous_profiles: vector<AnonymousProfile>, // Anonymized candidate info
        search_fee_paid: u64,
        created_at: u64,
        expires_at: u64,
        status: u8, // 1: Active, 2: Completed, 3: Expired
    }

    /// Anonymous candidate profile (for search results)
    public struct AnonymousProfile has store, copy, drop {
        candidate_address: address, // Hidden until contact is purchased
        skills: vector<String>,
        experience_level: u8,
        certificate_count: u64,
        certificate_types: vector<String>, // Types without revealing specifics
        hourly_rate: Option<u64>,
        availability: u8,
        profile_score: u64, // Computed matching score
    }

    /// Contact purchase request
    public struct ContactRequest has key, store {
        id: UID,
        requester: address,
        target_profile: address,
        search_id: ID,
        contact_fee_paid: u64,
        contact_info: Option<String>, // Decrypted contact info
        created_at: u64,
        status: u8, // 1: Pending, 2: Fulfilled
    }

    /// Platform-wide skill matching registry
    public struct SkillMatchingRegistry has key {
        id: UID,
        // Indexes for efficient search
        skill_profiles: Table<address, ID>, // user -> profile ID
        skills_index: Table<String, vector<address>>, // skill -> users
        certificate_index: Table<String, vector<address>>, // certificate type -> users
        experience_index: Table<u8, vector<address>>, // experience level -> users
        
        // Search and contact tracking
        active_searches: Table<ID, address>, // search ID -> searcher
        contact_requests: Table<ID, ContactRequest>,
        
        // Platform statistics
        total_searches: u64,
        total_contacts_purchased: u64,
        total_profiles: u64,
        platform_earnings: Balance<SUI>,
        
        // Popular skills tracking
        skill_search_counts: Table<String, u64>,
    }

    /// Search analytics data
    public struct SearchAnalytics has store, copy, drop {
        search_id: ID,
        candidates_found: u64,
        criteria_met_count: u64,
        average_experience_level: u64,
        most_common_skills: vector<String>,
    }

    // ===== Events =====
    
    public struct ProfileCreatedEvent has copy, drop {
        profile_id: ID,
        owner: address,
        skills: vector<String>,
        timestamp: u64,
    }

    public struct SearchCreatedEvent has copy, drop {
        search_id: ID,
        searcher: address,
        criteria: SearchCriteria,
        fee_paid: u64,
        timestamp: u64,
    }

    public struct CandidatesFoundEvent has copy, drop {
        search_id: ID,
        candidates_count: u64,
        analytics: SearchAnalytics,
        timestamp: u64,
    }

    public struct ContactRequestedEvent has copy, drop {
        contact_id: ID,
        requester: address,
        target: address,
        fee_paid: u64,
        timestamp: u64,
    }

    public struct RevenueDistributedEvent has copy, drop {
        contact_id: ID,
        candidate_share: u64,
        platform_share: u64,
        candidate: address,
        timestamp: u64,
    }

    public struct ProfileUpdatedEvent has copy, drop {
        profile_id: ID,
        owner: address,
        discovery_enabled: bool,
        timestamp: u64,
    }

    // ===== Initialization =====
    
    fun init(ctx: &mut TxContext) {
        let registry = SkillMatchingRegistry {
            id: object::new(ctx),
            skill_profiles: table::new(ctx),
            skills_index: table::new(ctx),
            certificate_index: table::new(ctx),
            experience_index: table::new(ctx),
            active_searches: table::new(ctx),
            contact_requests: table::new(ctx),
            total_searches: 0,
            total_contacts_purchased: 0,
            total_profiles: 0,
            platform_earnings: balance::zero(),
            skill_search_counts: table::new(ctx),
        };
        
        transfer::share_object(registry);
    }

    // ===== Profile Management Functions =====
    
    /// Create a discoverable skill profile
    public entry fun create_skill_profile(
        skills: vector<String>,
        experience_level: u8,
        contact_info: vector<u8>,
        hourly_rate: u64, // 0 for no rate
        registry: &mut SkillMatchingRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        assert!(!table::contains(&registry.skill_profiles, owner), E_PROFILE_NOT_FOUND);
        assert!(experience_level >= 1 && experience_level <= 5, E_INVALID_EXPERIENCE_LEVEL);
        assert!(vector::length(&skills) <= (MAX_SKILLS_PER_PROFILE as u64), E_INVALID_CRITERIA);
        assert!(vector::length(&contact_info) <= MAX_CONTACT_INFO_LENGTH, E_INVALID_CRITERIA);

        let current_time = clock::timestamp_ms(clock);
        let profile_uid = object::new(ctx);
        let profile_id = object::uid_to_inner(&profile_uid);

        // Encrypt contact info (simplified - in production use proper encryption)
        let encrypted_contact = encrypt_contact_info(contact_info, owner);

        let hourly_rate_option = if (hourly_rate > 0) {
            option::some(hourly_rate)
        } else {
            option::none()
        };

        let profile = SkillProfile {
            id: profile_uid,
            owner,
            certificate_ids: vector::empty(),
            skills,
            experience_level,
            availability: AVAILABILITY_AVAILABLE,
            hourly_rate: hourly_rate_option,
            contact_info_encrypted: encrypted_contact,
            discovery_enabled: true,
            total_contacts_sold: 0,
            earnings: balance::zero(),
            profile_views: 0,
            created_at: current_time,
            updated_at: current_time,
        };

        // Update registry indexes
        table::add(&mut registry.skill_profiles, owner, profile_id);
        
        // Add to skills index
        let mut i = 0;
        while (i < vector::length(&skills)) {
            let skill = *vector::borrow(&skills, i);
            if (!table::contains(&registry.skills_index, skill)) {
                table::add(&mut registry.skills_index, skill, vector::empty());
            };
            let skill_users = table::borrow_mut(&mut registry.skills_index, skill);
            vector::push_back(skill_users, owner);
            i = i + 1;
        };

        // Add to experience index
        if (!table::contains(&registry.experience_index, experience_level)) {
            table::add(&mut registry.experience_index, experience_level, vector::empty());
        };
        let exp_users = table::borrow_mut(&mut registry.experience_index, experience_level);
        vector::push_back(exp_users, owner);

        registry.total_profiles = registry.total_profiles + 1;

        event::emit(ProfileCreatedEvent {
            profile_id,
            owner,
            skills: profile.skills,
            timestamp: current_time,
        });

        transfer::share_object(profile);
    }

    /// Update profile information
    public entry fun update_profile(
        profile: &mut SkillProfile,
        skills: Option<vector<String>>,
        experience_level: Option<u8>,
        availability: Option<u8>,
        contact_info: Option<vector<u8>>,
        hourly_rate: Option<u64>,
        registry: &mut SkillMatchingRegistry,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, E_NOT_AUTHORIZED);

        // Update skills if provided
        if (option::is_some(&skills)) {
            let new_skills = *option::borrow(&skills);
            assert!(vector::length(&new_skills) <= (MAX_SKILLS_PER_PROFILE as u64), E_INVALID_CRITERIA);
            
            // Remove old skills from index
            update_skills_index(registry, profile.owner, &profile.skills, &new_skills);
            profile.skills = new_skills;
        };

        // Update experience level
        if (option::is_some(&experience_level)) {
            let new_level = *option::borrow(&experience_level);
            assert!(new_level >= 1 && new_level <= 5, E_INVALID_EXPERIENCE_LEVEL);
            
            // Update experience index
            update_experience_index(registry, profile.owner, profile.experience_level, new_level);
            profile.experience_level = new_level;
        };

        // Update availability
        if (option::is_some(&availability)) {
            let new_availability = *option::borrow(&availability);
            assert!(
                new_availability >= AVAILABILITY_AVAILABLE && 
                new_availability <= AVAILABILITY_NOT_AVAILABLE, 
                E_INVALID_AVAILABILITY
            );
            profile.availability = new_availability;
        };

        // Update contact info
        if (option::is_some(&contact_info)) {
            let new_contact = *option::borrow(&contact_info);
            assert!(vector::length(&new_contact) <= MAX_CONTACT_INFO_LENGTH, E_INVALID_CRITERIA);
            profile.contact_info_encrypted = encrypt_contact_info(new_contact, profile.owner);
        };

        // Update hourly rate
        if (option::is_some(&hourly_rate)) {
            let rate = *option::borrow(&hourly_rate);
            profile.hourly_rate = if (rate > 0) {
                option::some(rate)
            } else {
                option::none()
            };
        };

        profile.updated_at = clock::timestamp_ms(clock);

        event::emit(ProfileUpdatedEvent {
            profile_id: object::uid_to_inner(&profile.id),
            owner: profile.owner,
            discovery_enabled: profile.discovery_enabled,
            timestamp: profile.updated_at,
        });
    }

    /// Toggle profile discoverability
    public entry fun toggle_discovery(
        profile: &mut SkillProfile,
        enabled: bool,
        ctx: &TxContext,
    ) {
        assert!(profile.owner == tx_context::sender(ctx), E_NOT_AUTHORIZED);
        profile.discovery_enabled = enabled;
    }

    /// Add certificates to profile
    public entry fun add_certificates(
        profile: &mut SkillProfile,
        certificate_ids: vector<ID>,
        certificate_types: vector<String>,
        registry: &mut SkillMatchingRegistry,
        cert_registry: &CertificateRegistry,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, E_NOT_AUTHORIZED);
        assert!(vector::length(&certificate_ids) == vector::length(&certificate_types), E_INVALID_CRITERIA);

        // Verify certificates belong to user
        let user_certs = registry::get_user_certificates(cert_registry, sender);
        let mut i = 0;
        while (i < vector::length(&certificate_ids)) {
            let cert_id = *vector::borrow(&certificate_ids, i);
            assert!(vector::contains(&user_certs, &cert_id), E_NOT_AUTHORIZED);
            
            // Add to profile if not already present
            if (!vector::contains(&profile.certificate_ids, &cert_id)) {
                vector::push_back(&mut profile.certificate_ids, cert_id);
            };
            
            // Update certificate index
            let cert_type = *vector::borrow(&certificate_types, i);
            if (!table::contains(&registry.certificate_index, cert_type)) {
                table::add(&mut registry.certificate_index, cert_type, vector::empty());
            };
            let cert_users = table::borrow_mut(&mut registry.certificate_index, cert_type);
            if (!vector::contains(cert_users, &sender)) {
                vector::push_back(cert_users, sender);
            };
            
            i = i + 1;
        };
    }

    // ===== Search and Matching Functions =====
    
    /// Search for candidates based on criteria
    public entry fun search_candidates(
        required_certificates: vector<String>,
        min_experience_level: u8,
        max_results: u8,
        additional_skills: vector<String>,
        min_hourly_rate: u64, // 0 for no minimum
        max_hourly_rate: u64, // 0 for no maximum
        availability_required: u8, // 0 for no requirement
        payment: Coin<SUI>,
        registry: &mut SkillMatchingRegistry,
        random: &Random,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let searcher = tx_context::sender(ctx);
        assert!(coin::value(&payment) >= SEARCH_FEE, E_INSUFFICIENT_PAYMENT);
        assert!(max_results > 0 && max_results <= MAX_SEARCH_RESULTS, E_INVALID_CRITERIA);
        assert!(min_experience_level >= 1 && min_experience_level <= 5, E_INVALID_EXPERIENCE_LEVEL);

        let current_time = clock::timestamp_ms(clock);
        let search_uid = object::new(ctx);
        let search_id = object::uid_to_inner(&search_uid);

        // Create search criteria
        let criteria = SearchCriteria {
            required_certificates,
            min_experience_level,
            max_results,
            additional_skills,
            min_hourly_rate: if (min_hourly_rate > 0) { option::some(min_hourly_rate) } else { option::none() },
            max_hourly_rate: if (max_hourly_rate > 0) { option::some(max_hourly_rate) } else { option::none() },
            availability_required: if (availability_required > 0) { option::some(availability_required) } else { option::none() },
        };

        // Find matching candidates
        let matching_candidates = find_matching_candidates(&criteria, registry);
        assert!(vector::length(&matching_candidates) > 0, E_NO_MATCHING_CANDIDATES);

        // Randomly select candidates
        let selected_candidates = random_select_candidates(
            matching_candidates, 
            max_results, 
            random, 
            ctx
        );

        // Create anonymous profiles
        let anonymous_profiles = create_anonymous_profiles(&selected_candidates, &criteria, registry);

        // Create search analytics
        let analytics = SearchAnalytics {
            search_id,
            candidates_found: vector::length(&selected_candidates),
            criteria_met_count: vector::length(&matching_candidates),
            average_experience_level: calculate_average_experience(&selected_candidates, registry),
            most_common_skills: get_common_skills(&selected_candidates, registry),
        };

        let search = SkillSearch {
            id: search_uid,
            searcher,
            search_criteria: criteria,
            selected_candidates,
            anonymous_profiles,
            search_fee_paid: coin::value(&payment),
            created_at: current_time,
            expires_at: current_time + SEARCH_EXPIRY_TIME_MS,
            status: SEARCH_STATUS_ACTIVE,
        };

        // Take payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut registry.platform_earnings, payment_balance);
        registry.total_searches = registry.total_searches + 1;

        // Update skill search counts
        update_skill_search_counts(registry, &criteria.required_certificates);
        update_skill_search_counts(registry, &criteria.additional_skills);

        // Track active search
        table::add(&mut registry.active_searches, search_id, searcher);

        event::emit(SearchCreatedEvent {
            search_id,
            searcher,
            criteria,
            fee_paid: search.search_fee_paid,
            timestamp: current_time,
        });

        event::emit(CandidatesFoundEvent {
            search_id,
            candidates_count: vector::length(&selected_candidates),
            analytics,
            timestamp: current_time,
        });

        transfer::share_object(search);
    }

    /// Purchase contact information for a candidate
    public entry fun request_contact(
        search: &SkillSearch,
        target_candidate: address,
        mut payment: Coin<SUI>,
        registry: &mut SkillMatchingRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let requester = tx_context::sender(ctx);
        assert!(search.searcher == requester, E_NOT_AUTHORIZED);
        assert!(coin::value(&payment) >= CONTACT_FEE, E_INSUFFICIENT_PAYMENT);
        assert!(search.status == SEARCH_STATUS_ACTIVE, E_SEARCH_NOT_FOUND);
        assert!(vector::contains(&search.selected_candidates, &target_candidate), E_PROFILE_NOT_FOUND);

        let current_time = clock::timestamp_ms(clock);
        let contact_uid = object::new(ctx);
        let contact_id = object::uid_to_inner(&contact_uid);

        // Check if contact already purchased
        assert!(
            !contact_already_purchased(registry, requester, target_candidate),
            E_CONTACT_ALREADY_PURCHASED
        );

        // Create contact request
        let contact_request = ContactRequest {
            id: contact_uid,
            requester,
            target_profile: target_candidate,
            search_id: object::uid_to_inner(&search.id),
            contact_fee_paid: coin::value(&payment),
            contact_info: option::none(),
            created_at: current_time,
            status: CONTACT_STATUS_PENDING,
        };

        // Process payment and revenue distribution
        let payment_amount = coin::value(&payment);
        let candidate_share = (payment_amount * (CANDIDATE_SHARE_PERCENTAGE as u64)) / 100;
        let platform_share = payment_amount - candidate_share;

        // Add platform share to registry
        let platform_balance = coin::split(&mut payment, platform_share, ctx);
        balance::join(&mut registry.platform_earnings, coin::into_balance(platform_balance));

        // Transfer candidate share to candidate
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, target_candidate);
        } else {
            coin::destroy_zero(payment);
        };

        // Update candidate profile earnings
        if (table::contains(&registry.skill_profiles, target_candidate)) {
            // Note: We can't directly update the profile balance here as we don't have access to it
            // In production, this would require a different approach or additional capability patterns
        };

        registry.total_contacts_purchased = registry.total_contacts_purchased + 1;

        // Store contact request
        table::add(&mut registry.contact_requests, contact_id, contact_request);

        event::emit(ContactRequestedEvent {
            contact_id,
            requester,
            target: target_candidate,
            fee_paid: payment_amount,
            timestamp: current_time,
        });

        event::emit(RevenueDistributedEvent {
            contact_id,
            candidate_share,
            platform_share,
            candidate: target_candidate,
            timestamp: current_time,
        });
    }

    /// Fulfill contact request by providing decrypted contact info
    public entry fun fulfill_contact_request(
        contact_id: ID,
        profile: &mut SkillProfile,
        registry: &mut SkillMatchingRegistry,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, E_NOT_AUTHORIZED);
        assert!(table::contains(&registry.contact_requests, contact_id), E_CONTACT_REQUEST_NOT_FOUND);

        let contact_request = table::borrow_mut(&mut registry.contact_requests, contact_id);
        assert!(contact_request.target_profile == sender, E_NOT_AUTHORIZED);
        assert!(contact_request.status == CONTACT_STATUS_PENDING, E_CONTACT_ALREADY_PURCHASED);

        // Decrypt contact info (simplified - in production use proper decryption)
        let decrypted_info = decrypt_contact_info(&profile.contact_info_encrypted, profile.owner);
        
        contact_request.contact_info = option::some(decrypted_info);
        contact_request.status = CONTACT_STATUS_FULFILLED;

        // Update profile statistics
        profile.total_contacts_sold = profile.total_contacts_sold + 1;
        let candidate_earnings = coin::from_balance(
            balance::split(&mut profile.earnings, contact_request.contact_fee_paid * (CANDIDATE_SHARE_PERCENTAGE as u64) / 100), 
            ctx
        );
        balance::join(&mut profile.earnings, coin::into_balance(candidate_earnings));
    }

    // ===== Internal Helper Functions =====
    
    /// Find candidates matching search criteria
    fun find_matching_candidates(
        criteria: &SearchCriteria,
        registry: &SkillMatchingRegistry,
    ): vector<address> {
        let mut candidates = vector::empty<address>();
        
        // Start with certificate requirements
        if (vector::length(&criteria.required_certificates) > 0) {
            candidates = find_candidates_by_certificates(&criteria.required_certificates, registry);
        } else {
            // If no certificate requirements, use experience level
            if (table::contains(&registry.experience_index, criteria.min_experience_level)) {
                let exp_candidates = table::borrow(&registry.experience_index, criteria.min_experience_level);
                candidates = *exp_candidates;
            };
        };

        // Filter by additional criteria
        candidates = filter_by_experience(candidates, criteria.min_experience_level, registry);
        candidates = filter_by_skills(candidates, &criteria.additional_skills, registry);
        
        // TODO: Add filters for hourly rate and availability when profile data is accessible
        
        candidates
    }

    /// Find candidates by certificate requirements
    fun find_candidates_by_certificates(
        required_certs: &vector<String>,
        registry: &SkillMatchingRegistry,
    ): vector<address> {
        let mut result = vector::empty<address>();
        
        if (vector::length(required_certs) == 0) {
            return result
        };

        // Start with first certificate type
        let first_cert = *vector::borrow(required_certs, 0);
        if (table::contains(&registry.certificate_index, first_cert)) {
            result = *table::borrow(&registry.certificate_index, first_cert);
        };

        // Intersect with other certificate requirements
        let mut i = 1;
        while (i < vector::length(required_certs)) {
            let cert_type = *vector::borrow(required_certs, i);
            if (table::contains(&registry.certificate_index, cert_type)) {
                let cert_candidates = table::borrow(&registry.certificate_index, cert_type);
                result = intersect_vectors(&result, cert_candidates);
            } else {
                // If any required certificate has no candidates, return empty
                return vector::empty()
            };
            i = i + 1;
        };

        result
    }

    /// Filter candidates by minimum experience level
    fun filter_by_experience(
        candidates: vector<address>,
        min_level: u8,
        registry: &SkillMatchingRegistry,
    ): vector<address> {
        let mut filtered = vector::empty<address>();
        
        let mut level = min_level;
        while (level <= 5) {
            if (table::contains(&registry.experience_index, level)) {
                let level_candidates = table::borrow(&registry.experience_index, level);
                let intersected = intersect_vectors(&candidates, level_candidates);
                merge_vectors(&mut filtered, intersected);
            };
            level = level + 1;
        };

        filtered
    }

    /// Filter candidates by additional skills
    fun filter_by_skills(
        candidates: vector<address>,
        skills: &vector<String>,
        registry: &SkillMatchingRegistry,
    ): vector<address> {
        if (vector::length(skills) == 0) {
            return candidates
        };

        let mut result = candidates;
        
        let mut i = 0;
        while (i < vector::length(skills)) {
            let skill = *vector::borrow(skills, i);
            if (table::contains(&registry.skills_index, skill)) {
                let skill_candidates = table::borrow(&registry.skills_index, skill);
                result = intersect_vectors(&result, skill_candidates);
            };
            i = i + 1;
        };

        result
    }

    /// Randomly select candidates from matching pool
    fun random_select_candidates(
        candidates: vector<address>,
        max_results: u8,
        random: &Random,
        ctx: &mut TxContext,
    ): vector<address> {
        let candidates_count = vector::length(&candidates);
        let max_select = if ((max_results as u64) < candidates_count) {
            (max_results as u64)
        } else {
            candidates_count
        };

        if (max_select == 0) {
            return vector::empty()
        };

        let mut selected = vector::empty<address>();
        let mut remaining = candidates;

        let mut i = 0;
        while (i < max_select && vector::length(&remaining) > 0) {
            // Generate random index
            let mut random_gen = random::new_generator(random, ctx);
            let random_index = random::generate_u64_in_range(&mut random_gen, 0, vector::length(&remaining) - 1);
            
            let selected_candidate = vector::remove(&mut remaining, random_index);
            vector::push_back(&mut selected, selected_candidate);
            i = i + 1;
        };

        selected
    }

    /// Create anonymous profiles for selected candidates
    fun create_anonymous_profiles(
        candidates: &vector<address>,
        criteria: &SearchCriteria,
        registry: &SkillMatchingRegistry,
    ): vector<AnonymousProfile> {
        let mut profiles = vector::empty<AnonymousProfile>();
        
        let mut i = 0;
        while (i < vector::length(candidates)) {
            let candidate = *vector::borrow(candidates, i);
            
            // Create anonymous profile (simplified version)
            let anonymous_profile = AnonymousProfile {
                candidate_address: candidate,
                skills: get_user_skills(candidate, registry),
                experience_level: get_user_experience_level(candidate, registry),
                certificate_count: get_user_certificate_count(candidate, registry),
                certificate_types: get_user_certificate_types(candidate, registry),
                hourly_rate: option::none(), // TODO: Get from profile
                availability: AVAILABILITY_AVAILABLE, // TODO: Get from profile
                profile_score: calculate_match_score(candidate, criteria, registry),
            };
            
            vector::push_back(&mut profiles, anonymous_profile);
            i = i + 1;
        };

        profiles
    }

    // ===== Utility Functions =====
    
    /// Intersect two vectors
    fun intersect_vectors<T: copy + drop>(vec1: &vector<T>, vec2: &vector<T>): vector<T> {
        let mut result = vector::empty<T>();
        
        let mut i = 0;
        while (i < vector::length(vec1)) {
            let item = *vector::borrow(vec1, i);
            if (vector::contains(vec2, &item)) {
                vector::push_back(&mut result, item);
            };
            i = i + 1;
        };

        result
    }

    /// Merge two vectors (union without duplicates)
    fun merge_vectors<T: copy + drop>(target: &mut vector<T>, source: vector<T>) {
        let mut i = 0;
        while (i < vector::length(&source)) {
            let item = *vector::borrow(&source, i);
            if (!vector::contains(target, &item)) {
                vector::push_back(target, item);
            };
            i = i + 1;
        };
    }

    /// Simple contact info encryption (placeholder)
    fun encrypt_contact_info(contact_info: vector<u8>, _owner: address): vector<u8> {
        // In production, use proper encryption with the owner's public key
        // For now, return as-is (not secure)
        contact_info
    }

    /// Simple contact info decryption (placeholder)
    fun decrypt_contact_info(encrypted_info: &vector<u8>, _owner: address): String {
        // In production, use proper decryption with the owner's private key
        string::utf8(*encrypted_info)
    }

    /// Update skills index when profile skills change
    fun update_skills_index(
        registry: &mut SkillMatchingRegistry,
        user: address,
        old_skills: &vector<String>,
        new_skills: &vector<String>,
    ) {
        // Remove from old skills
        let mut i = 0;
        while (i < vector::length(old_skills)) {
            let skill = *vector::borrow(old_skills, i);
            if (table::contains(&registry.skills_index, skill)) {
                let skill_users = table::borrow_mut(&mut registry.skills_index, skill);
                remove_from_vector(skill_users, &user);
            };
            i = i + 1;
        };

        // Add to new skills
        let mut j = 0;
        while (j < vector::length(new_skills)) {
            let skill = *vector::borrow(new_skills, j);
            if (!table::contains(&registry.skills_index, skill)) {
                table::add(&mut registry.skills_index, skill, vector::empty());
            };
            let skill_users = table::borrow_mut(&mut registry.skills_index, skill);
            if (!vector::contains(skill_users, &user)) {
                vector::push_back(skill_users, user);
            };
            j = j + 1;
        };
    }

    /// Update experience index when level changes
    fun update_experience_index(
        registry: &mut SkillMatchingRegistry,
        user: address,
        old_level: u8,
        new_level: u8,
    ) {
        // Remove from old level
        if (table::contains(&registry.experience_index, old_level)) {
            let old_users = table::borrow_mut(&mut registry.experience_index, old_level);
            remove_from_vector(old_users, &user);
        };

        // Add to new level
        if (!table::contains(&registry.experience_index, new_level)) {
            table::add(&mut registry.experience_index, new_level, vector::empty());
        };
        let new_users = table::borrow_mut(&mut registry.experience_index, new_level);
        if (!vector::contains(new_users, &user)) {
            vector::push_back(new_users, user);
        };
    }

    /// Remove item from vector
    fun remove_from_vector<T: copy + drop>(vec: &mut vector<T>, item: &T) {
        let mut i = 0;
        while (i < vector::length(vec)) {
            if (vector::borrow(vec, i) == item) {
                vector::remove(vec, i);
                return
            };
            i = i + 1;
        };
    }

    /// Update skill search counts for analytics
    fun update_skill_search_counts(registry: &mut SkillMatchingRegistry, skills: &vector<String>) {
        let mut i = 0;
        while (i < vector::length(skills)) {
            let skill = *vector::borrow(skills, i);
            if (!table::contains(&registry.skill_search_counts, skill)) {
                table::add(&mut registry.skill_search_counts, skill, 0);
            };
            let count = table::borrow_mut(&mut registry.skill_search_counts, skill);
            *count = *count + 1;
            i = i + 1;
        };
    }

    /// Check if contact already purchased
    fun contact_already_purchased(
        registry: &SkillMatchingRegistry,
        _requester: address,
        _target: address,
    ): bool {
        // TODO: Implement proper tracking of purchased contacts
        false
    }

    // ===== Placeholder Functions (to be implemented with proper profile access) =====
    
    fun get_user_skills(_user: address, _registry: &SkillMatchingRegistry): vector<String> {
        vector::empty() // TODO: Get from profile
    }

    fun get_user_experience_level(_user: address, _registry: &SkillMatchingRegistry): u8 {
        1 // TODO: Get from profile
    }

    fun get_user_certificate_count(_user: address, _registry: &SkillMatchingRegistry): u64 {
        0 // TODO: Count user certificates
    }

    fun get_user_certificate_types(_user: address, _registry: &SkillMatchingRegistry): vector<String> {
        vector::empty() // TODO: Get certificate types
    }

    fun calculate_match_score(_candidate: address, _criteria: &SearchCriteria, _registry: &SkillMatchingRegistry): u64 {
        50 // TODO: Implement matching score algorithm
    }

    fun calculate_average_experience(_candidates: &vector<address>, _registry: &SkillMatchingRegistry): u64 {
        3 // TODO: Calculate actual average
    }

    fun get_common_skills(_candidates: &vector<address>, _registry: &SkillMatchingRegistry): vector<String> {
        vector::empty() // TODO: Find most common skills
    }

    // ===== View Functions =====
    
    /// Get platform statistics
    public fun get_platform_stats(registry: &SkillMatchingRegistry): (u64, u64, u64, u64) {
        (
            registry.total_searches,
            registry.total_contacts_purchased,
            registry.total_profiles,
            balance::value(&registry.platform_earnings)
        )
    }

    /// Get popular skills
    public fun get_popular_skills(registry: &SkillMatchingRegistry, limit: u64): vector<String> {
        // TODO: Implement sorting by search count
        vector::empty()
    }

    /// Check if profile exists for user
    public fun has_profile(registry: &SkillMatchingRegistry, user: address): bool {
        table::contains(&registry.skill_profiles, user)
    }

    /// Get profile ID for user
    public fun get_profile_id(registry: &SkillMatchingRegistry, user: address): Option<ID> {
        if (table::contains(&registry.skill_profiles, user)) {
            option::some(*table::borrow(&registry.skill_profiles, user))
        } else {
            option::none()
        }
    }

    /// Get contact request info
    public fun get_contact_info(registry: &SkillMatchingRegistry, contact_id: ID): Option<String> {
        if (table::contains(&registry.contact_requests, contact_id)) {
            let contact_request = table::borrow(&registry.contact_requests, contact_id);
            contact_request.contact_info
        } else {
            option::none()
        }
    }
}