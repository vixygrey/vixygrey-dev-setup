set shell := ["bash", "-cu"]

SCRIPT := "scripts/setup-dev-tools-mac.sh"

# List all recipes
default:
    @just --list

# ── Verification ─────────────────────────────────────────────────────────────

# Syntax check, then ShellCheck at the severity CI uses
lint:
    bash -n {{SCRIPT}}
    shellcheck -x -S warning {{SCRIPT}}

# Helper unit tests (runs the helper layer under SETUP_LIB_ONLY=1)
test:
    bats tests/

# Preview a full run without touching the machine
dry-run:
    ./{{SCRIPT}} --dry-run --no-prompt

# All pre-commit hooks: ShellCheck, gitleaks, typos, file hygiene
hooks:
    pre-commit run --all-files

# Everything a PR must pass. Mirrors .github/workflows/lint.yml.
preflight: lint test dry-run hooks

# ── Machine checks ───────────────────────────────────────────────────────────

# Not part of preflight: the answer depends on which tools this machine has,
# so it cannot gate a PR. Run it after touching any config path.

# Ask each installed tool whether it actually reads what we generate
verify:
    ./{{SCRIPT}} --verify

# Categories available to --only / --skip
categories:
    ./{{SCRIPT}} --list-categories

# ── Release ──────────────────────────────────────────────────────────────────

# Current version, straight from the script
version:
    @./{{SCRIPT}} --version
