#!/usr/bin/env bats

setup() {
    export SETUP_SCRIPT="$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh"
    TEST_TMP_DIR=""
}

teardown() {
    [[ -z "$TEST_TMP_DIR" ]] || /bin/rm -rf "$TEST_TMP_DIR"
}
@test "active package list omits retired SurgeDM (#586)" {
    run bash "$SETUP_SCRIPT" --list
    [ "$status" -eq 0 ]
    [[ $'\n'"$output"$'\n' != *$'\n  surge\n'* ]]
}

@test "cleanup retires only SurgeDM and preserves the core Surge cask (#586)" {
    test_tmp="$(mktemp -d)"
    TEST_TMP_DIR="$test_tmp"
    stub="$test_tmp/bin"
    mkdir -p "$stub" "$test_tmp/home/Library/Application Support/surge"
    touch "$test_tmp/surgedm-installed"

    cat > "$stub/brew" <<'BREW'
#!/usr/bin/env bash
case "$*" in
    "list --cask surgedm/tap/surge")
        [[ -e "$TEST_TMP/surgedm-installed" ]]
        ;;
    "uninstall --cask surge")
        printf '%s\n' "$*" >> "$TEST_TMP/operations"
        rm "$TEST_TMP/surgedm-installed"
        ;;
    "uninstall --cask surgedm/tap/surge")
        # Homebrew accepts the qualified name for lookup but removes the
        # installed cask by its short token.
        exit 1
        ;;
    "tap")
        printf '%s\n' "surgedm/tap"
        ;;
    "list --full-name")
        printf '%s\n' "homebrew/cask/surge"
        ;;
    "untap surgedm/tap")
        printf '%s\n' "$*" >> "$TEST_TMP/operations"
        ;;
    "untrust --tap surgedm/tap")
        printf 'untrust %s %s\n' "${XDG_CONFIG_HOME-unset}" "$*" >> "$TEST_TMP/operations"
        ;;
    "autoremove --dry-run"|"autoremove"|"cleanup")
        ;;
    *)
        exit 1
        ;;
esac
BREW

    cat > "$stub/surge" <<'SURGE'
#!/usr/bin/env bash
printf 'service %s\n' "$*" >> "$TEST_TMP/operations"
rm "$0"
SURGE

    for command in npm uv cargo mas; do
        printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/$command"
    done
    chmod +x "$stub"/*

    export TEST_TMP="$test_tmp"
    export HOME="$test_tmp/home"
    export PATH="$stub:$PATH"
    run bash "$SETUP_SCRIPT" --cleanup --no-prompt
    [ "$status" -eq 0 ]

    run cat "$test_tmp/operations"
    [ "$status" -eq 0 ]
    [[ "$output" == *"service service uninstall"* ]]
    [[ "$output" == *"uninstall --cask surge"* ]]
    [[ "$output" != *"uninstall --cask surgedm/tap/surge"* ]]
    [[ "$output" != *"trash "* ]]
    [[ "$output" == *"untrust $HOME/.config untrust --tap surgedm/tap"* ]]
    [[ "$output" == *"untrust unset untrust --tap surgedm/tap"* ]]
    [ -d "$HOME/Library/Application Support/surge" ]

}
