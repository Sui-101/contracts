module suiverse_content::projects {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::url::{Self, Url};
    use sui::transfer;
    use suiverse_core::parameters::{Self, GlobalParameters};
    use suiverse_content::validation::{Self, ValidationSession};
    use suiverse_core::treasury::{Self, Treasury};

    // =============== Constants ===============
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

    // Project status
    const STATUS_DRAFT: u8 = 0;
    const STATUS_PENDING_REVIEW: u8 = 1;
    const STATUS_APPROVED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_ACTIVE: u8 = 4;
    const STATUS_COMPLETED: u8 = 5;
    const STATUS_ARCHIVED: u8 = 6;

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

    // =============== Structs ===============
    
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
        view_count: u64,
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

    /// Project statistics
    public struct ProjectStats has key {
        id: UID,
        total_projects: u64,
        approved_projects: u64,
        active_projects: u64,
        completed_projects: u64,
        total_contributors: u64,
        total_views: u64,
        total_stars: u64,
        categories: Table<u8, u64>,
    }

    /// Project submission for featured status
    #[allow(unused_field)]
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

    // =============== Events ===============
    
    public struct ProjectCreated has copy, drop {
        project_id: ID,
        owner: address,
        title: String,
        category: u8,
        deposit_amount: u64,
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
        let stats = ProjectStats {
            id: object::new(ctx),
            total_projects: 0,
            approved_projects: 0,
            active_projects: 0,
            completed_projects: 0,
            total_contributors: 0,
            total_views: 0,
            total_stars: 0,
            categories: table::new(ctx),
        };
        
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Create a new project
    public entry fun create_project(
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
        params: &GlobalParameters,
        stats: &mut ProjectStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        
        // Validate inputs
        assert!(string::length(&title) > 0 && string::length(&title) <= 200, E_INVALID_CATEGORY);
        assert!(string::length(&repository_url) > 0, E_INVALID_URL);
        assert!(category >= CATEGORY_DEFI && category <= CATEGORY_OTHER, E_INVALID_CATEGORY);
        assert!(difficulty >= 1 && difficulty <= 5, E_INVALID_DIFFICULTY);
        
        // Check deposit amount
        let required_deposit = parameters::get_project_deposit(params);
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);
        
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
            view_count: 0,
            star_count: 0,
            fork_count: 0,
            earnings: balance::zero(),
            status: STATUS_PENDING_REVIEW,
            deposit_amount: coin::value(&deposit),
            validation_session_id: option::none(),
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
            completed_at: option::none(),
        };
        
        let project_id = object::uid_to_inner(&project.id);
        
        // Update statistics
        stats.total_projects = stats.total_projects + 1;
        if (table::contains(&stats.categories, category)) {
            let count = table::borrow_mut(&mut stats.categories, category);
            *count = *count + 1;
        } else {
            table::add(&mut stats.categories, category, 1);
        };
        
        // Project registered successfully
        
        // Store deposit
        transfer::public_transfer(deposit, @suiverse_core);
        
        event::emit(ProjectCreated {
            project_id,
            owner,
            title: project.title,
            category,
            deposit_amount: project.deposit_amount,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::share_object(project);
    }

    /// Add a contributor to the project
    public entry fun add_contributor(
        project: &mut Project,
        contributor_address: address,
        contribution_type: u8,
        stats: &mut ProjectStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        assert!(project.status == STATUS_ACTIVE, E_PROJECT_CLOSED);
        
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
        stats.total_contributors = stats.total_contributors + 1;
        project.updated_at = clock::timestamp_ms(clock);
        
        event::emit(ContributorAdded {
            project_id: object::uid_to_inner(&project.id),
            contributor: contributor_address,
            contribution_type,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update contributor statistics
    public entry fun update_contributor_stats(
        project: &mut Project,
        contributor_address: address,
        commits: u64,
        lines_added: u64,
        lines_removed: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender || sender == contributor_address, E_NOT_OWNER);
        
        // Find and update contributor
        let mut i = 0;
        let mut found = false;
        while (i < vector::length(&project.contributors)) {
            let contributor = vector::borrow_mut(&mut project.contributors, i);
            if (contributor.address == contributor_address) {
                contributor.commits = contributor.commits + commits;
                contributor.lines_added = contributor.lines_added + lines_added;
                contributor.lines_removed = contributor.lines_removed + lines_removed;
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, E_NOT_FOUND);
        project.updated_at = clock::timestamp_ms(clock);
    }

    /// Add a milestone to the project
    public entry fun add_milestone(
        project: &mut Project,
        title: String,
        description: String,
        target_date: u64,
        deliverables: vector<String>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        
        let milestone = Milestone {
            title,
            description,
            target_date,
            completed_date: option::none(),
            status: 0, // Pending
            deliverables,
        };
        
        vector::push_back(&mut project.milestones, milestone);
        project.updated_at = clock::timestamp_ms(clock);
    }

    /// Complete a milestone
    public entry fun complete_milestone(
        project: &mut Project,
        milestone_index: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        assert!(milestone_index < vector::length(&project.milestones), E_NOT_FOUND);
        
        let milestone = vector::borrow_mut(&mut project.milestones, milestone_index);
        milestone.status = 2; // Completed
        milestone.completed_date = option::some(clock::timestamp_ms(clock));
        
        project.updated_at = clock::timestamp_ms(clock);
        
        event::emit(MilestoneCompleted {
            project_id: object::uid_to_inner(&project.id),
            milestone_title: milestone.title,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update project after validation
    public fun update_project_validation_status(
        project: &mut Project,
        session: &ValidationSession,
        stats: &mut ProjectStats,
        clock: &Clock,
    ) {
        let approved = validation::get_validation_result(session);
        
        if (approved) {
            project.status = STATUS_ACTIVE;
            stats.approved_projects = stats.approved_projects + 1;
            stats.active_projects = stats.active_projects + 1;
            
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
        }
    }

    /// View a project and distribute rewards
    public entry fun view_project(
        project: &mut Project,
        treasury: &mut Treasury,
        params: &GlobalParameters,
        stats: &mut ProjectStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(project.status == STATUS_ACTIVE || project.status == STATUS_COMPLETED, E_NOT_APPROVED);
        
        // Increment view count
        project.view_count = project.view_count + 1;
        stats.total_views = stats.total_views + 1;
        
        // Calculate and distribute reward
        let reward_amount = parameters::get_project_view_reward(params);
        
        if (reward_amount > 0) {
            let reward = treasury::withdraw_for_rewards(
                treasury,
                reward_amount,
                project.owner,
                string::utf8(b"Project View Reward"),
                string::utf8(b"Project View Incentive"),
                clock,
                ctx
            );
            
            // Add to project earnings
            let reward_balance = coin::into_balance(reward);
            balance::join(&mut project.earnings, reward_balance);
        }
    }

    /// Star a project
    public entry fun star_project(
        project: &mut Project,
        stats: &mut ProjectStats,
        _ctx: &TxContext,
    ) {
        project.star_count = project.star_count + 1;
        stats.total_stars = stats.total_stars + 1;
    }

    /// Fork a project (creates a new forked project)
    public entry fun fork_project(
        original_project: &mut Project,
        fork_url: String,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let forker = tx_context::sender(ctx);
        
        // Create fork title
        let mut fork_title = string::utf8(b"Fork of ");
        string::append(&mut fork_title, original_project.title);
        
        // Create a new project as a fork
        let fork = Project {
            id: object::new(ctx),
            title: fork_title,
            description: original_project.description,
            owner: forker,
            repository_url: fork_url,
            demo_url: option::none(),
            documentation_url: option::none(),
            tags: original_project.tags,
            category: original_project.category,
            difficulty: original_project.difficulty,
            contributors: vector::empty(),
            milestones: vector::empty(),
            tech_stack: original_project.tech_stack,
            view_count: 0,
            star_count: 0,
            fork_count: 0,
            earnings: balance::zero(),
            status: STATUS_DRAFT,
            deposit_amount: 0,
            validation_session_id: option::none(),
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
            completed_at: option::none(),
        };
        
        // Update original project fork count
        original_project.fork_count = original_project.fork_count + 1;
        
        transfer::share_object(fork);
    }

    /// Complete a project
    public entry fun complete_project(
        project: &mut Project,
        stats: &mut ProjectStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(project.owner == sender, E_NOT_OWNER);
        assert!(project.status == STATUS_ACTIVE, E_NOT_APPROVED);
        
        project.status = STATUS_COMPLETED;
        project.completed_at = option::some(clock::timestamp_ms(clock));
        project.updated_at = clock::timestamp_ms(clock);
        
        stats.active_projects = stats.active_projects - 1;
        stats.completed_projects = stats.completed_projects + 1;
        
        event::emit(ProjectCompleted {
            project_id: object::uid_to_inner(&project.id),
            owner: project.owner,
            total_contributors: vector::length(&project.contributors),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Withdraw project earnings
    public entry fun withdraw_earnings(
        project: &mut Project,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        assert!(project.owner == owner, E_NOT_OWNER);
        
        let amount = balance::value(&project.earnings);
        assert!(amount > 0, E_INSUFFICIENT_DEPOSIT);
        
        let earnings = balance::withdraw_all(&mut project.earnings);
        let earnings_coin = coin::from_balance(earnings, ctx);
        
        transfer::public_transfer(earnings_coin, owner);
    }

    // =============== View Functions ===============
    
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

    public fun get_project_view_count(project: &Project): u64 {
        project.view_count
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

    public fun is_project_completed(project: &Project): bool {
        project.status == STATUS_COMPLETED
    }

    public fun get_stats(stats: &ProjectStats): (u64, u64, u64, u64) {
        (
            stats.total_projects,
            stats.approved_projects,
            stats.active_projects,
            stats.completed_projects
        )
    }
}