---
bug_id: BUG-2026-09-10T183556Z
status: fixed
severity: medium
scope: omp
issue: 580
title: Bigpowers MCP server cannot start in OMP
---

# BUG-2026-09-10T183556Z: Bigpowers MCP server cannot start in OMP

## Problem

OMP reports an `ENOENT` error for `posix_spawn 'node'` during startup. Node is available in the OMP process environment.

OMP must start without this MCP error. The native Bigpowers skills must remain available in every project.

Security impact: NONE. No security exploit path exists.

This defect is new. The bug registry contains no related entry.

## Root Cause Analysis

### Reproduce

The installed plugin declares a workspace placeholder as its working directory. OMP does not define this placeholder as an environment variable.

A Bun subprocess with an available command and a missing working directory returns the reported `posix_spawn` error.

### Isolate

The plugin installation succeeds. OMP lists and enables the plugin. The failure occurs in its redundant MCP subprocess configuration.

### Hypotheses

1. Node is absent from the OMP environment. The OMP environment disproves this hypothesis.
2. The MCP build output is absent. The installed package disproves this hypothesis.
3. The unresolved working directory does not exist. The matching Bun error confirms this hypothesis.
4. The nested MCP runtime dependencies are available. A direct launch disproves this hypothesis.

### Verify

The plugin directory contains the compiled MCP entry point. All inspected shell contexts resolve Node.

Bun returns the exact reported error when only the subprocess working directory is absent. A corrected launch then reports a missing MCP SDK.

These results confirm two package defects. The plugin already exposes its catalog through the native OMP extension.

Risk level: Low. The fix disables only the duplicate server and preserves the native Bigpowers tools.

## TDD Fix Plan

1. **RED**: Add a test that disables one MCP server in an existing user configuration.
   **GREEN**: Add a helper that preserves unrelated server definitions and existing denylist entries.
   **Verify**: Run `bats tests/helpers.bats`.

**REFACTOR**: Use OMP's user denylist. Do not patch the installed plugin package.

## Acceptance Criteria

- [x] OMP starts without the Bigpowers MCP error.
- [x] The native Bigpowers skills remain available.
- [x] The setup script preserves unrelated user MCP definitions.
- [x] The setup script applies the denylist entry idempotently.
- [x] The test suite and lint checks pass.

## Resolution

**Fixed:** 2026-09-10

**Root cause confirmed:** The published plugin has an invalid working directory and lacks its nested MCP runtime dependencies.

**Fix applied:** The generated OMP user denylist disables only the redundant server. The native Bigpowers extension remains active.

**Hardening added:** An atomic JSON helper validates the denylist shape. Tests cover preservation, idempotency, empty input, malformed input, and dry runs.

**Generalization sweep:** The repository contains no other workspace placeholders or plugin MCP definitions.

**Evidence:** `just preflight` passed 87 tests. `just verify` reported 23 verified and zero failed configurations.

The OMP runtime listed `bigpowers-mcp` as disabled and loaded 81 native Bigpowers skills.

**Commits:** `2d65f56`, `f173750`, `de4d8dc`, `061ed9f`, `fc7b0dc`, `203262b`
