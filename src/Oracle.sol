// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Oracle is Ownable, ReentrancyGuard {

    event PriceSubmitted(address indexed submitter, uint256 indexed timestamp, int256 submittedValue, int256 aggregatedPrice, uint256 weight, uint256 rewardWei);
    event Funded(address indexed from, uint256 amount);
    event TokenDeposited(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, uint256 amount);
    event Voted(address indexed target, address indexed voter, bool isBlacklist, uint256 weight);
    event BlacklistStatusChanged(address indexed target, bool isBlacklisted);

    IERC20 public immutable WEIGHT_TOKEN;
    
    mapping(address => uint256) public depositedTokens;         // Token deposit system for voting
    uint256 public totalDepositedTokens;
    
    mapping(address => uint256) public depositTimestamp;        // when user last deposited tokens
    mapping(address => uint256) public lastOperationTimestamp;  // when user last performed any operation (submit, vote)
    
    mapping(address => bool) public isBlacklisted;              // blacklist status of an address
    mapping(address => uint256) public blacklistVotes;          // votes to blacklist an address
    mapping(address => uint256) public whitelistVotes;          // votes to whitelist an address
    mapping(address => mapping(address => bool)) public hasVotedBlacklist;
    mapping(address => mapping(address => bool)) public hasVotedWhitelist;
    
    mapping(address => mapping(address => uint256)) public blacklistVoteWeights;   // Store individual vote weights: target => voter => weight
    mapping(address => mapping(address => uint256)) public whitelistVoteWeights;

    mapping(address => int256) private pof;                    // P(x): last submitted price by x
    mapping(address => uint256) private wof;                   // W(x): weight of x
    mapping(address => uint256) private tof;                   // T(x): last submission time of x

    mapping(address => address[]) public userBlacklistVotes;    // user => array of addresses they voted to blacklist
    mapping(address => address[]) public userWhitelistVotes;    // user => array of addresses they voted to whitelist
    
    // Price history tracking
    mapping(uint256 => int256) public priceHistory;              // timestamp => aggregated price at that time
    mapping(uint256 => int256) public latestValueHistory;        // timestamp => latest raw submission at that time
    uint256[] public priceTimestamps;                            // array of timestamps when price was updated

    uint256[61] private pow2NegIntWad = [1_000000000000000000, 500000000000000000, 250000000000000000, 125000000000000000,62500000000000000, 31250000000000000, 15625000000000000, 7812500000000000,3906250000000000, 1953125000000000, 976562500000000, 488281250000000,244140625000000, 122070312500000, 61035156250000, 30517578125000,15258789062500, 7629394531250, 3814697265625, 1907348632812, 953674316406,476837158203, 238418579102, 119209289551, 59604644775, 29802322388,14901161194, 7450580597, 3725290298, 1862645149, 931322574, 465661287,232830643, 116415322, 58207661, 29103831, 14551915, 7275958, 3637979, 1818989,909495, 454747, 227373, 113687, 56843, 28422, 14211, 7105, 3553, 1776, 888,444, 222, 111, 56, 28, 14, 7, 3, 2, 1];
    uint256 private constant WAD = 1e18;
    uint256 private constant DENOMINATOR = 1e5;

    int256  private _value;                                      // aggregated value (e.g., EWMA)
    int256  private latestValue;                                 // most recent raw submission
    int256  private aggregatedPrice;                             // last average price (decayed weighted mean) 
    uint256 private aggregatedWeight;                            // last decayed total weight
    uint256 public lastSubmissionTime;                           // Global last update time of a price submission
    uint256 public lastTimestamp;                                // Global last update time of a oracle operation

    // Aggregation config -> HALF_LIFE_SECONDS controls time-decay in default EWMA formula
    uint256 public immutable DEPOSIT_LOCKING_PERIOD;              // seconds that tokens must be locked after deposit before governance operations
    uint256 public immutable WITHDRAWAL_LOCKING_PERIOD;           // seconds that tokens must be locked after last operation before withdrawal
    uint256 public immutable REWARD; 
    uint256 public immutable HALF_LIFE_SECONDS;
    uint256 public immutable QUORUM;                              // required votes >= QUORUM% of totalDepositedTokens (out of 10000)
    uint256 public immutable ALPHA;

    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        _;
    }
    modifier onlyTokenHolder() {
        require(depositedTokens[msg.sender] > 0, "No deposited tokens");
        require(block.timestamp >= getTokenUnlockTime(msg.sender), "Tokens still in deposit locking period");
        _;
    }

    constructor(address owner_,address weightToken_,uint256 reward_,uint256 halfLifeSeconds_,uint256 quorum_,uint256 depositLockingPeriod_,uint256 withdrawalLockingPeriod_,uint256 alpha_) Ownable(owner_) {
        require(weightToken_ != address(0), "Invalid token address");
        WEIGHT_TOKEN = IERC20(weightToken_); REWARD = reward_; HALF_LIFE_SECONDS = halfLifeSeconds_;
        QUORUM = quorum_; DEPOSIT_LOCKING_PERIOD = depositLockingPeriod_; WITHDRAWAL_LOCKING_PERIOD = withdrawalLockingPeriod_;
        lastTimestamp = block.timestamp; lastSubmissionTime = block.timestamp; ALPHA = alpha_;
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
        uint256 w = depositedTokens[msg.sender];

        uint256 decayedQ = _applyDecay(aggregatedWeight, nowTs - lastSubmissionTime);

        uint256 lastT = tof[msg.sender];  
        uint256 oldWeight = wof[msg.sender];  
        int256 oldPrice = pof[msg.sender];            
        
        uint256 timeSinceUser = nowTs - lastT;
        uint256 userWeightDecayed = _applyDecay(oldWeight, timeSinceUser);               // Calculate decayed contributions 

        int256 numerator = aggregatedPrice * int256(decayedQ) - oldPrice * int256(userWeightDecayed); // Calculate new weighted average
        uint256 newQ = decayedQ - userWeightDecayed + w;
        numerator += newValue * int256(w);
        int256 newP = numerator / int256(newQ);
        
        uint256 rewardPool = (address(this).balance * REWARD) / DENOMINATOR;             // Calculate REWARD 

        uint256 activityDecay = _decayFactor(timeSinceUser);
        uint256 activityFactor = activityDecay >= 1e18 ? 0 : (1e18 - activityDecay);

        uint256 rewardToSubmitter = 0;                                                   // r = rewardPool * w * activityFactor / Q'
        if (rewardPool > 0 && w > 0 && activityFactor > 0 && decayedQ > 0) {
            uint256 num = (w * activityFactor) / 1e18;                                   // w * (1 - δ^Δy)
            rewardToSubmitter = (ALPHA * rewardPool * num) / decayedQ;                   // If decayedQ ≈ 0, no REWARD is given (system is effectively inactive)
        }
       
        if (rewardToSubmitter > 0) {
            (bool ok, ) = msg.sender.call{value: rewardToSubmitter}("");
            require(ok, "REWARD transfer failed");
        }
 
        // Update all state variables
        aggregatedPrice = newP; aggregatedWeight = newQ;
        pof[msg.sender] = newValue; wof[msg.sender] = w; tof[msg.sender] = nowTs;
        lastSubmissionTime = nowTs; latestValue = newValue;
        priceHistory[nowTs] = newP; latestValueHistory[nowTs] = newValue; priceTimestamps.push(nowTs);
        
        emit PriceSubmitted(msg.sender, nowTs, newValue, newP, w, rewardToSubmitter);
    }

    function readValue() external notBlacklisted returns (int256) { 
        lastTimestamp = block.timestamp;
        return aggregatedPrice; 
    }
    
    function readLatestValue() external notBlacklisted returns (int256) { 
        lastTimestamp = block.timestamp;
        return latestValue; 
    }

    function depositTokens(uint256 amount) external nonReentrant {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        require(amount > 0, "Amount must be positive");
        require(WEIGHT_TOKEN.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        lastTimestamp = block.timestamp;
        depositedTokens[msg.sender] += amount;
        totalDepositedTokens += amount;
        
        depositTimestamp[msg.sender] = block.timestamp;
        if (lastOperationTimestamp[msg.sender] == 0) { lastOperationTimestamp[msg.sender] = block.timestamp; }
        
        _updateUserVoteWeights(msg.sender);
        emit TokenDeposited(msg.sender, amount);
    }
    
    function withdrawTokens(uint256 amount) external nonReentrant {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        require(amount > 0, "Amount must be positive");
        require(depositedTokens[msg.sender] >= amount, "Insufficient deposited tokens");
        require(block.timestamp >= getTokenUnlockTime(msg.sender), "Tokens still in withdrawal locking period after last operation");
        
        lastTimestamp = block.timestamp;
        require(WEIGHT_TOKEN.transfer(msg.sender, amount), "Transfer failed");
        depositedTokens[msg.sender] -= amount;
        totalDepositedTokens -= amount;
        
        _updateUserVoteWeights(msg.sender);
        emit TokenWithdrawn(msg.sender, amount);
    }
    

    function voteBlacklist(address target) external onlyTokenHolder {
        require(!hasVotedBlacklist[target][msg.sender], "Already voted");
        
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        hasVotedBlacklist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        blacklistVotes[target] += weight;
        blacklistVoteWeights[target][msg.sender] = weight;
        userBlacklistVotes[msg.sender].push(target);
        
        emit Voted(target, msg.sender, true, weight);
        _updateBlacklistStatus(target);
    }
    
    function voteWhitelist(address target) external onlyTokenHolder {
        require(!hasVotedWhitelist[target][msg.sender], "Already voted");
        
        lastOperationTimestamp[msg.sender] = block.timestamp;
        lastTimestamp = block.timestamp;
        hasVotedWhitelist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        whitelistVotes[target] += weight;
        whitelistVoteWeights[target][msg.sender] = weight;
        userWhitelistVotes[msg.sender].push(target);
        
        emit Voted(target, msg.sender, false, weight);
        _updateBlacklistStatus(target);
    }
    
    function _updateUserVoteWeights(address user) internal {
        uint256 newWeight = depositedTokens[user];
        
        address[] storage blacklistTargets = userBlacklistVotes[user];          // Update blacklist votes
        for (uint256 i = 0; i < blacklistTargets.length; i++) {
            address target = blacklistTargets[i];
            if (hasVotedBlacklist[target][user]) {
                uint256 oldWeight = blacklistVoteWeights[target][user];
                blacklistVotes[target] = blacklistVotes[target] - oldWeight + newWeight;
                blacklistVoteWeights[target][user] = newWeight;
                _updateBlacklistStatus(target);
            }
        }
        
        address[] storage whitelistTargets = userWhitelistVotes[user];          // Update whitelist votes
        for (uint256 i = 0; i < whitelistTargets.length; i++) {
            address target = whitelistTargets[i];
            if (hasVotedWhitelist[target][user]) {
                uint256 oldWeight = whitelistVoteWeights[target][user];
                whitelistVotes[target] = whitelistVotes[target] - oldWeight + newWeight;
                whitelistVoteWeights[target][user] = newWeight;
                _updateBlacklistStatus(target);
            }
        }
    }

    function _updateBlacklistStatus(address target) internal {
        uint256 blacklistVotesCount = blacklistVotes[target];
        uint256 whitelistVotesCount = whitelistVotes[target];
        uint256 totalVotes = blacklistVotesCount + whitelistVotesCount;
        
        bool shouldBlacklist = blacklistVotesCount > whitelistVotesCount && totalVotes > QUORUM;
        bool wasBlacklisted = isBlacklisted[target];
        isBlacklisted[target] = shouldBlacklist;
        
        if (wasBlacklisted != shouldBlacklist) {
            emit BlacklistStatusChanged(target, shouldBlacklist);
        }
    }

    function _applyDecay(uint256 value, uint256 elapsed) internal view returns (uint256) {
        if (value == 0) return 0;
        uint256 f = _decayFactor(elapsed);        
        return (value * f) / WAD;
    }

    function _decayFactor(uint256 elapsed) internal view returns (uint256) {
        if (elapsed == 0) return WAD;
        if (HALF_LIFE_SECONDS == 0) return WAD;           // no decay if HL=0

        uint256 scaledX = (elapsed * DENOMINATOR) / HALF_LIFE_SECONDS;
        if (scaledX >= 61 * DENOMINATOR) return 1;      // If x >= 61 -> ~0 (2^-61 ~ 4.3e-19) ; ~0 in 1e18 scale

        uint256 k    = scaledX / DENOMINATOR;           // integer part
        uint256 frac = scaledX % DENOMINATOR;           // 0..99999 (fractional 5dp)

        if (frac == 0) return pow2NegIntWad[k];

        uint256 hi = pow2NegIntWad[k];
        uint256 lo = (k < 60) ? pow2NegIntWad[k + 1] : 0;
        unchecked {return hi - ((hi - lo) * frac) / DENOMINATOR;}
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

    function getTokenUnlockTime(address user) public view returns (uint256) { return lastOperationTimestamp[user] + WITHDRAWAL_LOCKING_PERIOD; }
    function hasBlacklistVotes(address target) external view returns (uint256) { return blacklistVotes[target]; }
    function hasWhitelistVotes(address target) external view returns (uint256) { return whitelistVotes[target]; }
    function getSubmitterInfo(address submitter) external view returns (int256 lastSubmittedPrice, uint256 lastWeight, uint256 lastSubmittedTime) { return (pof[submitter], wof[submitter], tof[submitter]); }
    function getPriceHistoryLength() external view returns (uint256) { return priceTimestamps.length; }
}