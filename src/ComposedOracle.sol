// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// interface for parent feeds
interface IOracle {
    function readValue() external returns (int256);
}

contract ComposedOracle {
    address public immutable feedA;
    address public immutable feedB;

    uint8 public immutable operation;

    bool public immutable invertResult;

    int256 private constant WAD = 1e18;

    error DivisionByZero();

    constructor(
        address _feedA,
        address _feedB,
        uint8 _operation,
        bool _invertResult
    ) {
        feedA = _feedA;
        feedB = _feedB;
        operation = _operation;
        invertResult = _invertResult;
    }

    function readValue() external returns (int256) {
        int256 valA = IOracle(feedA).readValue();
        int256 valB = IOracle(feedB).readValue();

        int256 result;

        if (operation == 0) {
            result = valA * valB;
        } else {
            if (valB == 0) revert DivisionByZero();
            result = valA / valB;
        }

        if (invertResult) {
            if (result == 0) revert DivisionByZero();
            result = (WAD * WAD) / result;
        }

        return result;
    }
}
