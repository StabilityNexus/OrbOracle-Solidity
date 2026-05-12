// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

uint256 constant DENOMINATOR = 1e5;



/// @title GovernanceLib
/// @dev Library for handling blacklist/whitelist governance functionality
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

    function voteBlacklist( GovernanceData storage data, address target, address voter, uint256 weight, uint256 totalSupply, uint256 q ) external {
        uint256 oldBlacklistWeight = data.blacklistVoteWeights[target][voter];
        uint256 oldWhitelistWeight = data.whitelistVoteWeights[target][voter];

        // Update blacklist votes
        if (oldBlacklistWeight > 0) {
            data.blacklistVotes[target] -= oldBlacklistWeight;
        } else if (!data.hasVotedBlacklist[target][voter]) {
            data.userBlacklistVotes[voter].push(target);
        }
        data.blacklistVotes[target] += weight;
        data.blacklistVoteWeights[target][voter] = weight;
        data.hasVotedBlacklist[target][voter] = true;

        // Cancel whitelist vote for this target
        if (oldWhitelistWeight > 0) {
            data.whitelistVotes[target] -= oldWhitelistWeight;
            data.whitelistVoteWeights[target][voter] = 0;
            data.hasVotedWhitelist[target][voter] = false;
        }

        emit Voted(target, voter, true, weight);
        _updateBlacklistStatus(data, target, totalSupply, q);
    }

    function voteWhitelist( GovernanceData storage data, address target, address voter, uint256 weight, uint256 totalSupply, uint256 q ) external {
        uint256 oldWhitelistWeight = data.whitelistVoteWeights[target][voter];
        uint256 oldBlacklistWeight = data.blacklistVoteWeights[target][voter];

        // Update whitelist votes
        if (oldWhitelistWeight > 0) {
            data.whitelistVotes[target] -= oldWhitelistWeight;
        } else if (!data.hasVotedWhitelist[target][voter]) {
            data.userWhitelistVotes[voter].push(target);
        }
        data.whitelistVotes[target] += weight;
        data.whitelistVoteWeights[target][voter] = weight;
        data.hasVotedWhitelist[target][voter] = true;

        // Cancel blacklist vote for this target
        if (oldBlacklistWeight > 0) {
            data.blacklistVotes[target] -= oldBlacklistWeight;
            data.blacklistVoteWeights[target][voter] = 0;
            data.hasVotedBlacklist[target][voter] = false;
        }

        emit Voted(target, voter, false, weight);
        _updateBlacklistStatus(data, target, totalSupply, q);
    }

    function updateUserVoteWeights( GovernanceData storage data, address user, uint256 newWeight, uint256 totalSupply, uint256 q) external {
        // Update blacklist votes
        address[] storage blacklistTargets = data.userBlacklistVotes[user];
        for (uint256 i = 0; i < blacklistTargets.length; i++) {
            address target = blacklistTargets[i];
            if (data.hasVotedBlacklist[target][user]) {
                uint256 oldWeight = data.blacklistVoteWeights[target][user];
                data.blacklistVotes[target] = data.blacklistVotes[target] - oldWeight + newWeight;
                data.blacklistVoteWeights[target][user] = newWeight;
                _updateBlacklistStatus(data, target, totalSupply, q);
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
                _updateBlacklistStatus(data, target, totalSupply, q);
            }
        }
    }

    // Internal function to update blacklist status based on votes
    function _updateBlacklistStatus( GovernanceData storage data, address target, uint256 totalSupply, uint256 q ) private {
        uint256 blacklistVotesCount = data.blacklistVotes[target];
        uint256 whitelistVotesCount = data.whitelistVotes[target];
        uint256 totalVotes = blacklistVotesCount + whitelistVotesCount;
        uint256 diff = blacklistVotesCount > whitelistVotesCount ? blacklistVotesCount - whitelistVotesCount : 0;
        uint256 undecided = totalSupply > totalVotes ? totalSupply - totalVotes : 0;
        bool shouldBlacklist = diff * DENOMINATOR > q * undecided;
        bool wasBlacklisted = data.isBlacklisted[target];
        data.isBlacklisted[target] = shouldBlacklist;

        if (wasBlacklisted != shouldBlacklist) {
            emit BlacklistStatusChanged(target, shouldBlacklist);
        }
    }
    
    function getVotes( GovernanceData storage data, address target) external view returns (uint256 blacklistVotesCount, uint256 whitelistVotesCount) { return (data.blacklistVotes[target], data.whitelistVotes[target]); }
    function isBlacklisted( GovernanceData storage data, address target ) external view returns (bool) { return data.isBlacklisted[target]; }
}
