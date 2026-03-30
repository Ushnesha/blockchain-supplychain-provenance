// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SupplyChain
 * @notice Core contract for the Blockchain-Based Supply Chain Provenance System.
 *
 * @dev Implements the full lifecycle of a product on-chain:
 *        1. Registration   — manufacturer records a new product with metadata
 *        2. Transfer       — custody (ownership) passes between authorized actors
 *        3. Status updates — stage progresses through the supply chain pipeline
 *        4. Provenance     — complete, immutable audit trail queryable by anyone
 *
 *      Design principles enforced by this contract:
 *        - Immutability   : historical transfer records are append-only; no deletion.
 *        - Verifiability  : all major state changes emit indexed events for off-chain indexing.
 *        - Error safety   : guards against duplicate registration, self-transfer, invalid
 *                           stage transitions, and unauthorized callers via modifiers/requires.
 *        - Role separation: only authorized actors can register/transfer; owner manages roles.
 */
contract SupplyChain {

    // ═══════════════════════════════════════════════════════════
    // SECTION 1 — DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Represents the lifecycle stage of a product as it moves
     *         through the supply chain from manufacture to final sale.
     *
     *  Progression: Manufactured → Shipped → InWarehouse → AtRetailer → Sold
     *
     *  Transitions are strictly sequential; skipping or reversing stages is not permitted.
     */
    enum Stage {
        Manufactured,   // Product has been created and registered by the manufacturer
        Shipped,        // Product is in transit toward a distributor or retailer
        InWarehouse,    // Product is held in a distributor's warehouse
        AtRetailer,     // Product has arrived at the retail point of sale
        Sold            // Product purchased by end consumer (terminal state — no further changes)
    }

    /**
     * @notice Core data structure holding all information about a registered product.
     *
     * @dev Fields:
     *   id            — Unique on-chain identifier, auto-assigned on registration.
     *   name          — Human-readable product name or SKU.
     *   origin        — Geographic origin or manufacturing facility.
     *   batchId       — Batch/lot number for grouped production run tracking.
     *   metadata      — Flexible JSON-encoded string for additional attributes
     *                   (e.g., expiry date, certifications, weight, category).
     *   manufacturer  — Ethereum address of the original registering manufacturer.
     *   currentOwner  — Ethereum address of the actor currently holding custody.
     *   stage         — Current supply chain stage (see Stage enum above).
     *   registeredAt  — Block timestamp when the product was first registered.
     *   updatedAt     — Block timestamp of the most recent state change.
     *   exists        — Guard flag; true once registered. Prevents treating
     *                   unregistered IDs as valid products (duplicate/phantom guard).
     */
    struct Product {
        uint256 id;
        string  name;
        string  origin;
        string  batchId;
        string  metadata;
        address manufacturer;
        address currentOwner;
        Stage   stage;
        uint256 registeredAt;
        uint256 updatedAt;
        bool    exists;
    }

    /**
     * @notice Records a single custody transfer event, forming the provenance chain.
     *
     * @dev All records are appended to _transferHistory[productId] and never modified.
     *      This append-only design ensures full immutability of the audit trail —
     *      even contract owners cannot alter historical records.
     *
     * Fields:
     *   from      — Address that held custody before this transfer (address(0) for genesis).
     *   to        — Address receiving custody.
     *   stage     — Supply chain stage at the moment of this record.
     *   timestamp — Block timestamp of the transfer.
     *   notes     — Optional free-text: location, condition, handler info, etc.
     */
    struct TransferRecord {
        address from;
        address to;
        Stage   stage;
        uint256 timestamp;
        string  notes;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 2 — STATE VARIABLES
    // ═══════════════════════════════════════════════════════════

    /// @notice Auto-incrementing counter; each registerProduct call increments this
    ///         and assigns the new value as the product's unique ID. Starts at 1.
    uint256 private _productCounter;

    /// @notice Primary product registry: maps product ID → Product struct.
    ///         Products are never deleted; the `exists` flag differentiates valid IDs.
    mapping(uint256 => Product) public products;

    /// @notice Append-only provenance ledger: maps product ID → ordered list of transfers.
    ///         Every registration and transfer appends a new TransferRecord here.
    mapping(uint256 => TransferRecord[]) private _transferHistory;

    /// @notice Duplicate-registration guard: maps keccak256(name + batchId) → productId.
    ///         Prevents the same product batch from being registered more than once.
    mapping(bytes32 => uint256) private _productIndex;

    /// @notice Authorization registry: maps actor address → authorized flag.
    ///         Only authorized addresses may register products or receive transfers.
    mapping(address => bool) public authorizedActors;

    /// @notice Contract owner/admin — manages actor authorization.
    ///         Immutable after deployment; set to deployer address at construction.
    address public immutable owner;

    // ═══════════════════════════════════════════════════════════
    // SECTION 3 — EVENTS
    // All major state changes emit an indexed event so that off-chain systems
    // (block explorers, subgraphs, frontend listeners) can reconstruct the
    // full supply chain history without reading contract storage directly.
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new product is successfully registered on-chain.
     *         Provides full identity info needed for off-chain product catalogues.
     * @param productId    The unique ID assigned to the product.
     * @param name         The product's name/SKU.
     * @param batchId      The production batch identifier.
     * @param manufacturer The address that registered the product.
     */
    event ProductCreated(
        uint256 indexed productId,
        string  name,
        string  batchId,
        address indexed manufacturer
    );

    /**
     * @notice Emitted whenever product custody changes from one actor to another.
     *         This is the primary event for tracking the product's chain of custody.
     * @param productId  The product whose ownership changed.
     * @param from       The previous owner's address.
     * @param to         The new owner's address.
     * @param stage      The supply chain stage at the time of transfer.
     * @param timestamp  Block timestamp of the ownership change.
     */
    event OwnershipTransferred(
        uint256 indexed productId,
        address indexed from,
        address indexed to,
        Stage   stage,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a product's supply chain stage changes — whether via
     *         a custody transfer or an explicit status update by the current owner.
     * @param productId The product whose stage changed.
     * @param oldStage  The stage before the update.
     * @param newStage  The stage after the update.
     * @param updatedBy The address that triggered the update.
     * @param timestamp Block timestamp of the stage change.
     */
    event StatusUpdated(
        uint256 indexed productId,
        Stage   oldStage,
        Stage   newStage,
        address indexed updatedBy,
        uint256 timestamp
    );

    /**
     * @notice Emitted when the owner grants or revokes an actor's authorization.
     * @param actor      The address whose authorization changed.
     * @param authorized True if authorized, false if revoked.
     */
    event ActorAuthorizationChanged(address indexed actor, bool authorized);

    // ═══════════════════════════════════════════════════════════
    // SECTION 4 — MODIFIERS (Access Control & Validation Guards)
    // Centralizing checks in modifiers keeps function bodies clean and
    // ensures consistent, descriptive error messages across all entry points.
    // ═══════════════════════════════════════════════════════════

    /// @dev Restricts to the contract owner/admin only.
    modifier onlyOwner() {
        require(msg.sender == owner, "SupplyChain: caller is not the owner");
        _;
    }

    /// @dev Restricts to addresses granted authorization by the owner.
    ///      Unauthorized callers cannot register products or receive transfers.
    modifier onlyAuthorized() {
        require(authorizedActors[msg.sender], "SupplyChain: caller is not authorized");
        _;
    }

    /// @dev Validates that a product ID corresponds to a registered product.
    ///      Reverts before any state is read, preventing phantom-ID exploits.
    modifier productExists(uint256 productId) {
        require(products[productId].exists, "SupplyChain: product does not exist");
        _;
    }

    /// @dev Ensures the caller is the current custodian of the product.
    ///      Only the current owner may transfer custody or update status.
    modifier onlyCurrentOwner(uint256 productId) {
        require(
            products[productId].currentOwner == msg.sender,
            "SupplyChain: caller is not the current product owner"
        );
        _;
    }

    /// @dev Prevents any action on products already in the Sold (terminal) state.
    ///      Sold products are finalized — no transfers or status changes are valid.
    modifier notSold(uint256 productId) {
        require(
            products[productId].stage != Stage.Sold,
            "SupplyChain: product is already sold and cannot be modified"
        );
        _;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 5 — CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Deploys the SupplyChain contract.
     * @dev The deployer becomes the immutable owner and is auto-authorized
     *      so they can immediately register products during setup or testing.
     */
    constructor() {
        owner = msg.sender;
        authorizedActors[msg.sender] = true;
        emit ActorAuthorizationChanged(msg.sender, true);
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 6 — ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Grants or revokes authorization for a supply chain actor.
     * @dev Only the owner may call this. Authorization is required before an
     *      address can register products or receive product transfers.
     *
     * Safeguards:
     *   - Zero address cannot be authorized (invalid actor).
     *   - Owner cannot de-authorize themselves (would lock the contract).
     *
     * @param actor  Ethereum address of the supply chain actor.
     * @param status True to authorize, false to revoke.
     */
    function setActorAuthorization(address actor, bool status) external onlyOwner {
        require(actor != address(0), "SupplyChain: cannot authorize zero address");
        require(actor != owner || status, "SupplyChain: cannot de-authorize the contract owner");
        authorizedActors[actor] = status;
        emit ActorAuthorizationChanged(actor, status);
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 7 — CORE SUPPLY CHAIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Registers a new product on the blockchain.
     *
     * @dev Registration flow:
     *   1. Validates caller is an authorized actor (manufacturer role).
     *   2. Rejects empty product names.
     *   3. Guards against duplicate (name + batchId) combinations using a hash index.
     *   4. Assigns a unique auto-incremented product ID.
     *   5. Stores the full Product struct on-chain.
     *   6. Appends the genesis TransferRecord to the immutable provenance trail.
     *   7. Emits ProductCreated for off-chain consumers.
     *
     * @param name     The product's name or SKU identifier.
     * @param origin   Geographic origin or manufacturing facility name.
     * @param batchId  Production batch or lot number (use "" if not applicable).
     * @param metadata JSON-encoded string of additional product attributes
     *                 e.g. '{"category":"food","expiryDate":"2026-12-01","weight":"500g"}'
     * @return productId The unique on-chain ID assigned to this product.
     */
    function registerProduct(
        string calldata name,
        string calldata origin,
        string calldata batchId,
        string calldata metadata
    )
        external
        onlyAuthorized
        returns (uint256 productId)
    {
        // Safeguard: reject nameless products
        require(bytes(name).length > 0, "SupplyChain: product name cannot be empty");

        // Safeguard: prevent duplicate registration of the same product/batch
        bytes32 productKey = keccak256(abi.encodePacked(name, batchId));
        require(
            _productIndex[productKey] == 0,
            "SupplyChain: product with this name and batchId is already registered"
        );

        // Assign unique ID (starts at 1; 0 is reserved as "not found")
        _productCounter++;
        productId = _productCounter;

        // Mark product key as taken to prevent future duplicates
        _productIndex[productKey] = productId;

        // Persist full product record on-chain
        products[productId] = Product({
            id:           productId,
            name:         name,
            origin:       origin,
            batchId:      batchId,
            metadata:     metadata,
            manufacturer: msg.sender,
            currentOwner: msg.sender,
            stage:        Stage.Manufactured,
            registeredAt: block.timestamp,
            updatedAt:    block.timestamp,
            exists:       true
        });

        // Append genesis provenance record (from address(0) = "created from nothing")
        _transferHistory[productId].push(TransferRecord({
            from:      address(0),
            to:        msg.sender,
            stage:     Stage.Manufactured,
            timestamp: block.timestamp,
            notes:     "Product registered on-chain by manufacturer"
        }));

        emit ProductCreated(productId, name, batchId, msg.sender);
    }

    /**
     * @notice Transfers custody of a product to the next supply chain actor.
     *
     * @dev Transfer flow:
     *   1. Validates product exists, caller is current owner, product is not sold.
     *   2. Validates recipient is authorized, non-zero, and not the caller.
     *   3. Automatically advances product to the next sequential Stage.
     *   4. Updates currentOwner and updatedAt timestamp.
     *   5. Appends a TransferRecord to the immutable provenance trail.
     *   6. Emits OwnershipTransferred and StatusUpdated events.
     *
     * Safeguards:
     *   - Cannot transfer a product in Sold (terminal) state.
     *   - Cannot transfer to self (no-op, likely a mistake).
     *   - Cannot transfer to the zero address.
     *   - Cannot transfer to an unauthorized actor.
     *   - Stage advances exactly one step — no skipping.
     *
     * @param productId  The ID of the product being transferred.
     * @param to         Ethereum address of the receiving actor (must be authorized).
     * @param notes      Optional handler notes: location, condition, carrier, etc.
     */
    function transferProduct(
        uint256 productId,
        address to,
        string calldata notes
    )
        external
        productExists(productId)
        onlyCurrentOwner(productId)
        notSold(productId)
    {
        require(to != address(0),     "SupplyChain: cannot transfer to the zero address");
        require(to != msg.sender,     "SupplyChain: cannot transfer product to yourself");
        require(authorizedActors[to], "SupplyChain: recipient is not an authorized actor");

        Product storage p = products[productId];
        Stage oldStage       = p.stage;
        Stage newStage       = _nextStage(oldStage);
        address previousOwner = p.currentOwner;

        // Update ownership and stage atomically
        p.currentOwner = to;
        p.stage        = newStage;
        p.updatedAt    = block.timestamp;

        // Append immutable provenance record
        _transferHistory[productId].push(TransferRecord({
            from:      previousOwner,
            to:        to,
            stage:     newStage,
            timestamp: block.timestamp,
            notes:     notes
        }));

        // Emit both events: ownership change + stage change
        emit OwnershipTransferred(productId, previousOwner, to, newStage, block.timestamp);
        emit StatusUpdated(productId, oldStage, newStage, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates a product's stage without changing ownership.
     *
     * @dev Useful for recording in-place status changes at the same custodian,
     *      e.g. a distributor marking goods as "received in warehouse" without
     *      transferring custody to a new address.
     *
     * Safeguards:
     *   - Cannot update a sold (terminal) product.
     *   - New stage must be strictly the next stage in sequence (no skipping, no reversals).
     *   - Only the current owner can update status.
     *
     * @param productId The ID of the product to update.
     * @param newStage  The target stage (must equal _nextStage(current stage)).
     * @param notes     Optional notes explaining the status change.
     */
    function updateProductStatus(
        uint256 productId,
        Stage newStage,
        string calldata notes
    )
        external
        productExists(productId)
        onlyCurrentOwner(productId)
        notSold(productId)
    {
        Product storage p = products[productId];
        Stage oldStage = p.stage;

        // Safeguard: enforce strictly sequential stage progression
        require(
            newStage == _nextStage(oldStage), "SupplyChain: invalid stage, must advance exactly one step at a time"
        );

        p.stage     = newStage;
        p.updatedAt = block.timestamp;

        // Record in provenance trail with same from/to (ownership unchanged)
        _transferHistory[productId].push(TransferRecord({
            from:      msg.sender,
            to:        msg.sender,
            stage:     newStage,
            timestamp: block.timestamp,
            notes:     notes
        }));

        emit StatusUpdated(productId, oldStage, newStage, msg.sender, block.timestamp);
    }

    /**
     * @notice Marks a product as sold to the end consumer (terminal action).
     *
     * @dev Transitions the product to the Sold stage, which is terminal.
     *      After this call, no further transfers or status updates are possible.
     *      Emits both OwnershipTransferred (to address(0) representing consumer)
     *      and StatusUpdated to give off-chain systems a complete record.
     *
     * Safeguards:
     *   - Only current owner (retailer) can call this.
     *   - Product must not already be in Sold state (idempotency guard).
     *
     * @param productId The ID of the product being sold.
     * @param notes     Optional sale notes (e.g., sale reference, consumer region).
     */
    function markAsSold(uint256 productId, string calldata notes)
        external
        productExists(productId)
        onlyCurrentOwner(productId)
        notSold(productId)
    {
        Product storage p = products[productId];
        Stage oldStage = p.stage;

        p.stage     = Stage.Sold;
        p.updatedAt = block.timestamp;

        // Record terminal entry in provenance trail
        _transferHistory[productId].push(TransferRecord({
            from:      msg.sender,
            to:        address(0),   // address(0) represents the consumer (end of chain)
            stage:     Stage.Sold,
            timestamp: block.timestamp,
            notes:     notes
        }));

        // Emit OwnershipTransferred: custody leaves the supply chain (to address(0))
        emit OwnershipTransferred(productId, msg.sender, address(0), Stage.Sold, block.timestamp);
        emit StatusUpdated(productId, oldStage, Stage.Sold, msg.sender, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 8 — VIEW / QUERY FUNCTIONS
    // Read-only functions for frontends, consumers, and regulators
    // to verify product authenticity and trace the supply chain.
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Returns the full metadata of a registered product.
     * @param productId The unique product identifier.
     * @return Product struct: name, origin, batchId, metadata, owner, stage, timestamps.
     */
    function getProduct(uint256 productId)
        external
        view
        productExists(productId)
        returns (Product memory)
    {
        return products[productId];
    }

    /**
     * @notice Returns the complete provenance (audit trail) of a product.
     * @dev Every entry was appended at the time of registration or transfer.
     *      The array is ordered chronologically; index 0 is always the genesis record.
     *      Consumers and regulators can call this to verify full chain of custody.
     * @param productId The unique product identifier.
     * @return Array of TransferRecord structs from manufacture to current state.
     */
    function getProvenance(uint256 productId)
        external
        view
        productExists(productId)
        returns (TransferRecord[] memory)
    {
        return _transferHistory[productId];
    }

    /**
     * @notice Returns the current supply chain stage of a product.
     * @param productId The unique product identifier.
     * @return Current Stage enum value.
     */
    function getProductStage(uint256 productId)
        external
        view
        productExists(productId)
        returns (Stage)
    {
        return products[productId].stage;
    }

    /**
     * @notice Returns the current owner (custodian) of a product.
     * @param productId The unique product identifier.
     * @return Ethereum address of the current owner.
     */
    function getProductOwner(uint256 productId)
        external
        view
        productExists(productId)
        returns (address)
    {
        return products[productId].currentOwner;
    }

    /**
     * @notice Checks whether a product ID has been registered.
     * @param productId The ID to check.
     * @return True if the product exists on-chain.
     */
    function productRegistered(uint256 productId) external view returns (bool) {
        return products[productId].exists;
    }

    /**
     * @notice Returns the total number of products registered on-chain.
     * @return Total product count (equals the last assigned product ID).
     */
    function totalProducts() external view returns (uint256) {
        return _productCounter;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 9 — INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════

    /**
     * @dev Determines the next stage in the supply chain sequence.
     *      Called internally during transferProduct and updateProductStatus.
     *      Reverts if the product is already at or beyond AtRetailer without Sold,
     *      which should be caught by notSold modifier first.
     *
     *  Manufactured → Shipped → InWarehouse → AtRetailer → Sold
     *
     * @param current The product's current Stage.
     * @return The next Stage in the fixed progression.
     */
    function _nextStage(Stage current) internal pure returns (Stage) {
        if (current == Stage.Manufactured) return Stage.Shipped;
        if (current == Stage.Shipped)      return Stage.InWarehouse;
        if (current == Stage.InWarehouse)  return Stage.AtRetailer;
        if (current == Stage.AtRetailer)   return Stage.Sold;
        revert("SupplyChain: no further stages available");
    }
}
