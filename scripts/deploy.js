// scripts/deploy.js
// Deployment script for all SupplyChain system contracts.
// Run with: npx hardhat run scripts/deploy.js --network <network>

const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  // console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // 1. Deploy ActorRegistry — manages participant identities and roles
  const ActorRegistry = await ethers.getContractFactory("ActorRegistry");
  const registry = await ActorRegistry.deploy();
  await registry.waitForDeployment();

  const registryAddress = await registry.getAddress(); //added for clarity when reading and passing values
  console.log("ActorRegistry deployed to:", registryAddress);

  // 2. Deploy SupplyChain — core product tracking and provenance contract
  const SupplyChain = await ethers.getContractFactory("SupplyChain");
  const supplyChain = await SupplyChain.deploy(registryAddress); // Pass registry address to link them
  await supplyChain.waitForDeployment();

  const supplyChainAddress = await supplyChain.getAddress(); //added for clarity when reading and passing values
  console.log("SupplyChain deployed to:", supplyChainAddress);

  // 3. Deploy PaymentEscrow — automated escrow for supply chain payments
  const PaymentEscrow = await ethers.getContractFactory("PaymentEscrow");
  const escrow = await PaymentEscrow.deploy(registryAddress); // Pass registry address to link them
  await escrow.waitForDeployment();

  const escrowAddress = await escrow.getAddress(); //added for clarity when reading and passing values
  console.log("PaymentEscrow deployed to:", escrowAddress);

  console.log("\n✅ All contracts deployed.");
}


main().catch((error) => {
  console.error(error);
  process.exit(1);
});
