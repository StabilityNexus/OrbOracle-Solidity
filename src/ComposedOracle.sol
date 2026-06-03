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
    uint8 public immutable decimalsA;
    uint8 public immutable decimalsB;

    uint256 private constant WAD = 1e18;

    error DivisionByZero();

    constructor(
        address _feedA,
        address _feedB,
        uint8 _operation,
        bool _invertResult,
        uint8 _decimalsA,
        uint8 _decimalsB
    ) {
        feedA = _feedA;
        feedB = _feedB;
        operation = _operation;
        invertResult = _invertResult;
        decimalsA = _decimalsA;
        decimalsB = _decimalsB;
    }

    function readValue() external returns (int256) {
        int256 valA = IOracle(feedA).readValue();
        int256 valB = IOracle(feedB).readValue();

        int256 result;

        if (operation == 0) {
            //muliplication
            // these are not gas efficient and will not work for negative values of valA and valB
            // uint256 numerator = uint256(valA) * uint256(valB) * (WAD);
            // uint256 denominator = (10 ** uint256(decimalsA)) * (10 ** uint256(decimalsB));
            // result = int256(numerator / denominator);

            uint256 scalingPower = decimalsA + decimalsB;
            if (18 >= scalingPower) {
                result = valA * valB * int256(10 ** (18 - scalingPower));
            } else {
                result = (valA * valB) / int256(10 ** (scalingPower - 18));
            }
        } else {
            //division
            if (valB == 0) revert DivisionByZero();

            // uint256 numerator = uint256(valA) * (10 ** uint256(decimalsB)) * (WAD);
            // uint denominator = uint256(valB) * (10 ** uint256(decimalsA));
            // result = int256(numerator / denominator);

            if (decimalsB + 18 >= decimalsA) {
                result =
                    (valA * int256(10 ** (decimalsB + 18 - decimalsA))) /
                    valB;
            } else {
                result =
                    valA /
                    (valB * int256(10 ** (decimalsA - decimalsB - 18)));
            }
        }

        if (invertResult) {
            if (result == 0) revert DivisionByZero();
            result = int256(WAD * WAD) / result;
        }

        return result;
    }
}
