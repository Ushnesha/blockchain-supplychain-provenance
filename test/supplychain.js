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

  // ── GAS CONSUMPTION TESTS ──────────────────────────────────────────────────
  describe("Gas Consumption", function () {
    beforeEach(async function () {
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
      await registry.registerActor(distributor.address, "D", "USA", 3);
      await registry.registerActor(retailer.address, "R", "USA", 4);
    });

    it("should record gas used by registerProduct()", async function () {
      const tx = await supply
        .connect(manufacturer)
        .registerProduct("Milk", "USA", "B1", JSON.stringify({ category: "food", weight: "500g" }));
      const receipt = await tx.wait();
      console.log("registerProduct() gas used:", receipt.gasUsed.toString());
      expect(receipt.gasUsed).to.be.gt(0);
    });

    it("should record gas used by transferProduct()", async function () {
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
      const tx = await supply.connect(manufacturer).transferProduct(1, supplier.address, "Shipped from factory");
      const receipt = await tx.wait();
      console.log("transferProduct() gas used:", receipt.gasUsed.toString());
      expect(receipt.gasUsed).to.be.gt(0);
    });

    it("should record gas used by updateProductStatus()", async function () {
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");
      const tx = await supply.connect(supplier).updateProductStatus(1, 2, "Arrived at warehouse");
      const receipt = await tx.wait();
      console.log("updateProductStatus() gas used:", receipt.gasUsed.toString());
      expect(receipt.gasUsed).to.be.gt(0);
    });

    it("should show gas cost increases with longer notes strings", async function () {
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
      await supply.connect(manufacturer).registerProduct("Juice", "USA", "B2", "{}");

      const txShort = await supply
        .connect(manufacturer)
        .transferProduct(1, supplier.address, "short");
      const receiptShort = await txShort.wait();

      const txLong = await supply
        .connect(manufacturer)
        .transferProduct(2, supplier.address, "A".repeat(500));
      const receiptLong = await txLong.wait();

      console.log("transferProduct() gas with short notes:", receiptShort.gasUsed.toString());
      console.log("transferProduct() gas with 500-char notes:", receiptLong.gasUsed.toString());
      expect(receiptLong.gasUsed).to.be.gt(receiptShort.gasUsed);
    });

    it("should record gas used by createEscrow()", async function () {
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
      const tx = await escrow
        .connect(manufacturer)
        .createEscrow(1, supplier.address, { value: ethers.parseEther("1") });
      const receipt = await tx.wait();
      console.log("createEscrow() gas used:", receipt.gasUsed.toString());
      expect(receipt.gasUsed).to.be.gt(0);
    });
  });

  // ── UNBOUNDED STORAGE GROWTH TESTS ────────────────────────────────────────
  describe("Unbounded _transferHistory Growth", function () {
    beforeEach(async function () {
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
      await registry.registerActor(distributor.address, "D", "USA", 3);
      await registry.registerActor(retailer.address, "R", "USA", 4);
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
    });

    it("should append a record on registerProduct() — genesis entry exists", async function () {
      const provenance = await supply.getProvenance(1);
      expect(provenance.length).to.equal(1);
      expect(provenance[0].from).to.equal(ethers.ZeroAddress);
    });

    it("should grow _transferHistory on every transferProduct() call", async function () {
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "leg 1");
      const provenance = await supply.getProvenance(1);
      expect(provenance.length).to.equal(2);
    });

    it("should grow _transferHistory on every updateProductStatus() call", async function () {
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");
      await supply.connect(supplier).updateProductStatus(1, 2, "warehouse arrival");
      const provenance = await supply.getProvenance(1);
      // genesis + transfer + status update = 3
      expect(provenance.length).to.equal(3);
    });

    it("should accumulate a minimum of 5 records across the full lifecycle", async function () {
      // genesis (registerProduct) = 1
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");    // 2
      await supply.connect(supplier).transferProduct(1, distributor.address, "");     // 3
      await supply.connect(distributor).transferProduct(1, retailer.address, "");     // 4
      await supply.connect(retailer).markAsSold(1, "");                               // 5

      const provenance = await supply.getProvenance(1);
      expect(provenance.length).to.equal(5);
    });

    it("should never decrease in length — no pruning or deletion exists", async function () {
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");
      const before = await supply.getProvenance(1);
      await supply.connect(supplier).transferProduct(1, distributor.address, "");
      const after = await supply.getProvenance(1);
      expect(after.length).to.be.gt(before.length);
    });
  });
  // ── PUBLIC READABILITY TESTS ───────────────────────────────────────────────
  describe("Provenance Data Publicly Readable Without Authentication", function () {
    beforeEach(async function () {
      await registry.registerActor(manufacturer.address, "Acme Corp", "USA", 1);
      await registry.registerActor(supplier.address, "Parts Ltd", "Germany", 2);
      await supply
        .connect(manufacturer)
        .registerProduct("Widget", "USA", "LOT-001", JSON.stringify({ price: "9.99" }));
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "Dispatched");
    });

    it("should allow any address to call getProvenance() without being registered", async function () {
      // `other` is not registered in ActorRegistry
      const provenance = await supply.connect(other).getProvenance(1);
      expect(provenance.length).to.be.gt(0);
    });

    it("should expose actor name and location to any caller via getActor()", async function () {
      const actor = await registry.connect(other).getActor(manufacturer.address);
      expect(actor.name).to.equal("Acme Corp");
      expect(actor.location).to.equal("USA");
    });

    it("should expose full supplier network by iterating actorList publicly", async function () {
      const total = await registry.connect(other).totalActors();
      expect(total).to.equal(2);

      for (let i = 0; i < total; i++) {
        const wallet = await registry.actorList(i);
        const actor = await registry.connect(other).getActor(wallet);
        // Any observer can map wallet → name + location + role
        expect(actor.name).to.be.a("string").and.not.equal("");
      }
    });

    it("should expose transfer notes, addresses, and stages in provenance to any caller", async function () {
      const provenance = await supply.connect(other).getProvenance(1);
      const transferRecord = provenance[1];
      expect(transferRecord.notes).to.equal("Dispatched");
      expect(transferRecord.from).to.equal(manufacturer.address);
      expect(transferRecord.to).to.equal(supplier.address);
    });

    it("should expose escrow buyer, seller, and amount publicly via escrows mapping", async function () {
      await registry.registerActor(distributor.address, "DistCo", "France", 3);
      await escrow
        .connect(supplier)
        .createEscrow(1, distributor.address, { value: ethers.parseEther("2.5") });

      const activeEscrowId = await escrow.getActiveEscrowForProduct(1);
      const escrowRecord = await escrow.connect(other).getEscrow(activeEscrowId);

      expect(escrowRecord.buyer).to.equal(supplier.address);
      expect(escrowRecord.seller).to.equal(distributor.address);
      expect(escrowRecord.amount).to.equal(ethers.parseEther("2.5"));
    });
  });

  // ── STAGE REVERSAL AND SKIP TESTS ─────────────────────────────────────────
  describe("Stage Progression Rigidity", function () {
    beforeEach(async function () {
      await registry.registerActor(manufacturer.address, "M", "USA", 1);
      await registry.registerActor(supplier.address, "S", "USA", 2);
      await supply.connect(manufacturer).registerProduct("Milk", "USA", "B1", "{}");
    });

    it("should revert when attempting to skip a stage", async function () {
      // Product is at Manufactured (0); attempting to jump to InWarehouse (2)
      await expect(
        supply.connect(manufacturer).updateProductStatus(1, 2, "skip attempt")
      ).to.be.revertedWith("SupplyChain: invalid stage, must advance exactly one step at a time");
    });

    it("should revert when attempting to reverse a stage", async function () {
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");
      // Product is now at Shipped (1); attempting to go back to Manufactured (0)
      await expect(
        supply.connect(supplier).updateProductStatus(1, 0, "reversal attempt")
      ).to.be.revertedWith("SupplyChain: invalid stage, must advance exactly one step at a time");
    });

    it("should make an intermediate-stage error irrecoverable", async function () {
      // Manufacturer accidentally advances to Shipped before the product is ready.
      // There is no undo function — the only valid next action is to continue forward.
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "premature shipment");
      const product = await supply.getProduct(1);

      // Stage is now Shipped (1) — cannot go back to Manufactured (0)
      expect(product.stage).to.equal(1);
      await expect(
        supply.connect(supplier).updateProductStatus(1, 0, "undo attempt")
      ).to.be.reverted;
    });

    it("should revert any modification attempt once a product is marked Sold", async function () {
      await registry.registerActor(distributor.address, "D", "USA", 3);
      await registry.registerActor(retailer.address, "R", "USA", 4);

      await supply.connect(manufacturer).transferProduct(1, supplier.address, "");
      await supply.connect(supplier).transferProduct(1, distributor.address, "");
      await supply.connect(distributor).transferProduct(1, retailer.address, "");
      await supply.connect(retailer).markAsSold(1, "sold");

      // Any further transfer or status update must revert
      await expect(
        supply.connect(retailer).updateProductStatus(1, 4, "post-sale update")
      ).to.be.revertedWith("SupplyChain: product is already sold and cannot be modified");
    });

    it("should confirm no function exists to modify a historical TransferRecord", async function () {
      await supply.connect(manufacturer).transferProduct(1, supplier.address, "original note");
      const before = await supply.getProvenance(1);
      const originalNote = before[1].notes;

      // The only way to interact with history is to read it — there is no setter.
      // A second transfer appends but does not alter the previous record.
      await supply.connect(supplier).updateProductStatus(1, 2, "new note");
      const after = await supply.getProvenance(1);

      expect(after[1].notes).to.equal(originalNote);
      expect(after.length).to.equal(before.length + 1);
    });
  });
});
