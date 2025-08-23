/// Certificate Registry using Dynamic Object Fields
/// Manages certificate lookups and validation tracking
module suiverse_certificate::certificate_registry {
    use std::string::{String};
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::dynamic_object_field as dof;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use suiverse_certificate::standalone_certificates::{CertificateNFT};

    // =============== Error Constants ===============
    const E_NOT_AUTHORIZED: u64 = 30001;
    const E_CERTIFICATE_NOT_FOUND: u64 = 30002;
    const E_ALREADY_REGISTERED: u64 = 30003;
    const E_REGISTRY_NOT_INITIALIZED: u64 = 30004;

    // =============== Dynamic Object Field Keys ===============
    
    /// Key for certificate lookup table
    public struct CertificateLookupKey has copy, drop, store {}
    
    /// Key for skill mappings table
    public struct SkillMappingsKey has copy, drop, store {}
    
    /// Key for issuer tracking table
    public struct IssuerTrackingKey has copy, drop, store {}

    // =============== Core Structs ===============

    /// Certificate registry using Dynamic Object Fields
    public struct CertificateRegistry has key, store {
        id: UID,
        total_registered: u64,
        registry_version: u64,
        created_at: u64,
        authorized_validators: VecSet<address>,
    }

    /// Certificate lookup table stored as DOF
    public struct CertificateLookupTable has key, store {
        id: UID,
        certificate_to_owner: Table<ID, address>,
        owner_to_certificates: Table<address, VecSet<ID>>,
    }

    /// Skill mappings table stored as DOF
    public struct SkillMappingsTable has key, store {
        id: UID,
        skill_to_certificates: Table<String, VecSet<ID>>,
        certificate_to_skills: Table<ID, vector<String>>,
    }

    /// Issuer tracking table stored as DOF
    public struct IssuerTrackingTable has key, store {
        id: UID,
        issuer_to_certificates: Table<address, VecSet<ID>>,
        certificate_to_issuer: Table<ID, address>,
    }

    /// Registry administrative capability
    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    // =============== Init Function ===============

    fun init(ctx: &mut TxContext) {
        let registry_admin_cap = RegistryAdminCap {
            id: object::new(ctx),
        };

        transfer::transfer(registry_admin_cap, tx_context::sender(ctx));
    }

    // =============== Initialization Functions ===============

    /// Initialize the certificate registry system
    public entry fun initialize_certificate_registry(
        _admin_cap: &RegistryAdminCap,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let current_time = clock::timestamp_ms(clock);
        let sender = tx_context::sender(ctx);

        let mut registry = CertificateRegistry {
            id: object::new(ctx),
            total_registered: 0,
            registry_version: 1,
            created_at: current_time,
            authorized_validators: vec_set::empty(),
        };

        // Add initializing admin as validator
        vec_set::insert(&mut registry.authorized_validators, sender);

        // Create and store lookup tables using DOF
        let lookup_table = CertificateLookupTable {
            id: object::new(ctx),
            certificate_to_owner: table::new(ctx),
            owner_to_certificates: table::new(ctx),
        };

        let skill_mappings = SkillMappingsTable {
            id: object::new(ctx),
            skill_to_certificates: table::new(ctx),
            certificate_to_skills: table::new(ctx),
        };

        let issuer_tracking = IssuerTrackingTable {
            id: object::new(ctx),
            issuer_to_certificates: table::new(ctx),
            certificate_to_issuer: table::new(ctx),
        };

        // Store tables as DOF
        dof::add(&mut registry.id, CertificateLookupKey {}, lookup_table);
        dof::add(&mut registry.id, SkillMappingsKey {}, skill_mappings);
        dof::add(&mut registry.id, IssuerTrackingKey {}, issuer_tracking);

        transfer::share_object(registry);
    }

    // =============== Certificate Registration Functions ===============

    /// Register a certificate in the registry (avoiding borrow conflicts)
    public fun register_certificate_in_registry(
        registry: &mut CertificateRegistry,
        certificate: &CertificateNFT,
        skills: vector<String>,
        issuer: address,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(is_authorized_validator(registry, tx_context::sender(ctx)), E_NOT_AUTHORIZED);

        let certificate_id = object::id(certificate);
        let owner = tx_context::sender(ctx);

        // Remove tables from DOF temporarily to avoid borrow conflicts
        let mut lookup_table = dof::remove<CertificateLookupKey, CertificateLookupTable>(
            &mut registry.id, CertificateLookupKey {}
        );
        let mut skill_mappings = dof::remove<SkillMappingsKey, SkillMappingsTable>(
            &mut registry.id, SkillMappingsKey {}
        );
        let mut issuer_tracking = dof::remove<IssuerTrackingKey, IssuerTrackingTable>(
            &mut registry.id, IssuerTrackingKey {}
        );

        // Update lookup table
        table::add(&mut lookup_table.certificate_to_owner, certificate_id, owner);
        
        if (table::contains(&lookup_table.owner_to_certificates, owner)) {
            let owner_certs = table::borrow_mut(&mut lookup_table.owner_to_certificates, owner);
            vec_set::insert(owner_certs, certificate_id);
        } else {
            let mut new_set = vec_set::empty();
            vec_set::insert(&mut new_set, certificate_id);
            table::add(&mut lookup_table.owner_to_certificates, owner, new_set);
        };

        // Update skill mappings
        table::add(&mut skill_mappings.certificate_to_skills, certificate_id, skills);
        
        let mut i = 0;
        while (i < vector::length(&skills)) {
            let skill = *vector::borrow(&skills, i);
            
            if (table::contains(&skill_mappings.skill_to_certificates, skill)) {
                let skill_certs = table::borrow_mut(&mut skill_mappings.skill_to_certificates, skill);
                vec_set::insert(skill_certs, certificate_id);
            } else {
                let mut new_set = vec_set::empty();
                vec_set::insert(&mut new_set, certificate_id);
                table::add(&mut skill_mappings.skill_to_certificates, skill, new_set);
            };
            
            i = i + 1;
        };

        // Update issuer tracking
        table::add(&mut issuer_tracking.certificate_to_issuer, certificate_id, issuer);
        
        if (table::contains(&issuer_tracking.issuer_to_certificates, issuer)) {
            let issuer_certs = table::borrow_mut(&mut issuer_tracking.issuer_to_certificates, issuer);
            vec_set::insert(issuer_certs, certificate_id);
        } else {
            let mut new_set = vec_set::empty();
            vec_set::insert(&mut new_set, certificate_id);
            table::add(&mut issuer_tracking.issuer_to_certificates, issuer, new_set);
        };

        // Update registry stats
        registry.total_registered = registry.total_registered + 1;

        // Put tables back into DOF
        dof::add(&mut registry.id, CertificateLookupKey {}, lookup_table);
        dof::add(&mut registry.id, SkillMappingsKey {}, skill_mappings);
        dof::add(&mut registry.id, IssuerTrackingKey {}, issuer_tracking);
    }

    // =============== Query Functions ===============

    /// Get certificates by owner
    public fun get_certificates_by_owner(
        registry: &CertificateRegistry,
        owner: address,
    ): vector<ID> {
        if (!dof::exists_<CertificateLookupKey>(&registry.id, CertificateLookupKey {})) {
            return vector::empty()
        };

        let lookup_table = dof::borrow<CertificateLookupKey, CertificateLookupTable>(
            &registry.id, CertificateLookupKey {}
        );

        if (table::contains(&lookup_table.owner_to_certificates, owner)) {
            vec_set::into_keys(*table::borrow(&lookup_table.owner_to_certificates, owner))
        } else {
            vector::empty()
        }
    }

    /// Get certificates by skill
    public fun get_certificates_by_skill(
        registry: &CertificateRegistry,
        skill: String,
    ): vector<ID> {
        if (!dof::exists_<SkillMappingsKey>(&registry.id, SkillMappingsKey {})) {
            return vector::empty()
        };

        let skill_mappings = dof::borrow<SkillMappingsKey, SkillMappingsTable>(
            &registry.id, SkillMappingsKey {}
        );

        if (table::contains(&skill_mappings.skill_to_certificates, skill)) {
            vec_set::into_keys(*table::borrow(&skill_mappings.skill_to_certificates, skill))
        } else {
            vector::empty()
        }
    }

    /// Get certificates by issuer
    public fun get_certificates_by_issuer(
        registry: &CertificateRegistry,
        issuer: address,
    ): vector<ID> {
        if (!dof::exists_<IssuerTrackingKey>(&registry.id, IssuerTrackingKey {})) {
            return vector::empty()
        };

        let issuer_tracking = dof::borrow<IssuerTrackingKey, IssuerTrackingTable>(
            &registry.id, IssuerTrackingKey {}
        );

        if (table::contains(&issuer_tracking.issuer_to_certificates, issuer)) {
            vec_set::into_keys(*table::borrow(&issuer_tracking.issuer_to_certificates, issuer))
        } else {
            vector::empty()
        }
    }

    // =============== Helper Functions ===============

    fun is_authorized_validator(registry: &CertificateRegistry, address: address): bool {
        vec_set::contains(&registry.authorized_validators, &address)
    }

    /// Add authorized validator
    public entry fun add_authorized_validator(
        registry: &mut CertificateRegistry,
        new_validator: address,
        _admin_cap: &RegistryAdminCap,
        ctx: &TxContext,
    ) {
        assert!(is_authorized_validator(registry, tx_context::sender(ctx)), E_NOT_AUTHORIZED);
        vec_set::insert(&mut registry.authorized_validators, new_validator);
    }

    // =============== View Functions ===============

    public fun get_registry_stats(registry: &CertificateRegistry): (u64, u64, u64) {
        (registry.total_registered, registry.registry_version, registry.created_at)
    }

    public fun is_registry_healthy(registry: &CertificateRegistry): bool {
        dof::exists_<CertificateLookupKey>(&registry.id, CertificateLookupKey {}) &&
        dof::exists_<SkillMappingsKey>(&registry.id, SkillMappingsKey {}) &&
        dof::exists_<IssuerTrackingKey>(&registry.id, IssuerTrackingKey {})
    }
}