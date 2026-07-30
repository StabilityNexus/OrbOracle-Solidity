// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ComposedOracleFactory, InvalidFeed, InvalidOperation} from "../src/ComposedOracleFactory.sol";
import {ComposedOracle, ComposedOracleByMultiplication, ComposedOracleByDivision} from "../src/ComposedOracle.sol";

contract MockOracle {
    function readValue() external pure returns (uint256) { return 100 * 1e18; }
    function readLatestValue() external pure returns (uint256) { return 100 * 1e18; }
    function readValueInterval() external pure returns (uint256, uint256) { return (100 * 1e18, 100 * 1e18); }
    function lastSubmissionTime() external pure returns (uint256) { return 0; }
    function isBlacklisted(address) external pure returns (bool) { return false; }
}

contract ComposedOracleFactoryTest is Test {
    ComposedOracleFactory public factory;
    address public feedA;
    address public feedB;
    address public owner = address(0x123);

    function setUp() public {
        factory = new ComposedOracleFactory(owner);
        feedA = address(new MockOracle());
        feedB = address(new MockOracle());
    }

    function testDeployMultiplication() public {
        address oracleAddr = factory.createComposedOracle(feedA, feedB, 0, false, 100);
        assertTrue(oracleAddr != address(0));

        // Check registry
        ComposedOracleFactory.ComposedOracleInfo memory info = factory.allComposedOracles()[0];
        assertEq(info.oracle, oracleAddr);
        assertEq(info.feedA, feedA);
        assertEq(info.feedB, feedB);
        assertEq(info.operation, 0);
        assertEq(info.creator, address(this));

        // Verify deployment returns correct price (100 * 100 / 1 = 10000 * 1e18)
        uint256 val = ComposedOracle(oracleAddr).readValue();
        assertEq(val, 10000 * 1e18);
    }

    // Multiplication Inverted
    function testDeployMultiplicationInverted() public {
        address oracleAddr = factory.createComposedOracle(feedA, feedB, 0, true, 100);
        assertTrue(oracleAddr != address(0));

        // Verify deployment returns inverted price (1e18 * 1e18 / (10000 * 1e18) = 1e14)
        uint256 val = ComposedOracle(oracleAddr).readValue();
        assertEq(val, 1e14);
    }

    function testDeployDivision() public {
        address oracleAddr = factory.createComposedOracle(feedA, feedB, 1, false, 100);
        assertTrue(oracleAddr != address(0));

        // Check registry
        ComposedOracleFactory.ComposedOracleInfo memory info = factory.allComposedOracles()[0];
        assertEq(info.oracle, oracleAddr);
        assertEq(info.feedA, feedA);
        assertEq(info.feedB, feedB);
        assertEq(info.operation, 1);

        // Verify deployment returns correct price (100 / 100 = 1 * 1e18)
        uint256 val = ComposedOracle(oracleAddr).readValue();
        assertEq(val, 1 * 1e18);
    }

    function testRevertInvalidOperation() public {
        vm.expectRevert(InvalidOperation.selector);
        factory.createComposedOracle(feedA, feedB, 2, false, 100);
    }

    function testRevertInvalidFeedAddress() public {
        vm.expectRevert(InvalidFeed.selector);
        factory.createComposedOracle(address(0), feedB, 0, false, 100);

        vm.expectRevert(InvalidFeed.selector);
        factory.createComposedOracle(feedA, address(0), 0, false, 100);
    }

    function testListsAndGetters() public {
        address oracle1 = factory.createComposedOracle(feedA, feedB, 0, false, 100);
        address oracle2 = factory.createComposedOracle(feedA, feedB, 1, false, 100);

        ComposedOracleFactory.ComposedOracleInfo[] memory all = factory.allComposedOracles();
        assertEq(all.length, 2);
        assertEq(all[0].oracle, oracle1);
        assertEq(all[1].oracle, oracle2);

        address[] memory creatorList = factory.creatorComposedOracleList(address(this));
        assertEq(creatorList.length, 2);
        assertEq(creatorList[0], oracle1);
        assertEq(creatorList[1], oracle2);
    }
}
