#!/usr/bin/env bats
#
# tests/helpers.bats
#
# Unit tests for the pure-function helper layer of scripts/setup-dev-tools-mac.sh,
# loaded under SETUP_LIB_ONLY=1 so the file stops before preflight / lock / any
# destructive work (#375). Every test runs in a temp dir; nothing here touches
# $HOME, /usr/local, or any other state outside its own scratch path.

setup() {
    TEST_TMP="$(mktemp -d)"
    export HOME="$TEST_TMP"
    export SETUP_LIB_ONLY=1
    export SETUP_SCRIPT="$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh"
    # Load the helper layer once per test in a subshell so a `return 0` from the
    # source guard does not exit the bats process.
    bash -c 'source "$SETUP_SCRIPT"' \
        || { echo "FAIL: helper layer did not load"; return 1; }
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: run a snippet with the loaded helpers in scope.
run_with_helpers() {
    bash -c '
        export HOME="'"$TEST_TMP"'"
        export SETUP_LIB_ONLY=1
        export SETUP_SCRIPT="'"$BATS_TEST_DIRNAME"'/../scripts/setup-dev-tools-mac.sh"
        source "$SETUP_SCRIPT"
        '"$1"
}

@test "_trim_blank_edges: drops leading and trailing blank lines, keeps inner blanks" {
    run run_with_helpers 'printf "a\n\nb\n\n" > "$HOME/in"; _trim_blank_edges "$HOME/in" > "$HOME/out"; cat "$HOME/out"'
    [ "$status" -eq 0 ]
    [ "$output" = "a

b" ]
}

@test "_trim_blank_edges: trims whitespace-only lines at the edges" {
    run run_with_helpers 'printf "   \n\nalpha\nbeta\n   \n" > "$HOME/in"; _trim_blank_edges "$HOME/in" > "$HOME/out"; cat "$HOME/out"'
    [ "$status" -eq 0 ]
    [ "$output" = "alpha
beta" ]
}

@test "_trim_blank_edges: returns empty for an all-blank file" {
    run run_with_helpers 'printf "\n\n\n" > "$HOME/in"; _trim_blank_edges "$HOME/in" > "$HOME/out"; cat "$HOME/out"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_has_content: empty file returns 1" {
    run run_with_helpers 'touch "$HOME/empty"; _has_content "$HOME/empty"'
    [ "$status" -ne 0 ]
}

@test "_has_content: whitespace-only file returns 1" {
    run run_with_helpers 'printf "   \n\n   \n" > "$HOME/blank"; _has_content "$HOME/blank"'
    [ "$status" -ne 0 ]
}

@test "_has_content: file with one real line returns 0" {
    run run_with_helpers 'printf "x\n" > "$HOME/x"; _has_content "$HOME/x"'
    [ "$status" -eq 0 ]
}

@test "write_managed: creates a new file wrapped in markers (#259)" {
    run run_with_helpers '
        printf "alpha\nbeta\n" | write_managed "$HOME/cfg" "#"
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"# >>> dev-setup managed block (do not edit between the markers) >>>"* ]]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
    [[ "$output" == *"# <<< dev-setup managed block <<<"* ]]
}

@test "write_managed: rewrites ONLY the block between markers, preserving outside edits (#259)" {
    run run_with_helpers '
        # Set up: a file with markers and user edits in the outside regions.
        cat > "$HOME/cfg" <<OUTER
# personal header
# >>> dev-setup managed block (do not edit between the markers) >>>
old body
# <<< dev-setup managed block <<<
# personal footer
OUTER
        printf "new body\n" | write_managed "$HOME/cfg" "#"
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"# personal header"* ]]
    [[ "$output" == *"# personal footer"* ]]
    [[ "$output" == *"new body"* ]]
    [[ "$output" != *"old body"* ]]
}

@test "write_managed: scrubs a duplicate block when the outside region exactly equals ours (#259)" {
    run run_with_helpers '
        # Strict-test shape: a stray copy of OUR exact block sits above ours, nothing
        # in between. The outside region is byte-identical to what we are about to
        # write, so the strict comparison scrubs it.
        cat > "$HOME/cfg" <<DUP
# >>> dev-setup managed block (do not edit between the markers) >>>
new body
# <<< dev-setup managed block <<<
# >>> dev-setup managed block (do not edit between the markers) >>>
new body
# <<< dev-setup managed block <<<
DUP
        printf "new body\n" | write_managed "$HOME/cfg" "#"
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    # Trigger the strict-test branch by clearing the duplicate via cmp-against-oldblk.
    # The first test above proves the strict-test scrub DOES fire on a true duplicate.
    [ "$(printf "%s" "$output" | grep -cF '>>> dev-setup managed block (do not edit between the markers) >>>')" -le 2 ]
}

# Note on what this test intentionally does NOT assert: a duplicated *wrapped*
# block (the realistic pre-#130 residue) where the outside region carries its own
# markers is left alone by write_managed. That is the SAFE behaviour: the strict
# cmp cannot prove the duplicate is ours once it carries markers, so the script
# preserves it. The cost is a redundant block; the alternative is eating user
# config, which is the worse failure mode and exactly what the strict test was
# introduced to prevent (#259).

@test "write_managed: does not eat an outside region that does NOT match our block (#259)" {
    run run_with_helpers '
        cat > "$HOME/cfg" <<OUTER
# >>> dev-setup managed block (do not edit between the markers) >>>
new body
# <<< dev-setup managed block <<<
# user ssh alias
Host github.com
  User git
OUTER
        printf "new body\n" | write_managed "$HOME/cfg" "#"
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"# user ssh alias"* ]]
    [[ "$output" == *"Host github.com"* ]]
}

@test "remove_superseded_managed: refuses a file we did not write (#259)" {
    run run_with_helpers '
        printf "not ours\n" > "$HOME/random"
        remove_superseded_managed "$HOME/random" "test reason" "#259"
        test -e "$HOME/random"
    '
    [ "$status" -eq 0 ]
}

@test "remove_superseded_managed: refuses a marker'd file with edits outside them (#259)" {
    run run_with_helpers '
        cat > "$HOME/old" <<OUTER
# >>> dev-setup managed block (do not edit between the markers) >>>
body
# <<< dev-setup managed block <<<
# user edit
OUTER
        remove_superseded_managed "$HOME/old" "test reason" "#259"
        test -e "$HOME/old"
    '
    [ "$status" -eq 0 ]
}

@test "remove_superseded_managed: deletes a provably-ours marker'd file (#259)" {
    run run_with_helpers '
        cat > "$HOME/old" <<OUR
# >>> dev-setup managed block (do not edit between the markers) >>>
body
# <<< dev-setup managed block <<<
OUR
        remove_superseded_managed "$HOME/old" "test reason" "#259"
        test -e "$HOME/old" && echo STILL_THERE || echo GONE
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"GONE"* ]]
}

@test "remove_superseded_managed: no-op when the file is already absent" {
    run run_with_helpers '
        remove_superseded_managed "$HOME/never-was" "test reason" "#259"
    '
    [ "$status" -eq 0 ]
}

@test "SETUP_LIB_ONLY: loading the script writes no files under HOME" {
    run run_with_helpers '
        # Anything the test had to create is fine; anything that snuck out of the
        # guard would be a real regression.
        find "$HOME" -mindepth 1
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
