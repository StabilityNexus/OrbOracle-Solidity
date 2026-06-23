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

    constructor(
        address _feedA,
        address _feedB,
        uint8 _operation,
        bool _invertResult,
        uint8 _decimalsA,
        uint8 _decimalsB
    ) {
        if (_feedA == address(0) || _feedB == address(0)) {
            revert InvalidFeedAddress();
        }
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

    function lastSubmissionTime() external view returns (uint256) {
        uint256 timeA = IOracle(feedA).lastSubmissionTime();
        uint256 timeB = IOracle(feedB).lastSubmissionTime();
        return timeA < timeB ? timeA : timeB;
    }
}
