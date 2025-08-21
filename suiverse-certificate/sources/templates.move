/// Certificate Templates Module for SuiVerse
/// Provides standardized certificate templates with governance approval
/// Implements dynamic certificate generation and validation rules
module suiverse_certificate::templates {
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
    use sui::url::{Self, Url};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::hash;
    use suiverse_certificate::certificates::{Self, CertificateNFT, CertificateMetadata, CertificateManager, CertificateStats};
    use suiverse_core::parameters::{Self, SystemParameters};

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 12001;
    const E_TEMPLATE_NOT_FOUND: u64 = 12002;
    const E_TEMPLATE_NOT_ACTIVE: u64 = 12003;
    const E_INVALID_TEMPLATE_DATA: u64 = 12004;
    const E_GOVERNANCE_NOT_APPROVED: u64 = 12005;
    const E_INSUFFICIENT_PAYMENT: u64 = 12006;
    const E_PREREQUISITES_NOT_MET: u64 = 12007;
    const E_INVALID_FIELD_VALUE: u64 = 12008;
    const E_TEMPLATE_LIMIT_EXCEEDED: u64 = 12009;
    const E_DUPLICATE_TEMPLATE: u64 = 12010;

    // Template status
    const STATUS_DRAFT: u8 = 0;
    const STATUS_PENDING_APPROVAL: u8 = 1;
    const STATUS_ACTIVE: u8 = 2;
    const STATUS_DEPRECATED: u8 = 3;
    const STATUS_REJECTED: u8 = 4;

    // Template categories
    const CATEGORY_EDUCATIONAL: u8 = 1;
    const CATEGORY_PROFESSIONAL: u8 = 2;
    const CATEGORY_ACHIEVEMENT: u8 = 3;
    const CATEGORY_SKILL_BASED: u8 = 4;
    const CATEGORY_PROJECT_BASED: u8 = 5;

    // Field types for validation
    const FIELD_TYPE_TEXT: u8 = 1;
    const FIELD_TYPE_NUMBER: u8 = 2;
    const FIELD_TYPE_DATE: u8 = 3;
    const FIELD_TYPE_URL: u8 = 4;
    const FIELD_TYPE_ADDRESS: u8 = 5;
    const FIELD_TYPE_ENUM: u8 = 6;

    // Fees
    const TEMPLATE_CREATION_FEE: u64 = 50000000; // 0.05 SUI
    const TEMPLATE_USAGE_FEE: u64 = 10000000; // 0.01 SUI
    const TEMPLATE_APPROVAL_DEPOSIT: u64 = 200000000; // 0.2 SUI

    // Limits
    const MAX_TEMPLATES_PER_USER: u64 = 50;
    const MAX_FIELDS_PER_TEMPLATE: u64 = 20;
    const MAX_PREREQUISITES: u64 = 10;

    // =============== Structs ===============

    /// Enhanced certificate template with governance and validation
    public struct CertificateTemplate has key, store {
        id: UID,
        name: String,
        description: String,
        category: u8,
        certificate_type: u8,
        level: u8,
        
        // Visual design
        image_template_url: Url,
        background_color: String,
        text_color: String,
        font_family: String,
        logo_url: Option<Url>,
        
        // Template structure
        template_fields: vector<TemplateField>,
        validation_rules: vector<ValidationRule>,
        required_skills: vector<String>,
        optional_skills: vector<String>,
        
        // Requirements
        min_score_required: Option<u64>,
        prerequisites: vector<ID>, // Required certificate IDs
        completion_criteria: vector<String>,
        
        // Metadata
        creator: address,
        status: u8,
        governance_proposal_id: Option<ID>,
        usage_count: u64,
        success_rate: u64, // Percentage of successful issuances
        
        // Economics
        usage_fee: u64,
        creator_royalty_rate: u64, // Basis points (e.g., 500 = 5%)
        
        // Timestamps
        created_at: u64,
        approved_at: Option<u64>,
        last_used: Option<u64>,
        expires_at: Option<u64>,
        
        // Governance
        is_active: bool,
        governance_approved: bool,
        rejection_reason: Option<String>,
    }

    /// Template field definition
    public struct TemplateField has store, drop, copy {
        field_name: String,
        field_type: u8,
        is_required: bool,
        default_value: Option<String>,
        validation_pattern: Option<String>,
        possible_values: vector<String>, // For enum fields
        min_length: Option<u64>,
        max_length: Option<u64>,
        placeholder_text: String,
    }

    /// Validation rule for template fields
    public struct ValidationRule has store, drop, copy {
        field_name: String,
        rule_type: String, // "min_value", "max_value", "regex", "custom"
        rule_value: String,
        error_message: String,
        is_blocking: bool, // If true, blocks certificate issuance
    }

    /// Template manager for global template operations
    public struct TemplateManager has key {
        id: UID,
        total_templates: u64,
        active_templates: u64,
        templates_by_type: Table<u8, VecSet<ID>>,
        templates_by_category: Table<u8, VecSet<ID>>,
        templates_by_creator: Table<address, VecSet<ID>>,
        popular_templates: vector<ID>, // Top 10 most used
        
        // Economics
        total_usage_fees_collected: u64,
        creator_royalties_paid: u64,
        treasury: Balance<SUI>,
        
        // Governance
        pending_approvals: VecSet<ID>,
        governance_queue: vector<ID>,
        auto_approval_threshold: u64, // Min reputation for auto-approval
        
        // Configuration
        template_creation_enabled: bool,
        max_templates_per_user: u64,
        admin_cap_id: ID,
    }

    /// Template usage instance for tracking
    public struct TemplateUsage has key, store {
        id: UID,
        template_id: ID,
        user: address,
        certificate_id: ID,
        field_values: Table<String, String>,
        used_at: u64,
        success: bool,
        error_message: Option<String>,
    }

    /// Template approval request for governance
    public struct TemplateApprovalRequest has key {
        id: UID,
        template_id: ID,
        creator: address,
        approval_deposit: Balance<SUI>,
        requested_at: u64,
        reviewer_votes: Table<address, bool>,
        vote_count_for: u64,
        vote_count_against: u64,
        status: u8, // 0: pending, 1: approved, 2: rejected
        decision_made_at: Option<u64>,
    }

    /// Certificate generation request using template
    public struct CertificateGenerationRequest has key {
        id: UID,
        template_id: ID,
        recipient: address,
        field_values: Table<String, String>,
        payment: Balance<SUI>,
        requested_by: address,
        requested_at: u64,
        status: u8, // 0: pending, 1: processing, 2: completed, 3: failed
        certificate_id: Option<ID>,
        error_message: Option<String>,
    }

    /// Template analytics and metrics
    public struct TemplateAnalytics has key {
        id: UID,
        most_used_templates: vector<ID>,
        most_successful_templates: vector<ID>,
        template_usage_trends: Table<u64, u64>, // timestamp -> usage count
        category_popularity: Table<u8, u64>,
        average_completion_time: u64,
        total_certificates_generated: u64,
        failure_rate_by_template: Table<ID, u64>,
        last_updated: u64,
    }

    /// Administrative capability for template management
    public struct TemplateAdminCap has key, store {
        id: UID,
    }

    // =============== Events ===============

    public struct TemplateCreated has copy, drop {
        template_id: ID,
        name: String,
        category: u8,
        certificate_type: u8,
        level: u8,
        creator: address,
        usage_fee: u64,
        timestamp: u64,
    }

    public struct TemplateApprovalRequested has copy, drop {
        template_id: ID,
        request_id: ID,
        creator: address,
        deposit_amount: u64,
        timestamp: u64,
    }

    public struct TemplateApproved has copy, drop {
        template_id: ID,
        approved_by: String, // "governance" or "admin"
        vote_count_for: u64,
        vote_count_against: u64,
        timestamp: u64,
    }

    public struct TemplateRejected has copy, drop {
        template_id: ID,
        reason: String,
        vote_count_for: u64,
        vote_count_against: u64,
        timestamp: u64,
    }

    public struct CertificateGeneratedFromTemplate has copy, drop {
        template_id: ID,
        certificate_id: ID,
        recipient: address,
        generator: address,
        usage_fee_paid: u64,
        creator_royalty: u64,
        timestamp: u64,
    }

    public struct TemplateUsageRecorded has copy, drop {
        template_id: ID,
        usage_id: ID,
        user: address,
        success: bool,
        timestamp: u64,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        // Create admin capability
        let admin_cap = TemplateAdminCap {
            id: object::new(ctx),
        };
        let admin_cap_id = object::uid_to_inner(&admin_cap.id);

        // Initialize template manager
        let manager = TemplateManager {
            id: object::new(ctx),
            total_templates: 0,
            active_templates: 0,
            templates_by_type: table::new(ctx),
            templates_by_category: table::new(ctx),
            templates_by_creator: table::new(ctx),
            popular_templates: vector::empty(),
            total_usage_fees_collected: 0,
            creator_royalties_paid: 0,
            treasury: balance::zero(),
            pending_approvals: vec_set::empty(),
            governance_queue: vector::empty(),
            auto_approval_threshold: 1000, // Reputation threshold
            template_creation_enabled: true,
            max_templates_per_user: MAX_TEMPLATES_PER_USER,
            admin_cap_id,
        };

        // Initialize analytics
        let analytics = TemplateAnalytics {
            id: object::new(ctx),
            most_used_templates: vector::empty(),
            most_successful_templates: vector::empty(),
            template_usage_trends: table::new(ctx),
            category_popularity: table::new(ctx),
            average_completion_time: 0,
            total_certificates_generated: 0,
            failure_rate_by_template: table::new(ctx),
            last_updated: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(manager);
        transfer::share_object(analytics);
    }

    // =============== Public Entry Functions ===============

    /// Create a new certificate template
    public fun create_template(
        manager: &mut TemplateManager,
        name: String,
        description: String,
        category: u8,
        certificate_type: u8,
        level: u8,
        image_template_url: vector<u8>,
        template_fields: vector<TemplateField>,
        validation_rules: vector<ValidationRule>,
        required_skills: vector<String>,
        min_score_required: u64,
        prerequisites: vector<ID>,
        usage_fee: u64,
        creator_royalty_rate: u64,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(manager.template_creation_enabled, E_NOT_AUTHORIZED);
        assert!(vector::length(&template_fields) <= MAX_FIELDS_PER_TEMPLATE, E_INVALID_TEMPLATE_DATA);
        assert!(vector::length(&prerequisites) <= MAX_PREREQUISITES, E_INVALID_TEMPLATE_DATA);
        assert!(creator_royalty_rate <= 2000, E_INVALID_TEMPLATE_DATA); // Max 20%
        
        // Check payment
        assert!(coin::value(&payment) >= TEMPLATE_CREATION_FEE, E_INSUFFICIENT_PAYMENT);
        balance::join(&mut manager.treasury, coin::into_balance(payment));
        
        // Check user template limit
        if (table::contains(&manager.templates_by_creator, creator)) {
            let creator_templates = table::borrow(&manager.templates_by_creator, creator);
            assert!(vec_set::size(creator_templates) < manager.max_templates_per_user, E_TEMPLATE_LIMIT_EXCEEDED);
        };
        
        // Create template
        let template = CertificateTemplate {
            id: object::new(ctx),
            name,
            description,
            category,
            certificate_type,
            level,
            image_template_url: url::new_unsafe_from_bytes(image_template_url),
            background_color: string::utf8(b"#ffffff"),
            text_color: string::utf8(b"#000000"),
            font_family: string::utf8(b"Arial"),
            logo_url: option::none(),
            template_fields,
            validation_rules,
            required_skills,
            optional_skills: vector::empty(),
            min_score_required: if (min_score_required > 0) { option::some(min_score_required) } else { option::none() },
            prerequisites,
            completion_criteria: vector::empty(),
            creator,
            status: STATUS_DRAFT,
            governance_proposal_id: option::none(),
            usage_count: 0,
            success_rate: 100,
            usage_fee,
            creator_royalty_rate,
            created_at: current_time,
            approved_at: option::none(),
            last_used: option::none(),
            expires_at: option::none(),
            is_active: false,
            governance_approved: false,
            rejection_reason: option::none(),
        };
        
        let template_id = object::uid_to_inner(&template.id);
        
        // Update manager indices
        update_template_indices(manager, template_id, category, certificate_type, creator);
        manager.total_templates = manager.total_templates + 1;
        
        event::emit(TemplateCreated {
            template_id,
            name,
            category,
            certificate_type,
            level,
            creator,
            usage_fee,
            timestamp: current_time,
        });
        
        transfer::share_object(template);
    }

    /// Request governance approval for a template
    public entry fun request_template_approval(
        template: &mut CertificateTemplate,
        manager: &mut TemplateManager,
        approval_deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let template_id = object::uid_to_inner(&template.id);
        
        assert!(template.creator == creator, E_NOT_AUTHORIZED);
        assert!(template.status == STATUS_DRAFT, E_INVALID_TEMPLATE_DATA);
        let deposit_amount = coin::value(&approval_deposit);
        assert!(deposit_amount >= TEMPLATE_APPROVAL_DEPOSIT, E_INSUFFICIENT_PAYMENT);
        
        // Create approval request
        let approval_request = TemplateApprovalRequest {
            id: object::new(ctx),
            template_id,
            creator,
            approval_deposit: coin::into_balance(approval_deposit),
            requested_at: current_time,
            reviewer_votes: table::new(ctx),
            vote_count_for: 0,
            vote_count_against: 0,
            status: 0, // Pending
            decision_made_at: option::none(),
        };
        
        let request_id = object::uid_to_inner(&approval_request.id);
        
        // Update template status
        template.status = STATUS_PENDING_APPROVAL;
        
        // Add to pending approvals
        vec_set::insert(&mut manager.pending_approvals, template_id);
        vector::push_back(&mut manager.governance_queue, template_id);
        
        event::emit(TemplateApprovalRequested {
            template_id,
            request_id,
            creator,
            deposit_amount,
            timestamp: current_time,
        });
        
        transfer::share_object(approval_request);
    }

    /// Generate certificate from template
    public entry fun generate_certificate_from_template(
        template: &mut CertificateTemplate,
        manager: &mut TemplateManager,
        cert_manager: &mut CertificateManager,
        stats: &mut CertificateStats,
        analytics: &mut TemplateAnalytics,
        recipient: address,
        field_values: vector<String>, // Corresponds to template fields
        image_url: vector<u8>,
        ipfs_hash: String,
        mut payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let generator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        let template_id = object::uid_to_inner(&template.id);
        
        assert!(template.is_active && template.governance_approved, E_TEMPLATE_NOT_ACTIVE);
        
        // Validate payment
        let total_fee = template.usage_fee + TEMPLATE_USAGE_FEE;
        assert!(coin::value(&payment) >= total_fee, E_INSUFFICIENT_PAYMENT);
        
        // Calculate royalty
        let royalty_amount = (template.usage_fee * template.creator_royalty_rate) / 10000;
        let platform_fee = template.usage_fee - royalty_amount;
        
        // Process payment
        let platform_coin = coin::split(&mut payment, platform_fee, ctx);
        balance::join(&mut manager.treasury, coin::into_balance(platform_coin));
        
        // Transfer royalty to creator (simplified - would use proper treasury) 
        let royalty_coin = coin::split(&mut payment, royalty_amount, ctx);
        balance::join(&mut manager.treasury, coin::into_balance(royalty_coin));
        
        // Validate field values
        validate_template_fields(template, &field_values);
        
        // Check prerequisites if any
        if (!vector::is_empty(&template.prerequisites)) {
            // Would verify user has required certificates
        };
        
        // Create certificate metadata from template
        let metadata = create_metadata_from_template(template, &field_values);
        
        // Generate certificate using certificates module
        certificates::issue_certificate(
            cert_manager,
            stats,
            template.certificate_type,
            template.level,
            template.name,
            template.description,
            recipient,
            image_url,
            ipfs_hash,
            metadata,
            template.required_skills,
            vector[string::utf8(b"template_generated")],
            option::none(), // Use default expiration
            true, // Is tradeable
            payment, // Remaining payment for certificate issuance
            clock,
            ctx
        );
        
        // Update template usage statistics
        template.usage_count = template.usage_count + 1;
        template.last_used = option::some(current_time);
        
        // Update manager statistics
        manager.total_usage_fees_collected = manager.total_usage_fees_collected + template.usage_fee;
        manager.creator_royalties_paid = manager.creator_royalties_paid + royalty_amount;
        
        // Update analytics
        update_template_analytics(analytics, template_id, true, current_time);
        
        let certificate_id = object::id_from_address(@0x0); // Would get actual ID from issuance
        
        event::emit(CertificateGeneratedFromTemplate {
            template_id,
            certificate_id,
            recipient,
            generator,
            usage_fee_paid: template.usage_fee,
            creator_royalty: royalty_amount,
            timestamp: current_time,
        });
    }

    /// Vote on template approval (for governance participants)
    public fun vote_on_template_approval(
        approval_request: &mut TemplateApprovalRequest,
        template: &mut CertificateTemplate,
        manager: &mut TemplateManager,
        vote: bool, // true for approve, false for reject
        _governance_cap: &sui::object::UID, // Would be actual governance capability
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let voter = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(approval_request.status == 0, E_NOT_AUTHORIZED); // Still pending
        
        // Record vote
        if (table::contains(&approval_request.reviewer_votes, voter)) {
            // Update existing vote
            *table::borrow_mut(&mut approval_request.reviewer_votes, voter) = vote;
        } else {
            // New vote
            table::add(&mut approval_request.reviewer_votes, voter, vote);
        };
        
        // Update vote counts
        if (vote) {
            approval_request.vote_count_for = approval_request.vote_count_for + 1;
        } else {
            approval_request.vote_count_against = approval_request.vote_count_against + 1;
        };
        
        // Check if decision threshold reached (simplified)
        let total_votes = approval_request.vote_count_for + approval_request.vote_count_against;
        if (total_votes >= 5) { // Minimum quorum
            if (approval_request.vote_count_for > approval_request.vote_count_against) {
                // Approve template
                approve_template(template, approval_request, manager, current_time);
            } else {
                // Reject template
                reject_template(template, approval_request, string::utf8(b"Insufficient votes"), current_time);
            };
        };
    }

    /// Activate approved template
    public entry fun activate_template(
        template: &mut CertificateTemplate,
        manager: &mut TemplateManager,
        _admin_cap: &TemplateAdminCap,
    ) {
        assert!(template.governance_approved, E_GOVERNANCE_NOT_APPROVED);
        assert!(template.status == STATUS_PENDING_APPROVAL, E_INVALID_TEMPLATE_DATA);
        
        template.is_active = true;
        template.status = STATUS_ACTIVE;
        manager.active_templates = manager.active_templates + 1;
        
        // Remove from pending approvals
        let template_id = object::uid_to_inner(&template.id);
        vec_set::remove(&mut manager.pending_approvals, &template_id);
    }

    // =============== Internal Helper Functions ===============

    fun update_template_indices(
        manager: &mut TemplateManager,
        template_id: ID,
        category: u8,
        cert_type: u8,
        creator: address,
    ) {
        // Update category index
        if (!table::contains(&manager.templates_by_category, category)) {
            table::add(&mut manager.templates_by_category, category, vec_set::empty());
        };
        let category_set = table::borrow_mut(&mut manager.templates_by_category, category);
        vec_set::insert(category_set, template_id);
        
        // Update type index
        if (!table::contains(&manager.templates_by_type, cert_type)) {
            table::add(&mut manager.templates_by_type, cert_type, vec_set::empty());
        };
        let type_set = table::borrow_mut(&mut manager.templates_by_type, cert_type);
        vec_set::insert(type_set, template_id);
        
        // Update creator index
        if (!table::contains(&manager.templates_by_creator, creator)) {
            table::add(&mut manager.templates_by_creator, creator, vec_set::empty());
        };
        let creator_set = table::borrow_mut(&mut manager.templates_by_creator, creator);
        vec_set::insert(creator_set, template_id);
    }

    fun validate_template_fields(template: &CertificateTemplate, field_values: &vector<String>) {
        assert!(vector::length(field_values) == vector::length(&template.template_fields), E_INVALID_FIELD_VALUE);
        
        let mut i = 0;
        while (i < vector::length(&template.template_fields)) {
            let field = vector::borrow(&template.template_fields, i);
            let value = vector::borrow(field_values, i);
            
            // Check required fields
            if (field.is_required) {
                assert!(!string::is_empty(value), E_INVALID_FIELD_VALUE);
            };
            
            // Validate field length
            if (option::is_some(&field.min_length)) {
                let min_len = *option::borrow(&field.min_length);
                assert!(string::length(value) >= min_len, E_INVALID_FIELD_VALUE);
            };
            
            if (option::is_some(&field.max_length)) {
                let max_len = *option::borrow(&field.max_length);
                assert!(string::length(value) <= max_len, E_INVALID_FIELD_VALUE);
            };
            
            i = i + 1;
        };
    }

    fun create_metadata_from_template(template: &CertificateTemplate, _field_values: &vector<String>): CertificateMetadata {
        // Create metadata based on template and field values
        certificates::create_certificate_metadata(
            option::none(),                        // exam_id
            option::none(),                        // project_id
            option::none(),                        // challenge_id
            option::none(),                        // course_id
            option::none(),                        // score
            option::none(),                        // grade
            template.required_skills,              // skills
            option::some(template.name),           // achievement_type
            vector::empty(),                       // validator_signatures
            option::none(),                        // completion_time
            option::some(template.level),          // difficulty_rating
            template.prerequisites,                // prerequisites_met
            string::utf8(b"")                      // additional_data - Would encode field_values as JSON
        )
    }

    fun approve_template(
        template: &mut CertificateTemplate,
        approval_request: &mut TemplateApprovalRequest,
        manager: &mut TemplateManager,
        timestamp: u64,
    ) {
        template.governance_approved = true;
        template.approved_at = option::some(timestamp);
        
        approval_request.status = 1; // Approved
        approval_request.decision_made_at = option::some(timestamp);
        
        // Return deposit to creator
        let deposit_amount = balance::value(&approval_request.approval_deposit);
        // Would transfer deposit back to creator
        
        event::emit(TemplateApproved {
            template_id: approval_request.template_id,
            approved_by: string::utf8(b"governance"),
            vote_count_for: approval_request.vote_count_for,
            vote_count_against: approval_request.vote_count_against,
            timestamp,
        });
    }

    fun reject_template(
        template: &mut CertificateTemplate,
        approval_request: &mut TemplateApprovalRequest,
        reason: String,
        timestamp: u64,
    ) {
        template.status = STATUS_REJECTED;
        template.rejection_reason = option::some(reason);
        
        approval_request.status = 2; // Rejected
        approval_request.decision_made_at = option::some(timestamp);
        
        // Forfeit deposit (goes to treasury)
        
        event::emit(TemplateRejected {
            template_id: approval_request.template_id,
            reason,
            vote_count_for: approval_request.vote_count_for,
            vote_count_against: approval_request.vote_count_against,
            timestamp,
        });
    }

    fun update_template_analytics(
        analytics: &mut TemplateAnalytics,
        template_id: ID,
        success: bool,
        timestamp: u64,
    ) {
        analytics.total_certificates_generated = analytics.total_certificates_generated + 1;
        analytics.last_updated = timestamp;
        
        // Update usage trends
        let day_epoch = timestamp / 86400000; // Daily epochs
        if (table::contains(&analytics.template_usage_trends, day_epoch)) {
            let count = table::borrow_mut(&mut analytics.template_usage_trends, day_epoch);
            *count = *count + 1;
        } else {
            table::add(&mut analytics.template_usage_trends, day_epoch, 1);
        };
        
        // Update failure rate
        if (!success) {
            if (table::contains(&analytics.failure_rate_by_template, template_id)) {
                let failures = table::borrow_mut(&mut analytics.failure_rate_by_template, template_id);
                *failures = *failures + 1;
            } else {
                table::add(&mut analytics.failure_rate_by_template, template_id, 1);
            };
        };
    }

    // =============== View Functions ===============

    public fun get_template_info(template: &CertificateTemplate): (String, u8, u8, u8, bool) {
        (template.name, template.category, template.certificate_type, template.level, template.is_active)
    }

    public fun get_template_usage_stats(template: &CertificateTemplate): (u64, u64, Option<u64>) {
        (template.usage_count, template.success_rate, template.last_used)
    }

    public fun get_template_fields(template: &CertificateTemplate): &vector<TemplateField> {
        &template.template_fields
    }

    public fun get_template_validation_rules(template: &CertificateTemplate): &vector<ValidationRule> {
        &template.validation_rules
    }

    public fun get_templates_by_category(manager: &TemplateManager, category: u8): vector<ID> {
        if (table::contains(&manager.templates_by_category, category)) {
            vec_set::into_keys(*table::borrow(&manager.templates_by_category, category))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_templates_by_creator(manager: &TemplateManager, creator: address): vector<ID> {
        if (table::contains(&manager.templates_by_creator, creator)) {
            vec_set::into_keys(*table::borrow(&manager.templates_by_creator, creator))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_manager_statistics(manager: &TemplateManager): (u64, u64, u64, u64) {
        (
            manager.total_templates,
            manager.active_templates,
            manager.total_usage_fees_collected,
            manager.creator_royalties_paid
        )
    }

    public fun is_template_approved(template: &CertificateTemplate): bool {
        template.governance_approved && template.is_active
    }

    public fun get_template_prerequisites(template: &CertificateTemplate): &vector<ID> {
        &template.prerequisites
    }

    public fun get_template_required_skills(template: &CertificateTemplate): &vector<String> {
        &template.required_skills
    }

    public fun get_pending_approvals(manager: &TemplateManager): vector<ID> {
        vec_set::into_keys(manager.pending_approvals)
    }
}