// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// interface for parent feeds
interface IOracle {
    function readValue() external returns (int256);
    function lastSubmissionTime() external view returns (uint256);
    function isBlacklisted(address target) external view returns (bool);
    function history(uint256 index) external view returns (int256);                 // sampled value at index
    function historyTimestamps(uint256 index) external view returns (uint256);      // timestamp for sampled value
    function getHistoryLength() external view returns (uint256);                    // number of sampled values
}

contract ComposedOracle {
    address public immutable feedA;
    address public immutable feedB;

    uint8 public immutable operation;

    bool public immutable invertResult;
    uint8 public immutable decimalsA;
    uint8 public immutable decimalsB;

    uint256 private constant WAD = 1e18;

    error DivisionByZero();
    error InvalidFeedAddress();
    error InvalidOperation();
    error BlacklistedCaller();
    error EmptyHistory();
    error InvalidSampleSize();

    constructor( address _feedA,address _feedB,uint8 _operation,bool _invertResult,uint8 _decimalsA,uint8 _decimalsB ) {
        if (_feedA == address(0) || _feedB == address(0)) revert InvalidFeedAddress();
        if (_operation > 1) revert InvalidOperation();
        feedA = _feedA;
        feedB = _feedB;
        operation = _operation;
        invertResult = _invertResult;
        decimalsA = _decimalsA;
        decimalsB = _decimalsB;
    }

    function _compose(int256 valA, int256 valB) internal view returns (int256) {
        int256 result;
        if (operation == 0) { 
            uint256 scalingPower = decimalsA + decimalsB;

            if (18 >= scalingPower) {
                result = valA * valB * int256(10 ** (18 - scalingPower));
            } else {
                result = (valA * valB) / int256(10 ** (scalingPower - 18));
            }
        } else { 
            if (valB == 0) revert DivisionByZero();

            if (decimalsB + 18 >= decimalsA) {
                result = (valA * int256(10 ** (decimalsB + 18 - decimalsA))) / valB;
            } else {  
                result = valA / (valB * int256(10 ** (decimalsA - decimalsB - 18)));
            }
        }
        if (invertResult) {  
            if (result == 0) revert DivisionByZero();
            result = int256(WAD * WAD) / result;
        }
        return result;
    }

    function readValue() external returns (int256) {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) revert BlacklistedCaller();
        int256 valA = IOracle(feedA).readValue();  // Read latest values from both parent feeds.
        int256 valB = IOracle(feedB).readValue();
        return _compose(valA, valB);  // Compose latest A and latest B using configured operation.
    }

    function readMaxValue(uint256 sampleSize) external returns (int256) {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) revert BlacklistedCaller();
        return _readExtremeValue(sampleSize, true);
    }

    function readMinValue(uint256 sampleSize) external returns (int256) {
        if (IOracle(feedA).isBlacklisted(msg.sender) || IOracle(feedB).isBlacklisted(msg.sender)) revert BlacklistedCaller();
        return _readExtremeValue(sampleSize, false);
    }

    function _readExtremeValue(uint256 sampleSize, bool findMax) internal view returns (int256) {
        if (sampleSize == 0) revert InvalidSampleSize();

        IOracle oracleA = IOracle(feedA);
        IOracle oracleB = IOracle(feedB);

        uint256 lengthA = oracleA.getHistoryLength();
        uint256 lengthB = oracleB.getHistoryLength();

        if (lengthA == 0 || lengthB == 0) revert EmptyHistory();
        uint256 totalComposedPoints = _countComposedHistoryPoints(oracleA,oracleB,lengthA,lengthB);  // Count virtual composed history points to support latest sampleSize values.
        if (totalComposedPoints == 0) revert EmptyHistory();
        if (sampleSize > totalComposedPoints) sampleSize = totalComposedPoints;
        uint256 skipUntil = totalComposedPoints - sampleSize;  // Skip older composed points and only check the latest sampleSize values.
        uint256 indexA;
        uint256 indexB;
        uint256 composedCount;
        int256 latestA;
        int256 latestB;
        int256 extremeValue;
        bool hasA;
        bool hasB;
        bool initialized;

        while (indexA < lengthA || indexB < lengthB) {
            uint256 timestampA = indexA < lengthA ? oracleA.historyTimestamps(indexA) : type(uint256).max;
            uint256 timestampB = indexB < lengthB ? oracleB.historyTimestamps(indexB) : type(uint256).max;
            uint256 currentTimestamp = timestampA <= timestampB ? timestampA : timestampB;  // Process the earliest next timestamp from A or B.

            if (indexA < lengthA && timestampA == currentTimestamp) {
                latestA = oracleA.history(indexA);  // latest A available at this time
                hasA = true;
                indexA++;
            }
            if (indexB < lengthB && timestampB == currentTimestamp) {
                latestB = oracleB.history(indexB);  // latest B available at this time
                hasB = true;
                indexB++;
            }
            if (hasA && hasB) {
                // Only evaluate values inside the latest sampleSize window.
                if (composedCount >= skipUntil) {
                    int256 composedValue = _compose(latestA, latestB);
                    if (!initialized) {
                        extremeValue = composedValue;
                        initialized = true;
                    } else if (findMax && composedValue > extremeValue) {
                        extremeValue = composedValue;
                    } else if (!findMax && composedValue < extremeValue) {
                        extremeValue = composedValue;
                    }
                }
                composedCount++;
            }
        }
        return extremeValue;
    }

    function _countComposedHistoryPoints(IOracle oracleA,IOracle oracleB,uint256 lengthA,uint256 lengthB) internal view returns (uint256 count) {
        uint256 indexA;
        uint256 indexB;
        bool hasA;
        bool hasB;
        while (indexA < lengthA || indexB < lengthB) {
            uint256 timestampA = indexA < lengthA ? oracleA.historyTimestamps(indexA) : type(uint256).max;
            uint256 timestampB = indexB < lengthB ? oracleB.historyTimestamps(indexB) : type(uint256).max;
            uint256 currentTimestamp = timestampA <= timestampB ? timestampA : timestampB;  // Move through both histories in chronological order.

            if (indexA < lengthA && timestampA == currentTimestamp) {  
                hasA = true;   // A has at least one usable value
                indexA++;
            }
            if (indexB < lengthB && timestampB == currentTimestamp) {
                hasB = true;  // B has at least one usable value
                indexB++;
            }
            if (hasA && hasB) count++;  // valid composed point exists here
        }
        return count;
    }

    function lastSubmissionTime() external view returns (uint256) {
        uint256 timeA = IOracle(feedA).lastSubmissionTime();
        uint256 timeB = IOracle(feedB).lastSubmissionTime();
        return timeA < timeB ? timeA : timeB;
    }
}
