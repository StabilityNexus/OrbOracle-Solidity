// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ComposedOracle} from "../src/ComposedOracle.sol";

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

    function _newMulComposed() internal returns (ComposedOracle) { return new ComposedOracle(address(feedA), address(feedB), 0, false, 0, 0); }

    function _newDivComposed() internal returns (ComposedOracle) { return new ComposedOracle(address(feedA), address(feedB), 1, false, 0, 0); }

    function testReadMaxValueMatchingTimestamps() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(20, 4);
        feedA.pushHistory(30, 1);
        feedB.pushHistory(10, 100);
        feedB.pushHistory(20, 50);
        feedB.pushHistory(30, 300);

        ComposedOracle composed = _newMulComposed();
        assertEq(composed.readMaxValue(3), 300 * 1e18);
    }

    function testReadMinValueMatchingTimestamps() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(20, 4);
        feedA.pushHistory(30, 1);
        feedB.pushHistory(10, 100);
        feedB.pushHistory(20, 50);
        feedB.pushHistory(30, 300);
        ComposedOracle composed = _newMulComposed();
        assertEq(composed.readMinValue(3), 200 * 1e18);
    }

    function testReadMaxValueUsesLatestAvailableValue() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 200);
        ComposedOracle composed = _newMulComposed();
        assertEq(composed.readMaxValue(3), 800 * 1e18);
    }

    function testReadMaxValueUsesLatestSampleSize() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 1);
        ComposedOracle composed = _newMulComposed();
        assertEq(composed.readMaxValue(2), 400 * 1e18);
    }

    function testReadMinValueSampleSizeGreaterThanHistoryUsesAll() public {
        feedA.pushHistory(10, 2);
        feedA.pushHistory(30, 4);
        feedB.pushHistory(20, 100);
        feedB.pushHistory(40, 1);
        ComposedOracle composed = _newMulComposed();
        assertEq(composed.readMinValue(100), 4 * 1e18);
    }

    function testReadMaxValueRevertsForZeroSampleSize() public {
        feedA.pushHistory(10, 2);
        feedB.pushHistory(10, 100);

        ComposedOracle composed = _newMulComposed();
        vm.expectRevert(ComposedOracle.InvalidSampleSize.selector);
        composed.readMaxValue(0);
    }

    function testReadMinValueRevertsForEmptyHistory() public {
        ComposedOracle composed = _newMulComposed();

        vm.expectRevert(ComposedOracle.EmptyHistory.selector);
        composed.readMinValue(1);
    }

    function testMultiplication() public {
        feedA.setPrice(6);
        feedB.setPrice(2);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, false, 0, 0);
        assertEq(composed.readValue(), 12 * 1e18);
    }

    function testDivision() public {
        feedA.setPrice(6);
        feedB.setPrice(2);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 1, false, 0, 0);
        assertEq(composed.readValue(), 3 * 1e18);
    }

    function testMultiplicationDifferentDecimals() public {
        feedA.setPrice(1 * 10 ** 8);
        feedB.setPrice(3000 * 10 ** 18);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, false, 8, 18);
        assertEq(composed.readValue(), 3000 * 1e18);
    }

    function testDivisionDifferentDecimals() public {
        feedA.setPrice(3000 * 10 ** 18);
        feedB.setPrice(100000 * 10 ** 8);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 1, false, 18, 8);
        assertEq(composed.readValue(), 3 * 10 ** 16);
    }

    function testDivisionByZeroRevert() public {
        feedA.setPrice(10);
        feedB.setPrice(0);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 1, false, 0, 0);
        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testZeroInversionRevert() public {
        feedA.setPrice(0);
        feedB.setPrice(5);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, true, 0, 0);
        vm.expectRevert(ComposedOracle.DivisionByZero.selector);
        composed.readValue();
    }

    function testNegativePrices() public {
        feedA.setPrice(-3 * 10 ** 8);
        feedB.setPrice(2 * 10 ** 18);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, false, 8, 18);
        assertEq(composed.readValue(), -6 * 1e18);
    }

    function testInversion() public {
        feedA.setPrice(2);
        feedB.setPrice(1);
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, true, 0, 0);
        int256 expected = (1e18 * 1e18) / (2 * 1e18);
        assertEq(composed.readValue(), expected);
    }

    function testConstructorRevertAddressZero() public {
        vm.expectRevert(ComposedOracle.InvalidFeedAddress.selector);
        new ComposedOracle(address(0), address(feedB), 0, false, 0, 0);
        vm.expectRevert(ComposedOracle.InvalidFeedAddress.selector);
        new ComposedOracle(address(feedA), address(0), 0, false, 0, 0);
    }

    function testConstructorRevertInvalidOperation() public {
        vm.expectRevert(ComposedOracle.InvalidOperation.selector);
        new ComposedOracle(address(feedA), address(feedB), 2, false, 0, 0);
    }

    function testBlacklistCallerRevert() public {
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, false, 0, 0);
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
        ComposedOracle composed = new ComposedOracle(address(feedA), address(feedB), 0, false, 0, 0);
        feedA.setLastSubmissionTime(1000);
        feedB.setLastSubmissionTime(2000);
        assertEq(composed.lastSubmissionTime(), 1000);

        feedA.setLastSubmissionTime(3000);
        feedB.setLastSubmissionTime(1500);
        assertEq(composed.lastSubmissionTime(), 1500);
    }
}
