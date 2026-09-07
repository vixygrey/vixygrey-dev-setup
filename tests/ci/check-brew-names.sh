#!/usr/bin/env bash
# tests/ci/check-brew-names.sh
#
# #384: every `brew_install "X"` and `brew_cask_install "X"` declaration in
# setup-dev-tools-mac.sh must use a name that exists, in the declared type, in
# Homebrew's current core API. The check fails on:
#   - alias / oldname / old_token (proves #371 — kubectl being an alias for
#     kubernetes-cli — cannot recur)
#   - wrong type: declared as formula when only a cask exists, or vice versa
#     (proves #366 — tflint/keyward — cannot recur for core packages)
#   - bare name not in core API (must be of the form user/repo/name, which
#     declares its own tap and is unambiguous)
#
# Runs on ubuntu-latest in lint.yml, no Homebrew needed.
#
# Inputs (positional): formula_json_path cask_json_path script_path
# Output: prints status lines to stdout; non-zero exit on the first violation
# with a full summary at the end.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 formula.json cask.json setup-dev-tools-mac.sh" >&2
    exit 2
fi
FORMULA_JSON="$1"
CASK_JSON="$2"
SCRIPT="$3"

# Build the lookup tables once. Core formulae: name -> canonical; aliases:
# alias -> canonical. Same for casks (token == name). Both APIs grow daily, so
# we rebuild on every CI run; the actions/cache job keeps the cost down.
echo "Building core formula lookup..."
declare -A FORMULA_NAMES
declare -A FORMULA_ALIASES
declare -A FORMULA_OLDNAMES
while IFS=$'\t' read -r canonical alias oldname; do
    FORMULA_NAMES[$canonical]=1
    [[ -n "$alias"   ]] && FORMULA_ALIASES[$alias]=$canonical
    [[ -n "$oldname" ]] && FORMULA_OLDNAMES[$oldname]=$canonical
done < <(jq -r '.[] | [.name, (.aliases // [] | join(" ")), (.oldnames // [] | join(" "))] | @tsv' "$FORMULA_JSON")

echo "Building core cask lookup..."
declare -A CASK_TOKENS
declare -A CASK_OLD_TOKENS
while IFS=$'\t' read -r token old; do
    CASK_TOKENS[$token]=1
    [[ -n "$old" ]] && CASK_OLD_TOKENS[$old]=$token
done < <(jq -r '.[] | [.token, (.old_tokens // [] | join(" "))] | @tsv' "$CASK_JSON")

# `claws` is shipped by `clawscli/tap` as BOTH a formula and a cask (the issue).
# Homebrew's `brew info` defaults to formula, so `brew info --json=v2 claws`
# reports the formula. We allow either type for any name present in both sets.
declare -A BOTH
for k in "${!FORMULA_NAMES[@]}"; do
    [[ -n "${CASK_TOKENS[$k]:-}" ]] && BOTH[$k]=1
done
for k in "${!CASK_TOKENS[@]}"; do
    [[ -n "${FORMULA_NAMES[$k]:-}" && -z "${BOTH[$k]:-}" ]] && BOTH[$k]=1
done

# Pull every declaration out of the script in order: TYPE<TAB>NAME.
mapfile -t DECLS < <(
    grep -nE '^(brew_install|brew_cask_install) "[^"]+"' "$SCRIPT" \
        | awk -F'"' '{print $2 "\t" $1}' \
        | awk '{sub(/^[^[:space:]]+:brew_/, "brew_", $2); print $2 "\t" $1}'
)

violations=0
MSGS=()
bump() { violations=$(( violations + 1 )); }

for decl in "${DECLS[@]}"; do
    type="${decl%%	*}"
    name="${decl##*	}"
    short="${name##*/}"
    kind="formula"; [[ "$type" == "brew_cask_install" ]] && kind="cask"

    # Tap packages must declare their tap explicitly: `user/repo/name`. A bare
    # name that is NOT in the core API cannot be distinguished from a typo, so
    # we reject it.
    if [[ "$name" != */* ]]; then
        if [[ "$kind" == "formula" && -z "${FORMULA_NAMES[$short]:-}${FORMULA_ALIASES[$short]:-}" ]]; then
            MSGS+=("FAIL  $type \"$name\" — bare name not in core formulae (use 'user/repo/$short')")
            bump; continue
        fi
        if [[ "$kind" == "cask" && -z "${CASK_TOKENS[$short]:-}" ]]; then
            MSGS+=("FAIL  $type \"$name\" — bare name not in core casks (use 'user/repo/$short')")
            bump; continue
        fi
    fi

    # Resolve the canonical name. For taps, skip the core-API checks (we trust
    # the tap). For core, check the alias/oldname/type-mismatch classes.
    if [[ "$name" == */* ]]; then
        # `user/repo/name` form. Sanity-check the three-segment shape.
        if [[ $(awk -F/ '{print NF}' <<<"$name") -lt 3 ]]; then
            MSGS+=("FAIL  $type \"$name\" — tap path must be 'user/repo/name'")
            bump
        fi
        continue
    fi

    # Alias / oldname: the declared name exists but is not canonical.
    if [[ -n "${FORMULA_ALIASES[$name]:-}" && "$kind" == "formula" ]]; then
        MSGS+=("FAIL  $type \"$name\" — alias of \"${FORMULA_ALIASES[$name]}\" (use the canonical name)")
        bump; continue
    fi
    if [[ -n "${FORMULA_OLDNAMES[$name]:-}" && "$kind" == "formula" ]]; then
        MSGS+=("FAIL  $type \"$name\" — oldname, current name is \"${FORMULA_OLDNAMES[$name]}\"")
        bump; continue
    fi
    if [[ -n "${CASK_OLD_TOKENS[$name]:-}" && "$kind" == "cask" ]]; then
        MSGS+=("FAIL  $type \"$name\" — old_token, current token is \"${CASK_OLD_TOKENS[$name]}\"")
        bump; continue
    fi

    # Type mismatch: declared as one kind, exists as the other (unless both).
    if [[ "$kind" == "formula" && -z "${FORMULA_NAMES[$name]:-}" && -z "${BOTH[$name]:-}" ]]; then
        MSGS+=("FAIL  $type \"$name\" — declared as formula but not in core formulae (is it a cask?)")
        bump; continue
    fi
    if [[ "$kind" == "cask" && -z "${CASK_TOKENS[$name]:-}" && -z "${BOTH[$name]:-}" ]]; then
        MSGS+=("FAIL  $type \"$name\" — declared as cask but not in core casks (is it a formula?)")
        bump; continue
    fi
done

echo ""
echo "Checked ${#DECLS[@]} Homebrew declarations:"
if (( ${#MSGS[@]} > 0 )); then
    printf '  %s\n' "${MSGS[@]}"
fi
echo ""
if (( violations > 0 )); then
    echo "FAIL: $violations declaration(s) failed the canonical-name / type check (#384)"
    exit 1
fi
echo "OK: every declared Homebrew name is canonical for its type"
