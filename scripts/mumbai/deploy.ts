import { ethers } from "hardhat";
import "dotenv/config";
import dedent from "dedent";

async function main() {
  const PhalaFlexContract = await ethers.getContractFactory("PhalaFlex");

  const [deployer] = await ethers.getSigners();

  console.log("Deploying...");
  const attestor =
    process.env["MUMBAI_LENSAPI_ORACLE_ENDPOINT"] || deployer.address; // When deploy for real e2e test, change it to the real attestor wallet.
  const consumer = await PhalaFlexContract.deploy(attestor);
  await consumer.deployed();
  const finalMessage = dedent`
    🎉 Your Consumer Contract has been deployed, check it out here: https://mumbai.polygonscan.com/address/${consumer.address}
    
    You also need to set up the consumer contract address in your .env file:
    
    MUMBAI_CONSUMER_CONTRACT_ADDRESS=${consumer.address}
  `;
  console.log(`\n${finalMessage}\n`);

  // console.log("Sending a request...");
  // await consumer.connect(deployer).request("0x01");
  // console.log("Done");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
