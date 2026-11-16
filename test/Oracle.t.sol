// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {Oracle, InvalidRewardBps} from "../src/Oracle.sol";

contract OracleTest is Test {
    function testRewardBpsAboveDenominatorReverts() public {
        new Oracle(address(this), "n", "d", address(1), 60, 50_000, 60, 60, 100_000, 0, 5);

        vm.expectRevert(InvalidRewardBps.selector);
        new Oracle(address(this), "n", "d", address(1), 60, 50_000, 60, 60, 100_001, 0, 5);
    }
}
