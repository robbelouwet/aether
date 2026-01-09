import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm, deployments } from "hardhat";
import { ERC721Confidential, ERC721Confidential__factory } from "../../types";
import { expect } from "chai";
import { addressToName, printBalance, successWithResult, type Signers } from "../ERC721Confidential.utils.test";

let signers: Signers;
let erc721Contract: ERC721Confidential;
let erc721ContractAddress: string;
let tokenId: bigint = ethers.toBigInt(ethers.randomBytes(32));

async function deployFixture() {
  const factory = (await ethers.getContractFactory("ERC721Confidential")) as ERC721Confidential__factory;
  const erc721Contract = (await factory.deploy("Aether", "AETH")) as ERC721Confidential;
  const erc721ContractAddress = await erc721Contract.getAddress();

  return { erc721Contract, erc721ContractAddress };
}

const isMockPrefix = fhevm.isMock ? "No revert: " : "";

describe("Success scenario 1", function () {
  before("Deploying contract", async function () {
    if (!fhevm.isMock) {
      const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
      signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2], eve: ethSigners[3] };

      // Force redeployment on sepolia
      await deployments.fixture([], {
        keepExistingDeployments: false,
      });

      const deployment = await deployments.deploy("ERC721Confidential", {
        from: signers.deployer.address,
        args: ["Aether", "AETH"],
        log: true,
        skipIfAlreadyDeployed: false,
      });

      erc721ContractAddress = deployment.address;
      erc721Contract = await ethers.getContractAt("ERC721Confidential", deployment.address, signers.deployer);

      // console.log("Contract at: ", erc721ContractAddress);
      // const ERC721Confidential = await deployments.get("ERC721Confidential");
      // erc721ContractAddress = ERC721Confidential.address;
      // erc721Contract = await ethers.getContractAt("ERC721Confidential", ERC721Confidential.address);
    } else {
      ({ erc721Contract, erc721ContractAddress } = await deployFixture());

      const ethSigners: HardhatEthersSigner[] = await ethers.getSigners();
      signers = { deployer: ethSigners[0], alice: ethSigners[1], bob: ethSigners[2], eve: ethSigners[3] };
    }

    // console.log("Contract address:", erc721ContractAddress);
    await printBalance(signers.deployer, "Deployer");
    await printBalance(signers.alice, "Alice");
    await printBalance(signers.bob, "Bob");
    await printBalance(signers.eve, "Eve");
  });
  it(`${isMockPrefix} Balance Alice = 0`, async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
      "BalanceResult",
      [(pt) => expect(pt).to.eq(0)],
    );
  });

  it(`${isMockPrefix} Mint for Alice`, async function () {
    // Call the method, fetch the error, and assert the error is an all-zero bitarray
    await successWithResult(
      signers.alice,
      erc721Contract,
      () => erc721Contract.connect(signers.alice).mint(signers.alice.address, tokenId),
      "ObliviousTransfer",
      [
        // First arg of ObliviousTransfer event should be zero addr, second is alice's addr, third is the tokenId (we're minting!)
        (pt) => expect(pt, `Expected 0x0 but got ${addressToName(pt, signers)}`).to.eq(ethers.ZeroAddress),
        (pt) => expect(pt, `Expected Alice but got ${addressToName(pt, signers)}`).to.eq(signers.alice.address),
        (pt) => expect(pt).to.eq(tokenId),
      ],
    );
  });

  describe("Transfer Alice => Bob", async function () {
    it("Balance Alice = 1", async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.alice,
        erc721Contract,
        () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
        "BalanceResult",
        [(pt) => expect(pt).to.eq(1)],
      );
    });

    it("Owner of token => Alice", async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.alice,
        erc721Contract,
        () => erc721Contract.connect(signers.alice).ownerOf(tokenId),
        "OwnerResult",
        [(pt) => expect(pt, `Expected Alice but got ${addressToName(pt, signers)}`).to.eq(signers.alice.address)],
      );
    });

    it(`${isMockPrefix} Transfer Alice => Bob`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "ObliviousTransfer" event from the receipt, and evaluate its values using the callables
      await successWithResult(
        signers.alice,
        erc721Contract,
        () =>
          erc721Contract
            .connect(signers.alice)
            ["safeTransferFrom(address,address,uint256)"](signers.alice.address, signers.bob.address, tokenId),
        "ObliviousTransfer",
        [
          // First arg of ObliviousTransfer event should be alice's addr, second is bob's addr, third is the tokenId
          (pt) => expect(pt, `Expected Alice but got ${addressToName(pt, signers)}`).to.eq(signers.alice.address),
          (pt) => expect(pt, `Expected Bob but got ${addressToName(pt, signers)}`).to.eq(signers.bob.address),
          (pt) => expect(pt).to.eq(tokenId),
        ],
      );
    });

    it("Owner of token => Bob", async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.bob,
        erc721Contract,
        () => erc721Contract.connect(signers.bob).ownerOf(tokenId),
        "OwnerResult",
        [(pt) => expect(pt, `Expected Bob but got ${addressToName(pt, signers)}`).to.eq(signers.bob.address)],
      );
    });
  });

  describe("Approve Eve for Bob's token", async function () {
    it(`${isMockPrefix} Balance Alice = 0`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.alice,
        erc721Contract,
        () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
        "BalanceResult",
        [(pt) => expect(pt).to.eq(0)],
      );
    });

    it(`${isMockPrefix} Balance Bob = 1`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.bob,
        erc721Contract,
        () => erc721Contract.connect(signers.bob).balanceOf(signers.bob.address),
        "BalanceResult",
        [(pt) => expect(pt).to.eq(1)],
      );
    });

    it(`${isMockPrefix} Approve Eve`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      const resp = await successWithResult(
        signers.bob,
        erc721Contract,
        () => erc721Contract.connect(signers.bob).setApprovalForAll(signers.eve.address, true),
        "ObliviousApprovalForAll",
        [
          (pt) => expect(pt, `Expected Bob but got ${addressToName(pt, signers)}`).to.eq(signers.bob.address),
          null, // is a plaintext address, we don't want to decrypt
          (pt) => expect(pt).to.be.true,
        ],
      );

      expect(resp![1], "Operator incorrect!").to.eq(signers.eve.address);
    });

    it(`${isMockPrefix} Eve is approved for all of Bob's tokens`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      const resp = await successWithResult(
        signers.eve,
        erc721Contract,
        () => erc721Contract.connect(signers.eve).isApprovedForAll(signers.bob.address, signers.eve.address),
        "ObliviousApprovalForAll",
        [
          (pt) => expect(pt, `Expected Bob but got ${addressToName(pt, signers)}`).to.eq(signers.bob.address),
          null,
          (pt) => expect(pt).to.be.true,
        ],
      );

      expect(resp![1], "Operator incorrect!").to.eq(signers.eve.address);
    });

    it(`${isMockPrefix} Eve transfers Bob's token back to Alice`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.eve,
        erc721Contract,
        () =>
          erc721Contract
            .connect(signers.eve)
            ["safeTransferFrom(address,address,uint256)"](signers.bob.address, signers.alice.address, tokenId),
        "ObliviousTransfer",
        [
          // First arg of ObliviousTransfer event should be alice's addr, second is bob's addr, third is the tokenId
          (pt) => expect(pt, `Expected Bob but got ${addressToName(pt, signers)}`).to.eq(signers.bob.address),
          (pt) => expect(pt, `Expected Alice but got ${addressToName(pt, signers)}`).to.eq(signers.alice.address),
          (pt) => expect(pt).to.eq(tokenId),
        ],
      );
    });

    it(`${isMockPrefix} Balance Bob = 0`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.bob,
        erc721Contract,
        () => erc721Contract.connect(signers.bob).balanceOf(signers.bob.address),
        "BalanceResult",
        [(pt) => expect(pt).to.eq(0)],
      );
    });

    it(`${isMockPrefix} Balance Alice = 1`, async function () {
      // Call the method, fetch the error, and assert the error is an all-zero bitarray
      // Also fetch a "BalanceResult" event from the receipt, and evaluate its value using the callables
      await successWithResult(
        signers.alice,
        erc721Contract,
        () => erc721Contract.connect(signers.alice).balanceOf(signers.alice.address),
        "BalanceResult",
        [(pt) => expect(pt).to.eq(1)],
      );
    });
  });
});
