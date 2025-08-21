module suiverse_content::collections {
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use std::vector;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use suiverse_content::articles::{Self, OriginalArticle, ExternalArticle};
    use suiverse_content::projects::{Self, Project};

    // =============== Constants ===============
    const E_NOT_OWNER: u64 = 5001;
    const E_ALREADY_EXISTS: u64 = 5002;
    const E_NOT_FOUND: u64 = 5003;
    const E_INVALID_TYPE: u64 = 5004;
    const E_COLLECTION_FULL: u64 = 5005;
    const E_EMPTY_COLLECTION: u64 = 5006;
    const E_INVALID_ACCESS: u64 = 5007;

    // Content types
    const CONTENT_TYPE_ARTICLE: u8 = 1;
    const CONTENT_TYPE_PROJECT: u8 = 2;
    const CONTENT_TYPE_QUIZ: u8 = 3;
    const CONTENT_TYPE_EXTERNAL: u8 = 4;

    // Collection visibility
    const VISIBILITY_PUBLIC: u8 = 1;
    const VISIBILITY_PRIVATE: u8 = 2;
    const VISIBILITY_FOLLOWERS_ONLY: u8 = 3;

    // Maximum items in a collection
    const MAX_ITEMS_PER_COLLECTION: u64 = 100;

    // =============== Structs ===============
    
    /// Content collection that groups related content
    public struct ContentCollection has key, store {
        id: UID,
        name: String,
        description: String,
        owner: address,
        items: vector<ContentItem>,
        tags: vector<ID>,
        visibility: u8,
        featured_item: Option<ID>,
        subscriber_count: u64,
        view_count: u64,
        created_at: u64,
        updated_at: u64,
    }

    /// Individual content item in a collection
    public struct ContentItem has store, drop, copy {
        content_id: ID,
        content_type: u8,
        title: String,
        description: String,
        added_at: u64,
        added_by: address,
        order_index: u64,
    }

    /// Collection subscription
    public struct CollectionSubscription has key, store {
        id: UID,
        subscriber: address,
        collection_id: ID,
        subscribed_at: u64,
        notifications_enabled: bool,
    }

    /// Collection statistics
    public struct CollectionStats has key {
        id: UID,
        total_collections: u64,
        public_collections: u64,
        total_items: u64,
        total_subscriptions: u64,
        popular_collections: vector<ID>,
        recent_collections: vector<ID>,
    }

    /// Collection recommendation
    public struct CollectionRecommendation has store, drop {
        collection_id: ID,
        reason: String,
        score: u64,
        recommended_at: u64,
    }

    // =============== Events ===============
    
    public struct CollectionCreated has copy, drop {
        collection_id: ID,
        owner: address,
        name: String,
        visibility: u8,
        timestamp: u64,
    }

    public struct ItemAddedToCollection has copy, drop {
        collection_id: ID,
        content_id: ID,
        content_type: u8,
        added_by: address,
        timestamp: u64,
    }

    public struct ItemRemovedFromCollection has copy, drop {
        collection_id: ID,
        content_id: ID,
        removed_by: address,
        timestamp: u64,
    }

    public struct CollectionSubscribed has copy, drop {
        collection_id: ID,
        subscriber: address,
        timestamp: u64,
    }

    public struct CollectionUnsubscribed has copy, drop {
        collection_id: ID,
        subscriber: address,
        timestamp: u64,
    }

    // =============== Init Function ===============
    
    fun init(ctx: &mut TxContext) {
        let stats = CollectionStats {
            id: object::new(ctx),
            total_collections: 0,
            public_collections: 0,
            total_items: 0,
            total_subscriptions: 0,
            popular_collections: vector::empty(),
            recent_collections: vector::empty(),
        };
        
        transfer::share_object(stats);
    }

    // =============== Public Entry Functions ===============
    
    /// Create a new content collection
    public entry fun create_collection(
        name: String,
        description: String,
        visibility: u8,
        tags: vector<ID>,
        stats: &mut CollectionStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let owner = tx_context::sender(ctx);
        
        // Validate visibility
        assert!(
            visibility >= VISIBILITY_PUBLIC && visibility <= VISIBILITY_FOLLOWERS_ONLY,
            E_INVALID_TYPE
        );

        let collection = ContentCollection {
            id: object::new(ctx),
            name,
            description,
            owner,
            items: vector::empty(),
            tags,
            visibility,
            featured_item: option::none(),
            subscriber_count: 0,
            view_count: 0,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        };

        let collection_id = object::uid_to_inner(&collection.id);

        // Update statistics
        stats.total_collections = stats.total_collections + 1;
        if (visibility == VISIBILITY_PUBLIC) {
            stats.public_collections = stats.public_collections + 1;
        };

        // Add to recent collections
        vector::push_back(&mut stats.recent_collections, collection_id);
        if (vector::length(&stats.recent_collections) > 10) {
            vector::remove(&mut stats.recent_collections, 0);
        };

        event::emit(CollectionCreated {
            collection_id,
            owner,
            name: collection.name,
            visibility,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::share_object(collection);
    }

    /// Add an item to a collection
    public entry fun add_item_to_collection(
        collection: &mut ContentCollection,
        content_id: ID,
        content_type: u8,
        title: String,
        description: String,
        stats: &mut CollectionStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check ownership
        assert!(collection.owner == sender, E_NOT_OWNER);
        
        // Check collection size limit
        assert!(
            vector::length(&collection.items) < MAX_ITEMS_PER_COLLECTION,
            E_COLLECTION_FULL
        );

        // Check if item already exists
        let mut i = 0;
        while (i < vector::length(&collection.items)) {
            let item = vector::borrow(&collection.items, i);
            assert!(item.content_id != content_id, E_ALREADY_EXISTS);
            i = i + 1;
        };

        // Add item
        let item = ContentItem {
            content_id,
            content_type,
            title,
            description,
            added_at: clock::timestamp_ms(clock),
            added_by: sender,
            order_index: vector::length(&collection.items),
        };

        vector::push_back(&mut collection.items, item);
        collection.updated_at = clock::timestamp_ms(clock);
        stats.total_items = stats.total_items + 1;

        event::emit(ItemAddedToCollection {
            collection_id: object::uid_to_inner(&collection.id),
            content_id,
            content_type,
            added_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Remove an item from a collection
    public entry fun remove_item_from_collection(
        collection: &mut ContentCollection,
        content_id: ID,
        stats: &mut CollectionStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        
        // Check ownership
        assert!(collection.owner == sender, E_NOT_OWNER);
        assert!(vector::length(&collection.items) > 0, E_EMPTY_COLLECTION);

        // Find and remove item
        let mut i = 0;
        let mut found = false;
        while (i < vector::length(&collection.items)) {
            let item = vector::borrow(&collection.items, i);
            if (item.content_id == content_id) {
                vector::remove(&mut collection.items, i);
                found = true;
                break
            };
            i = i + 1;
        };

        assert!(found, E_NOT_FOUND);
        
        collection.updated_at = clock::timestamp_ms(clock);
        stats.total_items = stats.total_items - 1;

        // Update featured item if it was removed
        if (option::is_some(&collection.featured_item)) {
            let featured = *option::borrow(&collection.featured_item);
            if (featured == content_id) {
                collection.featured_item = option::none();
            }
        };

        event::emit(ItemRemovedFromCollection {
            collection_id: object::uid_to_inner(&collection.id),
            content_id,
            removed_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Set featured item in collection
    public entry fun set_featured_item(
        collection: &mut ContentCollection,
        content_id: ID,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(collection.owner == sender, E_NOT_OWNER);

        // Verify item exists in collection
        let mut found = false;
        let mut i = 0;
        while (i < vector::length(&collection.items)) {
            let item = vector::borrow(&collection.items, i);
            if (item.content_id == content_id) {
                found = true;
                break
            };
            i = i + 1;
        };

        assert!(found, E_NOT_FOUND);
        
        collection.featured_item = option::some(content_id);
        collection.updated_at = clock::timestamp_ms(clock);
    }

    /// Reorder items in collection
    public entry fun reorder_items(
        collection: &mut ContentCollection,
        content_id: ID,
        new_index: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(collection.owner == sender, E_NOT_OWNER);
        assert!(new_index < vector::length(&collection.items), E_NOT_FOUND);

        // Find item
        let mut current_index = 0;
        let mut found = false;
        while (current_index < vector::length(&collection.items)) {
            let item = vector::borrow(&collection.items, current_index);
            if (item.content_id == content_id) {
                found = true;
                break
            };
            current_index = current_index + 1;
        };

        assert!(found, E_NOT_FOUND);

        // Move item to new position
        if (current_index != new_index) {
            let item = vector::remove(&mut collection.items, current_index);
            vector::insert(&mut collection.items, item, new_index);
            
            // Update order indices
            let mut i = 0;
            while (i < vector::length(&collection.items)) {
                let item_mut = vector::borrow_mut(&mut collection.items, i);
                item_mut.order_index = i;
                i = i + 1;
            };
        };

        collection.updated_at = clock::timestamp_ms(clock);
    }

    /// Subscribe to a collection
    public entry fun subscribe_to_collection(
        collection: &mut ContentCollection,
        stats: &mut CollectionStats,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let subscriber = tx_context::sender(ctx);

        // Check visibility
        assert!(
            collection.visibility == VISIBILITY_PUBLIC ||
            collection.owner == subscriber,
            E_INVALID_ACCESS
        );

        let subscription = CollectionSubscription {
            id: object::new(ctx),
            subscriber,
            collection_id: object::uid_to_inner(&collection.id),
            subscribed_at: clock::timestamp_ms(clock),
            notifications_enabled: true,
        };

        collection.subscriber_count = collection.subscriber_count + 1;
        stats.total_subscriptions = stats.total_subscriptions + 1;

        event::emit(CollectionSubscribed {
            collection_id: object::uid_to_inner(&collection.id),
            subscriber,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::transfer(subscription, subscriber);
    }

    /// Unsubscribe from a collection
    public entry fun unsubscribe_from_collection(
        subscription: CollectionSubscription,
        collection: &mut ContentCollection,
        stats: &mut CollectionStats,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let subscriber = tx_context::sender(ctx);
        assert!(subscription.subscriber == subscriber, E_NOT_OWNER);

        collection.subscriber_count = collection.subscriber_count - 1;
        stats.total_subscriptions = stats.total_subscriptions - 1;

        event::emit(CollectionUnsubscribed {
            collection_id: subscription.collection_id,
            subscriber,
            timestamp: clock::timestamp_ms(clock),
        });

        // Delete subscription object
        let CollectionSubscription { id, subscriber: _, collection_id: _, subscribed_at: _, notifications_enabled: _ } = subscription;
        object::delete(id);
    }

    /// Update collection metadata
    public entry fun update_collection(
        collection: &mut ContentCollection,
        name: Option<String>,
        description: Option<String>,
        visibility: Option<u8>,
        tags: Option<vector<ID>>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(collection.owner == sender, E_NOT_OWNER);

        if (option::is_some(&name)) {
            collection.name = *option::borrow(&name);
        };

        if (option::is_some(&description)) {
            collection.description = *option::borrow(&description);
        };

        if (option::is_some(&visibility)) {
            let new_visibility = *option::borrow(&visibility);
            assert!(
                new_visibility >= VISIBILITY_PUBLIC && 
                new_visibility <= VISIBILITY_FOLLOWERS_ONLY,
                E_INVALID_TYPE
            );
            collection.visibility = new_visibility;
        };

        if (option::is_some(&tags)) {
            collection.tags = *option::borrow(&tags);
        };

        collection.updated_at = clock::timestamp_ms(clock);
    }

    /// View a collection (increments view count)
    public entry fun view_collection(
        collection: &mut ContentCollection,
        _ctx: &TxContext,
    ) {
        collection.view_count = collection.view_count + 1;
    }

    // =============== View Functions ===============
    
    public fun get_collection_items(collection: &ContentCollection): &vector<ContentItem> {
        &collection.items
    }

    public fun get_collection_owner(collection: &ContentCollection): address {
        collection.owner
    }

    public fun get_collection_visibility(collection: &ContentCollection): u8 {
        collection.visibility
    }

    public fun get_collection_subscriber_count(collection: &ContentCollection): u64 {
        collection.subscriber_count
    }

    public fun get_collection_item_count(collection: &ContentCollection): u64 {
        vector::length(&collection.items)
    }

    public fun get_featured_item(collection: &ContentCollection): Option<ID> {
        collection.featured_item
    }

    public fun is_public(collection: &ContentCollection): bool {
        collection.visibility == VISIBILITY_PUBLIC
    }

    public fun get_stats(stats: &CollectionStats): (u64, u64, u64, u64) {
        (
            stats.total_collections,
            stats.public_collections,
            stats.total_items,
            stats.total_subscriptions
        )
    }
}