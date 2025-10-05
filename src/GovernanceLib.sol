// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GovernanceLib
 * @dev Library for handling blacklist/whitelist governance functionality
 */
library GovernanceLib {
    
    struct GovernanceData {
        mapping(address => bool) isBlacklisted;
        mapping(address => uint256) blacklistVotes;
        mapping(address => uint256) whitelistVotes;
        mapping(address => mapping(address => bool)) hasVotedBlacklist;
        mapping(address => mapping(address => bool)) hasVotedWhitelist;
        mapping(address => mapping(address => uint256)) blacklistVoteWeights;
        mapping(address => mapping(address => uint256)) whitelistVoteWeights;
        mapping(address => address[]) userBlacklistVotes;
        mapping(address => address[]) userWhitelistVotes;
    }
    
    event Voted(address indexed target, address indexed voter, bool isBlacklist, uint256 weight);
    event BlacklistStatusChanged(address indexed target, bool isBlacklisted);

    function voteBlacklist( GovernanceData storage data, address target, address voter, uint256 weight, uint256 quorum ) external {
        require(!data.hasVotedBlacklist[target][voter], "Already voted");
        
        data.hasVotedBlacklist[target][voter] = true;
        data.blacklistVotes[target] += weight;
        data.blacklistVoteWeights[target][voter] = weight;
        data.userBlacklistVotes[voter].push(target);
        
        emit Voted(target, voter, true, weight);
        _updateBlacklistStatus(data, target, quorum);
    }
    
    function voteWhitelist( GovernanceData storage data, address target, address voter, uint256 weight, uint256 quorum ) external {
        require(!data.hasVotedWhitelist[target][voter], "Already voted");
        
        data.hasVotedWhitelist[target][voter] = true;
        data.whitelistVotes[target] += weight;
        data.whitelistVoteWeights[target][voter] = weight;
        data.userWhitelistVotes[voter].push(target);
        
        emit Voted(target, voter, false, weight);
        _updateBlacklistStatus(data, target, quorum);
    }
    
    function updateUserVoteWeights( GovernanceData storage data, address user, uint256 newWeight, uint256 quorum) external {
        // Update blacklist votes
        address[] storage blacklistTargets = data.userBlacklistVotes[user];
        for (uint256 i = 0; i < blacklistTargets.length; i++) {
            address target = blacklistTargets[i];
            if (data.hasVotedBlacklist[target][user]) {
                uint256 oldWeight = data.blacklistVoteWeights[target][user];
                data.blacklistVotes[target] = data.blacklistVotes[target] - oldWeight + newWeight;
                data.blacklistVoteWeights[target][user] = newWeight;
                _updateBlacklistStatus(data, target, quorum);
            }
        }
        
        // Update whitelist votes
        address[] storage whitelistTargets = data.userWhitelistVotes[user];
        for (uint256 i = 0; i < whitelistTargets.length; i++) {
            address target = whitelistTargets[i];
            if (data.hasVotedWhitelist[target][user]) {
                uint256 oldWeight = data.whitelistVoteWeights[target][user];
                data.whitelistVotes[target] = data.whitelistVotes[target] - oldWeight + newWeight;
                data.whitelistVoteWeights[target][user] = newWeight;
                _updateBlacklistStatus(data, target, quorum);
            }
        }
    }
    
    // Internal function to update blacklist status based on votes
    function _updateBlacklistStatus( GovernanceData storage data, address target, uint256 quorum ) private {
        uint256 blacklistVotesCount = data.blacklistVotes[target];
        uint256 whitelistVotesCount = data.whitelistVotes[target];
        uint256 totalVotes = blacklistVotesCount + whitelistVotesCount;
        
        bool shouldBlacklist = blacklistVotesCount > whitelistVotesCount && totalVotes > quorum;
        bool wasBlacklisted = data.isBlacklisted[target];
        data.isBlacklisted[target] = shouldBlacklist;
        
        if (wasBlacklisted != shouldBlacklist) {
            emit BlacklistStatusChanged(target, shouldBlacklist);
        }
    }
    
    function getVotes( GovernanceData storage data, address target) external view returns (uint256 blacklistVotesCount, uint256 whitelistVotesCount) { return (data.blacklistVotes[target], data.whitelistVotes[target]); }
    function isBlacklisted( GovernanceData storage data, address target ) external view returns (bool) { return data.isBlacklisted[target]; }
}
