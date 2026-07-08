// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// interface for parent feeds
interface IOracle {
    function readValue() external view returns (int256);

    function lastSubmissionTime() external view returns (uint256);

    function isBlacklisted(address target) external view returns (bool);
}

abstract contract ComposedOracle {
    address public immutable feedA;
    address public immutable feedB;

    bool public immutable invertResult;
    uint8 public immutable decimalsA;
    uint8 public immutable decimalsB;

    uint256 private constant WAD = 1e18;

    error DivisionByZero();
    error InvalidFeedAddress();
    error BlacklistedCaller();

    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB) {
        if (_feedA == address(0) || _feedB == address(0)) {
            revert InvalidFeedAddress();
        }
        feedA = _feedA;
        feedB = _feedB;
        invertResult = _invertResult;
        decimalsA = _decimalsA;
        decimalsB = _decimalsB;
    }

    function readValue() external view returns (int256) {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) {
            revert BlacklistedCaller();
        }
        int256 valA = IOracle(feedA).readValue();
        int256 valB = IOracle(feedB).readValue();

        return _compose(valA, valB);
    }

    function _compose(int256 valA, int256 valB) internal view returns (int256) {
        int256 result = _composeWithoutInversion(valA, valB);

        if (invertResult) {
            if (result == 0) revert DivisionByZero();
            result = int256(WAD * WAD) / result;
        }

        return result;
    }

    function _composeWithoutInversion(int256 valA, int256 valB) internal view virtual returns (int256);

    function lastSubmissionTime() external view returns (uint256) {
        uint256 timeA = IOracle(feedA).lastSubmissionTime();
        uint256 timeB = IOracle(feedB).lastSubmissionTime();
        return timeA < timeB ? timeA : timeB;
    }
}

contract ComposedOracleByMultiplication is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB) 
        ComposedOracle(_feedA, _feedB, _invertResult, _decimalsA, _decimalsB) {}

    function _composeWithoutInversion(int256 valA, int256 valB) internal view override returns (int256) {
        uint256 scalingPower = decimalsA + decimalsB;

        if (18 >= scalingPower) { return valA * valB * int256(10 ** (18 - scalingPower)); }

        return (valA * valB) / int256(10 ** (scalingPower - 18));
    }
}

contract ComposedOracleByDivision is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB) 
        ComposedOracle(_feedA, _feedB, _invertResult, _decimalsA, _decimalsB) {}

    function _composeWithoutInversion(int256 valA, int256 valB) internal view override returns (int256) {
        if (valB == 0) revert DivisionByZero();

        if (decimalsB + 18 >= decimalsA) { return (valA * int256(10 ** (decimalsB + 18 - decimalsA))) / valB; }

        return valA / (valB * int256(10 ** (decimalsA - decimalsB - 18)));
    }
}
