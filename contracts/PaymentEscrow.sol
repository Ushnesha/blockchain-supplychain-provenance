// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PaymentEscrow
 * @notice Handles automated escrow payments between supply chain actors.
 *         Funds are locked when a shipment is initiated and released
 *         automatically upon confirmed delivery or stage advancement.
 *
 * @dev Integrates with the SupplyChain contract to trigger payments on
 *      successful product transfers. Supports dispute resolution by the
 *      contract owner/admin.
 */
contract PaymentEscrow {

    // ─────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────

    /**
     * @notice Lifecycle states for an escrow payment agreement.
     */
    enum EscrowStatus {
        Pending,    // Funds deposited, awaiting delivery confirmation
        Released,   // Funds released to the seller/recipient upon delivery
        Refunded,   // Funds returned to the buyer (e.g., dispute resolution)
        Disputed    // Payment flagged for admin arbitration
    }

    // ─────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────

    /**
     * @notice Represents a single escrow agreement tied to a product transfer.
     */
    struct Escrow {
        uint256 productId;      // ID of the product this payment is for
        address payable buyer;  // Party depositing funds (e.g., retailer paying supplier)
        address payable seller; // Party to receive funds upon delivery confirmation
        uint256 amount;         // Amount locked in escrow (in wei)
        EscrowStatus status;    // Current status of the escrow
        uint256 createdAt;      // Timestamp when the escrow was created
        uint256 releasedAt;     // Timestamp when funds were released (0 if not yet)
    }

    // ─────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────

    /// @notice Auto-incrementing escrow ID counter.
    uint256 private _escrowCounter;

    /// @notice Contract admin/owner responsible for dispute arbitration.
    address public owner;

    /// @notice Mapping from escrow ID to its Escrow struct.
    mapping(uint256 => Escrow) public escrows;

    /// @notice Mapping from product ID to its active escrow ID (0 if none).
    mapping(uint256 => uint256) public productEscrow;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    /// @notice Emitted when a new escrow agreement is created and funded.
    event EscrowCreated(uint256 indexed escrowId, uint256 indexed productId, address buyer, address seller, uint256 amount);

    /// @notice Emitted when funds are released to the seller upon delivery.
    event FundsReleased(uint256 indexed escrowId, address indexed seller, uint256 amount);

    /// @notice Emitted when funds are refunded to the buyer (dispute or cancellation).
    event FundsRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);

    /// @notice Emitted when an escrow is marked as disputed by the buyer.
    event EscrowDisputed(uint256 indexed escrowId, address indexed raisedBy);

    // ─────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "PaymentEscrow: not owner");
        _;
    }

    modifier escrowExists(uint256 escrowId) {
        require(escrows[escrowId].amount > 0, "PaymentEscrow: escrow does not exist");
        _;
    }

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    /**
     * @notice Deploys the PaymentEscrow contract.
     */
    constructor() {
        owner = msg.sender;
    }

    // ─────────────────────────────────────────────
    // Core Escrow Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Creates and funds an escrow agreement for a product transfer.
     * @dev Buyer must send ETH with this call. The ETH is locked until
     *      delivery is confirmed or a dispute is resolved.
     * @param productId The supply chain product ID being transacted.
     * @param seller    The address that will receive funds upon delivery.
     * @return escrowId The unique ID of the newly created escrow.
     */
    function createEscrow(uint256 productId, address payable seller)
        external
        payable
        returns (uint256 escrowId)
    {
        require(msg.value > 0, "PaymentEscrow: must send ETH");
        require(seller != address(0), "PaymentEscrow: invalid seller address");
        require(productEscrow[productId] == 0, "PaymentEscrow: active escrow exists");

        _escrowCounter++;
        escrowId = _escrowCounter;

        escrows[escrowId] = Escrow({
            productId:  productId,
            buyer:      payable(msg.sender),
            seller:     seller,
            amount:     msg.value,
            status:     EscrowStatus.Pending,
            createdAt:  block.timestamp,
            releasedAt: 0
        });

        productEscrow[productId] = escrowId;

        emit EscrowCreated(escrowId, productId, msg.sender, seller, msg.value);
    }

    /**
     * @notice Releases escrowed funds to the seller upon delivery confirmation.
     * @dev Only the buyer can confirm delivery and trigger fund release.
     *      Escrow must be in Pending status.
     * @param escrowId The ID of the escrow to release.
     */
    function confirmDeliveryAndRelease(uint256 escrowId)
        external
        escrowExists(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(msg.sender == e.buyer, "PaymentEscrow: only buyer can confirm");
        require(e.status == EscrowStatus.Pending, "PaymentEscrow: escrow not pending");

        e.status = EscrowStatus.Released;
        e.releasedAt = block.timestamp;
        productEscrow[e.productId] = 0; // Clear active escrow for product

        uint256 amount = e.amount;
        e.seller.transfer(amount);

        emit FundsReleased(escrowId, e.seller, amount);
    }

    /**
     * @notice Raises a dispute on a pending escrow, flagging it for admin review.
     * @dev Only the buyer can raise a dispute. Funds remain locked during dispute.
     * @param escrowId The ID of the escrow being disputed.
     */
    function raiseDispute(uint256 escrowId)
        external
        escrowExists(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(msg.sender == e.buyer, "PaymentEscrow: only buyer can dispute");
        require(e.status == EscrowStatus.Pending, "PaymentEscrow: escrow not pending");

        e.status = EscrowStatus.Disputed;
        emit EscrowDisputed(escrowId, msg.sender);
    }

    /**
     * @notice Resolves a disputed escrow — owner decides to release or refund.
     * @dev Only contract owner/admin can resolve disputes (arbitration role).
     * @param escrowId      The ID of the disputed escrow.
     * @param releaseFunds  True to release to seller; false to refund buyer.
     */
    function resolveDispute(uint256 escrowId, bool releaseFunds)
        external
        onlyOwner
        escrowExists(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.Disputed, "PaymentEscrow: escrow not disputed");

        uint256 amount = e.amount;

        if (releaseFunds) {
            e.status = EscrowStatus.Released;
            e.releasedAt = block.timestamp;
            e.seller.transfer(amount);
            emit FundsReleased(escrowId, e.seller, amount);
        } else {
            e.status = EscrowStatus.Refunded;
            e.buyer.transfer(amount);
            emit FundsRefunded(escrowId, e.buyer, amount);
        }

        productEscrow[e.productId] = 0;
    }

    // ─────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────

    /**
     * @notice Returns the details of a given escrow agreement.
     * @param escrowId The unique escrow identifier.
     * @return Escrow struct with all payment details and status.
     */
    function getEscrow(uint256 escrowId)
        external
        view
        escrowExists(escrowId)
        returns (Escrow memory)
    {
        return escrows[escrowId];
    }

    /**
     * @notice Returns the total number of escrow agreements created.
     */
    function totalEscrows() external view returns (uint256) {
        return _escrowCounter;
    }
}
