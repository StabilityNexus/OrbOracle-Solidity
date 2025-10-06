// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Oracle} from "./Oracle.sol";

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
    /// @param reward Portion of ETH reserve paid to submitters.
    /// @param halfLifeSeconds Time-decay (for default EWMA). You can set 0 and turn on simple mode.
    /// @param quorum Quorum for blacklisting 
    /// @param depositLockingPeriod Time in seconds that tokens must be locked after deposit before governance operations.
    /// @param withdrawalLockingPeriod Time in seconds that tokens must be locked after last operation before withdrawal. 
    function createOracle(
        string memory name,
        string memory description,
        address weightToken,
        uint256 reward,
        uint256 halfLifeSeconds,
        uint256 quorum,
        uint256 depositLockingPeriod,
        uint256 withdrawalLockingPeriod,
        uint256 alpha
    ) external returns (address oracle, address token)
    {
        require(weightToken != address(0), "Invalid token address");
        
        Oracle o = new Oracle(
            msg.sender,      // owner (oracle creator)
            name,
            description,
            weightToken,
            reward,
            halfLifeSeconds,
            quorum,
            depositLockingPeriod,
            withdrawalLockingPeriod,
            alpha
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
