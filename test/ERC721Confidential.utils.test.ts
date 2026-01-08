import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ethers, fhevm } from "hardhat";
import { ERC721Confidential } from "../types";
import { ClearValueType, createInstance, FhevmInstance, SepoliaConfig } from "@zama-fhe/relayer-sdk/node";
import { expect } from "chai";
import { ContractTransactionReceipt } from "ethers";

export async function successWithResult(
  caller: HardhatEthersSigner,
  contract: ERC721Confidential,
  method: () => Promise<any>,
  resultEvent: string | null,
  checkers: (((pt: ClearValueType) => Chai.Assertion) | null)[] | null,
) {
  const tx = await method();
  const receipt = await tx.wait();

  const error = extractEvent("ObliviousError", contract, receipt);
  expect(error, "Error was undefined!").to.be.not.undefined;
  expect(error![0]).to.be.not.undefined;

  if (resultEvent !== null) {
    const contractCallResult = extractEvent(resultEvent, contract, receipt);
    expect(contractCallResult, "Result event was not emitted or did not emit any value!").to.be.not.undefined;

    if (!fhevm.isMock) {
      for (let i = 0; i < contractCallResult!.length; i++) {
        if (checkers![i] === null) continue;
        const ptResult = await userDecrypt(
          contractCallResult![i],
          await contract.getAddress(),
          caller,
          await createInstance(SepoliaConfig),
        );
        checkers![i]!(ptResult);
      }
    }
  }

  if (!fhevm.isMock) {
    const ptError = await userDecrypt(
      error![0],
      await contract.getAddress(),
      caller,
      await createInstance(SepoliaConfig),
    );
    expect(ptError, `An oblivious error was raised! Error bit mask: ${ptError}`).to.eq(0);
  }
}

export function extractEvent(name: string, contract: ERC721Confidential, receipt: ContractTransactionReceipt | null) {
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

export async function userDecrypt(
  ct: any,
  erc721ContractAddress: string,
  user: HardhatEthersSigner,
  instance: FhevmInstance,
) {
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

export async function printBalance(signer: HardhatEthersSigner, name: string) {
  let ethBalance = ethers.formatEther(await ethers.provider.getBalance(signer.address));
  console.log(`Balance of ${name} (${await signer.getAddress()}): ${ethBalance}`);
}
