// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SupplyChain
 * @notice Core contract for the Blockchain-Based Supply Chain Provenance System.
 *         Manages product registration, ownership transfers across supply chain
 *         stages, and provenance verification for end consumers.
 *
 * @dev Each product is assigned a unique ID. As the product moves through the
 *      supply chain (manufacturer → supplier → retailer → consumer), the
 *      contract records each transfer immutably on-chain.
 */
contract SupplyChain {

    // ─────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────

    /**
     * @notice Represents the current stage of a product in the supply chain.
     */
    enum Stage {
        Manufactured,   // Product has been created by the manufacturer
        Shipped,        // Product is in transit to a supplier/retailer
        InWarehouse,    // Product is stored at a warehouse/distributor
        AtRetailer,     // Product has arrived at the retail location
        Sold            // Product has been purchased by the end consumer
    }

    // ─────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────

    /**
     * @notice Stores all metadata and current state for a registered product.
     */
    struct Product {
        uint256 id;             // Unique product identifier (auto-incremented)
        string  name;           // Human-readable product name
        string  origin;         // Place/country of manufacture
        address manufacturer;   // Ethereum address of the manufacturer
        address currentOwner;   // Address of the current supply chain actor
        Stage   stage;          // Current stage in the supply chain
        uint256 timestamp;      // Block timestamp of the last state change
        bool    exists;         // Guard flag to check product registration
    }

    /**
     * @notice Records a single custody transfer event for provenance history.
     */
    struct TransferRecord {
        address from;       // Address transferring custody
        address to;         // Address receiving custody
        Stage   stage;      // Supply chain stage at the time of transfer
        uint256 timestamp;  // Block timestamp of the transfer
        string  notes;      // Optional notes (e.g., location, condition)
    }

    // ─────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────

    /// @notice Auto-incrementing counter used to assign unique product IDs.
    uint256 private _productCounter;

    /// @notice Mapping from product ID to its Product metadata struct.
    mapping(uint256 => Product) public products;

    /// @notice Mapping from product ID to its full transfer/provenance history.
    mapping(uint256 => TransferRecord[]) public transferHistory;

    /// @notice Mapping of authorized supply chain actors (role-based access).
    mapping(address => bool) public authorizedActors;

    /// @notice Contract owner (typically the deploying organization/admin).
    address public owner;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    /// @notice Emitted when a new product is registered on-chain.
    event ProductRegistered(uint256 indexed productId, string name, address indexed manufacturer);

    /// @notice Emitted when a product's custody is transferred between actors.
    event ProductTransferred(uint256 indexed productId, address indexed from, address indexed to, Stage stage);

    /// @notice Emitted when a product's supply chain stage is updated.
    event StageUpdated(uint256 indexed productId, Stage newStage, uint256 timestamp);

    /// @notice Emitted when an actor is granted or revoked authorization.
    event ActorAuthorizationChanged(address indexed actor, bool authorized);

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    /// @dev Restricts function execution to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "SupplyChain: caller is not the owner");
        _;
    }

    /// @dev Restricts function execution to authorized supply chain actors.
    modifier onlyAuthorized() {
        require(authorizedActors[msg.sender], "SupplyChain: caller is not authorized");
        _;
    }

    /// @dev Ensures the given product ID references a registered product.
    modifier productExists(uint256 productId) {
        require(products[productId].exists, "SupplyChain: product does not exist");
        _;
    }

    /// @dev Ensures only the current owner of a product can act on it.
    modifier onlyCurrentOwner(uint256 productId) {
        require(products[productId].currentOwner == msg.sender, "SupplyChain: caller is not the current owner");
        _;
    }

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /**
     * @notice Deploys the SupplyChain contract.
     * @dev Sets the deployer as the owner and authorizes them by default.
     */
    constructor() {
        owner = msg.sender;
        authorizedActors[msg.sender] = true;
    }

    // ─────────────────────────────────────────────
    // Admin Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Grants or revokes authorization for a supply chain actor.
     * @param actor  Ethereum address of the actor.
     * @param status True to authorize, false to revoke.
     */
    function setActorAuthorization(address actor, bool status) external onlyOwner {
        authorizedActors[actor] = status;
        emit ActorAuthorizationChanged(actor, status);
    }

    // ─────────────────────────────────────────────
    // Core Supply Chain Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Registers a new product on the blockchain.
     * @dev Only authorized actors (manufacturers) may call this.
     *      Assigns a unique ID and sets the initial stage to Manufactured.
     * @param name    The product's name or SKU.
     * @param origin  The geographic origin or manufacturing location.
     * @return productId The unique ID assigned to the newly registered product.
     */
    function registerProduct(string calldata name, string calldata origin)
        external
        onlyAuthorized
        returns (uint256 productId)
    {
        _productCounter++;
        productId = _productCounter;

        products[productId] = Product({
            id:           productId,
            name:         name,
            origin:       origin,
            manufacturer: msg.sender,
            currentOwner: msg.sender,
            stage:        Stage.Manufactured,
            timestamp:    block.timestamp,
            exists:       true
        });

        transferHistory[productId].push(TransferRecord({
            from:      address(0),
            to:        msg.sender,
            stage:     Stage.Manufactured,
            timestamp: block.timestamp,
            notes:     "Product registered"
        }));

        emit ProductRegistered(productId, name, msg.sender);
    }

    /**
     * @notice Transfers custody of a product to the next supply chain actor.
     * @dev Caller must be the current owner. Both caller and recipient must be authorized.
     *      Advances the product's stage automatically.
     * @param productId  The ID of the product being transferred.
     * @param to         The Ethereum address of the receiving actor.
     * @param notes      Optional notes to record with the transfer (e.g., location, condition).
     */
    function transferProduct(uint256 productId, address to, string calldata notes)
        external
        productExists(productId)
        onlyCurrentOwner(productId)
    {
        require(authorizedActors[to], "SupplyChain: recipient is not authorized");
        require(to != msg.sender, "SupplyChain: cannot transfer to self");

        Product storage p = products[productId];
        Stage nextStage = _nextStage(p.stage);

        address previousOwner = p.currentOwner;
        p.currentOwner = to;
        p.stage = nextStage;
        p.timestamp = block.timestamp;

        transferHistory[productId].push(TransferRecord({
            from:      previousOwner,
            to:        to,
            stage:     nextStage,
            timestamp: block.timestamp,
            notes:     notes
        }));

        emit ProductTransferred(productId, previousOwner, to, nextStage);
        emit StageUpdated(productId, nextStage, block.timestamp);
    }

    /**
     * @notice Marks a product as sold to the end consumer.
     * @dev Only the current owner (e.g., retailer) can mark a product as sold.
     * @param productId The ID of the product being sold.
     * @param notes     Optional notes (e.g., consumer address, sale reference).
     */
    function markAsSold(uint256 productId, string calldata notes)
        external
        productExists(productId)
        onlyCurrentOwner(productId)
    {
        Product storage p = products[productId];
        require(p.stage != Stage.Sold, "SupplyChain: product already sold");

        p.stage = Stage.Sold;
        p.timestamp = block.timestamp;

        transferHistory[productId].push(TransferRecord({
            from:      msg.sender,
            to:        address(0),
            stage:     Stage.Sold,
            timestamp: block.timestamp,
            notes:     notes
        }));

        emit StageUpdated(productId, Stage.Sold, block.timestamp);
    }

    // ─────────────────────────────────────────────
    // View / Query Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Returns the full metadata of a registered product.
     * @param productId The unique product identifier.
     * @return Product struct containing name, origin, owner, stage, and timestamps.
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
     * @notice Returns the complete provenance (transfer history) of a product.
     * @dev Provides a full audit trail — usable by consumers to verify authenticity.
     * @param productId The unique product identifier.
     * @return Array of TransferRecord structs from manufacture to current state.
     */
    function getProvenance(uint256 productId)
        external
        view
        productExists(productId)
        returns (TransferRecord[] memory)
    {
        return transferHistory[productId];
    }

    /**
     * @notice Returns the current stage of a product in the supply chain.
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
     * @notice Returns the total number of products registered on-chain.
     * @return Total count of registered products.
     */
    function totalProducts() external view returns (uint256) {
        return _productCounter;
    }

    // ─────────────────────────────────────────────
    // Internal Helpers
    // ─────────────────────────────────────────────

    /**
     * @dev Determines the next logical stage in the supply chain sequence.
     *      Reverts if the product has already reached a terminal stage (Sold).
     * @param current The product's current Stage.
     * @return The next Stage in the progression.
     */
    function _nextStage(Stage current) internal pure returns (Stage) {
        if (current == Stage.Manufactured)  return Stage.Shipped;
        if (current == Stage.Shipped)       return Stage.InWarehouse;
        if (current == Stage.InWarehouse)   return Stage.AtRetailer;
        if (current == Stage.AtRetailer)    return Stage.Sold;
        revert("SupplyChain: no further stages");
    }
}
