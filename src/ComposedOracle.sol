// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// interface for parent feeds
interface IOracle {
    function readValue() external view returns (uint256);
    function readLatestValue() external view returns (uint256);
    function lastUpdated() external view returns (uint256);
    function isBlacklisted(address target) external view returns (bool);
    function history(uint256 index) external view returns (uint256);                 // sampled value at index
    function historyTimestamps(uint256 index) external view returns (uint256);      // timestamp for sampled value
    function getHistoryLength() external view returns (uint256);                    // number of sampled values
}

abstract contract ComposedOracle {
    address public immutable feedA;
    address public immutable feedB;

    bool public immutable invertResult;
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

    constructor(address _feedA, address _feedB, bool _invertResult, uint256 _defaultSampleSize) {
        if (_feedA == address(0) || _feedB == address(0)) revert InvalidFeedAddress();
        if (_defaultSampleSize == 0) revert InvalidSampleSize();
        feedA = _feedA;
        feedB = _feedB;
        invertResult = _invertResult;
        defaultSampleSize = _defaultSampleSize;
    }

    function readValue() external view notBlacklisted returns (uint256) {
        uint256 valA = IOracle(feedA).readValue();
        uint256 valB = IOracle(feedB).readValue();

        return _compose(valA, valB);
    }

    function readLatestValue() external view notBlacklisted returns (uint256) {
        uint256 valA = IOracle(feedA).readLatestValue();
        uint256 valB = IOracle(feedB).readLatestValue();

        return _compose(valA, valB);
    }

    function _compose(uint256 valA, uint256 valB) internal view returns (uint256) {
        uint256 result = _composeWithoutInversion(valA, valB);

        if (invertResult) {
            if (result == 0) revert DivisionByZero();
            return (WAD * WAD) / result;
        }

        return result;
    }

    function _composeWithoutInversion(uint256 valA, uint256 valB) internal view virtual returns (uint256);

    function readValueInterval() external view notBlacklisted returns (uint256 minValue, uint256 maxValue) {
        IOracle oracleA = IOracle(feedA);
        IOracle oracleB = IOracle(feedB);

        uint256 indexA = oracleA.getHistoryLength();
        uint256 indexB = oracleB.getHistoryLength();

        if (indexA == 0 || indexB == 0) revert EmptyHistory();

        // Calculate and initialize min/max with the first (latest) composed value
        uint256 timestampA = oracleA.historyTimestamps(indexA - 1);
        uint256 timestampB = oracleB.historyTimestamps(indexB - 1);
        uint256 currentTimestamp = timestampA >= timestampB ? timestampA : timestampB;

        uint256 composedValue = _compose(oracleA.history(indexA - 1), oracleB.history(indexB - 1));
        minValue = composedValue;
        maxValue = composedValue;
        uint256 composedCount = 1;

        if (timestampA == currentTimestamp) indexA--;
        if (timestampB == currentTimestamp) indexB--;

        // Loop for the remaining sampleSize
        while ((indexA > 0 && indexB > 0) && composedCount < defaultSampleSize) {
            timestampA = oracleA.historyTimestamps(indexA - 1);
            timestampB = oracleB.historyTimestamps(indexB - 1);
            currentTimestamp = timestampA >= timestampB ? timestampA : timestampB;
            
            composedValue = _compose(oracleA.history(indexA - 1), oracleB.history(indexB - 1));
            if (composedValue < minValue) {
                minValue = composedValue;
            }
            if (composedValue > maxValue) {
                maxValue = composedValue;
            }
            composedCount++;
            
            if (timestampA == currentTimestamp) indexA--;
            if (timestampB == currentTimestamp) indexB--;
        }

        return (minValue, maxValue);
    }

    function lastUpdated() external view returns (uint256) {
        uint256 timeA = IOracle(feedA).lastUpdated();
        uint256 timeB = IOracle(feedB).lastUpdated();
        return timeA < timeB ? timeA : timeB;
    }

    function isBlacklisted(address target) external view returns (bool) {
        return IOracle(feedA).isBlacklisted(target) || IOracle(feedB).isBlacklisted(target);
    }
}

contract ComposedOracleByMultiplication is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint256 _defaultSampleSize) 
        ComposedOracle(_feedA, _feedB, _invertResult, _defaultSampleSize) {}

    function _composeWithoutInversion(uint256 valA, uint256 valB) internal pure override returns (uint256) {
        return (valA * valB) / 1e18;
    }
}

contract ComposedOracleByDivision is ComposedOracle {
    constructor(address _feedA, address _feedB, bool _invertResult, uint256 _defaultSampleSize) 
        ComposedOracle(_feedA, _feedB, _invertResult, _defaultSampleSize) {}

    function _composeWithoutInversion(uint256 valA, uint256 valB) internal pure override returns (uint256) {
        if (valB == 0) revert DivisionByZero();
        return (valA * 1e18) / valB;
    }
}
