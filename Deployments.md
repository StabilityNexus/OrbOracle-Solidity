# Deployments

All deployments of contracts in this repo, including test/beta versions, are documented in this file. 
This file lists the addresses of the contracts that have been deployed 
as well as the constructor parameters that have been used.


| Network | Network ID | Version | Contract `OracleFactory.sol` Address | Contract `OracleFactory.sol` Parameters | Contract `ComposedOracleFactory.sol` Address | Contract `ComposedOracleFactory.sol` Parameters | Comments |
|---|---|---|---|---|---|---|---|
| Sepolia (Testnet) | 11155111 | [v0.0.1](https://github.com/StabilityNexus/OrbOracle-Solidity/tree/main) | `0xB3134111A1C33E5d879AE18cC2d386B2386BBE73` | `initialOwner = 0x365f66748c2F318b0593397f1a446e01Ec006B22` | `0xB790B846221e82373d7d5121F1901DD31B0f6496` | `initialOwner = 0x365f66748c2F318b0593397f1a446e01Ec006B22` | Deployed and verified on Sepolia testnet |


---
**Note to Developers:** After making a new deployment, please:
1. create a git tag for the deployed version;
2. add a new row to the table above with the details of the deployment.

---

## Deployed Supporting Libraries & Oracles

### Supporting Libraries
* **DecayLib:** [`0x7a1F06E6A6e27DcEd4eD9D5E64DD1eD130019C2D`](https://sepolia.etherscan.io/address/0x7a1F06E6A6e27DcEd4eD9D5E64DD1eD130019C2D)
* **GovernanceLib:** [`0x8cd1bd04231F558ECa7EbbB53c950B239250f5A3`](https://sepolia.etherscan.io/address/0x8cd1bd04231F558ECa7EbbB53c950B239250f5A3)

### Deployed Test Feeds (Sepolia Testnet)
* **WETH Weight Token:** [`0xfff9976782d46cc05630d1f6ebab18b2324d6b14`](https://sepolia.etherscan.io/address/0xfff9976782d46cc05630d1f6ebab18b2324d6b14) (Sepolia WETH9)
* **Base Oracle A (Feed A):** [`0xff2b1fca4aF0c9BCb576178e6989AA92819a0294`](https://sepolia.etherscan.io/address/0xff2b1fca4aF0c9BCb576178e6989AA92819a0294)
* **Base Oracle B (Feed B):** [`0x91818da4355d68BF1f76B00B53548E42d9e07935`](https://sepolia.etherscan.io/address/0x91818da4355d68BF1f76B00B53548E42d9e07935)
* **Composed Oracle (Multiplication):** [`0x3554D1feF9c95976634C2B9518790F146a6aa56A`](https://sepolia.etherscan.io/address/0x3554D1feF9c95976634C2B9518790F146a6aa56A)

---

## Deployment Instructions

To execute this deployment again using Foundry:
1. Set your private key in `.env`:
   ```env
   PRIVATE_KEY=0x...
   ```
2. Execute the Forge deployment scripts:
   ```bash
   source .env
   # Deploy Base Oracle Factory
   forge script script/DeployOracleFactory.s.sol:DeployOracleFactory --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast

   # Deploy Composed Oracle Factory
   forge script script/DeployComposedOracleFactory.s.sol:DeployComposedOracleFactory --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
   ```
