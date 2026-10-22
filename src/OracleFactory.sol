// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Oracle} from "./Oracle.sol";

error InvalidWeightToken();
error OnlyDev();
error OnlyProposedDev();
error DevFeeExceedsMax(uint256 devFee, uint256 maxDevFee);
error ZeroAddress();

contract OracleFactory is Ownable {
    event OracleCreated(address indexed oracle, address indexed creator, address token);
    event DevProposed(address indexed proposedDev);
    event DevTransferred(address indexed oldDev, address indexed newDev);

    struct OracleInfo {
        address oracle;
        address token;
        address creator;
    }

    uint256 public constant MAX_DEV_FEE = 30_000;                // Maximum allowed dev fee: 30% of DENOMINATOR (1e5)
    address public dev;
    address public proposedDev;
    uint256 public immutable devFee;

    OracleInfo[] public oracles;
    mapping(address => address[]) public creatorToOracle;

    constructor(address initialOwner, address initialDev, uint256 devFee_) Ownable(initialOwner) {
        if (initialDev == address(0)) revert ZeroAddress();
        if (devFee_ > MAX_DEV_FEE) revert DevFeeExceedsMax(devFee_, MAX_DEV_FEE);
        dev = initialDev;
        devFee = devFee_;
    }

    function proposeDev(address newDev) external {
        if (msg.sender != dev) revert OnlyDev();
        if (newDev == address(0)) revert ZeroAddress();
        proposedDev = newDev;
        emit DevProposed(newDev);
    }

    function acceptDev() external {
        if (msg.sender != proposedDev) revert OnlyProposedDev();
        address oldDev = dev;
        dev = msg.sender;
        proposedDev = address(0);
        emit DevTransferred(oldDev, msg.sender);
    }

    /// @notice Anyone can create a new Oracle using an existing ERC20 token.
    /// @param weightToken Address of the ERC20 token to be used for weighting.
    /// @param halfLifeSeconds Time-decay (for default EWMA). You can set 0 and turn on simple mode.
    /// @param q Governance constant for blacklist equation
    /// @param depositLockingPeriod Time in seconds that tokens must be locked after deposit before governance operations.
    /// @param withdrawalLockingPeriod Time in seconds that tokens must be locked after last operation before withdrawal. 
    /// @param rewardBps Basis point parameter used for rewards.
    /// @param gamma Minimum interval between stored historical averages for extrema queries.
    /// @param defaultSampleSize The default lookback sample size for extremes queries.
    function createOracle(
        string memory name,
        string memory description,
        address weightToken,
        uint256 halfLifeSeconds,
        uint256 q,
        uint256 depositLockingPeriod,
        uint256 withdrawalLockingPeriod,
        uint256 rewardBps,
        uint256 gamma,
        uint256 defaultSampleSize
    ) external returns (address oracle, address token)
    {
        if (weightToken == address(0)) revert InvalidWeightToken();
        
        Oracle o = new Oracle(
            msg.sender,      // owner (oracle creator)
            dev,             // dev
            devFee,          // devFee
            name,
            description,
            weightToken,
            halfLifeSeconds,
            q,
            depositLockingPeriod,
            withdrawalLockingPeriod,
            rewardBps,
            gamma,
            defaultSampleSize
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
