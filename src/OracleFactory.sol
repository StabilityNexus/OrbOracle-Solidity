// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Oracle} from "./Oracle.sol";

error InvalidWeightToken();

contract OracleFactory is Ownable {
    event OracleCreated(address indexed oracle, address indexed creator, address token);

    struct OracleInfo {
        address oracle;
        address token;
        address creator;
    }

    OracleInfo[] public oracles;
    mapping(address => address[]) public creatorToOracle;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Anyone can create a new Oracle using an existing ERC20 token.
    /// @param weightToken Address of the ERC20 token to be used for weighting.
    /// @param halfLifeSeconds Time-decay (for default EWMA). You can set 0 and turn on simple mode.
    /// @param quorum Quorum for blacklisting 
    /// @param depositLockingPeriod Time in seconds that tokens must be locked after deposit before governance operations.
    /// @param withdrawalLockingPeriod Time in seconds that tokens must be locked after last operation before withdrawal. 
    /// @param alpha Basis point parameter used for rewards and blacklist thresholding.
    /// @param gamma Minimum interval between stored historical averages for extrema queries.
    function createOracle(
        string memory name,
        string memory description,
        address weightToken,
        uint256 halfLifeSeconds,
        uint256 quorum,
        uint256 depositLockingPeriod,
        uint256 withdrawalLockingPeriod,
        uint256 alpha,
        uint256 gamma
    ) external returns (address oracle, address token)
    {
        if (weightToken == address(0)) revert InvalidWeightToken();
        
        Oracle o = new Oracle(
            msg.sender,      // owner (oracle creator)
            name,
            description,
            weightToken,
            halfLifeSeconds,
            quorum,
            depositLockingPeriod,
            withdrawalLockingPeriod,
            alpha,
            gamma
        );

        oracle = address(o);
        token = weightToken; // Use the provided token address

        oracles.push(OracleInfo({
            oracle: oracle,
            token: token,
            creator: msg.sender
        }));
        creatorToOracle[msg.sender].push(oracle);

        emit OracleCreated(oracle, msg.sender, token);
    }

    function allOracles() external view returns (OracleInfo[] memory) {
        return oracles;
    }

    function creatorOracleList(address creator) external view returns (address[] memory) {
        return creatorToOracle[creator];
    }
}
