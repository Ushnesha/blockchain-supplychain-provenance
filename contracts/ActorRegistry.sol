// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ActorRegistry
 * @notice Identity and role management for all supply chain participants.
 *
 * @dev Acts as the single source of truth for who is authorized to participate
 *      in the supply chain. Other contracts (SupplyChain, PaymentEscrow) query
 *      this registry to validate actors before permitting sensitive operations.
 *
 *      Roles map directly to the proposal's five stakeholder types:
 *        Manufacturer → Supplier → Distributor → Retailer (→ Consumer implied)
 *        Regulator: read-only auditing and compliance verification.
 *
 *      Design principles:
 *        - Duplicate prevention : one address can hold exactly one role at a time.
 *        - Auditability         : every registration and role change emits an event.
 *        - Deactivation vs deletion : actors are deactivated, never erased, preserving history.
 *        - Error safety         : guards against zero addresses, None-role assignments,
 *                                 and operations on unregistered actors.
 */
contract ActorRegistry {

    // ═══════════════════════════════════════════════════════════
    // SECTION 1 — DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Supply chain roles, aligned with stakeholder types described in the proposal.
     *
     * @dev Role.None is the default for any unregistered address and serves as a
     *      sentinel value — assigning None is explicitly prohibited.
     *
     *  None        — unregistered; cannot participate in any chain operations
     *  Manufacturer — registers new products; first actor in the chain
     *  Supplier    — provides raw materials or intermediate components
     *  Distributor — moves goods between locations; operates warehouses
     *  Retailer    — final point of sale; marks products as Sold
     *  Regulator   — read-only auditing role; cannot modify chain state
     */
    enum Role {
        None,
        Manufacturer,
        Supplier,
        Distributor,
        Retailer,
        Regulator
    }

    /**
     * @notice Stores identity and authorization data for a registered supply chain actor.
     *
     * @dev Fields:
     *   wallet       — Actor's Ethereum address (primary key).
     *   name         — Legal or business name for identification.
     *   location     — Physical location or jurisdiction.
     *   role         — Assigned supply chain role (see Role enum).
     *   isActive     — Soft-delete flag; false means deactivated (not erased).
     *   registeredAt — Block timestamp of initial registration (immutable after set).
     */
    struct Actor {
        address wallet;
        string  name;
        string  location;
        Role    role;
        bool    isActive;
        uint256 registeredAt;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 2 — STATE VARIABLES
    // ═══════════════════════════════════════════════════════════

    /// @notice Contract admin — the only address that can register actors and change roles.
    address public immutable owner;

    /// @notice Primary actor registry: maps wallet address → Actor struct.
    ///         Actors are never deleted; isActive=false represents deactivation.
    mapping(address => Actor) public actors;

    /// @notice Ordered list of all registered actor addresses for enumeration.
    ///         Used by frontends and regulators to iterate over all participants.
    address[] public actorList;

    // ═══════════════════════════════════════════════════════════
    // SECTION 3 — EVENTS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new actor is registered in the registry.
     * @param wallet   The actor's Ethereum address.
     * @param name     The actor's business/legal name.
     * @param role     The supply chain role assigned.
     * @param location The actor's physical location or jurisdiction.
     */
    event ActorRegistered(
        address indexed wallet,
        string  name,
        Role    indexed role,
        string  location
    );

    /**
     * @notice Emitted when an existing actor's role is changed by the owner.
     * @param wallet   The actor's address.
     * @param oldRole  The role before the update.
     * @param newRole  The role after the update.
     */
    event ActorRoleUpdated(
        address indexed wallet,
        Role    oldRole,
        Role    newRole
    );

    /**
     * @notice Emitted when an actor's active/deactivated status is toggled.
     * @param wallet   The actor's address.
     * @param isActive True if newly activated, false if deactivated.
     */
    event ActorStatusChanged(address indexed wallet, bool isActive);

    // ═══════════════════════════════════════════════════════════
    // SECTION 4 — MODIFIERS
    // ═══════════════════════════════════════════════════════════

    /// @dev Restricts to the contract owner/admin only.
    modifier onlyOwner() {
        require(msg.sender == owner, "ActorRegistry: caller is not the owner");
        _;
    }

    /// @dev Ensures the target address corresponds to a registered actor (role != None).
    modifier actorRegistered(address wallet) {
        require(actors[wallet].role != Role.None, "ActorRegistry: actor is not registered");
        _;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 5 — CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Deploys the ActorRegistry.
     * @dev Sets the deployer as the immutable owner/admin of the registry.
     */
    constructor() {
        owner = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 6 — REGISTRATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Registers a new supply chain actor with a specified role.
     *
     * @dev Registration flow:
     *   1. Validates caller is the owner.
     *   2. Rejects zero address and None role assignments.
     *   3. Prevents duplicate registration of the same wallet.
     *   4. Stores Actor struct and appends wallet to actorList for enumeration.
     *   5. Emits ActorRegistered event.
     *
     * Safeguards:
     *   - Zero address cannot be registered (no anonymous actors).
     *   - Role.None cannot be assigned (reserved for unregistered state).
     *   - Duplicate wallet registration reverts (one identity per address).
     *
     * @param wallet    The actor's Ethereum wallet address.
     * @param name      The actor's business or legal name.
     * @param location  Physical location or regulatory jurisdiction.
     * @param role      The supply chain role to assign (must not be None).
     */
    function registerActor(
        address wallet,
        string calldata name,
        string calldata location,
        Role role
    )
        external
        onlyOwner
    {
        require(wallet != address(0),          "ActorRegistry: cannot register zero address");
        require(role != Role.None,             "ActorRegistry: cannot assign None role");
        require(actors[wallet].role == Role.None, "ActorRegistry: actor is already registered");
        require(bytes(name).length > 0,        "ActorRegistry: actor name cannot be empty");

        actors[wallet] = Actor({
            wallet:       wallet,
            name:         name,
            location:     location,
            role:         role,
            isActive:     true,
            registeredAt: block.timestamp
        });

        actorList.push(wallet);
        emit ActorRegistered(wallet, name, role, location);
    }

    /**
     * @notice Updates the role assigned to an existing registered actor.
     *
     * @dev Useful when an actor's function in the supply chain changes
     *      (e.g., a supplier expands to become a distributor).
     *      The actor's profile and history are preserved; only the role changes.
     *
     * Safeguards:
     *   - Actor must already be registered.
     *   - New role cannot be None (would effectively "unregister" them; use setActorStatus instead).
     *
     * @param wallet  The actor's wallet address.
     * @param newRole The new role to assign.
     */
    function updateActorRole(address wallet, Role newRole)
        external
        onlyOwner
        actorRegistered(wallet)
    {
        require(newRole != Role.None, "ActorRegistry: cannot assign None role");
        Role oldRole = actors[wallet].role;
        require(oldRole != newRole,   "ActorRegistry: actor already has this role");

        actors[wallet].role = newRole;
        emit ActorRoleUpdated(wallet, oldRole, newRole);
    }

    /**
     * @notice Activates or deactivates an actor without removing their record.
     *
     * @dev Deactivated actors retain their profile and history but are treated as
     *      unauthorized by isAuthorized(). This "soft delete" preserves the audit trail
     *      while preventing further participation in supply chain operations.
     *
     * Safeguard: cannot deactivate the contract owner (would lock admin functions).
     *
     * @param wallet    The actor's wallet address.
     * @param isActive  True to reactivate, false to deactivate.
     */
    function setActorStatus(address wallet, bool isActive)
        external
        onlyOwner
        actorRegistered(wallet)
    {
        require(wallet != owner || isActive, "ActorRegistry: cannot deactivate the contract owner");
        require(actors[wallet].isActive != isActive, "ActorRegistry: status already set to this value");

        actors[wallet].isActive = isActive;
        emit ActorStatusChanged(wallet, isActive);
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 7 — VIEW / QUERY FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Checks whether an address is a registered and currently active actor.
     * @dev The SupplyChain and PaymentEscrow contracts call this to validate
     *      participants before permitting registration or transfer operations.
     * @param wallet The Ethereum address to check.
     * @return True if the actor is registered (role != None) AND isActive == true.
     */
    function isAuthorized(address wallet) external view returns (bool) {
        Actor storage a = actors[wallet];
        return a.role != Role.None && a.isActive;
    }

    /**
     * @notice Returns the role currently assigned to an actor.
     * @param wallet The actor's wallet address.
     * @return The actor's Role enum value (Role.None if unregistered).
     */
    function getActorRole(address wallet) external view returns (Role) {
        return actors[wallet].role;
    }

    /**
     * @notice Returns the full profile of a registered actor.
     * @param wallet The actor's wallet address.
     * @return Actor struct: name, location, role, isActive, registeredAt.
     */
    function getActor(address wallet)
        external
        view
        actorRegistered(wallet)
        returns (Actor memory)
    {
        return actors[wallet];
    }

    /**
     * @notice Returns the total number of actors ever registered (including deactivated ones).
     * @return Length of actorList array.
     */
    function totalActors() external view returns (uint256) {
        return actorList.length;
    }
}
