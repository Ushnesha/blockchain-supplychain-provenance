const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Supply Chain System", function () {
  let registry, supply, escrow;
  let owner, manufacturer, supplier, distributor, retailer, other;

  beforeEach(async function () {
    [owner, manufacturer, supplier, distributor, retailer, other] =
      await ethers.getSigners();

    // Deploy ActorRegistry
    const ActorRegistry = await ethers.getContractFactory("ActorRegistry");
    registry = await ActorRegistry.deploy();
    await registry.waitForDeployment();

    const registryAddress = await registry.getAddress();

    // Deploy SupplyChain
    const SupplyChain = await ethers.getContractFactory("SupplyChain");
    supply = await SupplyChain.deploy(registryAddress);
    await supply.waitForDeployment();

    // Deploy PaymentEscrow
    const PaymentEscrow = await ethers.getContractFactory("PaymentEscrow");
    escrow = await PaymentEscrow.deploy(registryAddress);
    await escrow.waitForDeployment();
  });

  // ============================
  // ACTOR REGISTRY TESTS
  // ============================
  describe("ActorRegistry", function () {
    it("should register an actor", async function () {
      await registry.registerActor(
        manufacturer.address,
        "Manufacturer",
        "USA",
        1
      );

      const actor = await registry.getActor(manufacturer.address);
      expect(actor.name).to.equal("Manufacturer");
    });

    it("should not allow duplicate registration", async function () {
      await registry.registerActor(
        manufacturer.address,
        "Manufacturer",
        "USA",
        1
      );

      await expect(
        registry.registerActor(manufacturer.address, "Again", "USA", 1)
      ).to.be.reverted;
    });

    it("should reject non-owner registration", async function () {
      await expect(
        registry
          .connect(other)
          .registerActor(other.address, "Bad", "USA", 1)
      ).to.be.reverted;
    });
  });

  // ============================
  // SUPPLY CHAIN TESTS
  // ============================
  describe("SupplyChain", function () {
    beforeEach(async function () {
      // Register actors
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
      await registry.registerActor(distributor.address, "D", "USA", 3);
      await registry.registerActor(retailer.address, "R", "USA", 4);
    });

    it("should create a product", async function () {
      await supply.connect(manufacturer).registerProduct(
        "Milk",
        "USA",
        "B1",
        "{}"
      );

      const product = await supply.getProduct(1);
      expect(product.name).to.equal("Milk");
    });

    it("should not allow unauthorized product creation", async function () {
      await expect(
        supply.connect(other).registerProduct("Bad", "USA", "X", "{}")
      ).to.be.reverted;
    });

    it("should transfer product through full chain", async function () {
      await supply.connect(manufacturer).registerProduct(
        "Milk",
        "USA",
        "B1",
        "{}"
      );

      await supply.connect(manufacturer).transferProduct(
        1,
        supplier.address,
        "to supplier"
      );

      await supply.connect(supplier).transferProduct(
        1,
        distributor.address,
        "to distributor"
      );

      await supply.connect(distributor).transferProduct(
        1,
        retailer.address,
        "to retailer"
      );

      const product = await supply.getProduct(1);
      expect(product.currentOwner).to.equal(retailer.address);
    });

    it("should prevent transfer to unauthorized actor", async function () {
      await supply.connect(manufacturer).registerProduct(
        "Milk",
        "USA",
        "B1",
        "{}"
      );

      await expect(
        supply
          .connect(manufacturer)
          .transferProduct(1, other.address, "bad")
      ).to.be.reverted;
    });

    it("should mark product as sold", async function () {
      await supply.connect(manufacturer).registerProduct(
        "Milk",
        "USA",
        "B1",
        "{}"
      );

      await supply.connect(manufacturer).transferProduct(
        1,
        supplier.address,
        ""
      );

      await supply.connect(supplier).transferProduct(
        1,
        distributor.address,
        ""
      );

      await supply.connect(distributor).transferProduct(
        1,
        retailer.address,
        ""
      );

      await supply.connect(retailer).markAsSold(1, "sold");

      const product = await supply.getProduct(1);
      expect(product.stage).to.equal(4); // Sold
    });
  });

  // ============================
  // ESCROW TESTS
  // ============================
  describe("PaymentEscrow", function () {
    beforeEach(async function () {
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
    });

    it("should create escrow", async function () {
      await escrow.connect(manufacturer).createEscrow(
        1,
        supplier.address,
        { value: ethers.parseEther("1") }
      );

      const esc = await escrow.getEscrow(1);
      expect(esc.amount).to.equal(ethers.parseEther("1"));
    });

    it("should reject zero value escrow", async function () {
      await expect(
        escrow.connect(manufacturer).createEscrow(1, supplier.address)
      ).to.be.reverted;
    });

    it("should release funds on confirmation", async function () {
      await escrow.connect(manufacturer).createEscrow(
        1,
        supplier.address,
        { value: ethers.parseEther("1") }
      );

      await escrow
        .connect(manufacturer)
        .confirmDeliveryAndRelease(1);

      const esc = await escrow.getEscrow(1);
      expect(esc.status).to.equal(1); // Released
    });

    it("should allow dispute resolution", async function () {
      await escrow.connect(manufacturer).createEscrow(
        1,
        supplier.address,
        { value: ethers.parseEther("1") }
      );

      await escrow.connect(manufacturer).raiseDispute(1);

      await escrow.resolveDispute(1, false);

      const esc = await escrow.getEscrow(1);
      expect(esc.status).to.equal(2); // Refunded
    });
  });

  // ============================
  // FULL SYSTEM TEST
  // ============================
  describe("Full Flow", function () {
    it("should run full supply chain + escrow", async function () {
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
      await registry.registerActor(retailer.address, "R", "USA", 4);

      await supply.connect(manufacturer).registerProduct(
        "Milk",
        "USA",
        "B1",
        "{}"
      );

      await supply.connect(manufacturer).transferProduct(
        1,
        supplier.address,
        ""
      );

      await escrow.connect(retailer).createEscrow(
        1,
        supplier.address,
        { value: ethers.parseEther("1") }
      );

      await escrow.connect(retailer).confirmDeliveryAndRelease(1);

      const esc = await escrow.getEscrow(1);
      expect(esc.status).to.equal(1);
    });
  });
});
