// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DecayLib
 * @dev Library for handling time-decay calculations in the Oracle
 */
library DecayLib {
    
    uint256 private constant WAD = 1e18;
    uint256 private constant DENOMINATOR = 1e5;
    
    function getPow2NegInt(uint256 k) private pure returns (uint256) {if (k == 0) return 1_000000000000000000;if (k == 1) return 500000000000000000;if (k == 2) return 250000000000000000;if (k == 3) return 125000000000000000;if (k == 4) return 62500000000000000;if (k == 5) return 31250000000000000;if (k == 6) return 15625000000000000;if (k == 7) return 7812500000000000;if (k == 8) return 3906250000000000;if (k == 9) return 1953125000000000;if (k == 10) return 976562500000000;if (k == 11) return 488281250000000;if (k == 12) return 244140625000000;if (k == 13) return 122070312500000;if (k == 14) return 61035156250000;if (k == 15) return 30517578125000;if (k == 16) return 15258789062500;if (k == 17) return 7629394531250;if (k == 18) return 3814697265625;if (k == 19) return 1907348632812;if (k == 20) return 953674316406;if (k == 21) return 476837158203;if (k == 22) return 238418579102;if (k == 23) return 119209289551;if (k == 24) return 59604644775;if (k == 25) return 29802322388;if (k == 26) return 14901161194;if (k == 27) return 7450580597;if (k == 28) return 3725290298;if (k == 29) return 1862645149;if (k == 30) return 931322574;if (k == 31) return 465661287;if (k == 32) return 232830643;if (k == 33) return 116415322;if (k == 34) return 58207661;if (k == 35) return 29103831; if (k == 36) return 14551915;if (k == 37) return 7275958;if (k == 38) return 3637979;if (k == 39) return 1818989;if (k == 40) return 909495;if (k == 41) return 454747;if (k == 42) return 227373;if (k == 43) return 113687;if (k == 44) return 56843;if (k == 45) return 28422;if (k == 46) return 14211;if (k == 47) return 7105;if (k == 48) return 3553;if (k == 49) return 1776;if (k == 50) return 888;if (k == 51) return 444;if (k == 52) return 222;if (k == 53) return 111;if (k == 54) return 56;if (k == 55) return 28;if (k == 56) return 14;if (k == 57) return 7;if (k == 58) return 3;if (k == 59) return 2;if (k == 60) return 1; 
        return 0; // k > 60
    }
    
    /**
     * @dev Apply decay to a value based on elapsed time
     * @param value The value to decay
     * @param elapsed Time elapsed since last update
     * @param halfLifeSeconds Half-life for decay calculation
     * @return decayedValue The value after applying decay
     */
    function applyDecay( uint256 value, uint256 elapsed, uint256 halfLifeSeconds) external pure returns (uint256 decayedValue) {
        if (value == 0) return 0;
        uint256 f = decayFactor(elapsed, halfLifeSeconds);
        return (value * f) / WAD;
    }
    
    // Calculate decay factor for given elapsed time
    function decayFactor( uint256 elapsed, uint256 halfLifeSeconds ) public pure returns (uint256 factor) {
        if (elapsed == 0) return WAD;
        if (halfLifeSeconds == 0) return WAD; // no decay if HL=0

        uint256 scaledX = (elapsed * DENOMINATOR) / halfLifeSeconds;
        if (scaledX >= 61 * DENOMINATOR) return 1; // If x >= 61 -> ~0 (2^-61 ~ 4.3e-19) ; ~0 in 1e18 scale

        uint256 k = scaledX / DENOMINATOR; // integer part
        uint256 frac = scaledX % DENOMINATOR; // 0..99999 (fractional 5dp)

        if (frac == 0) return getPow2NegInt(k);

        uint256 hi = getPow2NegInt(k);
        uint256 lo = (k < 60) ? getPow2NegInt(k + 1) : 0;
        unchecked {
            return hi - ((hi - lo) * frac) / DENOMINATOR;
        }
    }
    
    //  activity factor: 1 - δ^elapsed
    function activityFactor( uint256 elapsed, uint256 halfLifeSeconds ) public pure returns (uint256) {
        uint256 decay = decayFactor(elapsed, halfLifeSeconds);
        return decay >= WAD ? 0 : (WAD - decay);
    }
    
    /**
     * @dev Calculate reward based on activity and weight
     * @param rewardPool Total reward pool available
     * @param totalWeight Total decayed weight
     * @param alpha Alpha parameter for reward calculation
     */
    function calculateReward( uint256 rewardPool, uint256 weight, uint256 elapsed, uint256 totalWeight, uint256 alpha, uint256 halfLifeSeconds ) external pure returns (uint256 reward) {
        if (rewardPool == 0 || weight == 0 || totalWeight == 0) return 0;
        
        uint256 activityFac = activityFactor(elapsed, halfLifeSeconds);
        if (activityFac == 0) return 0;
        uint256 num = (weight * activityFac) / WAD; // w * (1 - δ^Δy)
        return (alpha * rewardPool * num) / totalWeight;
    }
}
