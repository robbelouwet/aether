// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
// import { ethers, fhevm, deployments } from "hardhat";
// import { ERC721Confidential, ERC721Confidential__factory } from "../types";
// import { createInstance, FhevmInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
// import { expect } from "chai";
// import { FhevmType } from "@fhevm/hardhat-plugin";
// import { Contract, ContractTransactionReceipt } from "ethers";

// type Signers = {
//   deployer: HardhatEthersSigner;
//   alice: HardhatEthersSigner;
//   bob: HardhatEthersSigner;
// };

// describe("ERC721Confidential", function () {
//   let signers: Signers;
//   let erc721Contract: ERC721Confidential;
//   let erc721ContractAddress: string;
//   let tokenId: bigint = ethers.toBigInt(ethers.randomBytes(32));

//   before(async function () {
//     if (fhevm.isMock) {
//       console.warn(`This hardhat test suite can only run on Sepolia Testnet`);
//       this.skip();
//     }

//     await printBalances(signers);
//   });

//   it("Test NFT mint", async function () {
//     const txTransfer = await erc721Contract.connect(signers.alice).mint(signers.alice.address, tokenId);
//     const receiptMint = await txTransfer.wait();
//     // console.log("mint receipt:", receiptMint);

//     const args = extractEvent("ObliviousError", erc721Contract, receiptMint);

//     expect(args).to.be.not.undefined;
//     expect(args![0]).to.be.not.undefined;
//     // console.log(args![0]);

//     const pt = await userDecrypt(args![0], erc721ContractAddress, signers.alice, await createInstance(SepoliaConfig));
//     // console.log("Error: ", pt);

//     expect(pt).to.eq(0);

//     // verify...
//   });

//   it("Verify balance after mint", async function () {
//     const txBalance = await erc721Contract.connect(signers.alice).balanceOf(signers.alice.address);
//     const receiptBalance = await txBalance.wait();
//     // console.log("BalanceOf receipt: ", receiptBalance);

//     const args = extractEvent("ObliviousError", erc721Contract, receiptBalance);
//     expect(args).to.be.not.undefined;
//     expect(args![0]).to.be.not.undefined;

//     const pt = await userDecrypt(args![0], erc721ContractAddress, signers.alice, await createInstance(SepoliaConfig));
//     // console.log("Plaintext error balanceOf: ", pt);

//     expect(pt).to.eq(0);
//   });

//   // it("increment the counter by 1", async function () {
//   //   const encryptedCountBeforeInc = await fheAetherContract.getCount();
//   //   expect(encryptedCountBeforeInc).to.eq(ethers.ZeroHash);
//   //   const clearCountBeforeInc = 0;

//   //   // Encrypt constant 1 as a euint32
//   //   const clearOne = 1;
//   //   const encryptedOne = await fhevm
//   //     .createEncryptedInput(fheAetherContractAddress, signers.alice.address)
//   //     .add32(clearOne)
//   //     .encrypt();

//   //   const tx = await fheAetherContract
//   //     .connect(signers.alice)
//   //     .increment(encryptedOne.handles[0], encryptedOne.inputProof);
//   //   await tx.wait();

//   //   const encryptedCountAfterInc = await fheAetherContract.getCount();
//   //   const clearCountAfterInc = await fhevm.userDecryptEuint(
//   //     FhevmType.euint32,
//   //     encryptedCountAfterInc,
//   //     fheAetherContractAddress,
//   //     signers.alice,
//   //   );

//   //   expect(clearCountAfterInc).to.eq(clearCountBeforeInc + clearOne);
//   // });

//   // it("decrement the counter by 1", async function () {
//   //   // Encrypt constant 1 as a euint32
//   //   const clearOne = 1;
//   //   const encryptedOne = await fhevm
//   //     .createEncryptedInput(fheAetherContractAddress, signers.alice.address)
//   //     .add32(clearOne)
//   //     .encrypt();

//   //   // First increment by 1, count becomes 1
//   //   let tx = await fheAetherContract.connect(signers.alice).increment(encryptedOne.handles[0], encryptedOne.inputProof);
//   //   await tx.wait();

//   //   // Then decrement by 1, count goes back to 0
//   //   tx = await fheAetherContract.connect(signers.alice).decrement(encryptedOne.handles[0], encryptedOne.inputProof);
//   //   await tx.wait();

//   //   const encryptedCountAfterDec = await fheAetherContract.getCount();
//   //   const clearCountAfterInc = await fhevm.userDecryptEuint(
//   //     FhevmType.euint32,
//   //     encryptedCountAfterDec,
//   //     fheAetherContractAddress,
//   //     signers.alice,
//   //   );

//   //   expect(clearCountAfterInc).to.eq(0);
//   // });
// });

// function extractEvent(name: string, contract: ERC721Confidential, receipt: ContractTransactionReceipt | null) {
//   const event = receipt?.logs
//     .map((log) => {
//       try {
//         return contract.interface.parseLog(log);
//       } catch {
//         return null;
//       }
//     })
//     .find((e) => e?.name === name);

//   return event?.args;
// }

// async function userDecrypt(ct: any, erc721ContractAddress: string, user: HardhatEthersSigner, instance: FhevmInstance) {
//   const keypair = instance.generateKeypair();

//   const handleContractPairs = [
//     {
//       handle: ct,
//       contractAddress: erc721ContractAddress,
//     },
//   ];

//   const startTimeStamp = Math.floor(Date.now() / 1000).toString();
//   const durationDays = "10"; // String for consistency
//   const contractAddresses = [erc721ContractAddress];

//   const eip712 = instance.createEIP712(keypair.publicKey, contractAddresses, startTimeStamp, durationDays);

//   const signature = await user.signTypedData(
//     eip712.domain,
//     {
//       UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification,
//     },
//     eip712.message,
//   );

//   const result = await instance.userDecrypt(
//     handleContractPairs,
//     keypair.privateKey,
//     keypair.publicKey,
//     signature.replace("0x", ""),
//     contractAddresses,
//     user.address,
//     startTimeStamp,
//     durationDays,
//   );

//   return result[ct];
// }

// async function printBalances(signers: Signers) {
//   console.log(
//     "deployer(",
//     signers.deployer.address,
//     ")",
//     ethers.formatEther(await ethers.provider.getBalance(signers.deployer.address)),
//   );
//   console.log(
//     "alice (",
//     signers.alice.address,
//     ")",
//     ethers.formatEther(await ethers.provider.getBalance(signers.alice.address)),
//   );
//   console.log(
//     "bob(",
//     signers.bob.address,
//     ")",
//     ethers.formatEther(await ethers.provider.getBalance(signers.bob.address)),
//   );
// }
