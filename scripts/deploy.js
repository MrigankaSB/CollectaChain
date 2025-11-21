const { ethers } = require("hardhat");

async function main() {
  const CollectaChain = await ethers.getContractFactory("CollectaChain");
  const collectaChain = await CollectaChain.deploy();

  await collectaChain.deployed();

  console.log("CollectaChain contract deployed to:", collectaChain.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
