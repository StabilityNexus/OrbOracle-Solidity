# Orb Oracle Deployments

This document lists the test/beta deployment details for the Orb Oracle contracts.

## Scroll Sepolia Testnet

* **Chain ID:** 534351
* **RPC URL:** `https://sepolia-rpc.scroll.io`

### 1. Base Oracle Factory
* **Contract Address:** `[INSERT_BASE_FACTORY_ADDRESS_HERE]`
* **Constructor Parameters:**
  * `initialOwner` (address): `[INSERT_DEPLOYER_ADDRESS_HERE]` (sets the deployer as the factory owner)

### 2. Composed Oracle Factory
* **Contract Address:** `[INSERT_COMPOSED_FACTORY_ADDRESS_HERE]`
* **Constructor Parameters:**
  * `initialOwner` (address): `[INSERT_DEPLOYER_ADDRESS_HERE]` (sets the deployer as the factory owner)

---

## Deployment Instructions

To execute this deployment again or verify:
1. Ensure your `.env` file contains your private key:
   ```env
   PRIVATE_KEY=0x...
   ```
2. Run the deployment script:
   ```bash
   source .env
   forge script script/DeployAll.s.sol:DeployAll --rpc-url https://sepolia-rpc.scroll.io --broadcast
   ```
