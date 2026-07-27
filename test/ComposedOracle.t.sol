// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ComposedOracle, ComposedOracleByMultiplication, ComposedOracleByDivision} from "../src/ComposedOracle.sol";

contract MockOracle {
    int256 private price;
    uint256 private lastSubTime;
    int256[] public history;
    uint256[] public historyTimestamps;

    mapping(address => bool) private blacklisted;

    constructor(int256 _price) {
        price = _price;
        lastSubTime = block.timestamp;
    }

    function pushHistory(uint256 timestamp, int256 value) external {
        historyTimestamps.push(timestamp);
        history.push(value);
    }

    function getHistoryLength() external view returns (uint256) { return history.length; }

    function readValue() external view returns (int256) {
        return price;
    }


    function setPrice(int256 _price) external {
        price = _price;
    }

    function lastSubmissionTime() external view returns (uint256) {
        return lastSubTime;
    }

    function setLastSubmissionTime(uint256 _time) external {
        lastSubTime = _time;
    }

    function isBlacklisted(address target) external view returns (bool) {
        return blacklisted[target];
    }

    function setBlacklisted(address target, bool _status) external {
        blacklisted[target] = _status;
    }
}

contract ComposedOracleTest is Test {
    MockOracle public feedA;
    MockOracle public feedB;

    function setUp() public {
        feedA = new MockOracle(0);
        feedB = new MockOracle(0);
    }

    function _newMulComposed() internal returns (ComposedOracle) { return _newMulComposed(100); }
    function _newMulComposed(uint256 defaultSampleSize) internal returns (ComposedOracle) {
        return new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 0, 0, defaultSampleSize);
    }

    function _newDivComposed() internal returns (ComposedOracle) { return _newDivComposed(100); }
    function _newDivComposed(uint256 defaultSampleSize) internal returns (ComposedOracle) {
        return new ComposedOracleByDivision(address(feedA), address(feedB), false, 0, 0, defaultSampleSize);
    }

    function testReadIntervalMatchingTimestamps() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(20, 4);
        feedA.pushHistory(30, 1);
        feedB.pushHistory(10, 100);
        feedB.pushHistory(20, 50);
        feedB.pushHistory(30, 300);

        ComposedOracle composed = _newMulComposed(3);
        (int256 min, int256 max) = composed.readValueInterval();
        assertEq(min, 200 * 1e18);
        assertEq(max, 300 * 1e18);
    }

    function testReadIntervalUsesLatestAvailableValue() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 200);
        ComposedOracle composed = _newMulComposed(3);
        (int256 min, int256 max) = composed.readValueInterval();
        assertEq(min, 200 * 1e18);
        assertEq(max, 800 * 1e18);
    }

    function testReadIntervalUsesLatestSampleSize() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 1);
        ComposedOracle composed = _newMulComposed(2);
        (int256 min, int256 max) = composed.readValueInterval();
        assertEq(min, 4 * 1e18);
        assertEq(max, 400 * 1e18);
    }

    function testReadIntervalSampleSizeGreaterThanHistoryUsesAll() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 1);
        ComposedOracle composed = _newMulComposed(100);
        (int256 min, int256 max) = composed.readValueInterval();
        assertEq(min, 4 * 1e18);
        assertEq(max, 400 * 1e18);
    }

    function testReadIntervalRevertsForZeroSampleSize() public {
        feedA.pushHistory(10, 2);
        feedB.pushHistory(10, 100);

        ComposedOracle composed = _newMulComposed(0);
        vm.expectRevert(ComposedOracle.InvalidSampleSize.selector);
        composed.readValueInterval();
    }

    function testReadIntervalRevertsForEmptyHistory() public {
        ComposedOracle composed = _newMulComposed(1);

        vm.expectRevert(ComposedOracle.EmptyHistory.selector);
        composed.readValueInterval();
    }

    function testMultiplication() public {
        feedA.setPrice(6);
        feedB.setPrice(2);

        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 0, 0, 100);
        assertEq(composed.readValue(), 12 * 1e18);
    }

    function testDivision() public {
        feedA.setPrice(6);
        feedB.setPrice(2);
        ComposedOracle composed = new ComposedOracleByDivision(address(feedA), address(feedB), false, 0, 0, 100);
        assertEq(composed.readValue(), 3 * 1e18);
    }

    function testMultiplicationDifferentDecimals() public {
        feedA.setPrice(1 * 10 ** 8);
        feedB.setPrice(3000 * 10 ** 18);

        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 8, 18, 100);

        assertEq(composed.readValue(), 3000 * 1e18);
    }

    function testDivisionDifferentDecimals() public {
        feedA.setPrice(3000 * 10 ** 18);
        feedB.setPrice(100000 * 10 ** 8);

        ComposedOracle composed = new ComposedOracleByDivision(address(feedA), address(feedB), false, 18, 8, 100);
        assertEq(composed.readValue(), 3 * 10 ** 16);
    }

    function testDivisionByZeroRevert() public {
        feedA.setPrice(10);
        feedB.setPrice(0);

        ComposedOracle composed = new ComposedOracleByDivision(address(feedA), address(feedB), false, 0, 0, 100);
        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testZeroInversionRevert() public {
        feedA.setPrice(0);
        feedB.setPrice(5);

        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), true, 0, 0, 100);
        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testNegativePrices() public {
        feedA.setPrice(-3 * 10 ** 8);
        feedB.setPrice(2 * 10 ** 18);

        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 8, 18, 100);
        assertEq(composed.readValue(), -6 * 1e18);
    }

    function testInversion() public {
        feedA.setPrice(2);
        feedB.setPrice(1);

        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), true, 0, 0, 100);
        int256 expected = (1e18 * 1e18) / (2 * 1e18);
        assertEq(composed.readValue(), expected);
    }

    function testConstructorRevertAddressZero() public {
        vm.expectRevert(ComposedOracle.InvalidFeedAddress.selector);
        new ComposedOracleByMultiplication(address(0), address(feedB), false, 0, 0, 100);
        vm.expectRevert(ComposedOracle.InvalidFeedAddress.selector);
        new ComposedOracleByMultiplication(address(feedA), address(0), false, 0, 0, 100);
    }

    function testBlacklistCallerRevert() public {
        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 0, 0, 100);
        feedA.setBlacklisted(address(this), true);
        vm.expectRevert(ComposedOracle.BlacklistedCaller.selector);
        composed.readValue();

        feedA.setBlacklisted(address(this), false);
        feedB.setBlacklisted(address(this), true);
        vm.expectRevert(ComposedOracle.BlacklistedCaller.selector);
        composed.readValue();

        feedB.setBlacklisted(address(this), false);
        feedA.setPrice(6);
        feedB.setPrice(2);
        assertEq(composed.readValue(), 12 * 1e18);
    }

    function testLastSubmissionTimeMin() public {
        ComposedOracle composed = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 0, 0, 100);
        feedA.setLastSubmissionTime(1000);
        feedB.setLastSubmissionTime(2000);
        assertEq(composed.lastSubmissionTime(), 1000);

        feedA.setLastSubmissionTime(3000);
        feedB.setLastSubmissionTime(1500);
        assertEq(composed.lastSubmissionTime(), 1500);
    }

    function testNestedComposedOracleBlacklist() public {
        MockOracle feedC = new MockOracle(5);
        
        // 1. Compose feedA and feedB (composedParent)
        ComposedOracle composedParent = new ComposedOracleByMultiplication(address(feedA), address(feedB), false, 0, 0, 100);
        
        // 2. Compose composedParent and feedC (nestedComposed)
        ComposedOracle nestedComposed = new ComposedOracleByDivision(address(composedParent), address(feedC), false, 18, 0, 100);

        feedA.setPrice(10);
        feedB.setPrice(2); // composedParent = 20 * 1e18
        
        // 3. Blacklist address(this) on feedA
        feedA.setBlacklisted(address(this), true);
        
        // 4. Verify nestedComposed.isBlacklisted(address(this)) is true
        assertTrue(nestedComposed.isBlacklisted(address(this)));
        
        // 5. Verify nestedComposed.readValue() reverts with BlacklistedCaller
        vm.expectRevert(ComposedOracle.BlacklistedCaller.selector);
        nestedComposed.readValue();

        // 6. Un-blacklist and verify readValue works (20 * 1e18 / 5 = 4 * 1e18)
        feedA.setBlacklisted(address(this), false);
        assertEq(nestedComposed.readValue(), 4 * 1e18);
    }
}
