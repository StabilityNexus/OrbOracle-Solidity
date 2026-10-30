# Orb Oracle — Smart Contract and Frontend Peer Review

**Repositories:**
- Contracts: https://github.com/StabilityNexus/OrbOracle-Solidity
- Frontend: https://github.com/StabilityNexus/OrbOracle-EVM-Frontend
- Contracts change: https://github.com/StabilityNexus/OrbOracle-Solidity/pull/19

**Source revisions inspected:** Solidity `main` at `5ae087fb5eecfaeb73ea6bd03665ae9ed2614405`, PR #19 at `ceda9dacd17f40c1ff45dee3afc7274445fba5de`, frontend `main` at `5648181faed82b101dc7f54f46ab7eb84dd4ee0a`.

## Overall assessment

The review concentrated on security-sensitive flows and practical problems affecting reporting, funds, deployment, and transaction execution. No confirmed direct theft-of-staked-tokens exploit was identified in the inspected source. The following material issues merit reproduction and fixes before treating the affected workflows as reliable.

## Finding 1 — A new reporter's computed reward may exceed the available ETH balance

**Potential severity:** High (price-reporting availability; reproduction required)

**Location:** `src/Oracle.sol`, `submitValue()` and `calculateReward()`.

The reward is computed from `rewardPool * weight * activityFactor / totalWeight`, where the `totalWeight` passed by `submitValue()` is the **decayed weight before adding the new reporter**. If an eligible first-time reporter has much more weight than the existing participants, the ratio can be greater than one. Since `rewardPool` is a fraction of the contract balance, the calculated reward can exceed the balance when the weight ratio is sufficiently high. The subsequent ETH transfer fails, reverting the entire price submission.

**Concrete test:** Begin with an existing small-weight reporter, fund the oracle, have a newly unlocked reporter hold substantially more voting weight than the existing aggregate, advance time sufficiently for a nonzero activity factor, then call `submitValue()`. Check whether reward exceeds balance and the price update reverts. Also test the no-prior-report state (`aggregatedWeight = 0`) separately; that path pays no reward by construction and does not demonstrate this issue.

**Recommendation:** Ensure the reward payout can never exceed a justified budget and cannot make a valid price update fail solely because the requested reward is unpayable. Confirm the intended economics before changing denominators.

## Finding 2 — Frontend reports an unrelated oracle as the one just created

**Severity:** Medium (misidentification of deployed contracts)

**Location:** `OrbOracle-EVM-Frontend/components/createOracle.tsx`, `createOracle()`; standard-oracle branch approximately lines 417–449.

After submitting a create transaction, the frontend waits a fixed five seconds, reads `allOracles()`, and uses the **last oracle in the entire factory**. It does not identify the instance emitted by the user's transaction. If another user deploys more recently, the UI can display and link to that other user's oracle as if it were the newly created one. The composed-oracle branch similarly picks the last factory entry belonging to the creator rather than identifying the submitted transaction's result.

**Reproduction:** Submit two creation transactions from different wallets in close succession so that the second oracle becomes the final registry entry before the first user's UI refresh. Compare the displayed address with the `OracleCreated` event in the first user's transaction receipt.

**Recommendation:** Wait for the actual transaction receipt and extract the contract address from the corresponding factory creation event; do not infer ownership or identity from the final array item or a fixed timeout.

## Finding 3 — Requested chain and wallet chain are not consistently enforced for oracle interactions

**Potential severity:** High (wrong-network transactions; confirm against supported wallet/network setup)

**Location:** `OrbOracle-EVM-Frontend/hooks/useOracles.ts`, `useOracle()`, and `app/[oracleId]/InteractionClient.tsx`, transaction handlers.

The details page accepts an explicit `chainId` query parameter, while some calls in `useOracle()` omit `chainId` and therefore use the connected/default chain. Core transaction handlers (`submitValue`, staking approval/deposit/withdrawal, votes) call `writeContract()` with an oracle address but do not explicitly require the wallet's chain to equal the chain requested by the URL. If the same address has code on another network, the user could sign a transaction on the wrong network; otherwise the action can fail or the UI can show inconsistent data.

**Reproduction:** Open a valid `?chainId=<network-A>&oracle=<address-A>` page with the wallet set to network B. Compare detail reads and chain ID of any simulated/submitted transaction. Do not send real funds; use disposable testnet accounts.

**Recommendation:** Enforce a chain match before enabling write actions, prompt a network switch, and make every contract read explicitly use the intended chain or a consistent configured client.

## PR #19 — Developer-fee forwarding (design and integration note)

`Oracle.sol` now transfers a portion of each native-coin deposit to the configured `devFeeReceiver`; if that receiver rejects ETH, `deposit()`/`receive()` revert. The PR tests this behavior. This is a practical funding-availability trade-off controlled by the dev role; treat it as a separate defect only if the project's intended availability guarantee forbids it.

The frontend on the inspected main revision uses an older factory ABI and does not surface the new immutable developer fee or fee receiver. This is a **release integration consideration** for new PR #19 deployments, not evidence that the existing deployed factories suddenly malfunction. Frontend messaging should disclose relevant deductions when the new factory is deployed.

## Review disposition

Before opening issues, reproduce Findings 1–3 in isolated local/testnet tests, record exact affected commits, and check whether fixes already exist on newer branches. Report only consequences that actually reproduce. No style-only or speculative findings are included.
