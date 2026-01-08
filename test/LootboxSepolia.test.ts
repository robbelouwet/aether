// import { ethers } from "hardhat";
// import { LootBox } from "../types";
// import { tryCatch, errTypes } from "../helpers/errors";
// import { parseEther } from "ethers";
// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

// describe("LootBox", function () {
//   this.timeout(120000); // 2 min timeout for Sepolia

//   let lootbox: LootBox;
//   let deployer: HardhatEthersSigner;
//   let user: HardhatEthersSigner;
//   let users: HardhatEthersSigner[];

//   before(async () => {
//     [deployer, user, ...users] = await ethers.getSigners();
//     const LootBoxFactory = await ethers.getContractFactory("LootBox", deployer);
//     lootbox = (await LootBoxFactory.deploy(parseEther("0.0000001"))) as LootBox;
//   });

//   describe("Success 1", () => {
//     it("Adding Wooden sword", async () => {
//       const tx = await lootbox.addBlueprint(2, "Wooden Sword", 1000);
//       console.log(tx.hash);
//     });

//     it("(fails) Loot illegal ticket", async () => {
//       await tryCatch(lootbox.loot(), errTypes.revert);
//     });

//     it("Loot ticket", async () => {
//       const tx = await lootbox.loot();
//       await tx.wait();

//       console.log(tx.hash);
//     });
//   });
// });
