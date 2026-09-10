#!/usr/bin/env bats
#
# tests/cleanup-npm.bats
#
# End-to-end tests for the `npm` arm of the --cleanup dispatch (#399).
#
# These do NOT use SETUP_LIB_ONLY: the dispatch is inline in the --cleanup block,
# and the lib-only guard returns at line ~1316, well before it. The block is
# self-contained though — it runs and `exit 0`s ahead of both preflight and
# acquire_lock — so invoking the real script with --cleanup is safe, needs no
# lock, and exercises the actual `case` rather than a copy of it.
#
# Every test runs against a stubbed PATH in a temp $HOME. `npm` is a recording
# stub, so "did it try to uninstall?" is an assertion rather than an inference.

setup() {
    TEST_TMP="$(mktemp -d)"
    export HOME="$TEST_TMP"
    export SETUP_SCRIPT="$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh"

    # Stub bin dir, ahead of everything real.
    STUB="$TEST_TMP/bin"
    mkdir -p "$STUB"

    # Fake global npm root the stub reports and the script probes.
    NPM_ROOT="$TEST_TMP/npm-root"
    mkdir -p "$NPM_ROOT"

    # Recording npm stub: `root -g` answers, `uninstall` is logged and never real.
    cat > "$STUB/npm" <<STUB_NPM
#!/usr/bin/env bash
if [[ "\$1" == "root" ]]; then echo "$NPM_ROOT"; exit 0; fi
if [[ "\$1" == "uninstall" ]]; then echo "\$*" >> "$TEST_TMP/npm-uninstall.log"; exit 0; fi
exit 0
STUB_NPM
    chmod +x "$STUB/npm"

    # brew/mas are stubbed rather than left to the real machine. The brew stub
    # models ffmpeg as installed and records uninstall attempts. This keeps the
    # cleanup regression hermetic while all unrelated formula probes stay absent.
    cat > "$STUB/brew" <<STUB_BREW
#!/usr/bin/env bash
if [[ "\$*" == "list ffmpeg" ]]; then exit 0; fi
if [[ "\$1" == "uninstall" ]]; then echo "\$*" >> "$TEST_TMP/brew-uninstall.log"; exit 0; fi
exit 1
STUB_BREW
    cat > "$STUB/mas" <<'STUB_MAS'
#!/usr/bin/env bash
exit 1
STUB_MAS
    chmod +x "$STUB/brew" "$STUB/mas"

    export PATH="$STUB:$PATH"
    : > "$TEST_TMP/npm-uninstall.log"
    : > "$TEST_TMP/brew-uninstall.log"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "npm row is reported when the package is present in the global root" {
    mkdir -p "$NPM_ROOT/playwright"
    run bash "$SETUP_SCRIPT" --cleanup --dry-run --no-prompt
    [ "$status" -eq 0 ]
    # The exact dry-run line, not just the display name: the loud `*)` default also
    # prints the display name, so a substring match on "Playwright" alone passes even
    # when the npm arm has been deleted. That mistake made the first version of this
    # file pass against a mutant with the arm removed.
    [[ "$output" == *"Would remove: Playwright (replaced by removed)"* ]]
    # And prove it was the npm arm that handled it, not the fallthrough.
    [[ "$output" != *"unknown entry type 'npm'"* ]]
}

@test "npm row is a silent skip when the package is absent" {
    # No package dir created.
    run bash "$SETUP_SCRIPT" --cleanup --dry-run --no-prompt
    [ "$status" -eq 0 ]
    [[ "$output" != *"Would remove: Playwright"* ]]
    # A skip, not a fallthrough — this is what distinguishes "the arm ran and found
    # nothing" from "no arm matched".
    [[ "$output" != *"unknown entry type 'npm'"* ]]
}

@test "--dry-run never invokes npm uninstall" {
    mkdir -p "$NPM_ROOT/playwright" "$NPM_ROOT/storybook" "$NPM_ROOT/repomix"
    run bash "$SETUP_SCRIPT" --cleanup --dry-run --no-prompt
    [ "$status" -eq 0 ]
    # Pin that the arm actually ran; otherwise an empty log proves nothing.
    [[ "$output" == *"Would remove: Playwright (replaced by removed)"* ]]
    # The recording stub is the proof: an empty log means nothing was uninstalled.
    [ ! -s "$TEST_TMP/npm-uninstall.log" ]
}


@test "a missing npm makes every npm row a skip, not an error" {
    # _npm_root is empty when npm is absent. Removing the stub is the only way to
    # reach that branch, and it must not warn or fail.
    mkdir -p "$NPM_ROOT/playwright"
    rm -f "$STUB/npm"
    run bash "$SETUP_SCRIPT" --cleanup --dry-run --no-prompt
    [ "$status" -eq 0 ]
    [[ "$output" != *"Would remove: Playwright"* ]]
    [[ "$output" != *"unknown entry type 'npm'"* ]]
}

@test "--cleanup keeps ffmpeg when retained formulae require it (#563)" {
    run bash "$SETUP_SCRIPT" --cleanup --no-prompt
    [ "$status" -eq 0 ]
    [ ! -s "$TEST_TMP/brew-uninstall.log" ]
    [[ "$output" != *"Failed to remove ffmpeg"* ]]
}


@test "an unknown entry type still hits the loud default" {
    # Regression guard for the #242 class: a type matching no arm must warn, not
    # silently no-op. `pnpm` is the realistic typo now that `npm` is a valid key.
    bogus="$TEST_TMP/bogus.sh"
    awk '/^        "npm:playwright:Playwright:removed"$/ {
           print "        \"pnpm:ghost:Ghost Tool:removed\""
         } { print }' "$SETUP_SCRIPT" > "$bogus"
    grep -q 'pnpm:ghost' "$bogus" || { echo "injection failed"; return 1; }
    run bash "$bogus" --cleanup --dry-run --no-prompt
    [ "$status" -eq 0 ]
    [[ "$output" == *"unknown entry type 'pnpm'"* ]]
}
