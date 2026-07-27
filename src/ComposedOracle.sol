// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// interface for parent feeds
interface IOracle {
    function readValue() external view returns (int256);

    function readLatestValue() external view returns (int256);

    function lastSubmissionTime() external view returns (uint256);

    function isBlacklisted(address target) external view returns (bool);

    function history(uint256 index) external view returns (int256);                 // sampled value at index
    function historyTimestamps(uint256 index) external view returns (uint256);      // timestamp for sampled value
    function getHistoryLength() external view returns (uint256);                    // number of sampled values
}

abstract contract ComposedOracle {
    address public immutable feedA;
    address public immutable feedB;

    bool public immutable invertResult;
    uint8 public immutable decimalsA;
    uint8 public immutable decimalsB;
    uint256 public immutable defaultSampleSize;

    uint256 private constant WAD = 1e18;

    error DivisionByZero();
    error InvalidFeedAddress();
    error BlacklistedCaller();
    error EmptyHistory();
    error InvalidSampleSize();

    modifier notBlacklisted() {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) {
            revert BlacklistedCaller();
        }
        _;
    }

    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB, uint256 _defaultSampleSize) {
        if (_feedA == address(0) || _feedB == address(0)) {
            revert InvalidFeedAddress();
        }
        feedA = _feedA;
        feedB = _feedB;
        invertResult = _invertResult;
        decimalsA = _decimalsA;
        decimalsB = _decimalsB;
        defaultSampleSize = _defaultSampleSize;
    }

    function readValue() external view notBlacklisted returns (int256) {
        int256 valA = IOracle(feedA).readValue();
        int256 valB = IOracle(feedB).readValue();

        return _compose(valA, valB);
    }

    function readLatestValue() external view returns (int256) {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) {
            revert BlacklistedCaller();
        }
        int256 valA = IOracle(feedA).readLatestValue();
        int256 valB = IOracle(feedB).readLatestValue();

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

    function readValueInterval() external view notBlacklisted returns (int256 minValue, int256 maxValue) {
        if (defaultSampleSize == 0) revert InvalidSampleSize();

        IOracle oracleA = IOracle(feedA);
        IOracle oracleB = IOracle(feedB);

        uint256 indexA = oracleA.getHistoryLength();
        uint256 indexB = oracleB.getHistoryLength();

        if (indexA == 0 || indexB == 0) revert EmptyHistory();

        uint256 composedCount;
        bool initialized;

        while ((indexA > 0 && indexB > 0) && composedCount < defaultSampleSize) {
            uint256 timestampA = indexA > 0 ? oracleA.historyTimestamps(indexA - 1) : 0;
            uint256 timestampB = indexB > 0 ? oracleB.historyTimestamps(indexB - 1) : 0;
            uint256 currentTimestamp = timestampA >= timestampB ? timestampA : timestampB; // Process the latest remaining timestamp from either parent history.
            
            if (indexA > 0 && indexB > 0) { // indexA - 1 and indexB - 1 are the latest values available at this time.
                int256 composedValue = _compose(oracleA.history(indexA - 1), oracleB.history(indexB - 1));
                if (!initialized) {
                    minValue = composedValue;
                    maxValue = composedValue;
                    initialized = true;
                } else {
                    if (composedValue < minValue) {
                        minValue = composedValue;
                    }
                    if (composedValue > maxValue) {
                        maxValue = composedValue;
                    }
                }
                composedCount++;
            }
            if (indexA > 0 && timestampA == currentTimestamp) indexA--;
            if (indexB > 0 && timestampB == currentTimestamp) indexB--;
        }
        if (composedCount == 0) revert EmptyHistory();

        return (minValue, maxValue);
    }

    function lastSubmissionTime() external view returns (uint256) {
        uint256 timeA = IOracle(feedA).lastSubmissionTime();
        uint256 timeB = IOracle(feedB).lastSubmissionTime();
        return timeA < timeB ? timeA : timeB;
    }

    function isBlacklisted(address target) external view returns (bool) {
        return IOracle(feedA).isBlacklisted(target) || IOracle(feedB).isBlacklisted(target);
    }
}

contract ComposedOracleByMultiplication is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB, uint256 _defaultSampleSize) 
        ComposedOracle(_feedA, _feedB, _invertResult, _decimalsA, _decimalsB, _defaultSampleSize) {}

    function _composeWithoutInversion(int256 valA, int256 valB) internal view override returns (int256) {
        uint256 scalingPower = decimalsA + decimalsB;

        if (18 >= scalingPower) { return valA * valB * int256(10 ** (18 - scalingPower)); }

        return (valA * valB) / int256(10 ** (scalingPower - 18));
    }
}

contract ComposedOracleByDivision is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint8 _decimalsA, uint8 _decimalsB, uint256 _defaultSampleSize) 
        ComposedOracle(_feedA, _feedB, _invertResult, _decimalsA, _decimalsB, _defaultSampleSize) {}

    function _composeWithoutInversion(int256 valA, int256 valB) internal view override returns (int256) {
        if (valB == 0) revert DivisionByZero();

        if (decimalsB + 18 >= decimalsA) { return (valA * int256(10 ** (decimalsB + 18 - decimalsA))) / valB; }

        return valA / (valB * int256(10 ** (decimalsA - decimalsB - 18)));
    }
}
