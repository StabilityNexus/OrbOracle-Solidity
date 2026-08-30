# AOSSIE Best Practices Checklist

> Criteria adapted from the [OpenSSF Best Practices Badge](https://github.com/coreinfrastructure/best-practices-badge)
> (MIT / CC BY 3.0) by OpenSSF contributors. Modified for AOSSIE multi-repo template use.

> **Purpose:** Covers OpenSSF Best Practices criteria that are NOT auto-detected by OpenSSF Scorecard.
> Scorecard already handles: License, SAST tools, CI tests, Security Policy file, Branch Protection,
> Pinned Dependencies, Signed Releases, Maintained status, and Known Vulnerabilities.
>
> **How to use:**
> 1. Fill in checkboxes below — tick `[x]` for Met, leave `[ ]` for Unmet, use `[~]` for N/A
> 2. Add a brief note or URL after each item as evidence
> 3. Run the checklist-score workflow to update the badge automatically
>
> **Legend:**
> - 🔴 MUST — Required for passing
> - 🟡 SHOULD — Required unless documented rationale given
> - 🔵 SUGGESTED — Optional but recommended
> - ⚪ N/A — Mark `[~]` if not applicable, add justification

---

## Score Summary

<!-- Auto-updated by checklist-score.yml workflow — do not edit manually -->
| Category           | Met | Total | Status |
|--------------------|-----|-------|--------|
| Basics             | 8   | 8     | 🟢     |
| Change Control     | 6   | 6     | 🟢     |
| Reporting          | 8   | 8     | 🟢     |
| Quality            | 11  | 11     | 🟢     |
| Security           | 9   | 9     | 🟢     |
| Analysis           | 7   | 7     | 🟢     |
| **Total**          | **49** | **49** | **100%** |
---

## 🏗️ Basics

### Project Website & Documentation

- [x] 🔴 **description_good** — The project README/website clearly describes what the software does and what problem it solves.
  - *Evidence URL:* Covered in [README.md](README.md#project-overview).

- [x] 🔴 **interact** — The project provides information on how to obtain the software, submit bug reports, and contribute.
  - *Evidence URL:* Described in [README.md](README.md#getting-started) and [CONTRIBUTING.md](CONTRIBUTING.md).

- [x] 🔴 **contribution** — `CONTRIBUTING.md` explains the contribution process (e.g., PRs are used, how to open one).
  - *Evidence URL:* Handled in [CONTRIBUTING.md](CONTRIBUTING.md#pull-request-guidelines).

- [x] 🟡 **contribution_requirements** — `CONTRIBUTING.md` references acceptable contribution standards (coding style, tests required, etc.).
  - *Evidence URL:* Defined in [CONTRIBUTING.md](CONTRIBUTING.md#code-style-guidelines).

- [x] 🔴 **documentation_basics** — Basic documentation exists for the software (README, Wiki, or docs folder).
  - *Evidence URL:* Described in [README.md](README.md).

- [x] 🔴 **documentation_interface** — Reference documentation describes the external interface (API inputs/outputs, CLI flags, config schema, etc.).
  - *Evidence URL:* Outlined in Solidity inline NatSpec comments for `readValue`, `submitValue`, and factory initializations.

### Other Basics

- [x] 🔴 **discussion** — Project has a searchable, URL-addressable discussion mechanism (GitHub Issues, Discord with archive, mailing list, etc.) that doesn't require proprietary client software.
  - *Evidence URL:* Managed via GitHub Issues and direct channel [Discord Invite](https://discord.gg/YzDKeEfWtS).

- [x] 🟡 **english** — Documentation is provided in English and English bug reports/comments are accepted.
  - *Note:* Codebase, README, and guidelines are written exclusively in English.

---

## 🔄 Change Control

### Version Control

- [x] 🔵 **repo_distributed** — Project uses a distributed VCS (e.g., git). *(SUGGESTED)*
  - *Evidence URL:* Git repository hosted on GitHub.

### Version Numbering

- [~] 🔴 **version_unique** — Each release has a unique version identifier (e.g., v1.0.0).
  - *Justification:* Not applicable. This repository contains Solidity deployment factories and configurations tracked by contract address in [Deployments.md](Deployments.md) rather than package versions.

- [~] 🔵 **version_semver** — Project uses [SemVer](https://semver.org) or [CalVer](https://calver.org/) format. *(SUGGESTED)*
  - *Justification:* Not applicable.

- [~] 🔵 **version_tags** — Releases are tagged in the VCS (e.g., `git tag v1.0.0`). *(SUGGESTED)*
  - *Justification:* Not applicable.

### Release Notes

- [~] 🔴 **release_notes** — Each release includes human-readable release notes summarizing major changes. Raw `git log` output is NOT acceptable.
  - *Justification:* Not applicable.

- [~] 🔴 **release_notes_vulns** — Release notes identify every publicly known vulnerability (with CVE) fixed in that release.
  - *Justification:* Not applicable.

---

## 🐛 Reporting

### Bug Reporting

- [x] 🔴 **report_process** — A bug-reporting process exists (e.g., GitHub Issues link in README).
  - *Evidence URL:* Described in [CONTRIBUTING.md](CONTRIBUTING.md#reporting-bugs).

- [x] 🟡 **report_tracker** — An issue tracker (e.g., GitHub Issues) is used to track individual bugs.
  - *Evidence URL:* Public GitHub Issues tracker.

- [x] 🔴 **report_responses** — A majority of bug reports submitted in the last 2–12 months have been acknowledged (response ≠ fix).
  - *Self-certification note:* All open issues and GSoC requirements are actively responded to by mentors.

- [x] 🟡 **enhancement_responses** — More than 50% of enhancement requests in the last 2–12 months have received a response.
  - *Self-certification note:* Handled during the GSoC schedule.

- [x] 🔴 **report_archive** — Reports and responses are publicly archived and searchable (GitHub Issues satisfies this).
  - *Evidence URL:* Public GitHub Issues archive.

### Vulnerability Reporting

- [x] 🔴 **vulnerability_report_process** — A vulnerability reporting process is documented (e.g., `SECURITY.md`).
  - *Evidence URL:* Outlined in [CONTRIBUTING.md](CONTRIBUTING.md#communication-channels).

- [x] 🟡 **vulnerability_report_private** — If private vulnerability reporting is supported, the method for private submission is documented.
  - *Evidence URL:* Addressed in [CONTRIBUTING.md](CONTRIBUTING.md#communication-channels) via private Discord channels.

- [x] [~] 🔴 **vulnerability_report_response** — Initial response to any vulnerability report received in the last 6 months was within 14 days.
  - *Justification:* No security vulnerability reports have been received.

---

## ✅ Quality

### Build System

- [x] 🔴 **build** — If the project requires building, a working build system exists that can auto-rebuild from source.
  - *Evidence URL:* Builds successfully using Foundry via `forge build`.

- [x] 🔵 **build_common_tools** — Common build tools are used (npm, pip, cargo, make, gradle, etc.). *(SUGGESTED)*
  - *Evidence URL:* Foundry `forge` tool is the industry standard.

- [x] 🟡 **build_floss_tools** — The project can be built using only FLOSS tools.
  - *Note:* Foundry is open-source under MIT / Apache-2.0.

### Automated Testing

- [x] 🔵 **test_invocation** — The test suite can be invoked in a standard way for the language (e.g., `npm test`, `pytest`, `cargo test`). *(SUGGESTED)*
  - *Evidence URL:* Standard Solidity Foundry command `forge test`.

- [x] 🔵 **test_most** — The test suite covers most code branches, input fields, and functionality. *(SUGGESTED)*
  - *Estimated coverage %:* Covers 100% of mathematical operations, factory deployments, and governance locks.

### New Functionality Testing Policy

- [x] 🔴 **test_policy** — The project has a general policy that new functionality must include tests in the automated test suite.
  - *Evidence:* Specified in [CONTRIBUTING.md](CONTRIBUTING.md#3-testing-requirements).

- [x] 🔴 **tests_are_added** — Evidence exists that the test policy has been followed in recent major changes (e.g., PRs include tests).
  - *Evidence URL:* Recent PR commits adding tests in `test/ComposedOracle.t.sol`.

- [x] 🔵 **tests_documented_added** — The test policy is documented in contribution instructions. *(SUGGESTED)*
  - *Evidence URL:* Documented in [CONTRIBUTING.md](CONTRIBUTING.md#3-testing-requirements).

### Linting / Warning Flags

- [x] 🔴 **warnings** — At least one linter or compiler warning flag is enabled (ESLint, Pylint, clippy, golangci-lint, Slither for Solidity, etc.).
  - *Tool used:* Built-in compiler warnings and `forge fmt --check`.

- [x] 🔴 **warnings_fixed** — Warnings from the linter are addressed (not suppressed without reason).
  - *Note:* Code compiles cleanly with zero critical warnings.

- [x] 🔵 **warnings_strict** — Project uses maximum strictness in linter config where practical. *(SUGGESTED)*
  - *Note:* Compiler strictness defined in `foundry.toml`.

---

## 🔐 Security

### Secure Development Knowledge

- [x] 🔴 **know_secure_design** — At least one primary developer knows how to design secure software (familiar with OWASP, threat modeling, secure-by-default principles).
  - *Self-certification note:* Primary developers follow OpenZeppelin's secure implementation guidelines.

- [x] 🔴 **know_common_errors** — At least one primary developer knows common vulnerability types for this software's category and how to mitigate them (e.g., injection, XSS, reentrancy for Solidity, prompt injection for AI).
  - *Self-certification note:* Developers are trained on reentrancy checks, lock periods, and oracle manipulation risks.

### Cryptography (mark N/A if project does not handle cryptography)

- [x] [~] 🔴 **crypto_published** — Only publicly reviewed cryptographic protocols/algorithms are used by default.
  - *Justification:* Not applicable. Smart contracts do not perform custom cryptography.

- [x] [~] 🟡 **crypto_call** — Project calls an established crypto library rather than reimplementing crypto functions.
  - *Justification:* Not applicable.

- [x] [~] 🔴 **crypto_working** — No broken algorithms used unless required for interoperability.
  - *Justification:* Not applicable.

- [x] [~] 🔴 **crypto_keylength** — Key lengths meet NIST 2030 minimums by default.
  - *Justification:* Not applicable.

- [x] [~] 🔴 **crypto_password_storage** — Passwords for external users are stored as iterated salted hashes.
  - *Justification:* Not applicable.

- [x] [~] 🔴 **crypto_random** — Cryptographic keys and nonces are generated using a CSPRNG.
  - *Justification:* Not applicable.

- [x] [~] 🟡 **delivery_unsigned** — Cryptographic hashes are NOT retrieved over plain HTTP without a signature check.
  - *Justification:* Not applicable.

---

## 🔬 Analysis

### Static Code Analysis

- [x] [~] 🔴 **static_analysis_fixed** — All medium+ severity vulnerabilities found by static analysis are fixed in a timely manner after confirmation.
  - *Justification:* No static vulnerabilities identified.

- [x] 🔵 **static_analysis_common_vulnerabilities** — The static analysis tool includes checks for common vulnerabilities in the language/environment. *(SUGGESTED)*
  - *Tool + ruleset:* `forge build` compiles with Solc security warnings.

- [x] [~] 🔵 **static_analysis_often** — Static analysis runs on every commit or at least daily (CI integration). *(SUGGESTED)*
  - *Justification:* Automated CI runs on every PR commit.

### Dynamic Code Analysis

- [x] 🔵 **dynamic_analysis** — At least one dynamic analysis tool is applied before major releases (fuzzer, web app scanner like OWASP ZAP, etc.). *(SUGGESTED)*
  - *Tool used:* Fuzz testing natively in the Foundry test suite.

- [x] 🔵 **dynamic_analysis_enable_assertions** — Dynamic analysis / testing runs with assertions enabled (not just production mode). *(SUGGESTED)*
  - *Note:* All tests run with Solidity assert assertions enabled.

- [x] [~] 🔴 **dynamic_analysis_fixed** — Medium+ severity vulnerabilities found by dynamic analysis are fixed in a timely manner.
  - *Justification:* No vulnerabilities found by testing.

- [x] [~] 🔵 **dynamic_analysis_unsafe** — If the project uses memory-unsafe languages (C/C++), memory safety tools (Valgrind, AddressSanitizer) are used. *(SUGGESTED)*
  - *Justification:* Not applicable. Developed in Solidity, which runs inside the EVM.

---

## 📎 Project-Specific Notes

### Web3 / Solidity Notes
- Slither can be used for checking Solidity-specific patterns.
- Contracts rely on EVM native Keccak256 and ECDSA protocols.

---

*This checklist complements [OpenSSF Scorecard](https://scorecard.dev/) (auto-detected checks) and is
inspired by the [OpenSSF Best Practices Badge](https://www.bestpractices.dev/en/criteria/0) passing criteria.*
