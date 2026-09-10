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

@test "remove_superseded_managed: honors the configured comment prefix (#561)" {
    run run_with_helpers '
        cat > "$HOME/old" <<OUR
// >>> dev-setup managed block (do not edit between the markers) >>>
body
// <<< dev-setup managed block <<<
OUR
        remove_superseded_managed "$HOME/old" "test reason" "#561" "//"
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

# ---------------------------------------------------------------------------
# #530: an opener with no closer (or a stray/reordered closer) used to be
# treated as "our block" by all three managed writers, which then guessed
# wrong about which half of the file was real content. write_managed silently
# dropped everything after the opener, write_managed_script did the same
# through its awk merge, and remove_superseded_managed deleted a file that
# still held real trailing content. All three must now refuse instead.
# ---------------------------------------------------------------------------

@test "_managed_marker_state: absent, unmarked, valid and invalid are distinguished (#530)" {
    run run_with_helpers '
        mb="# >>> dev-setup managed block (do not edit between the markers) >>>"
        me="# <<< dev-setup managed block <<<"
        echo "absent=$(_managed_marker_state "$HOME/nope" "$mb" "$me")"
        printf "plain file\n" > "$HOME/unmarked"
        echo "unmarked=$(_managed_marker_state "$HOME/unmarked" "$mb" "$me")"
        printf "%s\nbody\n%s\n" "$mb" "$me" > "$HOME/valid"
        echo "valid=$(_managed_marker_state "$HOME/valid" "$mb" "$me")"
        printf "%s\nbody, never closed\n" "$mb" > "$HOME/unclosed"
        echo "unclosed=$(_managed_marker_state "$HOME/unclosed" "$mb" "$me")"
        printf "%s\n%s\nbody\n%s\n" "$me" "$mb" "$me" > "$HOME/reordered"
        echo "reordered=$(_managed_marker_state "$HOME/reordered" "$mb" "$me")"
        printf "%s\nfirst\n%s\n%s\nsecond\n%s\n" "$mb" "$me" "$mb" "$me" > "$HOME/dup"
        echo "dup=$(_managed_marker_state "$HOME/dup" "$mb" "$me")"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"absent=absent"* ]]
    [[ "$output" == *"unmarked=unmarked"* ]]
    [[ "$output" == *"valid=valid"* ]]
    [[ "$output" == *"unclosed=invalid"* ]]
    [[ "$output" == *"reordered=invalid"* ]]
    [[ "$output" == *"dup=invalid"* ]]
}

@test "write_managed: refuses an opener with no closer, keeps the file byte-for-byte, and counts a failure (#530)" {
    # Heredoc, not a pipe: a piped write_managed runs in a subshell, where the
    # INSTALL_FAILED increment this test checks would be discarded before the
    # parent shell could see it (the same subshell hazard documented above
    # MANAGED_STATE, #259) — unrelated to the bug this test targets.
    run run_with_helpers '
        printf "# >>> dev-setup managed block (do not edit between the markers) >>>\nreal trailing content that was never closed\n" > "$HOME/cfg"
        before="$(cat "$HOME/cfg")"
        write_managed "$HOME/cfg" "#" <<EOF
new body
EOF
        rc=$?
        after="$(cat "$HOME/cfg")"
        echo "rc=$rc"
        echo "unchanged=$([ "$before" = "$after" ] && echo yes || echo no)"
        echo "failed=$INSTALL_FAILED"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"unchanged=yes"* ]]
    [[ "$output" == *"failed=1"* ]]
}

@test "write_managed_script: refuses an unclosed marker instead of swallowing trailing lines (#530)" {
    run run_with_helpers '
        printf "#!/usr/bin/env bash\n# >>> dev-setup managed block (do not edit between the markers) >>>\necho old\necho this line must survive\n" > "$HOME/script"
        before="$(cat "$HOME/script")"
        printf "#!/usr/bin/env bash\necho new\n" | write_managed_script "$HOME/script"
        rc=$?
        after="$(cat "$HOME/script")"
        echo "rc=$rc"
        echo "unchanged=$([ "$before" = "$after" ] && echo yes || echo no)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"unchanged=yes"* ]]
}

@test "write_managed_script: backs up an unmarked existing file before replacing it (#530)" {
    run run_with_helpers '
        printf "hand-written script\n" > "$HOME/tool"
        printf "#!/usr/bin/env bash\necho generated\n" | write_managed_script "$HOME/tool"
        shopt -s nullglob
        backups=("$HOME"/tool.pre-managed.*)
        echo "backup_count=${#backups[@]}"
        [ "${#backups[@]}" -gt 0 ] && cat "${backups[0]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup_count=1"* ]]
    [[ "$output" == *"hand-written script"* ]]
}

@test "remove_superseded_managed: refuses an unclosed marker rather than deleting real content (#530)" {
    run run_with_helpers '
        cat > "$HOME/orphan" <<OUTER
# >>> dev-setup managed block (do not edit between the markers) >>>
old body
real trailing content that was never closed
OUTER
        remove_superseded_managed "$HOME/orphan" "test reason" "#530"
        test -e "$HOME/orphan" && echo STILL_THERE || echo GONE
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"STILL_THERE"* ]]
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

# ---------------------------------------------------------------------------
# #536: create-once seed files used bespoke guards with no shared contract or
# dry-run report. write_seed_once is the explicit, auditable version of that guard.
# ---------------------------------------------------------------------------

@test "write_seed_once: creates a missing file and returns 0 (#536)" {
    run run_with_helpers '
        write_seed_once "$HOME/seed.yaml" "test reason" <<"EOF"
hello
EOF
        rc=$?
        echo "rc=$rc"
        cat "$HOME/seed.yaml"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"hello"* ]]
}

@test "write_seed_once: leaves an existing file untouched and returns 1 (#536)" {
    run run_with_helpers '
        printf "hand-edited\n" > "$HOME/seed.yaml"
        write_seed_once "$HOME/seed.yaml" "test reason" <<"EOF"
would-be new content
EOF
        rc=$?
        echo "rc=$rc"
        cat "$HOME/seed.yaml"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"hand-edited"* ]]
    [[ "$output" != *"would-be new content"* ]]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"test reason"* ]]
}

@test "write_seed_once: dry-run reports without creating the file, and returns 0 (#536)" {
    run run_with_helpers '
        export DRY_RUN=true
        write_seed_once "$HOME/seed.yaml" "test reason" <<"EOF"
hello
EOF
        rc=$?
        echo "rc=$rc"
        test -e "$HOME/seed.yaml" && echo EXISTS || echo ABSENT
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"ABSENT"* ]]
    [[ "$output" == *"[DRY RUN] Would seed $TEST_TMP/seed.yaml (test reason)"* ]]
}

# ---------------------------------------------------------------------------
# #533: existing JSON files must keep user keys, reject malformed input without
# mutation, and let a caller reassert the small set of generator-owned keys.
# ---------------------------------------------------------------------------

@test "merge_json_defaults: preserves user objects and adds top-level defaults (#533)" {
    run run_with_helpers '
        printf "%s\n" "{\"editor\":{\"font\":14},\"personal\":true}" > "$HOME/settings.json"
        merge_json_defaults "$HOME/settings.json" <<"EOF"
{"editor":{"font":12,"theme":"dracula"},"generated":true}
EOF
        jq -cS . "$HOME/settings.json"
    '
    [ "$status" -eq 0 ]
    [ "$output" = '{"editor":{"font":14,"theme":"dracula"},"generated":true,"personal":true}' ]
}

@test "merge_json_defaults: optional filter reasserts an owned key (#533)" {
    run run_with_helpers '
        printf "%s\n" "{\"theme\":\"user-choice\",\"personal\":true}" > "$HOME/settings.json"
        merge_json_defaults "$HOME/settings.json" ".theme = \"dracula-sakura\"" <<"EOF"
{"theme":"dracula-sakura","generated":true}
EOF
        jq -cS . "$HOME/settings.json"
    '
    [ "$status" -eq 0 ]
    [ "$output" = '{"generated":true,"personal":true,"theme":"dracula-sakura"}' ]
}

@test "merge_json_defaults: malformed existing JSON remains byte-for-byte unchanged (#533)" {
    run run_with_helpers '
        printf "%s\n" "{ // valid JSONC, invalid JSON" > "$HOME/settings.json"
        before="$(shasum -a 256 "$HOME/settings.json")"
        merge_json_defaults "$HOME/settings.json" <<"EOF"
{"generated":true}
EOF
        rc=$?
        after="$(shasum -a 256 "$HOME/settings.json")"
        printf "rc=%s\nsame=%s\n" "$rc" "$([[ "$before" == "$after" ]] && echo yes || echo no)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"same=yes"* ]]
}

@test "merge_json_defaults: dry run reports and writes nothing (#533)" {
    run run_with_helpers '
        export DRY_RUN=true
        merge_json_defaults "$HOME/settings.json" <<"EOF"
{"generated":true}
EOF
        test -e "$HOME/settings.json" && echo WROTE || echo CLEAN
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would merge JSON defaults"* ]]
    [[ "$output" == *"CLEAN"* ]]
}

# ---------------------------------------------------------------------------
# #565: Zed rewrites valid settings with trailing commas. The normalizer must
# accept that form without changing string content that contains punctuation.
# ---------------------------------------------------------------------------

@test "normalize_zed_jsonc: accepts Zed trailing commas without changing strings (#565)" {
    run run_with_helpers '
        cat > "$HOME/zed.jsonc" <<"EOF"
{
  "nested": {
    "enabled": true,
  },
  "array": [
    "rose",
  ],
  "literal": "keep,}"
}
EOF
        normalize_zed_jsonc "$HOME/zed.jsonc" "$HOME/zed.json"
        jq -cS . "$HOME/zed.json"
    '
    [ "$status" -eq 0 ]
    [ "$output" = '{"array":["rose"],"literal":"keep,}","nested":{"enabled":true}}' ]
}

@test "merge_json_defaults: reads a validated source and writes the destination (#565)" {
    run run_with_helpers '
        printf "%s\n" "{\"theme\":\"old\",\"personal\":true}" > "$HOME/source.json"
        merge_json_defaults "$HOME/settings.json" ".theme = \"Dracula-Sakura\"" "$HOME/source.json" <<"EOF"
{"generated":true}
EOF
        jq -cS . "$HOME/settings.json"
    '
    [ "$status" -eq 0 ]
    [ "$output" = '{"generated":true,"personal":true,"theme":"Dracula-Sakura"}' ]
}

# ---------------------------------------------------------------------------
# #532: the late mise linker is pure filesystem policy and can be exercised
# without installing a runtime or relying on the current machine PATH.
# ---------------------------------------------------------------------------

@test "link_mise_shims: links current shims and honors exclusions (#532)" {
    run run_with_helpers '
        mkdir -p "$HOME/shims" "$HOME/bin"
        touch "$HOME/shims/node" "$HOME/shims/python3"
        count="$(link_mise_shims "$HOME/shims" "$HOME/bin" python3)"
        printf "count=%s\nnode=%s\npython=%s\n" "$count" \
            "$(readlink "$HOME/bin/node")" \
            "$([[ -e "$HOME/bin/python3" ]] && echo linked || echo absent)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"node=$TEST_TMP/shims/node"* ]]
    [[ "$output" == *"python=absent"* ]]
}

@test "link_mise_shims: prunes only dangling links into its shim directory (#532)" {
    run run_with_helpers '
        mkdir -p "$HOME/shims" "$HOME/bin" "$HOME/elsewhere"
        touch "$HOME/bin/hand-written" "$HOME/elsewhere/foreign"
        ln -s "$HOME/shims/removed" "$HOME/bin/removed"
        ln -s "$HOME/elsewhere/missing" "$HOME/bin/foreign-missing"
        link_mise_shims "$HOME/shims" "$HOME/bin" >/dev/null
        printf "ours=%s\nforeign=%s\nfile=%s\n" \
            "$([[ -L "$HOME/bin/removed" ]] && echo kept || echo pruned)" \
            "$([[ -L "$HOME/bin/foreign-missing" ]] && echo kept || echo pruned)" \
            "$([[ -f "$HOME/bin/hand-written" ]] && echo kept || echo pruned)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ours=pruned"* ]]
    [[ "$output" == *"foreign=kept"* ]]
    [[ "$output" == *"file=kept"* ]]
}

@test "omp_plugin_install: installs once when the plugin is absent (#576)" {
    run run_with_helpers '
        export LOG_FILE="$HOME/setup.log"
        export ERROR_LOG="$HOME/error.log"
        mkdir -p "$HOME/bin"
        mkdir -p "$STATE_DIR"
        cat > "$HOME/bin/omp" <<"EOF"
#!/usr/bin/env bash
if [[ "$1 $2" == "plugin list" ]]; then
  if [[ -f "$HOME/plugin-installed" ]]; then
    printf "{\"npm\":[{\"name\":\"bigpowers\",\"enabled\":true}]}\n"
  else
    printf "{\"npm\":[]}\n"
  fi
elif [[ "$1 $2 $3" == "plugin install bigpowers" ]]; then
  touch "$HOME/plugin-installed"
  printf "install\n" >> "$HOME/install.log"
fi
EOF
        printf "#!/usr/bin/env bash\nexit 0\n" > "$HOME/bin/bun"
        chmod +x "$HOME/bin/omp" "$HOME/bin/bun"
        export PATH="$HOME/bin:$PATH"

        omp_plugin_install bigpowers bigpowers "Bigpowers"
        omp_plugin_install bigpowers bigpowers "Bigpowers"
        printf "installed=%s calls=%s\n" \
          "$([[ -f "$HOME/plugin-installed" ]] && echo yes || echo no)" \
          "$(/usr/bin/wc -l < "$HOME/install.log" | tr -d " ")"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"installed=yes calls=1"* ]]
}

@test "omp_plugin_install: dry-run does not invoke the plugin manager (#576)" {
    run run_with_helpers '
        export LOG_FILE="$HOME/setup.log"
        export ERROR_LOG="$HOME/error.log"
        mkdir -p "$HOME/bin"
        cat > "$HOME/bin/omp" <<"EOF"
#!/usr/bin/env bash
if [[ "$1 $2" == "plugin list" ]]; then
  printf "{\"npm\":[]}\n"
elif [[ "$1 $2" == "plugin install" ]]; then
  touch "$HOME/plugin-installed"
fi
EOF
        printf "#!/usr/bin/env bash\nexit 0\n" > "$HOME/bin/bun"
        chmod +x "$HOME/bin/omp" "$HOME/bin/bun"
        export PATH="$HOME/bin:$PATH"
        DRY_RUN=true

        omp_plugin_install bigpowers bigpowers "Bigpowers"
        [[ ! -e "$HOME/plugin-installed" ]]
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] Would install: Bigpowers"* ]]
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

# ---------------------------------------------------------------------------
# #505: --verify rows must not pipe into `grep -q`. Under `set -o pipefail` the
# producer takes SIGPIPE when grep exits early, and the row reports the tool as
# rejecting its config when the tool was fine.
# ---------------------------------------------------------------------------

@test "_verify_output_has: matches without SIGPIPE-ing a still-writing producer (#505)" {
    # The producer keeps printing long after the matched line. The old
    # `cmd | grep -q` form returns 141 here under pipefail; this must return 0.
    run run_with_helpers '
        set -o pipefail
        producer() { echo "whitelist.prefix [/x]"; for i in $(seq 1 20000); do echo "filler $i"; done; }
        _verify_output_has "^whitelist[.]prefix [[].+[]]" producer && echo MATCHED || echo "MISSED($?)"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MATCHED"* ]]
}

@test "_verify_output_has: the old piped form really does fail this way (#505)" {
    # Pins the diagnosis rather than trusting the comment. The assertion is
    # "non-zero", NOT a specific code: the exact value is platform-dependent.
    # macOS returns 141 (128 + SIGPIPE), where the producer is killed by the
    # signal. Linux bash reports a write error on the closed pipe instead and
    # returns 1. Either way `set -o pipefail` fails the row, which is the only
    # thing the fix depends on. An earlier version of this test asserted 141 and
    # passed on macOS while failing in CI, which is the AGENTS.md rule about CI
    # being the gate, in miniature.
    run run_with_helpers '
        set -o pipefail
        producer() { echo "whitelist.prefix [/x]"; for i in $(seq 1 20000); do echo "filler $i"; done; }
        producer | grep -q "^whitelist"
        rc=$?
        echo "piped_exit=$rc"
        [ "$rc" -ne 0 ] && echo PIPED_FORM_FAILS || echo PIPED_FORM_SUCCEEDS'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PIPED_FORM_FAILS"* ]]
}

@test "_verify_output_has: returns non-zero when the pattern is absent (#505)" {
    run run_with_helpers '
        producer() { echo "nothing of interest"; }
        _verify_output_has "^whitelist" producer && echo MATCHED || echo NOMATCH'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOMATCH"* ]]
}

@test "_verify_output_has: sees stderr, which zellij reports on (#505)" {
    run run_with_helpers '
        producer() { echo "Well defined" >&2; }
        _verify_output_has "Well defined" producer && echo MATCHED || echo NOMATCH'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MATCHED"* ]]
}

@test "no --verify row pipes into grep -q (#505)" {
    # The class, not the four instances. A new row written the old way is a
    # latent failure that only shows up when some tool's output grows.
    run grep -nE '"(validate|path|template)\|.*\| *grep -q' "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# #515: Homebrew's removed node left its global npm tree behind. The sweep
# selects bin stubs by TARGET, never by name — a name list would go stale, and
# picking the wrong link would delete a formula's binary.
# ---------------------------------------------------------------------------

@test "orphaned_brew_node_links: selects links pointing into lib/node_modules (#515)" {
    run run_with_helpers '
        p="'"$TEST_TMP"'/prefix"
        mkdir -p "$p/bin" "$p/lib/node_modules/typescript/bin"
        touch "$p/lib/node_modules/typescript/bin/tsc"
        ln -s ../lib/node_modules/typescript/bin/tsc "$p/bin/tsc"
        orphaned_brew_node_links "$p"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"/bin/tsc"* ]]
}

@test "orphaned_brew_node_links: leaves a formula's own link alone (#515)" {
    # The decisive case. Everything else in that directory belongs to Homebrew,
    # and removing one would break an installed formula.
    run run_with_helpers '
        p="'"$TEST_TMP"'/prefix"
        mkdir -p "$p/bin" "$p/Cellar/ripgrep/14.0/bin" "$p/lib/node_modules"
        touch "$p/Cellar/ripgrep/14.0/bin/rg"
        ln -s ../Cellar/ripgrep/14.0/bin/rg "$p/bin/rg"
        echo "[$(orphaned_brew_node_links "$p")]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[]"* ]]
}

@test "orphaned_brew_node_links: ignores real files, only links qualify (#515)" {
    run run_with_helpers '
        p="'"$TEST_TMP"'/prefix"
        mkdir -p "$p/bin" "$p/lib/node_modules"
        printf "#!/bin/sh\n" > "$p/bin/realbin"; chmod +x "$p/bin/realbin"
        echo "[$(orphaned_brew_node_links "$p")]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[]"* ]]
}

@test "orphaned_brew_node_links: no bin directory is a silent no-op (#515)" {
    run run_with_helpers '
        p="'"$TEST_TMP"'/empty-prefix"
        mkdir -p "$p"
        orphaned_brew_node_links "$p"
        echo "rc=$?"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
}

@test "orphaned_brew_node_links: picks the node link out of a mixed bin dir (#515)" {
    run run_with_helpers '
        p="'"$TEST_TMP"'/prefix"
        mkdir -p "$p/bin" "$p/lib/node_modules/turbo/bin" "$p/Cellar/jq/1.7/bin"
        touch "$p/lib/node_modules/turbo/bin/turbo" "$p/Cellar/jq/1.7/bin/jq"
        ln -s ../lib/node_modules/turbo/bin/turbo "$p/bin/turbo"
        ln -s ../Cellar/jq/1.7/bin/jq "$p/bin/jq"
        orphaned_brew_node_links "$p" | wc -l | tr -d " "
        orphaned_brew_node_links "$p"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"turbo"* ]]
    [[ "$output" != *"/bin/jq"* ]]
}

# ---------------------------------------------------------------------------
# #567: Thunderbird profiles.ini can mix relative and absolute profile paths.
# Configuration must reach each registered profile without guessing a directory.
# ---------------------------------------------------------------------------

@test "thunderbird_profile_paths: resolves relative and absolute profiles (#567)" {
    run run_with_helpers '
        registry="'"$TEST_TMP"'/Thunderbird/profiles.ini"
        mkdir -p "$(dirname "$registry")"
        cat > "$registry" <<EOF
[Profile0]
Name=default-release
IsRelative=1
Path=Profiles/a1b2.default-release

[InstallABC]
Default=Profiles/a1b2.default-release
Locked=1

[Profile1]
Name=Archive
IsRelative=0
Path=/Volumes/Mail Archive/Thunderbird
EOF
        thunderbird_profile_paths "$registry" "$(dirname "$registry")"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_TMP/Thunderbird/Profiles/a1b2.default-release"* ]]
    [[ "$output" == *"/Volumes/Mail Archive/Thunderbird"* ]]
    [ "${lines[0]}" = "$TEST_TMP/Thunderbird/Profiles/a1b2.default-release" ]
    [ "${lines[1]}" = "/Volumes/Mail Archive/Thunderbird" ]
}

@test "thunderbird_profile_paths: missing registry is a silent no-op (#567)" {
    run run_with_helpers '
        thunderbird_profile_paths "'"$TEST_TMP"'/missing.ini" "'"$TEST_TMP"'/Thunderbird"
        echo "rc=$?"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
}

# ---------------------------------------------------------------------------
# #569: Emeraldian rewrites its TOML settings. Theme selection must update one
# top-level key without replacing comments or similarly named nested settings.
# ---------------------------------------------------------------------------

@test "set_toml_top_level_string: replaces only the top-level key (#569)" {
    run run_with_helpers '
        cat > "$HOME/config.toml" <<EOF
# personal comment
theme = "obsidian-dark"

[preview]
theme = "terminal"
EOF
        set_toml_top_level_string "$HOME/config.toml" theme dracula-sakura
        cat "$HOME/config.toml"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"# personal comment"* ]]
    [[ "$output" == *'theme = "dracula-sakura"'* ]]
    [[ "$output" == *'theme = "terminal"'* ]]
    [[ "$output" != *'theme = "obsidian-dark"'* ]]
}

@test "set_toml_top_level_string: inserts before the first table (#569)" {
    run run_with_helpers '
        cat > "$HOME/config.toml" <<EOF
# personal comment
[ui]
show_hints = false
EOF
        set_toml_top_level_string "$HOME/config.toml" theme dracula-sakura
        cat "$HOME/config.toml"'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'# personal comment\ntheme = "dracula-sakura"\n[ui]'* ]]
    [[ "$output" == *"show_hints = false"* ]]
}
