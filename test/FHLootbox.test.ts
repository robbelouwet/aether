// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
// import { ethers } from "hardhat";
// import { FHECounter__factory, LootBox, LootBox__factory } from "../types";
// import { parseEther } from "ethers";
// import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";

// type Signers = {
//   deployer: HardhatEthersSigner;
//   alice: HardhatEthersSigner;
//   bob: HardhatEthersSigner;
// };

// async function deployFixture() {
//   const factory = (await ethers.getContractFactory("LootBox")) as LootBox__factory;
//   const lootbox = (await factory.deploy(parseEther("0.0000001"))) as LootBox;
//   const lootboxAddress = await lootbox.getAddress();

//   return { lootbox, lootboxAddress };
// }

// describe("FHECounter", function () {
//   let lootbox: LootBox;
//   let lootboxAddress: string;
//   let deployer: HardhatEthersSigner;
//   let user: HardhatEthersSigner;
//   let users: HardhatEthersSigner[];

//   beforeEach(async () => {
//     [deployer, user, ...users] = await ethers.getSigners();

//     ({ lootbox, lootboxAddress } = await deployFixture());
//   });

//   it("Loot a box", async () => {
//     const tx1 = await lootbox.loot({
//       value: parseEther("0.00000011"),
//     });
//     const receipt = await tx1.wait();

//     // Find the ClearBoxRequested event
//     const event = receipt?.logs
//       .map((log) => {
//         try {
//           return lootbox.interface.parseLog(log);
//         } catch {
//           return null;
//         }
//       })
//       .find((e) => e?.name === "ClearBoxRequested");

//     if (!event) {
//       throw new Error("ClearBoxRequested event not found");
//     }

//     const dice = event.args[0];
//     const e_blueprint_id = event.args[1];

//     console.log("dice:", dice);
//     console.log("e_blueprint_id:", e_blueprint_id);

//     const instance = await createInstance();
//     const results = await instance.publicDecrypt([dice, e_blueprint_id]);

//     const clearDice = results.clearValues[dice];
//     const blueprint = results.clearValues[e_blueprint_id];

//     const tx = await lootbox.mine(clearDice, blueprint, results.decryptionProof);
//     await tx.wait();
//   });
// });
