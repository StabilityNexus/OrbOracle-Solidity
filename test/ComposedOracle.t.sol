// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ComposedOracle} from "../src/ComposedOracle.sol";

contract MockOracle {
    int256 private price;

    constructor(int256 _price) {
        price = _price;
    }

    function readValue() external view returns (int256) {
        return price;
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}

contract ComposedOracleTest is Test {
    MockOracle public feedA;
    MockOracle public feedB;

    function setUp() public {
        feedA = new MockOracle(0);

        feedB = new MockOracle(0);
    }

    function testMultiplication() public {
        feedA.setPrice(6);
        feedB.setPrice(2);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            0,
            false,
            0,
            0
        );

        assertEq(composed.readValue(), 12 * 1e18);
    }

    function testDivision() public {
        feedA.setPrice(6);
        feedB.setPrice(2);
        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            1,
            false,
            0,
            0
        );

        assertEq(composed.readValue(), 3 * 1e18);
    }

    function testMultiplicationDifferentDecimals() public {
        feedA.setPrice(1 * 10 ** 8);
        feedB.setPrice(3000 * 10 ** 18);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            0,
            false,
            8,
            18
        );

        assertEq(composed.readValue(), 3000 * 1e18);
    }

    function testDivisionDifferentDecimals() public {
        feedA.setPrice(3000 * 10 ** 18);
        feedB.setPrice(100000 * 10 ** 8);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            1,
            false,
            18,
            8
        );

        assertEq(composed.readValue(), 3 * 10 ** 16);
    }

    function testDivisionByZeroRevert() public {
        feedA.setPrice(10);
        feedB.setPrice(0);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            1,
            false,
            0,
            0
        );

        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testZeroInversionRevert() public {
        feedA.setPrice(0);
        feedB.setPrice(5);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            0,
            true,
            0,
            0
        );

        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testNegativePrices() public {
        feedA.setPrice(-3 * 10 ** 8);
        feedB.setPrice(2 * 10 ** 18);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            0,
            false,
            8,
            18
        );

        assertEq(composed.readValue(), -6 * 1e18);
    }

    function testInversion() public {
        feedA.setPrice(2);
        feedB.setPrice(1);

        ComposedOracle composed = new ComposedOracle(
            address(feedA),
            address(feedB),
            0,
            true,
            0,
            0
        );
        int256 expected = (1e18 * 1e18) / (2 * 1e18);
        assertEq(composed.readValue(), expected);
    }
}
