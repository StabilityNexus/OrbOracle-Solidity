// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ComposedOracleByMultiplication, ComposedOracleByDivision} from "./ComposedOracle.sol";

error InvalidFeed();
error InvalidOperation();

contract ComposedOracleFactory is Ownable {
    event ComposedOracleCreated(address indexed oracle, address indexed creator, address feedA, address feedB, uint8 operation);

    struct ComposedOracleInfo {
        address oracle;
        address feedA;
        address feedB;
        uint8 operation;
        address creator;
    }

    ComposedOracleInfo[] public composedOracles;
    mapping(address => address[]) public creatorToComposedOracles;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Anyone can deploy a new ComposedOracle.
    /// @param feedA Address of the first parent feed.
    /// @param feedB Address of the second parent feed.
    /// @param operation 0 for Multiplication, 1 for Division.
    /// @param invertResult If true, the final price is inverted (1 / price).
    /// @param decimalsA Decimals of the first parent feed.
    /// @param decimalsB Decimals of the second parent feed.
    function createComposedOracle(
        address feedA,
        address feedB,
        uint8 operation,
        bool invertResult,
        uint8 decimalsA,
        uint8 decimalsB
    ) external returns (address oracle) {
        if (feedA == address(0) || feedB == address(0)) revert InvalidFeed();

        if (operation == 0) {
            oracle = address(new ComposedOracleByMultiplication(feedA, feedB, invertResult, decimalsA, decimalsB));
        } else if (operation == 1) {
            oracle = address(new ComposedOracleByDivision(feedA, feedB, invertResult, decimalsA, decimalsB));
        } else {
            revert InvalidOperation();
        }

        composedOracles.push(ComposedOracleInfo({
            oracle: oracle,
            feedA: feedA,
            feedB: feedB,
            operation: operation,
            creator: msg.sender
        }));
        creatorToComposedOracles[msg.sender].push(oracle);

        emit ComposedOracleCreated(oracle, msg.sender, feedA, feedB, operation);
    }

    function allComposedOracles() external view returns (ComposedOracleInfo[] memory) {
        return composedOracles;
    }

    function creatorComposedOracleList(address creator) external view returns (address[] memory) {
        return creatorToComposedOracles[creator];
    }
}
