import { expect } from "chai";
import { ethers } from "hardhat";
import { LootBox } from "../types";
import { tryCatch, errTypes } from "../helpers/errors";
import { parseEther } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("LootBox", function () {
  let lootbox: LootBox;
  let deployer: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let users: HardhatEthersSigner[];

  before(async () => {
    [deployer, user, ...users] = await ethers.getSigners();
    const LootBoxFactory = await ethers.getContractFactory("LootBox", deployer);
    lootbox = (await LootBoxFactory.deploy(parseEther("0.1"))) as LootBox;
  });

  describe("Setup tiers and blueprints", () => {
    it("Adding 3-8 tiers with buffer 3", async () => {
      await lootbox.addTier("normal", 0, 2);
      await lootbox.addTier("common", 0, 5);
      await lootbox.addTier("uncommon", 0, 20);
      await lootbox.addTier("Legendary", 0, 50);
      await lootbox.addTier("Exotic", 0, 100);
    });

    it('Add "Normal" items', async () => {
      await lootbox.addBlueprint(2, "Sword", 5);
      await lootbox.addBlueprint(2, "Pickaxe", 5);
      await lootbox.addBlueprint(2, "Axe", 5);
    });

    it('Add "Common" items', async () => {
      await lootbox.addBlueprint(5, "Sword", 5);
      await lootbox.addBlueprint(5, "Pickaxe", 5);
      await lootbox.addBlueprint(5, "Axe", 5);
    });

    it('Add "Uncommon" items', async () => {
      await lootbox.addBlueprint(20, "Sword", 5);
      await lootbox.addBlueprint(20, "Pickaxe", 5);
      await lootbox.addBlueprint(20, "Axe", 5);
    });

    it('Add "Legendary" blueprints', async () => {
      await lootbox.addBlueprint(50, "Flaming Sword", 10);
      await lootbox.addBlueprint(50, "Shadow Dagger", 10);
      await lootbox.addBlueprint(50, "Nexus", 10);
    });

    it('Add "Exotic" blueprints', async () => {
      await lootbox.addBlueprint(100, "Flaming Sword", 10);
      await lootbox.addBlueprint(100, "Shadow Dagger", 10);
      await lootbox.addBlueprint(100, "Nexus", 10);
    });
  });

  //   describe("Mining", () => {
  //     it("Mine nothing => challengeFailed", async () => {
  //       const input = generateInput(51, 1, 1);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("challengeFailed", receipt)).to.be.true;
  //     });

  //     it('Mine "normal" item => minedSuccessfully', async () => {
  //       const input = generateInput(4, 2, 1);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("minedSuccessfully", receipt)).to.be.true;
  //     });

  //     it('Mine another "normal" item, different blueprint => minedSuccessfully', async () => {
  //       const input = generateInput(4, 1, 1);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("minedSuccessfully", receipt)).to.be.true;
  //     });

  //     it("Mine existing blueprint, different instance => minedSuccessfully", async () => {
  //       const input = generateInput(4, 1, 2);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("minedSuccessfully", receipt)).to.be.true;
  //     });

  //     it('Mine "Legendary" item => minedSuccessfully', async () => {
  //       const input = generateInput(50, 1, 1);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("minedSuccessfully", receipt)).to.be.true;
  //     });

  //     it('Mine "Exotic" item => minedSuccessfully', async () => {
  //       const input = generateInput(100, 1, 1);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("minedSuccessfully", receipt)).to.be.true;
  //     });

  //     it("Mine same exact item 2 times => challengeFailed", async () => {
  //       const input = generateInput(100, 1, 2);
  //       await lootbox.mine(input);
  //       const tx = await lootbox.mine(input);
  //       const receipt = await tx.wait();
  //       expect(eventPresent("challengeFailed", receipt)).to.be.true;
  //     });
  //   });

  describe("Tiers", () => {
    it("Adding with rarity=0 fails", async () => {
      await tryCatch(lootbox.addTier("Impossible", 0, 0), errTypes.revert);
    });

    it("Adding duplicate tier masks fails", async () => {
      await tryCatch(lootbox.addTier("normal", 0, 2), errTypes.revert);
    });

    it("Adding duplicate tier names fails", async () => {
      await tryCatch(lootbox.addTier("normal", 9, 3), errTypes.revert);
    });

    it("Getting tier items count of nonexistent tier", async () => {
      await tryCatch(lootbox.getTierBlueprintCount(25000), errTypes.revert);
    });
  });

  describe("Blueprints", () => {
    it("Getting max supply of nonexistent tier fails", async () => {
      await tryCatch(lootbox.getBlueprintMaxSupply(25000, 0), errTypes.revert);
    });

    it("Getting max supply of nonexistent blueprint fails", async () => {
      await tryCatch(lootbox.getBlueprintMaxSupply(3, 2500), errTypes.revert);
    });

    it("Adding blueprint with buffer size overflowing max supply fails", async () => {
      await tryCatch(lootbox.addBlueprint(3, "Dagger", 3), errTypes.revert);
    });

    it("Adding existing blueprint fails", async () => {
      await tryCatch(lootbox.addBlueprint(5, "Sword", 5), errTypes.revert);
    });
  });

  describe("Buy ticket", () => {
    it("Buy 1 ticket and receive change back", async () => {
      const amount = 1;
      const ticketPrice = await lootbox.getTicketPrice();
      const value = BigInt(ticketPrice.toString()) * BigInt(amount) + 1n;

      const balanceBefore = await ethers.provider.getBalance(lootbox);

      const tx = await lootbox.buyTicket("appel", amount, { value });
      await tx.wait();

      const balanceAfter = await ethers.provider.getBalance(lootbox);
      expect(balanceAfter - balanceBefore).to.equal(BigInt(ticketPrice) * BigInt(amount));
    });

    it("Pop the only ticket we have", async () => {
      await lootbox.popTicket(deployer.address);
    });

    it("Pop a ticket we don't have", async () => {
      await tryCatch(lootbox.popTicket(deployer.address), errTypes.revert);
    });

    it("Buy 2 tickets with insufficient funds", async () => {
      //   const ticketPrice = await lootbox.getTicketPrice();
      const value = 1n; // insufficient
      await tryCatch(lootbox.buyTicket("appel", 2, { value }), errTypes.revert);
    });
  });

  describe("Looting", () => {
    it("First, buy 2 tickets and receive change back", async () => {
      const amount = 2;
      const ticketPrice = await lootbox.getTicketPrice();
      const value = BigInt(ticketPrice.toString()) * BigInt(amount) + 1n;

      const balanceBefore = await ethers.provider.getBalance(lootbox);

      const tx = await lootbox.buyTicket("appel", amount, { value });
      await tx.wait();

      const balanceAfter = await ethers.provider.getBalance(lootbox);
      expect(balanceAfter - balanceBefore).to.equal(BigInt(ticketPrice) * BigInt(amount));
    });

    it("Loot first ticket", async () => {
      const tx = await lootbox.loot({ from: deployer.address });
      await tx.wait();
    });

    it("Loot second ticket", async () => {
      const tx = await lootbox.loot({ from: deployer.address });
      await tx.wait();
    });

    it("Loot third nonexistent ticket => fails", async () => {
      await tryCatch(lootbox.loot({ from: deployer.address }), errTypes.revert);
    });
  });
});
