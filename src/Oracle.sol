// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {GovernanceLib} from "./GovernanceLib.sol";
import {DecayLib} from "./DecayLib.sol";

contract Oracle is Ownable, ReentrancyGuard {

    event ValueSubmitted(address indexed submitter, uint256 indexed timestamp, int256 submittedValue, int256 aggregatedValue, uint256 weight, uint256 rewardWei);
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

    mapping(address => int256) private pof;                     // P(x): last submitted price by x
    mapping(address => uint256) private wof;                    // W(x): weight of x
    mapping(address => uint256) private tof;                    // T(x): last submission time of x 

    
    // Price history tracking
    mapping(uint256 => int256) public priceHistory;              // timestamp => aggregated price at that time
    mapping(uint256 => int256) public latestValueHistory;        // timestamp => latest raw submission at that time 
    uint256[] public priceTimestamps;                            // array of timestamps when price was updated

    uint256 private constant DENOMINATOR = 1e5;

    int256  private latestValue;                                 // most recent raw submission
    int256  private aggregatedValue;                             // last aggregated price (decayed weighted mean) 
    uint256 private aggregatedWeight;                            // last decayed total weight
    uint256 public lastSubmissionTime;                           // Global last update time of a price submission
    uint256 public lastTimestamp;                                // Global last update time of a oracle operation
    string public name;
    string public description;
    
    uint256 public immutable DEPOSIT_LOCKING_PERIOD;              // seconds that tokens must be locked after deposit before operations
    uint256 public immutable WITHDRAWAL_LOCKING_PERIOD;           // seconds that tokens must be locked after last operation before withdrawal
    uint256 public immutable REWARD; 
    uint256 public immutable HALF_LIFE_SECONDS;                  // Aggregation config -> HALF_LIFE_SECONDS controls time-decay in default EWMA formula
    uint256 public immutable QUORUM;                              // required votes >= QUORUM% of totalDepositedTokens
    uint256 public immutable ALPHA;

    modifier notBlacklisted() {
        require(!GovernanceLib.isBlacklisted(governance, msg.sender), "Blacklisted");
        _;
    }
    modifier onlyTokenHolder() {
        _unlockTokensIfPossible(msg.sender);
        require(unlockedTokens[msg.sender] > 0, "No locked tokens for governance");
        _;
    }

    constructor(address owner_, string memory name_,string memory description_, address weightToken_,uint256 reward_,uint256 halfLifeSeconds_,uint256 quorum_,uint256 depositLockingPeriod_,uint256 withdrawalLockingPeriod_,uint256 alpha_) Ownable(owner_) {
        require(weightToken_ != address(0), "Invalid token address");
        WEIGHT_TOKEN = IERC20(weightToken_); REWARD = reward_; HALF_LIFE_SECONDS = halfLifeSeconds_;
        QUORUM = quorum_; DEPOSIT_LOCKING_PERIOD = depositLockingPeriod_; WITHDRAWAL_LOCKING_PERIOD = withdrawalLockingPeriod_;
        lastTimestamp = block.timestamp; lastSubmissionTime = block.timestamp; ALPHA = alpha_; name = name_; description = description_;
    }

    receive() external payable {
        lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }
    function deposit() external payable {
        lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }

    function submitValue(int256 newValue) external nonReentrant onlyTokenHolder {
        uint256 nowTs = block.timestamp;
        lastOperationTimestamp[msg.sender] = nowTs;
        lastTimestamp = nowTs;
        uint256 w = unlockedTokens[msg.sender];                                                        // Using unlocked tokens as weight

        uint256 decayedQ = DecayLib.applyDecay(aggregatedWeight, nowTs - lastSubmissionTime, HALF_LIFE_SECONDS);

        uint256 lastT = tof[msg.sender];  
        uint256 oldWeight = wof[msg.sender];  
        int256 oldPrice = pof[msg.sender];            
        
        uint256 timeSinceUser = nowTs - lastT;
        uint256 userWeightDecayed = DecayLib.applyDecay(oldWeight, timeSinceUser, HALF_LIFE_SECONDS); // Calculate decayed contributions 

        int256 numerator = aggregatedValue * int256(decayedQ) - oldPrice * int256(userWeightDecayed); // Calculate new weighted average
        uint256 newQ = decayedQ - userWeightDecayed + w;
        numerator += newValue * int256(w);
        int256 newP = numerator / int256(newQ);
        
        uint256 rewardPool = (address(this).balance * REWARD) / DENOMINATOR;                          // Calculate REWARD 
        uint256 rewardToSubmitter = DecayLib.calculateReward( rewardPool, w, timeSinceUser, decayedQ, ALPHA, HALF_LIFE_SECONDS );
        if (rewardToSubmitter > 0) {
            (bool ok, ) = msg.sender.call{value: rewardToSubmitter}("");
            require(ok, "REWARD transfer failed");
        }
 
        // Update all state variables
        aggregatedValue = newP; aggregatedWeight = newQ;
        pof[msg.sender] = newValue; wof[msg.sender] = w; tof[msg.sender] = nowTs;
        lastSubmissionTime = nowTs; latestValue = newValue;
        priceHistory[nowTs] = newP; latestValueHistory[nowTs] = newValue; priceTimestamps.push(nowTs);
        
        emit ValueSubmitted(msg.sender, nowTs, newValue, newP, w, rewardToSubmitter);
    }

    function readValue() external notBlacklisted returns (int256) { 
        lastTimestamp = block.timestamp;
        return aggregatedValue; 
    }
    
    function readLatestValue() external notBlacklisted returns (int256) { 
        lastTimestamp = block.timestamp;
        return latestValue; 
    }

    function depositTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(WEIGHT_TOKEN.transferFrom(msg.sender, address(this), amount), "Transfer failed");
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
        require(amount > 0, "Amount must be positive");
        _unlockTokensIfPossible(msg.sender);
        require(unlockedTokens[msg.sender] >= amount, "Insufficient unlocked tokens");
        require(lastOperationTimestamp[msg.sender] + WITHDRAWAL_LOCKING_PERIOD <= block.timestamp, "Withdrawal locking period not elapsed");
        
        lastTimestamp = block.timestamp;
        require(WEIGHT_TOKEN.transfer(msg.sender, amount), "Transfer failed");
        unlockedTokens[msg.sender] -= amount;
        totalDepositedTokens -= amount;
        
        GovernanceLib.updateUserVoteWeights(governance, msg.sender, unlockedTokens[msg.sender], QUORUM);
        emit TokenWithdrawn(msg.sender, amount);
    }
    
    function updateUserVoteWeights() external onlyTokenHolder {
        GovernanceLib.updateUserVoteWeights(governance, msg.sender, unlockedTokens[msg.sender], QUORUM);
    }

    function voteBlacklist(address target) external onlyTokenHolder {
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        GovernanceLib.voteBlacklist(governance, target, msg.sender, unlockedTokens[msg.sender], QUORUM);  // Unlocked tokens are used for voting as weight
    }
    
    function voteWhitelist(address target) external onlyTokenHolder {
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        GovernanceLib.voteWhitelist(governance, target, msg.sender, unlockedTokens[msg.sender], QUORUM);   // Unlocked tokens are used for voting as weight
    }

    // Unlock tokens if the locking periods have elapsed
    function _unlockTokensIfPossible(address user) internal {
        if (block.timestamp >= depositTimestamp[user] + DEPOSIT_LOCKING_PERIOD && lockedTokens[user] > 0) {
            unlockedTokens[user] += lockedTokens[user];
            lockedTokens[user] = 0;
        }
    }
    
    function getPriceHistoryRange(uint256 startIndex, uint256 endIndex) external view returns ( uint256[] memory timestamps,  int256[] memory aggregatedPrices, int256[] memory latestValues) {
        require(startIndex < priceTimestamps.length, "Start index out of bounds");
        require(endIndex <= priceTimestamps.length, "End index out of bounds");
        require(startIndex < endIndex, "Invalid range");
        
        uint256 length = endIndex - startIndex;
        timestamps = new uint256[](length);
        aggregatedPrices = new int256[](length);
        latestValues = new int256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            uint256 timestamp = priceTimestamps[startIndex + i];
            timestamps[i] = timestamp;
            aggregatedPrices[i] = priceHistory[timestamp];
            latestValues[i] = latestValueHistory[timestamp];
        }
    }

    function getVotes(address target) external view returns (uint256 blacklistVotesCount, uint256 whitelistVotesCount) { return GovernanceLib.getVotes(governance, target); }
    function isBlacklisted(address target) external view returns (bool) { return GovernanceLib.isBlacklisted(governance, target); }
    function getSubmitterInfo(address submitter) external view returns (int256 lastSubmittedPrice, uint256 lastWeight, uint256 lastSubmittedTime) { return (pof[submitter], wof[submitter], tof[submitter]); }
    function getPriceHistoryLength() external view returns (uint256) { return priceTimestamps.length; }
}