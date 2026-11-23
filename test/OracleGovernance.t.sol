// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Oracle, BlacklistedCaller} from "../src/Oracle.sol";

contract MockWeightToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OracleGovernanceTest is Test {
    MockWeightToken token;
    Oracle oracle;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockWeightToken();

        oracle = new Oracle(address(this), "Test Oracle", "Governance Test", address(token), 3600, 1e5, 0, 0, 0, 1, 1);

        token.mint(alice, 1 ether);
        token.mint(bob, 100 ether);

        vm.startPrank(alice);
        token.approve(address(oracle), type(uint256).max);
        oracle.depositTokens(1 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(oracle), type(uint256).max);
        oracle.depositTokens(100 ether);
        vm.stopPrank();

        vm.prank(bob);
        oracle.voteBlacklist(alice);

        assertTrue(oracle.isBlacklisted(alice));
    }

    function testBlacklistedUserCannotVoteBlacklist() public {
        address target = makeAddr("target1");

        vm.expectRevert(BlacklistedCaller.selector);
        vm.prank(alice);
        oracle.voteBlacklist(target);
    }

    function testBlacklistedUserCannotVoteWhitelist() public {
        address target = makeAddr("target2");

        vm.expectRevert(BlacklistedCaller.selector);
        vm.prank(alice);
        oracle.voteWhitelist(target);
    }
    function testNonBlacklistedUserCanStillVote() public {
    address target = makeAddr("target3");

    vm.prank(bob);
    oracle.voteBlacklist(target);

    (uint256 blacklistVotes, ) = oracle.getVotes(target);

    assertEq(blacklistVotes, 100 ether);
}
}
