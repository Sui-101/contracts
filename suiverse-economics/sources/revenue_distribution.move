module suiverse_economics::revenue_distribution {
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use suiverse_economics::utils;

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_AMOUNT: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;
    const E_INVALID_CONTENT_TYPE: u64 = 4;
    const E_INVALID_PERCENTAGE: u64 = 5;
    const E_EPOCH_ALREADY_PROCESSED: u64 = 6;
    const E_NO_REVENUE_TO_DISTRIBUTE: u64 = 7;

    // Content types
    const CONTENT_TYPE_QUIZ: u8 = 1;
    const CONTENT_TYPE_ORIGINAL_ARTICLE: u8 = 2;
    const CONTENT_TYPE_EXTERNAL_ARTICLE: u8 = 3;
    const CONTENT_TYPE_PROJECT: u8 = 4;

    // Revenue types
    const REVENUE_TYPE_VIEW: u8 = 1;
    const REVENUE_TYPE_USAGE: u8 = 2;
    const REVENUE_TYPE_QUALITY_BONUS: u8 = 3;
    const REVENUE_TYPE_EXAM_SHARE: u8 = 4;

    // Helper function to sum vector elements
    fun vector_sum(values: &vector<u64>): u64 {
        let mut sum = 0;
        let mut i = 0;
        while (i < vector::length(values)) {
            sum = sum + *vector::borrow(values, i);
            i = i + 1;
        };
        sum
    }

    // Admin capability
    public struct AdminCap has key {
        id: UID,
    }

    // Revenue configuration
    public struct RevenueConfig has key {
        id: UID,
        // Per-view rewards (in MIST = 10^-9 SUI)
        original_article_view_reward: u64,    // 0.001 SUI = 1,000,000 MIST
        external_article_view_reward: u64,    // 0.0005 SUI = 500,000 MIST
        project_view_reward: u64,             // 0.0008 SUI = 800,000 MIST
        
        // Per-usage rewards
        quiz_usage_reward: u64,               // 0.02 SUI = 20,000,000 MIST
        
        // Quality bonuses
        article_rating_bonus: u64,            // 0.01 SUI for rating >4.5
        article_rating_threshold: u64,        // 4.5 * 10 = 45 (stored as integer)
        project_completion_bonus: u64,        // 0.005 SUI = 5,000,000 MIST
        quiz_top_performer_bonus: u64,        // 0.05 SUI = 50,000,000 MIST
        quiz_top_performer_threshold: u8,     // Top 10%
        
        // Exam revenue sharing
        exam_creator_share: u64,              // 40% = 4000 basis points
        
        // Quality measurement thresholds
        min_views_for_bonus: u64,             // Minimum views to be eligible for bonuses
        measurement_window_epochs: u64,       // Epochs to measure performance over
        
        // Last governance update
        last_update_proposal: ID,
    }

    // Revenue record for tracking
    public struct RevenueRecord has key, store {
        id: UID,
        creator: address,
        content_id: ID,
        content_type: u8,
        revenue_type: u8,
        amount: u64,
        epoch: u64,
        processed: bool,
    }

    // Aggregated revenue pool for distribution
    public struct RevenuePool has key {
        id: UID,
        pending_distribution: Balance<SUI>,
        total_pending: u64,
        view_revenue_balance: Balance<SUI>,
        usage_revenue_balance: Balance<SUI>,
        bonus_revenue_balance: Balance<SUI>,
        current_epoch: u64,
        last_distribution_epoch: u64,
    }

    // Creator earnings tracker
    public struct CreatorEarnings has key, store {
        id: UID,
        creator: address,
        total_earned: u64,
        view_earnings: u64,
        usage_earnings: u64,
        bonus_earnings: u64,
        exam_share_earnings: u64,
        unclaimed_balance: Balance<SUI>,
        last_claim_epoch: u64,
    }

    // Content performance tracking
    public struct ContentPerformance has key, store {
        id: UID,
        content_id: ID,
        content_type: u8,
        creator: address,
        total_views: u64,
        total_usage: u64,
        current_epoch_views: u64,
        current_epoch_usage: u64,
        rating_sum: u64,
        rating_count: u64,
        completion_count: u64,
        last_bonus_epoch: u64,
    }

    // Epoch distribution summary
    public struct EpochDistribution has key, store {
        id: UID,
        epoch: u64,
        total_distributed: u64,
        view_rewards_distributed: u64,
        usage_rewards_distributed: u64,
        bonuses_distributed: u64,
        creators_rewarded: u64,
        timestamp: u64,
    }

    // Events
    public struct RevenueGeneratedEvent has copy, drop {
        creator: address,
        content_id: ID,
        revenue_type: u8,
        amount: u64,
        epoch: u64,
    }

    public struct RevenueDistributedEvent has copy, drop {
        creator: address,
        amount: u64,
        epoch: u64,
    }

    public struct BonusAwardedEvent has copy, drop {
        creator: address,
        content_id: ID,
        bonus_type: u8,
        amount: u64,
        epoch: u64,
    }

    public struct EarningsClaimedEvent has copy, drop {
        creator: address,
        amount: u64,
        epoch: u64,
    }

    public struct RevenueConfigUpdatedEvent has copy, drop {
        admin: address,
        proposal_id: ID,
    }

    // Initialize the revenue distribution system
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };

        let revenue_config = RevenueConfig {
            id: object::new(ctx),
            original_article_view_reward: 1_000_000,      // 0.001 SUI
            external_article_view_reward: 500_000,        // 0.0005 SUI
            project_view_reward: 800_000,                 // 0.0008 SUI
            quiz_usage_reward: 20_000_000,                // 0.02 SUI
            article_rating_bonus: 10_000_000,             // 0.01 SUI
            article_rating_threshold: 45,                 // 4.5 rating
            project_completion_bonus: 5_000_000,          // 0.005 SUI
            quiz_top_performer_bonus: 50_000_000,         // 0.05 SUI
            quiz_top_performer_threshold: 10,             // Top 10%
            exam_creator_share: 4000,                     // 40%
            min_views_for_bonus: 100,                     // Minimum 100 views
            measurement_window_epochs: 30,                // 30 epochs
            last_update_proposal: object::id_from_address(@0x0),
        };

        let revenue_pool = RevenuePool {
            id: object::new(ctx),
            pending_distribution: balance::zero<SUI>(),
            total_pending: 0,
            view_revenue_balance: balance::zero<SUI>(),
            usage_revenue_balance: balance::zero<SUI>(),
            bonus_revenue_balance: balance::zero<SUI>(),
            current_epoch: tx_context::epoch(ctx),
            last_distribution_epoch: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(revenue_config);
        transfer::share_object(revenue_pool);
    }

    // Record content view for revenue calculation
    public fun record_content_view(
        revenue_config: &RevenueConfig,
        revenue_pool: &mut RevenuePool,
        content_id: ID,
        content_type: u8,
        creator: address,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let reward_amount = if (content_type == CONTENT_TYPE_ORIGINAL_ARTICLE) {
            revenue_config.original_article_view_reward
        } else if (content_type == CONTENT_TYPE_EXTERNAL_ARTICLE) {
            revenue_config.external_article_view_reward
        } else if (content_type == CONTENT_TYPE_PROJECT) {
            revenue_config.project_view_reward
        } else {
            abort E_INVALID_CONTENT_TYPE
        };

        // Create revenue record
        let revenue_record = RevenueRecord {
            id: object::new(ctx),
            creator,
            content_id,
            content_type,
            revenue_type: REVENUE_TYPE_VIEW,
            amount: reward_amount,
            epoch: current_epoch,
            processed: false,
        };

        // Update revenue pool (will be distributed later)
        revenue_pool.total_pending = revenue_pool.total_pending + reward_amount;

        event::emit(RevenueGeneratedEvent {
            creator,
            content_id,
            revenue_type: REVENUE_TYPE_VIEW,
            amount: reward_amount,
            epoch: current_epoch,
        });

        transfer::share_object(revenue_record);
    }

    // Record quiz usage for revenue calculation
    public fun record_quiz_usage(
        revenue_config: &RevenueConfig,
        revenue_pool: &mut RevenuePool,
        quiz_id: ID,
        creator: address,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let reward_amount = revenue_config.quiz_usage_reward;

        let revenue_record = RevenueRecord {
            id: object::new(ctx),
            creator,
            content_id: quiz_id,
            content_type: CONTENT_TYPE_QUIZ,
            revenue_type: REVENUE_TYPE_USAGE,
            amount: reward_amount,
            epoch: current_epoch,
            processed: false,
        };

        revenue_pool.total_pending = revenue_pool.total_pending + reward_amount;

        event::emit(RevenueGeneratedEvent {
            creator,
            content_id: quiz_id,
            revenue_type: REVENUE_TYPE_USAGE,
            amount: reward_amount,
            epoch: current_epoch,
        });

        transfer::share_object(revenue_record);
    }

    // Distribute exam fee revenue to creators
    public fun distribute_exam_revenue(
        revenue_config: &RevenueConfig,
        exam_fee_amount: u64,
        exam_creators: vector<address>,
        quiz_usage_counts: vector<u64>,
        ctx: &mut TxContext
    ): Balance<SUI> {
        let creator_share_total = (exam_fee_amount * revenue_config.exam_creator_share) / 10000;
        let total_usage = vector_sum(&quiz_usage_counts);
        
        assert!(total_usage > 0, E_NO_REVENUE_TO_DISTRIBUTE);
        assert!(vector::length(&exam_creators) == vector::length(&quiz_usage_counts), E_INVALID_AMOUNT);

        let current_epoch = tx_context::epoch(ctx);
        let mut i = 0;
        let mut remaining_balance = creator_share_total;

        while (i < vector::length(&exam_creators)) {
            let creator = *vector::borrow(&exam_creators, i);
            let usage_count = *vector::borrow(&quiz_usage_counts, i);
            let creator_share = (creator_share_total * usage_count) / total_usage;
            
            if (creator_share > 0) {
                // Create revenue record for tracking
                let revenue_record = RevenueRecord {
                    id: object::new(ctx),
                    creator,
                    content_id: object::id_from_address(@0x0), // Exam revenue, no specific content
                    content_type: CONTENT_TYPE_QUIZ,
                    revenue_type: REVENUE_TYPE_EXAM_SHARE,
                    amount: creator_share,
                    epoch: current_epoch,
                    processed: false,
                };

                event::emit(RevenueGeneratedEvent {
                    creator,
                    content_id: object::id_from_address(@0x0),
                    revenue_type: REVENUE_TYPE_EXAM_SHARE,
                    amount: creator_share,
                    epoch: current_epoch,
                });

                transfer::share_object(revenue_record);
                remaining_balance = remaining_balance - creator_share;
            };
            
            i = i + 1;
        };

        // Return platform share
        balance::zero<SUI>()
    }

    // Award quality bonuses based on performance
    public fun award_quality_bonuses(
        revenue_config: &RevenueConfig,
        revenue_pool: &mut RevenuePool,
        mut content_performances: vector<ContentPerformance>,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        let mut i = 0;

        while (i < vector::length(&content_performances)) {
            let performance = vector::borrow(&content_performances, i);
            
            // Skip if already awarded bonus this epoch
            if (performance.last_bonus_epoch == current_epoch) {
                i = i + 1;
                continue
            };

            // Check eligibility and award bonuses
            if (performance.total_views >= revenue_config.min_views_for_bonus) {
                let mut bonus_amount = 0u64;
                let mut bonus_awarded = false;

                // Article rating bonus
                if (performance.content_type == CONTENT_TYPE_ORIGINAL_ARTICLE) {
                    if (performance.rating_count > 0) {
                        let avg_rating = (performance.rating_sum * 10) / performance.rating_count;
                        if (avg_rating >= revenue_config.article_rating_threshold) {
                            bonus_amount = revenue_config.article_rating_bonus;
                            bonus_awarded = true;
                        };
                    };
                } else if (performance.content_type == CONTENT_TYPE_PROJECT) {
                    // Project completion bonus
                    if (performance.completion_count > 0) {
                        bonus_amount = revenue_config.project_completion_bonus;
                        bonus_awarded = true;
                    };
                };

                // Award bonus if eligible
                if (bonus_awarded) {
                    let revenue_record = RevenueRecord {
                        id: object::new(ctx),
                        creator: performance.creator,
                        content_id: performance.content_id,
                        content_type: performance.content_type,
                        revenue_type: REVENUE_TYPE_QUALITY_BONUS,
                        amount: bonus_amount,
                        epoch: current_epoch,
                        processed: false,
                    };

                    revenue_pool.total_pending = revenue_pool.total_pending + bonus_amount;

                    event::emit(BonusAwardedEvent {
                        creator: performance.creator,
                        content_id: performance.content_id,
                        bonus_type: REVENUE_TYPE_QUALITY_BONUS,
                        amount: bonus_amount,
                        epoch: current_epoch,
                    });

                    transfer::share_object(revenue_record);
                };
            };

            i = i + 1;
        };
        
        // Consume the content_performances vector
        while (!vector::is_empty(&content_performances)) {
            let performance = vector::pop_back(&mut content_performances);
            let ContentPerformance {
                id,
                content_id: _,
                content_type: _,
                creator: _,
                total_views: _,
                total_usage: _,
                current_epoch_views: _,
                current_epoch_usage: _,
                rating_sum: _,
                rating_count: _,
                completion_count: _,
                last_bonus_epoch: _,
            } = performance;
            object::delete(id);
        };
        vector::destroy_empty(content_performances);
    }

    // Distribute pending revenue to creators
    public fun distribute_epoch_revenue(
        revenue_pool: &mut RevenuePool,
        mut revenue_records: vector<RevenueRecord>,
        funding_source: Balance<SUI>,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);
        assert!(current_epoch > revenue_pool.last_distribution_epoch, E_EPOCH_ALREADY_PROCESSED);

        let total_to_distribute = revenue_pool.total_pending;
        assert!(balance::value(&funding_source) >= total_to_distribute, E_INSUFFICIENT_BALANCE);

        // Add funding to pool
        balance::join(&mut revenue_pool.pending_distribution, funding_source);

        let mut i = 0;
        let mut total_distributed = 0u64;
        let mut creators_rewarded = 0u64;

        while (i < vector::length(&revenue_records)) {
            let record = vector::borrow_mut(&mut revenue_records, i);
            
            if (!record.processed && record.epoch <= current_epoch) {
                // Mark as processed
                record.processed = true;
                
                // Create or update creator earnings
                let reward_balance = balance::split(&mut revenue_pool.pending_distribution, record.amount);
                
                // Transfer directly to creator for now (could batch later)
                let reward_coin = coin::from_balance(reward_balance, ctx);
                transfer::public_transfer(reward_coin, record.creator);

                event::emit(RevenueDistributedEvent {
                    creator: record.creator,
                    amount: record.amount,
                    epoch: current_epoch,
                });

                total_distributed = total_distributed + record.amount;
                creators_rewarded = creators_rewarded + 1;
            };

            i = i + 1;
        };

        // Update pool state
        revenue_pool.total_pending = revenue_pool.total_pending - total_distributed;
        revenue_pool.last_distribution_epoch = current_epoch;

        // Create epoch distribution summary
        let epoch_distribution = EpochDistribution {
            id: object::new(ctx),
            epoch: current_epoch,
            total_distributed,
            view_rewards_distributed: total_distributed, // Simplified for now
            usage_rewards_distributed: 0,
            bonuses_distributed: 0,
            creators_rewarded,
            timestamp: clock::timestamp_ms(_clock),
        };

        // Consume the revenue_records vector by destructuring each record
        while (!vector::is_empty(&revenue_records)) {
            let record = vector::pop_back(&mut revenue_records);
            let RevenueRecord {
                id,
                creator: _,
                content_id: _,
                content_type: _,
                revenue_type: _,
                amount: _,
                epoch: _,
                processed: _,
            } = record;
            object::delete(id);
        };
        vector::destroy_empty(revenue_records);

        transfer::share_object(epoch_distribution);
    }

    // Update revenue configuration (governance only)
    public fun update_revenue_config(
        _: &AdminCap,
        config: &mut RevenueConfig,
        new_article_view_reward: u64,
        new_external_article_reward: u64,
        new_project_view_reward: u64,
        new_quiz_usage_reward: u64,
        new_article_bonus: u64,
        new_project_bonus: u64,
        new_quiz_bonus: u64,
        proposal_id: ID,
        ctx: &mut TxContext
    ) {
        config.original_article_view_reward = new_article_view_reward;
        config.external_article_view_reward = new_external_article_reward;
        config.project_view_reward = new_project_view_reward;
        config.quiz_usage_reward = new_quiz_usage_reward;
        config.article_rating_bonus = new_article_bonus;
        config.project_completion_bonus = new_project_bonus;
        config.quiz_top_performer_bonus = new_quiz_bonus;
        config.last_update_proposal = proposal_id;

        event::emit(RevenueConfigUpdatedEvent {
            admin: tx_context::sender(ctx),
            proposal_id,
        });
    }


    // Getter functions
    public fun get_original_article_view_reward(config: &RevenueConfig): u64 {
        config.original_article_view_reward
    }

    public fun get_external_article_view_reward(config: &RevenueConfig): u64 {
        config.external_article_view_reward
    }

    public fun get_project_view_reward(config: &RevenueConfig): u64 {
        config.project_view_reward
    }

    public fun get_quiz_usage_reward(config: &RevenueConfig): u64 {
        config.quiz_usage_reward
    }

    public fun get_article_rating_bonus(config: &RevenueConfig): u64 {
        config.article_rating_bonus
    }

    public fun get_project_completion_bonus(config: &RevenueConfig): u64 {
        config.project_completion_bonus
    }

    public fun get_quiz_top_performer_bonus(config: &RevenueConfig): u64 {
        config.quiz_top_performer_bonus
    }

    public fun get_exam_creator_share(config: &RevenueConfig): u64 {
        config.exam_creator_share
    }

    public fun get_total_pending_distribution(pool: &RevenuePool): u64 {
        pool.total_pending
    }

    public fun get_current_epoch(pool: &RevenuePool): u64 {
        pool.current_epoch
    }

    public fun get_last_distribution_epoch(pool: &RevenuePool): u64 {
        pool.last_distribution_epoch
    }

    // Revenue record accessors
    public fun revenue_record_creator(record: &RevenueRecord): address {
        record.creator
    }

    public fun revenue_record_amount(record: &RevenueRecord): u64 {
        record.amount
    }

    public fun revenue_record_processed(record: &RevenueRecord): bool {
        record.processed
    }

    public fun revenue_record_content_type(record: &RevenueRecord): u8 {
        record.content_type
    }

    public fun revenue_record_revenue_type(record: &RevenueRecord): u8 {
        record.revenue_type
    }

    // Test functions
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun create_test_revenue_record(
        creator: address,
        content_id: ID,
        content_type: u8,
        amount: u64,
        ctx: &mut TxContext
    ): RevenueRecord {
        RevenueRecord {
            id: object::new(ctx),
            creator,
            content_id,
            content_type,
            revenue_type: REVENUE_TYPE_VIEW,
            amount,
            epoch: tx_context::epoch(ctx),
            processed: false,
        }
    }
}