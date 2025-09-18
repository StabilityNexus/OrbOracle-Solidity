// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract Oracle is Ownable, ReentrancyGuard {
    // --------------------------
    // Events
    // --------------------------
    event Submitted(address indexed submitter, int256 value, uint256 weight, uint256 rewardWei, uint256 timestamp);
    event ValueUpdated(int256 value, int256 latestValue, uint256 timestamp);
    event Deposit(address indexed from, uint256 amount);
    event TokenDeposited(address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed user, uint256 amount);
    event VotedBlacklist(address indexed target, address indexed voter, bool support, uint256 weight);
    event VotedWhitelist(address indexed target, address indexed voter, bool support, uint256 weight);
    event Blacklisted(address indexed target);
    event Whitelisted(address indexed target);
    event ConfigUpdated(uint256 rewardBps, uint256 halfLifeSeconds, uint256 quorumBps);

    // --------------------------
    // Core state
    // --------------------------
    IERC20 public immutable weightToken;

    // Reader/operator control
    mapping(address => bool) public isBlacklisted;
    
    // Token deposit system for voting
    mapping(address => uint256) public depositedTokens;
    uint256 public totalDepositedTokens;
    
    // Token locking system
    uint256 public lockingPeriod; // seconds that tokens must be locked after deposit
    mapping(address => uint256) public depositTimestamp; // when user last deposited tokens
    
    // Voting mappings for blacklisting
    mapping(address => uint256) public blacklistYesVotes;
    mapping(address => uint256) public blacklistNoVotes;
    mapping(address => mapping(address => bool)) public hasVotedBlacklist;
    
    // Voting mappings for whitelisting
    mapping(address => uint256) public whitelistYesVotes;
    mapping(address => uint256) public whitelistNoVotes;
    mapping(address => mapping(address => bool)) public hasVotedWhitelist;

    // Oracle values (kept private-like but readable via getters)
    int256 private _value;       // aggregated value (e.g., EWMA)
    int256 private _latestValue; // most recent raw submission
    uint256 private _lastTimestamp;

    // P: last average price (decayed weighted mean)
    int256 private _P;      

    // Q: last decayed total weight
    uint256 private _Q;     

    // Per submitter state
    mapping(address => int256) private _Pof; // P(x): last submitted price by x
    mapping(address => uint256) private _Wof; // W(x): weight of x
    mapping(address => uint256) private _Tof; // T(x): last submission time of x

    // Global last update time
    uint256 private _T;   

    // Reward config (portion of ETH reserve paid on submission)
    // e.g., rewardBps = 1000 => 1% of current ETH balance goes to submitter
    uint256 public rewardBps; // out of 1e5
    uint256 public constant BPS_DENOMINATOR = 100_000;

    // Aggregation config
    // halfLifeSeconds controls time-decay in default EWMA formula
    uint256 public halfLifeSeconds;

    // Governance config
    uint256 public quorumBps; // required votes >= quorumBps% of totalDepositedTokens
    uint256 public alpha;

    // Individual submission tracking
    struct Submission {
        int256 value;           // submitted value
        uint256 weight;         // weight at time of submission
        uint256 timestamp;      // when it was submitted
        bool hasSubmitted;      // whether this address has ever submitted
    }
    mapping(address => Submission) public submissions;

    // --------------------------
    // Modifiers
    // --------------------------
    modifier onlyReader() {
        require(!isBlacklisted[msg.sender], "Blacklisted");
        _;
    }

    modifier onlyTokenHolder() {
        require(depositedTokens[msg.sender] > 0, "No deposited tokens");
        _;
    }

    // --------------------------
    // Constructor
    // --------------------------
    constructor(
        address owner_,
        address weightToken_,
        uint256 rewardBps_,
        uint256 halfLifeSeconds_,
        uint256 quorumBps_,
        uint256 lockingPeriod_,
        uint256 alpha_
    ) Ownable(owner_) {
        require(weightToken_ != address(0), "Invalid token address");
        weightToken = IERC20(weightToken_);

        rewardBps = rewardBps_;
        halfLifeSeconds = halfLifeSeconds_;
        quorumBps = quorumBps_;
        lockingPeriod = lockingPeriod_;
        _lastTimestamp = block.timestamp;
        alpha = alpha_;

        emit ConfigUpdated(rewardBps, halfLifeSeconds, quorumBps);
    }

    // --------------------------
    // Admin (owner) ops
    // --------------------------

    /// @notice Update reward and aggregation/voting config.
    function updateConfig(
        uint256 rewardBps_,
        uint256 halfLifeSeconds_,
        uint256 quorumBps_,
        uint256 lockingPeriod_
    ) external onlyOwner {
        require(rewardBps_ <= 20_000, "rewardBps too high (>20%)"); // safety cap, tweak if needed
        require(quorumBps_ <= 100_000, "quorumBps invalid");
        rewardBps = rewardBps_;
        halfLifeSeconds = halfLifeSeconds_;
        quorumBps = quorumBps_;
        lockingPeriod = lockingPeriod_;
        emit ConfigUpdated(rewardBps, halfLifeSeconds, quorumBps);
    }

    // --------------------------
    // ETH funding
    // --------------------------
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
    function deposit() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // --------------------------
    // Submissions
    // --------------------------
    function submitValue(int256 newValue) external nonReentrant onlyTokenHolder onlyReader {
        uint256 nowTs = block.timestamp;
        uint256 w = depositedTokens[msg.sender];

        // Step 1: decay global Q
        uint256 decayedQ = _applyDecay(_Q, nowTs - _T);

        // Step 2: remove old contribution from P
        uint256 lastT = _Tof[msg.sender];
        uint256 timeSinceUser = lastT == 0 ? 0 : nowTs - lastT;
        uint256 userWeightDecayed = _applyDecay(_Wof[msg.sender], timeSinceUser);

        int256 numerator = _P * int256(decayedQ) - _Pof[msg.sender] * int256(userWeightDecayed);
        // Prevent underflow in subtraction
        uint256 newQ = decayedQ >= userWeightDecayed ? decayedQ - userWeightDecayed + w : w;

        // Step 3: add new contribution
        numerator += newValue * int256(w);
        
        // Prevent division by zero
        if (newQ > 0) {
            _P = numerator / int256(newQ); // updated average price
        } else {
            _P = newValue; // fallback if no total weight
        }
        _Q = newQ;

        // Step 4: update per-user state
        _Pof[msg.sender] = newValue;
        _Wof[msg.sender] = w;
        _Tof[msg.sender] = nowTs;
        _T = nowTs;
        _latestValue = newValue; // Update for readLatestValue()
        _lastTimestamp = nowTs;  // Update for lastUpdateTimestamp()

        // --------------------------
        // Reward by time-decayed share
        // r = alpha * R * [ w * (1 - δ^(now - t(y))) ] / Q'
        // --------------------------
        uint256 rewardPool = (address(this).balance * rewardBps) / BPS_DENOMINATOR;

        // Q' = decayed global weight at "now" (before we add this submission)
        uint256 Qprime = _decayQToNow();

        // activity factor: 1 - δ^(now - t(y))
        uint256 lastTy = _Tof[msg.sender]; // 0 if first time (we'll treat as very old)
        uint256 elapsedY = lastTy == 0 ? type(uint256).max : (block.timestamp - lastTy);
        uint256 activityDecay = _decayFactor(elapsedY);          // δ^(Δy) in 1e18
        uint256 activityFactor = activityDecay >= 1e18 ? 0 : (1e18 - activityDecay);

        // denominator guard: if Q' == 0 (first ever submitter or everyone decayed to ~0),
        // we use the submitter's current weight to avoid div-by-zero and to give them the pool fairly.
        uint256 currentWeight = _Wof[msg.sender];
        uint256 denom = Qprime > 0 ? Qprime : currentWeight;

        // r = rewardPool * w * activityFactor / denom
        uint256 reward = 0;
        if (rewardPool > 0 && currentWeight > 0 && activityFactor > 0) {
            // multiply carefully to maintain precision
            uint256 num = (currentWeight * activityFactor) / 1e18; // w * (1 - δ^Δy)
            reward = alpha * (rewardPool * num) / denom;
        }

        // pay
        if (reward > 0) {
            (bool ok, ) = msg.sender.call{value: reward}("");
            require(ok, "reward transfer failed");
        }

        emit Submitted(msg.sender, newValue, w, reward, nowTs);
        emit ValueUpdated(_P, newValue, nowTs);
    }

    /// @dev Remove a previous contribution from the aggregated value
    function _removeContribution(address /* submitter */, Submission storage prevSubmission) internal {
        if (!prevSubmission.hasSubmitted) return;
        
        // Calculate the decayed weight of the previous submission
        uint256 decayedWeight = _calculateDecayedWeight(
            prevSubmission.weight, 
            prevSubmission.timestamp, 
            block.timestamp
        );
        
        // Remove the previous contribution from the aggregated value
        if (decayedWeight > 0) {
            // Calculate what the previous contribution would be worth now
            int256 decayedContribution = _calculateWeightedContribution(
                prevSubmission.value, 
                decayedWeight, 
                totalDepositedTokens
            );
            // Subtract it from the current aggregated value
            _value -= decayedContribution;
        }
    }
    
    /// @dev Add a new contribution to the aggregated value
    function _addContribution(address /* submitter */, int256 newValue, uint256 weight, uint256 /* timestamp */) internal {
        if (weight == 0 || totalDepositedTokens == 0) return;
        
        // Calculate the weighted contribution
        int256 weightedContribution = _calculateWeightedContribution(newValue, weight, totalDepositedTokens);
        
        // Add it to the aggregated value
        _value += weightedContribution;
    }
    
    /// @dev Calculate how much weight a submission has after time decay
    function _calculateDecayedWeight(uint256 originalWeight, uint256 submissionTime, uint256 currentTime) 
        internal 
        view 
        returns (uint256) 
    {
        if (currentTime <= submissionTime) {
            return originalWeight;
        }
        
        uint256 timeElapsed = currentTime - submissionTime;
        
        // Simple exponential decay: weight = originalWeight * (0.5)^(timeElapsed/halfLife)
        // Approximation: decay = max(0, 1e18 - (timeElapsed * 1e18) / (halfLifeSeconds * 2))
        if (timeElapsed >= halfLifeSeconds * 2) {
            return originalWeight / 4; // Minimum 25% of original weight
        }
        
        uint256 decayFactor = 1e18 - (timeElapsed * 1e18) / (halfLifeSeconds * 2);
        return (originalWeight * decayFactor) / 1e18;
    }
    
    /// @dev Calculate the weighted contribution of a value
    function _calculateWeightedContribution(int256 value, uint256 weight, uint256 totalWeight) 
        internal 
        pure 
        returns (int256) 
    {
        if (totalWeight == 0) return 0;
        
        // contribution = value * (weight / totalWeight)
        // To handle negative values properly:
        uint256 absValue = uint256(value >= 0 ? value : -value);
        uint256 weightedAbs = (absValue * weight) / totalWeight;
        int256 result = int256(weightedAbs);
        
        return value >= 0 ? result : -result;
    }

    // --------------------------
    // Reads (only for non-blacklisted)
    // --------------------------
    function readValue() external view onlyReader returns (int256) { return _P; }
    function readLatestValue() external view onlyReader returns (int256) { return _latestValue; }
    function lastUpdateTimestamp() external view returns (uint256) { return _lastTimestamp; }

    // --------------------------
    // Token deposit/withdrawal system
    // --------------------------
    function depositTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(weightToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        depositedTokens[msg.sender] += amount;
        totalDepositedTokens += amount;
        
        // Update deposit timestamp to reset locking period
        depositTimestamp[msg.sender] = block.timestamp;
        
        emit TokenDeposited(msg.sender, amount);
    }
    
    function withdrawTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(depositedTokens[msg.sender] >= amount, "Insufficient deposited tokens");
        
        // Check locking period
        require(
            block.timestamp >= depositTimestamp[msg.sender] + lockingPeriod,
            "Tokens are still locked"
        );
        
        // Update voting mappings when tokens are withdrawn
        _updateVotesOnWithdrawal(msg.sender, amount);
        
        require(weightToken.transfer(msg.sender, amount), "Transfer failed");
        depositedTokens[msg.sender] -= amount;
        totalDepositedTokens -= amount;
        
        emit TokenWithdrawn(msg.sender, amount);
    }
    
    /// @notice Get the timestamp when user's tokens will be unlocked
    function getUnlockTime(address user) external view returns (uint256) {
        return depositTimestamp[user] + lockingPeriod;
    }
    
    /// @notice Check if user's tokens are currently unlocked
    function isUnlocked(address user) external view returns (bool) {
        return block.timestamp >= depositTimestamp[user] + lockingPeriod;
    }
    
    function _updateVotesOnWithdrawal(address user, uint256 withdrawAmount) internal {
        // When tokens are withdrawn, we need to update the user's submission weight
        // and recalculate their contribution to the aggregated value
        
        Submission storage userSubmission = submissions[user];
        if (userSubmission.hasSubmitted && userSubmission.weight > 0) {
            // Remove the old contribution based on old weight
            _removeContribution(user, userSubmission);
            
            // Update the weight (this happens after the actual withdrawal in withdrawTokens)
            uint256 newWeight = depositedTokens[user] - withdrawAmount;
            
            // Add back the contribution with the new weight
            if (newWeight > 0) {
                _addContribution(user, userSubmission.value, newWeight, userSubmission.timestamp);
                userSubmission.weight = newWeight;
            } else {
                // If user withdraws all tokens, mark as not having submitted
                userSubmission.hasSubmitted = false;
            }
        }
        
        // Note: Voting weight updates are handled by the withdrawal affecting depositedTokens mapping
        // No need to iterate through all addresses for vote updates since votes are based on current deposits
    }

    // --------------------------
    // Blacklist/Whitelist governance
    // --------------------------
    function voteBlacklist(address target, bool support) external onlyTokenHolder onlyReader {
        require(!isBlacklisted[target], "Already blacklisted");
        require(!hasVotedBlacklist[target][msg.sender], "Already voted");
        
        hasVotedBlacklist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        if (support) {
            blacklistYesVotes[target] += weight;
        } else {
            blacklistNoVotes[target] += weight;
        }
        
        emit VotedBlacklist(target, msg.sender, support, weight);
        
        // Check if target should be blacklisted immediately
        _checkAndExecuteBlacklist(target);
    }
    
    function voteWhitelist(address target, bool support) external onlyTokenHolder onlyReader {
        require(isBlacklisted[target], "Not blacklisted");
        require(!hasVotedWhitelist[target][msg.sender], "Already voted");
        
        hasVotedWhitelist[target][msg.sender] = true;
        uint256 weight = depositedTokens[msg.sender];
        
        if (support) {
            whitelistYesVotes[target] += weight;
        } else {
            whitelistNoVotes[target] += weight;
        }
        
        emit VotedWhitelist(target, msg.sender, support, weight);
        
        // Check if target should be whitelisted immediately
        _checkAndExecuteWhitelist(target);
    }
    
    function _checkAndExecuteBlacklist(address target) internal {
        uint256 yesVotes = blacklistYesVotes[target];
        uint256 noVotes = blacklistNoVotes[target];
        
        // Check quorum: yes votes must be >= quorumBps% of totalDepositedTokens
        if (yesVotes * BPS_DENOMINATOR >= quorumBps * totalDepositedTokens) {
            // Check majority: yes votes > no votes
            if (yesVotes > noVotes) {
                isBlacklisted[target] = true;
                emit Blacklisted(target);
            }
        }
    }
    
    function _checkAndExecuteWhitelist(address target) internal {
        uint256 yesVotes = whitelistYesVotes[target];
        uint256 noVotes = whitelistNoVotes[target];
        
        // Check quorum: yes votes must be >= quorumBps% of totalDepositedTokens
        if (yesVotes * BPS_DENOMINATOR >= quorumBps * totalDepositedTokens) {
            // Check majority: yes votes > no votes
            if (yesVotes > noVotes) {
                isBlacklisted[target] = false;
                emit Whitelisted(target);
            }
        }
    }

    function _decayQToNow() internal view returns (uint256) {
        if (_Q == 0) return 0;
        uint256 elapsed = block.timestamp - _lastTimestamp; // or _T if you switch fully to the math state
        uint256 f = _decayFactor(elapsed); // returns δ^(elapsed) in 1e18 fixed-point
        return (_Q * f) / 1e18;
    }

    function _applyDecay(uint256 value, uint256 elapsed) internal view returns (uint256) {
        if (halfLifeSeconds == 0 || elapsed == 0) return value;
        // δ^(elapsed) ≈ exp(-ln(2) * elapsed / halfLife)
        // For simplicity we use a linear approximation or a precomputed lookup
        // Example: using fixed-point math for decay factor
        uint256 decayFactor = _decayFactor(elapsed);
        return (value * decayFactor) / 1e18;
    }

    function _decayFactor(uint256 elapsed) internal view returns (uint256) {
        // Implement exponential decay: δ^(elapsed)
        // You can use a library like PRBMath or compute with binary exponentiation
        // Placeholder: linear approximation for demo
        if (elapsed >= halfLifeSeconds * 2) return 0; 
        return 1e18 - (elapsed * 1e18) / (halfLifeSeconds * 2);
    }
    
    // --------------------------
    // View functions for voting status
    // --------------------------
    function getBlacklistVotes(address target) external view returns (uint256 yesVotes, uint256 noVotes) {
        return (blacklistYesVotes[target], blacklistNoVotes[target]);
    }
    
    function getWhitelistVotes(address target) external view returns (uint256 yesVotes, uint256 noVotes) {
        return (whitelistYesVotes[target], whitelistNoVotes[target]);
    }
    
    function isBlacklistReady(address target) external view returns (bool) {
        uint256 yesVotes = blacklistYesVotes[target];
        uint256 noVotes = blacklistNoVotes[target];
        return (yesVotes * BPS_DENOMINATOR >= quorumBps * totalDepositedTokens) && (yesVotes > noVotes);
    }
    
    function isWhitelistReady(address target) external view returns (bool) {
        uint256 yesVotes = whitelistYesVotes[target];
        uint256 noVotes = whitelistNoVotes[target];
        return (yesVotes * BPS_DENOMINATOR >= quorumBps * totalDepositedTokens) && (yesVotes > noVotes);
    }
}
