// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Oracle, ValueOutOfRange} from "../src/Oracle.sol";
import {ComposedOracleByDivision} from "../src/ComposedOracle.sol";

contract MockBandToken is ERC20 {
    constructor() ERC20("Weight", "WGT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OracleValueBandTest is Test {
    uint256 internal constant HALF_LIFE = 60;
    uint256 internal constant LOCK = 60;
    uint256 internal constant PRICE = 3000e18;

    MockBandToken internal token;
    Oracle internal oracle;

    address internal honest = makeAddr("honest");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        token = new MockBandToken();
        oracle = _newOracleWithPrice(1_000_000e18);
    }

    // Honest stakes `honestStake` and submits PRICE. The attacker stakes 1 wei. Both locks have passed.
    function _newOracleWithPrice(uint256 honestStake) internal returns (Oracle o) {
        // owner, name, description, token, halfLife, q, depositLock, withdrawalLock, rewardBps, gamma, sampleSize
        o = new Oracle(address(this), "ETH/USD", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
        _stake(o, honest, honestStake);
        _stake(o, attacker, 1);
        vm.warp(vm.getBlockTimestamp() + LOCK + 1);
        _submit(o, honest, PRICE);
        vm.warp(vm.getBlockTimestamp() + 1);
    }

    function _stake(Oracle o, address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(o), amount);
        o.depositTokens(amount);
        vm.stopPrank();
    }

    function _submit(Oracle o, address user, uint256 value) internal {
        vm.prank(user);
        o.submitValue(value);
    }

    // The band submitValue enforces: a move of at most a factor 1 + 9 * stake / totalDeposited.
    function _band(Oracle o, address user) internal view returns (uint256 minValue, uint256 maxValue) {
        uint256 stake = o.unlockedTokens(user) + o.lockedTokens(user);
        uint256 total = o.totalDepositedTokens();
        uint256 current = o.readValue();
        uint256 moveWeight = 9 * stake;
        maxValue = current > type(uint256).max / 10 || current > type(uint256).max / moveWeight
            ? type(uint256).max
            : current + current * moveWeight / total;
        minValue = current > type(uint256).max / total
            ? current / (total + moveWeight) * total
            : current * total / (total + moveWeight);
    }

    function test_FirstSubmissionHasNoBand() public {
        Oracle o =
            new Oracle(address(this), "New", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
        _stake(o, honest, 1e18);
        vm.warp(vm.getBlockTimestamp() + LOCK + 1);
        _submit(o, honest, 1e40);
        assertEq(o.readValue(), 1e40);
    }

    function test_DustFarAboveTheFeedReverts() public {
        (uint256 minValue, uint256 maxValue) = _band(oracle, attacker);
        vm.expectRevert(abi.encodeWithSelector(ValueOutOfRange.selector, 1e60, minValue, maxValue));
        _submit(oracle, attacker, 1e60);
        assertEq(oracle.readValue(), PRICE);
        assertEq(oracle.readLatestValue(), PRICE);
    }

    function test_DustFarBelowTheFeedReverts() public {
        (uint256 minValue, uint256 maxValue) = _band(oracle, attacker);
        vm.expectRevert(abi.encodeWithSelector(ValueOutOfRange.selector, 0, minValue, maxValue));
        _submit(oracle, attacker, 0);
        assertEq(oracle.readValue(), PRICE);
    }

    function test_BandEdgesAreAccepted() public {
        (uint256 minValue, uint256 maxValue) = _band(oracle, honest);
        assertApproxEqRel(maxValue, PRICE * 10, 1e6);
        assertApproxEqRel(minValue, PRICE / 10, 1e6);

        uint256 snapshot = vm.snapshotState();
        _submit(oracle, honest, maxValue);
        vm.revertToState(snapshot);
        _submit(oracle, honest, minValue);
        vm.revertToState(snapshot);

        vm.expectRevert(abi.encodeWithSelector(ValueOutOfRange.selector, maxValue + 1, minValue, maxValue));
        _submit(oracle, honest, maxValue + 1);
        vm.expectRevert(abi.encodeWithSelector(ValueOutOfRange.selector, minValue - 1, minValue, maxValue));
        _submit(oracle, honest, minValue - 1);
    }

    function test_DustAtItsBandEdgeDoesNotMoveTheFeed() public {
        (, uint256 maxValue) = _band(oracle, attacker);
        _submit(oracle, attacker, maxValue);
        assertApproxEqRel(oracle.readValue(), PRICE, 1e6);
    }

    // Holding almost all deposits, a real 50x move takes two submissions.
    function test_LargeStakeFollowsALargeMoveInSteps() public {
        (, uint256 maxValue) = _band(oracle, honest);
        _submit(oracle, honest, maxValue);
        vm.warp(vm.getBlockTimestamp() + 1);
        _submit(oracle, honest, PRICE * 50);
        assertEq(oracle.readValue(), PRICE * 50);
    }

    // The live Sepolia feed has 105e15 wei deposited and was idle for weeks. The old weight has decayed away,
    // so a 1 wei submitter is almost the whole decayed weight. Deposits do not decay, so its band stays tiny.
    function test_IdleLowStakeFeedCannotBeWalkedAway() public {
        Oracle o = _newOracleWithPrice(105e15);
        vm.warp(vm.getBlockTimestamp() + 70 days);

        (uint256 minValue, uint256 maxValue) = _band(o, attacker);
        vm.expectRevert(abi.encodeWithSelector(ValueOutOfRange.selector, PRICE * 10, minValue, maxValue));
        _submit(o, attacker, PRICE * 10);

        for (uint256 i = 0; i < 5; i++) {
            (, maxValue) = _band(o, attacker);
            _submit(o, attacker, maxValue);
            vm.warp(vm.getBlockTimestamp() + 1);
        }
        assertApproxEqRel(o.readValue(), PRICE, 1e6);
    }

    function test_IdleFeedStillFollowsItsMainStaker() public {
        Oracle o = _newOracleWithPrice(105e15);
        vm.warp(vm.getBlockTimestamp() + 70 days);
        _submit(o, honest, PRICE * 5);
        assertEq(o.readValue(), PRICE * 5);
    }

    // The division composed oracle no longer drops to zero and reverts after a dust outlier.
    function test_ComposedOracleSurvivesADustOutlier() public {
        Oracle base =
            new Oracle(address(this), "USD/EUR", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
        _stake(base, honest, 1e18);
        vm.warp(vm.getBlockTimestamp() + LOCK + 1);
        _submit(base, honest, 1e18);
        ComposedOracleByDivision composed = new ComposedOracleByDivision(address(base), address(oracle), true, 5, "c");
        uint256 before = composed.readValue();

        vm.prank(attacker);
        try oracle.submitValue(1e60) {} catch {}
        assertEq(composed.readValue(), before);
    }

    // Whatever a 1 wei staker submits after any idle time, the feed stays within 1e-12 of the honest price.
    function testFuzz_DustCannotMoveTheFeed(uint256 value, uint256 idle) public {
        vm.warp(vm.getBlockTimestamp() + bound(idle, 0, 365 days));
        vm.prank(attacker);
        try oracle.submitValue(value) {} catch {}
        assertApproxEqRel(oracle.readValue(), PRICE, 1e6);
    }

    // Same on the low stake feed.
    function testFuzz_DustCannotMoveAnIdleLowStakeFeed(uint256 value, uint256 idle) public {
        Oracle o = _newOracleWithPrice(105e15);
        vm.warp(vm.getBlockTimestamp() + bound(idle, 0, 365 days));
        vm.prank(attacker);
        try o.submitValue(value) {} catch {}
        assertApproxEqRel(o.readValue(), PRICE, 1e6);
    }

    // If a tiny stake gets in first with a huge value, the main staker can still walk it back one submit per half
    // life. It takes 67 submits here because each resubmit leaves part of the old value behind (the decay issue #25).
    // Before the overflow guard the band math itself overflowed here and every honest submit reverted.
    function test_ColdStartOutlierCanBeWalkedBack() public {
        Oracle o =
            new Oracle(address(this), "New", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
        _stake(o, honest, 1e18);
        _stake(o, attacker, 1);
        vm.warp(vm.getBlockTimestamp() + LOCK + 1);
        _submit(o, attacker, 1e60);

        uint256 steps;
        while (o.readValue() > PRICE * 9) {
            (uint256 minValue,) = _band(o, honest);
            _submit(o, honest, minValue);
            steps++;
            vm.warp(vm.getBlockTimestamp() + HALF_LIFE); // the 1 wei weight at 1e60 decays away
        }
        _submit(o, honest, PRICE);
        assertLt(o.readValue(), PRICE * 10);
        assertLt(steps, 100);
    }

    // The band math never panics, even for the largest values. A submit either works or reverts with
    // ValueOutOfRange.
    function testFuzz_BandMathNeverOverflows(uint256 first, uint256 next) public {
        Oracle o =
            new Oracle(address(this), "New", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
        _stake(o, honest, 1e18);
        _stake(o, attacker, 1);
        vm.warp(vm.getBlockTimestamp() + LOCK + 1);
        _submit(o, attacker, first);
        next = bound(next, 0, 1e58); // larger values overflow newValue * w further down, as on main

        vm.prank(honest);
        try o.submitValue(next) {}
        catch (bytes memory err) {
            assertEq(bytes4(err), ValueOutOfRange.selector);
        }
    }
}
