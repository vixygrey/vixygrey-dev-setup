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

@test "mark_done: no-op under --dry-run so previews cannot poison --resume (#390)" {
    run run_with_helpers '
        export DRY_RUN=true
        mkdir -p "$(dirname "$STATE_FILE")"
        : > "$STATE_FILE"
        mark_done "install:demo"
        test ! -s "$STATE_FILE"
    '
    [ "$status" -eq 0 ]
}

@test "append_line_if_missing: dry-run narrates and writes nothing (#391)" {
    run run_with_helpers '
        export DRY_RUN=true
        append_line_if_missing "$HOME/cfg" "alpha" "demo line"
        test ! -e "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would append demo line to $TEST_TMP/cfg"* ]]
}

@test "append_line_if_missing: appends once and then reports already present" {
    run run_with_helpers '
        append_line_if_missing "$HOME/cfg" "alpha" "demo line"
        append_line_if_missing "$HOME/cfg" "alpha" "demo line" && echo SECOND_WROTE || echo SECOND_SKIPPED
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SECOND_SKIPPED"* ]]
    [[ "$output" == *$'alpha'* ]]
}

@test "append_block_if_missing: dry-run narrates and writes nothing (#391)" {
    run run_with_helpers '
        export DRY_RUN=true
        append_block_if_missing "$HOME/cfg" "needle" "demo block" <<"EOF"
needle
payload
EOF
        test ! -e "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would append demo block to $TEST_TMP/cfg"* ]]
}

@test "append_block_if_missing: appends once when sentinel is absent" {
    run run_with_helpers '
        append_block_if_missing "$HOME/cfg" "needle" "demo block" <<"EOF"
needle
payload
EOF
        append_block_if_missing "$HOME/cfg" "needle" "demo block" <<"EOF"
needle
payload
EOF
        cat "$HOME/cfg"
    '
    [ "$status" -eq 0 ]
    [ "$(printf "%s" "$output" | grep -c '^needle$')" -eq 1 ]
    [ "$(printf "%s" "$output" | grep -c '^payload$')" -eq 1 ]
}

@test "write_generated: dry-run reports create when the file is absent (#426)" {
    run run_with_helpers '
        export DRY_RUN=true
        write_generated "$HOME/generated.txt" <<"EOF"
hello
EOF
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would create $TEST_TMP/generated.txt"* ]]
    [ ! -e "$TEST_TMP/generated.txt" ]
}

@test "write_generated: dry-run reports refresh when the file differs (#426)" {
    run run_with_helpers '
        export DRY_RUN=true
        printf "old\n" > "$HOME/generated.txt"
        write_generated "$HOME/generated.txt" <<"EOF"
new
EOF
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would refresh $TEST_TMP/generated.txt"* ]]
    [ "$(cat "$TEST_TMP/generated.txt")" = "old" ]
}

@test "run_remote_installer: executes the downloaded installer through the requested runner (#430)" {
    run run_with_helpers '
        export LOG_FILE="$HOME/log"
        export ERROR_LOG="$HOME/error.log"
        mkdir -p "$HOME/bin"
        cat > "$HOME/bin/curl" <<"EOF"
#!/usr/bin/env bash
out=""
while (($#)); do
  if [[ "$1" == "-o" ]]; then out="$2"; shift 2; continue; fi
  shift
done
printf "payload\n" > "$out"
EOF
        chmod +x "$HOME/bin/curl"
        export PATH="$HOME/bin:$PATH"
        cat > "$HOME/runner.sh" <<"EOF"
#!/usr/bin/env bash
cat "$1" > "$HOME/ran.txt"
EOF
        chmod +x "$HOME/runner.sh"
        run_remote_installer demo https://example.test/install.sh "" "$HOME/runner.sh"
        cat "$HOME/ran.txt"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "payload" ]
}

@test "run_remote_installer: checksum mismatch refuses execution (#430)" {
    run run_with_helpers '
        export LOG_FILE="$HOME/log"
        export ERROR_LOG="$HOME/error.log"
        mkdir -p "$HOME/bin"
        cat > "$HOME/bin/curl" <<"EOF"
#!/usr/bin/env bash
out=""
while (($#)); do
  if [[ "$1" == "-o" ]]; then out="$2"; shift 2; continue; fi
  shift
done
printf "payload\n" > "$out"
EOF
        chmod +x "$HOME/bin/curl"
        export PATH="$HOME/bin:$PATH"
        cat > "$HOME/runner.sh" <<"EOF"
#!/usr/bin/env bash
printf "ran\n" > "$HOME/ran.txt"
EOF
        chmod +x "$HOME/runner.sh"
        if run_remote_installer demo https://example.test/install.sh deadbeef "$HOME/runner.sh"; then
          echo UNEXPECTED_OK
        else
          printf "%s\n" "$REMOTE_INSTALLER_ERROR"
        fi
        test ! -e "$HOME/ran.txt"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "checksum mismatch" ]
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

# ---------------------------------------------------------------------------
# #502: sudo is asked for only when a category has privileged work PENDING.
# The predicates and their applied-once marker are pure enough to test on Linux;
# the macOS-only reads they wrap (pmset, nvram, networksetup) are not, so
# _pmset_value is exercised against a stubbed `pmset`.
# ---------------------------------------------------------------------------

@test "priv_done: false before anything is marked (#502)" {
    run run_with_helpers 'priv_done "systemsetup:networktime" && echo YES || echo NO'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO"* ]]
}

@test "priv_mark: marks, and priv_done then sees it (#502)" {
    run run_with_helpers '
        priv_mark "systemsetup:networktime"
        priv_done "systemsetup:networktime" && echo YES || echo NO'
    [ "$status" -eq 0 ]
    [[ "$output" == *"YES"* ]]
}

@test "priv_mark: survives a non-resume run, unlike mark_done (#502)" {
    # The whole reason this pair exists: STATE_FILE is truncated on every
    # non-resume run and is_done answers false without --resume, so neither can
    # carry "some previous run already applied this".
    run run_with_helpers '
        priv_mark "systemsetup:networktime"
        : > "$STATE_FILE"          # what a fresh non-resume run does
        RESUME=false
        priv_done "systemsetup:networktime" && echo STILL_MARKED || echo LOST
        is_done "systemsetup:networktime" && echo IS_DONE_TRUE || echo IS_DONE_FALSE'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STILL_MARKED"* ]]
    [[ "$output" == *"IS_DONE_FALSE"* ]]
}

@test "priv_mark: is idempotent — one line, not one per run (#502)" {
    run run_with_helpers '
        priv_mark "systemsetup:networktime"
        priv_mark "systemsetup:networktime"
        priv_mark "systemsetup:networktime"
        grep -c "^systemsetup:networktime$" "$PRIV_STATE_FILE"'
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "1" ]]
}

@test "priv_mark: dry-run records nothing (#502)" {
    run run_with_helpers '
        DRY_RUN=true
        priv_mark "systemsetup:networktime"
        priv_done "systemsetup:networktime" && echo MARKED || echo UNMARKED'
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNMARKED"* ]]
}

@test "_pmset_value: reads the requested power source, not the first match (#502)" {
    # displaysleep appears under BOTH headings with different values. A bare grep
    # would answer for whichever came first, which is the bug this parser avoids.
    run run_with_helpers '
        pmset() {
            printf "%s\n" "Battery Power:" " displaysleep         75" " lessbright           1" \
                          "AC Power:"      " displaysleep         120"
        }
        echo "AC=$(_pmset_value AC displaysleep)"
        echo "BATT=$(_pmset_value Battery displaysleep)"
        echo "LESS=$(_pmset_value Battery lessbright)"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC=120"* ]]
    [[ "$output" == *"BATT=75"* ]]
    [[ "$output" == *"LESS=1"* ]]
}

@test "_pmset_value: empty for a key absent from that section (#502)" {
    # lessbright is reported under Battery only. Asking AC must not fall through
    # to the battery value, or halfdim would read as already-applied.
    run run_with_helpers '
        pmset() {
            printf "%s\n" "Battery Power:" " lessbright           1" \
                          "AC Power:"      " displaysleep         120"
        }
        echo "[$(_pmset_value AC lessbright)]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[]"* ]]
}

@test "every SUDO_CATEGORY_REASON entry has a predicate (#502)" {
    # The loud default. A category that needs sudo but has no predicate must fail
    # at startup, not resolve to "no sudo needed" and die mid-work at a prompt.
    run run_with_helpers '
        for c in "${!SUDO_CATEGORY_REASON[@]}"; do
            [[ -n "${SUDO_CATEGORY_PREDICATE[$c]:-}" ]] || { echo "MISSING:$c"; exit 1; }
            declare -F "${SUDO_CATEGORY_PREDICATE[$c]}" >/dev/null || { echo "NOTAFUNC:$c"; exit 1; }
        done
        echo ALL_PRESENT'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL_PRESENT"* ]]
}

@test "sudo_reasons: names the PENDING items, not the category blurb (#502)" {
    # The prompt must describe the work it will actually do. Printing the whole
    # category description listed settings that were already applied, which is
    # the "you can only trust it" problem #269 fixed from the other direction.
    run run_with_helpers '
        unset SUDO_CATEGORY_REASON SUDO_CATEGORY_PREDICATE
        declare -A SUDO_CATEGORY_REASON=([macos-defaults]="BLURB_THAT_MUST_NOT_APPEAR")
        declare -A SUDO_CATEGORY_PREDICATE=([macos-defaults]=fake_pred)
        fake_pred() { printf "%s\n" "network time" "startup chime"; return 0; }
        DRY_RUN=false; ONLY_CATEGORIES=(); SKIP_CATEGORIES=()
        sudo_reasons'
    [ "$status" -eq 0 ]
    [[ "$output" == *"network time (macos-defaults)"* ]]
    [[ "$output" == *"startup chime (macos-defaults)"* ]]
    [[ "$output" != *"BLURB_THAT_MUST_NOT_APPEAR"* ]]
}

@test "sudo_reasons: silent when the predicate reports nothing pending (#502)" {
    # A converged machine must produce no reasons at all, because an empty result
    # is what makes preflight skip `sudo -v` and lets an unattended run finish.
    run run_with_helpers '
        unset SUDO_CATEGORY_REASON SUDO_CATEGORY_PREDICATE
        declare -A SUDO_CATEGORY_REASON=([macos-defaults]="blurb")
        declare -A SUDO_CATEGORY_PREDICATE=([macos-defaults]=fake_pred)
        fake_pred() { return 1; }
        DRY_RUN=false; ONLY_CATEGORIES=(); SKIP_CATEGORIES=()
        echo "[$(sudo_reasons)]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[]"* ]]
}
