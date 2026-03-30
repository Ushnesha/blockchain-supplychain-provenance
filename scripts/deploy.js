// scripts/deploy.js
// Deployment script for all SupplyChain system contracts.
// Run with: npx hardhat run scripts/deploy.js --network <network>

const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // 1. Deploy ActorRegistry — manages participant identities and roles
  const ActorRegistry = await ethers.getContractFactory("ActorRegistry");
  const registry = await ActorRegistry.deploy();
  await registry.waitForDeployment();
  console.log("ActorRegistry deployed to:", await registry.getAddress());

  // 2. Deploy SupplyChain — core product tracking and provenance contract
  const SupplyChain = await ethers.getContractFactory("SupplyChain");
  const supplyChain = await SupplyChain.deploy();
  await supplyChain.waitForDeployment();
  console.log("SupplyChain deployed to:", await supplyChain.getAddress());

  // 3. Deploy PaymentEscrow — automated escrow for supply chain payments
  const PaymentEscrow = await ethers.getContractFactory("PaymentEscrow");
  const escrow = await PaymentEscrow.deploy();
  await escrow.waitForDeployment();
  console.log("PaymentEscrow deployed to:", await escrow.getAddress());

  console.log("\n All contracts deployed. Update frontend/src/config.js with these addresses.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
