// import { expect } from "chai";
// import { ethers } from "hardhat";
// import { LootBox } from "../types";
// import { parseEther } from "ethers";
// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

// describe("LootBox", function () {
//   let lootbox: LootBox;
//   let deployer: HardhatEthersSigner;
//   let user: HardhatEthersSigner;
//   let users: HardhatEthersSigner[];

//   before(async () => {
//     [deployer, user, ...users] = await ethers.getSigners();
//     const LootBoxFactory = await ethers.getContractFactory("LootBox", deployer);
//     lootbox = await LootBoxFactory.deploy(parseEther("0.0000001"));
//   });

//   describe("Setup blueprints", () => {
//     it('Add "Normal" items', async () => {
//       await lootbox.addBlueprint(2, "Sword", 5);
//       await lootbox.addBlueprint(2, "Pickaxe", 5);
//       await lootbox.addBlueprint(2, "Axe", 5);
//     });

//     it('Add "Common" items', async () => {
//       await lootbox.addBlueprint(5, "Sword", 5);
//       await lootbox.addBlueprint(5, "Pickaxe", 5);
//       await lootbox.addBlueprint(5, "Axe", 5);
//     });

//     it('Add "Uncommon" items', async () => {
//       await lootbox.addBlueprint(20, "Sword", 5);
//       await lootbox.addBlueprint(20, "Pickaxe", 5);
//       await lootbox.addBlueprint(20, "Axe", 5);
//     });

//     it('Add "Legendary" blueprints', async () => {
//       await lootbox.addBlueprint(50, "Flaming Sword", 10);
//       await lootbox.addBlueprint(50, "Shadow Dagger", 10);
//       await lootbox.addBlueprint(50, "Nexus", 10);
//     });

//     it('Add "Exotic" blueprints', async () => {
//       await lootbox.addBlueprint(100, "Flaming Sword", 10);
//       await lootbox.addBlueprint(100, "Shadow Dagger", 10);
//       await lootbox.addBlueprint(100, "Nexus", 10);
//     });
//   });

//   describe("Looting", () => {
//     it("Loot with invalid seed fails", async () => {
//       await expect(lootbox.connect(deployer).loot()).to.be.rejectedWith("Invalid seed, no ticket found!");
//     });

//     it("Loot ticket after previous loot fails", async () => {
//       await lootbox.connect(deployer).loot();
//     });

//     it("Loot nonexistent ticket after previous loot fails", async () => {
//       await expect(lootbox.connect(deployer).loot()).to.be.rejectedWith("Invalid seed, no ticket found!");
//     });
//   });
// });
