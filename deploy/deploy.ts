import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { parseEther } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  // const deployedFHECounter = await deploy("FHECounter", {
  //   from: deployer,
  //   log: true,
  // });

  const deployedLootbox = await deploy("LootBox", {
    from: deployer,
    log: true,
    args: [parseEther("0.0001")],
  });

  console.log(`LootBox contract: `, deployedLootbox.address);
};
export default func;
func.id = "deploy_lootbox"; // id required to prevent reexecution
func.tags = ["LootBox"];
