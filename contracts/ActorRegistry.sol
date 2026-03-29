// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ActorRegistry
 * @notice Manages identity and role registration for all supply chain participants.
 *         Actors include manufacturers, suppliers, distributors, retailers, and regulators.
 *
 * @dev The registry acts as the source of truth for authorized participants.
 *      Other contracts (e.g., SupplyChain, PaymentEscrow) can query this contract
 *      to verify an actor's role and authorization status before permitting actions.
 */
contract ActorRegistry {

    // ─────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────

    /**
     * @notice Defines the possible roles a supply chain actor can hold.
     */
    enum Role {
        None,           // Default — unregistered address
        Manufacturer,   // Produces and registers goods
        Supplier,       // Sources raw materials or intermediate goods
        Distributor,    // Moves goods between stages/warehouses
        Retailer,       // Sells goods directly to consumers
        Regulator       // Read-only auditing and compliance verification
    }

    // ─────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────

    /**
     * @notice Stores profile and authorization data for a registered actor.
     */
    struct Actor {
        address wallet;         // Actor's Ethereum wallet address
        string  name;           // Legal or business name
        string  location;       // Physical location or jurisdiction
        Role    role;           // Assigned supply chain role
        bool    isActive;       // Whether the actor is currently authorized
        uint256 registeredAt;   // Block timestamp of registration
    }

    // ─────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────

    /// @notice Contract admin — manages actor registrations and role assignments.
    address public owner;

    /// @notice Mapping from actor wallet address to their Actor profile.
    mapping(address => Actor) public actors;

    /// @notice List of all registered actor addresses (for enumeration).
    address[] public actorList;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    /// @notice Emitted when a new actor is registered on-chain.
    event ActorRegistered(address indexed wallet, string name, Role role);

    /// @notice Emitted when an actor's role is updated by the owner.
    event ActorRoleUpdated(address indexed wallet, Role oldRole, Role newRole);

    /// @notice Emitted when an actor's active status is toggled.
    event ActorStatusChanged(address indexed wallet, bool isActive);

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "ActorRegistry: not owner");
        _;
    }

    modifier actorRegistered(address wallet) {
        require(actors[wallet].role != Role.None, "ActorRegistry: actor not registered");
        _;
    }

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /**
     * @notice Deploys the ActorRegistry and sets the deployer as the admin owner.
     */
    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────
    // Registration Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Registers a new supply chain actor with a specified role.
     * @dev Only the contract owner (admin) can register new actors.
     *      Prevents duplicate registration of the same wallet address.
     * @param wallet    The Ethereum address of the actor.
     * @param name      The actor's business/legal name.
     * @param location  The actor's geographic location or jurisdiction.
     * @param role      The supply chain role being assigned.
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
        require(wallet != address(0), "ActorRegistry: invalid address");
        require(role != Role.None, "ActorRegistry: cannot assign None role");
        require(actors[wallet].role == Role.None, "ActorRegistry: already registered");

        actors[wallet] = Actor({
            wallet:       wallet,
            name:         name,
            location:     location,
            role:         role,
            isActive:     true,
            registeredAt: block.timestamp
        });

        actorList.push(wallet);
        emit ActorRegistered(wallet, name, role);
    }

    /**
     * @notice Updates the role assigned to an existing registered actor.
     * @dev Useful when an actor's supply chain function changes (e.g., supplier → distributor).
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
        actors[wallet].role = newRole;
        emit ActorRoleUpdated(wallet, oldRole, newRole);
    }

    /**
     * @notice Activates or deactivates an actor's authorization status.
     * @dev Deactivated actors retain their profile but cannot participate in chain actions.
     * @param wallet    The actor's wallet address.
     * @param isActive  True to activate, false to deactivate.
     */
    function setActorStatus(address wallet, bool isActive)
        external
        onlyOwner
        actorRegistered(wallet)
    {
        actors[wallet].isActive = isActive;
        emit ActorStatusChanged(wallet, isActive);
    }

    // ─────────────────────────────────────────────
    // View / Query Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Checks whether an address is a registered and active supply chain actor.
     * @param wallet The Ethereum address to check.
     * @return True if the actor is registered and currently active.
     */
    function isAuthorized(address wallet) external view returns (bool) {
        Actor storage a = actors[wallet];
        return a.role != Role.None && a.isActive;
    }

    /**
     * @notice Returns the role assigned to a registered actor.
     * @param wallet The actor's wallet address.
     * @return The actor's Role enum value.
     */
    function getActorRole(address wallet) external view returns (Role) {
        return actors[wallet].role;
    }

    /**
     * @notice Returns the full profile of a registered actor.
     * @param wallet The actor's wallet address.
     * @return Actor struct containing name, location, role, and status.
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
     * @notice Returns the total count of registered actors.
     */
    function totalActors() external view returns (uint256) {
        return actorList.length;
    }
}
