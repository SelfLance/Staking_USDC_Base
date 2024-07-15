# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```
# Deployement Steps:
npx hardht compile 
npx hardhat run ./scripts/deploy.js 
      the above is used for deploy on local hardhat network. if you want to deploy it ona nay network then check hardhat.config.js deploy on specific network or add network by adding RPC and giving you PK.
npx hardhat run ./scripts/deploy.js --network spoila_base
       --network flag specify specifc chain.. Setup requied data in .env
npx hardaht verify "Contract_Address" "constructor Params in hirarchy" --network spoila_base

