import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm, deployments } from "hardhat";
import { ERC721Confidential, ERC721Confidential__factory } from "../types";
import { ClearValueType, createInstance, FhevmInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
import { expect } from "chai";
import { FhevmType } from "@fhevm/hardhat-plugin";
import { AddressLike, Contract, ContractTransactionReceipt } from "ethers";
import { TypedContractMethod } from "../types/common";

type Signers = {
  deployer: HardhatEthersSigner;
  alice: HardhatEthersSigner;
  bob: HardhatEthersSigner;
};

async function deployFixture() {
  const factory = (await ethers.getContractFactory("ERC721Confidential")) as ERC721Confidential__factory;
  const erc721Contract = (await factory.deploy("Aether", "AETH")) as ERC721Confidential;
  const erc721ContractAddress = await erc721Contract.getAddress();

  return { erc721Contract, erc721ContractAddress };
}

describe("Mint for Alice and transfer to Bob", function () {
  let signers: Signers;
  let erc721Contract: ERC721Confidential;
  let erc721ContractAddress: string;
  let tokenId: bigint = ethers.toBigInt(ethers.randomBytes(32));

  before(async function () {
    if (!fhevm.isMock) {
      const ERC721Confidential = await deployments.get("ERC721Confidential");
      erc721ContractAddress = ERC721Confidential.address;
      erc721Contract = await ethers.getContractAt("ERC721Confidential", ERC721Confidential.address);

      const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
      signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2] };
    } else {
      ({ erc721Contract, erc721ContractAddress } = await deployFixture());

      const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
      signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2] };
    }
  });

  //   it(" balance Alice = 0, balance Bob = 0", async function () {
  //     const txBalance = await erc721Contract.connect(signers.alice).balanceOf(signers.alice.address);
  //     const receiptBalance = await txBalance.wait();
  //     // console.log("BalanceOf receipt: ", receiptBalance);

  //     const balanceOfError = extractEvent("ObliviousError", erc721Contract, receiptBalance);
  //     expect(balanceOfError).to.be.not.undefined;
  //     expect(balanceOfError![0]).to.be.not.undefined;
  //     // console.log("Error balanceOf:", balanceOfError);

  //     const balanceResult = extractEvent("BalanceResult", erc721Contract, receiptBalance);
  //     expect(balanceResult).to.be.not.undefined;
  //     expect(balanceResult![0]).to.be.not.undefined;
  //     // console.log("BalanceResult:", balanceResult);

  //     if (!fhevm.isMock) {
  //       const ptError = await userDecrypt(
  //         balanceOfError![0],
  //         erc721ContractAddress,
  //         signers.alice,
  //         await createInstance(SepoliaConfig),
  //       );
  //       expect(ptError).to.eq(0);
  //       // console.log("Error: ", pt);

  //       const ptBalanceResult = await userDecrypt(
  //         balanceResult![0],
  //         erc721ContractAddress,
  //         signers.alice,
  //         await createInstance(SepoliaConfig),
  //       );
  //       expect(ptBalanceResult).to.eq(0);
  //     }
  //   });

  //   it("Mint for Alice", async function () {
  //     const txTransfer = await erc721Contract.connect(signers.alice).mint(signers.alice.address, tokenId);
  //     const receiptMint = await txTransfer.wait();
  //     // console.log("mint receipt:", receiptMint);

  //     const mintError = extractEvent("ObliviousError", erc721Contract, receiptMint);

  //     expect(mintError).to.be.not.undefined;
  //     expect(mintError![0]).to.be.not.undefined;
  //     // console.log("Error mint:", mintError);

  //     if (!fhevm.isMock) {
  //       const pt = await userDecrypt(
  //         mintError![0],
  //         erc721ContractAddress,
  //         signers.alice,
  //         await createInstance(SepoliaConfig),
  //       );
  //       console.log("Error: ", pt);
  //       expect(pt).to.eq(0);
  //     }

  //     // ...
  //   });

  it("Balance Alice = 0", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callable
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
      "BalanceResult",
      (pt) => expect(pt).to.eq(0),
    );
  });

  it("Mint for Alice", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).mint(signers.alice.address, tokenId),
      null,
      null,
    );
  });

  it("Balance Alice = 1", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callable
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
      "BalanceResult",
      (pt) => expect(pt).to.eq(1),
    );
  });

  it("Transfer Alice => Bob", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callable
    await successWithResult(
      signers.alice,
      erc721Contract,
      () =>
        erc721Contract
          .connect(signers.alice)
          ["safeTransferFrom(address,address,uint256)"](signers.alice.address, signers.bob.address, tokenId),
      null,
      null,
    );
  });

  it("Balance Alice = 0", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callable
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
      "BalanceResult",
      (pt) => expect(pt).to.eq(0),
    );
  });

  it("Balance Bob = 1", async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callable
    await successWithResult(
      signers.bob,
      erc721Contract,
      () => erc721Contract.connect(signers.bob).balanceOf(signers.bob.address),
      "BalanceResult",
      (pt) => expect(pt).to.eq(1),
    );
  });
});

async function successWithResult(
  caller: HardhatEthersSigner,
  contract: ERC721Confidential,
  method: () => Promise<any>,
  resultEvent: string | null,
  checker: ((pt: ClearValueType) => Chai.Assertion) | null,
) {
  const tx = await method();
  const receipt = await tx.wait();

  const error = extractEvent("ObliviousError", contract, receipt);
  expect(error).to.be.not.undefined;
  expect(error![0]).to.be.not.undefined;

  if (resultEvent !== null) {
    const contractCallResult = extractEvent(resultEvent, contract, receipt);
    expect(contractCallResult).to.be.not.undefined;
    expect(contractCallResult![0]).to.be.not.undefined;

    if (!fhevm.isMock) {
      const ptResult = await userDecrypt(
        contractCallResult![0],
        await contract.getAddress(),
        caller,
        await createInstance(SepoliaConfig),
      );
      checker!(ptResult);
    }
  }

  if (!fhevm.isMock) {
    const ptError = await userDecrypt(
      error![0],
      await contract.getAddress(),
      caller,
      await createInstance(SepoliaConfig),
    );
    expect(ptError).to.eq(0);
  }
}

function extractEvent(name: string, contract: ERC721Confidential, receipt: ContractTransactionReceipt | null) {
  const event = receipt?.logs
    .map((log) => {
      try {
        return contract.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((e) => {
      // console.log("Found event: ", e?.name);
      return e?.name === name;
    });

  return event?.args;
}

async function userDecrypt(ct: any, erc721ContractAddress: string, user: HardhatEthersSigner, instance: FhevmInstance) {
  const keypair = instance.generateKeypair();

  const handleContractPairs = [
    {
      handle: ct,
      contractAddress: erc721ContractAddress,
    },
  ];

  const startTimeStamp = Math.floor(Date.now() / 1000).toString();
  const durationDays = "10"; // String for consistency
  const contractAddresses = [erc721ContractAddress];

  const eip712 = instance.createEIP712(keypair.publicKey, contractAddresses, startTimeStamp, durationDays);

  const signature = await user.signTypedData(
    eip712.domain,
    {
      UserDecryptRequestVerification: eip712.types.UserDecryptRequestVerification,
    },
    eip712.message,
  );

  const result = await instance.userDecrypt(
    handleContractPairs,
    keypair.privateKey,
    keypair.publicKey,
    signature.replace("0x", ""),
    contractAddresses,
    user.address,
    startTimeStamp,
    durationDays,
  );

  return result[ct];
}
