// SPDX-License-Identifier: UNLICENSED
// Licensing information: https://github.com/StabilityNexus/OrbOracle-Solidity
pragma solidity ^0.8.20;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title DecayLib
 * @dev Library for handling time-decay calculations in the Oracle.
 * Decay is exactly 2^(-elapsed / halfLifeSeconds) (Def. 1 in OrbOracle-Formalization), up to rounding,
 * so decay(a) * decay(b) == decay(a + b). Oracle relies on this when it decays the aggregate weight step
 * by step but a submitter's own weight in one go. Internally the factor is 128.128 fixed point rather than WAD,
 * because its 64 table constants need about 2^-64 precision; inputs and outputs keep the caller's units.
 */
library DecayLib {
    uint256 private constant WAD = 1e18;
    uint256 private constant ONE = 1 << 128; // 1.0 in 128.128 fixed point

    /**
     * @dev Apply decay to a value based on elapsed time
     * @param value The value to decay
     * @param elapsed Time elapsed since last update
     * @param halfLifeSeconds Half-life for decay calculation
     * @return decayedValue The value after applying decay. The exponent is rounded down to 2^-64 of a
     * half-life and the product is rounded down, so it can differ from the exact value by up to 4e-20 of
     * the value plus 1 wei, in either direction.
     */
    function applyDecay(uint256 value, uint256 elapsed, uint256 halfLifeSeconds)
        external
        pure
        returns (uint256 decayedValue)
    {
        if (value == 0) return 0;
        return _decayBetween(value, 0, elapsed, halfLifeSeconds);
    }

    /**
     * @dev Apply decay to a value for the time between two timestamps. The exponent is counted from time 0, so
     * decaying over [t0, t1] and then [t1, t2] uses exactly the same total exponent as [t0, t2] in one go.
     * @param value The value to decay
     * @param fromTimestamp Start of the interval
     * @param toTimestamp End of the interval (no decay if it is not after fromTimestamp)
     * @param halfLifeSeconds Half-life for decay calculation (no decay if 0)
     * @return decayedValue The value after applying decay. The absolute timestamp exponents are rounded down
     * to 2^-64 of a half-life before subtraction and the product is rounded down, so it can differ from the
     * exact value by up to 4e-20 of the value plus 1 wei, in either direction.
     */
    function applyDecayBetween(uint256 value, uint256 fromTimestamp, uint256 toTimestamp, uint256 halfLifeSeconds)
        external
        pure
        returns (uint256 decayedValue)
    {
        if (value == 0) return 0;
        return _decayBetween(value, fromTimestamp, toTimestamp, halfLifeSeconds);
    }

    // Calculate decay factor (WAD) for given elapsed time
    function decayFactor(uint256 elapsed, uint256 halfLifeSeconds) public pure returns (uint256 factor) {
        return _decayBetween(WAD, 0, elapsed, halfLifeSeconds);
    }

    //  activity factor: 1 - δ^elapsed
    function activityFactor(uint256 elapsed, uint256 halfLifeSeconds) public pure returns (uint256) {
        uint256 decay = decayFactor(elapsed, halfLifeSeconds);
        return decay >= WAD ? 0 : (WAD - decay);
    }

    // value * 2^(-exponent), where exponent = floor(to * 2^64 / h) - floor(from * 2^64 / h) in units of 2^-64
    // half-lives. It is split into whole half-lives k (a shift) and a 64-bit fraction.
    function _decayBetween(uint256 value, uint256 from, uint256 to, uint256 halfLifeSeconds)
        private
        pure
        returns (uint256)
    {
        if (to <= from || halfLifeSeconds == 0) return value; // no decay if HL=0
        uint256 halfLives = to / halfLifeSeconds - from / halfLifeSeconds;
        if (halfLives > 256) return 0;
        uint256 exponent = (halfLives << 64) + Math.mulDiv(to % halfLifeSeconds, 1 << 64, halfLifeSeconds)
            - Math.mulDiv(from % halfLifeSeconds, 1 << 64, halfLifeSeconds);
        // k <= 256 here; a shift by 256 gives 0.
        return Math.mulDiv(value, _pow2NegFraction(exponent & type(uint64).max), ONE) >> (exponent >> 64);
    }

    // 2^(-frac / 2^64) in 128.128 fixed point (frac < 2^64). For each set bit of frac worth 2^-j it multiplies by
    // 2^(-1/2^j); each constant is floor(2^128 * 2^(-1/2^j)).
    function _pow2NegFraction(uint256 frac) private pure returns (uint256 r) {
        r = ONE;
        // r <= 2^128 and every constant is below 2^128, so r * constant cannot overflow.
        unchecked {
            if (frac & (1 << 63) != 0) r = (r * 240615969168004511545033772477625056927) >> 128;
            if (frac & (1 << 62) != 0) r = (r * 286142222517866327586855861304318312414) >> 128;
            if (frac & (1 << 61) != 0) r = (r * 312040306297756043528438546211487503610) >> 128;
            if (frac & (1 << 60) != 0) r = (r * 325855510927366467338765757798166302659) >> 128;
            if (frac & (1 << 59) != 0) r = (r * 332990817489906152516528174760363655116) >> 128;
            if (frac & (1 << 58) != 0) r = (r * 336616849754143321171240736068313607683) >> 128;
            if (frac & (1 << 57) != 0) r = (r * 338444645961211524111694060679677685513) >> 128;
            if (frac & (1 << 56) != 0) r = (r * 339362262485680770294711564297527942524) >> 128;
            if (frac & (1 << 55) != 0) r = (r * 339822003293300968391941903755125245321) >> 128;
            if (frac & (1 << 54) != 0) r = (r * 340052107201910159018235275086188756486) >> 128;
            if (frac & (1 << 53) != 0) r = (r * 340167217578529594754386235778394637196) >> 128;
            if (frac & (1 << 52) != 0) r = (r * 340224787378186065024124058177160890957) >> 128;
            if (frac & (1 << 51) != 0) r = (r * 340253575931572222344808541527975417861) >> 128;
            if (frac & (1 << 50) != 0) r = (r * 340267971121744950115931523046122852714) >> 128;
            if (frac & (1 << 49) != 0) r = (r * 340275168945212498243824544813253388216) >> 128;
            if (frac & (1 << 48) != 0) r = (r * 340278767914042977419818114301068315674) >> 128;
            if (frac & (1 << 47) != 0) r = (r * 340280567412732569420752589735540255585) >> 128;
            if (frac & (1 << 46) != 0) r = (r * 340281467165645975541538300962849720626) >> 128;
            if (frac & (1 << 45) != 0) r = (r * 340281917042994833884159925800699069144) >> 128;
            if (frac & (1 << 44) != 0) r = (r * 340282141981892302220047427165751816689) >> 128;
            if (frac & (1 << 43) != 0) r = (r * 340282254451396796222137840463944662897) >> 128;
            if (frac & (1 << 42) != 0) r = (r * 340282310686162983187095027395548206958) >> 128;
            if (frac & (1 << 41) != 0) r = (r * 340282338803549561661223530468750597251) >> 128;
            if (frac & (1 << 40) != 0) r = (r * 340282352862243722146284248737311181623) >> 128;
            if (frac & (1 << 39) != 0) r = (r * 340282359891591020200824223221658257108) >> 128;
            if (frac & (1 << 38) != 0) r = (r * 340282363406264723681097926634783937781) >> 128;
            if (frac & (1 << 37) != 0) r = (r * 340282365163601589034485871425767421621) >> 128;
            if (frac & (1 << 36) != 0) r = (r * 340282366042270025114492637597574848943) >> 128;
            if (frac & (1 << 35) != 0) r = (r * 340282366481604244005324221690708811930) >> 128;
            if (frac & (1 << 34) != 0) r = (r * 340282366701271353663447064309477272527) >> 128;
            if (frac & (1 << 33) != 0) r = (r * 340282366811104908545685248301961112247) >> 128;
            if (frac & (1 << 32) != 0) r = (r * 340282366866021686000098530973984089421) >> 128;
            if (frac & (1 << 31) != 0) r = (r * 340282366893480074730628719979566611706) >> 128;
            if (frac & (1 << 30) != 0) r = (r * 340282366907209269096724701399828852445) >> 128;
            if (frac & (1 << 29) != 0) r = (r * 340282366914073866279980413839337495360) >> 128;
            if (frac & (1 << 28) != 0) r = (r * 340282366917506164871660200491437419659) >> 128;
            if (frac & (1 << 27) != 0) r = (r * 340282366919222314167513076425573935295) >> 128;
            if (frac & (1 << 26) != 0) r = (r * 340282366920080388815442760044663850582) >> 128;
            if (frac & (1 << 25) != 0) r = (r * 340282366920509426139408413267214224979) >> 128;
            if (frac & (1 << 24) != 0) r = (r * 340282366920723944801391442731740766665) >> 128;
            if (frac & (1 << 23) != 0) r = (r * 340282366920831204132383008177316876167) >> 128;
            if (frac & (1 << 22) != 0) r = (r * 340282366920884833797878803578433140587) >> 128;
            if (frac & (1 << 21) != 0) r = (r * 340282366920911648630626704448573325215) >> 128;
            if (frac & (1 << 20) != 0) r = (r * 340282366920925056047000655676038930634) >> 128;
            if (frac & (1 << 19) != 0) r = (r * 340282366920931759755187631487870611619) >> 128;
            if (frac & (1 << 18) != 0) r = (r * 340282366920935111609281119443311171681) >> 128;
            if (frac & (1 << 17) != 0) r = (r * 340282366920936787536327863433412631604) >> 128;
            if (frac & (1 << 16) != 0) r = (r * 340282366920937625499851235431558656539) >> 128;
            if (frac & (1 << 15) != 0) r = (r * 340282366920938044481612921431405492749) >> 128;
            if (frac & (1 << 14) != 0) r = (r * 340282366920938253972493764431522366791) >> 128;
            if (frac & (1 << 13) != 0) r = (r * 340282366920938358717934185931629167795) >> 128;
            if (frac & (1 << 12) != 0) r = (r * 340282366920938411090654396681694659293) >> 128;
            if (frac & (1 << 11) != 0) r = (r * 340282366920938437277014502056730427791) >> 128;
            if (frac & (1 << 10) != 0) r = (r * 340282366920938450370194554744249067728) >> 128;
            if (frac & (1 << 9) != 0) r = (r * 340282366920938456916784581088008576618) >> 128;
            if (frac & (1 << 8) != 0) r = (r * 340282366920938460190079594259888378293) >> 128;
            if (frac & (1 << 7) != 0) r = (r * 340282366920938461826727100845828290938) >> 128;
            if (frac & (1 << 6) != 0) r = (r * 340282366920938462645050854138798250213) >> 128;
            if (frac & (1 << 5) != 0) r = (r * 340282366920938463054212730785283230588) >> 128;
            if (frac & (1 << 4) != 0) r = (r * 340282366920938463258793669108525720960) >> 128;
            if (frac & (1 << 3) != 0) r = (r * 340282366920938463361084138270146966193) >> 128;
            if (frac & (1 << 2) != 0) r = (r * 340282366920938463412229372850957588820) >> 128;
            if (frac & (1 << 1) != 0) r = (r * 340282366920938463437801990141362900137) >> 128;
            if (frac & (1 << 0) != 0) r = (r * 340282366920938463450588298786565555796) >> 128;
        }
    }
}
