---
bug_id: BUG-2026-09-10T203750Z
status: fixed
severity: medium
scope: setup
issue: 586
title: Incomplete Surge retirement
---

# BUG-2026-09-10T203750Z: Incomplete Surge retirement

## Problem

The recent tool retirement did not remove SurgeDM from the setup.

A normal setup run still taps the SurgeDM repository and requests the unqualified `surge` cask. Homebrew now resolves that token to the unrelated Nssurge application. Generated documents still describe SurgeDM and its background service.

The setup must not install SurgeDM or describe it as an active tool. Cleanup must preserve an unrelated Nssurge installation.

Security impact: LOW. The stale block can request a privileged background service installation. No security exploit path was identified.

## Root Cause Analysis

### Reproduce

The package list still contains a `surge` cask declaration. The generated checklist, summary, reference, and repository documentation still contain SurgeDM instructions.

Homebrew reports that the unqualified `surge` token belongs to `homebrew/cask`. The intended retired tool belongs to `surgedm/tap/surge`.

### Isolate

The active installation block contains the tap, cask request, and service installation. The generated documentation heredocs contain the remaining user instructions.

The recent retirement commit removed many workstation tools but did not change the Surge block. Repository history contains the original Surge addition and no completed Surge removal.

### Hypotheses

1. The retirement sweep omitted SurgeDM. The current source and retirement diff support this hypothesis.
2. A later change reintroduced SurgeDM. Repository history falsifies this hypothesis.
3. Only the documentation is stale. The active installation block falsifies this hypothesis.

### Verify

The current package list exposes `surge`. The dry run reaches its active installation declaration. The recent retirement diff contains no Surge removal.

The verified root cause is an omitted tool in the retirement sweep. The unqualified cask token also creates a collision with an unrelated application.

Risk level: Medium. Cleanup must identify SurgeDM by its qualified cask token and preserve the core Nssurge cask.

## TDD Fix Plan

1. **RED**: Add a cleanup test that models both casks and requires removal of only `surgedm/tap/surge`.
   **GREEN**: Add the qualified retired cask entry and uninstall its service before package removal.
   **verify**: `bats tests/cleanup-surge.bats`

2. **RED**: Require the public package list and generated documentation to omit active Surge references.
   **GREEN**: Remove the installation block and all current documentation references.
   **verify**: `bats tests/cleanup-surge.bats`

3. **RED**: Require cleanup to retain the unrelated core cask and remove an unused SurgeDM tap.
   **GREEN**: Add the retired tap entry and retain unowned SurgeDM application data for manual review.
   **verify**: `bats tests/cleanup-surge.bats`

**REFACTOR**: Keep cask identity checks qualified. Do not add a basename fallback for this collision.

## Acceptance Criteria

- [x] A setup run does not tap, install, start, or document SurgeDM.
- [x] `--list` does not report `surge` as an active cask.
- [x] `--cleanup` removes the qualified SurgeDM cask when present.
- [x] `--cleanup` preserves the unrelated core Surge cask.
- [x] `--cleanup` removes the SurgeDM tap only when it provides no installed package.
- [x] SurgeDM application data remains available for manual review.
- [x] The focused regression checks pass.
- [x] The full repository checks pass.

## Resolution

**Fixed:** 2026-09-10

**Root cause confirmed:** The workstation retirement sweep omitted the active SurgeDM installation and documentation.

**Fix applied:** The setup no longer installs or documents SurgeDM. Cleanup stops its service and removes only the qualified cask.

Cleanup removes and untrusts the unused SurgeDM tap. It preserves the core Surge cask and unowned application data.

**Hardening added:** Two behavioral checks cover the active package list, qualified cleanup, service removal, tap cleanup, and data preservation.

**Generalized sweep:** The script contains 11 active `trust_tap` calls. Other third-party installs use qualified package names.

Granted is the only nearby bare package. Its core formula and tapped formula refer to the same product.

**Evidence:** `bats tests/cleanup-surge.bats` passes 2 checks. `just preflight` passes all 90 repository checks.

**Commit:** Not created.
