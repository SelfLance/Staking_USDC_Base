const hre = require("hardhat");

async function main() {
  const _usdc = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
  const _weth = "0x4200000000000000000000000000000000000006";
  const _router = "0x4752ba5dbc23f44d87826276bf6fd6b1c372ad24";
  const _priceFeed = "";
  const _balancerVault = "";

  const Staking = await hre.ethers.getContractFactory("PointAMM");
  const stake = await Staking.deploy(
    _usdc,
    _weth,
    _router,
    _priceFeed,
    _balancerVault
  );

  console.log("Staking Contract deployed to:", stake.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
