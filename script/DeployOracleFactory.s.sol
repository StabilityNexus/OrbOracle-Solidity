// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {OracleFactory} from "../src/OracleFactory.sol";

contract DeployOracleFactory is Script {
    
    OracleFactory public factory;
    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address devAddress = vm.envOr("DEV_ADDRESS", address(0xab53369e91dcFC275744DC0A30BD3E363B2785e0));
        uint256 devFee = vm.envOr("DEV_FEE", uint256(1000)); // Default 1% (1000 / 1e5)

        factory = new OracleFactory(0xab53369e91dcFC275744DC0A30BD3E363B2785e0, devAddress, devFee);

        console.log("Factory Deployed: ", address(factory));

        vm.stopBroadcast();
    }
}
