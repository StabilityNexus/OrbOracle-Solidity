// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Oracle is Ownable, ReentrancyGuard {

    event Submitted(address indexed submitter, int256 value, uint256 weight, uint256 rewardWei, uint256 timestamp);
    event ValueUpdated(int256 value, int256 latestValue, uint256 timestamp);
    event Funded(address indexed from, uint256 amount);
    event TokenDeposited(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, uint256 amount);
    event VotedBlacklist(address indexed target, address indexed voter, bool support, uint256 weight);
    event VotedWhitelist(address indexed target, address indexed voter, bool support, uint256 weight);
    event Blacklisted(address indexed target);
    event Whitelisted(address indexed target);
    event ConfigUpdated(uint256 reward, uint256 halfLifeSeconds, uint256 quorum);

    IERC20 public immutable weightToken;
    mapping(address => bool) public isBlacklisted;
    
    // Token deposit system for voting
    mapping(address => uint256) public depositedTokens;
    uint256 public totalDepositedTokens;
    
    uint256 public immutable depositLockingPeriod;              // seconds that tokens must be locked after deposit before governance operations
    uint256 public immutable withdrawalLockingPeriod;           // seconds that tokens must be locked after last operation before withdrawal
    mapping(address => uint256) public depositTimestamp;        // when user last deposited tokens
    mapping(address => uint256) public lastOperationTimestamp;  // when user last performed any operation (submit, vote)
    
    mapping(address => uint256) public blacklistVotes; // votes to blacklist an address
    mapping(address => uint256) public whitelistVotes; // votes to whitelist an address
    mapping(address => mapping(address => bool)) public hasVotedBlacklist;
    mapping(address => mapping(address => bool)) public hasVotedWhitelist;

    // Oracle values (kept private-like but readable via getters)
    int256 private _value;       // aggregated value (e.g., EWMA)
    int256 private _latestValue; // most recent raw submission
    
    uint256 public _lastTimestamp;

    int256 private _P;        // last average price (decayed weighted mean) 
    uint256 private _Q;       // last decayed total weight

    mapping(address => int256) private _Pof; // P(x): last submitted price by x
    mapping(address => uint256) private _Wof; // W(x): weight of x
    mapping(address => uint256) private _Tof; // T(x): last submission time of x

    uint256 public _T;           // Global last update time

    uint256 public immutable reward; // out of 100000 (1 = 0.001%)
    uint256 public constant DENOMINATOR = 100000;

    // Aggregation config -> halfLifeSeconds controls time-decay in default EWMA formula
    uint256 public immutable halfLifeSeconds;
    uint256 public immutable quorum; // required votes >= quorum% of totalDepositedTokens (out of 10000)
    uint256 public immutable alpha;

    mapping(address => bool) public submitters; // submitters list

    // Modifiers
    modifier notBlacklisted() {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        _;
    }
    modifier onlyTokenHolder() {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        require(depositedTokens[msg.sender] > 0, "No deposited tokens");
        require(block.timestamp >= depositTimestamp[msg.sender] + depositLockingPeriod, "Tokens still in deposit locking period");
        _;
    }

    constructor(
        address owner_,
        address weightToken_,
        uint256 reward_,
        uint256 halfLifeSeconds_,
        uint256 quorum_,
        uint256 depositLockingPeriod_,
        uint256 withdrawalLockingPeriod_,
        uint256 alpha_
    ) Ownable(owner_) {
        require(weightToken_ != address(0), "Invalid token address");
        weightToken = IERC20(weightToken_);

        reward = reward_;
        halfLifeSeconds = halfLifeSeconds_;
        quorum = quorum_;
        depositLockingPeriod = depositLockingPeriod_;
        withdrawalLockingPeriod = withdrawalLockingPeriod_;
        _lastTimestamp = block.timestamp;
        _T = block.timestamp;  
        alpha = alpha_;

        emit ConfigUpdated(reward, halfLifeSeconds, quorum);
    }

    // Funding ETH to the contract
    receive() external payable {
        _lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }
    function deposit() external payable {
        _lastTimestamp = block.timestamp;
        emit Funded(msg.sender, msg.value);
    }

    function submitValue(int256 newValue) external nonReentrant onlyTokenHolder {
        lastOperationTimestamp[msg.sender] = block.timestamp;
        _lastTimestamp = block.timestamp;
        uint256 nowTs = block.timestamp;
        uint256 w = depositedTokens[msg.sender];

        // Step 1: decay global Q
        uint256 decayedQ = _applyDecay(_Q, nowTs - _T);

        // Step 2: Store old values before any state updates
        uint256 lastT = _Tof[msg.sender];  
        uint256 oldWeight = _Wof[msg.sender];  
        int256 oldPrice = _Pof[msg.sender];    
        
        // Calculate decayed contributions
        uint256 timeSinceUser = nowTs - lastT;
        uint256 userWeightDecayed = _applyDecay(oldWeight, timeSinceUser);

        // Step 3: Calculate new weighted average
        int256 numerator = _P * int256(decayedQ) - oldPrice * int256(userWeightDecayed);
        uint256 newQ = decayedQ - userWeightDecayed + w;
        numerator += newValue * int256(w);
        int256 newP = numerator / int256(newQ);
        
        // Step 4: Calculate reward 
        uint256 rewardPool = (address(this).balance * reward) / DENOMINATOR;
        uint256 Qprime = _decayQToNow();  // Current decayed global weight

        // activity factor: 1 - δ^(nowTs - lastT) using OLD timestamp
        uint256 elapsedY = nowTs - lastT;  // Use stored old timestamp
        uint256 activityDecay = _decayFactor(elapsedY);
        uint256 activityFactor = activityDecay >= 1e18 ? 0 : (1e18 - activityDecay);

        // r = rewardPool * w * activityFactor / Q'
        uint256 rewardToSubmitter = 0;
        if (rewardPool > 0 && w > 0 && activityFactor > 0 && Qprime > 0) {
            uint256 num = (w * activityFactor) / 1e18; // w * (1 - δ^Δy)
            rewardToSubmitter = (alpha * rewardPool * num) / Qprime;                // If Qprime ≈ 0, no reward is given (system is effectively inactive)
        }
       
        // pay
        if (rewardToSubmitter > 0) {
            (bool ok, ) = msg.sender.call{value: rewardToSubmitter}("");
            require(ok, "reward transfer failed");
        }
 
        // Step 5: Update all state variables
        _P = newP;
        _Q = newQ;
        _Pof[msg.sender] = newValue;
        _Wof[msg.sender] = w;
        _Tof[msg.sender] = nowTs;
        _T = nowTs;
        _latestValue = newValue;
        submitters[msg.sender] = true;
        
        emit Submitted(msg.sender, newValue, w, rewardToSubmitter, nowTs);
        emit ValueUpdated(newP, newValue, nowTs);
    }

    function readValue() external notBlacklisted returns (int256) { 
        _lastTimestamp = block.timestamp;
        return _P; 
    }
    
    function readLatestValue() external notBlacklisted returns (int256) { 
        _lastTimestamp = block.timestamp;
        return _latestValue; 
    }

    function depositTokens(uint256 amount) external nonReentrant {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        require(amount > 0, "Amount must be positive");
        require(weightToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        _lastTimestamp = block.timestamp;
        depositedTokens[msg.sender] += amount;
        totalDepositedTokens += amount;
        
        depositTimestamp[msg.sender] = block.timestamp;
        
        if (lastOperationTimestamp[msg.sender] == 0) { lastOperationTimestamp[msg.sender] = block.timestamp; }
        emit TokenDeposited(msg.sender, amount);
    }
    
    function withdrawTokens(uint256 amount) external nonReentrant {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        require(amount > 0, "Amount must be positive");
        require(depositedTokens[msg.sender] >= amount, "Insufficient deposited tokens");
        require(block.timestamp >= lastOperationTimestamp[msg.sender] + withdrawalLockingPeriod, "Tokens still in withdrawal locking period after last operation");
        
        _lastTimestamp = block.timestamp;
        require(weightToken.transfer(msg.sender, amount), "Transfer failed");
        depositedTokens[msg.sender] -= amount;
        totalDepositedTokens -= amount;
        
        emit TokenWithdrawn(msg.sender, amount);
    }
    
    /// @notice Get the timestamp when user's tokens will be unlocked for withdrawal
    function getWithdrawalUnlockTime(address user) external view returns (uint256) {
        return lastOperationTimestamp[user] + withdrawalLockingPeriod;
    }
    
    /// @notice Get the timestamp when user's tokens will be unlocked for governance operations
    function getGovernanceUnlockTime(address user) external view returns (uint256) {
        return depositTimestamp[user] + depositLockingPeriod;
    }
    
    /// @notice Check if user's tokens are currently unlocked for withdrawal
    function isWithdrawalUnlocked(address user) external view returns (bool) {
        return block.timestamp >= lastOperationTimestamp[user] + withdrawalLockingPeriod;
    }
    
    /// @notice Check if user's tokens are currently unlocked for governance operations
    function isGovernanceUnlocked(address user) external view returns (bool) {
        return block.timestamp >= depositTimestamp[user] + depositLockingPeriod;
    }

    // Blacklist/Whitelist governance
    function voteBlacklist(address target) external onlyTokenHolder {
        require(!hasVotedBlacklist[target][msg.sender], "Already voted");
        
        lastOperationTimestamp[msg.sender] = block.timestamp;
        _lastTimestamp = block.timestamp;
        hasVotedBlacklist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        blacklistVotes[target] += weight;
        
        emit VotedBlacklist(target, msg.sender, true, weight);
        _updateBlacklistStatus(target);
    }
    
    function voteWhitelist(address target) external onlyTokenHolder {
        require(!hasVotedWhitelist[target][msg.sender], "Already voted");
        
        lastOperationTimestamp[msg.sender] = block.timestamp;
        _lastTimestamp = block.timestamp;
        hasVotedWhitelist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        whitelistVotes[target] += weight;
        
        emit VotedWhitelist(target, msg.sender, true, weight);
        _updateBlacklistStatus(target);
    }
    
    function _updateBlacklistStatus(address target) internal {
        uint256 blacklistVotesCount = blacklistVotes[target];
        uint256 whitelistVotesCount = whitelistVotes[target];
        uint256 totalVotes = blacklistVotesCount + whitelistVotesCount;
        
        bool shouldBlacklist = blacklistVotesCount > whitelistVotesCount && totalVotes > quorum;
        bool wasBlacklisted = isBlacklisted[target];
        isBlacklisted[target] = shouldBlacklist;
        
        // Emit appropriate event if status changed
        if (!wasBlacklisted && shouldBlacklist) { emit Blacklisted(target); } 
        else if (wasBlacklisted && !shouldBlacklist) { emit Whitelisted(target); }
    }

    function _decayQToNow() internal view returns (uint256) {
        if (_Q == 0) return 0;
        uint256 elapsed = block.timestamp - _T; // Use _T for price submission time
        uint256 f = _decayFactor(elapsed); // returns δ^(elapsed) in 1e18 fixed-point
        return (_Q * f) / 1e18;
    }

    function _applyDecay(uint256 value, uint256 elapsed) internal view returns (uint256) {
        if (halfLifeSeconds == 0 || elapsed == 0) return value;
        uint256 decayFactor = _decayFactor(elapsed);
        return (value * decayFactor) / 1e18;
    }

    function _decayFactor(uint256 elapsed) internal view returns (uint256) {
        if (elapsed >= halfLifeSeconds * 2) return 0; 
        return 1e18 - (elapsed * 1e18) / (halfLifeSeconds * 2);
    }
    
    function getVotes(address target) external view returns (uint256 blacklistVotesCount, uint256 whitelistVotesCount) { return (blacklistVotes[target], whitelistVotes[target]); }
    /// @notice Check if an address has any votes for blacklisting (either blacklist)
    function hasBlacklistVotes(address target) external view returns (uint256) {
        return blacklistVotes[target];
    }
    /// @notice Check if an address has any votes for whitelisting (either whitelist)
    function hasWhitelistVotes(address target) external view returns (uint256) {
        return whitelistVotes[target];
    }
    /// @notice Get all submitter-related info for an address to track their activity
    function getSubmitterInfo(address submitter) external view returns ( bool hasEverSubmitted, int256 lastSubmittedPrice, uint256 lastWeight, uint256 lastSubmissionTime) {
        return (submitters[submitter], _Pof[submitter], _Wof[submitter], _Tof[submitter]);
    }
}
