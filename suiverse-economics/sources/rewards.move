module suiverse_economics::rewards {
    use std::string::{Self, String};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use suiverse_core::parameters::{Self, SystemParameters};
    use suiverse_core::treasury::{Self, Treasury};
    // use suiverse_content::validation::{Self, ValidationSession}; // Commented out - causing compilation issues
    use suiverse_core::governance::{Self, ValidatorPool};

    // =============== Constants ===============
    const E_NOT_AUTHORIZED: u64 = 15001;
    const E_INSUFFICIENT_BALANCE: u64 = 15002;
    const E_REWARD_ALREADY_CLAIMED: u64 = 15003;
    const E_INVALID_PERIOD: u64 = 15004;
    const E_PERIOD_NOT_ENDED: u64 = 15005;
    const E_NO_ACTIVITY: u64 = 15006;
    const E_INVALID_AMOUNT: u64 = 15007;
    const E_DISTRIBUTION_NOT_READY: u64 = 15008;
    const E_MILESTONE_NOT_REACHED: u64 = 15009;
    const E_INVALID_REWARD_TYPE: u64 = 15010;

    // Reward types
    const REWARD_VALIDATION: u8 = 1;
    const REWARD_CONTENT_CREATION: u8 = 2;
    const REWARD_GOVERNANCE: u8 = 3;
    const REWARD_REFERRAL: u8 = 4;
    const REWARD_ACHIEVEMENT: u8 = 5;
    const REWARD_BONUS: u8 = 6;
    const REWARD_CONTENT_VIEW: u8 = 7;
    const REWARD_QUIZ_USAGE: u8 = 8;

    // Distribution periods
    const PERIOD_DAILY: u8 = 1;
    const PERIOD_WEEKLY: u8 = 2;
    const PERIOD_MONTHLY: u8 = 3;

    // Time constants
    const DAY_IN_MS: u64 = 86400000;
    const WEEK_IN_MS: u64 = 604800000;
    const MONTH_IN_MS: u64 = 2592000000;

    // =============== Structs ===============
    
    /// Reward distribution configuration
    public struct RewardConfig has key {
        id: UID,
        validation_reward_rate: u64,        // Per validation
        content_reward_rate: u64,           // Per approved content
        governance_reward_rate: u64,        // Per vote
        referral_reward_rate: u64,          // Percentage of referee's earnings
        achievement_rewards: Table<String, u64>, // Achievement name -> reward amount
        bonus_pool_percentage: u8,          // Percentage of treasury for bonuses
        min_activity_threshold: u64,        // Minimum activity to qualify
        distribution_period: u8,            // Daily/Weekly/Monthly
    }

    /// Reward pool for distribution
    public struct RewardPool has key {
        id: UID,
        current_period: u64,
        period_start: u64,
        period_end: u64,
        total_rewards: Balance<SUI>,
        allocated_rewards: u64,
        distributed_rewards: u64,
        eligible_users: Table<address, UserRewardInfo>,
        distribution_status: u8,            // 0: Active, 1: Calculating, 2: Ready, 3: Distributed
    }

    /// User reward information
    public struct UserRewardInfo has store {
        user: address,
        activity_score: u64,
        validation_count: u64,
        content_count: u64,
        governance_participation: u64,
        referral_earnings: u64,
        achievements: vector<String>,
        pending_rewards: u64,
        claimed_rewards: u64,
        last_claim_time: u64,
    }

    /// Reward claim record
    public struct RewardClaim has key, store {
        id: UID,
        user: address,
        period: u64,
        reward_type: u8,
        amount: u64,
        claimed_at: u64,
        transaction_hash: vector<u8>,
    }

    /// User reward history
    public struct UserRewardHistory has key {
        id: UID,
        user: address,
        total_earned: u64,
        total_claimed: u64,
        unclaimed_balance: u64,
        claims: Table<u64, RewardClaim>,   // period -> claim
        referral_rewards: u64,
        achievement_rewards: u64,
        bonus_rewards: u64,
        last_activity: u64,
    }

    /// Referral tracking
    public struct ReferralRegistry has key {
        id: UID,
        referrals: Table<address, ReferralInfo>,
        referral_chains: Table<address, address>, // referee -> referrer
        total_referrals: u64,
        total_rewards_paid: u64,
    }

    /// Referral information
    public struct ReferralInfo has store {
        referrer: address,
        referees: vector<address>,
        total_earnings: u64,
        rewards_earned: u64,
        active_referees: u64,
        registration_date: u64,
    }

    /// Achievement definition
    public struct Achievement has key, store {
        id: UID,
        name: String,
        description: String,
        requirement_type: u8,               // 1: Count, 2: Streak, 3: Milestone
        requirement_value: u64,
        reward_amount: u64,
        icon_url: String,
        total_claimed: u64,
        active: bool,
    }

    // =============== Events ===============
    
    public struct RewardDistributed has copy, drop {
        user: address,
        amount: u64,
        reward_type: u8,
        period: u64,
        timestamp: u64,
    }

    public struct RewardClaimed has copy, drop {
        user: address,
        amount: u64,
        claim_id: ID,
        timestamp: u64,
    }

    public struct AchievementUnlocked has copy, drop {
        user: address,
        achievement: String,
        reward: u64,
        timestamp: u64,
    }

    public struct ReferralRewardEarned has copy, drop {
        referrer: address,
        referee: address,
        amount: u64,
        timestamp: u64,
    }

    public struct PeriodCompleted has copy, drop {
        period: u64,
        total_distributed: u64,
        eligible_users: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let config = RewardConfig {
            id: object::new(ctx),
            validation_reward_rate: 10_000000, // 10 SUI per validation
            content_reward_rate: 50_000000,    // 50 SUI per content
            governance_reward_rate: 5_000000,  // 5 SUI per vote
            referral_reward_rate: 10,          // 10% of referee earnings
            achievement_rewards: table::new(ctx),
            bonus_pool_percentage: 20,          // 20% for bonuses
            min_activity_threshold: 5,         // 5 activities minimum
            distribution_period: PERIOD_WEEKLY,
        };
        
        let pool = RewardPool {
            id: object::new(ctx),
            current_period: 1,
            period_start: 0,
            period_end: 0,
            total_rewards: balance::zero(),
            allocated_rewards: 0,
            distributed_rewards: 0,
            eligible_users: table::new(ctx),
            distribution_status: 0,
        };
        
        let referral_registry = ReferralRegistry {
            id: object::new(ctx),
            referrals: table::new(ctx),
            referral_chains: table::new(ctx),
            total_referrals: 0,
            total_rewards_paid: 0,
        };
        
        transfer::share_object(config);
        transfer::share_object(pool);
        transfer::share_object(referral_registry);
    }

    // =============== Public Entry Functions ===============
    
    /// Initialize reward period
    public entry fun start_reward_period(
        pool: &mut RewardPool,
        treasury: &mut Treasury,
        config: &RewardConfig,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if previous period ended
        assert!(current_time >= pool.period_end, E_PERIOD_NOT_ENDED);
        
        // Calculate period duration
        let period_duration = if (config.distribution_period == PERIOD_DAILY) {
            DAY_IN_MS
        } else if (config.distribution_period == PERIOD_WEEKLY) {
            WEEK_IN_MS
        } else {
            MONTH_IN_MS
        };
        
        // Set new period
        pool.current_period = pool.current_period + 1;
        pool.period_start = current_time;
        pool.period_end = current_time + period_duration;
        pool.allocated_rewards = 0;
        pool.distributed_rewards = 0;
        pool.distribution_status = 0;
        
        // Allocate rewards from treasury
        let allocation = treasury::withdraw_for_rewards(
            treasury,
            1000_000000, // 1000 SUI
            @suiverse_economics,
            string::utf8(b"Reward Pool"),
            string::utf8(b"Reward Pool Allocation"),
            clock,
            ctx
        );
        let allocation_balance = coin::into_balance(allocation);
        balance::join(&mut pool.total_rewards, allocation_balance);
    }

    /// Record validation activity for rewards
    public entry fun record_validation_activity(
        validator: address,
        pool: &mut RewardPool,
        config: &RewardConfig,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        ensure_period_active(pool, clock);
        
        if (!table::contains(&pool.eligible_users, validator)) {
            let info = UserRewardInfo {
                user: validator,
                activity_score: 0,
                validation_count: 0,
                content_count: 0,
                governance_participation: 0,
                referral_earnings: 0,
                achievements: vector::empty(),
                pending_rewards: 0,
                claimed_rewards: 0,
                last_claim_time: 0,
            };
            table::add(&mut pool.eligible_users, validator, info);
        };
        
        let user_info = table::borrow_mut(&mut pool.eligible_users, validator);
        user_info.validation_count = user_info.validation_count + 1;
        user_info.activity_score = user_info.activity_score + 10;
        user_info.pending_rewards = user_info.pending_rewards + config.validation_reward_rate;
        
        pool.allocated_rewards = pool.allocated_rewards + config.validation_reward_rate;
    }

    /// Record content creation activity
    public entry fun record_content_activity(
        creator: address,
        pool: &mut RewardPool,
        config: &RewardConfig,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        ensure_period_active(pool, clock);
        
        if (!table::contains(&pool.eligible_users, creator)) {
            let info = UserRewardInfo {
                user: creator,
                activity_score: 0,
                validation_count: 0,
                content_count: 0,
                governance_participation: 0,
                referral_earnings: 0,
                achievements: vector::empty(),
                pending_rewards: 0,
                claimed_rewards: 0,
                last_claim_time: 0,
            };
            table::add(&mut pool.eligible_users, creator, info);
        };
        
        let user_info = table::borrow_mut(&mut pool.eligible_users, creator);
        user_info.content_count = user_info.content_count + 1;
        user_info.activity_score = user_info.activity_score + 25;
        user_info.pending_rewards = user_info.pending_rewards + config.content_reward_rate;
        
        pool.allocated_rewards = pool.allocated_rewards + config.content_reward_rate;
    }

    /// Claim rewards for a period
    public entry fun claim_rewards(
        pool: &mut RewardPool,
        history: &mut UserRewardHistory,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let user = tx_context::sender(ctx);
        
        // Check if user has pending rewards
        assert!(table::contains(&pool.eligible_users, user), E_NO_ACTIVITY);
        
        let user_info = table::borrow_mut(&mut pool.eligible_users, user);
        assert!(user_info.pending_rewards > 0, E_NO_ACTIVITY);
        assert!(user_info.activity_score >= 5, E_NO_ACTIVITY); // Min threshold
        
        let reward_amount = user_info.pending_rewards;
        
        // Check pool balance
        assert!(balance::value(&pool.total_rewards) >= reward_amount, E_INSUFFICIENT_BALANCE);
        
        // Transfer rewards
        let reward_coin = coin::from_balance(balance::split(&mut pool.total_rewards, reward_amount), ctx);
        transfer::public_transfer(reward_coin, user);
        
        // Update user info
        user_info.claimed_rewards = user_info.claimed_rewards + reward_amount;
        user_info.pending_rewards = 0;
        user_info.last_claim_time = clock::timestamp_ms(clock);
        
        // Update pool
        pool.distributed_rewards = pool.distributed_rewards + reward_amount;
        
        // Update history
        history.total_claimed = history.total_claimed + reward_amount;
        history.unclaimed_balance = history.unclaimed_balance - reward_amount;
        history.last_activity = clock::timestamp_ms(clock);
        
        // Create claim record
        let claim = RewardClaim {
            id: object::new(ctx),
            user,
            period: pool.current_period,
            reward_type: REWARD_VALIDATION,
            amount: reward_amount,
            claimed_at: clock::timestamp_ms(clock),
            transaction_hash: vector::empty(),
        };
        
        let claim_id = object::uid_to_inner(&claim.id);
        
        event::emit(RewardClaimed {
            user,
            amount: reward_amount,
            claim_id,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::transfer(claim, user);
    }

    /// Register referral
    public entry fun register_referral(
        referee: address,
        referrer: address,
        registry: &mut ReferralRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Check if referee already has a referrer
        assert!(!table::contains(&registry.referral_chains, referee), E_INVALID_REWARD_TYPE);
        
        // Add referral chain
        table::add(&mut registry.referral_chains, referee, referrer);
        
        // Update referrer info
        if (!table::contains(&registry.referrals, referrer)) {
            let info = ReferralInfo {
                referrer,
                referees: vector::empty(),
                total_earnings: 0,
                rewards_earned: 0,
                active_referees: 0,
                registration_date: clock::timestamp_ms(clock),
            };
            table::add(&mut registry.referrals, referrer, info);
        };
        
        let referrer_info = table::borrow_mut(&mut registry.referrals, referrer);
        vector::push_back(&mut referrer_info.referees, referee);
        referrer_info.active_referees = referrer_info.active_referees + 1;
        
        registry.total_referrals = registry.total_referrals + 1;
    }

    /// Process referral rewards
    public entry fun process_referral_reward(
        referee: address,
        earnings: u64,
        registry: &mut ReferralRegistry,
        pool: &mut RewardPool,
        config: &RewardConfig,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        if (table::contains(&registry.referral_chains, referee)) {
            let referrer = *table::borrow(&registry.referral_chains, referee);
            let reward = (earnings * (config.referral_reward_rate as u64)) / 100;
            
            if (table::contains(&registry.referrals, referrer)) {
                let referrer_info = table::borrow_mut(&mut registry.referrals, referrer);
                referrer_info.total_earnings = referrer_info.total_earnings + earnings;
                referrer_info.rewards_earned = referrer_info.rewards_earned + reward;
                
                // Add to reward pool
                if (table::contains(&pool.eligible_users, referrer)) {
                    let user_info = table::borrow_mut(&mut pool.eligible_users, referrer);
                    user_info.referral_earnings = user_info.referral_earnings + reward;
                    user_info.pending_rewards = user_info.pending_rewards + reward;
                };
                
                registry.total_rewards_paid = registry.total_rewards_paid + reward;
                
                event::emit(ReferralRewardEarned {
                    referrer,
                    referee,
                    amount: reward,
                    timestamp: clock::timestamp_ms(clock),
                });
            };
        };
    }

    /// Create achievement
    public entry fun create_achievement(
        name: String,
        description: String,
        requirement_type: u8,
        requirement_value: u64,
        reward_amount: u64,
        icon_url: String,
        config: &mut RewardConfig,
        ctx: &mut TxContext,
    ) {
        let achievement = Achievement {
            id: object::new(ctx),
            name: name,
            description,
            requirement_type,
            requirement_value,
            reward_amount,
            icon_url,
            total_claimed: 0,
            active: true,
        };
        
        // Add to config
        table::add(&mut config.achievement_rewards, name, reward_amount);
        
        transfer::share_object(achievement);
    }

    /// Claim achievement reward
    public entry fun claim_achievement(
        achievement: &mut Achievement,
        history: &mut UserRewardHistory,
        pool: &mut RewardPool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let user = tx_context::sender(ctx);
        
        // Verify achievement completion (simplified)
        assert!(achievement.active, E_MILESTONE_NOT_REACHED);
        
        // Check pool balance
        assert!(balance::value(&pool.total_rewards) >= achievement.reward_amount, E_INSUFFICIENT_BALANCE);
        
        // Transfer reward
        let reward = coin::from_balance(
            balance::split(&mut pool.total_rewards, achievement.reward_amount),
            ctx
        );
        transfer::public_transfer(reward, user);
        
        // Update achievement
        achievement.total_claimed = achievement.total_claimed + 1;
        
        // Update history
        history.achievement_rewards = history.achievement_rewards + achievement.reward_amount;
        history.total_earned = history.total_earned + achievement.reward_amount;
        
        event::emit(AchievementUnlocked {
            user,
            achievement: achievement.name,
            reward: achievement.reward_amount,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Finalize period and prepare distribution
    public entry fun finalize_period(
        pool: &mut RewardPool,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= pool.period_end, E_PERIOD_NOT_ENDED);
        
        pool.distribution_status = 3; // Distributed
        
        let eligible_count = table::length(&pool.eligible_users);
        
        event::emit(PeriodCompleted {
            period: pool.current_period,
            total_distributed: pool.distributed_rewards,
            eligible_users: eligible_count,
            timestamp: current_time,
        });
    }

    /// Initialize user reward history
    public entry fun init_user_history(ctx: &mut TxContext) {
        let user = tx_context::sender(ctx);
        
        let history = UserRewardHistory {
            id: object::new(ctx),
            user,
            total_earned: 0,
            total_claimed: 0,
            unclaimed_balance: 0,
            claims: table::new(ctx),
            referral_rewards: 0,
            achievement_rewards: 0,
            bonus_rewards: 0,
            last_activity: 0,
        };
        
        transfer::transfer(history, user);
    }

    // =============== Internal Functions ===============
    
    fun ensure_period_active(pool: &RewardPool, clock: &Clock) {
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= pool.period_start && current_time < pool.period_end, E_INVALID_PERIOD);
        assert!(pool.distribution_status == 0, E_DISTRIBUTION_NOT_READY);
    }

    // =============== View Functions ===============
    
    public fun get_user_pending_rewards(pool: &RewardPool, user: address): u64 {
        if (table::contains(&pool.eligible_users, user)) {
            let info = table::borrow(&pool.eligible_users, user);
            info.pending_rewards
        } else {
            0
        }
    }

    public fun get_user_activity_score(pool: &RewardPool, user: address): u64 {
        if (table::contains(&pool.eligible_users, user)) {
            let info = table::borrow(&pool.eligible_users, user);
            info.activity_score
        } else {
            0
        }
    }

    public fun get_period_info(pool: &RewardPool): (u64, u64, u64, u8) {
        (pool.current_period, pool.period_start, pool.period_end, pool.distribution_status)
    }

    public fun get_pool_balance(pool: &RewardPool): u64 {
        balance::value(&pool.total_rewards)
    }

    public fun get_referral_info(registry: &ReferralRegistry, referrer: address): (u64, u64) {
        if (table::contains(&registry.referrals, referrer)) {
            let info = table::borrow(&registry.referrals, referrer);
            (vector::length(&info.referees), info.rewards_earned)
        } else {
            (0, 0)
        }
    }

    public fun get_user_history_stats(history: &UserRewardHistory): (u64, u64, u64) {
        (history.total_earned, history.total_claimed, history.unclaimed_balance)
    }

    public fun is_referee_registered(registry: &ReferralRegistry, referee: address): bool {
        table::contains(&registry.referral_chains, referee)
    }

    public fun get_achievement_info(achievement: &Achievement): (String, u64, u64, bool) {
        (achievement.name, achievement.reward_amount, achievement.total_claimed, achievement.active)
    }
}