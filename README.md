# Blockchain-Based Supply Chain Provenance System

## Executive Summary

A decentralized supply chain management system built on Ethereum that provides **complete transparency and immutable traceability** of products from manufacturer to end consumer. Using blockchain technology, this system eliminates fraud, counterfeiting, and ensures regulatory compliance throughout the entire supply chain.

---

## Problem Statement

Traditional supply chains suffer from:
- **Lack of Transparency**: No clear visibility into product movement and handling
- **Counterfeit Risk**: Difficulty verifying product authenticity
- **Trust Issues**: Multiple intermediaries with no unified source of truth
- **Compliance Challenges**: Difficult audit trails for regulators
- **Payment Disputes**: Trust issues when transferring goods between parties

This project solves these by creating an **immutable, transparent ledger** of every product journey.

---

## System Architecture

### Three Core Smart Contracts

#### 1. **ActorRegistry** — Identity & Role Management
**Purpose**: Central source of truth for all supply chain participants

**Key Features**:
- Registers supply chain actors (manufacturers, suppliers, distributors, retailers, regulators)
- Assigns and manages role-based access control
- Maintains actor profiles (name, location, registration date)
- Soft-delete mechanism: deactivate actors without erasing history
- Immutable audit trail of all role changes

**Supported Roles**:
- **Manufacturer**: Creates and registers new products
- **Supplier**: Provides raw materials or components
- **Distributor**: Moves goods between locations, operates warehouses
- **Retailer**: Final point of sale, marks products as sold
- **Regulator**: Read-only audit access for compliance verification

---

#### 2. **SupplyChain** — Core Product Tracking & Provenance
**Purpose**: Records complete lifecycle and custody history of every product

**Key Concepts**:

**Product Lifecycle Stages** (Sequential Progression):
```
Manufactured → Shipped → InWarehouse → AtRetailer → Sold
```
- **Manufactured**: Product created and registered by manufacturer
- **Shipped**: Product in transit (carrier custody)
- **InWarehouse**: Product in distributor's warehouse
- **AtRetailer**: Product arrived at retail point of sale
- **Sold**: Terminal state — product sold to end consumer

**Core Operations**:
- **Register Product**: Manufacturer creates a new product record with:
  - Product name / SKU
  - Origin / manufacturing facility
  - Batch ID (for grouped production runs)
  - Metadata (JSON format: expiry date, certifications, weight, category, etc.)

- **Transfer Custody**: Move product between actors with:
  - Automatic stage advancement
  - Handler notes (location, condition, carrier info)
  - Immutable transfer record added to audit trail

- **Update Status**: Current owner marks stage changes without transferring custody
  - Example: Distributor marks "received in warehouse" without transferring to new owner

- **Mark as Sold**: Retailer finalizes product as sold to consumer (terminal action)

**Provenance Trail** (Immutable Audit Log):
- Every registration and transfer is recorded with:
  - From/To addresses
  - Stage at time of transfer
  - Exact block timestamp
  - Handler notes
  - **Cannot be modified or deleted** — guaranteed authentic history

**Safeguards**:
- Duplicate registration prevention (same name + batch ID cannot be registered twice)
- Sequential stage enforcement (no skipping or reversing stages)
- Only current owner can transfer or update status
- Products in "Sold" state cannot be modified (finalized)

---

#### 3. **PaymentEscrow** — Automated Secure Payments
**Purpose**: Holds payment in escrow until delivery is confirmed

**Key Concepts**:

**Escrow Lifecycle**:
```
Pending → Released (on delivery confirmation)
       ↓
    Disputed → Released (admin resolves: release to seller)
            → Refunded (admin resolves: refund to buyer)
```

**Flow**:
1. **Buyer Initiates**: Locks ETH in escrow for a product transfer
2. **Funds Held**: ETH locked in contract until delivery or dispute resolution
3. **Two Resolution Paths**:
   - **Confirm Delivery**: Buyer confirms product received → funds released to seller
   - **Raise Dispute**: Buyer disputes delivery → funds locked for admin arbitration

**Admin Arbitration**:
- Contract owner acts as neutral arbitrator
- Reviews disputed escrows off-chain (external evidence: shipping docs, photos, etc.)
- Decides: Release funds to seller OR refund to buyer

**Safeguards**:
- Only buyer can confirm delivery or raise dispute
- Only admin/owner can resolve disputes
- One active escrow per product (prevents double-escrow)
- Reentrancy-protected using Checks-Effects-Interactions pattern
- Both parties must be authorized actors

---

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                   SYSTEM COMPONENTS                          │
└──────────────────────────────────────────────────────────────┘

                    ActorRegistry
                   ┌────────────┐
                   │  Actors    │
                   │  Roles     │
                   │  Status    │
                   └─────┬──────┘
                         │ (validates)
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
    SupplyChain     PaymentEscrow    Regulators
    ┌─────────┐    ┌──────────┐     (read-only)
    │Products │←──→│Escrows   │
    │Transfers│    │Payments  │
    │Provenance   │Disputes  │
    └─────────┘    └──────────┘
        ↓                ↓
    Frontend         Analytics
    UI/Dashboard     Off-chain indexing
```

---

## Key Technical Features

### 1. **Immutability & Audit Trail**
- All transfer records are append-only (never deleted or modified)
- Complete chronological history of every product
- Blockchain guarantees authenticity (cryptographically proven)

### 2. **Role-Based Access Control (RBAC)**
- ActorRegistry validates permissions for all operations
- Different actors can only perform role-specific actions
- Regulators have read-only access for compliance audits

### 3. **Event-Driven Architecture**
- Every significant action emits an indexed event:
  - `ProductCreated`: New product registered
  - `OwnershipTransferred`: Custody transfer between actors
  - `StatusUpdated`: Stage change without ownership change
  - `EscrowCreated`: Payment locked for product
  - `FundsReleased`: Payment released on delivery confirmation
  - `EscrowDisputed`: Dispute raised for arbitration
- Events enable off-chain indexing (The Graph, Subgraphs)
- External systems can listen to events in real-time

### 4. **Fraud Prevention**
- Duplicate registration guard (same product cannot be registered twice)
- Only authorized actors can participate
- Immutable proof of custody transfer
- Sequential stage progression prevents skipping steps
- Terminal "Sold" state prevents post-sale tampering

### 5. **Payment Security**
- Escrow holds funds until delivery confirmed
- Neutral arbitration for disputes
- Reentrancy protection using CEI pattern
- Safe ETH transfer using low-level call with success check

---

## Use Cases

### 1. **Pharmaceutical Supply Chain**
- Track medications from manufacturer to pharmacy
- Prevent counterfeit drugs
- Verify cold-chain handling (temperature-sensitive products)
- Metadata: Batch ID, expiry date, storage conditions

### 2. **Food & Beverage**
- Track origin and freshness of products
- Rapid recall capability (identify all units from specific batch)
- Verify organic/fair-trade certifications
- Metadata: Harvest date, certifications, expiry date

### 3. **Luxury Goods Authentication**
- Prove authenticity of high-value items
- Prevent counterfeit designer goods
- Track ownership history (resale value)
- Metadata: Serial number, certification details

### 4. **Electronics Manufacturing**
- Track components from supplier to final assembly
- Quality control checkpoints at each stage
- Warranty and repair history linked to product
- Metadata: Component specifications, certifications

### 5. **Regulatory Compliance**
- Auditors can query complete provenance at any time
- No way to hide supply chain steps
- Timestamped records for compliance reporting
- Immutable proof for investigations

---

## Technical Stack

### Smart Contracts
- **Language**: Solidity 0.8.20
- **Standards**: OpenZeppelin (security best practices)
- **Blockchain**: Ethereum (EVM-compatible networks)
- **Networks Supported**: 
  - Localhost (Hardhat)
  - Sepolia Testnet
  - Polygon Mumbai (config: chainID 80002)

### Development Tools
- **Hardhat**: Smart contract development & testing
- **ethers.js**: Contract interaction library (v6)
- **OpenZeppelin Contracts**: Secure contract primitives

### Frontend
- **React 18.2**: UI framework
- **Vite 5**: Fast build tooling
- **ethers.js**: Blockchain interaction
- **Web3 Integration**: MetaMask wallet connection

---

## Installation & Deployment

### Prerequisites
```bash
node --version    # v16+ required
npm --version     # v7+
```

### Setup
```bash
# Install root dependencies
npm install

# Install frontend dependencies
cd frontend && npm install && cd ..

# Create environment file
cp .env.example .env
# Fill in: SEPOLIA_RPC_URL, PRIVATE_KEY, PUBLIC_KEY
```

### Deploy to Local Hardhat
```bash
# Terminal 1: Start local blockchain
npm run node

# Terminal 2: Deploy contracts
npm run deploy:local
```

### Deploy to Sepolia Testnet
```bash
npm run deploy:sepolia
```

---

## Presentation Talking Points

### 1. **Problem & Motivation** (Slide 1-2)
- Current supply chains lack transparency
- Counterfeit products cost industries billions annually
- No unified source of truth for product custody
- Difficult for regulators to audit complex chains

### 2. **Solution Overview** (Slide 3-4)
- Blockchain provides immutable record
- Every product movement logged permanently
- Smart contracts enforce rules automatically
- Transparent to all authorized parties

### 3. **System Architecture** (Slide 5-7)
- Three contracts: ActorRegistry, SupplyChain, PaymentEscrow
- ActorRegistry: Who participates and their role
- SupplyChain: Product lifecycle and custody trail
- PaymentEscrow: Secure financial settlement

### 4. **Product Lifecycle** (Slide 8-9)
- Five sequential stages: Manufactured → Shipped → InWarehouse → AtRetailer → Sold
- Each transfer records: From, To, Stage, Timestamp, Notes
- Immutable audit trail follows product forever
- No way to hide supply chain steps

### 5. **Key Features** (Slide 10-12)
- **Immutability**: Append-only audit trail
- **Transparency**: Public ledger of all transfers
- **Automation**: Smart contracts enforce rules
- **Fraud Prevention**: Duplicate registration guard, sequential stages
- **Payment Security**: Escrow with dispute arbitration

### 6. **Use Cases** (Slide 13-15)
- Pharmaceuticals: Combat counterfeit drugs
- Food: Rapid recall + freshness verification
- Luxury Goods: Prove authenticity & ownership history
- Electronics: Track components + quality checkpoints
- Compliance: Regulator audit capability

### 7. **Technical Implementation** (Slide 16-17)
- Solidity smart contracts on Ethereum
- Event-driven: Every action emits indexed event
- Role-based access control (manufacturer, supplier, distributor, retailer, regulator)
- Reentrancy-protected payment handling

### 8. **Deployment & Future** (Slide 18)
- Contracts deployed on Sepolia testnet
- React frontend for user interaction
- Roadmap: Off-chain indexing (The Graph), mobile app, integration with ERP systems

---

## Security Considerations

### Implemented Safeguards
✅ Role-based access control (ActorRegistry validation)  
✅ Duplicate registration prevention (product key hash)  
✅ Sequential stage enforcement (no skipping backwards)  
✅ Immutable provenance (append-only transfer records)  
✅ Reentrancy protection (Checks-Effects-Interactions pattern)  
✅ Safe ETH transfer (low-level call with success check)  

### Audit Recommendations
- Code review by security auditor
- Formal verification of stage transitions
- Testing of edge cases (dispute resolution, actor deactivation)
- Gas optimization review
- Mainnet deployment only after thorough testing

---

## Conclusion

This blockchain-based supply chain system demonstrates how distributed ledger technology can solve real-world problems:
- **Transparency**: Complete visibility into product movement
- **Trust**: Immutable proof replaces faith in intermediaries
- **Efficiency**: Automated payments through escrow reduces disputes
- **Compliance**: Regulators can audit without special access

By encoding supply chain rules in smart contracts, we eliminate human error, fraud, and ambiguity—creating a system of truth rather than a system of trust.

---

## References

- [Ethereum Smart Contracts](https://ethereum.org/en/developers/docs/smart-contracts/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [Hardhat Development Environment](https://hardhat.org/)
- [ethers.js Library](https://docs.ethers.org/)
- [OpenZeppelin Security](https://docs.openzeppelin.com/contracts/)
