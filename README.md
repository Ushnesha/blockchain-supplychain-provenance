# Blockchain-Based Supply Chain Provenance System

## Description

A decentralized application (DApp) that enhances transparency, traceability, and trust in supply chain management using blockchain technology. Built on Ethereum, the system records every product's journey — from manufacturer to end consumer — on an immutable, shared ledger using smart contracts.

### Key Features
- **Transparency**: Every stakeholder can verify the origin and movement of goods in real time.
- **Traceability**: Products are tracked at each stage of the supply chain from production to delivery.
- **Security**: Data immutability prevents tampering and fraud.
- **Automation**: Smart contracts automate verification, payments, and order processing without intermediaries.

### System Architecture

The system is composed of three main layers:

1. **Frontend (DApp Interface)** – A React-based web application that allows supply chain actors (manufacturers, suppliers, retailers, regulators, consumers) to interact with the system.
2. **Smart Contracts** – Solidity contracts deployed on Ethereum that handle product registration, ownership transfer, verification, and payment.
3. **Blockchain Layer (Ethereum)** – Stores all immutable transaction records emitted by the smart contracts.

---

## Dependencies

### Blockchain / Smart Contracts
- [Node.js](https://nodejs.org/) (v18+)
- [Hardhat](https://hardhat.org/) – Ethereum development environment
- [Solidity](https://soliditylang.org/) (^0.8.0) – Smart contract language
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/) – Secure, audited contract libraries
- [ethers.js](https://docs.ethers.org/) – Ethereum interaction library

### Frontend
- [React](https://react.dev/) (v18+)
- [Web3.js](https://web3js.org/) – Browser-to-blockchain interaction
- [MetaMask](https://metamask.io/) – Browser wallet for signing transactions

### Backend (optional middleware)
- [Node.js](https://nodejs.org/) + [Express](https://expressjs.com/)
- [MongoDB](https://www.mongodb.com/) – Off-chain data storage (optional)

---

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/YOUR_USERNAME/blockchain-supply-chain.git
cd blockchain-supply-chain
```

### 2. Install Dependencies
```bash
# Install root-level dependencies (Hardhat, etc.)
npm install

# Install frontend dependencies
cd frontend
npm install
cd ..
```

### 3. Configure Environment
```bash
cp .env.example .env
# Edit .env with your Infura/Alchemy API key and deployer private key
```

### 4. Compile Smart Contracts
```bash
npx hardhat compile
```

### 5. Run Local Blockchain & Deploy
```bash
# Start a local Hardhat network
npx hardhat node

# In a new terminal, deploy contracts
npx hardhat run scripts/deploy.js --network localhost
```

### 6. Start the Frontend
```bash
cd frontend
npm start
```
Open [http://localhost:3000](http://localhost:3000) in your browser with MetaMask connected to the local network.

---

## How to Deploy (Testnet)

> Full deployment details will be added as the project progresses. The following outlines the intended flow:

1. Configure `.env` with a testnet RPC URL (e.g., Sepolia via Infura/Alchemy) and a funded wallet private key.
2. Run: `npx hardhat run scripts/deploy.js --network sepolia`
3. Copy the deployed contract addresses into `frontend/src/config.js`.
4. Build and serve the frontend: `npm run build`

---

## Team

| Name | Role |
|------|------|
| Sid Uppuluri | Research & Requirement Analysis |
| Venkata Rohith Reddy Putha | Blockchain Architecture & Smart Contract Development |
| Ushnesha Daripa | Backend System Development |
| Gavin Fiedler | Frontend & UI Development |
| Sai Sreekar Kallem | Testing, Evaluation & Documentation |
