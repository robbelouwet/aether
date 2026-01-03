import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm, deployments } from "hardhat";
import { ERC721Confidential, ERC721Confidential__factory } from "../types";
import { createInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/bundle";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { Contract, ContractTransactionReceipt } from "ethers";

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
};

describe("ERC721Confidential", function () {
  let signers: Signers;
  let erc721Contract: ERC721Confidential;
  let erc721ContractAddress: string;

  before(async function () {
    if (fhevm.isMock) {
      console.warn(`This hardhat test suite can only run on Sepolia Testnet`);
      this.skip();
    }

    try {
      const ERC721Confidential = await deployments.get("ERC721Confidential");
      erc721ContractAddress = ERC721Confidential.address;
      erc721Contract = await ethers.getContractAt("ERC721Confidential", ERC721Confidential.address);
    } catch (e) {
      (e as Error).message += ". Call 'npx hardhat deploy --network sepolia'";
      throw e;
    }

    const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
    signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2] };
  });

  it("Test NFT mint", async function () {
    // console.log("deployer(", signers.deployer.address, ")", await ethers.provider.getBalance(signers.deployer.address));
    // console.log("alice (", signers.alice.address, ")", await ethers.provider.getBalance(signers.alice.address));
    // console.log("bob(", signers.bob.address, ")", await ethers.provider.getBalance(signers.bob.address));

    const tokenId = ethers.toBigInt(ethers.randomBytes(32));

    const txTransfer = await erc721Contract
      .connect(signers.alice)
      ["safeTransferFrom(address,address,uint256)"](ethers.ZeroAddress, signers.bob.address, tokenId);
    const receipt = await txTransfer.wait();

    const args = extraceEvent("ObliviousError", erc721Contract, receipt);
    console.log(args);

    // console.log(receipt);

    // const tx = await fheAetherContract.connect(signers.bob).balanceOf(signers.bob.address);
    // await tx.wait();
    // console.log(tx);
    // const instance = await createInstance(SepoliaConfig);

    // const keypair = instance.generateKeypair();

    // const handleContractPairs = [
    //   {
    //     handle: e_balanceAfter,
    //     contractAddress: fheAetherContractAddress,
    //   },
    // ];

    // const startTimeStamp = Math.floor(Date.now() / 1000).toString();
    // const durationDays = "10"; // String for consistency
    // const contractAddresses = [contractAddress];

    // const eip712 = instance.createEIP712(keypair.publicKey, contractAddresses, startTimeStamp, durationDays);

    // const signature = await signers.bob.signTypedData(
    //   eip712.domain,
    //   {
    //     UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification,
    //   },
    //   eip712.message,
    // );

    // const result = await instance.userDecrypt(
    //   handleContractPairs,
    //   keypair.privateKey,
    //   keypair.publicKey,
    //   signature.replace("0x", ""),
    //   contractAddresses,
    //   signers.bob.address,
    //   startTimeStamp,
    //   durationDays,
    // );

    // const decryptedValue = result[e_balanceAfter];

    // verify...
  });

  // it("increment the counter by 1", async function () {
  //   const encryptedCountBeforeInc = await fheAetherContract.getCount();
  //   expect(encryptedCountBeforeInc).to.eq(ethers.ZeroHash);
  //   const clearCountBeforeInc = 0;

  //   // Encrypt constant 1 as a euint32
  //   const clearOne = 1;
  //   const encryptedOne = await fhevm
  //     .createEncryptedInput(fheAetherContractAddress, signers.alice.address)
  //     .add32(clearOne)
  //     .encrypt();

  //   const tx = await fheAetherContract
  //     .connect(signers.alice)
  //     .increment(encryptedOne.handles[0], encryptedOne.inputProof);
  //   await tx.wait();

  //   const encryptedCountAfterInc = await fheAetherContract.getCount();
  //   const clearCountAfterInc = await fhevm.userDecryptEuint(
  //     FhevmType.euint32,
  //     encryptedCountAfterInc,
  //     fheAetherContractAddress,
  //     signers.alice,
  //   );

  //   expect(clearCountAfterInc).to.eq(clearCountBeforeInc + clearOne);
  // });

  // it("decrement the counter by 1", async function () {
  //   // Encrypt constant 1 as a euint32
  //   const clearOne = 1;
  //   const encryptedOne = await fhevm
  //     .createEncryptedInput(fheAetherContractAddress, signers.alice.address)
  //     .add32(clearOne)
  //     .encrypt();

  //   // First increment by 1, count becomes 1
  //   let tx = await fheAetherContract.connect(signers.alice).increment(encryptedOne.handles[0], encryptedOne.inputProof);
  //   await tx.wait();

  //   // Then decrement by 1, count goes back to 0
  //   tx = await fheAetherContract.connect(signers.alice).decrement(encryptedOne.handles[0], encryptedOne.inputProof);
  //   await tx.wait();

  //   const encryptedCountAfterDec = await fheAetherContract.getCount();
  //   const clearCountAfterInc = await fhevm.userDecryptEuint(
  //     FhevmType.euint32,
  //     encryptedCountAfterDec,
  //     fheAetherContractAddress,
  //     signers.alice,
  //   );

  //   expect(clearCountAfterInc).to.eq(0);
  // });
});

function extraceEvent(name: string, contract: ERC721Confidential, receipt: ContractTransactionReceipt | null) {
  const event = receipt?.logs
    .map((log) => {
      try {
        return contract.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((e) => e?.name === name);

  return event?.args;
}
