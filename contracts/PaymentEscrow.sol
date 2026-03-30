// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PaymentEscrow
 * @notice Automated escrow payment contract for supply chain transactions.
 *
 * @dev Handles the financial layer of the supply chain: buyers lock ETH into
 *      escrow when initiating a product transfer, and funds are released to
 *      the seller only after the buyer confirms delivery. Disputes are handled
 *      by admin arbitration.
 *
 *      Design principles:
 *        - Immutability   : escrow records are never deleted; status transitions are one-way.
 *        - Verifiability  : every financial event emits an indexed event.
 *        - Duplicate guard: only one active escrow per product at a time.
 *        - Error safety   : guards against invalid amounts, addresses, wrong-state
 *                           transitions, and reentrancy via Checks-Effects-Interactions pattern.
 *        - Reentrancy safe: state is updated before ETH is transferred (CEI pattern).
 */
contract PaymentEscrow {

    // ═══════════════════════════════════════════════════════════
    // SECTION 1 — DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Lifecycle states for an escrow payment agreement.
     *
     *  Pending → Released  (buyer confirms delivery)
     *  Pending → Disputed  (buyer raises a dispute)
     *  Disputed → Released (admin resolves: release to seller)
     *  Disputed → Refunded (admin resolves: refund to buyer)
     *
     *  Released and Refunded are terminal states — no further transitions allowed.
     */
    enum EscrowStatus {
        Pending,    // Funds locked, awaiting delivery confirmation or dispute
        Released,   // Funds sent to seller — terminal
        Refunded,   // Funds returned to buyer — terminal
        Disputed    // Flagged for admin arbitration; funds remain locked
    }

    /**
     * @notice Represents a single escrow agreement tied to a product transfer.
     *
     * @dev Fields:
     *   escrowId    — Unique auto-incremented identifier for this agreement.
     *   productId   — ID of the SupplyChain product this payment covers.
     *   buyer       — Party who deposited funds (e.g., retailer paying a supplier).
     *   seller      — Party who receives funds upon confirmed delivery.
     *   amount      — ETH locked in escrow, in wei. Immutable after creation.
     *   status      — Current lifecycle status (see EscrowStatus enum).
     *   createdAt   — Block timestamp of escrow creation.
     *   resolvedAt  — Block timestamp when funds were released or refunded (0 if still pending).
     */
    struct Escrow {
        uint256      escrowId;
        uint256      productId;
        address payable buyer;
        address payable seller;
        uint256      amount;
        EscrowStatus status;
        uint256      createdAt;
        uint256      resolvedAt;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 2 — STATE VARIABLES
    // ═══════════════════════════════════════════════════════════

    /// @notice Auto-incrementing escrow ID counter. Starts at 1; 0 = "no escrow".
    uint256 private _escrowCounter;

    /// @notice Contract admin — resolves disputes and manages arbitration.
    address public immutable owner;

    /// @notice Primary escrow registry: maps escrow ID → Escrow struct.
    ///         Escrow records are never deleted; resolved ones retain their history.
    mapping(uint256 => Escrow) public escrows;

    /// @notice Active escrow index: maps product ID → active escrow ID.
    ///         Value is 0 when no active escrow exists for a product.
    ///         Prevents multiple simultaneous escrows for the same product.
    mapping(uint256 => uint256) public productEscrow;

    // ═══════════════════════════════════════════════════════════
    // SECTION 3 — EVENTS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new escrow agreement is created and funded.
     * @param escrowId  The unique ID of the escrow agreement.
     * @param productId The product ID this payment covers.
     * @param buyer     The address that deposited ETH.
     * @param seller    The address designated to receive funds on delivery.
     * @param amount    The ETH amount locked, in wei.
     */
    event EscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed productId,
        address indexed buyer,
        address seller,
        uint256 amount
    );

    /**
     * @notice Emitted when funds are successfully released to the seller.
     * @param escrowId The escrow that was resolved.
     * @param seller   The address that received the funds.
     * @param amount   The ETH amount transferred, in wei.
     */
    event FundsReleased(
        uint256 indexed escrowId,
        address indexed seller,
        uint256 amount
    );

    /**
     * @notice Emitted when funds are refunded to the buyer.
     * @param escrowId The escrow that was refunded.
     * @param buyer    The address that received the refund.
     * @param amount   The ETH amount returned, in wei.
     */
    event FundsRefunded(
        uint256 indexed escrowId,
        address indexed buyer,
        uint256 amount
    );

    /**
     * @notice Emitted when a buyer raises a dispute on a pending escrow.
     * @param escrowId  The disputed escrow ID.
     * @param raisedBy  The buyer's address that raised the dispute.
     * @param productId The product ID associated with the dispute.
     */
    event EscrowDisputed(
        uint256 indexed escrowId,
        address indexed raisedBy,
        uint256 indexed productId
    );

    // ═══════════════════════════════════════════════════════════
    // SECTION 4 — MODIFIERS
    // ═══════════════════════════════════════════════════════════

    /// @dev Restricts to contract owner/admin (arbitration role).
    modifier onlyOwner() {
        require(msg.sender == owner, "PaymentEscrow: caller is not the owner");
        _;
    }

    /// @dev Validates that an escrow ID refers to an existing escrow agreement.
    ///      Uses escrowId > 0 and amount > 0 as existence sentinels.
    modifier escrowExists(uint256 escrowId) {
        require(
            escrowId > 0 && escrows[escrowId].amount > 0,
            "PaymentEscrow: escrow does not exist"
        );
        _;
    }

    /// @dev Ensures an escrow is in Pending status before allowing state transitions.
    ///      Prevents duplicate actions on already-resolved or disputed escrows.
    modifier onlyPending(uint256 escrowId) {
        require(
            escrows[escrowId].status == EscrowStatus.Pending,
            "PaymentEscrow: escrow is not in Pending status"
        );
        _;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 5 — CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Deploys the PaymentEscrow contract.
     * @dev Sets the deployer as the immutable owner/arbitrator.
     */
    constructor() {
        owner = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 6 — CORE ESCROW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Creates a new escrow agreement and locks ETH for a product transfer.
     *
     * @dev Creation flow:
     *   1. Validates ETH was sent (msg.value > 0).
     *   2. Validates seller is a non-zero, non-self address.
     *   3. Guards against duplicate escrows for the same product (productEscrow mapping).
     *   4. Assigns unique escrow ID and stores Escrow struct.
     *   5. Records active escrow against product ID.
     *   6. Emits EscrowCreated event.
     *
     * Safeguards:
     *   - Must send ETH > 0 (zero-value escrows are meaningless).
     *   - Seller must be a valid non-zero address.
     *   - Buyer cannot be the same as the seller.
     *   - Only one active escrow per product at a time.
     *
     * @param productId The SupplyChain product ID this payment is for.
     * @param seller    The payable address of the party receiving funds on delivery.
     * @return escrowId The unique ID assigned to the new escrow agreement.
     */
    function createEscrow(uint256 productId, address payable seller)
        external
        payable
        returns (uint256 escrowId)
    {
        require(msg.value > 0,           "PaymentEscrow: escrow amount must be greater than zero");
        require(seller != address(0),    "PaymentEscrow: seller cannot be the zero address");
        require(seller != msg.sender,    "PaymentEscrow: buyer and seller cannot be the same address");
        require(productEscrow[productId] == 0, "PaymentEscrow: an active escrow already exists for this product");

        _escrowCounter++;
        escrowId = _escrowCounter;

        escrows[escrowId] = Escrow({
            escrowId:   escrowId,
            productId:  productId,
            buyer:      payable(msg.sender),
            seller:     seller,
            amount:     msg.value,
            status:     EscrowStatus.Pending,
            createdAt:  block.timestamp,
            resolvedAt: 0
        });

        productEscrow[productId] = escrowId;

        emit EscrowCreated(escrowId, productId, msg.sender, seller, msg.value);
    }

    /**
     * @notice Buyer confirms delivery and releases escrowed funds to the seller.
     *
     * @dev Implements the Checks-Effects-Interactions (CEI) pattern to prevent reentrancy:
     *      1. CHECK:  validate caller is buyer and status is Pending.
     *      2. EFFECT: update escrow status and clear productEscrow mapping.
     *      3. INTERACT: transfer ETH to seller.
     *
     * Safeguards:
     *   - Only the buyer can confirm their own delivery (not seller, not admin).
     *   - Escrow must be in Pending status (not already released, refunded, or disputed).
     *
     * @param escrowId The ID of the escrow to release.
     */
    function confirmDeliveryAndRelease(uint256 escrowId)
        external
        escrowExists(escrowId)
        onlyPending(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(msg.sender == e.buyer, "PaymentEscrow: only the buyer can confirm delivery");

        // EFFECT: update state before transferring ETH (CEI pattern — reentrancy protection)
        e.status     = EscrowStatus.Released;
        e.resolvedAt = block.timestamp;
        productEscrow[e.productId] = 0;   // Clear active escrow slot for this product

        uint256 amount = e.amount;

        // INTERACT: transfer funds to seller
        e.seller.transfer(amount);

        emit FundsReleased(escrowId, e.seller, amount);
    }

    /**
     * @notice Buyer raises a dispute on a pending escrow, locking funds for arbitration.
     *
     * @dev Transitions escrow from Pending → Disputed. Funds remain locked in the contract
     *      until an admin calls resolveDispute(). Only the buyer can initiate a dispute
     *      (they are the party at risk of non-delivery).
     *
     * Safeguards:
     *   - Only the buyer can raise a dispute on their own escrow.
     *   - Escrow must be in Pending status.
     *
     * @param escrowId The ID of the escrow being disputed.
     */
    function raiseDispute(uint256 escrowId)
        external
        escrowExists(escrowId)
        onlyPending(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(msg.sender == e.buyer, "PaymentEscrow: only the buyer can raise a dispute");

        e.status = EscrowStatus.Disputed;

        emit EscrowDisputed(escrowId, msg.sender, e.productId);
    }

    /**
     * @notice Admin resolves a disputed escrow by releasing funds to seller or refunding buyer.
     *
     * @dev Only callable by the contract owner (arbitrator). The owner reviews the dispute
     *      off-chain and decides the outcome. Implements CEI pattern for reentrancy safety.
     *
     * Safeguards:
     *   - Only the contract owner can call this.
     *   - Escrow must be in Disputed status (not Pending, Released, or Refunded).
     *
     * @param escrowId      The ID of the disputed escrow to resolve.
     * @param releaseFunds  True → release ETH to seller; False → refund ETH to buyer.
     */
    function resolveDispute(uint256 escrowId, bool releaseFunds)
        external
        onlyOwner
        escrowExists(escrowId)
    {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.Disputed, "PaymentEscrow: escrow is not in Disputed status");

        // EFFECT: update state before transferring ETH (CEI pattern)
        e.resolvedAt = block.timestamp;
        productEscrow[e.productId] = 0;  // Clear active escrow slot

        uint256 amount = e.amount;

        if (releaseFunds) {
            // Admin decides: delivery was valid — pay the seller
            e.status = EscrowStatus.Released;
            e.seller.transfer(amount);
            emit FundsReleased(escrowId, e.seller, amount);
        } else {
            // Admin decides: delivery failed — refund the buyer
            e.status = EscrowStatus.Refunded;
            e.buyer.transfer(amount);
            emit FundsRefunded(escrowId, e.buyer, amount);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // SECTION 7 — VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /**
     * @notice Returns full details of an escrow agreement.
     * @param escrowId The unique escrow identifier.
     * @return Escrow struct with all payment details, parties, and current status.
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
     * @notice Returns the active escrow ID for a given product, or 0 if none exists.
     * @param productId The SupplyChain product ID to query.
     * @return Active escrow ID, or 0 if no active escrow for this product.
     */
    function getActiveEscrowForProduct(uint256 productId) external view returns (uint256) {
        return productEscrow[productId];
    }

    /**
     * @notice Returns the total number of escrow agreements ever created.
     * @return Total escrow count (equals the last assigned escrow ID).
     */
    function totalEscrows() external view returns (uint256) {
        return _escrowCounter;
    }
}
