#!/usr/bin/env bats
# Integration coverage for the generated global Git hook chain (#531).

setup() {
    TEST_TMP="$(mktemp -d)"
    export HOOKS_DIR="$TEST_TMP/global-hooks"
    export REPO="$TEST_TMP/repo"
    mkdir -p "$HOOKS_DIR" "$REPO"
    awk "/<<'HOOK_CHAIN_LIB'/{f=1;next} /^HOOK_CHAIN_LIB$/{f=0} f" \
        "$BATS_TEST_DIRNAME/../scripts/setup-dev-tools-mac.sh" > "$HOOKS_DIR/dev-setup-chain.sh"
    git -C "$REPO" init -q
    git -C "$REPO" config user.name Test
    git -C "$REPO" config user.email test@example.invalid
}

teardown() {
    rm -rf "$TEST_TMP"
}

run_chain() {
    local hook="$1"
    shift
    bash -c '. "$1/dev-setup-chain.sh"; cd "$2"; run_hook_chain "$3" "${@:4}"' \
        _ "$HOOKS_DIR" "$REPO" "$hook" "$@"
}

make_hook() {
    local path="$1" body="$2"
    mkdir -p "$(dirname "$path")"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
    chmod +x "$path"
}

@test "hook chain runs the repository hook before preserved hooks (#531)" {
    make_hook "$REPO/.git/hooks/pre-commit" 'echo repo >> "$ORDER"'
    make_hook "$HOOKS_DIR/pre-commit.d/10-third-party" 'echo third-party >> "$ORDER"'
    export ORDER="$TEST_TMP/order"

    run run_chain pre-commit

    [ "$status" -eq 0 ]
    [ "$(cat "$ORDER")" = $'repo\nthird-party' ]
}

@test "hook chain stops at the first nonzero hook status (#531)" {
    make_hook "$REPO/.git/hooks/pre-commit" 'exit 23'
    make_hook "$HOOKS_DIR/pre-commit.d/10-third-party" 'echo ran > "$SHOULD_NOT_EXIST"'
    export SHOULD_NOT_EXIST="$TEST_TMP/ran"

    run run_chain pre-commit

    [ "$status" -eq 23 ]
    [ ! -e "$SHOULD_NOT_EXIST" ]
}

@test "pre-push replays identical stdin to every hook (#531)" {
    make_hook "$REPO/.git/hooks/pre-push" 'cat > "$REPO_STDIN"'
    make_hook "$HOOKS_DIR/pre-push.d/10-third-party" 'cat > "$THIRD_STDIN"'
    export REPO_STDIN="$TEST_TMP/repo.stdin"
    export THIRD_STDIN="$TEST_TMP/third.stdin"

    run bash -c '. "$1/dev-setup-chain.sh"; printf "local localsha remote remotesha\n" | (cd "$2" && run_hook_chain pre-push origin url)' \
        _ "$HOOKS_DIR" "$REPO"

    [ "$status" -eq 0 ]
    cmp -s "$REPO_STDIN" "$THIRD_STDIN"
    [ "$(cat "$REPO_STDIN")" = "local localsha remote remotesha" ]
}

@test "linked worktree uses the common repository hook without recursion (#531)" {
    git -C "$REPO" commit --allow-empty -qm initial
    git -C "$REPO" worktree add -q "$TEST_TMP/worktree"
    make_hook "$REPO/.git/hooks/post-commit" 'echo common > "$COMMON_RAN"'
    export COMMON_RAN="$TEST_TMP/common-ran"

    run bash -c '. "$1/dev-setup-chain.sh"; cd "$2"; run_hook_chain post-commit' \
        _ "$HOOKS_DIR" "$TEST_TMP/worktree"

    [ "$status" -eq 0 ]
    [ "$(cat "$COMMON_RAN")" = common ]
}

@test "LFS guard refuses a push without a repository hook and honors its bypass (#531)" {
    mkdir -p "$TEST_TMP/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMP/bin/git-lfs"
    chmod +x "$TEST_TMP/bin/git-lfs"
    export REAL_GIT="$(command -v git)"
    cat > "$TEST_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-files" && "$2" == ":(attr:filter=lfs)" ]]; then
    printf 'sample.bin\n'
    exit 0
fi
exec "$REAL_GIT" "$@"
EOF
    chmod +x "$TEST_TMP/bin/git"
    printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$REPO/.gitattributes"
    printf 'pointer\n' > "$REPO/sample.bin"
    git -C "$REPO" add .gitattributes sample.bin
    git -C "$REPO" commit -qm lfs

    run env PATH="$TEST_TMP/bin:$PATH" bash -c '. "$1/dev-setup-chain.sh"; cd "$2"; run_hook_chain pre-push' \
        _ "$HOOKS_DIR" "$REPO"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tracks files with Git LFS"* ]]

    git -C "$REPO" config dev-setup.lfsguard false
    run env PATH="$TEST_TMP/bin:$PATH" bash -c '. "$1/dev-setup-chain.sh"; cd "$2"; run_hook_chain pre-push' \
        _ "$HOOKS_DIR" "$REPO"
    [ "$status" -eq 0 ]
}
