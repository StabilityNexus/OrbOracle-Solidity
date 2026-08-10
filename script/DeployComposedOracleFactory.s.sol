// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {ComposedOracleFactory} from "../src/ComposedOracleFactory.sol";

contract DeployComposedOracleFactory is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Composed Oracle Factory only
        ComposedOracleFactory composedFactory = new ComposedOracleFactory(deployerAddress);
        console.log("Composed Oracle Factory Deployed:", address(composedFactory));

        vm.stopBroadcast();
    }
}
