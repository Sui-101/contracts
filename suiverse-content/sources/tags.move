module suiverse_content::tags {
    use std::string::{Self, String};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self as vec_set, VecSet};
    use sui::clock::{Self, Clock};

    // =============== Constants ===============
    const E_TAG_ALREADY_EXISTS: u64 = 7001;
    const E_TAG_NOT_FOUND: u64 = 7002;
    const E_INVALID_TAG_NAME: u64 = 7003;
    const E_CATEGORY_NOT_FOUND: u64 = 7004;
    const E_NOT_AUTHORIZED: u64 = 7005;
    const E_TAG_IN_USE: u64 = 7006;
    const E_MAX_TAGS_REACHED: u64 = 7007;

    // Tag categories
    const CATEGORY_TECHNOLOGY: u8 = 1;
    const CATEGORY_FRAMEWORK: u8 = 2;
    const CATEGORY_LANGUAGE: u8 = 3;
    const CATEGORY_BLOCKCHAIN: u8 = 4;
    const CATEGORY_TOPIC: u8 = 5;
    const CATEGORY_DIFFICULTY: u8 = 6;
    const CATEGORY_OTHER: u8 = 7;

    // Maximum tags per content
    const MAX_TAGS_PER_CONTENT: u64 = 10;
    
    // Minimum tag name length
    const MIN_TAG_LENGTH: u64 = 2;
    const MAX_TAG_LENGTH: u64 = 50;

    // =============== Structs ===============
    
    /// Individual tag
    public struct Tag has key, store {
        id: UID,
        name: String,
        normalized_name: String, // lowercase, no spaces
        category: u8,
        description: String,
        usage_count: u64,
        created_by: address,
        created_at: u64,
        synonyms: vector<String>,
        related_tags: vector<ID>,
    }

    /// Tag registry
    public struct TagRegistry has key {
        id: UID,
        tags: Table<String, ID>, // normalized_name -> Tag ID
        categories: Table<u8, VecSet<ID>>,
        trending_tags: vector<ID>,
        total_tags: u64,
        admin: address,
    }

    /// Content-tag mapping
    public struct ContentTagMapping has key {
        id: UID,
        content_tags: Table<ID, vector<ID>>, // content_id -> tag_ids
        tag_contents: Table<ID, VecSet<ID>>, // tag_id -> content_ids
    }

    /// Tag statistics
    public struct TagStats has key {
        id: UID,
        daily_usage: Table<u64, Table<ID, u64>>, // day -> tag_id -> count
        weekly_trending: vector<TrendingTag>,
        monthly_trending: vector<TrendingTag>,
    }

    /// Trending tag information
    public struct TrendingTag has store, drop, copy {
        tag_id: ID,
        name: String,
        usage_count: u64,
        growth_rate: u64, // percentage
        period: u64, // timestamp of period
    }

    // =============== Events ===============
    
    public struct TagCreated has copy, drop {
        tag_id: ID,
        name: String,
        category: u8,
        created_by: address,
        timestamp: u64,
    }

    public struct TagUsed has copy, drop {
        tag_id: ID,
        content_id: ID,
        content_type: u8,
        timestamp: u64,
    }

    public struct TagRemoved has copy, drop {
        tag_id: ID,
        content_id: ID,
        timestamp: u64,
    }

    public struct TagMerged has copy, drop {
        source_tag_id: ID,
        target_tag_id: ID,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let mut registry = TagRegistry {
            id: object::new(ctx),
            tags: table::new(ctx),
            categories: table::new(ctx),
            trending_tags: vector::empty<ID>(),
            total_tags: 0,
            admin: tx_context::sender(ctx),
        };

        // Initialize category tables
        let mut i = CATEGORY_TECHNOLOGY;
        while (i <= CATEGORY_OTHER) {
            table::add(&mut registry.categories, i, vec_set::empty());
            i = i + 1;
        };

        let mapping = ContentTagMapping {
            id: object::new(ctx),
            content_tags: table::new(ctx),
            tag_contents: table::new(ctx),
        };

        let stats = TagStats {
            id: object::new(ctx),
            daily_usage: table::new(ctx),
            weekly_trending: vector::empty<TrendingTag>(),
            monthly_trending: vector::empty<TrendingTag>(),
        };

        transfer::share_object(registry);
        transfer::share_object(mapping);
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Create a new tag
    public entry fun create_tag(
        name: String,
        category: u8,
        description: String,
        registry: &mut TagRegistry,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let creator = tx_context::sender(ctx);
        
        // Validate tag name
        let name_length = string::length(&name);
        assert!(name_length >= MIN_TAG_LENGTH && name_length <= MAX_TAG_LENGTH, E_INVALID_TAG_NAME);
        assert!(category >= CATEGORY_TECHNOLOGY && category <= CATEGORY_OTHER, E_CATEGORY_NOT_FOUND);
        
        // Normalize tag name (lowercase, no spaces)
        let normalized = normalize_tag_name(&name);
        
        // Check if tag already exists
        assert!(!table::contains(&registry.tags, normalized), E_TAG_ALREADY_EXISTS);
        
        // Create tag
        let tag = Tag {
            id: object::new(ctx),
            name,
            normalized_name: normalized,
            category,
            description,
            usage_count: 0,
            created_by: creator,
            created_at: clock::timestamp_ms(clock),
            synonyms: vector::empty<String>(),
            related_tags: vector::empty<ID>(),
        };
        
        let tag_id = object::uid_to_inner(&tag.id);
        
        // Add to registry
        table::add(&mut registry.tags, normalized, tag_id);
        
        // Add to category
        let category_tags = table::borrow_mut(&mut registry.categories, category);
        vec_set::insert(category_tags, tag_id);
        
        registry.total_tags = registry.total_tags + 1;
        
        event::emit(TagCreated {
            tag_id,
            name: tag.name,
            category,
            created_by: creator,
            timestamp: clock::timestamp_ms(clock),
        });
        
        transfer::share_object(tag);
    }

    /// Add tags to content
    public entry fun add_tags_to_content(
        content_id: ID,
        tag_ids: vector<ID>,
        content_type: u8,
        registry: &mut TagRegistry,
        mapping: &mut ContentTagMapping,
        stats: &mut TagStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // Check max tags limit
        assert!(vector::length(&tag_ids) <= MAX_TAGS_PER_CONTENT, E_MAX_TAGS_REACHED);
        
        // Get or create content tag list
        if (!table::contains(&mapping.content_tags, content_id)) {
            table::add(&mut mapping.content_tags, content_id, vector::empty<ID>());
        };
        
        let content_tags = table::borrow_mut(&mut mapping.content_tags, content_id);
        let current_day = clock::timestamp_ms(clock) / 86400000; // Convert to days
        
        // Ensure daily usage table exists
        if (!table::contains(&stats.daily_usage, current_day)) {
            table::add(&mut stats.daily_usage, current_day, table::new(ctx));
        };
        let daily_stats = table::borrow_mut(&mut stats.daily_usage, current_day);
        
        // Add each tag
        let mut i = 0;
        while (i < vector::length(&tag_ids)) {
            let tag_id = *vector::borrow(&tag_ids, i);
            
            // Check if tag not already added to this content
            if (!vector::contains(content_tags, &tag_id)) {
                vector::push_back(content_tags, tag_id);
                
                // Update tag-content mapping
                if (!table::contains(&mapping.tag_contents, tag_id)) {
                    table::add(&mut mapping.tag_contents, tag_id, vec_set::empty());
                };
                let tag_contents = table::borrow_mut(&mut mapping.tag_contents, tag_id);
                vec_set::insert(tag_contents, content_id);
                
                // Update daily usage stats
                if (!table::contains(daily_stats, tag_id)) {
                    table::add(daily_stats, tag_id, 0);
                };
                let usage_count = table::borrow_mut(daily_stats, tag_id);
                *usage_count = *usage_count + 1;
                
                event::emit(TagUsed {
                    tag_id,
                    content_id,
                    content_type,
                    timestamp: clock::timestamp_ms(clock),
                });
            };
            
            i = i + 1;
        };
    }

    /// Remove tags from content
    public entry fun remove_tags_from_content(
        content_id: ID,
        tag_ids: vector<ID>,
        mapping: &mut ContentTagMapping,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(table::contains(&mapping.content_tags, content_id), E_TAG_NOT_FOUND);
        
        let content_tags = table::borrow_mut(&mut mapping.content_tags, content_id);
        
        let mut i = 0;
        while (i < vector::length(&tag_ids)) {
            let tag_id = *vector::borrow(&tag_ids, i);
            
            // Find and remove tag from content
            let mut j = 0;
            while (j < vector::length(content_tags)) {
                if (*vector::borrow(content_tags, j) == tag_id) {
                    vector::remove(content_tags, j);
                    
                    // Update tag-content mapping
                    if (table::contains(&mapping.tag_contents, tag_id)) {
                        let tag_contents = table::borrow_mut(&mut mapping.tag_contents, tag_id);
                        vec_set::remove(tag_contents, &content_id);
                    };
                    
                    event::emit(TagRemoved {
                        tag_id,
                        content_id,
                        timestamp: clock::timestamp_ms(clock),
                    });
                    
                    break
                };
                j = j + 1;
            };
            
            i = i + 1;
        };
    }

    /// Add synonym to a tag
    public entry fun add_synonym(
        tag: &mut Tag,
        synonym: String,
        registry: &TagRegistry,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == tag.created_by || sender == registry.admin, E_NOT_AUTHORIZED);
        
        // Normalize synonym
        let normalized_synonym = normalize_tag_name(&synonym);
        
        // Check if synonym doesn't conflict with existing tags
        assert!(!table::contains(&registry.tags, normalized_synonym), E_TAG_ALREADY_EXISTS);
        
        // Add synonym if not already present
        if (!vector::contains(&tag.synonyms, &synonym)) {
            vector::push_back(&mut tag.synonyms, synonym);
        };
    }

    /// Add related tags
    public entry fun add_related_tags(
        tag: &mut Tag,
        related_tag_ids: vector<ID>,
        registry: &TagRegistry,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == tag.created_by || sender == registry.admin, E_NOT_AUTHORIZED);
        
        let mut i = 0;
        while (i < vector::length(&related_tag_ids)) {
            let related_id = *vector::borrow(&related_tag_ids, i);
            if (!vector::contains(&tag.related_tags, &related_id)) {
                vector::push_back(&mut tag.related_tags, related_id);
            };
            i = i + 1;
        };
    }

    /// Merge two tags (admin only)
    public entry fun merge_tags(
        source_tag: Tag,
        target_tag: &mut Tag,
        registry: &mut TagRegistry,
        mapping: &mut ContentTagMapping,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == registry.admin, E_NOT_AUTHORIZED);
        
        let source_id = object::uid_to_inner(&source_tag.id);
        let target_id = object::uid_to_inner(&target_tag.id);
        
        // Move all content associations from source to target
        if (table::contains(&mapping.tag_contents, source_id)) {
            let source_contents = table::remove(&mut mapping.tag_contents, source_id);
            
            if (!table::contains(&mapping.tag_contents, target_id)) {
                table::add(&mut mapping.tag_contents, target_id, vec_set::empty());
            };
            
            let target_contents = table::borrow_mut(&mut mapping.tag_contents, target_id);
            
            // Merge content sets
            let source_vec = vec_set::into_keys(source_contents);
            let mut i = 0;
            while (i < vector::length(&source_vec)) {
                vec_set::insert(target_contents, *vector::borrow(&source_vec, i));
                i = i + 1;
            };
        };
        
        // Add source synonyms to target
        let mut i = 0;
        while (i < vector::length(&source_tag.synonyms)) {
            let synonym = *vector::borrow(&source_tag.synonyms, i);
            if (!vector::contains(&target_tag.synonyms, &synonym)) {
                vector::push_back(&mut target_tag.synonyms, synonym);
            };
            i = i + 1;
        };
        
        // Update usage count
        target_tag.usage_count = target_tag.usage_count + source_tag.usage_count;
        
        // Remove source tag from registry
        table::remove(&mut registry.tags, source_tag.normalized_name);
        
        // Remove from category
        let category_tags = table::borrow_mut(&mut registry.categories, source_tag.category);
        vec_set::remove(category_tags, &source_id);
        
        registry.total_tags = registry.total_tags - 1;
        
        event::emit(TagMerged {
            source_tag_id: source_id,
            target_tag_id: target_id,
            timestamp: clock::timestamp_ms(clock),
        });
        
        // Delete source tag
        let Tag { id, name: _, normalized_name: _, category: _, description: _, 
                  usage_count: _, created_by: _, created_at: _, synonyms: _, related_tags: _ } = source_tag;
        object::delete(id);
    }

    /// Update trending tags
    public entry fun update_trending_tags(
        registry: &mut TagRegistry,
        stats: &mut TagStats,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        let current_day = clock::timestamp_ms(clock) / 86400000;
        
        if (table::contains(&stats.daily_usage, current_day)) {
            let daily_stats = table::borrow(&stats.daily_usage, current_day);
            
            // Calculate trending tags based on usage
            // This is a simplified version - in production would use more sophisticated algorithm
            let mut trending = vector::empty<ID>();
            
            // Add top 10 most used tags to trending
            // Note: This is a placeholder - would need proper sorting algorithm
            registry.trending_tags = trending;
        };
    }

    // =============== Internal Functions ===============
    
    /// Normalize tag name for consistency
    fun normalize_tag_name(name: &String): String {
        // Convert to lowercase and remove spaces
        // This is a simplified version - in production would need proper normalization
        let bytes = string::as_bytes(name);
        let mut normalized_bytes = vector::empty<u8>();
        
        let mut i = 0;
        while (i < vector::length(bytes)) {
            let mut byte = *vector::borrow(bytes, i);
            // Convert uppercase to lowercase (ASCII only)
            if (byte >= 65 && byte <= 90) {
                byte = byte + 32;
            };
            // Skip spaces
            if (byte != 32) {
                vector::push_back(&mut normalized_bytes, byte);
            };
            i = i + 1;
        };
        
        string::utf8(normalized_bytes)
    }

    // =============== View Functions ===============
    
    public fun get_tag_by_name(registry: &TagRegistry, name: String): Option<ID> {
        let normalized = normalize_tag_name(&name);
        if (table::contains(&registry.tags, normalized)) {
            option::some(*table::borrow(&registry.tags, normalized))
        } else {
            option::none()
        }
    }

    public fun get_content_tags(mapping: &ContentTagMapping, content_id: ID): vector<ID> {
        if (table::contains(&mapping.content_tags, content_id)) {
            *table::borrow(&mapping.content_tags, content_id)
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_tag_contents(mapping: &ContentTagMapping, tag_id: ID): vector<ID> {
        if (table::contains(&mapping.tag_contents, tag_id)) {
            vec_set::into_keys(*table::borrow(&mapping.tag_contents, tag_id))
        } else {
            vector::empty<ID>()
        }
    }

    public fun get_trending_tags(registry: &TagRegistry): vector<ID> {
        registry.trending_tags
    }

    public fun get_tag_usage_count(tag: &Tag): u64 {
        tag.usage_count
    }

    public fun get_tag_category(tag: &Tag): u8 {
        tag.category
    }

    public fun get_total_tags(registry: &TagRegistry): u64 {
        registry.total_tags
    }
}