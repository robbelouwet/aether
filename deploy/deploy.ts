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

  const deployedAether = await deploy("ERC721Confidential", {
    from: deployer,
    log: true,
    args: ["Aether", "AETH"],
  });

  console.log(`Aether contract: `, deployedAether.address);
};
export default func;
func.id = "deploy_aether"; // id required to prevent reexecution
func.tags = ["Aether"];
