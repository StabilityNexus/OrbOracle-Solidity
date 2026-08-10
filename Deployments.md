# Orb Oracle Deployments

This document lists the test/beta deployment details for the Orb Oracle contracts.

## Ethereum Sepolia Testnet

* **Chain ID:** 11155111
* **RPC URL:** `https://ethereum-sepolia-rpc.publicnode.com`
* **Explorer:** `https://sepolia.etherscan.io`

### 1. Base Oracle Factory
* **Contract:** `OracleFactory`
* **Contract Address:** [`0xB3134111A1C33E5d879AE18cC2d386B2386BBE73`](https://sepolia.etherscan.io/address/0xB3134111A1C33E5d879AE18cC2d386B2386BBE73)
* **Deployment Tx:** [`0xe82e25be49fa0bcf83db98b505eec6d3280789fe0f63392baaf328f1c241509c`](https://sepolia.etherscan.io/tx/0xe82e25be49fa0bcf83db98b505eec6d3280789fe0f63392baaf328f1c241509c)
* **Constructor Parameters:**
  * `initialOwner` (address): [`0x365f66748c2F318b0593397f1a446e01Ec006B22`](https://sepolia.etherscan.io/address/0x365f66748c2F318b0593397f1a446e01Ec006B22) (sets the deployer as the factory owner)

### 2. Composed Oracle Factory
* **Contract:** `ComposedOracleFactory`
* **Contract Address:** [`0xB790B846221e82373d7d5121F1901DD31B0f6496`](https://sepolia.etherscan.io/address/0xB790B846221e82373d7d5121F1901DD31B0f6496)
* **Deployment Tx:** [`0x8a9981cb467e710df0caef9548cd1a875f6cdb03554859cd4f1aa91135f7655b`](https://sepolia.etherscan.io/tx/0x8a9981cb467e710df0caef9548cd1a875f6cdb03554859cd4f1aa91135f7655b)
* **Constructor Parameters:**
  * `initialOwner` (address): [`0x365f66748c2F318b0593397f1a446e01Ec006B22`](https://sepolia.etherscan.io/address/0x365f66748c2F318b0593397f1a446e01Ec006B22) (sets the deployer as the factory owner)

### 3. Supporting Libraries
* **DecayLib:** [`0x7a1F06E6A6e27DcEd4eD9D5E64DD1eD130019C2D`](https://sepolia.etherscan.io/address/0x7a1F06E6A6e27DcEd4eD9D5E64DD1eD130019C2D)
* **GovernanceLib:** [`0x8cd1bd04231F558ECa7EbbB53c950B239250f5A3`](https://sepolia.etherscan.io/address/0x8cd1bd04231F558ECa7EbbB53c950B239250f5A3)

### 4. Deployed Test Feeds (For Evaluators)

To facilitate immediate testing and evaluation of the system, we have deployed and verified a complete sandboxed environment on Sepolia:

* **WETH Weight Token (Staking/Deposits):** [`0xfff9976782d46cc05630d1f6ebab18b2324d6b14`](https://sepolia.etherscan.io/address/0xfff9976782d46cc05630d1f6ebab18b2324d6b14) (Standard Sepolia WETH9)
* **Base Oracle A (Feed A):** [`0xff2b1fca4aF0c9BCb576178e6989AA92819a0294`](https://sepolia.etherscan.io/address/0xff2b1fca4aF0c9BCb576178e6989AA92819a0294)
* **Base Oracle B (Feed B):** [`0x91818da4355d68BF1f76B00B53548E42d9e07935`](https://sepolia.etherscan.io/address/0x91818da4355d68BF1f76B00B53548E42d9e07935)
* **Composed Oracle (Multiplication - A * B / 1e18):** [`0x3554D1feF9c95976634C2B9518790F146a6aa56A`](https://sepolia.etherscan.io/address/0x3554D1feF9c95976634C2B9518790F146a6aa56A)

---

## Deployment Instructions

To execute this deployment again or verify:
1. Ensure your `.env` file contains your private key:
   ```env
   PRIVATE_KEY=0x...
   ```
2. Run the deployment scripts for the factories:
   ```bash
   source .env
   # Deploy Base Oracle Factory
   forge script script/DeployOracleFactory.s.sol:DeployOracleFactory --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast

   # Deploy Composed Oracle Factory
   forge script script/DeployComposedOracleFactory.s.sol:DeployComposedOracleFactory --rpc-url https://ethereum-sepolia-rpc.publicnode.com --broadcast
   ```
