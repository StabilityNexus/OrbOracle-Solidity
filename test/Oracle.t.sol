// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Oracle, EmptyHistory} from "../src/Oracle.sol";

contract MockWeightToken is ERC20 {
    constructor() ERC20("Mock Weight Token", "MWT") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract OracleTest is Test {
    MockWeightToken private token;
    Oracle private oracle;
    address private submitter;

    function setUp() public {
        token = new MockWeightToken();
        oracle = new Oracle(address(this), "Orb/USD", "Test feed", address(token), 60, 50_000, 0, 0, 0, 60, 3);
        submitter = makeAddr("submitter");

        token.mint(submitter, 100e18);
        vm.prank(submitter);
        token.approve(address(oracle), type(uint256).max);
        vm.prank(submitter);
        oracle.depositTokens(100e18);
    }

    function testReadsMinAndMaxFromRecentHistory() public {
        _submitValues();

        (uint256 minValue, uint256 maxValue) = oracle.readValueInterval();
        assertEq(minValue, 100e18);
        assertEq(maxValue, 300e18);
        assertEq(oracle.readMinValue(), 100e18);
        assertEq(oracle.readMaxValue(), 300e18);
    }

    function testReadExtremesRevertForEmptyHistory() public {
        vm.expectRevert(EmptyHistory.selector);
        oracle.readMinValue();

        vm.expectRevert(EmptyHistory.selector);
        oracle.readMaxValue();
    }

    function _submitValues() private {
        vm.warp(block.timestamp + 1);
        vm.prank(submitter);
        oracle.submitValue(100e18);

        vm.warp(block.timestamp + 61);
        vm.prank(submitter);
        oracle.submitValue(200e18);

        vm.warp(block.timestamp + 61);
        vm.prank(submitter);
        oracle.submitValue(300e18);
    }
}
