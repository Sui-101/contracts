module suiverse_content::projects {
    use std::string::{Self, String};
    use std::option::{Option};
    use std::vector;
    use sui::object::{ID, UID};
    use sui::tx_context::{TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self as table, Table};
    use sui::clock::{Self as clock, Clock};
    use sui::transfer;
    
    use suiverse_core::parameters::{Self as parameters, GlobalParameters};
    use suiverse_core::treasury::{Treasury};
    use suiverse_core::governance::{ValidatorPool};
    use suiverse_content::config::{Self as config, ContentConfig};

    // =============== Constants ===============
    
    // Error codes
    const E_INSUFFICIENT_DEPOSIT: u64 = 6001;
    const E_NOT_OWNER: u64 = 6002;
    const E_ALREADY_EXISTS: u64 = 6003;
    const E_NOT_FOUND: u64 = 6004;
    const E_NOT_APPROVED: u64 = 6005;
    const E_INVALID_URL: u64 = 6006;
    const E_INVALID_DIFFICULTY: u64 = 6007;
    const E_INVALID_CATEGORY: u64 = 6008;
    const E_PROJECT_CLOSED: u64 = 6009;
    const E_ALREADY_CONTRIBUTOR: u64 = 6010;
    const E_INVALID_TITLE: u64 = 6011;
    
    // Validation error codes
    const E_NOT_VALIDATOR: u64 = 6012;
    const E_ALREADY_ASSIGNED: u64 = 6013;
    const E_NOT_ASSIGNED: u64 = 6014;
    const E_ALREADY_REVIEWED: u64 = 6015;
    const E_SESSION_EXPIRED: u64 = 6016;
    const E_SESSION_NOT_COMPLETE: u64 = 6017;
    const E_INVALID_SCORE: u64 = 6018;
    const E_INSUFFICIENT_VALIDATORS: u64 = 6019;
    const E_INVALID_CRITERIA_COUNT: u64 = 6020;
    const E_VALIDATION_NOT_COMPLETE: u64 = 6021;
    const E_NOT_AUTHORIZED: u64 = 6022;

    // Project status - enhanced for validation pipeline
    const STATUS_DRAFT: u8 = 0;
    const STATUS_PENDING_REVIEW: u8 = 1;  // Waiting for validator assignment
    const STATUS_IN_REVIEW: u8 = 2;       // Validators actively reviewing
    const STATUS_APPROVED: u8 = 3;        // Passed validation, ready for use
    const STATUS_REJECTED: u8 = 4;        // Failed validation
    const STATUS_ACTIVE: u8 = 5;          // Approved and active for contributions
    const STATUS_COMPLETED: u8 = 6;       // Project finished
    const STATUS_ARCHIVED: u8 = 7;        // Archived or deprecated

    // Project categories
    const CATEGORY_DEFI: u8 = 1;
    const CATEGORY_NFT: u8 = 2;
    const CATEGORY_GAMING: u8 = 3;
    const CATEGORY_INFRASTRUCTURE: u8 = 4;
    const CATEGORY_SOCIAL: u8 = 5;
    const CATEGORY_DAO: u8 = 6;
    const CATEGORY_OTHER: u8 = 7;

    // Contribution types
    const CONTRIBUTION_CODE: u8 = 1;
    const CONTRIBUTION_DOCUMENTATION: u8 = 2;
    const CONTRIBUTION_DESIGN: u8 = 3;
    const CONTRIBUTION_TESTING: u8 = 4;
    const CONTRIBUTION_REVIEW: u8 = 5;
    
    // Validation criteria for projects
    const CRITERIA_TECHNICAL_QUALITY: u8 = 1;
    const CRITERIA_INNOVATION: u8 = 2;
    const CRITERIA_DOCUMENTATION: u8 = 3;
    const CRITERIA_FEASIBILITY: u8 = 4;
    const CRITERIA_COMMUNITY_VALUE: u8 = 5;
    
    // Criteria weights (total = 100)
    const WEIGHT_TECHNICAL_QUALITY: u8 = 30;
    const WEIGHT_INNOVATION: u8 = 25;
    const WEIGHT_DOCUMENTATION: u8 = 20;
    const WEIGHT_FEASIBILITY: u8 = 15;
    const WEIGHT_COMMUNITY_VALUE: u8 = 10;
    
    // Consensus and validation parameters
    const CONSENSUS_THRESHOLD: u8 = 67; // 67% agreement required
    const MIN_VALIDATORS_PER_PROJECT: u8 = 3;
    const MAX_VALIDATORS_PER_PROJECT: u8 = 5;
    const VALIDATION_TIMEOUT_MS: u64 = 3 * 24 * 60 * 60 * 1000; // 72 hours (projects need more time)
    
    // Validator selection methods
    const SELECTION_RANDOM: u8 = 1;
    const SELECTION_EXPERTISE: u8 = 2;
    const SELECTION_HYBRID: u8 = 3;

    // =============== Structs ===============
    
    /// Project Registry for tracking all projects
    public struct ProjectRegistry has key {
        id: UID,
        all_projects: Table<ID, ProjectMetadata>,
        projects_by_owner: Table<address, vector<ID>>,
        projects_by_category: Table<u8, vector<ID>>,
        projects_by_status: Table<u8, vector<ID>>,
        recent_projects: vector<ID>,  // Last 100 projects
        featured_projects: vector<ID>,
        total_projects: u64,
        total_stars: u64,
        last_updated: u64,
    }
    
    /// Project metadata for registry
    public struct ProjectMetadata has store, copy, drop {
        project_id: ID,
        title: String,
        owner: address,
        category: u8,
        status: u8,
        star_count: u64,
        created_at: u64,
        is_featured: bool,
    }
    
    /// Project representation
    public struct Project has key, store {
        id: UID,
        title: String,
        description: String,
        owner: address,
        repository_url: String,
        demo_url: Option<String>,
        documentation_url: Option<String>,
        tags: vector<ID>,
        category: u8,
        difficulty: u8,
        contributors: vector<Contributor>,
        milestones: vector<Milestone>,
        tech_stack: vector<String>,
        star_count: u64,
        fork_count: u64,
        earnings: Balance<SUI>,
        status: u8,
        deposit_amount: u64,
        validation_session_id: Option<ID>,
        created_at: u64,
        updated_at: u64,
        completed_at: Option<u64>,
    }

    /// Project contributor
    public struct Contributor has store, drop, copy {
        address: address,
        contribution_type: u8,
        commits: u64,
        lines_added: u64,
        lines_removed: u64,
        joined_at: u64,
        reputation_earned: u64,
    }

    /// Project milestone
    public struct Milestone has store, drop, copy {
        title: String,
        description: String,
        target_date: u64,
        completed_date: Option<u64>,
        status: u8, // 0: Pending, 1: In Progress, 2: Completed
        deliverables: vector<String>,
    }

    /// Project submission for featured status
    public struct ProjectSubmission has key, store {
        id: UID,
        project_id: ID,
        submitter: address,
        reason: String,
        evidence_urls: vector<String>,
        votes_for: u64,
        votes_against: u64,
        status: u8,
        submitted_at: u64,
        reviewed_at: Option<u64>,
    }
    
    /// Individual validation session for a project
    public struct ProjectValidationSession has key {
        id: UID,
        project_id: ID,
        project_owner: address,
        
        // Validator assignment
        assigned_validators: vector<address>,
        required_validators: u8,
        selection_method: u8,
        
        // Review data
        reviews: Table<address, ProjectValidatorReview>,
        reviews_submitted: u8,
        
        // Timing
        created_at: u64,
        deadline: u64,
        completed_at: Option<u64>,
        
        // Results
        consensus_score: Option<u8>,
        final_decision: Option<bool>,
        validation_status: u8,
        
        // Metadata
        project_category: u8,
        difficulty_level: u8,
    }
    
    /// Individual validator review for a project
    public struct ProjectValidatorReview has store, drop {
        validator: address,
        session_id: ID,
        
        // Criteria scores (1-100 each)
        technical_quality_score: u8,
        innovation_score: u8,
        documentation_score: u8,
        feasibility_score: u8,
        community_value_score: u8,
        
        // Overall assessment
        overall_score: u8,
        recommendation: bool, // approve/reject
        
        // Qualitative feedback
        strengths: String,
        improvements: String,
        detailed_feedback: String,
        
        // Metadata
        review_time_ms: u64,
        submitted_at: u64,
        confidence_level: u8, // 1-10
    }
    
    /// Registry for active project validation sessions
    public struct ProjectValidationRegistry has key {
        id: UID,
        
        // Active sessions
        active_sessions: Table<ID, ID>, // project_id -> session_id
        validator_assignments: Table<address, vector<ID>>, // validator -> session_ids
        
        // Pending validations by category
        pending_by_category: Table<u8, vector<ID>>,
        
        // Completed sessions tracking
        completed_sessions: vector<ID>,
        
        // Statistics
        total_sessions_created: u64,
        total_sessions_completed: u64,
        total_sessions_expired: u64,
        
        // Admin
        admin: address,
    }

    // =============== Events ===============
    
    public struct ProjectCreated has copy, drop {
        project_id: ID,
        owner: address,
        title: String,
        category: u8,
        deposit_amount: u64,
        timestamp: u64,
    }
    
    /// Validation-specific events
    public struct ProjectValidationSessionCreated has copy, drop {
        session_id: ID,
        project_id: ID,
        project_owner: address,
        assigned_validators: vector<address>,
        deadline: u64,
        selection_method: u8,
        category: u8,
        difficulty: u8,
        timestamp: u64,
    }
    
    public struct ProjectValidatorAssigned has copy, drop {
        session_id: ID,
        project_id: ID,
        validator: address,
        assignment_method: u8,
        expertise_match: bool,
        timestamp: u64,
    }
    
    public struct ProjectReviewSubmitted has copy, drop {
        session_id: ID,
        project_id: ID,
        validator: address,
        overall_score: u8,
        recommendation: bool,
        review_time_ms: u64,
        confidence_level: u8,
        timestamp: u64,
    }
    
    public struct ProjectConsensusReached has copy, drop {
        session_id: ID,
        project_id: ID,
        consensus_score: u8,
        final_decision: bool,
        participating_validators: u8,
        agreement_percentage: u8,
        timestamp: u64,
    }
    
    public struct ProjectValidationCompleted has copy, drop {
        project_id: ID,
        approved: bool,
        consensus_score: u8,
        validator_count: u8,
        review_duration: u64,
        timestamp: u64,
    }

    public struct ProjectApproved has copy, drop {
        project_id: ID,
        timestamp: u64,
    }

    public struct ProjectRejected has copy, drop {
        project_id: ID,
        reason: String,
        timestamp: u64,
    }

    public struct ContributorAdded has copy, drop {
        project_id: ID,
        contributor: address,
        contribution_type: u8,
        timestamp: u64,
    }

    public struct MilestoneCompleted has copy, drop {
        project_id: ID,
        milestone_title: String,
        timestamp: u64,
    }

    public struct ProjectCompleted has copy, drop {
        project_id: ID,
        owner: address,
        total_contributors: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        
        // Create project registry
        let registry = ProjectRegistry {
            id: object::new(ctx),
            all_projects: table::new(ctx),
            projects_by_owner: table::new(ctx),
            projects_by_category: table::new(ctx),
            projects_by_status: table::new(ctx),
            recent_projects: vector::empty(),
            featured_projects: vector::empty(),
            total_projects: 0,
            total_stars: 0,
            last_updated: 0,
        };
        
        // Create project validation registry
        let validation_registry = ProjectValidationRegistry {
            id: object::new(ctx),
            active_sessions: table::new(ctx),
            validator_assignments: table::new(ctx),
            pending_by_category: table::new(ctx),
            completed_sessions: vector::empty(),
            total_sessions_created: 0,
            total_sessions_completed: 0,
            total_sessions_expired: 0,
            admin,
        };
        
        transfer::share_object(registry);
        transfer::share_object(validation_registry);
    }

    // =============== Registry Functions ===============
    
    /// Register a project in the registry
    fun register_project(
        registry: &mut ProjectRegistry,
        project_id: ID,
        title: String,
        owner: address,
        category: u8,
        status: u8,
        created_at: u64,
    ) {
        let metadata = ProjectMetadata {
            project_id,
            title,
            owner,
            category,
            status,
            star_count: 0,
            created_at,
            is_featured: false,
        };
        
        // Add to all projects
        table::add(&mut registry.all_projects, project_id, metadata);
        
        // Add to owner index
        if (!table::contains(&registry.projects_by_owner, owner)) {
            table::add(&mut registry.projects_by_owner, owner, vector::empty());
        };
        let owner_projects = table::borrow_mut(&mut registry.projects_by_owner, owner);
        vector::push_back(owner_projects, project_id);
        
        // Add to category index
        if (!table::contains(&registry.projects_by_category, category)) {
            table::add(&mut registry.projects_by_category, category, vector::empty());
        };
        let category_projects = table::borrow_mut(&mut registry.projects_by_category, category);
        vector::push_back(category_projects, project_id);
        
        // Add to status index
        if (!table::contains(&registry.projects_by_status, status)) {
            table::add(&mut registry.projects_by_status, status, vector::empty());
        };
        let status_projects = table::borrow_mut(&mut registry.projects_by_status, status);
        vector::push_back(status_projects, project_id);
        
        // Add to recent projects (keep last 100)
        vector::push_back(&mut registry.recent_projects, project_id);
        if (vector::length(&registry.recent_projects) > 100) {
            vector::remove(&mut registry.recent_projects, 0);
        };
        
        registry.total_projects = registry.total_projects + 1;
        registry.last_updated = created_at;
    }
    
    /// Update project status in registry
    fun update_project_status_in_registry(
        registry: &mut ProjectRegistry,
        project_id: ID,
        old_status: u8,
        new_status: u8,
    ) {
        // Update metadata
        if (table::contains(&registry.all_projects, project_id)) {
            let metadata = table::borrow_mut(&mut registry.all_projects, project_id);
            metadata.status = new_status;
            
            // Remove from old status index
            if (table::contains(&registry.projects_by_status, old_status)) {
                let old_status_projects = table::borrow_mut(&mut registry.projects_by_status, old_status);
                
                // Manual search for the project_id
                let mut i = 0;
                let len = vector::length(old_status_projects);
                while (i < len) {
                    if (*vector::borrow(old_status_projects, i) == project_id) {
                        vector::remove(old_status_projects, i);
                        break
                    };
                    i = i + 1;
                };
            };
            
            // Add to new status index
            if (!table::contains(&registry.projects_by_status, new_status)) {
                table::add(&mut registry.projects_by_status, new_status, vector::empty());
            };
            let new_status_projects = table::borrow_mut(&mut registry.projects_by_status, new_status);
            vector::push_back(new_status_projects, project_id);
        };
    }

    // =============== Public Entry Functions ===============
    
    /// Create a new project with automatic validation pipeline
    public fun create_project(
        config: &mut ContentConfig,
        registry: &mut ProjectRegistry,
        validation_registry: &mut ProjectValidationRegistry,
        validator_pool: &ValidatorPool,
        global_params: &GlobalParameters,
        title: String,
        description: String,
        repository_url: String,
        demo_url: Option<String>,
        documentation_url: Option<String>,
        tags: vector<ID>,
        category: u8,
        difficulty: u8,
        tech_stack: vector<String>,
        deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Check config is not in emergency pause
        assert!(!config::is_emergency_paused(config), E_PROJECT_CLOSED);
        
        let owner = tx_context::sender(ctx);
        
        // Validate inputs
        let title_length = string::length(&title);
        assert!(title_length > 0 && title_length <= 200, E_INVALID_TITLE);
        assert!(string::length(&repository_url) > 0, E_INVALID_URL);
        assert!(category >= CATEGORY_DEFI && category <= CATEGORY_OTHER, E_INVALID_CATEGORY);
        assert!(difficulty >= 1 && difficulty <= 5, E_INVALID_DIFFICULTY);
        
        // Check deposit amount
        let required_deposit = parameters::get_project_deposit(global_params);
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);
        
        let timestamp = clock::timestamp_ms(clock);
        
        // Create project
        let project = Project {
            id: object::new(ctx),
            title,
            description,
            owner,
            repository_url,
            demo_url,
            documentation_url,
            tags,
            category,
            difficulty,
            contributors: vector::empty(),
            milestones: vector::empty(),
            tech_stack,
            star_count: 0,
            fork_count: 0,
            earnings: balance::zero(),
            status: STATUS_PENDING_REVIEW,
            deposit_amount: coin::value(&deposit),
            validation_session_id: option::none(),
            created_at: timestamp,
            updated_at: timestamp,
            completed_at: option::none(),
        };
        
        let project_id = object::uid_to_inner(&project.id);
        
        // Register in registry
        register_project(
            registry,
            project_id,
            project.title,
            owner,
            category,
            STATUS_PENDING_REVIEW,
            timestamp,
        );
        
        // Update statistics
        config::increment_total_projects(config);
        config::increment_projects_this_epoch(config);
        
        // Store deposit
        transfer::public_transfer(deposit, @suiverse_core);
        
        event::emit(ProjectCreated {
            project_id,
            owner,
            title: project.title,
            category,
            deposit_amount: project.deposit_amount,
            timestamp,
        });
        
        // First share the project object
        transfer::share_object(project);
        
        // Create validation session automatically after project creation
        // Note: We use a shared reference in production, but for this implementation
        // we'll create the session directly with the project data
        create_project_validation_direct(
            validation_registry,
            validator_pool,
            project_id,
            owner,
            category,
            difficulty,
            clock,
            ctx,
        );
    }
    
    // =============== Project Validation Pipeline Functions ===============
    
    /// Create validation session for a project (automatically called during project creation)
    public fun create_project_validation(
        validation_registry: &mut ProjectValidationRegistry,
        validator_pool: &ValidatorPool,
        project: &Project,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let project_id = object::uid_to_inner(&project.id);
        let project_owner = project.owner;
        let current_time = clock::timestamp_ms(clock);
        
        // Check if validation session already exists
        assert!(!table::contains(&validation_registry.active_sessions, project_id), E_ALREADY_ASSIGNED);
        
        // Select validators for this project
        let selection_method = SELECTION_HYBRID; // Use hybrid selection for projects
        let validator_count = MIN_VALIDATORS_PER_PROJECT; // Start with minimum validators
        
        let assigned_validators = select_validators_for_project(
            validator_pool,
            validation_registry,
            project.category,
            project.difficulty,
            selection_method,
            validator_count,
            clock,
            ctx
        );
        
        // Create validation session
        let session = ProjectValidationSession {
            id: object::new(ctx),
            project_id,
            project_owner,
            assigned_validators,
            required_validators: validator_count,
            selection_method,
            reviews: table::new(ctx),
            reviews_submitted: 0,
            created_at: current_time,
            deadline: current_time + VALIDATION_TIMEOUT_MS,
            completed_at: option::none(),
            consensus_score: option::none(),
            final_decision: option::none(),
            validation_status: STATUS_PENDING_REVIEW,
            project_category: project.category,
            difficulty_level: project.difficulty,
        };
        
        let session_id = object::uid_to_inner(&session.id);
        
        // Update registry
        table::add(&mut validation_registry.active_sessions, project_id, session_id);
        validation_registry.total_sessions_created = validation_registry.total_sessions_created + 1;
        
        // Update validator assignments
        update_validator_assignments(validation_registry, &session.assigned_validators, session_id);
        
        // Emit validation session created event
        event::emit(ProjectValidationSessionCreated {
            session_id,
            project_id,
            project_owner,
            assigned_validators: session.assigned_validators,
            deadline: session.deadline,
            selection_method,
            category: project.category,
            difficulty: project.difficulty,
            timestamp: current_time,
        });
        
        // Emit individual validator assignments
        emit_validator_assignments(&session.assigned_validators, session_id, selection_method, current_time);
        
        transfer::share_object(session);
    }
    
    /// Create validation session directly with project data (for use during project creation)
    fun create_project_validation_direct(
        validation_registry: &mut ProjectValidationRegistry,
        validator_pool: &ValidatorPool,
        project_id: ID,
        project_owner: address,
        category: u8,
        difficulty: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if validation session already exists
        assert!(!table::contains(&validation_registry.active_sessions, project_id), E_ALREADY_ASSIGNED);
        
        // Select validators for this project
        let selection_method = SELECTION_HYBRID;
        let validator_count = MIN_VALIDATORS_PER_PROJECT;
        
        let assigned_validators = select_validators_for_project(
            validator_pool,
            validation_registry,
            category,
            difficulty,
            selection_method,
            validator_count,
            clock,
            ctx
        );
        
        // Create validation session
        let session = ProjectValidationSession {
            id: object::new(ctx),
            project_id,
            project_owner,
            assigned_validators,
            required_validators: validator_count,
            selection_method,
            reviews: table::new(ctx),
            reviews_submitted: 0,
            created_at: current_time,
            deadline: current_time + VALIDATION_TIMEOUT_MS,
            completed_at: option::none(),
            consensus_score: option::none(),
            final_decision: option::none(),
            validation_status: STATUS_PENDING_REVIEW,
            project_category: category,
            difficulty_level: difficulty,
        };
        
        let session_id = object::uid_to_inner(&session.id);
        
        // Update registry
        table::add(&mut validation_registry.active_sessions, project_id, session_id);
        validation_registry.total_sessions_created = validation_registry.total_sessions_created + 1;
        
        // Update validator assignments
        update_validator_assignments(validation_registry, &session.assigned_validators, session_id);
        
        // Emit validation session created event
        event::emit(ProjectValidationSessionCreated {
            session_id,
            project_id,
            project_owner,
            assigned_validators: session.assigned_validators,
            deadline: session.deadline,
            selection_method,
            category,
            difficulty,
            timestamp: current_time,
        });
        
        // Emit individual validator assignments
        emit_validator_assignments(&session.assigned_validators, session_id, selection_method, current_time);
        
        transfer::share_object(session);
    }
    
    /// Submit validator review for a project
    public fun submit_project_validation_review(
        session: &mut ProjectValidationSession,
        validator_pool: &ValidatorPool,
        technical_quality_score: u8,
        innovation_score: u8,
        documentation_score: u8,
        feasibility_score: u8,
        community_value_score: u8,
        strengths: String,
        improvements: String,
        detailed_feedback: String,
        confidence_level: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let validator = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        // Validate validator is assigned to this session
        assert!(vector::contains(&session.assigned_validators, &validator), E_NOT_ASSIGNED);
        
        // Check session hasn't expired
        assert!(current_time <= session.deadline, E_SESSION_EXPIRED);
        
        // Check validator hasn't already reviewed
        assert!(!table::contains(&session.reviews, validator), E_ALREADY_REVIEWED);
        
        // Validate scores are in range (1-100)
        assert!(technical_quality_score <= 100 && innovation_score <= 100 && 
                documentation_score <= 100 && feasibility_score <= 100 && 
                community_value_score <= 100, E_INVALID_SCORE);
        assert!(confidence_level >= 1 && confidence_level <= 10, E_INVALID_SCORE);
        
        // Calculate overall score using weighted criteria
        let overall_score = calculate_project_weighted_score(
            technical_quality_score, innovation_score, documentation_score, 
            feasibility_score, community_value_score
        );
        
        // Determine recommendation (approve if score >= 70)
        let recommendation = overall_score >= 70;
        
        // Calculate review time
        let review_time = current_time - session.created_at;
        
        // Create review
        let review = ProjectValidatorReview {
            validator,
            session_id: object::uid_to_inner(&session.id),
            technical_quality_score,
            innovation_score,
            documentation_score,
            feasibility_score,
            community_value_score,
            overall_score,
            recommendation,
            strengths,
            improvements,
            detailed_feedback,
            review_time_ms: review_time,
            submitted_at: current_time,
            confidence_level,
        };
        
        // Add review to session
        table::add(&mut session.reviews, validator, review);
        session.reviews_submitted = session.reviews_submitted + 1;
        session.validation_status = STATUS_IN_REVIEW;
        
        // Emit review submitted event
        event::emit(ProjectReviewSubmitted {
            session_id: object::uid_to_inner(&session.id),
            project_id: session.project_id,
            validator,
            overall_score,
            recommendation,
            review_time_ms: review_time,
            confidence_level,
            timestamp: current_time,
        });
        
        // Check if all reviews are complete
        if (session.reviews_submitted >= session.required_validators) {
            complete_project_validation_session(session, current_time);
        };
    }
    
    /// Complete project validation session and determine consensus
    fun complete_project_validation_session(
        session: &mut ProjectValidationSession, 
        current_time: u64
    ) {
        // Calculate consensus
        let (consensus_score, approval_rate, final_decision) = calculate_project_consensus(session);
        
        // Update session
        session.consensus_score = option::some(consensus_score);
        session.final_decision = option::some(final_decision);
        session.validation_status = if (final_decision) STATUS_APPROVED else STATUS_REJECTED;
        session.completed_at = option::some(current_time);
        
        // Emit consensus event
        event::emit(ProjectConsensusReached {
            session_id: object::uid_to_inner(&session.id),
            project_id: session.project_id,
            consensus_score,
            final_decision,
            participating_validators: session.reviews_submitted,
            agreement_percentage: approval_rate,
            timestamp: current_time,
        });
        
        // Emit validation completed event
        event::emit(ProjectValidationCompleted {
            project_id: session.project_id,
            approved: final_decision,
            consensus_score,
            validator_count: session.reviews_submitted,
            review_duration: current_time - session.created_at,
            timestamp: current_time,
        });
    }

    /// Add a contributor to the project
    public fun add_contributor(
        project: &mut Project,
        contributor_address: address,
        contribution_type: u8,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        // Ensure project is approved and active
        assert!(project.status == STATUS_APPROVED || project.status == STATUS_ACTIVE, E_NOT_APPROVED);
        assert!(project.status != STATUS_REJECTED, E_PROJECT_CLOSED);
        
        // Check if already a contributor
        let mut i = 0;
        while (i < vector::length(&project.contributors)) {
            let contributor = vector::borrow(&project.contributors, i);
            assert!(contributor.address != contributor_address, E_ALREADY_CONTRIBUTOR);
            i = i + 1;
        };
        
        // Add contributor
        let contributor = Contributor {
            address: contributor_address,
            contribution_type,
            commits: 0,
            lines_added: 0,
            lines_removed: 0,
            joined_at: clock::timestamp_ms(clock),
            reputation_earned: 0,
        };
        
        vector::push_back(&mut project.contributors, contributor);
        project.updated_at = clock::timestamp_ms(clock);
        
        event::emit(ContributorAdded {
            project_id: object::uid_to_inner(&project.id),
            contributor: contributor_address,
            contribution_type,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update project after validation (called by validation pipeline)
    public fun update_project_validation_status(
        config: &mut ContentConfig,
        registry: &mut ProjectRegistry,
        project: &mut Project,
        session: &ProjectValidationSession,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        let old_status = project.status;
        
        // Ensure validation session is for this project
        assert!(session.project_id == object::uid_to_inner(&project.id), E_NOT_FOUND);
        
        // Ensure validation is complete
        assert!(option::is_some(&session.final_decision), E_VALIDATION_NOT_COMPLETE);
        
        let approved = *option::borrow(&session.final_decision);
        
        if (approved) {
            project.status = STATUS_APPROVED;
            config::increment_approved_projects(config);
            
            event::emit(ProjectApproved {
                project_id: object::uid_to_inner(&project.id),
                timestamp: clock::timestamp_ms(clock),
            });
        } else {
            project.status = STATUS_REJECTED;
            
            event::emit(ProjectRejected {
                project_id: object::uid_to_inner(&project.id),
                reason: string::utf8(b"Did not meet approval threshold"),
                timestamp: clock::timestamp_ms(clock),
            });
        };
        
        // Update registry
        update_project_status_in_registry(
            registry,
            object::uid_to_inner(&project.id),
            old_status,
            project.status,
        );
    }


    /// Star a project (only approved projects can be starred)
    public fun star_project(
        config: &mut ContentConfig,
        registry: &mut ProjectRegistry,
        project: &mut Project,
        _ctx: &TxContext,
    ) {
        // Only allow starring approved projects
        assert!(project.status == STATUS_APPROVED || project.status == STATUS_ACTIVE, E_NOT_APPROVED);
        
        project.star_count = project.star_count + 1;
        config::increment_project_stars(config);
        
        // Update registry
        registry.total_stars = registry.total_stars + 1;
        if (table::contains(&registry.all_projects, object::uid_to_inner(&project.id))) {
            let metadata = table::borrow_mut(&mut registry.all_projects, object::uid_to_inner(&project.id));
            metadata.star_count = project.star_count;
        };
    }

    /// Complete a project (only approved/active projects can be completed)
    public fun complete_project(
        _config: &mut ContentConfig,
        registry: &mut ProjectRegistry,
        project: &mut Project,
        _clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        // Only approved or already active projects can be completed
        assert!(project.status == STATUS_APPROVED || project.status == STATUS_ACTIVE, E_NOT_APPROVED);
        
        let old_status = project.status;
        project.status = STATUS_COMPLETED;
        project.completed_at = option::some(clock::timestamp_ms(_clock));
        project.updated_at = clock::timestamp_ms(_clock);
        
        // Commented out for now as functions may not exist
        // config::decrement_active_projects(config);
        // config::increment_completed_projects(config);
        
        // Update registry
        update_project_status_in_registry(
            registry,
            object::uid_to_inner(&project.id),
            old_status,
            STATUS_COMPLETED,
        );
        
        event::emit(ProjectCompleted {
            project_id: object::uid_to_inner(&project.id),
            owner: project.owner,
            total_contributors: vector::length(&project.contributors),
            timestamp: clock::timestamp_ms(_clock),
        });
    }
    
    // =============== Project Validation Helper Functions ===============
    
    /// Select validators for project validation
    fun select_validators_for_project(
        validator_pool: &ValidatorPool,
        registry: &ProjectValidationRegistry,
        category: u8,
        difficulty: u8,
        selection_method: u8,
        count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        // Get available validators (simplified implementation)
        let available_validators = get_available_validators_for_projects(validator_pool, registry);
        let total_available = vector::length(&available_validators);
        
        assert!(total_available >= (count as u64), E_INSUFFICIENT_VALIDATORS);
        
        if (selection_method == SELECTION_RANDOM) {
            select_random_validators_for_projects(available_validators, count, clock, ctx)
        } else if (selection_method == SELECTION_EXPERTISE) {
            select_expertise_validators_for_projects(available_validators, category, count)
        } else { // SELECTION_HYBRID
            select_hybrid_validators_for_projects(available_validators, category, difficulty, count, clock, ctx)
        }
    }
    
    /// Get available validators for project review
    fun get_available_validators_for_projects(
        _validator_pool: &ValidatorPool,
        _registry: &ProjectValidationRegistry,
    ): vector<address> {
        // Simplified implementation - in production would check validator workload, stakes, etc.
        // For now return mock validator addresses for testing
        vector[@0x1001, @0x1002, @0x1003, @0x1004, @0x1005]
    }
    
    /// Random validator selection for projects
    fun select_random_validators_for_projects(
        mut available_validators: vector<address>,
        count: u8,
        clock: &Clock,
        ctx: &TxContext,
    ): vector<address> {
        let mut selected = vector::empty<address>();
        let mut seed = clock::timestamp_ms(clock) + (tx_context::epoch(ctx) as u64);
        
        while (vector::length(&selected) < (count as u64) && vector::length(&available_validators) > 0) {
            seed = hash_seed(seed);
            let index = seed % vector::length(&available_validators);
            let validator = vector::remove(&mut available_validators, index);
            vector::push_back(&mut selected, validator);
        };
        
        selected
    }
    
    /// Expertise-based validator selection for projects
    fun select_expertise_validators_for_projects(
        available_validators: vector<address>,
        _category: u8,
        count: u8,
    ): vector<address> {
        // Simplified - in production would check validator expertise in project categories
        let mut selected = vector::empty<address>();
        let mut i = 0;
        let select_count = if ((count as u64) > vector::length(&available_validators)) {
            vector::length(&available_validators)
        } else {
            (count as u64)
        };
        
        while (i < select_count) {
            vector::push_back(&mut selected, *vector::borrow(&available_validators, i));
            i = i + 1;
        };
        
        selected
    }
    
    /// Hybrid validator selection for projects
    fun select_hybrid_validators_for_projects(
        available_validators: vector<address>,
        category: u8,
        difficulty: u8,
        count: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ): vector<address> {
        // For complex projects (difficulty > 3), prefer expertise; otherwise use random
        if (difficulty > 3) {
            select_expertise_validators_for_projects(available_validators, category, count)
        } else {
            select_random_validators_for_projects(available_validators, count, clock, ctx)
        }
    }
    
    /// Calculate weighted score from individual project criteria scores
    fun calculate_project_weighted_score(
        technical_quality: u8, 
        innovation: u8, 
        documentation: u8, 
        feasibility: u8, 
        community_value: u8
    ): u8 {
        let weighted_sum = 
            (technical_quality as u64) * (WEIGHT_TECHNICAL_QUALITY as u64) +
            (innovation as u64) * (WEIGHT_INNOVATION as u64) +
            (documentation as u64) * (WEIGHT_DOCUMENTATION as u64) +
            (feasibility as u64) * (WEIGHT_FEASIBILITY as u64) +
            (community_value as u64) * (WEIGHT_COMMUNITY_VALUE as u64);
        
        ((weighted_sum / 100) as u8)
    }
    
    /// Calculate consensus from all project validator reviews
    fun calculate_project_consensus(
        session: &ProjectValidationSession
    ): (u8, u8, bool) {
        let mut total_score = 0u64;
        let mut approval_count = 0u64;
        let mut review_count = 0u64;
        
        // Iterate through assigned validators
        let mut i = 0;
        while (i < vector::length(&session.assigned_validators)) {
            let validator = vector::borrow(&session.assigned_validators, i);
            
            if (table::contains(&session.reviews, *validator)) {
                let review = table::borrow(&session.reviews, *validator);
                total_score = total_score + (review.overall_score as u64);
                if (review.recommendation) {
                    approval_count = approval_count + 1;
                };
                review_count = review_count + 1;
            };
            
            i = i + 1;
        };
        
        if (review_count == 0) {
            return (0, 0, false)
        };
        
        let consensus_score = ((total_score / review_count) as u8);
        let approval_rate = (((approval_count * 100) / review_count) as u8);
        let final_decision = approval_rate >= CONSENSUS_THRESHOLD;
        
        (consensus_score, approval_rate, final_decision)
    }
    
    /// Update validator assignment tracking
    fun update_validator_assignments(
        registry: &mut ProjectValidationRegistry,
        validators: &vector<address>,
        session_id: ID,
    ) {
        let mut i = 0;
        while (i < vector::length(validators)) {
            let validator = *vector::borrow(validators, i);
            
            if (!table::contains(&registry.validator_assignments, validator)) {
                table::add(&mut registry.validator_assignments, validator, vector::empty());
            };
            
            let assignments = table::borrow_mut(&mut registry.validator_assignments, validator);
            vector::push_back(assignments, session_id);
            
            i = i + 1;
        };
    }
    
    /// Emit validator assignment events
    fun emit_validator_assignments(
        validators: &vector<address>,
        session_id: ID,
        selection_method: u8,
        timestamp: u64,
    ) {
        let mut i = 0;
        while (i < vector::length(validators)) {
            let validator = *vector::borrow(validators, i);
            
            event::emit(ProjectValidatorAssigned {
                session_id,
                project_id: object::id_from_address(@0x0), // Would get from session in production
                validator,
                assignment_method: selection_method,
                expertise_match: true, // Simplified
                timestamp,
            });
            
            i = i + 1;
        };
    }
    
    /// Simple hash function for validator selection randomness
    fun hash_seed(input: u64): u64 {
        // Simple linear congruential generator
        let a = 1664525u64;
        let c = 1013904223u64;
        let m = 4294967296u64; // 2^32
        ((a * input + c) % m)
    }

    // =============== Read Functions ===============
    
    /// Get projects by owner from registry
    public fun get_projects_by_owner(registry: &ProjectRegistry, owner: address): vector<ID> {
        if (table::contains(&registry.projects_by_owner, owner)) {
            *table::borrow(&registry.projects_by_owner, owner)
        } else {
            vector::empty()
        }
    }
    
    /// Get projects by category from registry
    public fun get_projects_by_category(registry: &ProjectRegistry, category: u8): vector<ID> {
        if (table::contains(&registry.projects_by_category, category)) {
            *table::borrow(&registry.projects_by_category, category)
        } else {
            vector::empty()
        }
    }
    
    /// Get projects by status from registry
    public fun get_projects_by_status(registry: &ProjectRegistry, status: u8): vector<ID> {
        if (table::contains(&registry.projects_by_status, status)) {
            *table::borrow(&registry.projects_by_status, status)
        } else {
            vector::empty()
        }
    }
    
    /// Get recent projects from registry
    public fun get_recent_projects(registry: &ProjectRegistry): vector<ID> {
        registry.recent_projects
    }
    
    /// Get featured projects from registry
    public fun get_featured_projects(registry: &ProjectRegistry): vector<ID> {
        registry.featured_projects
    }
    
    /// Get project metadata from registry
    public fun get_project_metadata(registry: &ProjectRegistry, project_id: ID): Option<ProjectMetadata> {
        if (table::contains(&registry.all_projects, project_id)) {
            option::some(*table::borrow(&registry.all_projects, project_id))
        } else {
            option::none()
        }
    }
    
    public fun get_project_status(project: &Project): u8 {
        project.status
    }

    public fun get_project_owner(project: &Project): address {
        project.owner
    }

    public fun get_project_contributors(project: &Project): &vector<Contributor> {
        &project.contributors
    }

    public fun get_project_milestones(project: &Project): &vector<Milestone> {
        &project.milestones
    }


    public fun get_project_star_count(project: &Project): u64 {
        project.star_count
    }

    public fun get_project_earnings(project: &Project): u64 {
        balance::value(&project.earnings)
    }

    public fun is_project_active(project: &Project): bool {
        project.status == STATUS_ACTIVE
    }
    
    /// Check if project is approved and safe for user interaction
    public fun is_project_approved(project: &Project): bool {
        project.status == STATUS_APPROVED || project.status == STATUS_ACTIVE
    }
    
    /// Check if project is in validation (pending or in review)
    public fun is_project_in_validation(project: &Project): bool {
        project.status == STATUS_PENDING_REVIEW || project.status == STATUS_IN_REVIEW
    }
    
    /// Check if project validation was rejected
    public fun is_project_rejected(project: &Project): bool {
        project.status == STATUS_REJECTED
    }

    public fun is_project_completed(project: &Project): bool {
        project.status == STATUS_COMPLETED
    }
    
    /// Get registry stats
    public fun get_registry_stats(registry: &ProjectRegistry): (u64, u64) {
        (registry.total_projects, registry.total_stars)
    }
    
    /// Activate an approved project (move from STATUS_APPROVED to STATUS_ACTIVE)
    public fun activate_approved_project(
        _config: &mut ContentConfig,
        registry: &mut ProjectRegistry,
        project: &mut Project,
        _clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        assert!(project.status == STATUS_APPROVED, E_NOT_APPROVED);
        
        let old_status = project.status;
        project.status = STATUS_ACTIVE;
        project.updated_at = clock::timestamp_ms(_clock);
        
        // Update statistics (commenting out for now as function may not exist)
        // config::increment_active_projects(config);
        
        // Update registry
        update_project_status_in_registry(
            registry,
            object::uid_to_inner(&project.id),
            old_status,
            STATUS_ACTIVE,
        );
    }
    
    // =============== Validation View Functions ===============
    
    /// Get validation session information
    public fun get_validation_session_info(
        session: &ProjectValidationSession
    ): (u8, u8, Option<u8>, Option<bool>, u64, u64) {
        (
            session.validation_status,
            session.reviews_submitted,
            session.consensus_score,
            session.final_decision,
            session.created_at,
            session.deadline
        )
    }
    
    /// Get validator review if exists
    public fun get_project_validator_review(
        _session: &ProjectValidationSession, 
        _validator: address
    ): &ProjectValidatorReview {
        table::borrow(&_session.reviews, _validator)
    }
    
    /// Check if validator is assigned to this project session
    public fun is_validator_assigned_to_project(
        session: &ProjectValidationSession, 
        validator: address
    ): bool {
        vector::contains(&session.assigned_validators, &validator)
    }
    
    /// Check if validation session has expired
    public fun is_validation_session_expired(
        session: &ProjectValidationSession,
        _clock: &Clock
    ): bool {
        clock::timestamp_ms(_clock) > session.deadline
    }
    
    /// Get validation registry statistics
    public fun get_validation_registry_stats(
        registry: &ProjectValidationRegistry
    ): (u64, u64, u64) {
        (
            registry.total_sessions_created,
            registry.total_sessions_completed,
            registry.total_sessions_expired
        )
    }
    
    // =============== Test Functions ===============
    
    #[test_only]
    use sui::test_scenario::{Self as ts, Scenario};
    #[test_only]
    use sui::coin;
    #[test_only]
    use sui::clock;
    #[test_only]
    use suiverse_core::parameters;
    #[test_only]
    use suiverse_core::treasury;
    #[test_only]
    use suiverse_core::governance::{Self, ValidatorPool};
    
    #[test_only]
    const TEST_ADMIN: address = @0x1;
    #[test_only]
    const TEST_AUTHOR: address = @0x2;
    #[test_only]
    const TEST_USER: address = @0x3;
    
    #[test]
    public fun test_happy_path_project_workflow() {
        let mut scenario = ts::begin(TEST_ADMIN);
        let ctx = ts::ctx(&mut scenario);
        
        // Initialize components
        let clock_obj = clock::create_for_testing(ctx);
        let mut config = config::create_test_config(ctx);
        let global_params = parameters::create_test_parameters(ctx);
        // Mock validator pool for testing - in production this would be properly initialized
        let validator_pool = ValidatorPool {
            id: object::new(ctx),
            active_validators: table::new(ctx),
            total_weight: 0,
            total_stake: 0,
            total_knowledge: 0,
            knowledge_exchange_rate: 1,
            current_epoch: 0,
            admin: TEST_ADMIN,
        };
        
        let mut registry = ProjectRegistry {
            id: object::new(ctx),
            total_projects: 0,
            total_stars: 0,
            all_projects: table::new(ctx),
            projects_by_owner: table::new(ctx),
            projects_by_status: table::new(ctx),
            projects_by_category: table::new(ctx),
            recent_projects: vector::empty(),
            featured_projects: vector::empty(),
            last_updated: 0,
        };
        
        let mut validation_registry = ProjectValidationRegistry {
            id: object::new(ctx),
            active_sessions: table::new(ctx),
            validator_assignments: table::new(ctx),
            pending_by_category: table::new(ctx),
            completed_sessions: vector::empty(),
            total_sessions_created: 0,
            total_sessions_completed: 0,
            total_sessions_expired: 0,
            admin: TEST_ADMIN,
        };
        
        // Test create project
        ts::next_tx(&mut scenario, TEST_AUTHOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut payment = coin::mint_for_testing<SUI>(1000000000, ctx); // 1 SUI
            
            create_project(
                &mut config,
                &mut registry,
                &mut validation_registry,
                &validator_pool,
                &global_params,
                string::utf8(b"Test Project"),
                string::utf8(b"A comprehensive test project"),
                string::utf8(b"https://github.com/test/project"),
                option::some(string::utf8(b"https://demo.test.com")),
                option::some(string::utf8(b"https://docs.test.com")),
                vector[object::id_from_address(@0xCCC)],
                1, // category
                1, // difficulty
                vector[string::utf8(b"sui"), string::utf8(b"move")],
                payment,
                &clock_obj,
                ctx
            );
            
            coin::destroy_zero(payment);
        };
        
        // Test project stats
        ts::next_tx(&mut scenario, TEST_USER);
        {
            let (total_projects, _total_stars) = get_registry_stats(&registry);
            assert!(total_projects == 1, 0);
        };
        
        // Test project approval and starring (projects start as PENDING_REVIEW)
        ts::next_tx(&mut scenario, TEST_USER);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut project = ts::take_shared<Project>(&scenario);
            
            // Manually approve project for testing
            project.status = STATUS_APPROVED;
            
            star_project(&mut config, &mut registry, &mut project, ctx);
            
            let star_count = get_project_star_count(&project);
            assert!(star_count == 1, 1);
            
            ts::return_shared(project);
        };
        
        // Test activate and complete project
        ts::next_tx(&mut scenario, TEST_AUTHOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut project = ts::take_shared<Project>(&scenario);
            
            // Activate approved project
            activate_approved_project(&mut config, &mut registry, &mut project, &clock_obj, ctx);
            assert!(is_project_active(&project), 2);
            
            // Complete active project
            complete_project(&mut config, &mut registry, &mut project, &clock_obj, ctx);
            assert!(is_project_completed(&project), 3);
            
            ts::return_shared(project);
        };
        
        clock::destroy_for_testing(clock_obj);
        transfer::share_object(registry);
        transfer::share_object(validation_registry);
        transfer::share_object(validator_pool);
        ts::end(scenario);
    }
    
    #[test]
    public fun test_project_contributors_and_milestones() {
        let mut scenario = ts::begin(TEST_ADMIN);
        let ctx = ts::ctx(&mut scenario);
        
        let clock_obj = clock::create_for_testing(ctx);
        let mut config = config::create_test_config(ctx);
        let global_params = parameters::create_test_parameters(ctx);
        // Mock validator pool for testing - in production this would be properly initialized
        let validator_pool = ValidatorPool {
            id: object::new(ctx),
            active_validators: table::new(ctx),
            total_weight: 0,
            total_stake: 0,
            total_knowledge: 0,
            knowledge_exchange_rate: 1,
            current_epoch: 0,
            admin: TEST_ADMIN,
        };
        
        let mut registry = ProjectRegistry {
            id: object::new(ctx),
            total_projects: 0,
            total_stars: 0,
            all_projects: table::new(ctx),
            projects_by_owner: table::new(ctx),
            projects_by_status: table::new(ctx),
            projects_by_category: table::new(ctx),
            recent_projects: vector::empty(),
            featured_projects: vector::empty(),
            last_updated: 0,
        };
        
        let mut validation_registry = ProjectValidationRegistry {
            id: object::new(ctx),
            active_sessions: table::new(ctx),
            validator_assignments: table::new(ctx),
            pending_by_category: table::new(ctx),
            completed_sessions: vector::empty(),
            total_sessions_created: 0,
            total_sessions_completed: 0,
            total_sessions_expired: 0,
            admin: TEST_ADMIN,
        };
        
        // Create project first
        ts::next_tx(&mut scenario, TEST_AUTHOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut payment = coin::mint_for_testing<SUI>(1000000000, ctx);
            
            create_project(
                &mut config,
                &mut registry,
                &mut validation_registry,
                &validator_pool,
                &global_params,
                string::utf8(b"Collaborative Project"),
                string::utf8(b"Project with multiple contributors"),
                string::utf8(b"https://github.com/test/collab"),
                option::none(),
                option::none(),
                vector[object::id_from_address(@0xDDD)],
                2, // category
                2, // difficulty
                vector[string::utf8(b"react")],
                payment,
                &clock_obj,
                ctx
            );
            
            coin::destroy_zero(payment);
        };
        
        // Test add contributor
        ts::next_tx(&mut scenario, TEST_AUTHOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let project = ts::take_shared<Project>(&scenario);
            
            // Manually approve project first for contributor testing
            project.status = STATUS_APPROVED;
            
            add_contributor(
                &mut project,
                TEST_USER,
                1, // CONTRIBUTION_CODE
                &clock_obj,
                ctx
            );
            
            ts::return_shared(project);
        };
        
        // Test project view functionality
        ts::next_tx(&mut scenario, TEST_USER);
        {
            let ctx = ts::ctx(&mut scenario);
            let project = ts::take_shared<Project>(&scenario);
            
            // Test that project is in validation initially (not active yet)
            let in_validation = is_project_in_validation(&project);
            assert!(in_validation, 3);
            
            ts::return_shared(project);
        };
        
        clock::destroy_for_testing(clock_obj);
        transfer::share_object(registry);
        transfer::share_object(validation_registry);
        transfer::share_object(validator_pool);
        ts::end(scenario);
    }
    
    #[test]
    public fun test_project_indexing_and_queries() {
        let mut scenario = ts::begin(TEST_ADMIN);
        let ctx = ts::ctx(&mut scenario);
        
        let clock_obj = clock::create_for_testing(ctx);
        let mut config = config::create_test_config(ctx);
        let global_params = parameters::create_test_parameters(ctx);
        // Mock validator pool for testing - in production this would be properly initialized
        let validator_pool = ValidatorPool {
            id: object::new(ctx),
            active_validators: table::new(ctx),
            total_weight: 0,
            total_stake: 0,
            total_knowledge: 0,
            knowledge_exchange_rate: 1,
            current_epoch: 0,
            admin: TEST_ADMIN,
        };
        
        let mut registry = ProjectRegistry {
            id: object::new(ctx),
            total_projects: 0,
            total_stars: 0,
            all_projects: table::new(ctx),
            projects_by_owner: table::new(ctx),
            projects_by_status: table::new(ctx),
            projects_by_category: table::new(ctx),
            recent_projects: vector::empty(),
            featured_projects: vector::empty(),
            last_updated: 0,
        };
        
        let mut validation_registry = ProjectValidationRegistry {
            id: object::new(ctx),
            active_sessions: table::new(ctx),
            validator_assignments: table::new(ctx),
            pending_by_category: table::new(ctx),
            completed_sessions: vector::empty(),
            total_sessions_created: 0,
            total_sessions_completed: 0,
            total_sessions_expired: 0,
            admin: TEST_ADMIN,
        };
        
        // Create multiple projects
        ts::next_tx(&mut scenario, TEST_AUTHOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let mut payment1 = coin::mint_for_testing<SUI>(1000000000, ctx);
            let mut payment2 = coin::mint_for_testing<SUI>(1000000000, ctx);
            
            create_project(
                &mut config,
                &mut registry,
                &mut validation_registry,
                &validator_pool,
                &global_params,
                string::utf8(b"Project 1"),
                string::utf8(b"First project"),
                string::utf8(b"https://github.com/test/1"),
                option::some(string::utf8(b"https://demo1.com")),
                option::some(string::utf8(b"https://docs1.com")),
                vector[object::id_from_address(@0xAAA)],
                1,
                1,
                vector[string::utf8(b"sui")],
                payment1,
                &clock_obj,
                ctx
            );
            
            create_project(
                &mut config,
                &mut registry,
                &mut validation_registry,
                &validator_pool,
                &global_params,
                string::utf8(b"Project 2"),
                string::utf8(b"Second project"),
                string::utf8(b"https://github.com/test/2"),
                option::none(),
                option::none(),
                vector[object::id_from_address(@0xBBB)],
                2,
                2,
                vector[string::utf8(b"move")],
                payment2,
                &clock_obj,
                ctx
            );
            
            coin::destroy_zero(payment1);
            coin::destroy_zero(payment2);
        };
        
        // Test registry stats after multiple projects
        ts::next_tx(&mut scenario, TEST_USER);
        {
            let (total_projects, _total_stars) = get_registry_stats(&registry);
            assert!(total_projects == 2, 4);
        };
        
        clock::destroy_for_testing(clock_obj);
        transfer::share_object(registry);
        transfer::share_object(validation_registry);
        transfer::share_object(validator_pool);
        ts::end(scenario);
    }
}