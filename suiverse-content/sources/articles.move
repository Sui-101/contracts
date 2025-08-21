module suiverse_content::articles {
    use std::string::{Self, String};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    
    // Dependencies
    use suiverse_core::parameters::{Self, SystemParameters};
    use suiverse_content::validation::{ValidationReview};

    // =============== Constants ===============
    const E_INVALID_TITLE_LENGTH: u64 = 4001;
    const E_INVALID_CONTENT_HASH: u64 = 4002;
    const E_INVALID_DIFFICULTY: u64 = 4003;
    const E_INVALID_CATEGORY: u64 = 4004;
    const E_ARTICLE_NOT_APPROVED: u64 = 4005;
    const E_NOT_AUTHOR: u64 = 4006;
    const E_ARTICLE_ALREADY_APPROVED: u64 = 4007;
    const E_INVALID_URL: u64 = 4008;
    const E_INSUFFICIENT_DEPOSIT: u64 = 4009;
    const E_INVALID_TAG_COUNT: u64 = 4010;

    // Article status
    const STATUS_PENDING: u8 = 0;
    const STATUS_APPROVED: u8 = 1;
    const STATUS_REJECTED: u8 = 2;
    const STATUS_ARCHIVED: u8 = 3;

    // Article difficulty levels
    const DIFFICULTY_BEGINNER: u8 = 1;
    const DIFFICULTY_INTERMEDIATE: u8 = 2;
    const DIFFICULTY_ADVANCED: u8 = 3;
    const DIFFICULTY_EXPERT: u8 = 4;

    // Limits
    const MAX_TITLE_LENGTH: u64 = 200;
    const MIN_TITLE_LENGTH: u64 = 10;
    const MAX_TAGS: u64 = 10;
    const MAX_DESCRIPTION_LENGTH: u64 = 500;

    // =============== Structs ===============
    
    /// Original article created by authors
    public struct OriginalArticle has key, store {
        id: UID,
        title: String,
        author: address,
        content_hash: vector<u8>, // IPFS hash
        tags: vector<ID>,
        category: String,
        difficulty: u8,
        view_count: u64,
        earnings: Balance<SUI>,
        status: u8,
        deposit_amount: u64,
        validator_reviews: vector<ValidationReview>,
        created_at: u64,
        approved_at: Option<u64>,
        last_updated: u64,
        
        // Additional metadata
        word_count: u64,
        reading_time: u64, // in minutes
        language: String,
        preview: String, // Short preview text
        cover_image: Option<String>,
        
        // Engagement metrics
        like_count: u64,
        share_count: u64,
        bookmark_count: u64,
        comment_count: u64,
        
        // Version control
        version: u64,
        previous_versions: vector<vector<u8>>, // Previous IPFS hashes
    }

    /// External article recommended by users
    public struct ExternalArticle has key, store {
        id: UID,
        title: String,
        recommender: address,
        url: String,
        description: String,
        preview_image: Option<String>,
        tags: vector<ID>,
        category: String,
        view_count: u64,
        earnings: Balance<SUI>,
        status: u8,
        created_at: u64,
        approved_at: Option<u64>,
        
        // Source information
        source_domain: String,
        author_name: Option<String>,
        published_date: Option<u64>,
        
        // Engagement metrics
        click_count: u64,
        upvotes: u64,
        downvotes: u64,
        report_count: u64,
    }

    /// Article collection/series
    public struct ArticleCollection has key, store {
        id: UID,
        title: String,
        creator: address,
        description: String,
        articles: vector<ID>, // IDs of articles in collection
        cover_image: Option<String>,
        category: String,
        tags: vector<ID>,
        created_at: u64,
        last_updated: u64,
        is_series: bool, // true if articles should be read in order
        total_views: u64,
        subscriber_count: u64,
    }

    /// Article statistics aggregator
    public struct ArticleStats has key {
        id: UID,
        total_original_articles: u64,
        total_external_articles: u64,
        total_approved: u64,
        total_rejected: u64,
        total_views: u64,
        total_earnings_distributed: u64,
        
        // Category statistics
        articles_by_category: Table<String, u64>,
        
        // Author statistics
        top_authors: vector<AuthorStats>,
        
        // Time-based statistics
        articles_this_epoch: u64,
        views_this_epoch: u64,
    }

    /// Author statistics
    public struct AuthorStats has store, copy, drop {
        author: address,
        article_count: u64,
        total_views: u64,
        total_earnings: u64,
        average_rating: u8,
    }

    // =============== Events ===============
    
    public struct OriginalArticleCreated has copy, drop {
        article_id: ID,
        author: address,
        title: String,
        category: String,
        content_hash: vector<u8>,
        deposit_amount: u64,
        timestamp: u64,
    }

    public struct ExternalArticleCreated has copy, drop {
        article_id: ID,
        recommender: address,
        title: String,
        url: String,
        category: String,
        timestamp: u64,
    }

    public struct ArticleApproved has copy, drop {
        article_id: ID,
        article_type: u8, // 1: Original, 2: External
        timestamp: u64,
    }

    public struct ArticleRejected has copy, drop {
        article_id: ID,
        article_type: u8,
        reason: String,
        timestamp: u64,
    }

    public struct ArticleViewed has copy, drop {
        article_id: ID,
        viewer: address,
        timestamp: u64,
    }

    public struct ArticleEarningsDistributed has copy, drop {
        article_id: ID,
        author: address,
        amount: u64,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let stats = ArticleStats {
            id: object::new(ctx),
            total_original_articles: 0,
            total_external_articles: 0,
            total_approved: 0,
            total_rejected: 0,
            total_views: 0,
            total_earnings_distributed: 0,
            articles_by_category: table::new(ctx),
            top_authors: vector::empty(),
            articles_this_epoch: 0,
            views_this_epoch: 0,
        };
        
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Create an original article
    public entry fun create_original_article(
        title: String,
        content_hash: vector<u8>,
        tags: vector<ID>,
        category: String,
        difficulty: u8,
        word_count: u64,
        language: String,
        preview: String,
        cover_image: Option<String>,
        deposit: Coin<SUI>,
        params: &SystemParameters,
        stats: &mut ArticleStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let author = tx_context::sender(ctx);
        
        // Validate inputs
        let title_length = string::length(&title);
        assert!(
            title_length >= MIN_TITLE_LENGTH && title_length <= MAX_TITLE_LENGTH,
            E_INVALID_TITLE_LENGTH
        );
        assert!(vector::length(&content_hash) == 46, E_INVALID_CONTENT_HASH); // IPFS hash length
        assert!(difficulty >= DIFFICULTY_BEGINNER && difficulty <= DIFFICULTY_EXPERT, E_INVALID_DIFFICULTY);
        assert!(vector::length(&tags) <= MAX_TAGS, E_INVALID_TAG_COUNT);
        
        // Check deposit amount
        let required_deposit = parameters::get_article_deposit_original(params);
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);
        
        // Calculate reading time (assuming 200 words per minute)
        let reading_time = (word_count + 199) / 200;
        
        // Create article
        let article = OriginalArticle {
            id: object::new(ctx),
            title,
            author,
            content_hash,
            tags,
            category,
            difficulty,
            view_count: 0,
            earnings: balance::zero(),
            status: STATUS_PENDING,
            deposit_amount: coin::value(&deposit),
            validator_reviews: vector::empty(),
            created_at: clock::timestamp_ms(clock),
            approved_at: option::none(),
            last_updated: clock::timestamp_ms(clock),
            word_count,
            reading_time,
            language,
            preview,
            cover_image,
            like_count: 0,
            share_count: 0,
            bookmark_count: 0,
            comment_count: 0,
            version: 1,
            previous_versions: vector::empty(),
        };
        
        let article_id = object::uid_to_inner(&article.id);
        
        // Update user profile
        // TODO: Uncomment when user_profile has this function
        // user_profile::increment_content_created(profile);
        
        // Update statistics
        stats.total_original_articles = stats.total_original_articles + 1;
        stats.articles_this_epoch = stats.articles_this_epoch + 1;
        update_category_stats(stats, &category, true);
        
        // Emit event
        event::emit(OriginalArticleCreated {
            article_id,
            author,
            title: article.title,
            category: article.category,
            content_hash: article.content_hash,
            deposit_amount: article.deposit_amount,
            timestamp: article.created_at,
        });
        
        // Transfer deposit to validation
        transfer::public_transfer(deposit, @suiverse_content);
        
        transfer::share_object(article);
    }

    /// Create an external article recommendation
    public entry fun create_external_article(
        title: String,
        url: String,
        description: String,
        tags: vector<ID>,
        category: String,
        preview_image: Option<String>,
        author_name: Option<String>,
        deposit: Coin<SUI>,
        params: &SystemParameters,
        stats: &mut ArticleStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let recommender = tx_context::sender(ctx);
        
        // Validate inputs
        let title_length = string::length(&title);
        assert!(
            title_length >= MIN_TITLE_LENGTH && title_length <= MAX_TITLE_LENGTH,
            E_INVALID_TITLE_LENGTH
        );
        assert!(string::length(&description) <= MAX_DESCRIPTION_LENGTH, E_INVALID_TITLE_LENGTH);
        assert!(vector::length(&tags) <= MAX_TAGS, E_INVALID_TAG_COUNT);
        
        // Check deposit amount
        let required_deposit = parameters::get_article_deposit_external(params);
        assert!(coin::value(&deposit) >= required_deposit, E_INSUFFICIENT_DEPOSIT);
        
        // Extract domain from URL
        let source_domain = extract_domain(&url);
        
        // Create external article
        let article = ExternalArticle {
            id: object::new(ctx),
            title,
            recommender,
            url,
            description,
            preview_image,
            tags,
            category,
            view_count: 0,
            earnings: balance::zero(),
            status: STATUS_PENDING,
            created_at: clock::timestamp_ms(clock),
            approved_at: option::none(),
            source_domain,
            author_name,
            published_date: option::none(),
            click_count: 0,
            upvotes: 0,
            downvotes: 0,
            report_count: 0,
        };
        
        let article_id = object::uid_to_inner(&article.id);
        
        // Update user profile
        // TODO: Uncomment when user_profile has this function
        // user_profile::increment_content_created(profile);
        
        // Update statistics
        stats.total_external_articles = stats.total_external_articles + 1;
        stats.articles_this_epoch = stats.articles_this_epoch + 1;
        update_category_stats(stats, &category, true);
        
        // Emit event
        event::emit(ExternalArticleCreated {
            article_id,
            recommender,
            title: article.title,
            url: article.url,
            category: article.category,
            timestamp: article.created_at,
        });
        
        // Transfer deposit to validation
        transfer::public_transfer(deposit, @suiverse_content);
        
        transfer::share_object(article);
    }

    /// Update article after validation
    public fun update_article_status(
        article_id: ID,
        is_original: bool,
        approved: bool,
        stats: &mut ArticleStats,
        clock: &Clock,
    ) {
        // This would be called by validation module
        if (approved) {
            stats.total_approved = stats.total_approved + 1;
            
            event::emit(ArticleApproved {
                article_id,
                article_type: if (is_original) 1 else 2,
                timestamp: clock::timestamp_ms(clock),
            });
        } else {
            stats.total_rejected = stats.total_rejected + 1;
            
            event::emit(ArticleRejected {
                article_id,
                article_type: if (is_original) 1 else 2,
                reason: string::utf8(b"Failed validation"),
                timestamp: clock::timestamp_ms(clock),
            });
        }
    }

    /// View an article (increments view count)
    public entry fun view_original_article(
        article: &mut OriginalArticle,
        stats: &mut ArticleStats,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(article.status == STATUS_APPROVED, E_ARTICLE_NOT_APPROVED);
        
        article.view_count = article.view_count + 1;
        stats.total_views = stats.total_views + 1;
        stats.views_this_epoch = stats.views_this_epoch + 1;
        
        // Update viewer profile
        // TODO: Uncomment when user_profile has this function
        // user_profile::increment_content_consumed(viewer_profile);
        
        event::emit(ArticleViewed {
            article_id: object::uid_to_inner(&article.id),
            viewer: tx_context::sender(_ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// View an external article
    public entry fun view_external_article(
        article: &mut ExternalArticle,
        stats: &mut ArticleStats,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(article.status == STATUS_APPROVED, E_ARTICLE_NOT_APPROVED);
        
        article.view_count = article.view_count + 1;
        article.click_count = article.click_count + 1;
        stats.total_views = stats.total_views + 1;
        stats.views_this_epoch = stats.views_this_epoch + 1;
        
        // Update viewer profile
        // TODO: Uncomment when user_profile has this function
        // user_profile::increment_content_consumed(viewer_profile);
        
        event::emit(ArticleViewed {
            article_id: object::uid_to_inner(&article.id),
            viewer: tx_context::sender(_ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Like an original article
    public entry fun like_article(
        article: &mut OriginalArticle,
        _ctx: &TxContext,
    ) {
        assert!(article.status == STATUS_APPROVED, E_ARTICLE_NOT_APPROVED);
        article.like_count = article.like_count + 1;
    }

    /// Upvote an external article
    public entry fun upvote_external_article(
        article: &mut ExternalArticle,
        _ctx: &TxContext,
    ) {
        assert!(article.status == STATUS_APPROVED, E_ARTICLE_NOT_APPROVED);
        article.upvotes = article.upvotes + 1;
    }

    /// Downvote an external article
    public entry fun downvote_external_article(
        article: &mut ExternalArticle,
        _ctx: &TxContext,
    ) {
        assert!(article.status == STATUS_APPROVED, E_ARTICLE_NOT_APPROVED);
        article.downvotes = article.downvotes + 1;
    }

    /// Update article content (creates new version)
    public entry fun update_original_article(
        article: &mut OriginalArticle,
        new_content_hash: vector<u8>,
        new_preview: String,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(tx_context::sender(_ctx) == article.author, E_NOT_AUTHOR);
        assert!(vector::length(&new_content_hash) == 46, E_INVALID_CONTENT_HASH);
        
        // Save previous version
        vector::push_back(&mut article.previous_versions, article.content_hash);
        
        // Update content
        article.content_hash = new_content_hash;
        article.preview = new_preview;
        article.version = article.version + 1;
        article.last_updated = clock::timestamp_ms(clock);
    }

    /// Create article collection
    public entry fun create_article_collection(
        title: String,
        description: String,
        articles: vector<ID>,
        cover_image: Option<String>,
        category: String,
        tags: vector<ID>,
        is_series: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let collection = ArticleCollection {
            id: object::new(ctx),
            title,
            creator: tx_context::sender(ctx),
            description,
            articles,
            cover_image,
            category,
            tags,
            created_at: clock::timestamp_ms(clock),
            last_updated: clock::timestamp_ms(clock),
            is_series,
            total_views: 0,
            subscriber_count: 0,
        };
        
        transfer::share_object(collection);
    }

    /// Add article to collection
    public entry fun add_to_collection(
        collection: &mut ArticleCollection,
        article_id: ID,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(tx_context::sender(_ctx) == collection.creator, E_NOT_AUTHOR);
        
        vector::push_back(&mut collection.articles, article_id);
        collection.last_updated = clock::timestamp_ms(clock);
    }

    // =============== Internal Functions ===============
    
    /// Update category statistics
    fun update_category_stats(stats: &mut ArticleStats, category: &String, increment: bool) {
        if (table::contains(&stats.articles_by_category, *category)) {
            let count = table::borrow_mut(&mut stats.articles_by_category, *category);
            if (increment) {
                *count = *count + 1;
            } else if (*count > 0) {
                *count = *count - 1;
            }
        } else if (increment) {
            table::add(&mut stats.articles_by_category, *category, 1);
        }
    }

    /// Extract domain from URL
    fun extract_domain(url: &String): String {
        // Simple domain extraction (would need more robust implementation)
        let url_bytes = string::as_bytes(url);
        let mut start = 0;
        let mut i = 0;
        
        // Find "://" 
        while (i < vector::length(url_bytes) - 2) {
            if (*vector::borrow(url_bytes, i) == 58 && // ':'
                *vector::borrow(url_bytes, i + 1) == 47 && // '/'
                *vector::borrow(url_bytes, i + 2) == 47) { // '/'
                start = i + 3;
                break
            };
            i = i + 1;
        };
        
        // Find next '/'
        let mut end = start;
        while (end < vector::length(url_bytes)) {
            if (*vector::borrow(url_bytes, end) == 47) { // '/'
                break
            };
            end = end + 1;
        };
        
        // Extract domain
        let mut domain_bytes = vector::empty<u8>();
        let mut j = start;
        while (j < end && j < vector::length(url_bytes)) {
            vector::push_back(&mut domain_bytes, *vector::borrow(url_bytes, j));
            j = j + 1;
        };
        
        string::utf8(domain_bytes)
    }

    // =============== Read Functions ===============
    
    public fun get_article_status(article: &OriginalArticle): u8 {
        article.status
    }

    public fun get_article_author(article: &OriginalArticle): address {
        article.author
    }

    public fun get_article_view_count(article: &OriginalArticle): u64 {
        article.view_count
    }

    public fun get_external_article_status(article: &ExternalArticle): u8 {
        article.status
    }

    public fun get_external_article_url(article: &ExternalArticle): String {
        article.url
    }

    public fun get_stats(stats: &ArticleStats): (u64, u64, u64, u64) {
        (
            stats.total_original_articles,
            stats.total_external_articles,
            stats.total_approved,
            stats.total_views
        )
    }
}