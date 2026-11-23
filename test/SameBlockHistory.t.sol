// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Oracle} from "../src/Oracle.sol";

contract MockHistoryToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SameBlockHistoryTest is Test {
    MockHistoryToken token;
    Oracle oracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockHistoryToken();

        oracle = new Oracle(address(this), "Test Oracle", "History Test", address(token), 3600, 1e5, 60, 0, 0, 1, 1);

        token.mint(alice, 1 ether);
        token.mint(bob, 1 ether);

        vm.startPrank(alice);
        token.approve(address(oracle), type(uint256).max);
        oracle.depositTokens(1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(oracle), type(uint256).max);
        oracle.depositTokens(1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 61);
    }

    function testSameTimestampSubmissionsCreateSingleHistoryEntry() public {
        vm.prank(alice);
        oracle.submitValue(3000 ether);

        vm.prank(bob);
        oracle.submitValue(3100 ether);

        assertEq(oracle.getPriceHistoryLength(), 1);

        (uint256[] memory timestamps, uint256[] memory aggregatedPrices, uint256[] memory latestValues) =
            oracle.getPriceHistoryRange(0, 1);

        assertEq(timestamps.length, 1);
        assertEq(aggregatedPrices[0], 3050 ether);
        assertEq(latestValues[0], 3100 ether);
    }

    function testDifferentTimestampsCreateSeparateHistoryEntries() public {
        vm.prank(alice);
        oracle.submitValue(3000 ether);

        vm.warp(block.timestamp + 1);

        vm.prank(bob);
        oracle.submitValue(3100 ether);

        assertEq(oracle.getPriceHistoryLength(), 2);

        (uint256[] memory timestamps,,) = oracle.getPriceHistoryRange(0, 2);

        assertTrue(timestamps[0] < timestamps[1]);
    }
}
