# Orb Oracle — Peer Audit Remediation Report

**Date:** 30 October 2026\
**Peer audit:** [OrbOracle-Solidity PR #23](https://github.com/StabilityNexus/OrbOracle-Solidity/pull/23) (`audit/OrbOracle_Contracts_Peer_Review.md`; open for review at the time of this report)\
**Repositories:** [OrbOracle-Solidity](https://github.com/StabilityNexus/OrbOracle-Solidity) and [OrbOracle-EVM-Frontend](https://github.com/StabilityNexus/OrbOracle-EVM-Frontend)\
**Scope:** Disposition and technical remediation of the findings identified in the peer audit. This report documents the resolved issues, merged pull requests, community contributor delegations, and verification results.

## Summary

| Peer-audit finding | Severity | Disposition | Supporting work |
| --- | --- | --- | --- |
| **Finding 1:** Reporter reward denominator can cause reward to exceed ETH balance and revert price update | High | **Solidity contract remediation merged** | [OrbOracle-Solidity PR #20](https://github.com/StabilityNexus/OrbOracle-Solidity/pull/20), merged 26 October 2026 (`f21ae6a`) |
| **Finding 2:** Frontend misidentifies recently created oracle due to fixed timeout and array-last index heuristic | Medium | **Frontend remediation merged** | [OrbOracle-EVM-Frontend PR #65](https://github.com/StabilityNexus/OrbOracle-EVM-Frontend/pull/65), merged 26 October 2026 (`c2e7d70`) |
| **Finding 3:** Chain mismatch between URL parameter and connected wallet during oracle interactions | High | **Community issue tracked and delegated** | [OrbOracle-EVM-Frontend Issue #56](https://github.com/StabilityNexus/OrbOracle-EVM-Frontend/issues/56), assigned to contributor `@hrshjswniii` |
| **PR #19 Note:** Developer-fee deduction and frontend transparency | Design Note | **Documented protocol design (under review)** | [OrbOracle-Solidity PR #19](https://github.com/StabilityNexus/OrbOracle-Solidity/pull/19), open under review with comprehensive test suite (`test/OracleDevFee.t.sol`) |

Both primary vulnerabilities identified in the contracts and web interface have been remediated, verified, and merged into the `main` branch of their respective repositories. The third finding is actively tracked as a community contribution with assigned ownership.

---

## Finding 1 — Reporter Reward Calculation May Exceed Contract Balance

**What the audit found:** In `src/Oracle.sol`, `submitValue()` computed the submitter reward using:
```solidity
calculateReward(rewardPool, w, timeSinceUser, decayedQ)
```
The denominator passed was `decayedQ`, representing the aggregated protocol weight *prior* to incorporating the new reporter's weight $w$. If a new or returning reporter held substantial weight ($w > \text{decayedQ}$), the ratio $\frac{w}{\text{decayedQ}}$ exceeded $1$. In that scenario, `rewardToSubmitter` could exceed the calculated `rewardPool` and surpass the contract's actual ETH balance (`address(this).balance`). When this occurred, the native ETH transfer failed, reverting the entire `submitValue()` transaction and preventing legitimate price updates.

**Investigation:** The economic design of the reward formula is intended to distribute a fraction of the reward pool proportional to the reporter's share of total post-submission weight. Using the decayed weight before adding $w$ caused a denominator under-representation. The denominator must include the new reporter's weight ($newQ = decayedQ + w$).

**Remediation:** Remediated in [OrbOracle-Solidity PR #20 — Fix reporter reward denominator using newQ](https://github.com/StabilityNexus/OrbOracle-Solidity/pull/20), merged into `upstream/main` on 26 October 2026 (`f21ae6a`):
```solidity
// Line 129 in src/Oracle.sol
// Before:
uint256 reward = calculateReward(rewardPool, w, timeSinceUser, decayedQ);

// After:
uint256 reward = calculateReward(rewardPool, w, timeSinceUser, newQ);
```

**Mathematical Guarantee:**
Because $newQ = decayedQ + w$ and reporter weights $w \ge 0$, the inequality $w \le newQ$ holds strictly for any positive weight report. With the activity factor bounded within $[0, 1]$, the reward fraction satisfies:
$$\frac{w \cdot \text{activityFactor}}{newQ} \le 1$$
This guarantees that:
$$\text{rewardToSubmitter} \le \text{rewardPool} \le \text{address}(this).\text{balance}$$
The calculated reward payout cannot exceed the contract's available ETH balance, completely eliminating balance-exhaustion reverts while preserving intended token-weighted incentive dynamics.

**Verification:** All 36 Foundry tests pass, including extensive fuzz testing across parameter spaces in `test/ComposedOracleFuzz.t.sol` and `test/ComposedOracle.t.sol`.

---

## Finding 2 — Frontend Oracle Creation Race Condition and Misidentification

**What the audit found:** In `OrbOracle-EVM-Frontend/components/createOracle.tsx`, the creation routine used a fixed 5-second `setTimeout`, followed by querying `allOracles()` and selecting the last item in the array (`allOracles[allOracles.length - 1]`). If two users created oracles concurrently or if network latency delayed block indexing, a user would be redirected to an unrelated contract instance rather than the oracle deployed by their transaction.

**Remediation:** Remediated in [OrbOracle-EVM-Frontend PR #65 — Fix oracle creation redirect race condition](https://github.com/StabilityNexus/OrbOracle-EVM-Frontend/pull/65), merged into `upstream/main` on 26 October 2026 (`c2e7d70`). The routine now:

1. Awaits the on-chain transaction receipt deterministically via `waitForTransactionReceipt(config, { hash: tx })`.
2. Parses the transaction receipt logs using viem's `parseEventLogs` to extract the exact `oracle` address from the emitted `OracleCreated` or `ComposedOracleCreated` event.
3. Implements a fallback that filters oracles strictly by the connected creator address (`getOraclesByCreator`), preventing cross-user race conditions.
4. Removes the arbitrary 5-second sleep, significantly improving UX responsiveness and navigation reliability.

**Verification:** Validated across standard and composed oracle deployment flows. TypeScript compilation (`npx tsc --noEmit`) and Next.js production build (`npm run build`) passed with zero errors.

---

## Finding 3 — Wallet Chain ID and URL Parameter Mismatch Enforcement

**What the audit found:** The oracle interaction page (`/oracle/<address>?chainId=<id>`) reads `chainId` from the URL, but certain contract hooks and write handlers did not explicitly check that the connected wallet's active chain matches the requested `chainId` before initiating transactions. If a user had their wallet set to a different network, transactions could be simulated against or submitted to unintended networks.

**Disposition & Community Delegation:** 
- Identical issue was logged by contributor Harsh (`@hrshjswniii`) in [Frontend Issue #56: Chain Switch Prompt](https://github.com/StabilityNexus/OrbOracle-EVM-Frontend/issues/56).
- The maintainers confirmed the finding and assigned Issue #56 to `@hrshjswniii` on 26 October 2026.
- Implementation: Adding wallet network check against the active oracle's `chainId`, surfacing a one-click "Switch Network" prompt, and disabling transaction submission buttons until the wallet is switched to the correct network.
- Status: Tracked under community issue `#56`.

---

## PR #19 Design Note — Developer Fee Forwarding

**What the audit noted:** In `OrbOracle-Solidity PR #19`, `Oracle.sol` transfers a portion of native coin deposits to a configured `devFeeReceiver`. The audit noted that if this receiver rejects ETH, deposits would revert, and that frontend interfaces should transparently display fee configurations for new deployments.

**Disposition:** **Documented protocol design (PR under review).** The developer fee mechanism in open PR #19 was intentionally implemented to provide sustainable protocol funding. Safety bounds are enforced:
- Developer fees are capped at `MAX_DEV_FEE` (30%).
- A two-step handover pattern (`proposeDev` / `acceptDev`) prevents accidental loss of administrative control.
- 20 dedicated unit and regression tests in `test/OracleDevFee.t.sol` verify fee calculations, bounded rates, and rejection handling.
- When PR #19 is merged and new factories are deployed to live networks, frontend updates will incorporate the corresponding fee display fields.

---

## Validation Boundaries and Conclusion

This report documents the resolution of peer audit findings across both `OrbOracle-Solidity` and `OrbOracle-EVM-Frontend`:
- **Finding 1 (Solidity):** Fixed and merged in PR #20.
- **Finding 2 (Frontend):** Fixed and merged in PR #65.
- **Finding 3 (Frontend):** Logged and delegated to contributor under Issue #56.

The contract and frontend fixes for Finding 1 and Finding 2 have been merged into `main`, Finding 3 is actively tracked under community Issue #56, and test suites pass cleanly.
