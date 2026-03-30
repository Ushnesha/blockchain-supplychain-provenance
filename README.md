# Blockchain-Based Supply Chain Provenance System

## Description

A decentralized application (DecAp) that enhances transparency, traceability, and trust in supply chain management using blockchain technology. Built on Ethereum, the system records every product's journey — from manufacturer to end consumer — on an immutable, shared ledger using smart contracts.

### Core Goals (from proposal)
| Goal | How It's Achieved |
|------|------------------|
| **Transparency** | All stakeholders can verify product origin and movement via `getProvenance()` |
| **Traceability** | Products are tracked at every stage: `Manufactured → Shipped → InWarehouse → AtRetailer → Sold` |
| **Security** | Data immutability: transfer records are append-only; no deletion functions exist |
| **Automation** | `PaymentEscrow` automates payments between actors without intermediaries |

### System Architecture

The system is composed of three layers, as defined in the proposal:

1. **Frontend (DecAp Interface)** — React + Web3.js web application for all supply chain actors (manufacturers, suppliers, retailers, regulators, consumers).
2. **Smart Contracts** — Three Solidity contracts deployed on Ethereum handling product registration, ownership transfer, payment escrow, and identity management.
3. **Blockchain Layer (Ethereum)** — Stores all immutable transaction records emitted by the smart contracts.

---

## Smart Contract Design

### Contracts Overview

| Contract | Responsibility |
|----------|---------------|
| `SupplyChain.sol` | Core product registration, custody transfer, stage tracking, and provenance |
| `ActorRegistry.sol` | Role-based identity management for all supply chain participants |
| `PaymentEscrow.sol` | Automated ETH escrow for payments between supply chain actors |

---

### Data Structures

#### `SupplyChain.sol` — Product

The `Product` struct stores all information about a registered product:

```solidity
struct Product {
    uint256 id;           // Unique on-chain identifier (auto-incremented)
    string  name;         // Human-readable product name or SKU
    string  origin;       // Geographic origin or manufacturing facility
    string  batchId;      // Production batch/lot number for grouped tracking
    string  metadata;     // JSON-encoded additional attributes (e.g., expiry, weight)
    address manufacturer; // Ethereum address of the original manufacturer
    address currentOwner; // Address of the current supply chain custodian
    Stage   stage;        // Current lifecycle stage (see Stage enum)
    uint256 registeredAt; // Block timestamp of first registration
    uint256 updatedAt;    // Block timestamp of most recent state change
    bool    exists;       // Guard flag preventing phantom-ID access
}
```

The `Stage` enum enforces a strictly sequential product lifecycle:
```
Manufactured → Shipped → InWarehouse → AtRetailer → Sold
```

The `TransferRecord` struct forms the immutable, append-only provenance chain:
```solidity
struct TransferRecord {
    address from;       // Previous custodian (address(0) for genesis entry)
    address to;         // Receiving custodian
    Stage   stage;      // Stage at time of this record
    uint256 timestamp;  // Block timestamp
    string  notes;      // Handler notes: location, condition, carrier info, etc.
}
```

#### `ActorRegistry.sol` — Actor

```solidity
struct Actor {
    address wallet;       // Actor's Ethereum address (primary key)
    string  name;         // Legal or business name
    string  location;     // Physical location or jurisdiction
    Role    role;         // Assigned role: Manufacturer | Supplier | Distributor | Retailer | Regulator
    bool    isActive;     // Soft-delete flag (false = deactivated, not erased)
    uint256 registeredAt; // Block timestamp of registration
}
```

#### `PaymentEscrow.sol` — Escrow

```solidity
struct Escrow {
    uint256      escrowId;   // Unique auto-incremented identifier
    uint256      productId;  // SupplyChain product ID this payment covers
    address payable buyer;   // Party who deposited ETH
    address payable seller;  // Party who receives ETH on delivery confirmation
    uint256      amount;     // ETH locked in escrow (wei), immutable after creation
    EscrowStatus status;     // Pending | Released | Refunded | Disputed
    uint256      createdAt;  // Block timestamp of creation
    uint256      resolvedAt; // Block timestamp of resolution (0 if unresolved)
}
```

---

### Key Functions

#### Registration
| Function | Contract | Description |
|----------|----------|-------------|
| `registerProduct(name, origin, batchId, metadata)` | SupplyChain | Registers a new product on-chain; assigns unique ID; creates genesis provenance record |
| `registerActor(wallet, name, location, role)` | ActorRegistry | Registers a supply chain participant with an assigned role |

#### Transfer & Ownership
| Function | Contract | Description |
|----------|----------|-------------|
| `transferProduct(productId, to, notes)` | SupplyChain | Transfers product custody to next actor; auto-advances stage |
| `updateProductStatus(productId, newStage, notes)` | SupplyChain | Updates stage without changing owner (e.g., warehouse arrival) |
| `markAsSold(productId, notes)` | SupplyChain | Terminal action: marks product as sold to end consumer |

#### Status & Role Management
| Function | Contract | Description |
|----------|----------|-------------|
| `setActorAuthorization(actor, status)` | SupplyChain | Owner grants/revokes actor authorization |
| `updateActorRole(wallet, newRole)` | ActorRegistry | Changes an actor's supply chain role |
| `setActorStatus(wallet, isActive)` | ActorRegistry | Soft-activates or deactivates an actor |

#### Payment Escrow
| Function | Contract | Description |
|----------|----------|-------------|
| `createEscrow(productId, seller)` | PaymentEscrow | Locks ETH for a product transaction |
| `confirmDeliveryAndRelease(escrowId)` | PaymentEscrow | Buyer confirms delivery; releases ETH to seller |
| `raiseDispute(escrowId)` | PaymentEscrow | Buyer flags a dispute; funds held for arbitration |
| `resolveDispute(escrowId, releaseFunds)` | PaymentEscrow | Admin arbitrates: release to seller or refund buyer |

---

### Events (State Change Logging)

All major state changes emit indexed events for off-chain verification and frontend listeners:

#### `SupplyChain.sol`
```solidity
event ProductCreated(uint256 indexed productId, string name, string batchId, address indexed manufacturer);
event OwnershipTransferred(uint256 indexed productId, address indexed from, address indexed to, Stage stage, uint256 timestamp);
event StatusUpdated(uint256 indexed productId, Stage oldStage, Stage newStage, address indexed updatedBy, uint256 timestamp);
event ActorAuthorizationChanged(address indexed actor, bool authorized);
```

#### `ActorRegistry.sol`
```solidity
event ActorRegistered(address indexed wallet, string name, Role indexed role, string location);
event ActorRoleUpdated(address indexed wallet, Role oldRole, Role newRole);
event ActorStatusChanged(address indexed wallet, bool isActive);
```

#### `PaymentEscrow.sol`
```solidity
event EscrowCreated(uint256 indexed escrowId, uint256 indexed productId, address indexed buyer, address seller, uint256 amount);
event FundsReleased(uint256 indexed escrowId, address indexed seller, uint256 amount);
event FundsRefunded(uint256 indexed escrowId, address indexed buyer, uint256 amount);
event EscrowDisputed(uint256 indexed escrowId, address indexed raisedBy, uint256 indexed productId);
```

---

### Immutability & Verifiability

- **Append-only provenance**: `_transferHistory[productId]` is a dynamic array that only grows. No delete or overwrite functions exist anywhere in the codebase.
- **Indexed events**: Every `ProductCreated`, `OwnershipTransferred`, and `StatusUpdated` event is indexed, making them queryable via `eth_getLogs` or The Graph subgraphs.
- **Immutable owner**: The `owner` state variable is declared `immutable` — set once at deployment and unchangeable.
- **Terminal states**: Once a product is `Sold` or an escrow is `Released`/`Refunded`, the `notSold` and `onlyPending` modifiers block any further modifications.

---

### Error Handling & Safeguards

| Safeguard | Where Applied |
|-----------|--------------|
| Duplicate product registration (same name + batchId) | `registerProduct` — reverts via `_productIndex` hash map |
| Duplicate actor registration (same wallet) | `registerActor` — checks `actors[wallet].role == Role.None` |
| Phantom product ID access | `productExists` modifier — checks `exists` flag |
| Unauthorized caller | `onlyAuthorized`, `onlyCurrentOwner` modifiers |
| Self-transfer | `transferProduct` — `require(to != msg.sender)` |
| Zero-address recipient | `transferProduct`, `createEscrow` — explicit zero-address checks |
| Invalid stage transition (skipping or reverting) | `updateProductStatus` — enforces `newStage == _nextStage(current)` |
| Actions on terminal (Sold) products | `notSold` modifier on transfer and status update functions |
| Duplicate escrow per product | `createEscrow` — checks `productEscrow[productId] == 0` |
| Reentrancy in ETH transfers | Checks-Effects-Interactions (CEI) pattern in `confirmDeliveryAndRelease` and `resolveDispute` |
| Owner lockout prevention | `setActorAuthorization` and `setActorStatus` block de-authorizing the owner |

---

## Dependencies

### Blockchain / Smart Contracts
- [Node.js](https://nodejs.org/) (v18+)
- [Hardhat](https://hardhat.org/) — Ethereum development environment
- [Solidity](https://soliditylang.org/) (^0.8.20) — Smart contract language
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/) — Audited base libraries
- [ethers.js](https://docs.ethers.org/) — Ethereum interaction library

### Frontend
- [React](https://react.dev/) (v18+)
- [Web3.js](https://web3js.org/) — Browser-to-blockchain interaction
- [MetaMask](https://metamask.io/) — Browser wallet for signing transactions

### Backend (middleware layer — planned)
- [Node.js](https://nodejs.org/) + [Express](https://expressjs.com/)
- [MongoDB](https://www.mongodb.com/) — Off-chain metadata storage

---

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/blockchain-supply-chain-provenance.git
cd blockchain-supply-chain-provenance
```

### 2. Install Dependencies
```bash
# Install root-level dependencies (Hardhat, ethers, etc.)
npm install

# Install frontend dependencies
cd frontend && npm install && cd ..
```

### 3. Configure Environment
```bash
cp .env.example .env
# Edit .env with your RPC URL, private key, and Etherscan API key
```

### 4. Compile Smart Contracts
```bash
npx hardhat compile
```

### 5. Run Local Blockchain & Deploy
```bash
# Terminal 1 — start local Hardhat node
npx hardhat node

# Terminal 2 — deploy all contracts to local network
npx hardhat run scripts/deploy.js --network localhost
```

### 6. Start the Frontend
```bash
cd frontend
npm start
# Open http://localhost:3000 with MetaMask connected to localhost:8545
```

---

## How to Deploy (Testnet — Sepolia)

> Full deployment details will be finalized during the implementation phase.

1. Fund your deployer wallet with Sepolia ETH via a faucet.
2. Set `SEPOLIA_RPC_URL` and `PRIVATE_KEY` in your `.env` file.
3. Deploy: `npx hardhat run scripts/deploy.js --network sepolia`
4. Copy the three deployed contract addresses into `frontend/src/config.js`.
5. Build the frontend: `cd frontend && npm run build`
6. Serve or host the build folder (e.g., via Vercel, Netlify, or IPFS).

---

## Team

| Name | Role |
|------|------|
| Sid Uppuluri | Research & Requirement Analysis |
| Venkata Rohith Reddy Putha | Blockchain Architecture & Smart Contract Development |
| Ushnesha Daripa | Backend System Development |
| Gavin Fiedler | Frontend & UI Development |
| Sai Sreekar Kallem | Testing, Evaluation & Documentation |
