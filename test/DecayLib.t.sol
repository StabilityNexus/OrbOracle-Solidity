// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Oracle} from "../src/Oracle.sol";
import {DecayLib} from "../src/DecayLib.sol";

contract MockDecayToken is ERC20 {
    constructor() ERC20("Weight", "WGT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DecayLibTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_LIFE = 60;

    function test_DecayFactorKnownValues() public pure {
        assertEq(DecayLib.decayFactor(0, HALF_LIFE), WAD);
        assertEq(DecayLib.decayFactor(HALF_LIFE, HALF_LIFE), WAD / 2);
        assertEq(DecayLib.decayFactor(2 * HALF_LIFE, HALF_LIFE), WAD / 4);
        // 2^-0.5 = 0.707106781186547524400...
        assertApproxEqAbs(DecayLib.decayFactor(HALF_LIFE / 2, HALF_LIFE), 707106781186547524, 1);
        // 2^-0.25 = 0.840896415253714543031...
        assertApproxEqAbs(DecayLib.decayFactor(HALF_LIFE / 4, HALF_LIFE), 840896415253714543, 1);
        // Reward activity 1 - 2^(-1/60) = 0.011485979647103864... The old straight-line code gave 0.5/60 = 0.008333...,
        // so a submitter who posts every second now earns about 1.38 times as much.
        assertApproxEqAbs(DecayLib.activityFactor(1, HALF_LIFE), 11485979647103864, 2);
        // No decay when the half-life is 0.
        assertEq(DecayLib.decayFactor(1000, 0), WAD);
        // Fully decayed after a huge number of half-lives (the shift must not wrap around).
        assertEq(DecayLib.applyDecay(WAD, (uint256(1) << 192) * HALF_LIFE, HALF_LIFE), 0);
        assertEq(DecayLib.decayFactor(type(uint256).max, 1), 0);
        // No decay for an empty or reversed interval.
        assertEq(DecayLib.applyDecayBetween(WAD, 500, 500, HALF_LIFE), WAD);
        assertEq(DecayLib.applyDecayBetween(WAD, 500, 100, HALF_LIFE), WAD);
    }

    // With halfLife = 2^64 the fraction of a half-life is elapsed itself, so these hit chosen bits of the
    // constant table. Expected values are floor(2^200 * 2^(-elapsed / 2^64)), computed to 150 digits.
    function test_FractionTableMatchesExactPowers() public pure {
        uint256 value = 1 << 200;
        uint256 halfLife = 1 << 64;
        uint256 tolerance = 64 << 72; // one rounding step per constant, scaled by 2^72
        // every bit of the fraction set
        assertApproxEqAbs(
            DecayLib.applyDecay(value, halfLife - 1, halfLife),
            803469022129495137801171863863447002911325565967588446044182,
            tolerance
        );
        // only the top bit set: 2^-0.5
        assertApproxEqAbs(
            DecayLib.applyDecay(value, 1 << 63, halfLife),
            1136276788042180458070828951474823657989790988021617205464301,
            tolerance
        );
        // only the lowest bit set
        assertApproxEqAbs(
            DecayLib.applyDecay(value, 1, halfLife),
            1606938044258990275481580456955431199224023730839929796075919,
            tolerance
        );
    }

    // decay(a) * decay(b) == decay(a + b): the property the aggregation relies on (Oracle.v, lemma decay_add).
    function testFuzz_DecayIsMultiplicative(uint256 value, uint256 a, uint256 b, uint256 halfLife) public pure {
        value = bound(value, 0, 1e30);
        halfLife = bound(halfLife, 1, 30 days);
        a = bound(a, 0, 100 * halfLife);
        b = bound(b, 0, 100 * halfLife);

        uint256 stepwise = DecayLib.applyDecay(DecayLib.applyDecay(value, a, halfLife), b, halfLife);
        uint256 oneShot = DecayLib.applyDecay(value, a + b, halfLife);

        assertApproxEqAbs(stepwise, oneShot, value / 1e18 + 2);
    }

    // Decaying [t0, t1] and then [t1, t2] uses the same exponent as [t0, t2], so only the final roundings differ.
    function testFuzz_DecayBetweenTelescopes(uint256 value, uint256 t0, uint256 d1, uint256 d2, uint256 halfLife)
        public
        pure
    {
        value = bound(value, 0, 1e36);
        halfLife = bound(halfLife, 1, 30 days);
        t0 = bound(t0, 0, 1e12);
        d1 = bound(d1, 0, 100 * halfLife);
        d2 = bound(d2, 0, 100 * halfLife);
        uint256 t1 = t0 + d1;
        uint256 t2 = t1 + d2;

        uint256 stepwise =
            DecayLib.applyDecayBetween(DecayLib.applyDecayBetween(value, t0, t1, halfLife), t1, t2, halfLife);
        uint256 oneShot = DecayLib.applyDecayBetween(value, t0, t2, halfLife);

        assertApproxEqAbs(stepwise, oneShot, 3);
    }

    // Any inputs, unbounded: decay never reverts and never makes a value bigger.
    function testFuzz_DecayBetweenNeverRevertsOrGrows(uint256 value, uint256 from, uint256 to, uint256 halfLife)
        public
        pure
    {
        assertLe(DecayLib.applyDecayBetween(value, from, to, halfLife), value);
    }

    function testFuzz_DecayFactorIsMonotonicAndBounded(uint256 a, uint256 b, uint256 halfLife) public pure {
        halfLife = bound(halfLife, 1, 30 days);
        a = bound(a, 0, 1000 * halfLife);
        b = bound(b, a, 1000 * halfLife);

        uint256 fa = DecayLib.decayFactor(a, halfLife);
        uint256 fb = DecayLib.decayFactor(b, halfLife);
        assertLe(fa, WAD);
        assertLe(fb, fa);
        assertEq(DecayLib.activityFactor(a, halfLife), WAD - fa);
    }
}

contract OracleDecayTest is Test {
    uint256 internal constant HALF_LIFE = 60;
    uint256 internal constant LOCK = 60;

    MockDecayToken internal token;
    Oracle internal oracle;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new MockDecayToken();
        // owner, name, description, token, halfLife, q, depositLock, withdrawalLock, rewardBps, gamma, sampleSize
        oracle =
            new Oracle(address(this), "Test", "Test feed", address(token), HALF_LIFE, 50_000, LOCK, LOCK, 100, 0, 5);
    }

    function _stake(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(oracle), amount);
        oracle.depositTokens(amount);
        vm.stopPrank();
    }

    function _submit(address user, uint256 value) internal {
        vm.prank(user);
        oracle.submitValue(value);
    }

    // Scenario from issue #25: Alice says 10000, Bob says 100 in between, then Alice corrects herself to 100.
    function _feedAfterCorrection(uint256 bobSubmissions) internal returns (uint256) {
        _stake(alice, 100e18);
        _stake(bob, 1e18);

        uint256 start = vm.getBlockTimestamp() + LOCK + 1;
        vm.warp(start);
        _submit(alice, 10_000e18);

        uint256 step = HALF_LIFE / (bobSubmissions + 1);
        for (uint256 i = 1; i <= bobSubmissions; i++) {
            vm.warp(start + i * step);
            _submit(bob, 100e18);
        }

        vm.warp(start + HALF_LIFE);
        _submit(alice, 100e18);
        return oracle.readValue();
    }

    function test_ResubmissionReplacesOldValueWithOneSubmissionInBetween() public {
        assertApproxEqRel(_feedAfterCorrection(1), 100e18, 1e6);
    }

    function test_ResubmissionReplacesOldValueWithManySubmissionsInBetween() public {
        assertApproxEqRel(_feedAfterCorrection(59), 100e18, 1e6);
    }

    function testFuzz_ResubmissionReplacesOldValue(uint256 aliceStake, uint256 bobStake, uint8 count, uint256 gap)
        public
    {
        aliceStake = bound(aliceStake, 1e18, 1e27);
        bobStake = bound(bobStake, 1e18, 1e27);
        count = uint8(bound(count, 1, 30));
        gap = bound(gap, 1, 2 * HALF_LIFE);

        _stake(alice, aliceStake);
        _stake(bob, bobStake);
        uint256 t = vm.getBlockTimestamp() + LOCK + 1;
        vm.warp(t);
        _submit(alice, 10_000e18);
        for (uint256 i = 0; i < count; i++) {
            t += gap;
            vm.warp(t);
            _submit(bob, 100e18);
        }
        vm.warp(t + gap);
        _submit(alice, 100e18);

        assertApproxEqRel(oracle.readValue(), 100e18, 1e6);
    }

    // Found by fuzzing: rounding left decayedQ below the big submitter's own decayed weight and submitValue panicked.
    function test_ResubmissionDoesNotUnderflowAfterDustSubmission() public {
        Oracle o = new Oracle(address(this), "Test", "Test feed", address(token), 2650, 50_000, 1, 1, 100, 0, 5);
        address big = makeAddr("big");
        address dust = makeAddr("dust");
        token.mint(big, 96915334977010372059856900697739702795);
        token.mint(dust, 1);
        vm.startPrank(big);
        token.approve(address(o), type(uint256).max);
        o.depositTokens(96915334977010372059856900697739702795);
        vm.stopPrank();
        vm.startPrank(dust);
        token.approve(address(o), type(uint256).max);
        o.depositTokens(1);
        vm.stopPrank();

        uint256 start = vm.getBlockTimestamp() + 2;
        vm.warp(start);
        vm.prank(big);
        o.submitValue(1e18);
        vm.warp(start + 600);
        vm.prank(dust);
        o.submitValue(2e18);
        vm.warp(start + 603);
        vm.prank(big);
        o.submitValue(3e18);

        assertApproxEqAbs(o.readValue(), 3e18, 1);
    }

    // Found by a break-it review: with the fraction rounded per call, the steps that decay the total weight added up
    // to slightly less decay than the one step used for the whale's own weight, so ~1e8 wei of the whale's old
    // weight stayed in the total at its old price after the whale replaced its value. The whale keeps 1e9 wei so
    // the stored 1-wei-rounded price stays precise enough to check the feed right after its correction.
    function test_NoPhantomWeightAfterWhaleResubmits() public {
        Oracle o = new Oracle(address(this), "Test", "Test feed", address(token), 1000, 50_000, 1, 1, 100, 0, 5);
        address whale = makeAddr("whale");
        address dust = makeAddr("dust");
        address honest = makeAddr("honest");
        uint256[3] memory amounts = [uint256(1e27), 1, 1e18];
        address[3] memory users = [whale, dust, honest];
        for (uint256 i = 0; i < 3; i++) {
            token.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            token.approve(address(o), type(uint256).max);
            o.depositTokens(amounts[i]);
            vm.stopPrank();
        }

        uint256 t = vm.getBlockTimestamp() + 2;
        vm.warp(t);
        vm.prank(whale);
        o.submitValue(678e18);
        for (uint256 i = 0; i < 100; i++) {
            t += 7;
            vm.warp(t);
            vm.prank(dust);
            o.submitValue(100e18);
        }
        vm.prank(whale);
        o.withdrawTokens(1e27 - 1e9);
        t += 7;
        vm.warp(t);
        vm.prank(whale);
        o.submitValue(100e18);

        // Everyone's latest price is 100. A leftover of the whale's old weight at 678 would pull the feed up.
        assertApproxEqRel(o.readValue(), 100e18, 1e11);
        vm.prank(honest);
        o.submitValue(100e18);
        assertApproxEqRel(o.readValue(), 100e18, 1e8);
    }

    // Rounding must never make a submission revert.
    function testFuzz_SubmissionsNeverRevert(uint256[3] memory stakes, uint256[8] memory gaps, uint8[8] memory who)
        public
    {
        address[3] memory users = [alice, bob, makeAddr("carol")];
        for (uint256 i = 0; i < 3; i++) {
            stakes[i] = bound(stakes[i], 1, 1e27);
            _stake(users[i], stakes[i]);
        }
        uint256 t = vm.getBlockTimestamp() + LOCK + 1;
        for (uint256 i = 0; i < 8; i++) {
            t += bound(gaps[i], 0, 10 * HALF_LIFE);
            vm.warp(t);
            _submit(users[who[i] % 3], 1e18 + i);
        }
    }

    // Fuzzing found these inputs. On main submitValue panics here with 0x11 (the underflow from issue #25).
    function test_SubmissionsDoNotRevertOnMainUnderflowCase() public {
        testFuzz_SubmissionsNeverRevert(
            [uint256(41), 999999999999999999000000000, 17736],
            [uint256(4743), 600, 488281250000000, 7629394531250, 12112, 4108, 2573, 1000000000],
            [uint8(31), 33, 61, 100, 46, 40, 17, 180]
        );
    }
}
