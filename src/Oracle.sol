// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {GovernanceLib} from "./GovernanceLib.sol";
import {DecayLib} from "./DecayLib.sol";

error BlacklistedCaller();
error NoGovernanceWeight();
error InvalidWeightTokenAddress();
error RewardTransferFailed();
error AmountZero();
error TokenTransferFailed();
error InsufficientUnlockedBalance();
error WithdrawalLockActive(uint256 unlockTime);
error PriceHistoryStartOutOfBounds();
error PriceHistoryEndOutOfBounds();
error InvalidPriceHistoryRange();
error EmptyHistory();
error InvalidSampleSize();

contract Oracle is Ownable, ReentrancyGuard {

    event ValueSubmitted(address indexed submitter, uint256 indexed timestamp, uint256 submittedValue, uint256 aggregatedValue, uint256 weight, uint256 rewardWei);
    event Funded(address indexed from, uint256 amount);
    event TokenDeposited(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, uint256 amount);
    event Voted(address indexed target, address indexed voter, bool isBlacklist, uint256 weight);
    event BlacklistStatusChanged(address indexed target, bool isBlacklisted);

    IERC20 public immutable WEIGHT_TOKEN;
    
    mapping(address => uint256) public lockedTokens;            // Tokens locked for operations 
    mapping(address => uint256) public unlockedTokens;          // Tokens available for withdrawal 
    uint256 public totalDepositedTokens;
    
    mapping(address => uint256) public depositTimestamp;        // when user last deposited tokens
    mapping(address => uint256) public lastOperationTimestamp;  // when user last performed any operation (submit, vote)
    
    GovernanceLib.GovernanceData private governance;

    mapping(address => uint256) private pof;                     // P(x): last submitted price by x 
    mapping(address => uint256) private wof;                    // W(x): weight of x 
    mapping(address => uint256) private tof;                    // T(x): last submission time of x 

    // Price history tracking
    mapping(uint256 => uint256) public priceHistory;              // timestamp => aggregated price at that time
    mapping(uint256 => uint256) public latestValueHistory;        // timestamp => latest raw submission at that time 
    uint256[] public priceTimestamps;                            // array of timestamps when price was updated
    uint256[] public history;                             // historical aggregated values sampled at fixed interval
    uint256[] public historyTimestamps;                  // timestamps corresponding to entries in history

    uint256 private constant DENOMINATOR = 1e5;
    uint256 private constant WAD = 1e18;

    uint256 private latestValue;                                 // most recent raw submission
    uint256 private aggregatedValue;                             // last aggregated price (decayed weighted mean) 
    uint256 private aggregatedWeight;                            // last decayed total weight
    uint256 public lastUpdated;                                  // Global last update time of a price submission
    uint256 public lastTimestamp;                                // Global last update time of a oracle operation
    string public name;
    string public description;
    
    uint256 public immutable DEPOSIT_LOCKING_PERIOD;              // seconds that tokens must be locked after deposit before operations
    uint256 public immutable WITHDRAWAL_LOCKING_PERIOD;           // seconds that tokens must be locked after last operation before withdrawal
    uint256 public immutable HALF_LIFE_SECONDS;                   // Aggregation config -> HALF_LIFE_SECONDS controls time-decay
    uint256 public immutable Q;                                   // governance constant used in blacklist equation
    uint256 public immutable REWARD_BPS;
    uint256 public immutable GAMMA;                               // minimal interval between entries recorded for extremes
    uint256 public immutable defaultSampleSize;

    modifier notBlacklisted() {
        if (GovernanceLib.isBlacklisted(governance, msg.sender)) revert BlacklistedCaller();
        _;
    }
    modifier onlyTokenHolder() {
        _unlockTokensIfPossible(msg.sender);
        if (unlockedTokens[msg.sender] == 0) revert NoGovernanceWeight();
        _;
    }

    constructor(address owner_, string memory name_,string memory description_, address weightToken_,uint256 halfLifeSeconds_,uint256 q_,uint256 depositLockingPeriod_,uint256 withdrawalLockingPeriod_,uint256 rewardBps_, uint256 gamma_, uint256 defaultSampleSize_) Ownable(owner_) {
        if (weightToken_ == address(0)) revert InvalidWeightTokenAddress();
        if (defaultSampleSize_ == 0) revert InvalidSampleSize();
        WEIGHT_TOKEN = IERC20(weightToken_); HALF_LIFE_SECONDS = halfLifeSeconds_;
        Q = q_; DEPOSIT_LOCKING_PERIOD = depositLockingPeriod_; WITHDRAWAL_LOCKING_PERIOD = withdrawalLockingPeriod_;
        lastTimestamp = block.timestamp; lastUpdated = block.timestamp; REWARD_BPS = rewardBps_; name = name_; description = description_;
        GAMMA = gamma_; defaultSampleSize = defaultSampleSize_;
    }

    receive() external payable {
        lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }
    function deposit() external payable {
        lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }

    function submitValue(uint256 newValue) external nonReentrant onlyTokenHolder {
        uint256 nowTs = block.timestamp;
        lastOperationTimestamp[msg.sender] = nowTs;
        lastTimestamp = nowTs;
        uint256 w = unlockedTokens[msg.sender];                                                        // Using unlocked tokens as weight

        uint256 decayedQ = DecayLib.applyDecay(aggregatedWeight, nowTs - lastUpdated, HALF_LIFE_SECONDS); 

        uint256 lastT = tof[msg.sender]; 
        uint256 oldWeight = wof[msg.sender]; 
        uint256 oldPrice = pof[msg.sender];  
        
        uint256 timeSinceUser = nowTs - lastT;
        uint256 userWeightDecayed = DecayLib.applyDecay(oldWeight, timeSinceUser, HALF_LIFE_SECONDS); // Calculate decayed contributions 

        uint256 sub = oldPrice * userWeightDecayed;
        uint256 numerator; // Calculate new weighted average
        if (aggregatedValue * decayedQ > sub) {
            numerator = aggregatedValue * decayedQ - sub;
        } else {
            numerator = 0;
        }
        uint256 newQ = decayedQ - userWeightDecayed + w;
        numerator += newValue * w;
        uint256 newP = numerator / newQ; 
        
        uint256 rewardPool = (address(this).balance * REWARD_BPS) / DENOMINATOR;                     // Portion of balance reserved for rewards
        uint256 rewardToSubmitter = calculateReward(rewardPool, w, timeSinceUser, decayedQ);
        if (rewardToSubmitter > 0) {
            (bool ok, ) = msg.sender.call{value: rewardToSubmitter}("");
            if (!ok) revert RewardTransferFailed();
        }
 
        // Update all state variables
        aggregatedValue = newP; aggregatedWeight = newQ;
        pof[msg.sender] = newValue; wof[msg.sender] = w; tof[msg.sender] = nowTs;
        lastUpdated = nowTs; latestValue = newValue;
        priceHistory[nowTs] = newP; latestValueHistory[nowTs] = newValue; priceTimestamps.push(nowTs);

        uint256 lastRecordedTs = historyTimestamps.length == 0 ? 0 : historyTimestamps[historyTimestamps.length - 1];
        if (history.length == 0 || nowTs > lastRecordedTs + GAMMA) {
            history.push(newP);
            historyTimestamps.push(nowTs);
        }
        
        emit ValueSubmitted(msg.sender, nowTs, newValue, newP, w, rewardToSubmitter);
    }

    function readValue() external view notBlacklisted returns (uint256) { 
        return aggregatedValue; 
    }
    
    function readLatestValue() external view notBlacklisted returns (uint256) { 
        return latestValue; 
    }

    function readValueInterval() external view notBlacklisted returns (uint256 minValue, uint256 maxValue) {
        if (history.length == 0) revert EmptyHistory();

        uint256 historyLength = history.length;
        uint256 sampleSize = defaultSampleSize;
        if (sampleSize > historyLength) sampleSize = historyLength;

        minValue = history[historyLength - 1];
        maxValue = history[historyLength - 1];

        for (uint256 i = 1; i < sampleSize; ++i) {
            uint256 candidate = history[historyLength - 1 - i];
            if (candidate < minValue) {
                minValue = candidate;
            }
            if (candidate > maxValue) {
                maxValue = candidate;
            }
        }
        return (minValue, maxValue);
    }

    function depositTokens(uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountZero();
        if (!WEIGHT_TOKEN.transferFrom(msg.sender, address(this), amount)) revert TokenTransferFailed();
        _unlockTokensIfPossible(msg.sender);
        
        uint256 nowTs = block.timestamp;
        lockedTokens[msg.sender] += amount; // New deposits are locked for governance and operations
        totalDepositedTokens += amount;
        
        depositTimestamp[msg.sender] = nowTs;
        lastOperationTimestamp[msg.sender] = nowTs;
        lastTimestamp = nowTs;
        emit TokenDeposited(msg.sender, amount);
    }
    
    function withdrawTokens(uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountZero();
        _unlockTokensIfPossible(msg.sender);
        if (unlockedTokens[msg.sender] < amount) revert InsufficientUnlockedBalance();
        uint256 unlockTime = lastOperationTimestamp[msg.sender] + WITHDRAWAL_LOCKING_PERIOD;
        if (unlockTime > block.timestamp) revert WithdrawalLockActive(unlockTime);

        lastTimestamp = block.timestamp;
        if (!WEIGHT_TOKEN.transfer(msg.sender, amount)) revert TokenTransferFailed();
        unlockedTokens[msg.sender] -= amount;
        totalDepositedTokens -= amount;
        
        GovernanceLib.updateUserVoteWeights(governance, msg.sender, unlockedTokens[msg.sender], totalDepositedTokens, Q);
        emit TokenWithdrawn(msg.sender, amount);
    }
    
    function updateUserVoteWeights() external onlyTokenHolder {
        GovernanceLib.updateUserVoteWeights(governance, msg.sender, unlockedTokens[msg.sender], totalDepositedTokens, Q);
    }

    function voteBlacklist(address target) external onlyTokenHolder {
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        GovernanceLib.voteBlacklist(governance, target, msg.sender, unlockedTokens[msg.sender], totalDepositedTokens, Q);                 // Unlocked tokens are used for voting as weight
    }
    
    function voteWhitelist(address target) external onlyTokenHolder {
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        GovernanceLib.voteWhitelist(governance, target, msg.sender, unlockedTokens[msg.sender], totalDepositedTokens, Q);                  // Unlocked tokens are used for voting as weight
    }

    function calculateReward(uint256 rewardPool, uint256 weight, uint256 elapsed, uint256 totalWeight) private view returns (uint256 reward) {
        if (rewardPool == 0 || weight == 0 || totalWeight == 0) return 0;

        uint256 activityFac = DecayLib.activityFactor(elapsed, HALF_LIFE_SECONDS);
        if (activityFac == 0) return 0;
        uint256 num = (weight * activityFac) / WAD; // w * (1 - δ^Δy)
        return (rewardPool * num) / totalWeight;
    }

    // Unlock tokens if the locking periods have elapsed
    function _unlockTokensIfPossible(address user) internal {
        if (block.timestamp >= depositTimestamp[user] + DEPOSIT_LOCKING_PERIOD && lockedTokens[user] > 0) {
            unlockedTokens[user] += lockedTokens[user];
            lockedTokens[user] = 0;
        }
    }
    
    function getPriceHistoryRange(uint256 startIndex, uint256 endIndex) external view returns ( uint256[] memory timestamps,  uint256[] memory aggregatedPrices, uint256[] memory latestValues) {
        if (startIndex >= priceTimestamps.length) revert PriceHistoryStartOutOfBounds();
        if (endIndex > priceTimestamps.length) revert PriceHistoryEndOutOfBounds();
        if (startIndex >= endIndex) revert InvalidPriceHistoryRange();
        
        uint256 length = endIndex - startIndex;
        timestamps = new uint256[](length);
        aggregatedPrices = new uint256[](length);
        latestValues = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 timestamp = priceTimestamps[startIndex + i];
            timestamps[i] = timestamp;
            aggregatedPrices[i] = priceHistory[timestamp];
            latestValues[i] = latestValueHistory[timestamp];
        }
    }

    function getVotes(address target) external view returns (uint256 blacklistVotesCount, uint256 whitelistVotesCount) { return GovernanceLib.getVotes(governance, target); }
    function isBlacklisted(address target) external view returns (bool) { return GovernanceLib.isBlacklisted(governance, target); }
    function getSubmitterInfo(address submitter) external view returns (uint256 lastSubmittedPrice, uint256 lastWeight, uint256 lastSubmittedTime) { return (pof[submitter], wof[submitter], tof[submitter]); }
    function getPriceHistoryLength() external view returns (uint256) { return priceTimestamps.length; }
    function getHistoryLength() external view returns (uint256) { return history.length; } // number of sampled history entries
}
