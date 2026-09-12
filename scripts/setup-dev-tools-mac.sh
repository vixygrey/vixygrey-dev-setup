#!/usr/bin/env bash

# Require bash 4+ (this script uses associative arrays). macOS ships bash 3.2 as
# /bin/bash, so on a clean Mac re-exec under a newer bash if one is installed;
# otherwise tell the user how to get one. (This guard is itself 3.2-compatible.)
if ((BASH_VERSINFO[0] < 4)); then
    _path_bash="$(command -v bash 2>/dev/null || true)"
    _brew_prefix="$(brew --prefix 2>/dev/null || true)"
    for _newbash in "$_path_bash" "$_brew_prefix/bin/bash" /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
        [[ -n "$_newbash" && -x "$_newbash" ]] || continue
        [[ "$_newbash" != "$BASH" ]] || continue
        "$_newbash" -c '(( BASH_VERSINFO[0] >= 4 ))' >/dev/null 2>&1 || continue
        # shellcheck disable=SC2093
        exec "$_newbash" "$0" "$@"
    done
    echo "This setup script needs bash 4+ (macOS ships bash 3.2)." >&2
    if command -v brew >/dev/null 2>&1; then
        echo "Install a newer bash and re-run:  brew install bash" >&2
    else
        echo "Install Homebrew first, then install a newer bash:  brew install bash" >&2
        echo "Or run the script with any bash 4+ already on your machine." >&2
    fi
    exit 1
fi

# =============================================================================
# Development Environment Setup Script (macOS)
# =============================================================================
# Version:  see SCRIPT_VERSION below (source of truth)
# Platform: macOS (Apple Silicon + Intel), requires bash 4+
# Run:      chmod +x setup-dev-tools-mac.sh && ./setup-dev-tools-mac.sh
# Flags:    --dry-run, --no-prompt, --list, --list-categories, --only <cats>,
#           --skip <cats>, --interactive/-i, --resume, --cleanup, --verify,
#           --update-brew, --doctor, --uninstall, --version, --help
# =============================================================================

SCRIPT_VERSION="8.2.0"
SCRIPT_START=$(date +%s)
PYTHON_VERSION="3.12"
# Absolute directory of this script. Used to resolve bundled assets both from the
# repo layout (scripts/setup-dev-tools-mac.sh -> ../assets/...) and the release zip
# layout (setup-dev-tools-mac.sh -> ./assets/...). Read-only; no side effects.
SETUP_SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Where `go install` writes binaries. The generated login shell adds
# $GOPATH/bin (== ~/.local/share/go/bin) to PATH, but `go install` defaults to
# ~/go/bin unless GOBIN is set — so pin GOBIN here to the dir the shell expects,
# and put it on THIS run's PATH so freshly-installed Go tools resolve immediately.
export GOBIN="$HOME/.local/share/go/bin"
export PATH="$GOBIN:$PATH"
# The directory itself is created later, once --dry-run has been parsed — see the
# ensure_dir call before preflight. Creating it here ran before the flags were read,
# so a dry run made the directory unconditionally (#380). The export and the PATH
# entry are free; only the mkdir is a change to the machine.

# -- Colors & Formatting ------------------------------------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# -- Logging ------------------------------------------------------------------
LOG_DIR="$HOME/.local/share/dev-setup"
# #375: skip directory creation under SETUP_LIB_ONLY — the helper layer has no
# logs and creating the dir is itself a side effect. The variables below are still
# set so any helper that does try to log does not fail with an unbound variable.
if [[ -z "${SETUP_LIB_ONLY:-}" ]]; then
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
    ERROR_LOG="$LOG_DIR/setup-errors-$(date +%Y%m%d-%H%M%S).log"
fi

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }

info() {
    printf '\033[2K\r'
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

# success() means "a tool was INSTALLED". It used to mean three different things —
# a tool installed, a config file written, and a preflight check that passed — all
# counted into one `Installed:` number, which is why a run that installed nothing
# still reported 71 (#381). The other two now have their own functions below.
success() {
    printf '\033[2K\r'
    echo -e "${GREEN}[  OK]${NC} $1"
    log "OK: $1"
    ((INSTALL_SUCCESS++)) || true
}

# configured() — configuration was applied. Counts into `Configured:`, separately from
# installs, and is SILENT under --dry-run.
#
# "Configuration" includes generated files and macOS defaults. These actions use
# `defaults write` and `networksetup`, but still belong in the Configured count (#500).
#
# Silent rather than reworded: these messages are past-tense summaries ("delta
# configured as git pager"), and no prefix makes a past-tense sentence honest about
# something that did not happen. write_managed already narrates the file it would
# create or refresh, so the preview loses nothing by dropping the claim — it gets
# shorter and stops asserting 65 completed actions that never occurred.
configured() {
    [[ "$DRY_RUN" == "true" ]] && { log "[DRY RUN] would report: $1"; return 0; }
    printf '\033[2K\r'
    echo -e "${GREEN}[  OK]${NC} $1"
    log "CONFIGURED: $1"
    ((INSTALL_CONFIGURED++)) || true
}

# checked() — a preflight check passed. Green, because it is good news, but counted
# nowhere: "Disk space: 291GB free" is not something that was installed, and it was
# padding the install count on every run.
checked() {
    printf '\033[2K\r'
    echo -e "${GREEN}[  OK]${NC} $1"
    log "CHECK: $1"
}

warn() {
    printf '\033[2K\r'
    echo -e "${YELLOW}[SKIP]${NC} $1"
    log "SKIP: $1"
    ((INSTALL_SKIPPED++)) || true
}

error() {
    printf '\033[2K\r'
    echo -e "${RED}[ ERR]${NC} $1"
    log "ERROR: $1"
    echo "[$(date +%H:%M:%S)] $1" >> "$ERROR_LOG"
    ((INSTALL_FAILED++)) || true
    FAILED_ITEMS+=("$1")
}

banner() {
    local title="$1"
    timing_phase_end
    TIMING_PHASE="$title"
    TIMING_PHASE_START=$SECONDS
    ((PHASE_COUNTS["$title"]++)) || true
    printf '\033[2K\r'
    echo ""
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}${BOLD}  $title${NC}"
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "=== $title ==="
}


# Runtime profiling is coarse by design. Bash 4 guarantees `SECONDS`, while
# nanosecond timestamps are not portable across the supported macOS Bash versions.
declare -A PHASE_SECONDS PHASE_COUNTS HELPER_SECONDS HELPER_CALLS
TIMING_PHASE=""
TIMING_PHASE_START=$SECONDS
timing_phase_end() {
    [[ -n "$TIMING_PHASE" ]] || return 0
    (( PHASE_SECONDS["$TIMING_PHASE"] += SECONDS - TIMING_PHASE_START )) || true
    TIMING_PHASE_START=$SECONDS
}
_time_install_helper() {
    local kind="$1"; shift
    local started=$SECONDS rc
    "$@"; rc=$?
    (( HELPER_CALLS["$kind"]++ )) || true
    (( HELPER_SECONDS["$kind"] += SECONDS - started )) || true
    return "$rc"
}

timing_report() {
    timing_phase_end
    echo ""
    echo -e "${BLUE}${BOLD}Runtime profile:${NC}"
    echo "  Phases (seconds):"
    for _timing_key in "${!PHASE_SECONDS[@]}"; do
        printf '    %-28s %s\n' "$_timing_key" "${PHASE_SECONDS[$_timing_key]}"
    done
    echo "  Install helpers (calls, seconds):"
    for _timing_key in "${!HELPER_SECONDS[@]}"; do
        printf '    %-28s %s, %s\n' "$_timing_key" "${HELPER_CALLS[$_timing_key]}" "${HELPER_SECONDS[$_timing_key]}"
    done
    unset _timing_key
}

# -- Counters -----------------------------------------------------------------
INSTALL_SUCCESS=0
INSTALL_CONFIGURED=0
INSTALL_SKIPPED=0
INSTALL_FAILED=0
INSTALL_CURRENT=0
FAILED_ITEMS=()

# Managed-block bookkeeping (see write_managed): 'repaired<TAB>path' for files where
# a duplicate pre-managed copy of our own block was removed, 'outside<TAB>path' for
# files that still carry content outside the markers. Reported once at the end.
# A FILE rather than an array on purpose — write_managed is normally fed by a heredoc,
# but a caller feeding it through a PIPE runs it in a subshell, where array appends are
# discarded while the on-disk repair still happens. That is exactly the silent-no-op
# shape this script keeps getting bitten by, so the state has to outlive a subshell.
MANAGED_STATE="$(mktemp)"
managed_note() { printf '%s\t%s\n' "$1" "$2" >> "$MANAGED_STATE"; }
managed_list() { [[ -s "$MANAGED_STATE" ]] && awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$MANAGED_STATE" | sort -u; }

# Dynamic total — count all install calls in this script so the progress bar stays accurate
# when tools are added or removed. A new install helper MUST be added to this pattern,
# or its calls run uncounted and the progress bar overshoots 100%.
# Count all install calls plus standalone progress calls for an accurate progress bar.
# Note: `grep -c` prints "0" AND exits 1 on zero matches, so `|| echo 0` would append
# a SECOND "0" ("0\n0") and break the arithmetic. Use `|| true` plus a default instead.
_INSTALL_CALLS=$(grep -cE '^\s*(brew_install|brew_cask_install|npm_global_install|kiro_extension_install|go_install|uv_tool_install|cargo_install|rustup_component_install) ' "$0" 2>/dev/null || true)
_PROGRESS_CALLS=$(grep -cE '^\s*progress\s*$' "$0" 2>/dev/null || true)
INSTALL_TOTAL=$(( ${_INSTALL_CALLS:-0} + ${_PROGRESS_CALLS:-0} ))
[[ "$INSTALL_TOTAL" -eq 0 ]] && INSTALL_TOTAL=200

progress() {
    ((INSTALL_CURRENT++)) || true
    local pct=$((INSTALL_CURRENT * 100 / INSTALL_TOTAL))
    [[ "$pct" -gt 100 ]] && pct=100
    local bar_len=$((pct / 2))
    local bar
    bar=$(printf '█%.0s' $(seq 1 $bar_len 2>/dev/null) 2>/dev/null || echo "")
    local spaces
    spaces=$(printf ' %.0s' $(seq 1 $((50 - bar_len)) 2>/dev/null) 2>/dev/null || echo "")
    # In-place progress bar — stays on current line, overwritten by next status message
    printf '\033[2K\r%s[%s%s%s%s] %d%% (%d/%d)%s' "$DIM" "$CYAN" "$bar" "$DIM" "$spaces" "$pct" "$INSTALL_CURRENT" "$INSTALL_TOTAL" "$NC"
}

# -- State flags --------------------------------------------------------------
DRY_RUN=false
RESUME=false
UNINSTALL=false
CLEANUP=false
FORCE_BREW_UPDATE=false
FORCE_BREW_DOCTOR=false
INTERACTIVE=false
NO_PROMPT=false
BREW_INSTALLED_THIS_RUN=false
BREW_DOCTOR_RAN=false
SKIP_CATEGORIES=()
ONLY_CATEGORIES=()
MCP_INSPECTOR_NODE_READY=true
PRIVILEGED_WORK_SKIPPED=false

# prompt_ask <prompt> <answer-when-no-prompt>   (answer on stdout)
# Ask, or take the given answer without blocking when --no-prompt is set. Every
# prompt this script owns goes through here: a run launched where nobody is
# watching (an editor's "run in terminal" button, a detached pane, a scheduled
# job) otherwise parks on a prompt forever (#265).
# Usable in a command substitution because `read -p` writes its prompt to stderr,
# so the prompt still reaches the terminal while only the answer is captured.
prompt_ask() {
    local __prompt="$1" __auto="$2" __reply
    if [[ "$NO_PROMPT" == "true" ]]; then
        printf '%s' "$__auto"
        log "--no-prompt: answered '$__auto' to: $__prompt"
        return 0
    fi
    read -r -p "$__prompt" __reply
    printf '%s' "$__reply"
}

# -- State file for --resume --------------------------------------------------
STATE_DIR="$HOME/.local/share/dev-setup"
STATE_FILE="$STATE_DIR/completed-items.txt"
BREW_UPDATE_INTERVAL=86400
BREW_UPDATE_STATE="$STATE_DIR/homebrew-updated-at"

_brew_update_age() {
    local updated now
    updated="$(stat -f %m "$BREW_UPDATE_STATE" 2>/dev/null || true)"
    [[ "$updated" =~ ^[0-9]+$ ]] || updated="$(stat -c %Y "$BREW_UPDATE_STATE" 2>/dev/null || true)"
    [[ "$updated" =~ ^[0-9]+$ ]] || return 1
    now="$(date +%s)"
    printf '%s\n' "$((now - updated))"
}

brew_update_if_due() {
    local age
    if [[ "$FORCE_BREW_UPDATE" == "true" ]] || [[ ! -e "$BREW_UPDATE_STATE" ]]; then
        age="stale"
    else
        age="$(_brew_update_age || echo stale)"
    fi
    if [[ "$age" != "stale" ]] && (( age < BREW_UPDATE_INTERVAL )); then
        info "Skipping Homebrew update — metadata refreshed ${age}s ago"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: brew update"
    elif brew update; then
        mkdir -p "$STATE_DIR"
        touch "$BREW_UPDATE_STATE"
        success "Homebrew metadata updated"
    else
        warn "Homebrew metadata update failed — continuing with the existing index"
    fi
}

brew_doctor_needed() {
    [[ "$DRY_RUN" != "true" ]] || return 1
    [[ "$BREW_DOCTOR_RAN" != "true" ]] || return 1
    [[ "$FORCE_BREW_DOCTOR" == "true" ]] \
        || [[ "$BREW_INSTALLED_THIS_RUN" == "true" ]] \
        || (( INSTALL_FAILED > 0 ))
}

run_brew_doctor() {
    BREW_DOCTOR_RAN=true
    info "Running brew doctor..."
    if brew doctor >> "$LOG_FILE" 2>&1; then
        checked "Homebrew healthy (brew doctor passed)"
    else
        warn "brew doctor found issues (may cause install failures — see $LOG_FILE)"
    fi
}

mark_done() {
    # A preview must not poison a later `--resume` by recording work it only named.
    # CI's dry-run job deliberately permits the log/state dir itself to exist, so this
    # class needs the guard here rather than another path denylist entry (#390).
    [[ "$DRY_RUN" == "true" ]] && return 0
    echo "$1" >> "$STATE_FILE"
}

is_done() {
    [[ "$RESUME" == "true" ]] && grep -qxF "$1" "$STATE_FILE" 2>/dev/null
}

# -- Applied-once state for privileged settings that cannot be read back ------
# Deliberately NOT mark_done/is_done. That pair is the --resume mechanism: the
# state file is truncated on every non-resume run, and is_done answers false
# unless --resume was passed. Both are correct for resume and wrong here, where
# the question is "did any previous run ever apply this" (#502).
#
# Only for settings whose state root owns and does not expose. `systemsetup
# -getusingnetworktime` needs administrator access to READ, so detecting it costs
# the password we are trying to avoid asking for.
#
# The trade: turn one of these off by hand and the run will not notice, because
# the marker still says applied. Delete the line from this file to force a
# re-apply. The alternative is a password prompt on every run forever, which is
# the defect this replaces.
PRIV_STATE_FILE="$STATE_DIR/privileged-applied.txt"

priv_mark() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    mkdir -p "$STATE_DIR"
    priv_done "$1" || echo "$1" >> "$PRIV_STATE_FILE"
}

priv_done() {
    grep -qxF "$1" "$PRIV_STATE_FILE" 2>/dev/null
}

# -- Lockfile (prevent concurrent runs) ---------------------------------------
LOCKFILE="$STATE_DIR/setup.lock"

acquire_lock() {
    mkdir -p "$STATE_DIR"
    if mkdir "$LOCKFILE" 2>/dev/null; then
        echo $$ > "$LOCKFILE/pid"
        return 0
    fi
    # Check for stale lock
    local old_pid
    old_pid=$(cat "$LOCKFILE/pid" 2>/dev/null)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        # Say enough to tell a working run from one parked on a prompt. "Another
        # instance is running" alone reads as "work in progress" even when that
        # instance finished hours ago and is only waiting on a question (#265).
        local age last_log
        age=$(ps -o etime= -p "$old_pid" 2>/dev/null | tr -d ' ')
        error "Another instance is running (PID: $old_pid${age:+, started ${age} ago})"
        # Newest log that is NOT this run's own — that is the other instance's.
        # Log names are timestamped (setup-YYYYMMDD-HHMMSS.log), so glob order is
        # chronological and the last match is the newest.
        local f
        for f in "$STATE_DIR"/setup-2*.log; do
            [[ -f "$f" ]] || continue
            [[ "$f" == "${LOG_FILE:-}" ]] && continue   # skip this run's own log
            last_log="$f"
        done
        if [[ -n "$last_log" ]]; then
            echo "  Its last activity: $(date -r "$last_log" '+%Y-%m-%d %H:%M:%S')"
            echo "  Tail it with: tail -5 \"$last_log\""
        fi
        echo "  If that run has finished and is only waiting at a prompt, end it: kill $old_pid"
        exit 1
    fi
    warn "Removing stale lock (PID: ${old_pid:-unknown})"
    rm -rf "$LOCKFILE"
    mkdir "$LOCKFILE" 2>/dev/null || { error "Failed to acquire lock"; exit 1; }
    echo $$ > "$LOCKFILE/pid"
}

release_lock() {
    rm -rf "$LOCKFILE"
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    [[ -n "${MANAGED_STATE:-}" ]] && rm -f "$MANAGED_STATE"
}

SUDO_KEEPALIVE_PID=""
trap release_lock EXIT

ALL_CATEGORIES=(
    prerequisites
    core
    git
    aws
    iac
    security
    replacements
    data-processing
    code-quality
    perf-testing
    dev-servers
    terminal-productivity
    k8s-github
    database
    containers
    api
    networking
    dx
    docs
    mac-system
    mac-productivity
    mac-browsers
    mac-media
    mac-cloud
    dracula
    configs
    filesystem
    macos-defaults
    shell
)

# Category descriptions for interactive picker (must match ALL_CATEGORIES order)
declare -A CATEGORY_DESC=(
    [prerequisites]="Xcode CLI Tools, Homebrew, GNU coreutils"
    [core]="mise (Node, Python), Go, Rust, uv, pnpm, PyYAML helper venv"
    [git]="Git, GitHub CLI, delta, lazygit, pre-commit framework (hooks + config: configs)"
    [aws]="AWS CLI, CDK, SAM, Granted, cfn-lint, e1s/e2c/stu/claws (TUIs), s5cmd, steampipe, dynein, iamlive"
    [iac]="terraform-docs, checkov"
    [security]="gitleaks, trivy, semgrep, Objective-See, Bitwarden, chamber"
    [replacements]="eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, Yazi, fx, etc."
    [data-processing]="yq, csvkit, jc, jqp, pandoc, ImageMagick"
    [code-quality]="shellcheck, shfmt, actionlint, act, hadolint, ruff, prettier"
    [perf-testing]="Hurl"
    [dev-servers]="ngrok, miniserve"
    [terminal-productivity]="Caligula, Nerdlog, Emeraldian, Watchtower, leaf, topgrade, fastfetch, mprocs, Broot, qalc, lazyssh/rsync/npm, cheznav, eilmeldung, concord, cfait"
    [k8s-github]="gh-dash"
    [database]="duckdb, harlequin, usql, dbmate"
    [containers]="Docker Desktop, lazydocker, dive"
    [api]="Posting"
    [networking]="nmap, trippy"
    [dx]="fzf, starship, atuin, micro, Kiro, Kitty, zellij, omp, language servers"
    [docs]="d2"
    [mac-system]="LuLu, Mullvad VPN, mullvad CLI, mullvad-tui"
    [mac-productivity]="Draw.io, Obsidian, Herald, LibreOffice, Vulkan llama.cpp"
    [mac-browsers]="Firefox, Carbonyl, Chawan, monolith"
    [mac-media]="mpv, oxipng, jpegoptim, cliamp, spotatui"
    [mac-cloud]="rclone, borg, borgmatic"
    [dracula]="Dracula-Sakura theme pass for terminal, editor, and TUI surfaces"
    [configs]="Generated tool config, global git hooks, and omp setup"
    [filesystem]="Directory structure, helper scripts, git identity"
    [macos-defaults]="Finder, keyboard, screenshots, Touch ID, DNS"
    [shell]="\$HOME/.zshrc, Brewfile export"
)

# -- Install-vs-config split --------------------------------------------------
# A category INSTALLS its tools. It does not CONFIGURE them. Generated config files
# live in three ordered `configs` segments (with starship in `dracula`, ~/Scripts in
# `filesystem` and ~/.zshrc in `shell`), so `--only git` installs git tooling and
# refreshes NONE of its configuration — including the global pre-commit hook — while
# still reporting "Failed: 0". That silent half-run is #258.
#
# This table is what `--only` uses to say so out loud. It is descriptive text only —
# no control flow keys off it — but a typo'd category name would make a notice
# silently never appear, so the keys are validated against ALL_CATEGORIES below.
declare -A CONFIG_LIVES_IN_CONFIGS=(
    [core]="mise, direnv, ~/.npmrc, pip, gemrc"
    [git]="the global pre-commit hook, lazygit, gh, the commit template, global gitignore"
    [aws]="the AWS CLI config (\$HOME/.aws/config), Claws"
    [code-quality]="shellcheck, act, prettier, editorconfig"
    [replacements]="btop, ripgreprc, fdignore, aria2, Yazi"
    [data-processing]="yt-dlp, jqp"
    [api]="Posting"
    [terminal-productivity]="Emeraldian, leaf, topgrade, fastfetch, mprocs, Broot, eilmeldung, concord, cfait"
    [k8s-github]="gh-dash"
    [database]="harlequin"
    [containers]="Docker daemon, lazydocker"
    [networking]="trippy"
    [dx]="atuin, zellij, Kitty, Kiro, Croft, omp (~/.omp/agent + ~/.omp/plugins + ~/.agents/skills) — and starship, which is in the \`dracula\` category"
    [mac-media]="mpv, spotatui"
    [mac-browsers]="Chawan"
    [mac-productivity]="Obsidian vault themes, Herald, llama.cpp service"
)

# Loud default: a key here that is not a real category is a notice that can never
# fire. Fail at startup rather than silently doing nothing (the #241/#242 lesson).
for _cat in "${!CONFIG_LIVES_IN_CONFIGS[@]}"; do
    _known=false
    for _known_cat in "${ALL_CATEGORIES[@]}"; do
        [[ "$_cat" == "$_known_cat" ]] && _known=true && break
    done
    if [[ "$_known" != "true" ]]; then
        echo "INTERNAL ERROR: CONFIG_LIVES_IN_CONFIGS has unknown category '$_cat'" >&2
        exit 1
    fi
done
unset _cat _known _known_cat

# -- Which categories actually need sudo --------------------------------------
# Asking for a password up front is only defensible if something in THIS run will
# use it. `--only configs` uses none: the one `sudo` in that segment is inside the
# generated Justfile's `flush-dns` recipe, which the user may run later — the setup
# script never executes it. Every other category is unprivileged too (#269).
declare -A SUDO_CATEGORY_REASON=(
    [macos-defaults]="system settings (display sleep, DNS servers, startup chime, network time) and Touch ID for sudo"
)

# Predicate per sudo-needing category: does it have privileged work PENDING?
# `should_run` answers whether a category was selected, which is a different
# question and the one that made every run ask for a password (#502).
declare -A SUDO_CATEGORY_PREDICATE=(
    [macos-defaults]=macos_defaults_needs_sudo
)

# Same loud-default discipline as the table above. A category listed as needing
# sudo but missing a predicate must fail here, not quietly resolve to "no sudo
# needed" and then die at a password prompt in the middle of the work — which is
# the exact failure the up-front prompt exists to prevent.
for _cat in "${!SUDO_CATEGORY_REASON[@]}"; do
    if [[ -z "${SUDO_CATEGORY_PREDICATE[$_cat]:-}" ]]; then
        echo "INTERNAL ERROR: SUDO_CATEGORY_REASON['$_cat'] has no predicate in SUDO_CATEGORY_PREDICATE" >&2
        exit 1
    fi
done
unset _cat

# Same loud-default discipline as CONFIG_LIVES_IN_CONFIGS: a typo'd key here would
# silently drop a category's sudo requirement, and the run would fail later with a
# password prompt from the middle of the work instead of once, up front.
for _cat in "${!SUDO_CATEGORY_REASON[@]}"; do
    _known=false
    for _known_cat in "${ALL_CATEGORIES[@]}"; do
        [[ "$_cat" == "$_known_cat" ]] && _known=true && break
    done
    if [[ "$_known" != "true" ]]; then
        echo "INTERNAL ERROR: SUDO_CATEGORY_REASON has unknown category '$_cat'" >&2
        exit 1
    fi
done
unset _cat _known _known_cat

# Reasons this run needs sudo, one per line; empty when it does not need it at all.
# --cleanup is not considered here: it exits before preflight and prompts at the
# point of use. --dry-run never needs it, because it changes nothing.
# Read one key out of one power source's section of `pmset -g custom`. The output
# is two blocks headed "Battery Power:" and "AC Power:", and the same key name
# appears in both, so a bare grep would answer for whichever came first.
_pmset_value() {   # <Battery|AC> <key>
    pmset -g custom 2>/dev/null | awk -v sec="$1 Power:" -v key="$2" '
        $0 == sec { inblock = 1; next }
        /Power:$/ { inblock = 0 }
        inblock && $1 == key { print $2; exit }'
}

# Does `macos-defaults` have privileged work left to do?
#
# Every check below is the READ half of a guard the work block already applies.
# They must not drift: a predicate that says "already done" about work that is
# actually pending silently skips a system setting, which is worse than one
# unnecessary password prompt (#502).
macos_defaults_needs_sudo() {
    local pending=()

    # Touch ID for sudo — /etc/pam.d/sudo_local is world readable.
    [[ -f /etc/pam.d/sudo_local ]] && grep -q pam_tid /etc/pam.d/sudo_local 2>/dev/null \
        || pending+=("Touch ID for sudo")

    # DNS — only the services the work block actually touches.
    local service current
    while IFS= read -r service; do
        [[ "$service" == "Wi-Fi" || "$service" == "Ethernet" ]] || continue
        current=$(networksetup -getdnsservers "$service" 2>/dev/null)
        grep -q '1\.1\.1\.1' <<<"$current" || pending+=("DNS servers for $service")
    done < <(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)

    # Display sleep and half-dim. `halfdim` reads back as `lessbright`, and only
    # under Battery Power — pmset does not report it for AC.
    [[ "$(_pmset_value AC displaysleep)" == "120" && "$(_pmset_value Battery displaysleep)" == "75" ]] \
        || pending+=("display sleep timers")
    [[ "$(_pmset_value Battery lessbright)" == "1" ]] || pending+=("half-brightness step")

    # Startup chime.
    [[ "$(nvram StartupMute 2>/dev/null | awk '{print $2}')" == "%01" ]] \
        || pending+=("startup chime")

    # /Volumes visibility. MUST be /bin/ls: the coreutils install shadows BSD ls,
    # and GNU ls rejects -O with "invalid option", which reads like a permission
    # problem and is not one. This is the AGENTS.md environment gotcha in the wild.
    /bin/ls -ldO /Volumes 2>/dev/null | awk '{print $5}' | grep -q hidden \
        && pending+=("/Volumes visibility")

    # Network time. `systemsetup -getusingnetworktime` needs admin to READ, so the
    # state cannot be detected without the password we are trying to avoid asking
    # for. It is set-once, so an applied-once marker answers instead. The work
    # block still runs the command whenever it executes, so any run that obtains
    # sudo for another reason re-applies it for free.
    priv_done "systemsetup:networktime" || pending+=("network time")

    [[ ${#pending[@]} -gt 0 ]] || return 1
    printf '%s\n' "${pending[@]}"
    return 0
}

sudo_reasons() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    local c predicate item
    for c in "${!SUDO_CATEGORY_REASON[@]}"; do
        should_run "$c" || continue
        # Selected is not the same as pending. Ask the category whether it has
        # privileged work left; a converged machine needs no password at all,
        # which is what makes an unattended full run possible (#502).
        #
        # The predicate names the specific PENDING items, and those are what the
        # prompt shows. Printing the category's whole blurb would list settings
        # that are already applied, and a request naming work it will not do is
        # the same "you can only trust it" problem #269 fixed from the other side.
        predicate="${SUDO_CATEGORY_PREDICATE[$c]}"
        while IFS= read -r item; do
            [[ -n "$item" ]] && printf '%s (%s)\n' "$item" "$c"
        done < <("$predicate")
    done
}

# Print the notice when --only would skip the configuration for what was selected.
# Called early (before the work) and again in the completion summary, because the
# whole failure mode is a run that looks successful.
config_split_notice() {
    [[ ${#ONLY_CATEGORIES[@]} -gt 0 ]] || return 0
    local c
    for c in "${ONLY_CATEGORIES[@]}"; do
        [[ "$c" == "configs" ]] && return 0   # they asked for it; nothing to warn about
    done
    local affected=()
    for c in "${ONLY_CATEGORIES[@]}"; do
        [[ -n "${CONFIG_LIVES_IN_CONFIGS[$c]:-}" ]] && affected+=("$c")
    done
    [[ ${#affected[@]} -gt 0 ]] || return 0
    echo ""
    echo -e "${YELLOW}${BOLD}  Note: this run installs tools but refreshes no configuration.${NC}"
    for c in "${affected[@]}"; do
        echo -e "${YELLOW}    ${c}:${NC} ${CONFIG_LIVES_IN_CONFIGS[$c]}"
    done
    echo -e "${YELLOW}  Generated config lives in the ${BOLD}configs${NC}${YELLOW} category, not in the category that${NC}"
    echo -e "${YELLOW}  installs the tool. To refresh it too:${NC}"
    echo -e "      ${DIM}$0 --only $(IFS=,; echo "${ONLY_CATEGORIES[*]}"),configs${NC}"
    echo ""
}

# -- Interactive category picker -----------------------------------------------
interactive_select() {
    echo ""
    echo -e "${BOLD}${CYAN}Interactive Mode — Select categories to install${NC}"
    echo ""

    if command -v gum &>/dev/null; then
        # Build label list: "category — description"
        local labels=()
        for cat in "${ALL_CATEGORIES[@]}"; do
            labels+=("$cat — ${CATEGORY_DESC[$cat]:-}")
        done

        # gum choose with multi-select, all pre-selected
        local selected
        selected=$(printf '%s\n' "${labels[@]}" | gum choose --no-limit --height=35 \
            --header="Space to toggle, Enter to confirm" \
            --selected="*" \
            --cursor-prefix="[ ] " --selected-prefix="[✓] " --unselected-prefix="[ ] ") || true

        if [[ -z "$selected" ]]; then
            echo -e "${RED}No categories selected. Exiting.${NC}"
            exit 0
        fi

        # Extract category names (everything before " — ")
        while IFS= read -r line; do
            ONLY_CATEGORIES+=("${line%% — *}")
        done <<< "$selected"
    else
        # Fallback: numbered menu with toggle
        local -a selected_flags=()
        for _ in "${ALL_CATEGORIES[@]}"; do
            selected_flags+=(1)  # all selected by default
        done

        while true; do
            echo -e "${BOLD}Toggle categories (all selected by default):${NC}"
            echo ""
            for i in "${!ALL_CATEGORIES[@]}"; do
                local cat="${ALL_CATEGORIES[$i]}"
                local mark
                if [[ "${selected_flags[$i]}" -eq 1 ]]; then
                    mark="${GREEN}[✓]${NC}"
                else
                    mark="${DIM}[ ]${NC}"
                fi
                printf "  %s %2d) %-25s %s\n" "$mark" "$((i + 1))" "$cat" "${DIM}${CATEGORY_DESC[$cat]:-}${NC}"
            done

            echo ""
            echo -e "  ${CYAN}a${NC}) Select all  ${CYAN}n${NC}) Select none  ${CYAN}Enter${NC}) Confirm"
            echo ""
            read -rp "  Toggle (number, a, n, or Enter to confirm): " choice

            if [[ -z "$choice" ]]; then
                break
            elif [[ "$choice" == "a" ]]; then
                for i in "${!selected_flags[@]}"; do selected_flags[$i]=1; done
            elif [[ "$choice" == "n" ]]; then
                for i in "${!selected_flags[@]}"; do selected_flags[$i]=0; done
            elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ALL_CATEGORIES[@]} )); then
                local idx=$((choice - 1))
                if [[ "${selected_flags[$idx]}" -eq 1 ]]; then
                    selected_flags[$idx]=0
                else
                    selected_flags[$idx]=1
                fi
            else
                echo -e "  ${RED}Invalid input. Enter a number (1-${#ALL_CATEGORIES[@]}), a, n, or Enter.${NC}"
            fi

            # Clear the menu for redraw (move cursor up)
            local lines_to_clear=$(( ${#ALL_CATEGORIES[@]} + 5 ))
            for ((j = 0; j < lines_to_clear; j++)); do
                printf '\033[A\033[2K'
            done
        done

        # Build ONLY_CATEGORIES from selected flags
        for i in "${!ALL_CATEGORIES[@]}"; do
            if [[ "${selected_flags[$i]}" -eq 1 ]]; then
                ONLY_CATEGORIES+=("${ALL_CATEGORIES[$i]}")
            fi
        done

        if [[ ${#ONLY_CATEGORIES[@]} -eq 0 ]]; then
            echo -e "${RED}No categories selected. Exiting.${NC}"
            exit 0
        fi
    fi

    echo ""
    echo -e "${GREEN}Selected ${#ONLY_CATEGORIES[@]}/${#ALL_CATEGORIES[@]} categories:${NC} ${ONLY_CATEGORIES[*]}"
    echo ""
}

# -- CLI argument parsing -----------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}macOS Development Environment Setup v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: ./setup-dev-tools-mac.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --dry-run           Preview what would be installed (no changes)"
    echo "  --resume            Skip items that succeeded in a previous run"
    echo "  --uninstall         Show commands to remove everything (no changes made)"
    echo "  --doctor            Run Homebrew diagnostics even when no package failed"
    echo "  --verify            Check supported generated config with installed consumers"
    echo "                      and report unchecked inventory rows. CI proves syntax."
    echo "                      Only a machine with each tool can prove path usage."
    echo "                      Exits 1 when a supported consumer ignores our config"
    echo "  --interactive, -i   Interactively pick which categories to install"
    echo "  --no-prompt         Never wait for input — decline every optional prompt."
    echo "                      Use when nothing can answer (CI, a detached pane, an"
    echo "                      editor's run-in-terminal button), so the run cannot park"
    echo "                      on a question and hold the lock"
    echo "  --skip <cats>       Skip categories (comma-separated)"
    echo "  --only <cats>       Only run these categories (comma-separated)"
    echo "                      Add 'configs' to also refresh generated config —"
    echo "                      a category installs its tools but does not configure them"
    echo "  --list-categories   List all available categories"
    echo "  --list              List declared Homebrew and npm packages"
    echo "  --version           Show script version"
    echo ""
    echo "Examples:"
    echo "  ./setup-dev-tools-mac.sh                          # Install everything"
    echo "  ./setup-dev-tools-mac.sh -i                       # Interactive category picker"
    echo "  ./setup-dev-tools-mac.sh --dry-run                # Preview only"
    echo "  ./setup-dev-tools-mac.sh --list                   # List package declarations"
    echo "  ./setup-dev-tools-mac.sh --resume                 # Continue after a failure"
    echo "  ./setup-dev-tools-mac.sh --uninstall              # Show removal commands"
    echo "  ./setup-dev-tools-mac.sh --cleanup                # Remove dropped tools from previous versions"
    echo "  ./setup-dev-tools-mac.sh --verify                 # Is each tool reading our config?"
    echo "  ./setup-dev-tools-mac.sh --skip mac-media,mac-cloud"
    echo "  ./setup-dev-tools-mac.sh --only core,git,aws,dx"
    echo "  ./setup-dev-tools-mac.sh --only git,configs      # git tooling AND its config/hooks"
    echo "  ./setup-dev-tools-mac.sh --only configs          # regenerate every config file"
    echo ""
}

list_categories() {
    echo ""
    echo -e "${BOLD}Available categories:${NC}"
    echo ""
    # This note is FIRST on purpose. `configs` sorts last in a ~32-entry list, so
    # anyone skimming — or piping through `head` — never learns that a category
    # installs tools without configuring them (#258).
    echo -e "  ${YELLOW}Note:${NC} a category INSTALLS its tools; it does not CONFIGURE them."
    echo -e "        Generated config lives in ${BOLD}configs${NC} (plus starship in ${BOLD}dracula${NC},"
    echo -e "        ~/Scripts in ${BOLD}filesystem${NC}, ~/.zshrc in ${BOLD}shell${NC}), so pair them:"
    echo -e "        ${DIM}--only git,configs${NC}   not   ${DIM}--only git${NC}"
    echo ""
    # Read from CATEGORY_DESC rather than a second hardcoded copy. The two lists had
    # silently drifted apart in seven categories (act3, ni, Objective-See, monolith,
    # terminal-notifier, fx, and most of terminal-productivity appeared in one and not
    # the other), so --list-categories and the interactive picker described the same
    # category differently. One source of truth means that can't recur.
    local cat
    for cat in "${ALL_CATEGORIES[@]}"; do
        printf "  %-25s %s\n" "$cat" "${CATEGORY_DESC[$cat]:-}"
    done
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "setup-dev-tools-mac.sh v${SCRIPT_VERSION}"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --update-brew)
            FORCE_BREW_UPDATE=true
            shift
            ;;
        --doctor)
            FORCE_BREW_DOCTOR=true
            shift
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --interactive|-i)
            INTERACTIVE=true
            shift
            ;;
        --no-prompt)
            NO_PROMPT=true
            shift
            ;;
        --skip)
            if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
                echo -e "${RED}ERROR: --skip requires a comma-separated list of categories${NC}"
                echo "  Example: --skip mac-media,mac-cloud"
                echo "  Run --list-categories to see options."
                exit 1
            fi
            IFS=',' read -ra SKIP_CATEGORIES <<< "$2"
            shift 2
            ;;
        --only)
            if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
                echo -e "${RED}ERROR: --only requires a comma-separated list of categories${NC}"
                echo "  Example: --only core,git,aws,dx"
                echo "  Run --list-categories to see options."
                exit 1
            fi
            IFS=',' read -ra ONLY_CATEGORIES <<< "$2"
            shift 2
            ;;
        --list-categories)
            list_categories
            exit 0
            ;;
        --list)
            echo ""
            echo -e "${BOLD}Declared packages and editor extensions:${NC}"
            echo ""
            echo -e "${CYAN}Homebrew formulae:${NC}"
            grep -E '^\s*brew_install ' "$0" | sed 's/.*brew_install "\([^"]*\)".*/  \1/' | sort
            echo ""
            echo -e "${CYAN}Homebrew casks:${NC}"
            grep -E '^\s*brew_cask_install ' "$0" | sed 's/.*brew_cask_install "\([^"]*\)".*/  \1/' | sort
            echo ""
            echo -e "${CYAN}npm global packages:${NC}"
            grep -E '^\s*npm_global_install ' "$0" | sed 's/.*npm_global_install "\([^"]*\)".*/  \1/' | sort
            echo ""
            echo -e "${CYAN}Kiro extensions:${NC}"
            grep -E '^\s*kiro_extension_install ' "$0" | sed 's/.*kiro_extension_install "\([^"]*\)".*/  \1/' | sort
            echo ""
            _f=$(grep -cE '^\s*brew_install ' "$0")
            _c=$(grep -cE '^\s*brew_cask_install ' "$0")
            _n=$(grep -cE '^\s*npm_global_install ' "$0")
            _k=$(grep -cE '^\s*kiro_extension_install ' "$0")
            echo -e "${DIM}Total: ${_f} formulae, ${_c} casks, ${_n} npm packages, ${_k} Kiro extensions ($((_f + _c + _n + _k)) declarations)${NC}"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# --interactive is a prompt; --no-prompt says never prompt. Must be checked BEFORE
# interactive_select runs, or the picker asks the question we just promised not to.
if [[ "$INTERACTIVE" == "true" && "$NO_PROMPT" == "true" ]]; then
    echo -e "${RED}[ ERR]${NC} --interactive and --no-prompt are mutually exclusive."
    exit 1
fi

# Homebrew 6 defaults to confirmation prompts for installs. Disable them when
# --no-prompt promises an unattended run.
if [[ "$NO_PROMPT" == "true" ]]; then
    export HOMEBREW_NO_ASK=1
fi

# -- Interactive mode (must run before validation, populates ONLY_CATEGORIES) --
if [[ "$INTERACTIVE" == "true" ]]; then
    if [[ ${#ONLY_CATEGORIES[@]} -gt 0 ]] || [[ ${#SKIP_CATEGORIES[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: --interactive cannot be combined with --only or --skip${NC}"
        exit 1
    fi
    interactive_select
fi

# -- Validate --skip/--only category names early ------------------------------
for cat in "${SKIP_CATEGORIES[@]}" "${ONLY_CATEGORIES[@]}"; do
    _valid=false
    for known in "${ALL_CATEGORIES[@]}"; do
        [[ "$cat" == "$known" ]] && _valid=true && break
    done
    if [[ "$_valid" != "true" ]]; then
        echo -e "${RED}[ ERR]${NC} Unknown category: '$cat'. Valid categories: ${ALL_CATEGORIES[*]}"
        exit 1
    fi
done

# Say up front when --only will install without configuring (#258); repeated in the
# completion summary, since by then this notice has scrolled away.
config_split_notice

# -- Category filtering -------------------------------------------------------
should_run() {
    local category="$1"
    [[ "$category" == "macos-defaults" && "$PRIVILEGED_WORK_SKIPPED" == "true" ]] && return 1

    # If --only is set, only run matching categories
    if [[ ${#ONLY_CATEGORIES[@]} -gt 0 ]]; then
        for c in "${ONLY_CATEGORIES[@]}"; do
            [[ "$c" == "$category" ]] && return 0
        done
        return 1
    fi

    # If --skip is set, skip matching categories
    for c in "${SKIP_CATEGORIES[@]}"; do
        [[ "$c" == "$category" ]] && return 1
    done

    return 0
}

# -- Utility functions --------------------------------------------------------
installed() { command -v "$1" &>/dev/null; }
# Run a command with administrator privileges without allowing an unexpected
# password prompt when --no-prompt is active.
sudo_run() {
    if [[ "$NO_PROMPT" == "true" ]]; then
        sudo -n "$@"
    else
        sudo "$@"
    fi
}

# node_version_at_least <required-version>
# Return success when the active Node.js version meets the required semver floor.
node_version_at_least() {
    local required="$1" current
    local req_major req_minor req_patch cur_major cur_minor cur_patch
    current="$(node --version 2>/dev/null)" || return 1
    current="${current#v}"
    IFS=. read -r cur_major cur_minor cur_patch <<< "$current"
    IFS=. read -r req_major req_minor req_patch <<< "$required"
    cur_major="${cur_major:-0}"
    cur_minor="${cur_minor:-0}"
    cur_patch="${cur_patch:-0}"
    req_major="${req_major:-0}"
    req_minor="${req_minor:-0}"
    req_patch="${req_patch:-0}"
    (( 10#$cur_major > 10#$req_major ||
       (10#$cur_major == 10#$req_major && 10#$cur_minor > 10#$req_minor) ||
       (10#$cur_major == 10#$req_major && 10#$cur_minor == 10#$req_minor &&
        10#$cur_patch >= 10#$req_patch) ))
}

# ensure_mcp_inspector_node
# Make the Node.js engine required by MCP Inspector available through mise.
ensure_mcp_inspector_node() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    node_version_at_least "22.19.0" && return 0
    installed mise || return 1
    info "Installing Node.js 22.19.0 or newer for MCP Inspector..."
    mise install node@22.19.0 >> "$LOG_FILE" 2>&1 &&
        mise use --global node@22.19.0 >> "$LOG_FILE" 2>&1 || return 1
    _mise_node="$(mise which node 2>/dev/null || true)"
    if [[ -n "$_mise_node" ]]; then
        _mise_node_bin="$(dirname "$_mise_node")"
        export PATH="$_mise_node_bin:$PATH"
        hash -r 2>/dev/null || true
        # npm_global_install may have snapshotted another Node installation before
        # this function selected the MCP Inspector runtime.
        _npm_snapshot_ready=
        _NPM_GLOBALS=
    fi
    unset _mise_node _mise_node_bin
    node_version_at_least "22.19.0"
}


# _verify_output_has <extended-regex> <cmd> [args...]
# Test a command's output against a pattern WITHOUT a pipe. Used by --verify.
#
# `<tool> | grep -q <pat>` is unsafe anywhere in this script: grep -q exits at
# the first match, the tool ahead of it gets SIGPIPE while still writing, and
# `set -o pipefail` turns that 141 into a failure. In a --verify row the result
# reads exactly like "the tool rejected our config", which is the opposite of
# what happened.
#
# direnv hit this on every run, because `direnv status` keeps printing after the
# matched line. pi, omp and zellij shared the shape and passed only because their
# output was short enough to finish first — luck, not correctness, and a row that
# passes for that reason starts failing when a tool grows one more line (#505).
#
# Lives in the helper layer rather than inside the verify function so the bug has
# a regression test; the tool-specific _verify_* helpers stay where they are used.
# stderr is folded in because zellij reports on it, and every caller matches a
# positive marker specific enough that a warning cannot satisfy it by accident.
_verify_output_has() {
    local pattern="$1"; shift
    local out; out="$("$@" 2>&1)"
    grep -qE "$pattern" <<<"$out"
}

# orphaned_brew_node_links <brew-prefix>
# Print every symlink in <prefix>/bin whose target points into <prefix>/lib/node_modules.
#
# Those are the bin stubs `npm install -g` creates under a Homebrew node. When that
# node is removed the stubs stay, still resolving, still executing the old tree's
# code through whatever `node` PATH now finds (#515). Selecting them by TARGET
# rather than by name matters: everything else in that directory belongs to a
# formula, and a name-based list would go stale the moment a package is added.
#
# The caller is responsible for the guard that this prefix has no node at all.
# While a node formula is installed the tree is its live global root, not an orphan.
orphaned_brew_node_links() {
    local prefix="$1" f target
    [[ -d "$prefix/bin" ]] || return 0
    for f in "$prefix/bin"/*; do
        [[ -L "$f" ]] || continue
        target="$(readlink "$f")"
        case "$target" in
            */lib/node_modules/*) printf '%s\n' "$f" ;;
        esac
    done
}

# git_global <args...>
# A `git config --global` WRITE, with the --dry-run rule applied in one place instead
# of at 49 call sites. Every one of those sites was unguarded, so `--dry-run` rewrote
# the user's global git config — pager, aliases, hooksPath, excludesfile, commit
# template, the includeIf identity routing — on a run that signs off with "no changes
# were made" (#380). Guarding them individually would have worked once and rotted at
# the next addition; a helper is what makes the next line someone adds safe by default.
#
# WRITES ONLY. A read (`if git config --global core.pager | grep -q delta`) must stay
# a raw `git config` call — it has no side effect, and routing it through here would
# make it return success without answering the question, which is how a guard turns
# into a bug.
#
# Logged rather than printed: 49 "[DRY RUN] Would set …" lines would bury the run's
# actual output. The enclosing block prints one summary line; the detail is in the log.
git_global() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] git config --global $*"
        return 0
    fi
    git config --global "$@"
}

# ensure_dir <dir...>
# `mkdir -p` that honours --dry-run. Used at the sites a dry run actually reaches —
# found by running one against a throwaway $HOME and listing what appeared, not by
# reading (#380). An empty ~/.ssh/sockets is harmless in itself; the problem is that
# "no changes were made" has to be true or it is worth nothing, and a directory tree
# is the thing someone checks for when they want to know whether a preview touched
# their machine. Keep the guard here so the next caller inherits the rule instead
# of having to remember it.
ensure_dir() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] mkdir -p $*"
        return 0
    fi
    mkdir -p "$@"
}

# _trim_blank_edges <file>   (trimmed content on stdout)
# The file's content with leading and trailing blank lines removed, so two regions
# can be compared for equality without tripping over surrounding spacing.
_trim_blank_edges() {
    awk '{ l[NR] = $0 }
         END { s = 1; e = NR
               while (s <= e && l[s] ~ /^[[:space:]]*$/) s++
               while (e >= s && l[e] ~ /^[[:space:]]*$/) e--
               for (i = s; i <= e; i++) print l[i] }' "$1"
}

# _has_content <file>   -> 0 when the file holds anything other than whitespace
_has_content() { grep -q '[^[:space:]]' "$1" 2>/dev/null; }

# _managed_marker_state <file> <mb> <me>   -> "absent" | "unmarked" | "valid" | "invalid"
# Single point of truth for whether a file's dev-setup markers are well-formed:
# exactly one opening marker, exactly one closing marker, opening before closing.
# write_managed, write_managed_script and remove_superseded_managed all treat
# anything else as INVALID rather than guessing which half of the file is real —
# an unclosed opener made write_managed silently drop everything after it, and
# made remove_superseded_managed delete a file that still held real content (#530).
_managed_marker_state() {
    local file="$1" mb="$2" me="$3"
    [[ -f "$file" ]] || { echo absent; return 0; }
    local mb_n me_n
    mb_n="$(grep -cF -- "$mb" "$file" 2>/dev/null || true)"; mb_n="${mb_n:-0}"
    me_n="$(grep -cF -- "$me" "$file" 2>/dev/null || true)"; me_n="${me_n:-0}"
    if [[ "$mb_n" -eq 0 ]]; then
        echo unmarked; return 0
    fi
    if [[ "$mb_n" -eq 1 && "$me_n" -eq 1 ]]; then
        local mb_line me_line
        mb_line="$(grep -nF -- "$mb" "$file" | head -1 | cut -d: -f1)"
        me_line="$(grep -nF -- "$me" "$file" | head -1 | cut -d: -f1)"
        if [[ "$me_line" -gt "$mb_line" ]]; then
            echo valid; return 0
        fi
    fi
    echo invalid
}

# remove_superseded_managed <file> <explanation> [issue-ref] [comment-prefix]
# Delete a config file THIS SCRIPT wrote that has since moved to a new path. Only
# when it is provably ours: our markers present AND nothing outside them — the same
# test write_managed applies before it deletes an outside region (#259), and for the
# same reason. Anything else is a user edit, a foreign file, or something holding a
# credential, and is left in place with a warning instead. Honors DRY_RUN.
#
# A path change is only half-delivered without this. Writing the new file fixes fresh
# installs; every already-provisioned machine keeps the old one sitting there, and in
# every case so far it kept costing something — asciinema printed a banner on each
# invocation (#329), nushell prints one too (#333).
remove_superseded_managed() {
    local file="$1" what="$2" ref="${3:-}" cp="${4:-#}"
    [[ -f "$file" ]] || return 0
    local mb="$cp >>> dev-setup managed block (do not edit between the markers) >>>"
    local me="$cp <<< dev-setup managed block <<<"
    local _state; _state="$(_managed_marker_state "$file" "$mb" "$me")"
    if [[ "$_state" == "unmarked" ]]; then
        warn "Left $file alone — this script did not write it. $what"
        return 0
    fi
    if [[ "$_state" == "invalid" ]]; then
        warn "Left $file alone — its dev-setup markers are malformed (unbalanced or reordered), so ownership cannot be proven. $what"
        return 0
    fi
    local outside; outside="$(mktemp)"
    awk -v mb="$mb" -v me="$me" '
        index($0, mb) { inb = 1; next }
        index($0, me) { inb = 0; next }
        !inb { print }' "$file" > "$outside"
    if _has_content "$outside"; then
        warn "Left $file alone — it has edits outside our markers. $what"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove the superseded $file $ref"
    else
        rm -f "$file"
        info "Removed the superseded $file — $what $ref"
    fi
    rm -f "$outside"
}

# write_managed <file> [comment-prefix]   (config content on stdin)
# Idempotent config writer that MERGES on re-run instead of overwriting:
#   - new file                -> create it wrapped in dev-setup markers
#   - file has our markers    -> replace ONLY the block between markers (edits outside survive)
#   - file exists, no markers -> back up and REPLACE (see the branch below for why)
# Comment prefix defaults to '#'. Honors DRY_RUN. This is the .zshrc managed-block
# pattern generalized so re-running the setup pulls config updates without clobbering
# personal edits placed outside the markers.
write_managed() {
    local file="$1" cp="${2:-#}"
    local mb="$cp >>> dev-setup managed block (do not edit between the markers) >>>"
    local me="$cp <<< dev-setup managed block <<<"
    local body; body="$(mktemp)"
    cat > "$body"
    local tmp; tmp="$(mktemp)"
    { printf '%s\n' "$mb"; cat "$body"; printf '%s\n' "$me"; } > "$tmp"
    if [[ "$DRY_RUN" != "true" ]]; then mkdir -p "$(dirname "$file")"; fi
    local _mstate; _mstate="$(_managed_marker_state "$file" "$mb" "$me")"
    if [[ ! -f "$file" ]]; then
        # A dry run used to say nothing at all here, so the preview was least
        # informative exactly where it matters most: on a fresh machine, where every
        # one of these managed files is absent and every one of them would be created.
        # Announcing it is also what lets `configured` go silent without the run
        # losing the information (#381).
        [[ "$DRY_RUN" == "true" ]] && info "[DRY RUN] Would create $file"
        [[ "$DRY_RUN" == "true" ]] || cp "$tmp" "$file"
    elif [[ "$_mstate" == "invalid" ]]; then
        # An opener with no closer (or a stray/reordered closer) means half the file
        # is not real content and half is not a real block — merging blindly used to
        # silently drop everything after the opener (#530). Refuse and count it as a
        # failure instead of guessing.
        rm -f "$tmp" "$body"
        error "Left $file alone — its dev-setup markers are malformed (unbalanced or reordered). Fix or remove the file, then re-run."
        return 1
    elif [[ "$_mstate" == "valid" ]]; then
        # Split the file around our markers so the regions OUTSIDE them can be
        # inspected rather than blindly preserved. A pre-#130 write_managed APPENDED
        # its block to marker-less files, so upgraded machines can carry a stray copy
        # of the block above ours — which the marker-to-marker rewrite below could
        # never reach, freezing the file duplicated forever. Fatal for ~/.prettierrc,
        # which is parsed as YAML and rejects a second document; merely redundant for
        # the ~18 other configs affected, whose formats happen to be last-key-wins
        # (~/.aws/config, ~/.npmrc, ~/.editorconfig, ~/.vimrc, …). See #259.
        local pre post oldblk; pre="$(mktemp)"; post="$(mktemp)"; oldblk="$(mktemp)"
        awk -v mb="$mb" 'index($0, mb) { exit } { print }' "$file" > "$pre"
        awk -v me="$me" 'seen { print } index($0, me) { seen = 1 }' "$file" > "$post"
        awk -v mb="$mb" -v me="$me" '
            index($0, me) { inb = 0 } inb { print } index($0, mb) { inb = 1 }' "$file" > "$oldblk"
        # Drop an outside region ONLY when it is an exact duplicate of content we know
        # to be ours: either the block we are about to write, or the block already
        # between the markers (which this script wrote on an earlier run, so a stray
        # copy of it is ours too — that is what catches a duplicate left by an OLDER
        # version whose content has since drifted). Deleting outside content on any
        # looser test would eat real user config: ~/.ssh/config Host entries,
        # ~/.aws/config profiles, ~/.npmrc tokens and ~/.zshrc edits all legitimately
        # live out there, and none of them match our own generated block.
        local repaired=false region
        for region in "$pre" "$post"; do
            _has_content "$region" || continue
            if cmp -s <(_trim_blank_edges "$region") <(_trim_blank_edges "$body") ||
               { _has_content "$oldblk" && cmp -s <(_trim_blank_edges "$region") <(_trim_blank_edges "$oldblk"); }; then
                : > "$region"
                repaired=true
            fi
        done
        [[ "$repaired" == "true" ]] && managed_note repaired "$file"
        # Whatever is still outside the markers is either a deliberate user edit or a
        # duplicate left by an older script version that has since drifted. Either way
        # it is not ours to delete — record it for the one-line notice at the end.
        if _has_content "$pre" || _has_content "$post"; then managed_note outside "$file"; fi
        if [[ "$DRY_RUN" == "true" ]]; then
            [[ "$repaired" == "true" ]] && info "[DRY RUN] Would remove a duplicate pre-managed copy of the block from $file"
        else
            local out; out="$(mktemp)"
            cat "$pre" "$tmp" "$post" > "$out" && mv "$out" "$file"
            [[ "$repaired" == "true" ]] && info "Removed a duplicate pre-managed copy of the block from $file (#259)"
        fi
        rm -f "$pre" "$post" "$oldblk"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would back up and replace the unmarked $file"
    else
        # File exists but has none of our markers — e.g. written whole by a
        # pre-managed-block version of this script. APPENDING our block would
        # duplicate keys/sections (fatal for TOML/YAML: "duplicate key"). These
        # configs are script-owned (keep personal edits in *.local files or track
        # them with chezmoi), so back the file up and REPLACE it with the block.
        cp "$file" "${file}.pre-managed.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        cp "$tmp" "$file"
    fi
    rm -f "$tmp" "$body"
}

# write_managed_script <file>   (script body on stdin, may start with a #! shebang)
# Like write_managed, but for EXECUTABLES: the shebang stays on line 1 (outside the
# markers) and only the body is wrapped in a managed block, so re-runs refresh the
# body while the shebang (and any edits outside the block) survive. chmod +x on write.
write_managed_script() {
    local file="$1"
    local body shebang="#!/usr/bin/env bash"
    body="$(cat)"
    if [[ "$body" == '#!'* ]]; then          # split off an existing shebang
        shebang="${body%%$'\n'*}"
        body="${body#*$'\n'}"
    fi
    local mb="# >>> dev-setup managed block (do not edit between the markers) >>>"
    local me="# <<< dev-setup managed block <<<"
    local _mstate; _mstate="$(_managed_marker_state "$file" "$mb" "$me")"
    if [[ "$_mstate" == "invalid" ]]; then
        # Same integrity gap as write_managed (#530): an opener with no matching
        # closer used to make the awk merge below swallow every line after it,
        # since `inb` was set and never cleared. Refuse rather than guess.
        error "Left $file alone — its dev-setup markers are malformed (unbalanced or reordered). Fix or remove the file, then re-run."
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        # Say what would happen, for the same reason write_managed does (#381) — these
        # are the ~/Scripts/bin helpers and the git hook delegators, and a preview that
        # named none of them was the least useful part of the output.
        case "$_mstate" in
            absent)   info "[DRY RUN] Would create $file" ;;
            unmarked) info "[DRY RUN] Would back up and replace the unmarked $file" ;;
            *)        info "[DRY RUN] Would refresh $file" ;;
        esac
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    local bt; bt="$(mktemp)"; printf '%s\n' "$body" > "$bt"
    if [[ "$_mstate" == "unmarked" ]]; then
        # File exists with none of our markers — back it up before replacing, same
        # rule write_managed applies, so an overwritten hand-placed script is
        # recoverable rather than silently gone (#530).
        cp "$file" "${file}.pre-managed.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    if [[ "$_mstate" == "absent" || "$_mstate" == "unmarked" ]]; then
        { printf '%s\n' "$shebang"; printf '%s\n' "$mb"; cat "$bt"; printf '%s\n' "$me"; } > "$file"
    else
        local out; out="$(mktemp)"
        awk -v mb="$mb" -v me="$me" -v blk="$bt" '
            index($0, mb) { print; while ((getline line < blk) > 0) print line; close(blk); inb=1; next }
            index($0, me) { inb=0; print; next }
            !inb { print }
        ' "$file" > "$out" && mv "$out" "$file"
    fi
    rm -f "$bt"
    chmod +x "$file"
}

# write_generated <file>   (content on stdin)
# For script-owned files that cannot carry managed-block markers. Examples
# include prompt files with required frontmatter and machine-read data formats.
# The function keeps marker text out of content that a consumer parses verbatim.
# Refreshes only when the content differs, and backs up whatever it replaces, so an
# edit made on the machine is recoverable. The alternative in use before this was a
# create-once guard ("directory already has agents"), under which one pre-existing
# file froze the entire set and no later addition or edit ever arrived (#277).
write_generated() {
    local file="$1"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp"
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$file" ]]; then
            ! cmp -s "$tmp" "$file" && info "[DRY RUN] Would refresh $file"
        else
            info "[DRY RUN] Would create $file"
        fi
        rm -f "$tmp"; return 0
    fi
    mkdir -p "$(dirname "$file")"
    if [[ -f "$file" ]] && cmp -s "$tmp" "$file"; then rm -f "$tmp"; return 0; fi
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.replaced.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        managed_note refreshed "$file"
    fi
    mv "$tmp" "$file"
}

# write_seed_once <file> <why>   (content on stdin)
# For files that are seeded ONCE and then left alone forever: a starter template the
# user is expected to edit (borgmatic), or a file a tool later writes a credential
# into (ngrok's authtoken). Unlike write_managed
# there is no block to refresh on re-run — an existing file is ALWAYS left exactly as
# it is, which is the deliberate, auditable version of a bare `if [[ ! -f ]]` guard
# rather than an accident (#536). Honors DRY_RUN. Returns 0 when the file was written
# (or would be, under DRY_RUN) and 1 when an existing file was left alone, so a caller
# gates its own `success`/`configured` message on whether anything actually changed.
write_seed_once() {
    local file="$1" why="$2"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$file" ]]; then
        rm -f "$tmp"
        info "$file already exists — leaving it alone ($why)"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        rm -f "$tmp"
        info "[DRY RUN] Would seed $file ($why)"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    mv "$tmp" "$file"
    return 0
}

# set_toml_top_level_string <file> <key> <value>
# Replace or add one top-level TOML string without rewriting comments or user formatting.
# A parser check fails closed before the edit. Nested keys with the same name stay untouched.
set_toml_top_level_string() {
    local file="$1" key="$2" value="$3"
    local tmp
    [[ "$key" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    [[ "$value" != *'"'* && "$value" != *$'\n'* ]] || return 1
    [[ -f "$file" ]] || return 1
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would set $key in $file"
        return 0
    fi
    command -v python3 &>/dev/null || return 2
    python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" &>/dev/null || return 1
    tmp="$(mktemp)"
    if awk -v key="$key" -v replacement="$key = \"$value\"" '
        BEGIN { done = 0 }
        !done && /^[[:space:]]*\[/ {
            print replacement
            done = 1
        }
        !done && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            print replacement
            done = 1
            next
        }
        { print }
        END {
            if (!done) print replacement
        }
    ' "$file" > "$tmp" && python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$tmp" &>/dev/null; then
        mv "$tmp" "$file"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# merge_json_defaults <file> [jq-filter] [source-file]   (defaults on stdin)
# Merges script defaults below an existing JSON object. The on-disk object wins unless
# the optional filter reasserts an owned key. A source file lets a caller supply a
# validated representation while the destination remains the generated output path.
# Invalid JSON and missing jq leave the destination byte-for-byte unchanged (#533).
merge_json_defaults() {
    local file="$1" filter="${2:-.}" source="${3:-$1}"
    local defaults current tmp
    defaults="$(mktemp)"
    current="$(mktemp)"
    tmp="$(mktemp)"
    cat > "$defaults"
    if [[ "$DRY_RUN" == "true" ]]; then
        rm -f "$defaults" "$current" "$tmp"
        info "[DRY RUN] Would merge JSON defaults into $file"
        return 0
    fi
    if ! command -v jq &>/dev/null; then
        rm -f "$defaults" "$current" "$tmp"
        return 2
    fi
    if [[ -f "$source" ]]; then
        cat "$source" > "$current"
    else
        printf '{}\n' > "$current"
    fi
    if jq -s ".[0] * .[1] | $filter" "$defaults" "$current" > "$tmp" 2>/dev/null; then
        mkdir -p "$(dirname "$file")"
        mv "$tmp" "$file"
        rm -f "$defaults" "$current"
        return 0
    fi
    rm -f "$defaults" "$current" "$tmp"
    return 1
}


# normalize_editor_jsonc <input> <output>
# Code OSS editors can rewrite settings with trailing commas. Remove only commas
# immediately before a closing object or array, then require jq to accept the
# result. Comments and all other JSONC syntax fail closed.
normalize_editor_jsonc() {
    local input="$1" output="$2"
    command -v perl &>/dev/null || return 1
    command -v jq &>/dev/null || return 1
    perl -0pe '1 while s/,[ \t]*\n([ \t]*[}\]])/\n$1/g' "$input" |
        jq . > "$output" 2>/dev/null
}

# link_mise_shims <shims-dir> <bin-dir> [excluded-name ...]
# Links every current shim except explicit exclusions, then removes only dangling links
# that point into the same shim directory. Returns the number of current links (#532).
link_mise_shims() {
    local shims="$1" bin_dir="$2"
    shift 2
    local shim name excluded ex link count=0
    mkdir -p "$bin_dir"
    for shim in "$shims"/*; do
        [[ -e "$shim" ]] || continue
        name="$(basename "$shim")"
        excluded=false
        for ex in "$@"; do
            [[ "$name" == "$ex" ]] && excluded=true && break
        done
        [[ "$excluded" == "true" ]] && continue
        ln -sfn "$shim" "$bin_dir/$name"
        count=$((count + 1))
    done
    for link in "$bin_dir"/*; do
        [[ -L "$link" ]] || continue
        case "$(readlink "$link")" in
            "$shims/"*) [[ -e "$link" ]] || rm -f "$link" ;;
        esac
    done
    printf '%s\n' "$count"
}

# Append one exact line when it is missing. Used for tool-owned config files whose
# existing user content we must preserve rather than replace. DRY_RUN narrates the
# pending append and writes nothing (#391).
append_line_if_missing() {
    local file="$1" line="$2" desc="${3:-line}"
    if [[ -f "$file" ]] && grep -qxF -- "$line" "$file" 2>/dev/null; then
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would append $desc to $file"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$line" >> "$file"
}

# Append a heredoc block when a sentinel text is missing. Same constraints and same
# DRY_RUN rule as append_line_if_missing (#391).
append_block_if_missing() {
    local file="$1" needle="$2" desc="${3:-block}"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp"
    if [[ -f "$file" ]] && grep -qF -- "$needle" "$file" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would append $desc to $file"
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    cat "$tmp" >> "$file"
    rm -f "$tmp"
}

# Membership checks against a ONE-TIME snapshot of installed formulae/casks, instead
# of booting Ruby via `brew list <name>` ~200 times (that cost ~80-150s per re-run).
# The snapshot is populated lazily on first use (after Homebrew is installed) and
# kept in sync as we install. `brew list -1` prints short names, so normalize tap
# paths (a/b/c -> c) with ${x##*/}.
_brew_snapshot_ready=""
_ensure_brew_snapshot() {
    [[ -n "$_brew_snapshot_ready" ]] && return 0
    _BREW_FORMULAE=" $(brew list --formula -1 2>/dev/null | tr '\n' ' ') "
    _BREW_CASKS=" $(brew list --cask -1 2>/dev/null | tr '\n' ' ') "
    _brew_snapshot_ready=1
}
_brew_has_formula() { _ensure_brew_snapshot; [[ "$_BREW_FORMULAE" == *" ${1##*/} "* ]]; }
_brew_has_cask()    { _ensure_brew_snapshot; [[ "$_BREW_CASKS"    == *" ${1##*/} "* ]]; }

brew_install_batch() {
    local entry formula name
    local -a pending_formulas=() pending_names=()
    _ensure_brew_snapshot
    for entry in "$@"; do
        formula="${entry%%|*}"
        name="${entry#*|}"
        [[ "$name" == "$entry" ]] && name="$formula"
        is_done "brew:$formula" && continue
        _brew_has_formula "$formula" && continue
        pending_formulas+=("$formula")
        pending_names+=("$name")
    done
    ((${#pending_formulas[@]} > 0)) || return 0
    [[ "$DRY_RUN" == "true" ]] && return 0
    info "Installing Homebrew formula batch (${#pending_formulas[@]} formulae)..."
    if brew install "${pending_formulas[@]}" >> "$LOG_FILE" 2>&1; then
        local i
        for i in "${!pending_formulas[@]}"; do
            formula="${pending_formulas[$i]}"
            success "${pending_names[$i]} installed"
            _BREW_FORMULAE="$_BREW_FORMULAE${formula##*/} "
            mark_done "brew:$formula"
        done
    else
        warn "Homebrew formula batch failed — retrying formulae individually"
        return 1
    fi
}

brew_cask_install_batch() {
    local entry cask name
    local -a pending_casks=() pending_names=()
    _ensure_brew_snapshot
    for entry in "$@"; do
        cask="${entry%%|*}"
        name="${entry#*|}"
        [[ "$name" == "$entry" ]] && name="$cask"
        is_done "cask:$cask" && continue
        _brew_has_cask "$cask" && continue
        pending_casks+=("$cask")
        pending_names+=("$name")
    done
    ((${#pending_casks[@]} > 0)) || return 0
    [[ "$DRY_RUN" == "true" ]] && return 0
    info "Installing Homebrew cask batch (${#pending_casks[@]} casks)..."
    if brew install --cask --adopt "${pending_casks[@]}" >> "$LOG_FILE" 2>&1; then
        local i
        for i in "${!pending_casks[@]}"; do
            cask="${pending_casks[$i]}"
            success "${pending_names[$i]} installed"
            _BREW_CASKS="$_BREW_CASKS${cask##*/} "
            mark_done "cask:$cask"
        done
    else
        warn "Homebrew cask batch failed — retrying casks individually"
        return 1
    fi
}

brew_install() { _time_install_helper brew _brew_install "$@"; }
_brew_install() {
    local formula="$1"
    local name="${2:-$1}"
    progress
    is_done "brew:$formula" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        if _brew_has_formula "$formula"; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if _brew_has_formula "$formula"; then
        warn "$name already installed"
        mark_done "brew:$formula"
    else
        info "Installing $name..."
        if brew install "$formula" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
            _BREW_FORMULAE="$_BREW_FORMULAE${formula##*/} "
            mark_done "brew:$formula"
        else
            error "Failed to install $name"
        fi
    fi
}

brew_cask_install() { _time_install_helper cask _brew_cask_install "$@"; }
_brew_cask_install() {
    local cask="$1"
    local name="${2:-$1}"
    progress
    is_done "cask:$cask" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        if _brew_has_cask "$cask"; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if _brew_has_cask "$cask"; then
        warn "$name already installed"
        mark_done "cask:$cask"
    else
        info "Installing $name..."
        if brew install --cask --adopt "$cask" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
            _BREW_CASKS="$_BREW_CASKS${cask##*/} "
            mark_done "cask:$cask"
        else
            error "Failed to install $name (cask may have been renamed)"
        fi
    fi
}

# One-time snapshot of global npm packages (each `npm list -g` parses the whole tree,
# ~1s). Matches on the package path so scoped names (@antfu/ni) work.
_npm_snapshot_ready=""
_ensure_npm_snapshot() {
    [[ -n "$_npm_snapshot_ready" ]] && return 0
    _NPM_GLOBALS="$(npm ls -g --depth=0 --parseable 2>/dev/null)"
    _npm_snapshot_ready=1
}
_npm_pkg_name() {
    local spec="$1"
    if [[ "$spec" == @*/*@* ]]; then
        printf '%s\n' "${spec%@*}"
    elif [[ "$spec" != @* && "$spec" == *@* ]]; then
        printf '%s\n' "${spec%@*}"
    else
        printf '%s\n' "$spec"
    fi
}
_npm_has() {
    _ensure_npm_snapshot
    local name; name="$(_npm_pkg_name "$1")"
    local line
    while IFS= read -r line; do [[ "$line" == */node_modules/"$name" ]] && return 0; done <<< "$_NPM_GLOBALS"
    return 1
}

npm_global_install() { _time_install_helper npm _npm_global_install "$@"; }
_npm_global_install() {
    local pkg="$1"
    local name="${2:-$1}"
    # Any args after the display name go straight to `npm install -g`, for packages that
    # document a flag as part of their install form (--ignore-scripts and the like). This
    # script runs under bash 4+ with no `set -u`, so an empty array expands to zero words,
    # not one empty one.
    shift $(( $# > 2 ? 2 : $# ))
    local npm_flags=("$@")
    progress
    is_done "npm:$pkg" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        if _npm_has "$pkg"; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if _npm_has "$pkg"; then
        warn "$name already installed globally"
        mark_done "npm:$pkg"
    else
        info "Installing $name globally..."
        if npm install -g "${npm_flags[@]}" "$pkg" >> "$LOG_FILE" 2>&1; then
            _npm_snapshot_ready=
            _NPM_GLOBALS=
            success "$name installed"
            mark_done "npm:$pkg"
        else
            error "Failed to install $name"
        fi
    fi
}

_KIRO_EXTENSIONS=""
_kiro_extensions_ready=""
_ensure_kiro_extension_snapshot() {
    [[ -n "$_kiro_extensions_ready" ]] && return 0
    _KIRO_EXTENSIONS="$(kiro --list-extensions 2>/dev/null || true)"
    _kiro_extensions_ready=1
}

# kiro_extension_install <extension-id> <display-name>
# Installs a registry extension through Kiro's Code OSS command-line interface.
kiro_extension_install() { _time_install_helper kiro _kiro_extension_install "$@"; }
_kiro_extension_install() {
    local extension="$1" name="${2:-$1}"
    progress
    if ! installed kiro; then
        warn "Skipping $name — Kiro not installed"
        return 0
    fi
    _ensure_kiro_extension_snapshot
    if printf '%s\n' "$_KIRO_EXTENSIONS" | grep -Fxiq "$extension"; then
        warn "$name already installed in Kiro"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install Kiro extension: $name"
    else
        info "Installing Kiro extension: $name..."
        if kiro --install-extension "$extension" >> "$LOG_FILE" 2>&1; then
            _KIRO_EXTENSIONS="${_KIRO_EXTENSIONS}${_KIRO_EXTENSIONS:+$'\n'}$extension"
            success "$name installed in Kiro"
        else
            error "Failed to install Kiro extension: $name"
        fi
    fi
}



# go_install <import-path@ver> <cmd-name> <description>
# Installs a Go tool into $GOBIN (the dir the login shell puts on PATH), so it's
# reachable both during this run and in new shells. Skips if already present,
# honors DRY_RUN, and advances the progress bar in every branch.
go_install() { _time_install_helper go _go_install "$@"; }
_go_install() {
    local path="$1" name="$2" desc="${3:-$2}"
    if command -v "$name" &>/dev/null; then
        warn "$name already installed"; progress; return 0
    fi
    if ! installed go; then
        warn "Skipping $name — Go not installed (run: brew install go)"; progress; return 0
    fi
    info "Installing $desc via go..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: go install $path"
    elif go install "$path" >> "$LOG_FILE" 2>&1; then
        success "$name installed"
    else
        error "Failed to install $name via go"
    fi
    progress
}

# uv_tool_install <pkg-spec> <cmd-name> <description> <success-msg> [extra uv args...]
# Installs a PyPI tool via `uv tool install` (isolated venv, binary on PATH via
# ~/.local/bin). Skips if present, honors DRY_RUN, advances the progress bar.
# Pass all four positional args; any trailing args are forwarded to uv.
uv_tool_install() { _time_install_helper uv _uv_tool_install "$@"; }
_uv_tool_install() {
    local spec="$1" name="$2" desc="$3" done_msg="$4"; shift 4
    if command -v "$name" &>/dev/null; then
        warn "$name already installed"; progress; return 0
    fi
    if ! installed uv; then
        warn "Skipping $name — uv not installed"; progress; return 0
    fi
    info "Installing $desc via uv..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: uv tool install${*:+ $*} ${spec}"
    elif uv tool install "$@" "$spec" >> "$LOG_FILE" 2>&1; then
        success "$done_msg"
    else
        error "Failed to install $name via uv"
    fi
    progress
}

# cargo_install <pkg> <cmd-name> <description> [cargo install args...]
# Installs a Rust CLI from crates.io or a Git repository. The command name is
# checked first because package and binary names can differ (chamber-tui -> chamber).
cargo_install() { _time_install_helper cargo _cargo_install "$@"; }
_cargo_install() {
    local package="$1" name="$2" desc="$3"; shift 3
    if command -v "$name" &>/dev/null; then
        warn "$name already installed"; progress; return 0
    fi
    if ! installed cargo; then
        warn "Skipping $name — cargo not installed"; progress; return 0
    fi
    info "Installing $desc via cargo..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: cargo install $package${*:+ $*}"
    elif cargo install "$package" "$@" >> "$LOG_FILE" 2>&1; then
        success "$name installed"
    else
        error "Failed to install $name via cargo"
    fi
    progress
}

# rustup_component_install <toolchain> <component> <probe-command> <display-name>
# Installs a component and its toolchain together so a fresh machine needs one run.
rustup_component_install() { _time_install_helper rustup _rustup_component_install "$@"; }
_rustup_component_install() {
    local toolchain="$1" component="$2" probe="$3" name="$4"
    progress
    if ! installed rustup; then
        warn "Skipping $name — rustup not installed"
    elif rustup which "$probe" --toolchain "$toolchain" &>/dev/null; then
        warn "$name already installed for the $toolchain Rust toolchain"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: $name for the $toolchain Rust toolchain"
    elif rustup toolchain install "$toolchain" --component "$component" >> "$LOG_FILE" 2>&1; then
        success "$name installed for the $toolchain Rust toolchain"
    else
        error "Failed to install $name for the $toolchain Rust toolchain"
    fi
}

# run_remote_installer <label> <url> <optional-sha256> <runner>... [-- <script-args...>]
# Download an upstream installer script to a temp file, optionally verify it by
# SHA256, then execute it via the given runner command. Any args after `--` are
# passed to the installer script itself, so callers can express both
#   /bin/bash installer.sh
# and
#   sh installer.sh -y --no-modify-path
# through one helper.
#
# This centralizes the repo's fetch-and-exec bootstrap paths (Homebrew / rustup /
# pnpm today) so the trust boundary is one helper instead of three hand-rolled
# blocks, and makes a future pin as small as supplying the third argument.
#
# No DRY_RUN branch here on purpose: callers decide whether a fetch/exec path is
# appropriate for the current mode. On failure, REMOTE_INSTALLER_ERROR is set to
# one of: download failed, empty download, checksum mismatch, execution failed,
# no runner.
REMOTE_INSTALLER_ERROR=""
run_remote_installer() {
    local label="$1" url="$2" expected_sha="$3"; shift 3
    local installer actual_sha arg seen_sep=0
    local -a runner script_args
    REMOTE_INSTALLER_ERROR=""
    for arg in "$@"; do
        if (( ! seen_sep )) && [[ "$arg" == "--" ]]; then
            seen_sep=1
            continue
        fi
        if (( seen_sep )); then
            script_args+=("$arg")
        else
            runner+=("$arg")
        fi
    done
    if (( ${#runner[@]} == 0 )); then
        REMOTE_INSTALLER_ERROR="no runner"
        return 1
    fi
    installer="$(mktemp)"
    if ! curl -fsSL "$url" -o "$installer"; then
        rm -f "$installer"
        REMOTE_INSTALLER_ERROR="download failed"
        return 1
    fi
    if [[ ! -s "$installer" ]]; then
        rm -f "$installer"
        REMOTE_INSTALLER_ERROR="empty download"
        return 1
    fi
    if [[ -n "$expected_sha" ]]; then
        actual_sha="$(shasum -a 256 "$installer" | awk '{print $1}')"
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            rm -f "$installer"
            REMOTE_INSTALLER_ERROR="checksum mismatch"
            return 1
        fi
        log "REMOTE_INSTALLER: $label from $url (sha256 pinned)"
    else
        log "REMOTE_INSTALLER: $label from $url (sha256 unpinned)"
    fi
    if "${runner[@]}" "$installer" "${script_args[@]}" >> "$LOG_FILE" 2>&1; then
        rm -f "$installer"
        return 0
    fi
    rm -f "$installer"
    REMOTE_INSTALLER_ERROR="execution failed"
    return 1
}

# trust_tap <user/repo>
# Homebrew 6 refuses to load formulae OR casks from non-official ("untrusted")
# taps until they're trusted with `brew trust` (HOMEBREW_ALLOWED_TAPS does NOT
# bypass this — it's a separate gate). Tap and trust in one step so installs from
# our vetted taps proceed. Trust persists in ~/.homebrew/trust.json, so the user's
# later manual installs from these taps work too. Honors DRY_RUN.
trust_tap() {
    local tap="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: brew tap $tap && brew trust --tap $tap"
        return 0
    fi
    brew tap "$tap" >> "$LOG_FILE" 2>&1 || true
    # brew reads its trust from $XDG_CONFIG_HOME/homebrew/trust.json when XDG_CONFIG_HOME
    # is set (interactive shells — we export it) but from ~/.homebrew/trust.json when it
    # isn't (launchd / `brew services` at login). Write BOTH, so tapped-formula
    # services auto-start at login, not only after an interactive install.
    # Writing one location leaves the other context refusing the tap.
    XDG_CONFIG_HOME="$HOME/.config" brew trust --tap "$tap" >> "$LOG_FILE" 2>&1 \
        || warn "Could not trust tap $tap — installs from it may be refused by Homebrew"
    env -u XDG_CONFIG_HOME brew trust --tap "$tap" >> "$LOG_FILE" 2>&1 || true
}


# -- Source guard for unit tests ---------------------------------------------
# #375: the helpers above carry all the risk in this script and were testable only
# by hand (the file executes top to bottom on source, so `source setup-dev-tools-mac.sh`
# starts installing things). Setting SETUP_LIB_ONLY=1 before sourcing returns here,
# after every helper is defined and before preflight / lock / anything destructive
# runs — so a bats suite can load the helper layer in isolation on a Linux CI runner.
#
# The guard is its own short block so the intent is obvious in code review; placing it
# after trust_tap (the last helper) and before preflight (the first side-effecting
# function) gives it a precise load boundary.
if [[ -n "${SETUP_LIB_ONLY:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

# -- Pre-flight checks --------------------------------------------------------
preflight() {
    banner "Pre-flight Checks"

    # macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion)
    local macos_major
    macos_major=$(echo "$macos_version" | cut -d. -f1)
    if [[ "$macos_major" -lt 13 ]]; then
        error "macOS 13 (Ventura) or later required. You have: $macos_version"
        echo "  Some tools may not work on older versions."
        confirm=$(prompt_ask "Continue anyway? [y/N] " "n")
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        checked "macOS $macos_version detected"
    fi

    # Architecture
    local arch
    arch=$(uname -m)
    checked "Architecture: $arch"

    # Internet connectivity
    if curl -s --max-time 5 https://raw.githubusercontent.com > /dev/null 2>&1; then
        checked "Internet connection OK"
    else
        error "No internet connection detected"
        echo "  This script requires internet to download packages."
        exit 1
    fi

    # Disk space (require at least 15GB free)
    # Use native macOS df (not GNU coreutils which may be in PATH and lacks -g)
    local free_space
    free_space=$(/bin/df -g "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
    # Fallback: parse df -h output if -g isn't available
    if [[ -z "$free_space" ]] || [[ "$free_space" == "0" ]]; then
        free_space=$(df -h "$HOME" | tail -1 | awk '{print $4}' | sed 's/[^0-9]//g')
    fi
    if [[ -n "$free_space" ]] && [[ "$free_space" -lt 15 ]]; then
        error "Low disk space: ${free_space}GB free (15GB+ recommended)"
        confirm=$(prompt_ask "Continue anyway? [y/N] " "n")
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        checked "Disk space: ${free_space:-unknown}GB free"
    fi

    # Admin check — only when a step in THIS run will actually use sudo, and saying
    # what for. Asking unconditionally meant `--dry-run` demanded a password to
    # produce a preview that changes nothing, and the message named no step, so the
    # only way to judge the request was to trust it (#269).
    local reasons
    reasons=$(sudo_reasons)
    if [[ -z "$reasons" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            checked "No admin privileges needed (dry run changes nothing)"
        else
            checked "No admin privileges needed for the selected categories"
        fi
    elif sudo -n true 2>/dev/null; then
        checked "Admin privileges available"
    elif [[ "$NO_PROMPT" == "true" ]]; then
        warn "Skipping privileged work — --no-prompt prevents a sudo password prompt"
        PRIVILEGED_WORK_SKIPPED=true
    else
        info "Admin privileges are needed for:"
        while IFS= read -r reason; do
            [[ -n "$reason" ]] && echo "         • $reason"
        done <<< "$reasons"
        info "Enter your password once now:"
        sudo -v
        checked "Admin privileges granted"
        # Keep sudo alive for the duration of the script. Test liveness BEFORE each
        # refresh, not only after the sleep: the old order could refresh the sudo
        # timestamp once more after the parent had already exited.
        ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done 2>/dev/null ) &
        SUDO_KEEPALIVE_PID=$!
    fi

    if command -v brew &>/dev/null; then
        if brew_doctor_needed; then
            run_brew_doctor
        else
            info "Skipping brew doctor — use --doctor, or rerun after a package failure"
        fi
    fi

    # Validate --skip and --only categories
    local invalid_cats=()
    for c in "${SKIP_CATEGORIES[@]}" "${ONLY_CATEGORIES[@]}"; do
        local found=false
        for valid in "${ALL_CATEGORIES[@]}"; do
            [[ "$c" == "$valid" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && invalid_cats+=("$c")
    done
    if [[ ${#invalid_cats[@]} -gt 0 ]]; then
        error "Unknown categories: ${invalid_cats[*]}"
        echo "  Run with --list-categories to see valid options."
        exit 1
    fi

    # Log file
    checked "Log file: $LOG_FILE"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}  DRY RUN MODE — no changes will be made${NC}"
        echo ""
    fi

    if [[ "$RESUME" == "true" ]]; then
        if [[ -f "$STATE_FILE" ]]; then
            local completed_count
            completed_count=$(wc -l < "$STATE_FILE" | tr -d ' ')
            echo ""
            echo -e "${CYAN}${BOLD}  RESUME MODE — skipping $completed_count previously completed items${NC}"
            echo ""
        else
            info "Resume mode enabled but no previous state found — running from scratch"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}${MAGENTA}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           macOS Dev Environment Setup v${SCRIPT_VERSION}              ║"
echo "  ║                                                              ║"
echo "  ║  Curated tools · managed configs · Dracula-Sakura terminal Mac  ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Don't exit on error — we count failures instead
set +e
set -o pipefail

# -- Handle --uninstall early (just prints commands, no changes) --------------
if [[ "$UNINSTALL" == "true" ]]; then
    echo ""
    echo -e "${BOLD}${YELLOW}Uninstall Guide${NC}"
    echo -e "${DIM}Run these commands to remove everything installed by this script.${NC}"
    echo ""
    echo "# Remove all Homebrew formulae and casks installed by this script:"
    echo "  brew bundle cleanup --file=~/.config/brewfile/Brewfile --force"
    echo ""
    echo "# Remove config files:"
    echo "  rm -f ~/.shellcheckrc ~/.editorconfig ~/.prettierrc"
    echo ""
    echo "# Remove the mise shim links that make node/npm/npx visible to git hooks:"
    echo "  rm -f ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx"
    echo "  rm -f ~/.curlrc ~/.npmrc ~/.ripgreprc ~/.fdignore ~/.nanorc ~/.vimrc"
    echo "  rm -f ~/.hushlogin ~/.gitmessage ~/.gemrc ~/.actrc ~/.tflint.hcl"
    echo "  rm -rf ~/.aria2 ~/.config/atuin ~/.config/ngrok"
    echo "  rm -rf ~/.config/yt-dlp ~/.config/gh-dash ~/.config/stern"
    echo "  rm -rf ~/.config/btop ~/.config/lazydocker ~/.config/mise"
    echo "  rm -rf ~/.config/topgrade.toml ~/.config/fastfetch ~/.config/kitty"
    echo "  rm -rf ~/.config/direnv ~/.config/broot ~/.herald"
    echo "  rm -f ~/.justfile ~/Media/photos/dracula-sakura.jpg"
    echo "  rm -f ~/Library/Application\\ Support/Kiro/User/settings.json"
    echo "  rm -rf ~/.kiro/extensions/vixygrey.dracula-sakura-*"
    echo ""
    echo "# Remove Rust (installed via rustup):"
    echo "  rustup self uninstall"
    echo ""
    echo "# Remove tools not managed by Homebrew:"
    echo "  rm -f ~/.local/bin/llama-cli ~/.local/bin/llama-server"
    echo "  rm -rf ~/.local/share/llama.cpp-vulkan ~/.local/share/llama.cpp"
    echo "  rm -f ~/.local/bin/mullvad-tui"
    echo "  rm -rf ~/.local/share/mullvad-tui"
    echo "  [[ \"\$(readlink ~/.local/bin/clangd 2>/dev/null)\" == */opt/llvm/bin/clangd ]] && rm -f ~/.local/bin/clangd"
    echo "  [[ \"\$(readlink ~/.local/bin/omnisharp 2>/dev/null)\" == ~/.local/share/omnisharp/omnisharp ]] && rm -f ~/.local/bin/omnisharp"
    echo "  [[ -f ~/.local/share/omnisharp/.dev-setup-build ]] && rm -rf ~/.local/share/omnisharp"
    echo "  launchctl bootout gui/\$(id -u) ~/Library/LaunchAgents/dev.vixygrey.llama-cpp.plist 2>/dev/null || true"
    echo "  rm -f ~/Library/LaunchAgents/dev.vixygrey.llama-cpp.plist"
    echo ""
    echo "# Remove OMP config, sessions, and generated shared skills:"
    echo "  rm -rf ~/.omp"
    echo "  rm -rf ~/.agents/skills/api-testing ~/.agents/skills/d2-diagrams ~/.agents/skills/inspect-machine ~/.agents/skills/office-layout-check"
    echo "  brew untap can1357/tap"
    echo ""
    echo "# Remove Helix config:"
    echo "  rm -rf ~/.config/helix"
    echo ""
    echo "# Remove helper scripts:"
    echo "  rm -rf ~/Scripts/bin"
    echo ""
    echo "# Remove the managed block from ~/.zshrc (edit manually)"
    echo "# Remove git global config overrides:"
    echo "  git config --global --unset core.pager"
    echo "  git config --global --unset core.hooksPath"
    echo "  git config --global --unset core.excludesfile"
    echo "  git config --global --unset commit.template"
    echo ""
    echo "# Remove state files:"
    echo "  rm -rf ~/.local/share/dev-setup"
    echo ""
    echo -e "${YELLOW}Review each command before running. This does NOT auto-execute.${NC}"
    exit 0
fi

# -- Handle --cleanup (remove tools from previous versions no longer in script)
if [[ "$CLEANUP" == "true" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}Cleanup: Removing tools from previous versions${NC}"
    echo ""

    # Tools removed in current version (were in previous versions, now replaced or dropped)
    # Format: "type:name:display-name:replacement:appname"
    # appname (optional, 5th field) = actual .app name when it differs from display-name.
    # Used as fallback to find apps in /Applications that weren't installed via Homebrew.
    #
    # type is one of: formula (alias: brew), cask, mas, npm, uv, cargo.
    # Package types identify tools that this script installed through matching helpers.
    # Anything else hits the loud `*)` default below.
    DEPRECATED_TOOLS=(
        "brew:tmux:tmux:zellij"
        "brew:helix:Helix (hx):micro"
        "brew:aider:aider:omp"
        "brew:repomix:repomix:omp"
        "brew:aerc:aerc:removed"
        "brew:khal:khal:removed"
        "brew:vdirsyncer:vdirsyncer:removed"
        "brew:tldr:tldr (unmaintained, disabled upstream):tlrc"
        # npm globals this script installed and later dropped. Until #399 there was no
        # way to express these at all, so they stayed on every machine that had them.
        # `repomix` also has a brew: row above — it shipped both ways, and removing the
        # formula never touched an npm copy.
        "npm:playwright:Playwright:removed"
        "npm:storybook:Storybook CLI:removed"
        "npm:repomix:repomix (npm copy):omp"
        # Retired in #513: omp replaced pi. ~/.pi goes with it through
        # CONFIG_ORPHANS below.
        "npm:@earendil-works/pi-coding-agent:pi (superseded by omp):omp"
        # Retired in #540. Personal notes under ~/Documents/notes stay untouched.
        "brew:boolean-maybe/tap/tiki:tiki:plain Markdown + reminders"
        # Retired in #542. Cleanup removes the packages first, then removes
        # exclusive per-user data only after the owning command or app is absent.
        # Retired in #544. The managed config and exact generated login agent are
        # removed in the configs segment, where normal reruns also reach them.
        "cask:ghostty:Ghostty:Kitty:Ghostty"
        # Retired in #546. Yazi replaces both file managers. starlit has no
        # replacement. Exclusive config is handled through CONFIG_ORPHANS.
        "uv:rovr:rovr:Yazi"
        "formula:nnn:nnn:Yazi"
        "uv:starlit-cli:starlit:removed"
        "formula:vhs:vhs:removed"
        "cask:claude:Claude:removed:Claude"
        "formula:ollama:Ollama:llama.cpp"
        "formula:bendews/tap/apw:apw:removed"
        "formula:keith/formulae/reminders-cli:reminders-cli:removed"
        "npm:@anthropic-ai/claude-code:Claude Code CLI:omp"
        "formula:bun:Bun (former OMP plugin runtime):removed"
        "formula:ikebastuz/wiper/wiper:wiper:removed"
        "formula:glab:glab:removed"
        "formula:doxx:doxx:removed"
        "formula:dhth/tap/bmm:bmm:removed"
        "uv:manly:manly:removed"
        "formula:git-lfs:Git LFS:removed"
        "cask:gitkraken-cli:GitKraken CLI:removed"
        "formula:dhth/tap/act3:act3:removed"
        "npm:@antfu/ni:ni:removed"
        "formula:asciinema:asciinema:removed"
        "formula:jordond/tap/jolt:jolt:removed"
        "cask:visual-studio-code:Visual Studio Code:micro:Visual Studio Code"
        "npm:@github/copilot:GitHub Copilot CLI:omp"
        # Replaced by Kiro in #589. User-owned files under ~/.config/zed stay.
        "cask:zed:Zed:Kiro:Zed"
        "formula:aichat:aichat:removed"
        "npm:turbo:Turborepo:removed"
        "npm:lighthouse:Lighthouse CLI:removed"
        "cask:pearcleaner:Pearcleaner:removed:Pearcleaner"
        "formula:dockutil:dockutil:removed"
        "formula:terminal-notifier:terminal-notifier:removed"
        "cask:shottr:Shottr:removed:Shottr"
        "cask:skim:Skim:removed:Skim"
        "formula:p7zip:p7zip:removed"
        "formula:newsboat:newsboat:removed"
        "formula:googleworkspace-cli:Google Workspace CLI:removed"
        "formula:gws:gws (git-workspace):removed"
        "cask:gcloud-cli:Google Cloud CLI:removed"
        "cask:google-cloud-sdk:Google Cloud SDK:removed"
        "cask:orbstack:OrbStack:removed:OrbStack"
        "cask:qlmarkdown:QLMarkdown (Quick Look):removed"
        "cask:qlstephen:QLStephen (Quick Look):removed"
        "cask:protonvpn:Proton VPN:removed"
        "cask:proton-mail:Proton Mail:removed"
        "cask:proton-pass:Proton Pass:removed"
        "cask:proton-drive:Proton Drive:removed"
        "cask:warp:Warp terminal:Kitty:Warp"
        "cask:iterm2:iTerm2:Kitty:iTerm"
        "formula:FelixKratz/formulae/sketchybar:SketchyBar:removed"
        "cask:font-sketchybar-app-font:SketchyBar app font:removed"
        "formula:blueutil:blueutil:removed"
        "cask:cursor:Cursor (AI editor):micro + omp:Cursor"
        "cask:bruno:Bruno:Posting:Bruno"
        "cask:dbeaver-community:DBeaver Community:harlequin:DBeaver"
        "cask:cyberduck:Cyberduck:rclone:Cyberduck"
        "cask:google-drive:Google Drive:rclone:Google Drive"
        "cask:notion:Notion:plain Markdown + reminders:Notion"
        "cask:notion-calendar:Notion Calendar:removed:Notion Calendar"
        "brew:cmus:cmus:cliamp"
        "brew:kew:kew:cliamp"
        "brew:tokei:tokei:scc"
        "brew:glow:glow:leaf"
        "cask:raycast:Raycast:Spotlight + clipse:Raycast"
        "cask:aerospace:AeroSpace:native Spaces + macOS tiling:AeroSpace"
        "cask:unifi-identity-endpoint:UniFi Identity Endpoint:removed:UniFi Identity Endpoint"
        "cask:cleanshot:CleanShot X:removed"
        "cask:soulver:Soulver 3:removed:Soulver 3"
        "cask:numi:Numi:removed"
        "cask:hazel:Hazel:macOS Automator/scripts"
        "cask:popclip:PopClip:removed"
        "cask:espanso:Espanso:removed"
        "cask:wireshark:Wireshark:removed"
        "cask:topnotch:TopNotch:removed"
        "cask:syncthing:Syncthing:removed"
        "cask:arc:Arc:Google Chrome"
        "cask:brave-browser:Brave Browser:removed:Brave Browser"
        "cask:postman:Postman:Bruno"
        "cask:daisydisk:DaisyDisk:dust + duf (CLI)"
        "cask:proxyman:Proxyman:mitmproxy"
        "cask:appcleaner:AppCleaner:removed"
        "cask:bartender:Bartender:removed:Bartender 4"
        "cask:jordanbaird-ice:Ice:removed"
        "mas:1502839586:Hand Mirror:removed"
        "formula:dog:dog (DNS tool):doggo"
        "cask:tailscale:Tailscale:removed"
        "cask:alt-tab:AltTab:removed (macOS alt-tab is sufficient)"
        "cask:anki:Anki:removed"
        "cask:discord:Discord:removed"
        "cask:figma:Figma:removed"
        "cask:gimp:GIMP:removed:GIMP-2.10"
        "cask:keyboardcleantool:KeyboardCleanTool:removed"
        "cask:pocket-casts:Pocket Casts:removed"
        "cask:yoink:Yoink:removed"
        "mas:1289583905:Pixelmator Pro:removed"
        "mas:1470584107:Dato:removed"
        "mas:1607635845:Velja:removed"
        "mas:1423210932:Flow:removed"
        "cask:maccy:Maccy:clipse"
        "formula:nvm:nvm:mise"
        "formula:pyenv:pyenv:mise"
        "formula:httpie:HTTPie:xh"
        "formula:git-secrets:git-secrets:gitleaks"
        "formula:trufflehog:trufflehog:gitleaks"
        "cask:the-unarchiver:The Unarchiver:ouch"
        "cask:transmit:Transmit:rclone:Transmit"
        "cask:colima:colima:removed"
        "cask:blockblock:BlockBlock:removed"
        "cask:oversight:OverSight:removed"
        "cask:knockknock:KnockKnock:removed"
        "cask:reikey:ReiKey:removed"
        "cask:syntax-highlight:Syntax Highlight:removed"
        "mas:937984704:Amphetamine:removed"
        "cask:stats:Stats:removed"
        "cask:rectangle:Rectangle:removed"
        "cask:snagit:Snagit:removed:Snagit"
        "cask:signal:Signal:removed"
        "formula:gifski:gifski:removed"
        "mas:6475002485:Reeder:removed"
        "formula:mas:mas:removed"
        "cask:tableplus:TablePlus:DBeaver:TablePlus"
        "cask:iina:IINA:mpv (CLI)"
        "cask:imageoptim:ImageOptim:oxipng + jpegoptim (CLI)"
        "cask:keka:Keka:ouch"
        "formula:entr:entr:watchexec"
        "cask:slack:Slack:removed"
        "cask:telegram:Telegram:removed"
        "cask:notion-mail:Notion Mail:removed (retired by Notion):Notion Mail"
        # Retired in #555 after the default toolset audit. These entries make the
        # removal reach machines that were provisioned before the install list shrank.
        "npm:cdk-nag:cdk-nag global library:removed"
        "formula:tree:tree:eza"
        "formula:curlie:curlie:xh"
        "formula:detect-secrets:detect-secrets:gitleaks"
        "npm:@commitlint/cli:commitlint:project-local commit policy"
        "npm:commitizen:commitizen:git template + omp"
        "npm:cz-conventional-changelog:Commitizen conventional adapter:git template + omp"
        "npm:npkill:npkill:removed"
        "formula:nano:Homebrew nano:micro"
        "cask:font-meslo-lg-nerd-font:MesloLGS Nerd Font:JetBrains Mono Nerd Font"
        "cask:font-fira-code:Fira Code:JetBrains Mono"
        "cask:font-fira-code-nerd-font:Fira Code Nerd Font:JetBrains Mono Nerd Font"
        "cask:font-hack-nerd-font:Hack Nerd Font:JetBrains Mono Nerd Font"
        "uv:llm:llm:omp"
        "uv:linecast:Linecast:removed"
        "formula:pgcli:pgcli:harlequin + usql"
        "formula:mycli:mycli:harlequin + usql"
        "formula:lazysql:lazysql:harlequin"
        "formula:neilotoole/sq/sq:sq:DuckDB + usql"
        "formula:mtr:mtr:trippy"
        "formula:watchman:Watchman:watchexec"
        "formula:git-cliff:git-cliff:hand-written changelogs"
        "npm:@mermaid-js/mermaid-cli:Mermaid CLI:d2"
        "formula:caddy:Caddy:miniserve"
        "formula:clamav:ClamAV:removed"
        "formula:kdabir/tap/has:has:removed"
        "formula:taproom:taproom:Homebrew CLI"
        "cask:gateway-of-last-resort/tap/keyward:keyward:OpenSSH"
        "formula:lazynop/tap/lazyenv:lazyenv:direnv"
        "formula:nushell:Nushell:zsh + jq + yq"
        "formula:kondo:kondo:removed"
        "formula:miller:Miller:csvkit + DuckDB"
        "formula:grpcurl:grpcurl:removed"
        # Replaced by the themed terminal browser in #572.
        "formula:w3m:w3m:Chawan"
        # Replaced by Posting in #572.
        "formula:atac:ATAC:Posting"
        # Retired from the curated setup in #578.
        "formula:k9s:k9s:removed"
        "formula:stern:stern:removed"
        "formula:kubernetes-cli:kubectl:removed"
        "formula:bandwhich:bandwhich:removed"
        "formula:opentofu:OpenTofu:removed"
        "cask:tflint:tflint:removed"
        "formula:infracost:infracost:removed"
        "cask:thunderbird:Thunderbird:removed:Thunderbird"
        "cask:mitmproxy:mitmproxy:removed"
        "formula:parallel:GNU parallel:removed"
        "formula:sops:sops:removed"
        "formula:hyperfine:hyperfine:removed"
        "formula:oha:oha:removed"
        # Retired in #586. The qualified token is required because Homebrew's core
        # cask uses the same basename for the unrelated Nssurge application.
        "cask:surgedm/tap/surge:SurgeDM:removed"
        # The direct ffmpeg install was retired in #555, but mpv and cliamp still
        # require the formula. Do not make cleanup break those retained tools (#563).
    )

    CLEANUP_COUNT=0
    CLEANUP_SKIPPED=0

    # Resolved once rather than per entry: `npm root -g` is a process spawn, and the
    # loop below would otherwise pay for it on every npm row. Empty when npm is absent,
    # which makes every npm row a skip instead of an error.
    _npm_root=""
    if installed npm; then _npm_root="$(npm root -g 2>/dev/null || true)"; fi
    _uv_tools=""
    if installed uv; then _uv_tools="$(uv tool list 2>/dev/null || true)"; fi
    _cargo_tools=""
    if installed cargo; then _cargo_tools="$(cargo install --list 2>/dev/null || true)"; fi

    for entry in "${DEPRECATED_TOOLS[@]}"; do
        IFS=':' read -r type name display replacement appname <<< "$entry"
        # appname defaults to display name when not specified (5th field)
        appname="${appname:-$display}"

        case "$type" in
            formula|brew)
                if brew list "$name" &>/dev/null; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if [[ "$name" == "ollama" || "$name" == "bendews/tap/apw" || "$name" == "FelixKratz/formulae/sketchybar" ]]; then
                            brew services stop "$name" >> "$LOG_FILE" 2>&1 || true
                        elif [[ "$name" == "clamav" ]]; then
                            launchctl unload "$HOME/Library/LaunchAgents/com.freshclam.update.plist" >> "$LOG_FILE" 2>&1 || true
                        fi
                        if [[ "$name" == "git-lfs" ]]; then
                            git lfs uninstall --skip-repo >> "$LOG_FILE" 2>&1 || true
                        fi
                        if brew uninstall "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            cask)
                if brew list --cask "$name" &>/dev/null; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if [[ "$name" == "surgedm/tap/surge" ]] && installed surge; then
                            if ! surge service uninstall >> "$LOG_FILE" 2>&1; then
                                error "Failed to uninstall the SurgeDM service. SurgeDM remains installed for a safe retry."
                                ((CLEANUP_SKIPPED++))
                                continue
                            fi
                        fi
                        # Homebrew records a fully-qualified cask but removes it by
                        # its short token. This matters for custom casks that share
                        # a basename with a core cask.
                        _cask_token="${name##*/}"
                        case "$name" in
                            claude|gitkraken-cli|visual-studio-code|pearcleaner|shottr|skim|orbstack)
                                _cask_remove=(brew uninstall --cask --zap "$_cask_token")
                                ;;
                            *)
                                _cask_remove=(brew uninstall --cask "$_cask_token")
                                ;;
                        esac
                        if "${_cask_remove[@]}" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        unset _cask_remove _cask_token

                        ((CLEANUP_COUNT++))
                    fi
                elif [[ -d "/Applications/$appname.app" ]]; then
                    # App exists but wasn't installed via Homebrew (manual / direct download)
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (not managed by Homebrew, replaced by $replacement)"
                    else
                        info "Removing $display (not managed by Homebrew, replaced by $replacement)..."
                        if installed trash; then
                            trash "/Applications/$appname.app" >> "$LOG_FILE" 2>&1 && success "$display trashed" || error "Failed to remove $display"
                        else
                            sudo_run rm -rf "/Applications/$appname.app" 2>/dev/null && success "$display removed" || error "Failed to remove $display"
                        fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            mas)
                # Check mas registry first (if mas is installed), then fall back to /Applications
                if installed mas && mas list 2>/dev/null | grep -q "$name"; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        sudo_run rm -rf "/Applications/$appname.app" 2>/dev/null || true
                        ((CLEANUP_COUNT++))
                        success "$display removed"
                    fi
                elif [[ -d "/Applications/$appname.app" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        sudo_run rm -rf "/Applications/$appname.app" 2>/dev/null || true
                        ((CLEANUP_COUNT++))
                        success "$display removed"
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            npm)
                # A directory probe, not `npm ls -g <name>`: `npm ls` is a slow spawn per
                # entry and exits non-zero for reasons unrelated to presence (peer-dep
                # warnings), which would silently turn a real removal into a skip.
                if [[ -n "$_npm_root" && -d "$_npm_root/$name" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if npm uninstall -g "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            uv)
                if printf '%s\n' "$_uv_tools" | grep -qE "^${name} "; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if uv tool uninstall "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            cargo)
                if printf '%s\n' "$_cargo_tools" | grep -qE "^${name} v"; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if cargo uninstall "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            *)
                # A deprecated-tool entry whose type field matches no branch would
                # otherwise be a silent no-op (the tool never gets removed and the
                # count is never touched). "brew" was exactly this bug — an alias
                # for "formula" the case never handled. Fail loudly instead so a
                # future typo can't quietly leave a retired tool installed.
                warn "Cleanup: unknown entry type '$type' for $display — skipped (fix DEPRECATED_TOOLS)"
                ((CLEANUP_SKIPPED++))
                ;;
        esac
    done
    unset _uv_tools _cargo_tools

    # -- Orphaned application support trees ----------------------------------
    # Homebrew removes an app bundle but does not remove its per-user data.
    # Remove only paths for retired apps after the matching app bundle is absent.
    # Prefer Trash so each removal stays recoverable.
    ORPHANED_EDITOR_DIRS=(
        "Cursor|$HOME/.cursor"
        "Cursor|$HOME/Library/Application Support/Cursor"
        "Visual Studio Code|$HOME/.vscode"
        "Visual Studio Code|$HOME/Library/Application Support/Code"
        "Claude|$HOME/Library/Application Support/Claude"
        "Pearcleaner|$HOME/Library/Application Support/Pearcleaner"
        "Shottr|$HOME/Library/Application Support/Shottr"
        "Skim|$HOME/Library/Application Support/Skim"
        "OrbStack|$HOME/.orbstack"
        "OrbStack|$HOME/Library/Application Support/OrbStack"
        # CAUTION: This directory contains mail and account data. Cleanup moves it
        # to Trash only after the Thunderbird application is absent (#578).
        "Thunderbird|$HOME/Library/Thunderbird"
    )
    for entry in "${ORPHANED_EDITOR_DIRS[@]}"; do
        _app="${entry%%|*}"
        _dir="${entry#*|}"
        _pretty="${_dir/#$HOME/\~}"
        if [[ ! -d "$_dir" ]]; then
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if [[ -d "/Applications/${_app}.app" ]]; then
            info "Keeping $_pretty — ${_app} is still installed"
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove orphaned $_pretty (${_app} is not installed)"
        else
            info "Removing orphaned $_pretty (${_app} is not installed)..."
            if installed trash; then
                if trash "$_dir" >> "$LOG_FILE" 2>&1; then
                    ((CLEANUP_COUNT++)); success "$_pretty moved to Trash"
                else
                    error "Failed to remove $_pretty"
                fi
            elif rm -rf "$_dir"; then
                ((CLEANUP_COUNT++)); success "$_pretty removed"
            else
                error "Failed to remove $_pretty"
            fi
        fi
    done
    unset _app _dir _pretty

    # office-py was a generator-owned link into a generator-owned virtual environment.
    # Remove only the exact link target, then remove the isolated environment.
    _office_venv="$HOME/.local/share/dev-setup/office-venv"
    _office_link="$HOME/.local/bin/office-py"
    if [[ -L "$_office_link" && "$(readlink "$_office_link")" == "$_office_venv/bin/python" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove $_office_link"
        elif rm -f "$_office_link"; then
            ((CLEANUP_COUNT++)); success "$HOME/.local/bin/office-py removed"
        else
            error "Failed to remove $_office_link"
        fi
    fi
    if [[ -d "$_office_venv" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove $_office_venv"
        elif installed trash && trash "$_office_venv" >> "$LOG_FILE" 2>&1; then
            ((CLEANUP_COUNT++)); success "office-py environment moved to Trash"
        elif rm -rf "$_office_venv"; then
            ((CLEANUP_COUNT++)); success "office-py environment removed"
        else
            error "Failed to remove $_office_venv"
        fi
    fi
    unset _office_venv _office_link

    # -- Orphaned config and data paths --------------------------------------
    # Uninstalling a CLI removes its binary, not its per-user data. This sweep
    # runs after package removal and requires the owning command to be absent.
    #
    # ~/.docker is deliberately absent. Docker clients and container runtimes
    # share its contexts and registry credentials. Removing OrbStack does not
    # prove ownership of that shared directory.
    hash -r 2>/dev/null || true
    CONFIG_ORPHANS=(
        "aerc|$HOME/.config/aerc|removed"
        "khal|$HOME/.config/khal|removed"
        "vdirsyncer|$HOME/.config/vdirsyncer|removed"
        "hx|$HOME/.config/helix|micro"
        "cmus|$HOME/.config/cmus|cliamp"
        "kew|$HOME/.config/kew|cliamp"
        "glow|$HOME/.config/glow|leaf"
        "rovr|$HOME/.config/rovr|Yazi"
        "nnn|$HOME/.config/nnn|Yazi"
        "starlit|$HOME/.config/starlit|removed"
        "tmux|$HOME/.tmux.conf|zellij"
        "aerospace|$HOME/.aerospace.toml|native Spaces + tiling"
        "nvm|$HOME/.nvm|mise"
        "pyenv|$HOME/.pyenv|mise"
        # CAUTION: ~/.pi holds content this generator never wrote — hand-placed
        # extensions, auth.json and session history. Removal is deliberate (#513)
        # and is guarded the way section 15 requires: this sweep only fires when
        # `pi` is absent from PATH, and it moves the directory to the Trash rather
        # than deleting it, so it stays recoverable from Finder until emptied.
        "pi|$HOME/.pi|omp"
        "tiki|$HOME/.config/tiki|plain Markdown + reminders"
        "ollama|$HOME/.ollama|llama.cpp"
        "vhs|$HOME/.config/vhs|removed"
        "wiper|$HOME/.config/wiper|removed"
        "doxx|$HOME/.config/doxx|removed"
        "apw|$HOME/.config/apw|removed"
        "act3|$HOME/.config/act3|removed"
        "manly|$HOME/.config/manly|removed"
        "bmm|$HOME/.local/share/bmm|removed"
        "bmm|$HOME/.config/bmm|removed"
        "glab|$HOME/.config/glab-cli|removed"
        "gk|$HOME/.local/share/GitKrakenCLI|removed"
        "gk|$HOME/.local/share/gk|removed"
        "gk|$HOME/.gitkraken|removed"
        "asciinema|$HOME/.config/asciinema|removed"
        "jolt|$HOME/.config/jolt|removed"
        "copilot|$HOME/.copilot|omp"
        "turbo|$HOME/.cache/turbo|removed"
        "aichat|$HOME/.config/aichat|removed"
        "lighthouse|$HOME/.cache/lighthouse|removed"
        "newsboat|$HOME/.newsboat|removed"
        "gws|$HOME/.config/gws|removed"
        "gcloud|$HOME/.config/gcloud|removed"
        # CAUTION: These paths can contain credentials and session history that
        # the generator did not write. Removal is explicit under --cleanup and
        # uses Trash after both Claude command providers are absent.
        "claude|$HOME/.claude|removed"
        "claude|$HOME/.claude.json|removed"
        "sketchybar|$HOME/.config/sketchybar|removed"
        "cz|$HOME/.czrc|git template + omp"
        "freshclam|$HOME/Library/LaunchAgents/com.freshclam.update.plist|removed"
        "k9s|$HOME/.config/k9s|removed"
        "stern|$HOME/.config/stern|removed"
        "tflint|$HOME/.tflint.hcl|removed"
    )
    for entry in "${CONFIG_ORPHANS[@]}"; do
        _tool="${entry%%|*}"
        _rest="${entry#*|}"
        _dir="${_rest%%|*}"
        _repl="${_rest##*|}"
        _pretty="${_dir/#$HOME/\~}"
        if [[ ! -e "$_dir" ]]; then
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if command -v "$_tool" &>/dev/null; then
            info "Keeping $_pretty — $_tool is still installed"
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove orphaned config $_pretty ($_tool -> $_repl)"
        else
            info "Removing orphaned config $_pretty ($_tool -> $_repl)..."
            if installed trash; then
                if trash "$_dir" >> "$LOG_FILE" 2>&1; then
                    ((CLEANUP_COUNT++)); success "$_pretty moved to Trash"
                else
                    error "Failed to remove $_pretty"
                fi
            elif rm -rf "$_dir"; then
                ((CLEANUP_COUNT++)); success "$_pretty removed"
            else
                error "Failed to remove $_pretty"
            fi
        fi
    done
    unset _tool _rest _dir _repl _pretty

    # SurgeDM stores its queue, token, logs, and settings together. The generator
    # did not write these files, so package retirement does not prove that the
    # directory is disposable. Keep it for manual review instead of risking user data.
    _surgedm_data="$HOME/Library/Application Support/surge"
    if [[ -e "$_surgedm_data" ]] && ! command -v surge &>/dev/null; then
        info "Keeping $_surgedm_data. Review and remove it manually if SurgeDM data is no longer needed."
    fi
    unset _surgedm_data

    # -- Orphaned Homebrew node_modules ---------------------------------------
    # #344 removed Homebrew's node and left its global npm tree behind: 19
    # packages and 1.6 GB on the maintainer's machine, plus 31 live symlinks in
    # $HOMEBREW_PREFIX/bin still pointing into it. They resolve, and their
    # shebangs find node through PATH, so they execute the OLD tree's code
    # against mise's node. Versions matched at the time this was found, which is
    # timing rather than safety: npm_global_install only ever writes to mise's
    # tree, so the two diverge at the first upgrade and PATH order decides which
    # one runs. That is #343, and the shape #513 found with pi under two managers.
    #
    # Not a CONFIG_ORPHANS row: that list is per-tool config directories keyed on
    # a binary name, and this is one prefix-wide sweep with a different guard.
    #
    # The guard is that the prefix has NO node. lib/node_modules is npm's global
    # root for that prefix's node, so while the formula is installed the tree is
    # live and must not be touched.
    _brew_prefix="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null)}"
    _node_modules="$_brew_prefix/lib/node_modules"
    if [[ -n "$_brew_prefix" && -d "$_node_modules" ]]; then
        if [[ -x "$_brew_prefix/bin/node" ]] || brew list --formula 2>/dev/null | grep -qxE 'node|node@[0-9.]+'; then
            info "Keeping $_node_modules — Homebrew's node is installed, so it is that node's live global root"
        else
            _nm_count=$(find "$_node_modules" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
            _nm_size=$(/usr/bin/du -sh "$_node_modules" 2>/dev/null | cut -f1)
            mapfile -t _nm_links < <(orphaned_brew_node_links "$_brew_prefix")
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would remove orphaned Homebrew node tree: $_node_modules (${_nm_count} packages, ${_nm_size:-unknown})"
                info "[DRY RUN] Would remove ${#_nm_links[@]} bin symlink(s) pointing into it (Homebrew's node is gone)"
            else
                info "Removing orphaned Homebrew node tree (${_nm_count} packages, ${_nm_size:-unknown}) — Homebrew's node is gone..."
                # Links first: a link into a directory that no longer exists is a
                # worse state than either end of this operation on its own.
                for _l in "${_nm_links[@]}"; do
                    [[ -n "$_l" ]] || continue
                    rm -f "$_l" 2>/dev/null || warn "Could not remove $_l"
                done
                [[ ${#_nm_links[@]} -gt 0 ]] && info "Removed ${#_nm_links[@]} orphaned bin symlink(s)"
                if installed trash; then
                    if trash "$_node_modules" >> "$LOG_FILE" 2>&1; then
                        ((CLEANUP_COUNT++)); success "Homebrew node tree moved to Trash (${_nm_size:-unknown} — empty the Trash to reclaim the space)"
                    else
                        error "Failed to remove $_node_modules"
                    fi
                elif rm -rf "$_node_modules"; then
                    ((CLEANUP_COUNT++)); success "Homebrew node tree removed (${_nm_size:-unknown} reclaimed)"
                else
                    error "Failed to remove $_node_modules"
                fi
            fi
            unset _nm_count _nm_size _nm_links _l
        fi
    fi
    unset _brew_prefix _node_modules

    # -- Orphaned taps --------------------------------------------------------
    # Uninstalling a formula leaves its tap cloned and trusted forever. Only taps
    # THIS script previously used are listed — untapping anything that merely has
    # zero installed packages would delete taps the user added by hand. The
    # zero-package check is still enforced, so a tap the user has since installed
    # something else from is left alone.
    DEPRECATED_TAPS=(
        "nikitabobko/tap|AeroSpace"
        "snyk/tap|snyk"
        "boolean-maybe/tap|tiki"
        "oven-sh/bun|bun"
        "dhth/tap|act3 and bmm"
        "jordond/tap|jolt"
        "ikebastuz/wiper|wiper"
        "FelixKratz/formulae|SketchyBar"
        "bendews/tap|apw"
        "keith/formulae|reminders-cli"
        "neilotoole/sq|sq"
        "kdabir/tap|has"
        "gateway-of-last-resort/tap|keyward"
        "lazynop/tap|lazyenv"
        "terraform-linters/tap|tflint"
        "surgedm/tap|SurgeDM"
    )
    for entry in "${DEPRECATED_TAPS[@]}"; do
        _tap="${entry%%|*}"
        _why="${entry#*|}"
        if ! brew tap 2>/dev/null | grep -ix "$_tap" >/dev/null; then
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if brew list --full-name 2>/dev/null | grep -i "^${_tap}/" >/dev/null; then
            info "Keeping tap $_tap — still provides installed packages"
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would untap $_tap (was $_why; provides nothing)"
        else
            info "Untapping $_tap (was $_why; provides nothing)..."
            if brew untap "$_tap" >> "$LOG_FILE" 2>&1; then
                XDG_CONFIG_HOME="$HOME/.config" brew untrust --tap "$_tap" >> "$LOG_FILE" 2>&1 || true
                env -u XDG_CONFIG_HOME brew untrust --tap "$_tap" >> "$LOG_FILE" 2>&1 || true
                ((CLEANUP_COUNT++)); success "$_tap untapped and untrusted"
            else
                warn "Could not untap $_tap"
            fi
        fi
    done
    unset _tap _why

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        # Preview what autoremove would reclaim. Note this UNDERSTATES the real run:
        # most orphans only come into existence once the uninstalls above actually
        # happen (removing aider is what orphans python@3.12), and a dry run has
        # removed nothing, so only pre-existing orphans show up here.
        _orphans=$(brew autoremove --dry-run 2>/dev/null | grep -c '^' || true)
        if [[ "${_orphans:-0}" -gt 0 ]]; then
            info "[DRY RUN] Would also remove $_orphans already-orphaned dependency/ies (brew autoremove)"
        else
            info "[DRY RUN] No dependencies are orphaned yet — a real run may orphan more as it uninstalls"
        fi
        unset _orphans
    else
        success "Cleanup complete: $CLEANUP_COUNT removed, $CLEANUP_SKIPPED not found (already clean)"
        if [[ "$CLEANUP_COUNT" -gt 0 ]]; then
            # Uninstalling a formula leaves behind the dependencies it pulled in —
            # removing aider, for instance, orphans python@3.12. `brew cleanup` does
            # NOT touch those: it only purges download caches and outdated versions.
            # `brew autoremove` is what removes them, and it only considers formulae
            # Homebrew recorded as installed AS A DEPENDENCY — anything installed on
            # request is never touched, so this cannot remove a tool you asked for.
            # Run before cleanup so the freshly-uninstalled files are purged too.
            info "Removing orphaned dependencies (brew autoremove)..."
            brew autoremove >> "$LOG_FILE" 2>&1 || warn "brew autoremove failed — see $LOG_FILE"
            info "Running brew cleanup..."
            brew cleanup >> "$LOG_FILE" 2>&1 || true
        fi
    fi
    exit 0
fi

# -- Handle --verify (does each tool actually READ what we generate?) ---------
# CI proves every generated file PARSES (.github/workflows/lint.yml). It cannot
# prove anything READS it. #329 (asciinema) and #332 (ngrok) were both well-formed
# files sitting at paths their tool never looks at, and both sailed through CI for
# releases — one of them printing a warning on every invocation the whole time.
# That question can only be answered where the tools are installed, which is why
# this is a script mode and not a CI job (#331).
#
# VERIFY_TARGETS rows: mode|label|path|command
#
#   validate  Run the tool's own validator with NO path argument. Success proves
#             the tool found our file at ITS default location and accepted it —
#             the path question and the format question answered in one shot.
#             This is the strongest form; prefer it whenever a tool offers one.
#   template  Same command, but the file is a deliberately incomplete seed. A
#             borgmatic config with no `repositories` cannot validate until the
#             user fills it in, so a failure there is the design, not a fault.
#             Reported as SEED — a check that always fails is one people learn to
#             skim past, which is how the blocking WARNING in #327 survived.
#   path      No validator, but the tool will say where it looks. Capture that and
#             compare it with where we write. This is the cheap check that catches
#             the whole drift class: #329, #332 and the k9s skin were all path
#             drift, none of them syntax.
#   unchecked Neither is available. Listed by name so the gap stays visible rather
#             than being quietly counted as a pass.
#
# The command field may contain '|' — `read` puts the remainder in the last var.
if [[ "$VERIFY" == "true" ]]; then
    echo ""
    echo -e "${BOLD}${CYAN}Verifying generated config against the installed tools${NC}"
    echo ""

    _verify_lnav() {
        # lnav refuses /dev/null ("unable to open file ... Invalid argument"), so
        # it needs a real file to open before it will answer anything (#518).
        local probe out
        probe="$(mktemp)"; printf 'verify\n' > "$probe"
        out="$(lnav -n -c ':config /ui/theme' "$probe" 2>&1)"
        rm -f "$probe"
        grep -qE '^/ui/theme = "dracula-sakura"' <<<"$out"
    }

    # topgrade and starship can return misleading exit codes. Capture their output
    # and judge the reported parse result. A check that cannot fail is worse than
    # no check because the summary counts it as verified.
    _verify_topgrade() {
        # `--dry-run` executes nothing; it prints the steps. On a config it cannot accept it
        # prints "Failed to deserialize <path>" and does no work at all. ~3s.
        local out; out="$(topgrade --dry-run 2>&1 || true)"
        ! grep -q 'Failed to deserialize' <<<"$out"
    }
    _verify_starship() {
        # `print-config` exits 0 even when it could not parse the file; the error only
        # appears on stderr.
        local out; out="$(starship print-config 2>&1 || true)"
        ! grep -q 'Unable to parse the config file' <<<"$out"
    }

    _verify_kitty() {
        # Kitty has no public validate-config command. Its bundled Python runtime
        # exposes the same loader used at startup and can collect rejected lines.
        kitty +runpy 'import sys; from kitty.config import load_config; bad = []; load_config(sys.argv[1], accumulate_bad_lines=bad); [print(line, file=sys.stderr) for line in bad]; raise SystemExit(bool(bad))' \
            "$HOME/.config/kitty/kitty.conf"
    }


    VERIFY_TARGETS=(
        # `omp config get` prints the EFFECTIVE value, so a pass proves omp read the file
        # at this path and resolved our merged key — not merely that the YAML parses.
        # Reading theme.dark rather than a model role keeps it honest when no
        # GEMINI_API_KEY is set: the theme resolves with no provider reachable at all.
        "validate|omp|$HOME/.omp/agent/config.yml|_verify_output_has 'dracula-sakura' omp config get theme.dark"
        # Parse the installed managed file through fastfetch itself. This catches
        # invalid managed-marker comments that body-only JSON checks cannot see (#561).
        "validate|fastfetch|$HOME/.config/fastfetch/config.jsonc|fastfetch --config '$HOME/.config/fastfetch/config.jsonc' --logo none --structure Title"
        # Asks lnav which theme it RESOLVED, not whether the file parses. A pass
        # means the fragment was found, loaded, and selected (#518).
        "validate|lnav|${XDG_CONFIG_HOME:-$HOME/.config}/lnav/configs/dev-setup/dracula-sakura.json|_verify_lnav"
        "validate|kitty|$HOME/.config/kitty/kitty.conf|_verify_kitty"
        "validate|zellij|$HOME/.config/zellij/config.kdl|_verify_output_has 'Well defined' zellij setup --check"
        # Kiro exposes no headless config validator. CI parses the settings,
        # extension manifest, and theme files.
        "unchecked|Kiro settings|$HOME/Library/Application Support/Kiro/User/settings.json|"
        "unchecked|Kiro theme|$HOME/.kiro/extensions/vixygrey.dracula-sakura-1.0.0/themes/dracula-sakura-color-theme.json|"
        # Yazi has no headless validator or command that reports its config path.
        # Both TOML files carry official schema links for editor validation.
        "unchecked|yazi|$HOME/.config/yazi/theme.toml|"
        "unchecked|eilmeldung|$HOME/.config/eilmeldung/config.toml|"
        "validate|concord|$HOME/.config/concord/config.toml|concord --check-config"
        "unchecked|spotatui|$HOME/.config/spotatui/config.yml|"
        "unchecked|cfait|$HOME/.config/cfait/config.toml|"
        "path|posting|$HOME/.config/posting/config.yaml|posting locate config 2>/dev/null | sed -n '\$p'"
        "validate|ngrok|$HOME/Library/Application Support/ngrok/ngrok.yml|ngrok config check"
        "template|borgmatic|$HOME/.config/borgmatic/config.yaml|borgmatic config validate"
        "path|mise|$HOME/.config/mise/config.toml|mise config ls 2>/dev/null | awk 'NR==1 {print \$1}' | sed \"s|^~|\$HOME|\""
        "path|lazygit|$HOME/.config/lazygit/config.yml|echo \"\$(lazygit --print-config-dir)/config.yml\""
        "path|atuin|$HOME/.config/atuin/config.toml|atuin info 2>/dev/null | awk -F'\"' '/client config:/ {print \$2}'"
        "path|bat|$(bat --config-file 2>/dev/null)|bat --config-file"
        # These two were "unchecked" until #367. Their helpers inspect effective
        # configuration because their exit codes alone cannot prove that the file loaded.
        "validate|starship|$HOME/.config/starship.toml|_verify_starship"
        "validate|topgrade|$HOME/.config/topgrade.toml|_verify_topgrade"
        "unchecked|trippy|$HOME/.config/trippy/trippy.toml|"
        "path|harlequin|$HOME/.harlequin.toml|_verify_harlequin_config"
        "unchecked|gh-dash|$HOME/.config/gh-dash/config.yml|"
        "unchecked|lazydocker|$HOME/.config/lazydocker/config.yml|"
        "unchecked|yt-dlp|$HOME/.config/yt-dlp/config|"
        "unchecked|micro|$HOME/.config/micro/settings.json|"
        "unchecked|croft|$HOME/.config/croft/config.json|"
        # Emeraldian exposes no headless config validator or path command.
        "unchecked|emeraldian|$HOME/Library/Application Support/emeraldian/config.toml|"
        # The remaining path checks ask each tool where it reads, so every row stays
        # correct if the tool moves. This follows the "ask the tool; do not hardcode" rule
        # in AGENTS. The captured path is tilde-normalised on both sides before
        # comparing, so tools that return absolute paths and tools that return
        # `~/...` are compared against the same string. Cheap high-signal
        # additions from #374.
        # $HOME/.gitconfig, NOT the XDG path, and that is deliberate (#505). git
        # writes --global to $XDG_CONFIG_HOME/git/config only when that file
        # exists AND ~/.gitconfig does not; with ~/.gitconfig present it always
        # wins (verified against git 2.55). Every provisioned machine already has
        # one, holding the identity, the includeIf routing and any hand edits, so
        # moving to XDG would mean relocating a file we did not write and cannot
        # prove is ours. This row previously named the XDG path, which nothing
        # writes, so it reported MISSING on every machine forever.
        "path|git|$HOME/.gitconfig|_verify_git_config"
        "path|ssh|$HOME/.ssh/config|_verify_ssh_config"
        "path|npm|$HOME/.npmrc|npm config get userconfig 2>/dev/null | tr -d '\n'; echo"
        "path|pip|$HOME/.config/pip/pip.conf|_verify_pip_config"
        "path|gem|$HOME/.gemrc|_verify_gem_config"
        # Was wrong twice and could never pass (#505): it named `direnvrc`, which
        # this script does not write, and its extractor looked for a `DirenvRC:`
        # field that `direnv status` does not emit. A `validate` row is also the
        # stronger question here — `whitelist.prefix` is EMPTY (`[]`) in a default
        # direnv and non-empty only because our direnv.toml set it, so a pass
        # proves direnv loaded our file rather than merely looked in its folder.
        "validate|direnv|$HOME/.config/direnv/direnv.toml|_verify_output_has '^whitelist[.]prefix [[].+[]]' direnv status ."
        "path|gh|$HOME/.config/gh/config.yml|_verify_gh_config"
        # ripgrep only reads its config when RIPGREP_CONFIG_PATH is exported — a self-
        # contained trap. The export lives in the generated ~/.zshrc, so a row that
        # fires under --verify would always look MISSING on a non-interactive shell.
        # Leave the path row in place so it CAN run when the env is set, but the row
        # is gated on the env var so it skips itself otherwise, instead of failing.
        "path|ripgrep|$HOME/.config/ripgrep/config|[[ -n \"\${RIPGREP_CONFIG_PATH:-}\" ]] && echo \"\$RIPGREP_CONFIG_PATH\" || true"
    )

    # Helpers for path-mode rows above. Keep them near VERIFY_TARGETS so the row and
    # its helper are edited together. All three echo a single path on stdout, ending
    # in `echo` to guarantee a trailing newline (some tools print without one and the
    # comparison would fail on the missing byte).
    _verify_git_config() {
        # --show-origin prints `file:/path/to/git/config\tvalue`. Pull the file field
        # and strip the `file:` prefix so it matches the `$HOME/.config/git/config`
        # we wrote. The user's gitconfig may live at ~/.gitconfig instead — that is
        # surfaced as a real FAIL (the row reports both paths), which is the point.
        git config --show-origin --get core.hooksPath 2>/dev/null \
            | awk -F'\t' 'NR==1 {sub(/^file:/, "", $1); print $1}'
    }
    _verify_pip_config() {
        # pip config debug emits `user:` followed by two file lines. The second is the
        # `$HOME/.config/pip/pip.conf` we write; the first is the legacy `~/.pip/`
        # location pip also consults. Match on the .config/ path so we pick ours.
        pip config debug 2>/dev/null \
            | awk '/^user:/{u=1; next} u && /\.config\/pip\/pip\.conf/ {print $1; exit}' \
            | tr -d ,; echo
    }
    # OpenSSH 10 dropped the `configfile` line from `ssh -G` output, so the
    # issue's `ssh -G … | awk '/^configfile/'` advice no longer works. Ask `ssh`
    # itself anyway (it still prints every other resolved option) and fall back to
    # a file-existence probe on $HOME/.ssh/config when the line is absent. The
    # file check is the same shape lazygit uses — both confirm "the path the tool
    # reads" without depending on a specific output field.
    _verify_ssh_config() {
        local cf
        cf="$(ssh -G git@127.0.0.1 2>/dev/null | awk '/^configfile/ {print $2; exit}')"
        if [[ -n "$cf" ]]; then
            echo "$cf"
        elif [[ -f "$HOME/.ssh/config" ]]; then
            echo "$HOME/.ssh/config"
        fi
    }
    # RubyGems does not surface the gemrc path from `gem env` at all on stock macOS
    # (it only lists INSTALLATION DIRECTORY, USER INSTALLATION DIRECTORY, and SYSTEM
    # CONFIGURATION DIRECTORY — none of which is the user's gemrc). The cheapest
    # probe is the file itself; if it is missing the row already fails earlier on
    # the `[[ -e "$path" ]]` check.
    _verify_gem_config() {
        [[ -f "$HOME/.gemrc" ]] && echo "$HOME/.gemrc"
    }
    _verify_harlequin_config() {
        local out
        out="$(harlequin --help 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
        if grep -q '\.harlequin\.toml in the current directory and' <<<"$out" \
            && grep -q 'the home directory (~) and merges them' <<<"$out"; then
            echo "$HOME/.harlequin.toml"
        fi
    }
    # `gh` does not expose a "where is your config file" command (the closest,
    # `gh config get config-dir`, returns "could not find key 'config-dir'" on
    # every release tried). It also ignores `XDG_CONFIG_HOME` and hardcodes
    # `$HOME/.config/gh` unless `GH_CONFIG_DIR` is set. So the only honest
    # check is the file itself — same shape as ngrok and VS Code (#334), and
    # exactly the class this row was added to catch.
    _verify_gh_config() {
        local d="${GH_CONFIG_DIR:-$HOME/.config/gh}"
        [[ -f "$d/config.yml" ]] && echo "$d/config.yml"
    }

    VERIFY_OK=0 VERIFY_BAD=0 VERIFY_SEED=0 VERIFY_SKIP=0 VERIFY_GAP=0

    for entry in "${VERIFY_TARGETS[@]}"; do
        IFS='|' read -r mode label path cmd <<< "$entry"

        # A config for a tool that isn't installed is not a finding — the category
        # may simply have been skipped. Say so and move on.
        if ! installed "$label" && [[ "$mode" != "unchecked" ]]; then
            printf "  ${DIM}%-12s %s${NC}\n" "SKIP" "$label — not installed"
            ((VERIFY_SKIP++)); continue
        fi

        if [[ -n "$path" && ! -e "$path" ]]; then
            printf "  ${RED}%-12s${NC} %s — nothing at %s\n" "MISSING" "$label" "$path"
            printf "               ${DIM}re-run the script to generate it${NC}\n"
            ((VERIFY_BAD++)); continue
        fi

        case "$mode" in
            validate)
                if eval "$cmd" >/dev/null 2>&1; then
                    printf "  ${GREEN}%-12s${NC} %s — its own validator accepts the file it found\n" "OK" "$label"
                    ((VERIFY_OK++))
                else
                    printf "  ${RED}%-12s${NC} %s — %s rejected or never found its config\n" "FAIL" "$label" "$label"
                    printf "               ${DIM}we write: %s${NC}\n" "$path"
                    ((VERIFY_BAD++))
                fi
                ;;
            template)
                if eval "$cmd" >/dev/null 2>&1; then
                    printf "  ${GREEN}%-12s${NC} %s — validates\n" "OK" "$label"
                    ((VERIFY_OK++))
                else
                    printf "  ${YELLOW}%-12s${NC} %s — seed template, incomplete until you fill it in\n" "SEED" "$label"
                    ((VERIFY_SEED++))
                fi
                ;;
            path)
                _vp="$(eval "$cmd" 2>/dev/null | head -1)"
                # Normalise a leading `~/` on either side to `$HOME/` so the row is
                # stable across shells that return absolute paths (ssh, gem, pip) and
                # shells that return tildes (npm, gh). Without this, half the rows
                # would always FAIL on the same machine.
                _vp="${_vp/#\~/$HOME}"
                _cmp="$path"
                _cmp="${_cmp/#\~/$HOME}"
                if [[ -z "$_vp" ]]; then
                    printf "  ${YELLOW}%-12s${NC} %s — could not read its config path back\n" "UNKNOWN" "$label"
                    ((VERIFY_GAP++))
                elif [[ "$_vp" == "$_cmp" ]]; then
                    printf "  ${GREEN}%-12s${NC} %s — reads the path we write\n" "OK" "$label"
                    ((VERIFY_OK++))
                else
                    printf "  ${RED}%-12s${NC} %s — reads a DIFFERENT path than we write\n" "FAIL" "$label"
                    printf "               ${DIM}we write:  %s${NC}\n" "$_cmp"
                    printf "               ${DIM}%s reads: %s${NC}\n" "$label" "$_vp"
                    ((VERIFY_BAD++))
                fi
                ;;
            unchecked)
                printf "  ${DIM}%-12s %s — no validator and no way to ask; syntax only (CI)${NC}\n" "UNVERIFIED" "$label"
                ((VERIFY_GAP++))
                ;;
            *)
                # Same rule as DEPRECATED_TOOLS (#242): an unrecognized mode must be
                # loud. A row that silently matches no branch reads as "verified".
                warn "Verify: unknown mode '$mode' for $label — skipped (fix VERIFY_TARGETS)"
                ((VERIFY_SKIP++))
                ;;
        esac
    done

    # The inventory is the source of truth for every generated-output policy.
    # A runtime verifier belongs to an inventory row, so this count is the actual
    # set difference rather than a subtraction between unrelated path sets (#534).
    _inventory="$SETUP_SCRIPT_DIR/../config/generated-outputs.tsv"
    if [[ -f "$_inventory" ]]; then
        _vw_total="$(awk -F'|' 'NR > 1 && $3 != "superseded" {n++} END {print n+0}' "$_inventory")"
        _vw_gap="$(awk -F'|' 'NR > 1 && $3 != "superseded" && $7 == "none" {n++} END {print n+0}' "$_inventory")"
    else
        _vw_total=0
        _vw_gap=0
        warn "Generated-output inventory is missing: $_inventory"
    fi

    echo ""
    echo -e "  ${GREEN}${BOLD}Verified:${NC}    $VERIFY_OK"
    echo -e "  ${RED}${BOLD}Failed:${NC}      $VERIFY_BAD"
    echo -e "  ${YELLOW}${BOLD}Seed:${NC}        $VERIFY_SEED"
    echo -e "  ${DIM}Unverified:  $VERIFY_GAP${NC}"
    echo -e "  ${DIM}Skipped:     $VERIFY_SKIP${NC}"
    echo -e "  ${DIM}Files not verified: $_vw_gap (of $_vw_total)${NC}"
    echo ""
    if [[ "$VERIFY_BAD" -gt 0 ]]; then
        echo -e "${RED}A FAIL means the file is fine and the tool is not reading it.${NC}"
        echo -e "${DIM}That is the #329/#332 shape: valid config, wrong address, no error anywhere.${NC}"
        echo ""
        exit 1
    fi
    exit 0
fi

# GOBIN was exported at the top of the file (it has to be, so it lands on this run's
# PATH before anything resolves a Go tool), but creating the directory is a change to
# the machine and so waits until here, where --dry-run has been parsed (#380).
ensure_dir "$GOBIN"

preflight
acquire_lock

# Truncate state file on a fresh run so it doesn't accumulate duplicates across
# repeated invocations. Preserved when --resume is passed so previous successes
# can short-circuit. (Issue #28)
if [[ "$RESUME" != "true" ]]; then
    : > "$STATE_FILE"
fi

# =============================================================================
# PREREQUISITES
# =============================================================================
# Gated like every other category (#324). It was the ONE member of ALL_CATEGORIES
# with no `should_run` call, so `--skip prerequisites` passed validation — the
# error message even lists it as valid — and was then discarded in silence:
# Xcode, Homebrew and `brew update` all ran anyway, with nothing said. `--only
# prerequisites` worked, but only by accident of the section always running.
#
# Skipping is refused when the machine does not already HAVE them, because
# everything below needs `brew` and the failure would otherwise land much later
# as a wall of confusing errors. That refusal is loud, which is the whole point.
#
# NOT `should_run "prerequisites"`, deliberately — prerequisites are a
# PRECONDITION, not a peer category. Under `should_run`, `--only core` would stop
# installing Homebrew, so `--only core` on a fresh machine would refuse to run at
# all instead of bootstrapping itself as it does today. The rule is narrower than
# should_run's: run unless the user *explicitly* asked to skip.
_prereqs_skipped=false
for _c in "${SKIP_CATEGORIES[@]}"; do
    [[ "$_c" == "prerequisites" ]] && _prereqs_skipped=true
done
unset _c
if [[ "$_prereqs_skipped" != "true" ]]; then
banner "Prerequisites"

if xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools already installed"
else
    info "Installing Xcode Command Line Tools..."
    xcode-select --install
    # Wait for installation to complete
    until xcode-select -p &>/dev/null; do
        sleep 5
    done
    success "Xcode Command Line Tools installed"
fi

# -----------------------------------------------------------------------------
# Homebrew
# -----------------------------------------------------------------------------
if ! installed brew; then
    info "Installing Homebrew..."
    if run_remote_installer \
        "Homebrew installer" \
        "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
        "${HOMEBREW_INSTALLER_SHA256:-}" \
        /bin/bash; then
        # Add to path for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        BREW_INSTALLED_THIS_RUN=true
        success "Homebrew installed"
    else
        error "Failed to install Homebrew (${REMOTE_INSTALLER_ERROR:-unknown error})"
        exit 1
    fi
else
    warn "Homebrew already installed"
    brew_update_if_due
fi

# Prevent brew from auto-updating on every install (we already updated above)
export HOMEBREW_NO_AUTO_UPDATE=1

# GNU coreutils (Linux-compatible sed, tar, awk, grep for script portability)
brew_install_batch \
    "coreutils|coreutils (GNU core utilities)" \
    "gnu-sed|gnu-sed (Linux-compatible sed)" \
    "gnu-tar|gnu-tar (Linux-compatible tar)" \
    "gawk|gawk (GNU awk)" \
    "findutils|findutils (GNU find, xargs)" || true
brew_install "coreutils" "coreutils (GNU core utilities)"
brew_install "gnu-sed" "gnu-sed (Linux-compatible sed)"
brew_install "gnu-tar" "gnu-tar (Linux-compatible tar)"
brew_install "gawk" "gawk (GNU awk)"
brew_install "findutils" "findutils (GNU find, xargs)"

else
    # --skip prerequisites, honoured — but only on a machine that already has them.
    _missing_prereqs=()
    xcode-select -p &>/dev/null || _missing_prereqs+=("Xcode Command Line Tools")
    command -v brew &>/dev/null || _missing_prereqs+=("Homebrew")
    if (( ${#_missing_prereqs[@]} )); then
        error "Cannot skip prerequisites: ${_missing_prereqs[*]} not installed."
        echo "  Everything after this point needs them. Re-run without"
        echo "  '--skip prerequisites' once, then skip it on later runs."
        exit 1
    fi
    unset _missing_prereqs
    info "Skipping prerequisites — Xcode CLI Tools and Homebrew already present"
    # Normally exported by the section above. Without it every brew_install below
    # triggers an auto-update, which is the slow networked work that skipping
    # prerequisites is most often meant to avoid — so skipping it must not cause
    # MORE of it.
    export HOMEBREW_NO_AUTO_UPDATE=1
fi

# =============================================================================
if should_run "core"; then
banner "Core Development"

# mise (universal version manager — replaces nvm, pyenv, rbenv in one tool)
brew_install "mise" "mise (universal version manager — Node, Python, Go, Ruby, etc.)"

# Activate mise for this script session
if installed mise; then
    eval "$(mise activate bash 2>/dev/null)" || true
fi

# Install Node.js LTS and Python via mise
if installed mise; then
    if ! is_done "install:mise-node"; then
    if ! mise ls node 2>/dev/null | grep -q "lts"; then
        info "Installing Node.js LTS via mise..."
        if [[ "$DRY_RUN" != "true" ]]; then
            if mise install node@lts >> "$LOG_FILE" 2>&1 && mise use --global node@lts >> "$LOG_FILE" 2>&1; then
                success "Node.js LTS installed via mise"
            else
                error "Failed to install Node.js LTS via mise (check $LOG_FILE)"
            fi
        fi
    else
        warn "Node.js LTS already installed via mise"
    fi
    mark_done "install:mise-node"
    fi

    # Put the Node mise just installed on THIS script's PATH (#343). `mise activate bash`
    # above registers a PROMPT_COMMAND hook, and PROMPT_COMMAND never fires in a
    # non-interactive script — so PATH does not pick up node until the next shell. Without
    # this, `installed npm` is false for the rest of the run whenever the invoking shell
    # did not already have mise's node in front, and every later npm_global_install
    # silently no-ops while the run still reports "Failed: 0". `mise which` resolves
    # the real binary without needing the hook.
    if [[ "$DRY_RUN" != "true" ]]; then
        _mise_node="$(mise which node 2>/dev/null || true)"
        if [[ -n "$_mise_node" ]]; then
            _mise_node_bin="$(dirname "$_mise_node")"
            export PATH="$_mise_node_bin:$PATH"
            hash -r 2>/dev/null || true
        fi
        unset _mise_node _mise_node_bin
    fi


    if ! is_done "install:mise-python"; then
    if ! mise ls python 2>/dev/null | grep -q "$PYTHON_VERSION"; then
        info "Installing Python $PYTHON_VERSION via mise..."
        if [[ "$DRY_RUN" != "true" ]]; then
            if mise install "python@$PYTHON_VERSION" >> "$LOG_FILE" 2>&1 && mise use --global "python@$PYTHON_VERSION" >> "$LOG_FILE" 2>&1; then
                success "Python $PYTHON_VERSION installed via mise"
            else
                error "Failed to install Python $PYTHON_VERSION via mise (check $LOG_FILE)"
            fi
        fi
    else
        warn "Python $PYTHON_VERSION already installed via mise"
    fi
    mark_done "install:mise-python"
    fi

    # Ensure mise shims are in PATH for the rest of this script
    eval "$(mise env 2>/dev/null)" || true
fi

brew_install "go" "Go (lang)"
brew_install "uv" "uv (fast Python package manager — 10-100x faster than pip)"
# PyYAML is a library rather than a user-facing CLI, so keep it out of the main
# interpreter and expose a tiny dedicated helper Python instead. This mirrors the
# office-py pattern: local scripts and ad hoc one-liners can `import yaml` without
# teaching the machine to `pip install` into the global runtime this setup pins via mise.
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create PyYAML helper venv (PyYAML) -> yaml-py"
elif installed uv; then
    YAML_VENV="$HOME/.local/share/dev-setup/yaml-venv"
    if [[ -x "$YAML_VENV/bin/python" ]] && "$YAML_VENV/bin/python" -c 'import yaml' 2>/dev/null; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$YAML_VENV/bin/python" "$HOME/.local/bin/yaml-py"
        warn "yaml-py venv already present"
    else
        info "Creating PyYAML helper venv..."
        if uv venv --python 3.13 "$YAML_VENV" >> "$LOG_FILE" 2>&1 \
            && uv pip install --python "$YAML_VENV/bin/python" PyYAML >> "$LOG_FILE" 2>&1; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$YAML_VENV/bin/python" "$HOME/.local/bin/yaml-py"
            success "yaml-py ready (PyYAML helper Python for local YAML scripts)"
        else
            warn "Could not create PyYAML helper venv"
        fi
    fi
else
    warn "Skipping PyYAML helper venv — uv not installed"
fi
brew_install "jq" "jq (JSON processor)"
brew_install "direnv" "direnv (per-project env vars)"
brew_install "cmake" "CMake"
brew_install "pkgconf" "pkgconf (provides pkg-config; pkg-config was renamed to pkgconf in homebrew-core)"

# Rust (rustup manages the toolchain — installs rustc, cargo, etc.)
progress
if ! is_done "install:rust"; then
if ! installed rustup; then
    info "Installing Rust via rustup..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: Rust via rustup"
    else
        if run_remote_installer \
            "rustup installer" \
            "https://sh.rustup.rs" \
            "${RUSTUP_INSTALLER_SHA256:-}" \
            sh -- -y --no-modify-path; then
            source "$HOME/.cargo/env" 2>/dev/null || true
            success "Rust installed via rustup"
        else
            error "Failed to install Rust via rustup (${REMOTE_INSTALLER_ERROR:-check $LOG_FILE})"
        fi
    fi
else
    warn "Rust (rustup) already installed"
fi
mark_done "install:rust"
fi

# Miri is available only as a nightly rustup component.
rustup_component_install nightly miri cargo-miri Miri


# pnpm
progress
if ! is_done "install:pnpm"; then
if ! installed pnpm; then
    info "Installing pnpm..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: pnpm via upstream installer"
    else
    if run_remote_installer \
        "pnpm installer" \
        "https://get.pnpm.io/install.sh" \
        "${PNPM_INSTALLER_SHA256:-}" \
        bash; then
        success "pnpm installed"
    else
        error "Failed to install pnpm (${REMOTE_INSTALLER_ERROR:-check $LOG_FILE})"
    fi
    fi  # DRY_RUN — this block downloads and EXECUTES a remote installer (#380)
else
    warn "pnpm already installed"
fi
mark_done "install:pnpm"
fi

# -- Verify all runtimes are in PATH for the rest of the script ----------------
info "Verifying runtime paths..."
# Go (brew puts it in PATH automatically, but verify)
if ! installed go && [[ -d "/usr/local/go/bin" ]]; then
    export PATH="/usr/local/go/bin:$PATH"
fi
# Rust/cargo
if ! installed cargo && [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env" 2>/dev/null || true
fi
# pnpm
if ! installed pnpm && [[ -d "$HOME/.local/share/pnpm" ]]; then
    export PATH="$HOME/.local/share/pnpm:$PATH"
fi
# Report what's available
for tool in node npm go cargo rustc pnpm uv; do
    if installed "$tool"; then
        log "RUNTIME: $tool found at $(which "$tool")"
    else
        log "RUNTIME: $tool NOT found in PATH"
    fi
done

fi  # core

# =============================================================================
if should_run "git"; then
banner "Git & GitHub"

brew_install_batch \
    "git|Git" \
    "gh|GitHub CLI" \
    "git-delta|delta (better git diffs)" \
    "gnupg|GnuPG (commit signing)" \
    "pinentry-mac|pinentry-mac (GPG passphrase)" \
    "lazygit|lazygit (terminal UI for git)" \
    "git-absorb|git-absorb (auto-fixup commits)" \
    "pre-commit|pre-commit (git hook framework)" || true
brew_install "git" "Git"
brew_install "gh" "GitHub CLI"
brew_install "git-delta" "delta (better git diffs)"
brew_install "gnupg" "GnuPG (commit signing)"
brew_install "pinentry-mac" "pinentry-mac (GPG passphrase)"
brew_install "lazygit" "lazygit (terminal UI for git)"
brew_install "git-absorb" "git-absorb (auto-fixup commits)"

# pre-commit
brew_install "pre-commit" "pre-commit (git hook framework)"

# Configure delta as default git pager if not already set
if ! git config --global core.pager | grep -q delta 2>/dev/null; then
    info "Configuring delta as git pager..."
    git_global core.pager delta
    git_global interactive.diffFilter "delta --color-only"
    git_global delta.navigate true
    git_global delta.side-by-side true
    git_global merge.conflictstyle diff3
    configured "delta configured as git pager"
fi

fi  # git

# =============================================================================
if should_run "aws"; then
banner "AWS & CDK"

brew_install "awscli" "AWS CLI v2"
brew_install "aws-sam-cli" "AWS SAM CLI"
brew_install "cfn-lint" "CloudFormation Linter"

# Session Manager Plugin
brew_cask_install "session-manager-plugin" "AWS SSM Session Manager Plugin"

# Granted (multi-account credential switching) — provides `granted` + `assume`.
# Trust its tap, then install via the helper (honors DRY_RUN + existence checks).
# Trust the tap OUTSIDE the installed-check. It used to sit in the `else`, so on a
# machine that already had granted the branch never ran, the tap stayed untrusted
# forever, and Homebrew silently ignored every formula and cask in it — including
# updates to granted itself. `brew doctor` reported it on every run (#298). Trusting
# is idempotent, so doing it unconditionally costs nothing.
trust_tap common-fate/granted
if installed granted || installed assume; then
    warn "Granted already installed"
    progress
else
    brew_install "granted" "Granted (AWS SSO credential switching — granted + assume)"
fi

# AWS CDK (via npm)
if installed npm; then
    npm_global_install "aws-cdk" "AWS CDK CLI"
else
    progress  # keep progress bar accurate when npm unavailable
fi

# -- AWS TUIs (k9s-style, per service) --
brew_install "e1s" "e1s (ECS TUI — clusters/services/tasks, exec, logs, port-forward)"
brew_install "stu" "stu (S3 TUI — browse/preview/download buckets)"
# e2c (EC2 TUI) — young project; not on Homebrew, install via Go.
go_install github.com/nlamirault/e2c/cmd/e2c@latest e2c "e2c (EC2 TUI)"
# claws — broad all-AWS TUI (young); cask from the clawscli tap.
trust_tap clawscli/tap
brew_cask_install "clawscli/tap/claws" "claws (all-AWS TUI — ~70 services, k9s-style; young project)"

# -- AWS CLIs --
brew_install "s5cmd" "s5cmd (massively parallel S3 CLI — 10-30x faster than 'aws s3' for bulk)"
brew_install "dynein" "dynein (ergonomic DynamoDB CLI — awslabs; shorthand ops, import/export)"
brew_install "steampipe" "steampipe (query live AWS with SQL — inventory & posture)"
# steampipe AWS plugin (one-time)
if [[ "$DRY_RUN" != "true" ]] && installed steampipe && ! is_done "config:steampipe-aws"; then
    steampipe plugin install aws >> "$LOG_FILE" 2>&1 \
        && success "steampipe AWS plugin installed" || warn "Could not install steampipe aws plugin (run: steampipe plugin install aws)"
    mark_done "config:steampipe-aws"
fi
# iamlive — generate least-privilege IAM policies from observed API calls (tap).
trust_tap iann0036/iamlive
brew_install "iann0036/iamlive/iamlive" "iamlive (generate least-privilege IAM policies from observed API calls)"

fi  # aws

# =============================================================================
if should_run "iac"; then
banner "Infrastructure as Code"

brew_install "terraform-docs" "terraform-docs (auto-generate module docs from variables/outputs)"
brew_install "checkov" "checkov (IaC static analysis — Terraform, CloudFormation, Kubernetes, Dockerfile)"
# Note: tfsec was folded into trivy (installed under 'security'). Run `trivy config .`
# instead — same Terraform misconfig coverage, broader scan surface.

fi  # iac

# =============================================================================
if should_run "security"; then
banner "Security & Secrets"

# Secret management
brew_install_batch \
    "age|age (modern file encryption)" \
    "gitleaks|gitleaks (fast git secret scanning — great for CI/pre-commit)" \
    "trivy|trivy (container & IaC vulnerability scanning)" \
    "semgrep|semgrep (static analysis — bugs & security issues)" \
    "cosign|cosign (sign & verify container images)" || true
brew_install "age" "age (modern file encryption)"
cargo_install "chamber-tui" chamber \
    "chamber (local encrypted secrets manager and TUI)" --locked
brew_cask_install "bitwarden" "Bitwarden (password manager)"

# Code & dependency security
brew_install "gitleaks" "gitleaks (fast git secret scanning — great for CI/pre-commit)"
brew_install "trivy" "trivy (container & IaC vulnerability scanning)"
brew_install "semgrep" "semgrep (static analysis — bugs & security issues)"
brew_install "cosign" "cosign (sign & verify container images)"

# Network security
brew_install "mkcert" "mkcert (local HTTPS certs for dev)"
brew_install "ssh-audit" "ssh-audit (audit SSH server/client config)"
# macOS hardening: FileVault
if fdesetup status 2>/dev/null | grep -q "On"; then
    warn "FileVault is already enabled"
else
    info "FileVault (full disk encryption) is NOT enabled"
    echo "  -> Enable it: System Settings > Privacy & Security > FileVault > Turn On"
fi

# macOS hardening: Firewall
if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q "enabled"; then
    warn "macOS Firewall is already enabled"
else
    info "macOS Firewall is NOT enabled"
    echo "  -> Enable it: System Settings > Network > Firewall > Turn On"
fi

# Install local CA for mkcert
if ! is_done "install:mkcert-ca"; then
if installed mkcert; then
    info "Installing local CA for mkcert (enables trusted localhost HTTPS)..."
    # `mkcert -install` writes a root CA into the system trust store — about the last
    # thing a preview should do to a machine. It was unguarded (#380), and invisible on
    # a machine that already had the CA, where it is a no-op. It also never showed up on
    # the CI runner, because a dry run does not install mkcert and this block is behind
    # `installed mkcert` — a whole class that only appears on a machine that already has
    # the tool.
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: mkcert -install (adds a local root CA to the system trust store)"
    elif mkcert -install >> "$LOG_FILE" 2>&1; then
        success "mkcert local CA installed"
    else
        error "Failed to install mkcert local CA (check $LOG_FILE)"
    fi
fi
mark_done "install:mkcert-ca"
fi

fi  # security

# =============================================================================
if should_run "replacements"; then
banner "Modern CLI Replacements"
echo "  (upgrades for standard macOS/Unix utilities)"
echo ""

# ls -> eza (formerly exa): icons, git status, tree view, colors
brew_install_batch \
    "eza|eza (replaces ls — icons, git status, tree view)" \
    "bat|bat (replaces cat — syntax highlighting, line numbers)" \
    "fd|fd (replaces find — faster, simpler syntax)" \
    "ripgrep|ripgrep (replaces grep — 10x faster, .gitignore aware)" \
    "zoxide|zoxide (replaces cd — smart frecency-based jumping)" || true
brew_install "eza" "eza (replaces ls — icons, git status, tree view)"

# cat -> bat: syntax highlighting, line numbers, git integration, paging
brew_install "bat" "bat (replaces cat — syntax highlighting, line numbers)"

# find -> fd: simpler syntax, faster, respects .gitignore
brew_install "fd" "fd (replaces find — faster, simpler syntax)"

# grep -> ripgrep: massively faster, respects .gitignore, unicode
brew_install "ripgrep" "ripgrep (replaces grep — 10x faster, .gitignore aware)"

# cd -> zoxide: learns your most-used dirs, fuzzy matching
brew_install "zoxide" "zoxide (replaces cd — smart frecency-based jumping)"

# diff -> delta: syntax highlighting, side-by-side, git integration
# (already installed in Git section, just noting the replacement)
warn "delta (replaces diff — already installed in Git section)"

# man -> tldr: community-driven simplified man pages with examples.
# The `tldr` FORMULA is deprecated and DISABLED upstream (unmaintained), so a fresh
# machine cannot install it at all. `tlrc` is the official Rust client and provides
# the same `tldr` command — but it `conflicts_with` the old formula, so an existing
# install has to go first or brew refuses. Doing that here rather than leaving it to
# --cleanup means the swap reaches machines that already have the old one (#299).
if [[ "$DRY_RUN" != "true" ]] && brew list --formula tldr &>/dev/null; then
    info "Removing the disabled tldr formula (replaced by tlrc, same command)..."
    brew uninstall --formula tldr >> "$LOG_FILE" 2>&1 \
        || warn "Could not uninstall the old tldr formula — tlrc may refuse to install"
fi
brew_install "tlrc" "tlrc (official tldr client — replaces man with examples)"

# top/htop -> btop: modern resource monitor with graphs
brew_install_batch \
    "btop|btop (replaces top/htop — graphs, mouse support)" \
    "sd|sd (replaces sed — intuitive find & replace)" \
    "choose-rust|choose (replaces cut/awk — simpler syntax)" \
    "dust|dust (replaces du — visual disk usage tree)" \
    "duf|duf (replaces df — colorful disk usage table)" \
    "procs|procs (replaces ps — sortable, tree view, docker-aware)" \
    "gping|gping (replaces ping — real-time latency graph)" \
    "xh|xh (replaces curl — colorized, JSON-friendly)" \
    "doggo|doggo (replaces dig — colorized DNS, DoH support)" \
    "scc|scc (replaces wc for code — LOC by language, complexity + COCOMO cost)" \
    "viddy|viddy (replaces watch — diff highlighting, history)" \
    "rsync|rsync (latest — better cp/mv for large transfers)" \
    "hexyl|hexyl (replaces hexdump — colorized hex viewer)" \
    "aria2|aria2 (replaces curl/wget for downloads — multi-connection, BitTorrent)" \
    "ouch|ouch (universal archive tool — compress/decompress any format)" \
    "trash|trash (replaces rm — moves to macOS Trash, recoverable)" \
    "difftastic|difftastic (replaces diff for code — syntax-aware structural diffs)" \
    "vivid|vivid (LS_COLORS generator — colorize file listings by type)" \
    "just|just (replaces make — simpler task runner, no tab issues)" \
    "yazi|Yazi (terminal file manager with previews and bulk tasks)" \
    "fx|fx (interactive JSON viewer — better than jq for exploring)" \
    "jnv|jnv (interactive JSON navigator with jq filtering)" || true
brew_install "btop" "btop (replaces top/htop — graphs, mouse support)"

# sed -> sd: simpler regex syntax, string-literal mode, faster
brew_install "sd" "sd (replaces sed — intuitive find & replace)"

# cut/awk -> choose: simple column selection, negative indexing
brew_install "choose-rust" "choose (replaces cut/awk — simpler column selection)"

# du -> dust: visual disk usage with bar charts, sorted
brew_install "dust" "dust (replaces du — visual disk usage tree)"

# df -> duf: colorful disk free with table layout
brew_install "duf" "duf (replaces df — colorful disk usage table)"

# ps -> procs: colorful, sortable, tree view, docker-aware
brew_install "procs" "procs (replaces ps — sortable, tree view, docker-aware)"

# ping -> gping: graph ping latency over time, multi-host
brew_install "gping" "gping (replaces ping — real-time latency graph)"

# curl -> xh: colorized output, JSON shortcuts, HTTPie-like
brew_install "xh" "xh (replaces curl — colorized, JSON-friendly)"

# dig -> doggo: colorized DNS, supports DoH/DoT (dog is abandoned, doggo is the maintained successor)
brew_install "doggo" "doggo (replaces dig — colorized DNS, DoH support)"

# wc -> scc: lines of code by language + COCOMO cost/effort + complexity estimates
brew_install "scc" "scc (replaces wc for code — LOC by language, complexity + COCOMO cost)"

# watch -> viddy: modern watch with diff highlighting, history
brew_install "viddy" "viddy (replaces watch — diff highlighting, history)"

# cp/mv -> rsync is already on mac, but add progress
brew_install "rsync" "rsync (latest — better cp/mv for large transfers)"

# hexdump -> hexyl: colorized hex viewer with ASCII sidebar
brew_install "hexyl" "hexyl (replaces hexdump — colorized hex viewer)"

# aria2: multi-connection parallel downloads, 3-10x faster than a single stream.
# The scriptable download backend (yt-dlp and this script use aria2c), reached via
# its own name or the `dl` shortcut. Deliberately NOT aliased over `wget` — the
# flags differ, so the alias only turned "command not found" into an exception.
brew_install "aria2" "aria2 (replaces curl/wget for downloads — multi-connection, BitTorrent)"


# tar/unzip/7z -> ouch: universal archive tool, auto-detects format
brew_install "ouch" "ouch (universal archive tool — compress/decompress any format)"

# rm -> trash: moves to macOS Trash instead of permanent delete
brew_install "trash" "trash (replaces rm — moves to macOS Trash, recoverable)"

# diff (code-aware) -> difftastic: structural diff that understands syntax
brew_install "difftastic" "difftastic (replaces diff for code — syntax-aware structural diffs)"

# LS_COLORS -> vivid: generate LS_COLORS themes (Dracula, molokai, etc.)
brew_install "vivid" "vivid (LS_COLORS generator — colorize file listings by type)"

# make -> just: modern command runner, simpler syntax, no tab weirdness
brew_install "just" "just (replaces make — simpler task runner, no tab issues)"

# file manager -> Yazi: fast terminal file manager with previews and bulk tasks.
brew_install "yazi" "Yazi (terminal file manager with previews and bulk tasks)"

# jq (interactive) -> fx: interactive JSON viewer/processor
brew_install "fx" "fx (interactive JSON viewer — better than jq for exploring)"
brew_install "jnv" "jnv (interactive JSON navigator with jq filtering)"

fi  # replacements

# =============================================================================
if should_run "data-processing"; then
banner "Data & File Processing"

# yq: jq for YAML (essential for k8s/CDK)
brew_install_batch \
    "yq|yq (jq for YAML — essential for k8s/CDK work)" \
    "csvkit|csvkit (CSV tools — csvcut, csvgrep, csvstat)" \
    "jc|jc (convert command output into JSON for jq/automation)" \
    "jqp|jqp (interactive jq playground / JSON TUI)" \
    "pandoc|pandoc (universal document converter — md, pdf, docx, html)" \
    "tectonic|tectonic (self-contained LaTeX/PDF engine)" \
    "imagemagick|ImageMagick (image resize, convert, composite)" \
    "poppler|poppler (PDF tools — pdftoppm, pdftotext, pdfinfo)" \
    "yt-dlp|yt-dlp (video/audio downloader)" || true
brew_install "yq" "yq (jq for YAML — essential for k8s/CDK work)"
# csvkit: suite of CSV tools
brew_install "csvkit" "csvkit (CSV tools — csvcut, csvgrep, csvstat)"

# jc: convert classic CLI output into JSON for jq/automation
brew_install "jc" "jc (convert command output to JSON for jq/automation)"

# jqp: interactive jq playground / JSON TUI
brew_install "jqp" "jqp (interactive jq playground / JSON TUI)"

# pandoc: universal document converter
brew_install "pandoc" "pandoc (universal document converter — md, pdf, docx, html)"

# tectonic: self-contained LaTeX engine so pandoc can actually produce PDFs. A bare
# Mac has no PDF engine, so `pandoc -o x.pdf` fails with "pdflatex not found".
# tectonic is a single binary that fetches TeX packages on demand (fits CLI-first,
# minimal). pandoc won't auto-pick it, so pass the flag: pandoc in.md -o out.pdf --pdf-engine=tectonic
brew_install "tectonic" "tectonic (self-contained LaTeX/PDF engine for pandoc — md → pdf via --pdf-engine=tectonic)"

# imagemagick: image manipulation CLI
brew_install "imagemagick" "ImageMagick (image resize, convert, composite)"

# poppler: PDF utilities — pdftoppm (PDF->PNG), pdftotext, pdfinfo. These tools
# rasterize the PDFs LibreOffice produces for visual inspection.
brew_install "poppler" "poppler (PDF tools — pdftoppm, pdftotext, pdfinfo)"
# yt-dlp: video/audio downloader
brew_install "yt-dlp" "yt-dlp (video/audio downloader)"

fi  # data-processing

# =============================================================================
if should_run "code-quality"; then
banner "Code Quality"

brew_install_batch \
    "shellcheck|shellcheck (shell script linter)" \
    "shfmt|shfmt (shell script formatter)" \
    "actionlint|actionlint (GitHub Actions workflow linter)" \
    "act|act (run GitHub Actions locally)" \
    "hadolint|hadolint (Dockerfile linter — catches bad practices)" \
    "ruff|ruff (fast Python linter+formatter — replaces flake8+black+isort)" || true
brew_install "shellcheck" "shellcheck (shell script linter)"
brew_install "shfmt" "shfmt (shell script formatter)"
brew_install "actionlint" "actionlint (GitHub Actions workflow linter)"
brew_install "act" "act (run GitHub Actions locally)"
brew_install "hadolint" "hadolint (Dockerfile linter — catches bad practices)"

# Python linting (ruff — extremely fast, replaces flake8+black+isort)
brew_install "ruff" "ruff (fast Python linter+formatter — replaces flake8+black+isort)"
# prettier — the JS/TS/CSS/MD formatter the generated agent context requires and the
# pre-push checklist runs. It was documented but never installed, so the format-on-edit
# hook found nothing on PATH and silently no-opped.
#
# Installed from npm, NOT brew (#343). The Homebrew formula depends on `node`, so
# `brew install prettier` silently pulled in a second Node — 26.8.1 — alongside the
# `node@lts` this script pins through mise, and with it a second global node_modules
# tree. Nothing errored: `mise current node` kept reporting the pinned 24.18.1 while an
# interactive shell served 26.8.1, and `npm install -g` wrote to whichever tree the
# invoking shell happened to resolve. One Node, owned by mise, is the whole point.
#
# The old rationale for brew here was that a bottled binary survives mise Node switches.
# It does — but it bought that by installing its own Node, which is the disease, not the
# cure. `mise use --global node@lts` keeps the runtime stable instead.
#
# NOTE: the hook still prefers a project's OWN prettier over this one — see the
# format-on-edit heredoc — so a repo pinning prettier 2.x is not reformatted by 3.x.
# Existing-machine half of the same fix. A change that only lands on fresh installs is half
# a fix: without this, every already-provisioned machine keeps the Homebrew prettier, its
# Node, and the duplicate global tree forever.
#
# Two ordering constraints, both learned the hard way, both load-bearing:
#
#  1. The whole migration is INSIDE the `installed npm` guard. Removing the Homebrew copy
#     when npm is unavailable leaves the machine with no prettier at all — strictly worse
#     than before. And npm can genuinely be missing here: removing Homebrew's node takes
#     Homebrew's npm with it, so a shell whose PATH only ever had `$HOMEBREW_PREFIX/bin`
#     has no npm at all on the very next run. Never uninstall before the replacement is
#     known to be installable.
#  2. The uninstall runs BEFORE the install, not after. Homebrew's prettier owns
#     `$HOMEBREW_PREFIX/bin/prettier`; when the invoking shell resolves `npm` to Homebrew's
#     — which a login shell did, and which is the very ambiguity this fixes — `npm install
#     -g prettier` tries to write its shim to that same path and dies with `EEXIST: file
#     already exists`. Install-then-remove fails the install and removes the old copy
#     anyway, which is exactly how this was first shipped and immediately caught.
#
# A dry run cannot catch either: it reports both steps as intended and never discovers that
# they collide. This has to be exercised on a machine that actually has the old package.
if ! installed npm; then
    warn "npm not found — leaving prettier as-is (removing the Homebrew copy without a replacement would leave none)"
    progress  # keep the progress bar accurate
else
    if [[ "$DRY_RUN" == "true" ]]; then
        brew list --formula prettier &>/dev/null \
            && info "[DRY RUN] Would remove Homebrew prettier + its orphaned Node (#343)"
    elif brew list --formula prettier &>/dev/null; then
        info "Removing Homebrew prettier — its formula pulls in a second Node (#343)..."
        if brew uninstall prettier >> "$LOG_FILE" 2>&1; then
            # `brew autoremove` only considers formulae Homebrew recorded as installed AS A
            # DEPENDENCY. node here is `installed_on_request: false`, so it goes; a node the
            # user asked for on purpose is left alone. Same guard the cleanup path uses.
            brew autoremove >> "$LOG_FILE" 2>&1 || true
            if brew list --formula node &>/dev/null; then
                success "Homebrew prettier removed (npm's prettier takes over)"
                warn "Homebrew node is still installed — something else depends on it, or it was installed on request"
                info "  Two Node installs remain. Check with: brew uses --installed node"
            else
                success "Homebrew prettier + its orphaned Node removed — mise now owns the only Node"
            fi
        else
            warn "Could not remove Homebrew prettier — run: brew uninstall prettier && brew autoremove"
        fi
    fi
    npm_global_install "prettier" "prettier (JS/TS/CSS/MD/YAML formatter — global fallback; projects pin their own)"
fi

brew_install "typos-cli" "typos (source code spell checker — fast, low false positives)"
brew_install "ast-grep" "ast-grep (structural code search/replace using AST)"


fi  # code-quality

# =============================================================================
if should_run "perf-testing"; then
banner "Performance & Load Testing"

brew_install "hurl" "hurl (HTTP requests from plain text files — curl + test runner)"

fi  # perf-testing

# =============================================================================
if should_run "dev-servers"; then
banner "Dev Servers & Tunnels"

brew_cask_install "ngrok" "ngrok (expose localhost to the internet)"
brew_install "miniserve" "miniserve (instant file server from any directory)"

fi  # dev-servers

# =============================================================================
if should_run "terminal-productivity"; then
banner "Terminal Productivity"

brew_install "leaf-markdown-viewer" "leaf (terminal Markdown previewer — live watch, fuzzy picker, Mermaid/LaTeX, inline mode)"
# Leaf installs completions into this path. Generate the file without letting Leaf
# append an unmanaged source line to ~/.zshrc; the managed shell block loads it.
LEAF_COMPLETION="$HOME/.local/share/leaf/completions/_leaf"
if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -s "$LEAF_COMPLETION" ]]; then
        warn "[DRY RUN] leaf shell completions already installed"
    else
        info "[DRY RUN] Would install leaf shell completions"
    fi
elif [[ -s "$LEAF_COMPLETION" ]]; then
    warn "leaf shell completions already installed"
elif command -v leaf &>/dev/null; then
    info "Installing leaf shell completions..."
    mkdir -p "$(dirname "$LEAF_COMPLETION")"
    LEAF_COMPLETION_TMP="$(mktemp "$(dirname "$LEAF_COMPLETION")/.leaf.XXXXXX")"
    if leaf --auto-complete zsh:dump > "$LEAF_COMPLETION_TMP" 2>> "$LOG_FILE" &&
       [[ -s "$LEAF_COMPLETION_TMP" ]]; then
        mv "$LEAF_COMPLETION_TMP" "$LEAF_COMPLETION"
        success "leaf shell completions installed (restart shell to activate)"
    else
        rm -f "$LEAF_COMPLETION_TMP"
        warn "Could not install leaf completions (run manually: leaf --auto-complete)"
    fi
    unset LEAF_COMPLETION_TMP
fi
unset LEAF_COMPLETION
brew_install "watchexec" "watchexec (run commands on file changes — better entr)"
brew_install "pv" "pv (pipe viewer — progress bars for pipes)"
brew_install "gum" "gum (shell script UI toolkit — prompts, spinners, confirmations)"
brew_install "topgrade" "topgrade (update everything — brew, npm, pip, macOS, all at once)"
brew_install "fastfetch" "fastfetch (quick system info display — faster neofetch)"
brew_install "mprocs" "mprocs (TUI for running multiple dev processes)"
brew_install "broot" "broot (directory tree and file-navigation TUI)"
brew_install "lnav" "lnav (advanced log file viewer — auto-format, SQL queries on logs)"
brew_install "progress" "progress (coreutils progress viewer — cp, mv, dd, tar)"
# Native release packages avoid duplicate Rust and Go compilation.
trust_tap iamrohithrnair/tap
brew_install "iamrohithrnair/tap/emeraldian" \
    "Emeraldian (Obsidian vault TUI with backlinks, graph, and optional assistant)"
trust_tap lajosdeme/watchtower
brew_install "lajosdeme/watchtower/watchtower" \
    "Watchtower (global news, markets, weather, and intelligence dashboard)"
# Upstream publishes checksum-addressed macOS binaries. Use those instead of its
# Homebrew formula, whose build-only dependencies install a second Rust toolchain.
EILMELDUNG_VERSION="1.8.1"
EILMELDUNG_PREFIX="$HOME/.local/share/eilmeldung"
EILMELDUNG_BIN="$EILMELDUNG_PREFIX/eilmeldung"
EILMELDUNG_LINK="$HOME/.local/bin/eilmeldung"
case "$(uname -m)" in
    arm64)
        EILMELDUNG_ASSET="eilmeldung-aarch64-apple-darwin-$EILMELDUNG_VERSION.tar.gz"
        EILMELDUNG_SHA256="37af65f24cf50f7e95339679b6ab5cf90eb492a333ca31316d173e1064beaf31"
        ;;
    x86_64)
        EILMELDUNG_ASSET="eilmeldung-x86_64-apple-darwin-$EILMELDUNG_VERSION.tar.gz"
        EILMELDUNG_SHA256="c7387b767aed5f1b5b85649321cb8effcbda001df7018580d130091c91b191d0"
        ;;
    *)
        EILMELDUNG_ASSET=""
        EILMELDUNG_SHA256=""
        ;;
esac
EILMELDUNG_URL="https://github.com/christo-auer/eilmeldung/releases/download/$EILMELDUNG_VERSION/$EILMELDUNG_ASSET"

# Migrate the Homebrew formula from the first release that carried eilmeldung.
# Remove only Homebrew-recorded dependencies after its formula is gone. A manual
# reinstall after this migration remains untouched because the state key persists.
_eilmeldung_formula="christo-auer/eilmeldung/eilmeldung"
_eilmeldung_had_formula=false
if ! is_done "cleanup:eilmeldung-homebrew" && brew list --formula "$_eilmeldung_formula" &>/dev/null; then
    _eilmeldung_had_formula=true
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would replace the Homebrew eilmeldung formula with its verified macOS binary"
    else
        info "Replacing the Homebrew eilmeldung formula with its verified macOS binary..."
        if brew uninstall "$_eilmeldung_formula" >> "$LOG_FILE" 2>&1; then
            success "Homebrew eilmeldung formula removed"
        else
            error "Failed to remove the Homebrew eilmeldung formula"
        fi
    fi
fi
if [[ "$DRY_RUN" != "true" ]] && ! is_done "cleanup:eilmeldung-homebrew" &&
   ! brew list --formula "$_eilmeldung_formula" &>/dev/null; then
    brew untap christo-auer/eilmeldung >> "$LOG_FILE" 2>&1 || true
    XDG_CONFIG_HOME="$HOME/.config" brew untrust --formula "$_eilmeldung_formula" >> "$LOG_FILE" 2>&1 || true
    XDG_CONFIG_HOME="$HOME/.config" brew untrust --tap christo-auer/eilmeldung >> "$LOG_FILE" 2>&1 || true
    env -u XDG_CONFIG_HOME brew untrust --formula "$_eilmeldung_formula" >> "$LOG_FILE" 2>&1 || true
    env -u XDG_CONFIG_HOME brew untrust --tap christo-auer/eilmeldung >> "$LOG_FILE" 2>&1 || true
    if [[ "$_eilmeldung_had_formula" == "true" ]]; then
        brew autoremove >> "$LOG_FILE" 2>&1 || true
        _brew_snapshot_ready=""
        _BREW_FORMULAE=""
    fi
    mark_done "cleanup:eilmeldung-homebrew"
fi
_eilmeldung_resolved="$(command -v eilmeldung 2>/dev/null || true)"
if [[ "$DRY_RUN" == "true" && "$_eilmeldung_had_formula" == "true" ]]; then
    _eilmeldung_resolved=""
fi

# The official macOS archive links against Homebrew's libxml2 dylib.
if [[ -n "$EILMELDUNG_ASSET" &&
      ( -z "$_eilmeldung_resolved" || "$_eilmeldung_resolved" == "$EILMELDUNG_LINK" ) ]]; then
    brew_install "libxml2" "libxml2 (eilmeldung runtime library)"
else
    progress
fi
progress
if [[ -n "$_eilmeldung_resolved" && "$_eilmeldung_resolved" != "$EILMELDUNG_LINK" ]]; then
    warn "eilmeldung already available at $_eilmeldung_resolved"
elif [[ -z "$EILMELDUNG_ASSET" ]]; then
    error "eilmeldung has no supported archive for $(uname -m)"
elif [[ "$DRY_RUN" == "true" ]]; then
    if [[ -e "$EILMELDUNG_PREFIX" && ! -f "$EILMELDUNG_PREFIX/.dev-setup-version" ]]; then
        warn "[DRY RUN] Would leave $EILMELDUNG_PREFIX alone because this script does not own it"
    elif [[ -x "$EILMELDUNG_BIN" ]] &&
         [[ "$(/bin/cat "$EILMELDUNG_PREFIX/.dev-setup-version" 2>/dev/null || true)" == "$EILMELDUNG_VERSION" ]]; then
        warn "[DRY RUN] eilmeldung $EILMELDUNG_VERSION already installed"
    else
        info "[DRY RUN] Would install eilmeldung $EILMELDUNG_VERSION -> $EILMELDUNG_PREFIX"
    fi
elif [[ -e "$EILMELDUNG_PREFIX" && ! -f "$EILMELDUNG_PREFIX/.dev-setup-version" ]]; then
    warn "Left $EILMELDUNG_PREFIX alone because this script does not own it"
elif [[ ! -x "$EILMELDUNG_BIN" ]] ||
     [[ "$(/bin/cat "$EILMELDUNG_PREFIX/.dev-setup-version" 2>/dev/null || true)" != "$EILMELDUNG_VERSION" ]]; then
    _eilmeldung_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dev-setup-eilmeldung.XXXXXX")"
    mkdir -p "$_eilmeldung_tmp/stage"
    info "Installing eilmeldung $EILMELDUNG_VERSION..."
    if run_remote_installer "eilmeldung $EILMELDUNG_VERSION" "$EILMELDUNG_URL" "$EILMELDUNG_SHA256" \
           tar -xzf -- -C "$_eilmeldung_tmp/stage" eilmeldung/eilmeldung &&
       [[ -x "$_eilmeldung_tmp/stage/eilmeldung/eilmeldung" ]]; then
        rm -rf "$EILMELDUNG_PREFIX"
        mkdir -p "$EILMELDUNG_PREFIX"
        mv "$_eilmeldung_tmp/stage/eilmeldung/eilmeldung" "$EILMELDUNG_BIN"
        printf '%s\n' "$EILMELDUNG_VERSION" > "$EILMELDUNG_PREFIX/.dev-setup-version"
        success "eilmeldung $EILMELDUNG_VERSION installed"
    else
        error "Failed to download or verify eilmeldung $EILMELDUNG_VERSION"
    fi
    rm -rf "$_eilmeldung_tmp"
    unset _eilmeldung_tmp
fi
if [[ "$DRY_RUN" != "true" && -x "$EILMELDUNG_BIN" ]]; then
    mkdir -p "$HOME/.local/bin"
    if [[ -L "$EILMELDUNG_LINK" && "$(readlink "$EILMELDUNG_LINK")" == "$EILMELDUNG_BIN" ]]; then
        warn "eilmeldung already linked into ~/.local/bin"
    elif [[ -e "$EILMELDUNG_LINK" || -L "$EILMELDUNG_LINK" ]]; then
        warn "Left $EILMELDUNG_LINK alone because another installation owns it"
    elif ln -s "$EILMELDUNG_BIN" "$EILMELDUNG_LINK"; then
        success "eilmeldung linked into ~/.local/bin"
    else
        error "Failed to link eilmeldung into ~/.local/bin"
    fi
fi
unset EILMELDUNG_VERSION EILMELDUNG_PREFIX EILMELDUNG_BIN EILMELDUNG_LINK
unset EILMELDUNG_ASSET EILMELDUNG_SHA256 EILMELDUNG_URL
unset _eilmeldung_formula _eilmeldung_had_formula _eilmeldung_resolved
brew_install "concord" "concord (Discord client for the terminal)"
cargo_install "cfait" cfait \
    "cfait (offline-first task manager TUI with optional CalDAV sync)" --locked
cargo_install "caligula" caligula \
    "Caligula (disk imaging TUI with verification and compressed-image support)" --locked
go_install "github.com/dimonomid/nerdlog/cmd/nerdlog@latest" nerdlog \
    "Nerdlog (multi-host log viewer with live filtering, histograms, and SSH transport)"

# -- Additional TUI/CLI tools (homebrew-core) --
brew_install "lazyssh" "lazyssh (SSH connection manager TUI)"
brew_install "lazyrsync" "lazyrsync (rsync TUI with reusable profiles)"
brew_install "libqalculate" "qalc (powerful CLI calculator — units, live currency, variables)"

# -- Additional TUI/CLI tools (third-party taps) --
trust_tap jesseduffield/lazynpm
brew_install "jesseduffield/lazynpm/lazynpm" "lazynpm (npm TUI — joins lazygit and lazydocker)"
trust_tap djetelina/tap
brew_install "djetelina/tap/cheznav" "cheznav (chezmoi dotfiles TUI — dual-pane add/apply/diff)"


fi  # terminal-productivity

# =============================================================================
if should_run "k8s-github"; then
banner "GitHub Extras"


# gh-dash (GitHub dashboard extension)
# A raw `gh extension install` — not one of the managed helpers — so it has to guard
# itself, per the --dry-run rule in AGENTS.md. It did not, and a dry run therefore
# attempted a real network install every time. Invisible on a machine that already had
# the extension; on a clean one (the macOS CI job, #376) it failed against an
# unauthenticated gh and put a red `Failed: 1` on a run that was supposed to change
# nothing. The rest of that class is #380.
progress
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-dash"; then
        warn "gh-dash already installed"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install gh extension: dlvhdr/gh-dash"
    else
        info "Installing gh-dash (GitHub dashboard)..."
        if gh extension install dlvhdr/gh-dash >> "$LOG_FILE" 2>&1; then
            success "gh-dash installed (run: gh dash)"
        else
            error "Failed to install gh-dash extension"
        fi
    fi
fi

fi  # k8s-github

# =============================================================================
if should_run "database"; then
banner "Database & Data"

brew_install "duckdb" "duckdb (local analytics database for CSV/JSON/Parquet)"

# harlequin (terminal SQL IDE — DuckDB/Postgres/MySQL, multi-tab, autocomplete)
uv_tool_install 'harlequin[postgres,mysql,s3]' harlequin \
    "harlequin (terminal SQL IDE; postgres,mysql,s3 adapters)" \
    "harlequin installed (DuckDB + Postgres + MySQL + S3 adapters)"
# usql — not in Homebrew, install via Go (@latest intentionally unpinned).
# go_install is DRY_RUN-aware and lands the binary in GOBIN (on PATH).
go_install github.com/xo/usql@latest usql "usql (universal SQL CLI)"
brew_install "dbmate" "dbmate (lightweight DB migrations)"
# DBeaver (GUI) remains replaced by harlequin, usql, and DuckDB.

fi  # database

# =============================================================================
if should_run "containers"; then
banner "Containers & Orchestration"

brew_install "lazydocker" "lazydocker (terminal UI for Docker)"
brew_cask_install "docker-desktop" "Docker Desktop"
brew_install "dive" "dive (explore Docker image layers)"

fi  # containers

# =============================================================================
if should_run "api"; then
banner "API Development"

uv_tool_install "posting" posting \
    "Posting (terminal HTTP client with git-friendly YAML collections)" \
    "Posting installed (HTTP client TUI)" --python 3.13

fi  # api

# =============================================================================
if should_run "networking"; then
banner "Networking & Debugging"

brew_install "nmap" "nmap (network scanning)"
brew_install "trippy" "trippy (modern traceroute TUI with charts)"

fi  # networking

# =============================================================================
if should_run "dx"; then
banner "Developer Experience & Editor Flow"

# Terminal tools
brew_install "fzf" "fzf (fuzzy finder)"
brew_install "starship" "Starship (shell prompt)"

# Shell plugins
brew_install "zsh-autosuggestions" "zsh-autosuggestions (Fish-like inline suggestions)"
brew_install "zsh-syntax-highlighting" "zsh-syntax-highlighting (command coloring)"
brew_install "atuin" "atuin (replaces shell history — SQLite-backed, searchable)"

# mise (single tool version manager — can replace nvm + pyenv)
# mise already installed in core section

# Editors and terminals. micro handles quick edits and commit messages. Croft
# provides the terminal IDE, while Kiro provides the native graphical editor.
brew_install "micro" "micro (non-modal terminal editor — \$EDITOR for git; on-screen key menu)"
cargo_install "croft-software" croft \
    "Croft (VS Code-style terminal IDE)" --locked
brew_cask_install "kiro" "Kiro (agent-centric native code editor)"
# Kiro uses the Code OSS extension command-line interface. This list mirrors the
# active registry extensions on the maintainer's Kiro installation (#594).
kiro_extension_install "amazonwebservices.aws-toolkit-vscode" "AWS Toolkit"
kiro_extension_install "christian-kohler.path-intellisense" "Path Intellisense"
kiro_extension_install "coenraads.bracket-pair-colorizer-2" "Bracket Pair Colorizer 2"
kiro_extension_install "davidanson.vscode-markdownlint" "markdownlint"
kiro_extension_install "dbaeumer.vscode-eslint" "ESLint"
kiro_extension_install "dotnetdev-kr-custom.csharp" "C#"
kiro_extension_install "ecmel.vscode-html-css" "HTML CSS Support"
kiro_extension_install "editorconfig.editorconfig" "EditorConfig"
kiro_extension_install "esbenp.prettier-vscode" "Prettier"
kiro_extension_install "formulahendry.auto-rename-tag" "Auto Rename Tag"
kiro_extension_install "gruntfuggly.todo-tree" "Todo Tree"
kiro_extension_install "llvm-vs-code-extensions.lldb-dap" "LLDB DAP"
kiro_extension_install "mikestead.dotenv" "DotENV"
kiro_extension_install "ms-azuretools.vscode-containers" "Container Tools"
kiro_extension_install "ms-dotnettools.vscode-dotnet-runtime" ".NET Install Tool"
kiro_extension_install "ms-python.debugpy" "Python Debugger"
kiro_extension_install "ms-python.python" "Python"
kiro_extension_install "oderwat.indent-rainbow" "indent-rainbow"
kiro_extension_install "redhat.vscode-xml" "XML"
kiro_extension_install "redhat.vscode-yaml" "YAML"
kiro_extension_install "rust-lang.rust-analyzer" "rust-analyzer"
kiro_extension_install "shardulm94.trailing-spaces" "Trailing Spaces"
kiro_extension_install "shd101wyy.markdown-preview-enhanced" "Markdown Preview Enhanced"
kiro_extension_install "streetsidesoftware.code-spell-checker" "Code Spell Checker"
kiro_extension_install "stylelint.vscode-stylelint" "Stylelint"
kiro_extension_install "tamasfe.even-better-toml" "Even Better TOML"
kiro_extension_install "timonwong.shellcheck" "ShellCheck"
kiro_extension_install "usernamehw.errorlens" "Error Lens"
kiro_extension_install "vadimcn.vscode-lldb" "CodeLLDB"
kiro_extension_install "zignd.html-css-class-completion" "CSS Class IntelliSense"

brew_cask_install "kitty" "Kitty (fast GPU-accelerated terminal)"
brew_install "zellij" "zellij (modern terminal multiplexer — discoverable UI, layouts)"

# Language servers for OMP and other editor clients (#559). Homebrew formulae
# land in its default bin directory. npm binaries become mise shims, and the
# final shim-link pass exposes them through ~/.local/bin to non-zsh callers.
brew_install "taplo" "taplo (TOML language server and formatter)"
brew_install "marksman" "marksman (Markdown language server)"
brew_install "llvm" "LLVM (clangd language server)"

# Homebrew keeps LLVM keg-only. Publish only clangd through the PATH directory
# that this script already owns, without replacing a foreign file or link.
LLVM_CLANGD="$HOMEBREW_PREFIX/opt/llvm/bin/clangd"
LLVM_CLANGD_LINK="$HOME/.local/bin/clangd"
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would expose clangd through $LLVM_CLANGD_LINK"
elif [[ ! -x "$LLVM_CLANGD" ]]; then
    error "LLVM installed without clangd at $LLVM_CLANGD"
elif [[ -e "$LLVM_CLANGD_LINK" || -L "$LLVM_CLANGD_LINK" ]]; then
    if [[ -L "$LLVM_CLANGD_LINK" && "$(readlink "$LLVM_CLANGD_LINK")" == "$LLVM_CLANGD" ]]; then
        warn "clangd already linked into ~/.local/bin"
    else
        warn "Left $LLVM_CLANGD_LINK alone because another installation owns it"
    fi
else
    mkdir -p "$HOME/.local/bin"
    if ln -s "$LLVM_CLANGD" "$LLVM_CLANGD_LINK"; then
        success "clangd linked into ~/.local/bin"
    else
        error "Failed to link clangd into ~/.local/bin"
    fi
fi
unset LLVM_CLANGD LLVM_CLANGD_LINK

brew_install "rust-analyzer" "rust-analyzer (Rust language server)"
brew_install "lua-language-server" "Lua language server"
brew_install "docker-language-server" "Docker language server"

# Native bottles avoid compiling these Cargo subcommands during setup.
brew_install "cargo-watch" "cargo-watch (run Cargo commands when sources change)"
brew_install "cargo-nextest" "cargo-nextest (fast Rust test runner)"
brew_install "cargo-expand" "cargo-expand (show macro-expanded Rust source)"
brew_install "cargo-edit" "cargo-edit (Cargo dependency commands)"

if [[ "$MCP_INSPECTOR_NODE_READY" == "true" ]] && ! ensure_mcp_inspector_node; then
    error "MCP Inspector requires Node.js 22.19.0 or newer (check $LOG_FILE)"
    MCP_INSPECTOR_NODE_READY=false
fi
if installed npm; then
    npm_global_install "typescript-language-server" "TypeScript and JavaScript language server"
    npm_global_install "vscode-langservers-extracted" "HTML, CSS, JSON, and ESLint language servers"
    npm_global_install "bash-language-server" "Bash language server"
    npm_global_install "yaml-language-server" "YAML language server"
    npm_global_install "pyright" "Pyright language server"
    npm_global_install "@biomejs/biome" "Biome linter and language server"
    if [[ "$MCP_INSPECTOR_NODE_READY" == "true" ]]; then
        # Inspector 2.6.0 requests hono@^4.13.7, which is not published. Pin
        # the last known-good release and resolve its dependencies before the
        # Vite 8.3.0 metadata introduced the same unavailable-version failure.
        npm_global_install "@modelcontextprotocol/inspector@2.5.0" "MCP Inspector" "--before=2026-09-08"
    else
        progress
    fi
else
    progress; progress; progress; progress; progress; progress; progress  # keep progress bar accurate when npm unavailable
fi

# Ruff already comes from code-quality. Its `ruff server` command is the
# supported language server. Disable the redundant ty and basedpyright servers
# in omp's generated LSP policy below so Pyright owns Python type intelligence.

# OmniSharp has no current Homebrew formula. Its official net6 build needs a
# .NET runtime. Install the current SDK, then use runtime roll-forward so the
# pinned server can run without an unsupported .NET 6 installation.
brew_cask_install "dotnet-sdk" ".NET SDK (OmniSharp runtime)"
OMNISHARP_VERSION="1.39.15"
OMNISHARP_PREFIX="$HOME/.local/share/omnisharp"
OMNISHARP_APP="$OMNISHARP_PREFIX/OmniSharp"
OMNISHARP_BIN="$OMNISHARP_PREFIX/omnisharp"
OMNISHARP_LINK="$HOME/.local/bin/omnisharp"
case "$(uname -m)" in
    arm64)
        OMNISHARP_ASSET="omnisharp-osx-arm64-net6.0.tar.gz"
        OMNISHARP_SHA256="ae9ccca3ef1c4a4a3fbae7186a02bbc6c1290d8f4e2c845a214dabaf03cd7103"
        ;;
    x86_64)
        OMNISHARP_ASSET="omnisharp-osx-x64-net6.0.tar.gz"
        OMNISHARP_SHA256="bd2d273aff669645bdac2ee382d3a9c0220381b725a78697c9f6b6df9d22dafb"
        ;;
    *)
        OMNISHARP_ASSET=""
        OMNISHARP_SHA256=""
        ;;
esac
OMNISHARP_URL="https://github.com/OmniSharp/omnisharp-roslyn/releases/download/v$OMNISHARP_VERSION/$OMNISHARP_ASSET"
_omnisharp_resolved="$(command -v omnisharp 2>/dev/null || true)"
progress
if [[ -n "$_omnisharp_resolved" && "$_omnisharp_resolved" != "$OMNISHARP_LINK" ]]; then
    warn "OmniSharp already available at $_omnisharp_resolved"
elif [[ -z "$OMNISHARP_ASSET" ]]; then
    error "OmniSharp has no supported archive for $(uname -m)"
elif [[ "$DRY_RUN" == "true" ]]; then
    if [[ -e "$OMNISHARP_PREFIX" && ! -f "$OMNISHARP_PREFIX/.dev-setup-build" ]]; then
        warn "[DRY RUN] Would leave $OMNISHARP_PREFIX alone because this script does not own it"
    elif [[ -x "$OMNISHARP_BIN" ]] &&
         [[ "$(/bin/cat "$OMNISHARP_PREFIX/.dev-setup-build" 2>/dev/null || true)" == "$OMNISHARP_VERSION" ]]; then
        warn "[DRY RUN] OmniSharp $OMNISHARP_VERSION already installed"
    else
        info "[DRY RUN] Would install OmniSharp $OMNISHARP_VERSION -> $OMNISHARP_PREFIX"
    fi
elif [[ -e "$OMNISHARP_PREFIX" && ! -f "$OMNISHARP_PREFIX/.dev-setup-build" ]]; then
    warn "Left $OMNISHARP_PREFIX alone because this script does not own it"
elif [[ ! -x "$OMNISHARP_BIN" ]] ||
     [[ "$(/bin/cat "$OMNISHARP_PREFIX/.dev-setup-build" 2>/dev/null || true)" != "$OMNISHARP_VERSION" ]]; then
    _omnisharp_tmp="$(mktemp -d "${TMPDIR:-/tmp}/dev-setup-omnisharp.XXXXXX")"
    _omnisharp_archive="$_omnisharp_tmp/$OMNISHARP_ASSET"
    _omnisharp_stage="$_omnisharp_tmp/stage"
    info "Installing OmniSharp $OMNISHARP_VERSION..."
    if curl -fL --retry 3 "$OMNISHARP_URL" -o "$_omnisharp_archive" >> "$LOG_FILE" 2>&1 &&
       printf '%s  %s\n' "$OMNISHARP_SHA256" "$_omnisharp_archive" |
           shasum -a 256 -c - >> "$LOG_FILE" 2>&1 &&
       mkdir -p "$_omnisharp_stage" &&
       tar -xzf "$_omnisharp_archive" -C "$_omnisharp_stage" >> "$LOG_FILE" 2>&1 &&
       [[ -x "$_omnisharp_stage/OmniSharp" ]]; then
        rm -rf "$OMNISHARP_PREFIX"
        mv "$_omnisharp_stage" "$OMNISHARP_PREFIX"
        printf '#!/bin/sh\nexport DOTNET_ROOT="/usr/local/share/dotnet"\nexport DOTNET_ROLL_FORWARD="Major"\nexec "%s" "$@"\n' "$OMNISHARP_APP" > "$OMNISHARP_BIN"
        chmod +x "$OMNISHARP_BIN"
        printf '%s\n' "$OMNISHARP_VERSION" > "$OMNISHARP_PREFIX/.dev-setup-build"
        success "OmniSharp $OMNISHARP_VERSION installed"
    else
        error "Failed to download or verify OmniSharp $OMNISHARP_VERSION"
    fi
    rm -rf "$_omnisharp_tmp"
    unset _omnisharp_tmp _omnisharp_archive _omnisharp_stage
fi

if [[ "$DRY_RUN" != "true" && -x "$OMNISHARP_BIN" ]] &&
   [[ "$(/bin/cat "$OMNISHARP_PREFIX/.dev-setup-build" 2>/dev/null || true)" == "$OMNISHARP_VERSION" ]]; then
    mkdir -p "$HOME/.local/bin"
    if [[ -L "$OMNISHARP_LINK" && "$(readlink "$OMNISHARP_LINK")" == "$OMNISHARP_BIN" ]]; then
        warn "OmniSharp already linked into ~/.local/bin"
    elif [[ -e "$OMNISHARP_LINK" || -L "$OMNISHARP_LINK" ]]; then
        warn "Left $OMNISHARP_LINK alone because another installation owns it"
    elif ln -s "$OMNISHARP_BIN" "$OMNISHARP_LINK"; then
        success "OmniSharp linked into ~/.local/bin"
    else
        error "Failed to link OmniSharp into ~/.local/bin"
    fi
fi
unset OMNISHARP_VERSION OMNISHARP_PREFIX OMNISHARP_APP OMNISHARP_BIN OMNISHARP_LINK
unset OMNISHARP_ASSET OMNISHARP_SHA256 OMNISHARP_URL _omnisharp_resolved

go_install golang.org/x/tools/gopls@latest gopls "gopls (Go language server)"

# pi was retired in #513. omp replaces its agent runtime, web search, local model
# discovery, approval policies, and one-shot prompt use.
# OMP ships as a prebuilt native binary.
trust_tap can1357/tap
brew_install "can1357/tap/omp" "omp (Oh My Pi — workload-routed agent harness)"

# Clipboard history
# clipse — TUI clipboard manager (replaces Raycast clipboard history). Not on Homebrew.
go_install github.com/savedra1/clipse@latest clipse "clipse (TUI clipboard manager)"

# Dotfile management
brew_install "chezmoi" "chezmoi (dotfile manager — backup/restore configs across machines)"


# Node/JS tooling (via npm)
if installed npm; then
    npm_global_install "typescript" "TypeScript"
    npm_global_install "tsx" "tsx (TS execute)"
else
    progress; progress  # keep progress bar accurate when npm unavailable
fi

# fzf key bindings
if ! is_done "install:fzf-keybindings"; then
FZF_INSTALL_SCRIPT="$(brew --prefix 2>/dev/null)/opt/fzf/install"
if [[ ! -f "$HOME/.fzf.zsh" ]] && installed fzf && [[ -x "$FZF_INSTALL_SCRIPT" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        # fzf's own installer writes ~/.fzf.zsh. Unguarded, a dry run created it (#380).
        info "[DRY RUN] Would run fzf's installer to write $HOME/.fzf.zsh (key bindings + completion)"
    else
        info "Setting up fzf key bindings..."
        "$FZF_INSTALL_SCRIPT" --key-bindings --completion --no-update-rc --no-bash --no-fish
        success "fzf key bindings configured"
    fi
fi
mark_done "install:fzf-keybindings"
fi

fi  # dx


# =============================================================================
if should_run "docs"; then
banner "Documentation & Diagrams"

brew_install "d2" "d2 (code-to-diagram scripting language)"

fi  # docs

# =============================================================================
if should_run "mac-system"; then
banner "Mac Apps — System & Utilities"

# UniFi Identity Endpoint removed (dropped from setup).
brew_cask_install_batch \
    "lulu|LuLu (outbound firewall)" \
    "mullvad-vpn|Mullvad VPN (privacy-focused VPN with bundled CLI)" || true
brew_cask_install "lulu" "LuLu (outbound firewall)"
# The app package also installs the supported `mullvad` CLI at /usr/local/bin.
brew_cask_install "mullvad-vpn" "Mullvad VPN (privacy-focused VPN with bundled CLI)"

# mullvad-tui publishes Linux packages only. Build the pinned source on macOS
# against the exact Mullvad app submodule revision recorded by its release.
progress
MULLVAD_TUI_VERSION="v0.10.1"
MULLVAD_TUI_COMMIT="b65adc39029c888e78777c759c3a717f4d3d3f4d"
MULLVAD_TUI_BUILD_ID="$MULLVAD_TUI_VERSION@$MULLVAD_TUI_COMMIT"
MULLVAD_TUI_BIN="$HOME/.local/bin/mullvad-tui"
MULLVAD_TUI_STATE_DIR="$HOME/.local/share/mullvad-tui"
MULLVAD_TUI_MARKER="$MULLVAD_TUI_STATE_DIR/.dev-setup-build"

if [[ -x "$MULLVAD_TUI_BIN" ]] &&
   [[ "$(/bin/cat "$MULLVAD_TUI_MARKER" 2>/dev/null || true)" == "$MULLVAD_TUI_BUILD_ID" ]]; then
    warn "mullvad-tui $MULLVAD_TUI_VERSION — already installed"
elif [[ -x "$MULLVAD_TUI_BIN" && ! -f "$MULLVAD_TUI_MARKER" ]]; then
    warn "mullvad-tui already exists outside dev-setup — leaving it alone"
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would build mullvad-tui $MULLVAD_TUI_VERSION from pinned source"
elif ! installed cargo || ! installed git; then
    error "mullvad-tui needs cargo and git, but one is unavailable"
else
    _mullvad_tui_tmp="$(mktemp -d)"
    _mullvad_tui_src="$_mullvad_tui_tmp/mullvad-tui"
    info "Building mullvad-tui $MULLVAD_TUI_VERSION..."
    if git clone --branch "$MULLVAD_TUI_VERSION" --depth 1 \
           https://github.com/d10n/mullvad-tui.git "$_mullvad_tui_src" >> "$LOG_FILE" 2>&1 &&
       [[ "$(git -C "$_mullvad_tui_src" rev-parse HEAD 2>/dev/null)" == "$MULLVAD_TUI_COMMIT" ]] &&
       git -C "$_mullvad_tui_src" submodule update --init --depth 1 \
           mullvadvpn-app >> "$LOG_FILE" 2>&1 &&
       cargo build --release --locked -p mullvad-tui \
           --manifest-path "$_mullvad_tui_src/Cargo.toml" >> "$LOG_FILE" 2>&1; then
        mkdir -p "$(dirname "$MULLVAD_TUI_BIN")" "$MULLVAD_TUI_STATE_DIR"
        cp "$_mullvad_tui_src/target/release/mullvad-tui" "$MULLVAD_TUI_BIN"
        chmod 755 "$MULLVAD_TUI_BIN"
        printf '%s\n' "$MULLVAD_TUI_BUILD_ID" > "$MULLVAD_TUI_MARKER"
        success "mullvad-tui $MULLVAD_TUI_VERSION installed"
    else
        error "Failed to build mullvad-tui $MULLVAD_TUI_VERSION (check $LOG_FILE)"
    fi
    rm -rf "$_mullvad_tui_tmp"
    unset _mullvad_tui_tmp _mullvad_tui_src
fi
unset MULLVAD_TUI_VERSION MULLVAD_TUI_COMMIT MULLVAD_TUI_BUILD_ID
unset MULLVAD_TUI_BIN MULLVAD_TUI_STATE_DIR MULLVAD_TUI_MARKER

# No Quick Look plugins. QLMarkdown and QLStephen were dropped in 7.11.0 — Finder
# preview is not part of this workflow (files get read in the terminal), qlstephen was
# deprecated upstream, and QuickLookJSON had already been disabled. The qlmanage reload
# that registered them went with them; both are retired via DEPRECATED_TOOLS so
# --cleanup removes them from machines that have them (#299).

fi  # mac-system

# =============================================================================
if should_run "mac-productivity"; then
banner "Mac Apps — Productivity"
# Herald core mail and calendar features need no AI runtime or API key.
trust_tap herald-email/herald
brew_install "herald-email/herald/herald" "Herald (terminal email and calendar)"

# llama.cpp replaces Ollama as the local OMP provider. Homebrew's llama.cpp bottle
# enables Metal on macOS, so build the pinned release from source with Vulkan only.
# MoltenVK translates Vulkan to Metal while preserving the requested backend.
brew_install "ninja" "Ninja (llama.cpp build runner)"
brew_install "vulkan-loader" "Vulkan loader (llama.cpp backend)"
brew_install "molten-vk" "MoltenVK (Vulkan on macOS)"
brew_install "shaderc" "shaderc (Vulkan shader compiler)"
brew_install "spirv-headers" "SPIR-V headers (llama.cpp Vulkan backend)"
brew_install "openssl@3" "OpenSSL (llama.cpp server transport)"

LLAMA_CPP_VERSION="v0.4.0"
LLAMA_CPP_PREFIX="$HOME/.local/share/llama.cpp-vulkan"
LLAMA_CPP_BUILD_ID="${LLAMA_CPP_VERSION}-vulkan"
LLAMA_CPP_MODEL_DIR="$HOME/.local/share/llama.cpp/models"
LLAMA_CPP_MODEL_NAME="qwen2.5-coder-14b-instruct-q4_k_m.gguf"
LLAMA_CPP_MODEL="$LLAMA_CPP_MODEL_DIR/$LLAMA_CPP_MODEL_NAME"
LLAMA_CPP_MODEL_SIZE="8988110272"
LLAMA_CPP_MODEL_SHA256="c1e659736d89ac1065fb495330fb824d94001974a4bfa78e7270e43476a8d940"
LLAMA_CPP_MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct-GGUF/resolve/main/$LLAMA_CPP_MODEL_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -x "$LLAMA_CPP_PREFIX/bin/llama-server" ]] &&
       [[ "$(/bin/cat "$LLAMA_CPP_PREFIX/.dev-setup-build" 2>/dev/null || true)" == "$LLAMA_CPP_BUILD_ID" ]]; then
        warn "[DRY RUN] llama.cpp $LLAMA_CPP_VERSION Vulkan build — already installed"
    else
        info "[DRY RUN] Would build llama.cpp $LLAMA_CPP_VERSION with Vulkan and Metal disabled"
    fi
    if [[ -f "$LLAMA_CPP_MODEL" ]] &&
       [[ "$(/usr/bin/stat -f '%z' "$LLAMA_CPP_MODEL" 2>/dev/null || true)" == "$LLAMA_CPP_MODEL_SIZE" ]] &&
       [[ "$(/bin/cat "$LLAMA_CPP_MODEL.sha256" 2>/dev/null || true)" == "$LLAMA_CPP_MODEL_SHA256" ]]; then
        warn "[DRY RUN] llama.cpp model $LLAMA_CPP_MODEL_NAME — already downloaded"
    else
        info "[DRY RUN] Would download $LLAMA_CPP_MODEL_NAME (8.4 GiB)"
    fi
else
    if [[ ! -x "$LLAMA_CPP_PREFIX/bin/llama-server" ]] ||
       [[ "$(/bin/cat "$LLAMA_CPP_PREFIX/.dev-setup-build" 2>/dev/null || true)" != "$LLAMA_CPP_BUILD_ID" ]]; then
        _llama_build="$(mktemp -d "${TMPDIR:-/tmp}/dev-setup-llama.XXXXXX")"
        _llama_stage="${LLAMA_CPP_PREFIX}.new"
        rm -rf "$_llama_stage"
        info "Building llama.cpp $LLAMA_CPP_VERSION with the Vulkan backend..."
        if git clone --quiet --depth 1 --branch "$LLAMA_CPP_VERSION" \
                https://github.com/ggml-org/llama.cpp.git "$_llama_build/src" >> "$LOG_FILE" 2>&1 &&
           PATH="$(brew --prefix shaderc)/bin:$PATH" cmake -S "$_llama_build/src" -B "$_llama_build/build" \
                -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_PREFIX_PATH="$(brew --prefix vulkan-loader);$(brew --prefix molten-vk);$(brew --prefix shaderc);$(brew --prefix spirv-headers);$(brew --prefix openssl@3)" \
                -DGGML_VULKAN=ON \
                -DGGML_METAL=OFF \
                -DBUILD_SHARED_LIBS=OFF \
                -DLLAMA_BUILD_TESTS=OFF \
                -DLLAMA_USE_PREBUILT_UI=OFF \
                -DLLAMA_BUILD_EXAMPLES=OFF >> "$LOG_FILE" 2>&1 &&
           cmake --build "$_llama_build/build" --target llama-cli llama-server >> "$LOG_FILE" 2>&1 &&
           mkdir -p "$_llama_stage/bin" &&
           install -m 0755 "$_llama_build/build/bin/llama-cli" "$_llama_stage/bin/llama-cli" &&
           install -m 0755 "$_llama_build/build/bin/llama-server" "$_llama_stage/bin/llama-server"; then
            printf '%s\n' "$LLAMA_CPP_BUILD_ID" > "$_llama_stage/.dev-setup-build"
            rm -rf "$LLAMA_CPP_PREFIX"
            mv "$_llama_stage" "$LLAMA_CPP_PREFIX"
            mkdir -p "$HOME/.local/bin"
            ln -sf "$LLAMA_CPP_PREFIX/bin/llama-cli" "$HOME/.local/bin/llama-cli"
            ln -sf "$LLAMA_CPP_PREFIX/bin/llama-server" "$HOME/.local/bin/llama-server"
            success "llama.cpp $LLAMA_CPP_VERSION installed with Vulkan"
        else
            rm -rf "$_llama_stage"
            error "Failed to build llama.cpp with Vulkan — see $LOG_FILE"
        fi
        rm -rf "$_llama_build"
        unset _llama_build _llama_stage
    else
        warn "llama.cpp $LLAMA_CPP_VERSION Vulkan build already installed"
    fi

    mkdir -p "$LLAMA_CPP_MODEL_DIR"
    _llama_model_valid() {
        local model_path="$1"
        [[ -f "$model_path" ]] &&
            [[ "$(/usr/bin/stat -f '%z' "$model_path" 2>/dev/null || true)" == "$LLAMA_CPP_MODEL_SIZE" ]] && {
            printf '%s  %s\n' "$LLAMA_CPP_MODEL_SHA256" "$model_path" |
                shasum -a 256 -c - >> "$LOG_FILE" 2>&1
        }
    }
    if _llama_model_valid "$LLAMA_CPP_MODEL"; then
        warn "llama.cpp model $LLAMA_CPP_MODEL_NAME already downloaded"
    else
        info "Downloading $LLAMA_CPP_MODEL_NAME (8.4 GiB, resumable)..."
        # Accept a complete verified partial file before curl. A server can close
        # the final transfer with a nonzero status after every byte reached disk.
        if _llama_model_valid "$LLAMA_CPP_MODEL.part" || {
            # Override ~/.curlrc's 30-second request limit. This multi-gigabyte
            # transfer keeps its resumable partial file, but one run must finish it.
            curl --fail --location --continue-at - --max-time 0 \
                --output "$LLAMA_CPP_MODEL.part" "$LLAMA_CPP_MODEL_URL" >> "$LOG_FILE" 2>&1 &&
                _llama_model_valid "$LLAMA_CPP_MODEL.part"
        }; then
            mv "$LLAMA_CPP_MODEL.part" "$LLAMA_CPP_MODEL"
            printf '%s\n' "$LLAMA_CPP_MODEL_SHA256" > "$LLAMA_CPP_MODEL.sha256"
            success "$LLAMA_CPP_MODEL_NAME downloaded and verified"
        else
            error "Failed to download or verify $LLAMA_CPP_MODEL_NAME — resume by re-running setup"
        fi
    fi
    unset -f _llama_model_valid
fi
progress
unset LLAMA_CPP_VERSION LLAMA_CPP_PREFIX LLAMA_CPP_BUILD_ID LLAMA_CPP_MODEL_DIR
unset LLAMA_CPP_MODEL_NAME LLAMA_CPP_MODEL LLAMA_CPP_MODEL_SIZE LLAMA_CPP_MODEL_SHA256 LLAMA_CPP_MODEL_URL

# LibreOffice is the headless office suite for local document validation and conversion.
brew_cask_install_batch \
    "libreoffice|LibreOffice (headless document validation and conversion)" \
    "obsidian|Obsidian (local Markdown knowledge base)" \
    "drawio|Draw.io (desktop diagram editor)" || true
brew_cask_install "libreoffice" "LibreOffice (headless document validation and conversion)"
brew_cask_install "obsidian" "Obsidian (local Markdown knowledge base)"
brew_cask_install "drawio" "Draw.io (desktop diagram editor)"
# Draw.io keeps its supported user settings in application-owned Electron
# storage. It exposes no stable preference file for this generator to manage (#578).
# The cask ships only the app. Link `soffice` into the managed user binary directory.
if [[ "$DRY_RUN" != "true" ]]; then
    _soffice="/Applications/LibreOffice.app/Contents/MacOS/soffice"
    if [[ -x "$_soffice" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$_soffice" "$HOME/.local/bin/soffice"
        success "soffice linked to ~/.local/bin (headless: soffice --headless --convert-to pdf file.pptx)"
    fi
    unset _soffice
fi


# File transfer — Cyberduck (GUI) removed; rclone (installed below) covers SFTP/S3/cloud.

fi  # mac-productivity

# =============================================================================
if should_run "mac-browsers"; then
banner "Mac Apps — Browsers"

brew_cask_install_batch \
    "google-chrome|Google Chrome" \
    "firefox|Firefox" || true
brew_cask_install "google-chrome" "Google Chrome"
brew_cask_install "firefox" "Firefox"

npm_global_install "carbonyl" "Carbonyl (Chromium-based browser for the terminal)"
brew_install "chawan" "Chawan (terminal web browser and pager with CSS, JavaScript, and Kitty images)"
brew_install "monolith" "monolith (save complete web pages as a single HTML file)"

fi  # mac-browsers

# =============================================================================
if should_run "mac-media"; then
banner "Mac Apps — Media"

brew_install "mpv" "mpv (terminal video player)"
brew_install "oxipng" "oxipng (lossless PNG compression)"
brew_install "jpegoptim" "jpegoptim (lossless JPEG compression)"
# cliamp — Winamp-inspired terminal music player (MIT): many formats, streaming
# (YouTube/SoundCloud/Spotify/radio), parametric EQ, 20+ visualizations. Replaced kew.
trust_tap bjarneo/cliamp
brew_install "bjarneo/cliamp/cliamp" "cliamp (terminal music player — Winamp-style, streaming, EQ, 20+ visualizers)"
trust_tap LargeModGames/spotatui
brew_install "LargeModGames/spotatui/spotatui" "spotatui (multi-source terminal music player)"

fi  # mac-media

# =============================================================================
if should_run "mac-cloud"; then
banner "Mac Apps — Cloud Storage"

# Google Drive (GUI) removed — rclone handles Google Drive (and S3/Dropbox/etc.) from the terminal.

# Backup & sync
brew_install "rclone" "rclone (sync files to any cloud — Google Drive, S3, Dropbox, etc.)"
brew_install "borgbackup" "borg (deduplicated encrypted backups — better than Time Machine for offsite)"
brew_install "borgmatic" "borgmatic (automated borg backup scheduling and config)"
# borgmatic does nothing without a config. Scaffold a commented starter (only if none
# exists, so user edits are never clobbered): source dirs, retention, and excludes for
# churny/regenerable data (node_modules/caches/Downloads — same intent as the old Time
# Machine exclusions). Repo path + passphrase are user/secret-specific — fill them in,
# init the repo, then enable the daily schedule (see the post-setup checklist).
if installed borgmatic; then
    BORGMATIC_CONFIG="$HOME/.config/borgmatic/config.yaml"
    if write_seed_once "$BORGMATIC_CONFIG" "fill in repositories, then borgmatic init --encryption repokey-blake2" <<'BORGMATIC_CONF'
# borgmatic configuration — https://torsion.org/borgmatic/
# TODO: set `repositories`, then run: borgmatic init --encryption repokey-blake2
source_directories:
    - ~/Code
    - ~/Documents
    - ~/Creative

repositories:
    # - path: /Volumes/Backup/borg        # local external drive, or
    # - path: ssh://user@host/./borg-repo  # remote over SSH
    #   label: primary

# Skip regenerable/churny data (mirrors the old Time Machine exclusions).
exclude_patterns:
    - '**/node_modules'
    - ~/.cache
    - ~/Library/Caches
    - ~/.docker
    - ~/Downloads
    - ~/.Trash

# Passphrase from the macOS Keychain (no plaintext on disk). Create it once with:
#   security add-generic-password -a "$USER" -s borg-passphrase -w
encryption_passcommand: security find-generic-password -a $USER -s borg-passphrase -w

keep_daily: 7
keep_weekly: 4
keep_monthly: 6
BORGMATIC_CONF
    then
        configured "borgmatic starter config scaffolded (~/.config/borgmatic/config.yaml — fill in repositories)"
    fi
fi

fi  # mac-cloud


# mac-disk: Disk analysis handled by dust and duf (installed in "replacements" section)
# No additional tools needed — section removed to avoid empty banner

# =============================================================================
if should_run "dracula"; then
banner "Dracula-Sakura Theme"

# micro - Dracula (dracula-tc) is bundled with micro and set via ~/.config/micro/settings.json
# (see the micro config block below). No theme file to install.

# bat (Dracula is built-in, just needs to be set)
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    if [[ -n "$BAT_CONFIG_DIR" ]]; then
        if ! is_done "config:bat-dracula"; then
        if append_line_if_missing "$BAT_CONFIG_DIR/config" '--theme="Dracula"' 'bat Dracula theme'; then
            configured "bat Dracula theme configured"
        else
            warn "bat Dracula theme already configured"
        fi
        mark_done "config:bat-dracula"
        fi
    fi
fi

# delta (git diffs) - Dracula colors
if ! is_done "config:delta-dracula"; then
if git config --global delta.syntax-theme &>/dev/null; then
    warn "delta syntax theme already set"
else
    info "Setting delta to Dracula theme..."
    git_global delta.syntax-theme Dracula
    configured "delta Dracula theme configured"
fi
mark_done "config:delta-dracula"
fi

# Starship prompt (rich config with Dracula palette)
STARSHIP_CONFIG="$HOME/.config/starship.toml"
    info "Creating rich Starship prompt config..."
    write_managed "$STARSHIP_CONFIG" "#" <<'STARSHIP_CONF'
# =============================================================================
# Starship Prompt — Dracula-Sakura themed, info-rich
# =============================================================================

# Use the shared Dracula-Sakura house palette.
palette = "dracula_sakura"

# Prompt format: elegant, informative, two-line
format = """
[╭─](comment)$os$username$hostname$directory$git_branch$git_status$git_state$fill$battery$time
[╰─](comment)$nodejs$python$rust$go$docker_context$aws$terraform$cmd_duration$jobs$character"""

# Right prompt disabled (everything is on the left two-line prompt)
right_format = ""

# Wait 10ms for starship to check files (snappy)
scan_timeout = 10
command_timeout = 500

# Don't add blank line between prompts
add_newline = false

# -- Prompt character ---------------------------------------------------------
[character]
success_symbol = "[♡](bold rose)"
error_symbol = "[✗](bold red)"
vimcmd_symbol = "[❮](bold mint)"

# -- Fill (pushes battery/time to the right) ----------------------------------
[fill]
symbol = " "

# -- OS icon ------------------------------------------------------------------
[os]
disabled = false
style = "fg:dim"
format = "[$symbol ]($style)"

[os.symbols]
Macos = "☾"
Linux = ""
Windows = ""
Arch = ""
Ubuntu = ""
Fedora = ""
Debian = ""

# -- Username (only show if SSH or root) --------------------------------------
[username]
show_always = false
style_user = "fg:lilac"
style_root = "bold fg:red"
format = "[$user]($style) "

# -- Hostname (only show if SSH) ----------------------------------------------
[hostname]
ssh_only = true
style = "fg:rose"
format = "[@$hostname]($style) "

# -- Directory ----------------------------------------------------------------
[directory]
style = "bold fg:cyan"
format = "[✿ ](rose)[$path]($style)[$read_only]($read_only_style) "
truncation_length = 8
truncation_symbol = "…/"
read_only = " 󰌾"
read_only_style = "fg:red"

[directory.substitutions]
"Inbox" = "📥"
"Documents" = "󰈙"
"Downloads" = "⇣"
"Code" = ""
"Creative" = "🎨"
"Media" = "🎵"
"Archive" = "📦"

# -- Git branch ---------------------------------------------------------------
[git_branch]
symbol = " "
style = "fg:lilac"
format = "[$symbol$branch(:$remote_branch)]($style) "
truncation_length = 24

# -- Git status ---------------------------------------------------------------
[git_status]
style = "fg:rose"
format = '([$all_status$ahead_behind]($style) )'
conflicted = "⚡${count} "
ahead = "⇡${count} "
behind = "⇣${count} "
diverged = "⇕⇡${ahead_count}⇣${behind_count} "
untracked = "?${count} "
stashed = "📦${count} "
modified = "!${count} "
staged = "+${count} "
renamed = "»${count} "
deleted = "✘${count} "

# -- Git state (rebase, merge, etc.) ------------------------------------------
[git_state]
style = "bold fg:peach"
format = "[$state( $progress_current/$progress_total)]($style) "
rebase = "REBASING"
merge = "MERGING"
revert = "REVERTING"
cherry_pick = "CHERRY-PICKING"
bisect = "BISECTING"

# -- Node.js ------------------------------------------------------------------
[nodejs]
symbol = " "
style = "fg:mint"
format = "[$symbol$version]($style) "
detect_files = ["package.json", ".nvmrc"]
detect_extensions = []

# -- Python -------------------------------------------------------------------
[python]
symbol = " "
style = "fg:yellow"
format = '[$symbol$version( \($virtualenv\))]($style) '
detect_extensions = ["py"]

# -- Rust ---------------------------------------------------------------------
[rust]
symbol = "🦀 "
style = "fg:peach"
format = "[$symbol$version]($style) "

# -- Go ----------------------------------------------------------------------
[golang]
symbol = " "
style = "fg:cyan"
format = "[$symbol$version]($style) "

# -- Docker context -----------------------------------------------------------
[docker_context]
symbol = " "
style = "fg:cyan"
format = "[$symbol$context]($style) "
only_with_files = true

# -- AWS profile --------------------------------------------------------------
[aws]
symbol = "☁️ "
style = "bold fg:peach"
format = "[$symbol$profile(\\($region\\))]($style) "

# -- Terraform ----------------------------------------------------------------
[terraform]
symbol = "💠 "
style = "fg:lilac"
format = "[$symbol$workspace]($style) "

# -- Command duration (show if > 3 seconds) -----------------------------------
[cmd_duration]
min_time = 3_000
style = "fg:peach"
format = "[󱎫 $duration]($style) "
show_milliseconds = false

# -- Background jobs ----------------------------------------------------------
[jobs]
symbol = "✦"
style = "bold fg:cyan"
number_threshold = 1
format = "[$symbol $number]($style) "

# -- Battery (show if < 30%) --------------------------------------------------
[battery]
format = "[$symbol$percentage]($style) "

[[battery.display]]
threshold = 15
style = "bold fg:red"

[[battery.display]]
threshold = 30
style = "fg:peach"

# -- Time (always show) -------------------------------------------------------
[time]
disabled = false
style = "fg:dim"
format = "[ $time]($style)"
time_format = "%H:%M"

# -- Dracula-Sakura color palette ---------------------------------------------
[palettes.dracula_sakura]
bg = "#282a36"
panel = "#323448"
panel_soft = "#2f3144"
current = "#4b4963"
selection = "#6a5d86"
fg = "#f8f8f2"
muted = "#ddd2f7"
dim = "#a297cb"
comment = "#8a88c7"
cyan = "#9be7ff"
mint = "#8af7cf"
peach = "#ffcf93"
rose = "#ff9fe3"
blush = "#ffc2ec"
lilac = "#d4b2ff"
red = "#ff7aa8"
yellow = "#fff0a8"
STARSHIP_CONF
    configured "Starship prompt configured (Dracula-Sakura two-line prompt)"

fi  # dracula

# =============================================================================
if should_run "configs"; then
banner "Configuration Layer"

# ---- git global config ----
info "Configuring git global settings..."

# Default branch
git_global init.defaultBranch main 2>/dev/null

# Pull strategy (rebase to keep history clean)
git_global pull.rebase true

# Auto-stash on rebase
git_global rebase.autoStash true

# Better diff algorithm
git_global diff.algorithm histogram

# Show diff in commit message editor
git_global commit.verbose true

# Auto-correct typos (0.5s delay)
git_global help.autocorrect 5

# Column output for branch listing
git_global column.ui auto

# Sort branches by most recent commit
git_global branch.sort -committerdate

# Remember merge conflict resolutions and auto-apply next time
git_global rerere.enabled true

configured "  git core settings configured (rebase, histogram diff, rerere)"

# Useful aliases
# Basic shortcuts
git_global alias.st "status -sb"
git_global alias.co "checkout"
git_global alias.br "branch"
git_global alias.ci "commit"
git_global alias.sw "switch"

# Undo & reset
git_global alias.unstage "reset HEAD --"
git_global alias.undo "reset --soft HEAD~1"
git_global alias.discard "checkout -- ."
git_global alias.amend "commit --amend --no-edit"

# Quick commits
git_global alias.wip "!git add -A && git commit -m 'WIP'"
git_global alias.save "!git add -A && git commit -m 'chore: savepoint'"

# Stash
git_global alias.stash-all "stash push --include-untracked"
git_global alias.stash-peek "stash show -p"

# Log & history
git_global alias.last "log -1 HEAD --stat"
git_global alias.lg "log --oneline --graph --decorate --all"
git_global alias.log-stats "log --oneline --stat"
git_global alias.log-since "log --oneline --since='1 week ago'"
git_global alias.contributors "shortlog -sne --no-merges"
git_global alias.standup "!git log --oneline --since='yesterday' --author=\"\$(git config user.name)\""

# Branch management
git_global alias.recent "branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)' -n 15"
# `cleanup` deletes local branches that are finished with. "Finished" has TWO
# shapes here, and each selector is blind to the other's population (#321, #470):
#
#   * Upstream `[gone]` — what a squash merge plus `--delete-branch` leaves
#     behind. This is the common case in this workflow.
#   * Merged by ancestry — a branch that never had an upstream at all, so it can
#     never be `[gone]`. Anything created locally and never pushed, or pushed
#     without `-u`. #470 found one of these sitting fully merged and permanently
#     invisible to the alias.
#
# Ancestry ALONE was the pre-#321 bug and must not come back as the only test:
# `git branch --merged main` is an ancestry test, and a squash merge writes a NEW
# commit that the branch tip is not an ancestor of. Every squash-merged branch is
# invisible to it, so `cleanup` selected nothing, forever, then died on `xargs`
# with `fatal: branch name required`, which reads as a usage error rather than
# "nothing to do". The fix is the UNION of both selectors, not a swap.
#
# Deleting with `-d` is equally not an option: it applies that same ancestry test
# and refuses a squash-merged branch, so selection would be right and the delete
# would fail at the last step. `-D` gives up git's safety net, and the echoed SHA
# is what replaces it: recovery is `git branch <name> <sha>`, with the reflog
# behind that. Silence is the bug here, not politeness — an alias that finds
# nothing says so.
#
# The default branch is read from origin/HEAD rather than hardcoded, and is
# excluded from its own merged list (every branch is merged into itself). The
# `--merged` call is guarded so a repo without that branch reports nothing
# instead of erroring.
#
# Single-quoted so the body reaches git verbatim; keep single quotes OUT of it.
# `for-each-ref` rather than `branch -vv | awk` so that no `$1` has to survive
# three levels of quoting.
git_global alias.cleanup '!f() {
    git fetch --prune --quiet
    current=$(git branch --show-current)
    default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed "s|^origin/||")
    [ -z "$default" ] && default=main
    git show-ref --verify --quiet "refs/heads/$default" || default=master
    stale=$(git for-each-ref --format="%(refname:short) %(upstream:track)" refs/heads | grep "\[gone\]$" | cut -d" " -f1)
    merged=""
    if git show-ref --verify --quiet "refs/heads/$default"; then
        merged=$(git branch --merged "$default" --format="%(refname:short)" | grep -vx "$default")
    fi
    targets=$(printf "%s\n%s\n" "$stale" "$merged" | grep -v "^$" | sort -u)
    if [ -z "$targets" ]; then
        echo "Nothing to delete - no branch has a gone upstream or is merged into $default."
        return 0
    fi
    echo "$targets" | while read -r b; do
        if [ "$b" = "$current" ]; then
            echo "skipped  $b - checked out, switch away first"
            continue
        fi
        sha=$(git rev-parse --short "$b")
        if git branch -D "$b" >/dev/null 2>&1; then
            echo "deleted  $b ($sha) - restore with: git branch $b $sha"
        else
            echo "FAILED   $b ($sha)" >&2
        fi
    done
}; f'

# gone delegates. The implementation moved here from `gone` in #470: once the
# behaviour is "gone OR merged", `cleanup` is the honest name for it. `gone` stays
# as a second name for the same one implementation, per #321.
git_global alias.gone "!git cleanup"

# Diff
git_global alias.dft "!git -c diff.external=difft diff"
git_global alias.dfl "!git -c diff.external=difft log -p --ext-diff"
git_global alias.diff-names "diff --name-only"
git_global alias.diff-stat "diff --stat"

# Worktree shortcuts
git_global alias.wt "worktree"
git_global alias.wta "worktree add"
git_global alias.wtl "worktree list"

configured "  git aliases configured (30+ shortcuts for status, log, branch, diff, worktree)"

# ---- GPG + pinentry-mac ----
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
    info "Configuring GPG to use pinentry-mac..."
    # write_managed and the gpgconf restart below are the guarded parts; this chmod and
    # the agent kill were not, so a dry run changed permissions on ~/.gnupg and dropped
    # the user's cached passphrases (#380).
    [[ "$DRY_RUN" == "true" ]] || chmod 700 "$HOME/.gnupg"
    PINENTRY_PATH="$(brew --prefix 2>/dev/null)/bin/pinentry-mac"
    if [[ ! -x "$PINENTRY_PATH" ]]; then
        warn "pinentry-mac not found at $PINENTRY_PATH — skipping GPG agent config"
    else
        write_managed "$GPG_AGENT_CONF" "#" <<GPG_CONFIG
# Use macOS keychain for passphrase
pinentry-program $PINENTRY_PATH

# Cache passphrase for 8 hours
default-cache-ttl 28800
max-cache-ttl 28800
GPG_CONFIG
        # Restart gpg-agent to pick up changes
        [[ "$DRY_RUN" == "true" ]] || gpgconf --kill gpg-agent 2>/dev/null || true
        configured "GPG pinentry-mac configured (passphrases cached 8 hours)"
    fi

# ---- aria2 ----
ARIA2_CONFIG_DIR="$HOME/.aria2"
ARIA2_CONFIG="$ARIA2_CONFIG_DIR/aria2.conf"
    info "Creating aria2 configuration..."
    write_managed "$ARIA2_CONFIG" "#" <<'ARIA2_CONF'
## aria2 configuration

# -- Connections & Speed ------------------------------------------------------
# Max concurrent downloads
max-concurrent-downloads=5

# Max connections per server (split file into N parts)
max-connection-per-server=16

# Split file into N pieces
split=16

# Min split size (don't split files smaller than this)
min-split-size=1M

# -- Retry & Resume -----------------------------------------------------------
# Auto-retry on failure
max-tries=5
retry-wait=10

# Always resume incomplete downloads
continue=true

# -- File Management ----------------------------------------------------------
# Default download directory
dir=PLACEHOLDER_HOME/Downloads

# Allocate disk space before downloading (faster on APFS)
file-allocation=none

# Auto-rename if file already exists
auto-file-renaming=true

# -- Console Output -----------------------------------------------------------
# Summary interval (seconds)
summary-interval=0

# Human-readable output
human-readable=true

# Show console readout
enable-color=true

# -- HTTP/HTTPS ---------------------------------------------------------------
# Use server-provided filename
content-disposition-default-utf8=true

# HTTP compression
http-accept-gzip=true

# User agent
user-agent=Mozilla/5.0 (compatible; aria2)

# -- BitTorrent ---------------------------------------------------------------
# Enable DHT for BitTorrent
enable-dht=true
enable-dht6=true

# Listen port for BitTorrent
listen-port=6881-6999

# Seed ratio (0.0 = don't seed after completion)
seed-ratio=1.0

# Max upload speed (0 = unlimited)
max-overall-upload-limit=256K

# -- Disk Cache ---------------------------------------------------------------
disk-cache=64M
ARIA2_CONF
    # Replace placeholder with actual home directory
    /usr/bin/sed -i '' "s|PLACEHOLDER_HOME|$HOME|g" "$ARIA2_CONFIG"
    configured "aria2 configured (16 connections, auto-resume, BitTorrent)"

# ---- atuin ----
ATUIN_CONFIG_DIR="$HOME/.config/atuin"
ATUIN_CONFIG="$ATUIN_CONFIG_DIR/config.toml"
    info "Creating atuin configuration..."
    write_managed "$ATUIN_CONFIG" "#" <<'ATUIN_CONF'
## atuin configuration

# -- Theme --------------------------------------------------------------------
# Selects themes/dracula-sakura.toml, written beside this file. `style` below is
# layout (compact vs full), not colour — atuin had no colours until #518.
[theme]
name = "dracula-sakura"


# -- Search -------------------------------------------------------------------
# Search mode: prefix, fulltext, fuzzy, skim
search_mode = "fuzzy"

# Filter mode when pressing up arrow (host = only this machine's history)
filter_mode = "host"

# Filter mode for ctrl-r search (global = all history)
filter_mode_shell_up_key_binding = "host"

# -- Display ------------------------------------------------------------------
# Inline search height (number of results)
inline_height = 20

# Show preview of full command
show_preview = true

# Timestamp format
style = "compact"

# Show help banner at top of search
show_help = false

# -- Behavior -----------------------------------------------------------------
# Accept command on Enter (true = execute immediately, false = paste to prompt)
enter_accept = false

# Don't sync to atuin server (local only)
auto_sync = false

# Store in plaintext locally (faster)
daemon.enabled = false

# -- History Filter (ignore noise) --------------------------------------------
# Commands that shouldn't pollute history
history_filter = [
    "^ls$",
    "^ll$",
    "^la$",
    "^cd ",
    "^clear$",
    "^exit$",
    "^pwd$",
    "^\\.$",
    "^cat ",
    "^echo ",
    "^export ",
]

# Secrets: don't record commands containing these patterns
secrets_filter = true

# -- Stats --------------------------------------------------------------------
# Show stats in search footer (e.g., "3,402 commands")
stats.show_in_footer = true
ATUIN_CONF
    configured "atuin configured (fuzzy search, local-only, history filter, enter=paste)"

    # -- Dracula-Sakura theme -----------------------------------------------------
    # 15 tokens, taken from the `Meaning` enum in atuin-client/src/theme.rs. The
    # help text embedded in the binary lists only 7 and says values must be
    # "lowercase entries" from the palette named-colour list; both are out of date.
    # The parser checks for a leading `#` and reads hex pairs BEFORE falling back
    # to named lookup (theme.rs:184-215), so the real palette is usable (#518).
    #
    # An unknown token or an unparsable colour is skipped rather than rejected,
    # and `atuin history list` renders no theme at all — a run that "does not
    # complain" proves nothing here. `atuin` itself is the check.
    ensure_dir "$ATUIN_CONFIG_DIR/themes"
    write_generated "$ATUIN_CONFIG_DIR/themes/dracula-sakura.toml" <<'ATUIN_THEME_CONF'
[theme]
name = "dracula-sakura"

[colors]
Base = "#f8f8f2"
Title = "#ff9fe3"
Important = "#ffc2ec"
Guidance = "#9be7ff"
Annotation = "#8a88c7"
Muted = "#a297cb"
AlertInfo = "#9be7ff"
AlertWarn = "#ffcf93"
AlertError = "#ff7aa8"
SyntaxCommand = "#ff9fe3"
SyntaxFlag = "#d4b2ff"
SyntaxString = "#fff0a8"
SyntaxVariable = "#ffcf93"
SyntaxOperator = "#ff9fe3"
SyntaxComment = "#8a88c7"
ATUIN_THEME_CONF
    configured "atuin Dracula-Sakura theme written (~/.config/atuin/themes/dracula-sakura.toml)"

# ---- lazygit Dracula theme ----
if installed lazygit; then
# Ask lazygit where it looks rather than assuming (#333). It follows XDG, and this
# script's own ~/.zshrc exports XDG_CONFIG_HOME=~/.config — so the answer depends on
# an environment variable WE set, and the honest question is not "where does lazygit
# look right now" but "where will it look once setup is done". Hence the explicit
# XDG_CONFIG_HOME on the query: it asks about the post-setup machine, not this shell,
# which may be a bare bash on a fresh box that has never sourced the generated zshrc.
LAZYGIT_CONFIG_DIR="$(XDG_CONFIG_HOME="$HOME/.config" lazygit --print-config-dir 2>/dev/null)"
LAZYGIT_CONFIG_DIR="${LAZYGIT_CONFIG_DIR:-$HOME/.config/lazygit}"
LAZYGIT_CONFIG="$LAZYGIT_CONFIG_DIR/config.yml"
LAZYGIT_SUPERSEDED="$HOME/Library/Application Support/lazygit/config.yml"
    info "Creating lazygit Dracula Sakura config..."
    write_managed "$LAZYGIT_CONFIG" "#" <<'LAZYGIT_CONF'
gui:
  nerdFontsVersion: "3"
  showBottomLine: false
  showPanelJumps: true
  showRandomTip: false
  showCommandLog: false
  border: rounded
  branchColors:
    '*': '#d4b2ff'
  theme:
    activeBorderColor:
      - "#ff9fe3"
      - bold
    inactiveBorderColor:
      - "#4b4963"
    optionsTextColor:
      - "#9be7ff"
    selectedLineBgColor:
      - "#6a5d86"
    inactiveViewSelectedLineBgColor:
      - "#323448"
    cherryPickedCommitFgColor:
      - "#8af7cf"
    cherryPickedCommitBgColor:
      - "#4b4963"
    unstagedChangesColor:
      - "#ff7aa8"
    defaultFgColor:
      - "#ddd2f7"
    searchingActiveBorderColor:
      - "#ffcf93"
git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never
  commit:
    signOff: false
  autoFetch: true
  autoRefresh: true
  branchLogCmd: "git log --graph --color=always --abbrev-commit --decorate --date=relative --pretty=medium {{branchName}} --"
os:
  edit: 'micro {{filename}}'
  editAtLine: 'micro {{filename}} +{{line}}'
  editAtLineAndWait: 'micro {{filename}} +{{line}}'
  editInTerminal: true
  open: "open {{filename}}"
  openLink: "open {{link}}"
notARepository: skip
promptToReturnFromSubprocess: false
LAZYGIT_CONF
    remove_superseded_managed "$LAZYGIT_SUPERSEDED" \
        "lazygit reads $LAZYGIT_CONFIG" "(#333)"
    configured "lazygit configured (Dracula Sakura theme, delta pager, micro editor)"
fi  # installed lazygit



# ---- Retired Kubernetes config cleanup ----
# Remove only files that still contain a complete managed block. The cleanup
# path can remove modified or unmarked leftovers after the retired tools are absent.
remove_superseded_managed "$HOME/.config/k9s/skins/dracula.yaml" \
    "k9s was retired from this setup" "(#578)"
remove_superseded_managed "$HOME/.config/k9s/config.yaml" \
    "k9s was retired from this setup" "(#578)"
remove_superseded_managed "$HOME/Library/Application Support/k9s/skins/dracula.yaml" \
    "k9s was retired from this setup" "(#578)"
remove_superseded_managed "$HOME/Library/Application Support/k9s/config.yaml" \
    "k9s was retired from this setup" "(#578)"

# ---- micro editor config ----
# micro is the $EDITOR: git/gh/lazygit commit messages, leaf's Ctrl+E, quick file edits.
# Non-modal by design, so the settings below favor discoverability and match the
# code standards in the generated OMP AGENTS.md.
#   keymenu    - persistent key-binding strip along the bottom (the whole point)
#   dracula-tc - built into micro; needs truecolor, which Kitty advertises via COLORTERM
#   rmtrailingws/eofnewline - match what prettier and ruff would do on save anyway
# Indentation follows the house rules: 2 spaces, 4 for Python, real tabs for Go/Makefiles.
MICRO_CONFIG_DIR="$HOME/.config/micro"
info "Configuring micro (Dracula, on-screen key menu, house indent rules)..."
ensure_dir "$MICRO_CONFIG_DIR"
# NOT write_managed: settings.json is JSON, which has no comment syntax for the markers,
# and micro rewrites this file itself whenever you change a setting from inside the editor
# (`> set foo bar`). So merge instead of overwrite, with the on-disk file winning — your
# in-editor tweaks survive re-runs, while options added in later releases still land.
MICRO_DEFAULTS=$(cat <<'MICRO_CONF'
{
    "colorscheme": "dracula-tc",
    "keymenu": true,
    "infobar": true,
    "statusline": true,
    "mouse": true,
    "clipboard": "external",
    "ruler": true,
    "scrollbar": true,
    "cursorline": true,
    "matchbrace": true,
    "softwrap": true,
    "wordwrap": true,
    "diffgutter": true,
    "hlsearch": true,
    "incsearch": true,
    "autoindent": true,
    "eofnewline": true,
    "rmtrailingws": true,
    "hltrailingws": true,
    "saveundo": true,
    "savecursor": true,
    "savehistory": true,
    "autosave": 0,
    "tabsize": 2,
    "tabstospaces": true,
    "ft:python": { "tabsize": 4 },
    "ft:go": { "tabstospaces": false, "tabsize": 4 },
    "ft:makefile": { "tabstospaces": false }
}
MICRO_CONF
)
if merge_json_defaults "$MICRO_CONFIG_DIR/settings.json" <<< "$MICRO_DEFAULTS"; then
    [[ "$DRY_RUN" == "true" ]] \
        || success "micro settings merged (your changes kept; new defaults added)"
else
    _micro_merge_status=$?
    if [[ "$_micro_merge_status" -eq 2 ]]; then
        warn "micro settings exist but jq is missing — not merging new defaults"
    else
        warn "Could not merge micro settings — left as-is: $MICRO_CONFIG_DIR/settings.json"
    fi
    unset _micro_merge_status
fi
unset MICRO_DEFAULTS

# ---- Kiro editor config ----
# Kiro is based on Code OSS. It reads user settings from the standard macOS
# Application Support path and scans local extensions under ~/.kiro/extensions.
# The local theme extension avoids a registry dependency and gives the house
# palette a stable name in Kiro's theme picker.
KIRO_CONFIG_DIR="$HOME/Library/Application Support/Kiro/User"
KIRO_CONFIG="$KIRO_CONFIG_DIR/settings.json"
KIRO_EXTENSION_DIR="$HOME/.kiro/extensions/vixygrey.dracula-sakura-1.0.0"
KIRO_EXTENSION_MANIFEST="$KIRO_EXTENSION_DIR/package.json"
KIRO_THEME="$KIRO_EXTENSION_DIR/themes/dracula-sakura-color-theme.json"
info "Configuring Kiro (Dracula-Sakura, house fonts, editor defaults)..."

KIRO_EXTENSION_JSON=$(cat <<'KIRO_EXTENSION_CONF'
{
  "name": "dracula-sakura",
  "displayName": "Dracula-Sakura",
  "description": "Dark plum, rose, lilac, cyan, and mint theme from vixygrey-dev-setup.",
  "version": "1.0.0",
  "publisher": "vixygrey",
  "engines": {
    "vscode": "^1.80.0"
  },
  "categories": [
    "Themes"
  ],
  "contributes": {
    "themes": [
      {
        "label": "Dracula-Sakura",
        "uiTheme": "vs-dark",
        "path": "./themes/dracula-sakura-color-theme.json"
      }
    ]
  }
}
KIRO_EXTENSION_CONF
)
write_generated "$KIRO_EXTENSION_MANIFEST" <<< "$KIRO_EXTENSION_JSON"

KIRO_THEME_JSON=$(cat <<'KIRO_THEME_CONF'
{
  "$schema": "vscode://schemas/color-theme",
  "name": "Dracula-Sakura",
  "type": "dark",
  "semanticHighlighting": true,
  "colors": {
    "foreground": "#F8F8F2",
    "descriptionForeground": "#A297CB",
    "disabledForeground": "#77748F",
    "focusBorder": "#D4B2FF",
    "errorForeground": "#FF7AA8",
    "icon.foreground": "#DDD2F7",
    "selection.background": "#4B4963",
    "textLink.foreground": "#9BE7FF",
    "textLink.activeForeground": "#B9EEFF",
    "textBlockQuote.background": "#2F3144",
    "textBlockQuote.border": "#D4B2FF",
    "textCodeBlock.background": "#232531",
    "button.background": "#FF9FE3",
    "button.foreground": "#282A36",
    "button.hoverBackground": "#FFC2EC",
    "input.background": "#232531",
    "input.foreground": "#F8F8F2",
    "input.border": "#4B4963",
    "input.placeholderForeground": "#8A88C7",
    "inputOption.activeBorder": "#D4B2FF",
    "dropdown.background": "#2F3144",
    "dropdown.foreground": "#F8F8F2",
    "dropdown.border": "#4B4963",
    "badge.background": "#D4B2FF",
    "badge.foreground": "#282A36",
    "progressBar.background": "#FF9FE3",
    "titleBar.activeBackground": "#282A36",
    "titleBar.activeForeground": "#F8F8F2",
    "titleBar.inactiveBackground": "#2F3144",
    "titleBar.inactiveForeground": "#A297CB",
    "activityBar.background": "#282A36",
    "activityBar.foreground": "#F8F8F2",
    "activityBar.inactiveForeground": "#8A88C7",
    "activityBarBadge.background": "#FF9FE3",
    "activityBarBadge.foreground": "#282A36",
    "sideBar.background": "#2F3144",
    "sideBar.foreground": "#DDD2F7",
    "sideBar.border": "#3B3D52",
    "sideBarTitle.foreground": "#F8F8F2",
    "sideBarSectionHeader.background": "#323448",
    "sideBarSectionHeader.foreground": "#FFC2EC",
    "list.activeSelectionBackground": "#4B4963",
    "list.activeSelectionForeground": "#FFFFFF",
    "list.inactiveSelectionBackground": "#3B3D52",
    "list.inactiveSelectionForeground": "#F8F8F2",
    "list.hoverBackground": "#3B3D52",
    "list.hoverForeground": "#FFFFFF",
    "list.highlightForeground": "#FF9FE3",
    "tree.indentGuidesStroke": "#4B4963",
    "editorGroup.border": "#3B3D52",
    "editorGroupHeader.tabsBackground": "#2F3144",
    "tab.activeBackground": "#282A36",
    "tab.activeForeground": "#F8F8F2",
    "tab.activeBorderTop": "#FF9FE3",
    "tab.inactiveBackground": "#2F3144",
    "tab.inactiveForeground": "#A297CB",
    "tab.hoverBackground": "#3B3D52",
    "editor.background": "#282A36",
    "editor.foreground": "#F8F8F2",
    "editorLineNumber.foreground": "#6272A4",
    "editorLineNumber.activeForeground": "#FFC2EC",
    "editorCursor.foreground": "#FF9FE3",
    "editor.selectionBackground": "#4B4963",
    "editor.inactiveSelectionBackground": "#3B3D52",
    "editor.selectionHighlightBackground": "#D4B2FF33",
    "editor.wordHighlightBackground": "#9BE7FF22",
    "editor.wordHighlightStrongBackground": "#FF9FE333",
    "editor.lineHighlightBackground": "#323448BF",
    "editorWhitespace.foreground": "#4B4963",
    "editorIndentGuide.background1": "#3B3D52",
    "editorIndentGuide.activeBackground1": "#8A88C7",
    "editorBracketHighlight.foreground1": "#FF9FE3",
    "editorBracketHighlight.foreground2": "#D4B2FF",
    "editorBracketHighlight.foreground3": "#9BE7FF",
    "editorBracketHighlight.foreground4": "#8AF7CF",
    "editorBracketHighlight.foreground5": "#FFCF93",
    "editorBracketHighlight.foreground6": "#FF7AA8",
    "editorGutter.addedBackground": "#8AF7CF",
    "editorGutter.modifiedBackground": "#9BE7FF",
    "editorGutter.deletedBackground": "#FF7AA8",
    "editorError.foreground": "#FF7AA8",
    "editorWarning.foreground": "#FFCF93",
    "editorInfo.foreground": "#9BE7FF",
    "editorHint.foreground": "#8AF7CF",
    "editorWidget.background": "#2F3144",
    "editorWidget.foreground": "#F8F8F2",
    "editorWidget.border": "#4B4963",
    "editorSuggestWidget.selectedBackground": "#4B4963",
    "peekView.border": "#D4B2FF",
    "peekViewEditor.background": "#232531",
    "peekViewResult.background": "#2F3144",
    "peekViewResult.selectionBackground": "#4B4963",
    "peekViewTitle.background": "#323448",
    "diffEditor.insertedTextBackground": "#8AF7CF22",
    "diffEditor.removedTextBackground": "#FF7AA822",
    "diffEditor.insertedLineBackground": "#8AF7CF11",
    "diffEditor.removedLineBackground": "#FF7AA811",
    "panel.background": "#282A36",
    "panel.border": "#4B4963",
    "panelTitle.activeBorder": "#FF9FE3",
    "panelTitle.activeForeground": "#F8F8F2",
    "panelTitle.inactiveForeground": "#8A88C7",
    "statusBar.background": "#282A36",
    "statusBar.foreground": "#F8F8F2",
    "statusBar.debuggingBackground": "#FF7AA8",
    "statusBar.debuggingForeground": "#282A36",
    "statusBar.noFolderBackground": "#2F3144",
    "terminal.background": "#282A36",
    "terminal.foreground": "#F8F8F2",
    "terminal.ansiBlack": "#282A36",
    "terminal.ansiBrightBlack": "#6272A4",
    "terminal.ansiRed": "#FF7AA8",
    "terminal.ansiBrightRed": "#FF94B8",
    "terminal.ansiGreen": "#8AF7CF",
    "terminal.ansiBrightGreen": "#A8FFDC",
    "terminal.ansiYellow": "#FFCF93",
    "terminal.ansiBrightYellow": "#FFF0A8",
    "terminal.ansiBlue": "#9BE7FF",
    "terminal.ansiBrightBlue": "#B9EEFF",
    "terminal.ansiMagenta": "#FF9FE3",
    "terminal.ansiBrightMagenta": "#FFC2EC",
    "terminal.ansiCyan": "#8AF7CF",
    "terminal.ansiBrightCyan": "#9BE7FF",
    "terminal.ansiWhite": "#F8F8F2",
    "terminal.ansiBrightWhite": "#FFFFFF",
    "terminalCursor.foreground": "#FF9FE3",
    "notifications.background": "#2F3144",
    "notifications.foreground": "#F8F8F2",
    "notifications.border": "#4B4963",
    "notificationLink.foreground": "#9BE7FF",
    "gitDecoration.addedResourceForeground": "#8AF7CF",
    "gitDecoration.modifiedResourceForeground": "#9BE7FF",
    "gitDecoration.deletedResourceForeground": "#FF7AA8",
    "gitDecoration.untrackedResourceForeground": "#A8FFDC",
    "gitDecoration.ignoredResourceForeground": "#77748F",
    "minimap.background": "#282A36",
    "scrollbar.shadow": "#00000055",
    "scrollbarSlider.background": "#6272A455",
    "scrollbarSlider.hoverBackground": "#8A88C777",
    "scrollbarSlider.activeBackground": "#D4B2FF88"
  },
  "tokenColors": [
    {
      "scope": ["comment", "punctuation.definition.comment"],
      "settings": { "foreground": "#6272A4", "fontStyle": "italic" }
    },
    {
      "scope": ["string", "string.quoted", "markup.inline.raw"],
      "settings": { "foreground": "#FFF0A8" }
    },
    {
      "scope": ["constant.numeric", "constant.language", "constant.character"],
      "settings": { "foreground": "#D4B2FF" }
    },
    {
      "scope": ["keyword", "storage", "storage.type", "storage.modifier"],
      "settings": { "foreground": "#FF9FE3" }
    },
    {
      "scope": ["entity.name.function", "support.function", "meta.function-call"],
      "settings": { "foreground": "#8AF7CF" }
    },
    {
      "scope": ["entity.name.type", "entity.name.class", "support.type", "support.class"],
      "settings": { "foreground": "#9BE7FF" }
    },
    {
      "scope": ["variable.parameter", "meta.function.parameters"],
      "settings": { "foreground": "#FFCF93", "fontStyle": "italic" }
    },
    {
      "scope": ["variable.other.property", "support.variable.property"],
      "settings": { "foreground": "#FF7AA8" }
    },
    {
      "scope": ["entity.name.tag", "punctuation.definition.tag"],
      "settings": { "foreground": "#FF9FE3" }
    },
    {
      "scope": ["entity.other.attribute-name"],
      "settings": { "foreground": "#8AF7CF" }
    },
    {
      "scope": ["markup.heading", "markup.heading entity.name"],
      "settings": { "foreground": "#FFC2EC", "fontStyle": "bold" }
    },
    {
      "scope": ["markup.bold"],
      "settings": { "foreground": "#FFCF93", "fontStyle": "bold" }
    },
    {
      "scope": ["markup.italic"],
      "settings": { "foreground": "#D4B2FF", "fontStyle": "italic" }
    },
    {
      "scope": ["markup.inserted"],
      "settings": { "foreground": "#8AF7CF" }
    },
    {
      "scope": ["markup.deleted"],
      "settings": { "foreground": "#FF7AA8" }
    },
    {
      "scope": ["invalid", "invalid.illegal"],
      "settings": { "foreground": "#FFFFFF", "background": "#FF7AA8" }
    }
  ],
  "semanticTokenColors": {
    "class": "#9BE7FF",
    "enum": "#9BE7FF",
    "interface": "#9BE7FF",
    "struct": "#9BE7FF",
    "type": "#9BE7FF",
    "typeParameter": "#D4B2FF",
    "function": "#8AF7CF",
    "method": "#8AF7CF",
    "property": "#FF7AA8",
    "enumMember": "#D4B2FF",
    "variable": "#F8F8F2",
    "parameter": { "foreground": "#FFCF93", "italic": true },
    "keyword": "#FF9FE3",
    "string": "#FFF0A8",
    "number": "#D4B2FF",
    "comment": { "foreground": "#6272A4", "italic": true }
  }
}
KIRO_THEME_CONF
)
write_generated "$KIRO_THEME" <<< "$KIRO_THEME_JSON"
configured "Kiro Dracula-Sakura theme extension written (~/.kiro/extensions/vixygrey.dracula-sakura-1.0.0)"

KIRO_DEFAULTS=$(cat <<'KIRO_CONF'
{
  "workbench.colorTheme": "Dracula-Sakura",
  "workbench.preferredDarkColorTheme": "Dracula-Sakura",
  "workbench.iconTheme": "vs-seti",
  "workbench.startupEditor": "none",
  "workbench.tree.indent": 16,
  "window.autoDetectColorScheme": false,
  "window.commandCenter": true,
  "editor.fontFamily": "'JetBrains Mono', Menlo, Monaco, monospace",
  "editor.fontSize": 14,
  "editor.fontLigatures": true,
  "editor.fontWeight": "400",
  "editor.lineHeight": 22,
  "editor.minimap.enabled": false,
  "editor.renderWhitespace": "selection",
  "editor.renderControlCharacters": true,
  "editor.smoothScrolling": true,
  "editor.cursorBlinking": "smooth",
  "editor.cursorSmoothCaretAnimation": "on",
  "editor.formatOnSave": true,
  "editor.formatOnPaste": true,
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.detectIndentation": true,
  "editor.wordWrap": "bounded",
  "editor.wordWrapColumn": 100,
  "editor.rulers": [100],
  "editor.linkedEditing": true,
  "editor.stickyScroll.enabled": true,
  "editor.stickyScroll.maxLineCount": 3,
  "editor.inlayHints.enabled": "onUnlessPressed",
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "editor.guides.indentation": true,
  "editor.suggest.preview": true,
  "files.autoSave": "onFocusChange",
  "files.trimTrailingWhitespace": true,
  "files.trimFinalNewlines": true,
  "files.insertFinalNewline": true,
  "files.hotExit": "onExitAndWindowClose",
  "diffEditor.ignoreTrimWhitespace": false,
  "explorer.confirmDelete": true,
  "explorer.confirmDragAndDrop": true,
  "terminal.integrated.defaultProfile.osx": "zsh",
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font",
  "terminal.integrated.fontSize": 13,
  "terminal.integrated.cursorStyle": "line",
  "terminal.integrated.cursorBlinking": true,
  "terminal.integrated.scrollback": 20000,
  "git.autofetch": true,
  "git.openRepositoryInParentFolders": "never",
  "telemetry.telemetryLevel": "off",
  "security.workspace.trust.enabled": true,
  "aws.telemetry": false,
  "aws.cloudformation.telemetry.enabled": false,
  "aws.cloudformation.hover.enabled": true,
  "aws.cloudformation.completion.enabled": true,
  "aws.cloudformation.diagnostics.cfnLint.enabled": true,
  "aws.cloudformation.diagnostics.cfnLint.lintOnChange": true,
  "aws.cloudformation.diagnostics.cfnGuard.enabled": true,
  "aws.cloudformation.diagnostics.cfnGuard.validateOnChange": true,
  "aws.cloudformation.diagnostics.cfnGuard.enabledRulePacks": ["wa-Security-Pillar"],
  "aws.samcli.enableCodeLenses": true,
  "ruff.nativeServer": "on",
  "ruff.lint.enable": true,
  "ruff.organizeImports": true,
  "ruff.fixAll": true,
  "ruff.importStrategy": "fromEnvironment",
  "ruff.showNotifications": "onError",
  "path-intellisense.extensionOnImport": true,
  "path-intellisense.autoSlashAfterDirectory": true,
  "path-intellisense.showHiddenFiles": false,
  "bracket-pair-colorizer-2.colors": [
    "#FF9FE3",
    "#D4B2FF",
    "#9BE7FF",
    "#8AF7CF",
    "#FFCF93"
  ],
  "bracket-pair-colorizer-2.unmatchedScopeColor": "#FF7AA8",
  "bracket-pair-colorizer-2.highlightActiveScope": true,
  "markdownlint.run": "onType",
  "markdownlint.config": {
    "MD013": {
      "line_length": 100,
      "code_blocks": false,
      "tables": false
    }
  },
  "eslint.enable": true,
  "eslint.run": "onType",
  "eslint.format.enable": false,
  "dotnet.formatting.organizeImportsOnFormat": true,
  "dotnet.backgroundAnalysis.analyzerDiagnosticsScope": "openFiles",
  "dotnet.navigation.navigateToDecompiledSources": true,
  "csharp.debug.justMyCode": true,
  "csharp.format.enable": true,
  "omnisharp.enableEditorConfigSupport": true,
  "omnisharp.enableDecompilationSupport": true,
  "css.autoValidation": "Never",
  "editorconfig.generateAuto": false,
  "editorconfig.showMenuEntry": true,
  "prettier.enable": true,
  "prettier.requireConfig": false,
  "prettier.useEditorConfig": true,
  "prettier.printWidth": 100,
  "prettier.endOfLine": "lf",
  "auto-rename-tag.activationOnLanguage": [
    "html",
    "xml",
    "javascript",
    "javascriptreact",
    "typescriptreact",
    "vue",
    "svelte"
  ],
  "todo-tree.general.tags": [
    "BUG",
    "FIXME",
    "HACK",
    "TODO",
    "XXX",
    "[ ]",
    "[x]"
  ],
  "todo-tree.filtering.excludeGlobs": [
    "**/.git/**",
    "**/node_modules/**",
    "**/vendor/**",
    "**/dist/**",
    "**/build/**"
  ],
  "todo-tree.tree.showCountsInTree": true,
  "todo-tree.highlights.customHighlight": {
    "BUG": {"icon": "bug", "foreground": "#FF7AA8"},
    "FIXME": {"icon": "flame", "foreground": "#FF7AA8"},
    "HACK": {"icon": "tools", "foreground": "#FFCF93"},
    "TODO": {"icon": "check", "foreground": "#9BE7FF"}
  },
  "lldb-dap.captureSessionLogs": false,
  "lldb-dap.disableASLR": false,
  "lldb-dap.enableAutoVariableSummaries": true,
  "git-graph.repository.fetchAndPrune": true,
  "git-graph.repository.fetchAndPruneTags": true,
  "git-graph.repository.onLoad.showCheckedOutBranch": true,
  "git-graph.graph.colours": [
    "#FF9FE3",
    "#D4B2FF",
    "#9BE7FF",
    "#8AF7CF",
    "#FFCF93",
    "#FF7AA8"
  ],
  "containers.images.checkForOutdatedImages": false,
  "containers.networks.showBuiltInNetworks": false,
  "containers.enableComposeLanguageService": true,
  "dotnetAcquisitionExtension.enableTelemetry": false,
  "dotnetAcquisitionExtension.enablePreviewFeatures": false,
  "python.analysis.autoImportCompletions": true,
  "python.analysis.diagnosticMode": "openFilesOnly",
  "python.analysis.typeCheckingMode": "standard",
  "debugpy.debugJustMyCode": true,
  "debugpy.showPythonInlineValues": true,
  "python.defaultInterpreterPath": "python",
  "python.languageServer": "Default",
  "python.experiments.enabled": false,
  "python.testing.promptToConfigure": false,
  "python-envs.defaultEnvManager": "ms-python.python:venv",
  "python-envs.defaultPackageManager": "ms-python.python:pip",
  "python-envs.terminal.autoActivationType": "command",
  "python-envs.alwaysUseUv": true,
  "indentRainbow.colors": [
    "rgba(255,159,227,0.08)",
    "rgba(212,178,255,0.08)",
    "rgba(155,231,255,0.08)",
    "rgba(138,247,207,0.08)"
  ],
  "indentRainbow.errorColor": "rgba(255,122,168,0.35)",
  "indentRainbow.tabmixColor": "rgba(255,207,147,0.35)",
  "redhat.telemetry.enabled": false,
  "xml.downloadExternalResources.enabled": false,
  "xml.format.enabled": true,
  "xml.format.maxLineWidth": 100,
  "xml.validation.enabled": true,
  "xml.validation.disallowDocTypeDecl": true,
  "yaml.format.enable": true,
  "yaml.format.printWidth": 100,
  "yaml.validate": true,
  "yaml.hover": true,
  "yaml.completion": true,
  "yaml.schemaStore.enable": true,
  "liveServer.settings.port": 5500,
  "liveServer.settings.host": "127.0.0.1",
  "liveServer.settings.useLocalIp": false,
  "liveServer.settings.cors": false,
  "rust-client.autoStartRls": false,
  "rust-client.disableRustup": true,
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.check.workspace": true,
  "rust-analyzer.cargo.allTargets": true,
  "rust-analyzer.procMacro.enable": true,
  "rust-analyzer.inlayHints.closingBraceHints.minLines": 20,
  "rust-analyzer.runnables.extraTestBinaryArgs": ["--nocapture"],
  "trailing-spaces.trimOnSave": true,
  "trailing-spaces.showStatusBarMessage": false,
  "trailing-spaces.backgroundColor": "rgba(255,122,168,0.25)",
  "markdown-preview-enhanced.scrollSync": true,
  "markdown-preview-enhanced.liveUpdate": true,
  "markdown-preview-enhanced.previewColorScheme": "editorColorScheme",
  "markdown-preview-enhanced.mathRenderingOption": "KaTeX",
  "markdown-preview-enhanced.mermaidTheme": "dark",
  "markdown-preview-enhanced.enableScriptExecution": false,
  "markdown-preview-enhanced.enablePreviewScripts": false,
  "markdown-preview-enhanced.d2Path": "d2",
  "cSpell.useGitignore": true,
  "cSpell.language": "en",
  "cSpell.diagnosticLevel": "Information",
  "cSpell.minWordLength": 4,
  "stylelint.enable": true,
  "stylelint.run": "onType",
  "stylelint.validate": ["css", "scss", "sass", "less", "postcss"],
  "evenBetterToml.taplo.bundled": true,
  "evenBetterToml.taplo.configFile.enabled": true,
  "evenBetterToml.schema.enabled": true,
  "evenBetterToml.schema.links": false,
  "evenBetterToml.formatter.columnWidth": 100,
  "evenBetterToml.formatter.trailingNewline": true,
  "shellcheck.enable": true,
  "shellcheck.enableQuickFix": true,
  "shellcheck.run": "onType",
  "shellcheck.useWorkspaceRootAsCwd": true,
  "errorLens.enabled": true,
  "errorLens.messageMaxChars": 180,
  "errorLens.messageBackgroundMode": "message",
  "errorLens.gutterIconsEnabled": true,
  "lldb.consoleMode": "commands",
  "lldb.evaluationTimeout": 5,
  "lldb.showDisassembly": "auto",
  "lldb.dereferencePointers": true,
  "html-css-class-completion.enableEmmetSupport": true,
  "[markdown]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.wordWrap": "on",
    "editor.quickSuggestions": {
      "comments": "off",
      "strings": "off",
      "other": "off"
    }
  },
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.tabSize": 4,
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  },
  "[go]": {
    "editor.tabSize": 4,
    "editor.insertSpaces": false
  },
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.tabSize": 4
  },
  "[toml]": {
    "editor.defaultFormatter": "tamasfe.even-better-toml"
  },
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml"
  },
  "[xml]": {
    "editor.defaultFormatter": "redhat.vscode-xml"
  },
  "[csharp]": {
    "editor.defaultFormatter": "dotnetdev-kr-custom.csharp",
    "editor.tabSize": 4
  },
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[jsonc]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[html]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[css]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[scss]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
KIRO_CONF
)

# Kiro can rewrite settings as JSONC with trailing commas. Normalize that
# specific syntax before the JSON merge. Other JSONC syntax fails closed.
KIRO_MERGE_FILE="$KIRO_CONFIG"
KIRO_JSONC_TMP=""
if [[ "$DRY_RUN" != "true" && -f "$KIRO_CONFIG" ]] && installed jq &&
   ! jq -e . "$KIRO_CONFIG" &>/dev/null; then
    KIRO_JSONC_TMP="$(mktemp)"
    if normalize_editor_jsonc "$KIRO_CONFIG" "$KIRO_JSONC_TMP"; then
        KIRO_MERGE_FILE="$KIRO_JSONC_TMP"
    else
        rm -f "$KIRO_JSONC_TMP"
        KIRO_JSONC_TMP=""
    fi
fi

# The house theme is an owned choice. Preserve every unrelated user setting.
KIRO_SETTINGS_FILTER='
  .["workbench.colorTheme"] = "Dracula-Sakura"
  | .["workbench.preferredDarkColorTheme"] = "Dracula-Sakura"
'
if merge_json_defaults "$KIRO_CONFIG" "$KIRO_SETTINGS_FILTER" "$KIRO_MERGE_FILE" <<< "$KIRO_DEFAULTS"; then
    [[ -n "$KIRO_JSONC_TMP" ]] && rm -f "$KIRO_JSONC_TMP"
    [[ "$DRY_RUN" == "true" ]] \
        || success "Kiro settings merged with Dracula-Sakura defaults. Your other settings remain."
else
    _kiro_merge_status=$?
    [[ -n "$KIRO_JSONC_TMP" ]] && rm -f "$KIRO_JSONC_TMP"
    if [[ "$_kiro_merge_status" -eq 2 ]]; then
        warn "Kiro settings exist, but jq is missing. New defaults did not merge."
    else
        warn "Could not merge Kiro settings. The script left $KIRO_CONFIG unchanged."
    fi
    unset _kiro_merge_status
fi

# Remove only the old named theme that carries this generator's provenance.
# Zed settings can include user changes, so they remain untouched.
ZED_THEME_SUPERSEDED="$HOME/.config/zed/themes/dracula-sakura.json"
if [[ -f "$ZED_THEME_SUPERSEDED" ]] && installed jq &&
   jq -e '.author == "vixygrey-dev-setup" and .name == "Dracula-Sakura"' \
      "$ZED_THEME_SUPERSEDED" &>/dev/null; then
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove the superseded generated Zed Dracula-Sakura theme (#589)"
    else
        rm -f "$ZED_THEME_SUPERSEDED"
        info "Removed the superseded generated Zed Dracula-Sakura theme (#589)"
    fi
fi

unset KIRO_CONFIG_DIR KIRO_CONFIG KIRO_STEERING_DIR KIRO_AGENTS KIRO_EXTENSION_DIR KIRO_EXTENSION_MANIFEST KIRO_THEME
unset KIRO_EXTENSION_JSON KIRO_THEME_JSON KIRO_DEFAULTS KIRO_MERGE_FILE KIRO_JSONC_TMP
unset KIRO_SETTINGS_FILTER ZED_THEME_SUPERSEDED

# ---- Emeraldian Obsidian vault TUI ----
# Emeraldian uses the macOS Application Support directory. Its custom themes sit
# beside config.toml. The starter config stays user-owned after creation because
# Emeraldian writes settings from the TUI.
EMERALDIAN_CONFIG_DIR="$HOME/Library/Application Support/emeraldian"
EMERALDIAN_CONFIG="$EMERALDIAN_CONFIG_DIR/config.toml"
EMERALDIAN_THEME="$EMERALDIAN_CONFIG_DIR/themes/dracula-sakura.toml"

write_generated "$EMERALDIAN_THEME" <<'EMERALDIAN_THEME_CONF'
name = "dracula-sakura"
extends = "dracula"
dark = true

bg_primary = "#282a36"
bg_primary_alt = "#2f3144"
bg_secondary = "#232530"
bg_secondary_alt = "#1f202b"
bg_hover = "#323448"
bg_active = "#4b4963"
bg_selection = "#4b4963"
border = "#4b4963"
border_focus = "#ff9fe3"
text_normal = "#f8f8f2"
text_muted = "#c6bce5"
text_faint = "#8a88c7"
text_accent = "#ff9fe3"
text_on_accent = "#282a36"
text_error = "#ff7aa8"
text_warning = "#ffcf93"
text_success = "#8af7cf"
text_info = "#9be7ff"
accent = "#ff9fe3"
accent_hover = "#ffc2ec"
h1 = "#ffc2ec"
h2 = "#ff9fe3"
h3 = "#d4b2ff"
h4 = "#9be7ff"
h5 = "#8af7cf"
h6 = "#fff0a8"
link = "#9be7ff"
link_unresolved = "#ff7aa8"
tag_fg = "#ffc2ec"
tag_bg = "#323448"
code_fg = "#f8f8f2"
code_bg = "#232530"
syn_keyword = "#ff9fe3"
syn_string = "#fff0a8"
syn_comment = "#8a88c7"
syn_number = "#ffcf93"
syn_function = "#8af7cf"
syn_type = "#9be7ff"
graph_bg = "#282a36"
graph_node = "#d4b2ff"
graph_node_focused = "#ff9fe3"
graph_node_neighbor = "#9be7ff"
graph_node_unresolved = "#8a88c7"
graph_node_tag = "#8af7cf"
graph_edge = "#c6bce5"
graph_edge_active = "#ff9fe3"
cursor = "#ffc2ec"
cursor_line_bg = "#2f3144"
EMERALDIAN_THEME_CONF

if write_seed_once "$EMERALDIAN_CONFIG" \
    "edit in Emeraldian with :mkconfig or the command palette" \
    <<'EMERALDIAN_CONFIG_CONF'
theme = "dracula-sakura"

[ui]
show_hints = true
show_hidden = false
line_numbers = true
reading_mode = true
sort_order = "modified"

[editor]
tab_width = 4
expand_tabs = true
wrap = true
vim = false
auto_save = true
daily_folder = "Daily"
daily_format = "%Y-%m-%d"

[images]
enabled = true
max_height_percent = 66
protocol = "auto"

[agent]
provider = "offline"
allow_writes = false
include_active_note = false
EMERALDIAN_CONFIG_CONF
then
    configured "Emeraldian starter config and Dracula-Sakura theme configured"
elif set_toml_top_level_string "$EMERALDIAN_CONFIG" theme "dracula-sakura"; then
    configured "Emeraldian existing config selected the Dracula-Sakura theme"
else
    _emeraldian_theme_status=$?
    if [[ "$_emeraldian_theme_status" -eq 2 ]]; then
        warn "Emeraldian config exists, but python3 is missing. The theme selection did not change."
    else
        warn "Could not update the Emeraldian theme setting. The script left $EMERALDIAN_CONFIG unchanged."
    fi
    unset _emeraldian_theme_status
fi
unset EMERALDIAN_CONFIG_DIR EMERALDIAN_CONFIG EMERALDIAN_THEME

# Linecast was removed from the setup. Its JSON was merged into a user-owned
# file, so the managed-marker ownership check deliberately retains that file.
remove_superseded_managed "$HOME/.config/linecast/config.json" \
    "Linecast was removed from the setup" "(#572)"

# ---- Croft terminal IDE ----
# Croft loads user themes from extension manifests and deep-merges its JSON
# preference layers. The config merge preserves unrelated user settings.
CROFT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/croft"
CROFT_CONFIG="$CROFT_CONFIG_DIR/config.json"
CROFT_THEME="$CROFT_CONFIG_DIR/extensions/dracula-sakura/extension.toml"

write_generated "$CROFT_THEME" <<'CROFT_THEME_CONF'
id = "vixygrey-dracula-sakura"
name = "Dracula-Sakura"
description = "Dark plum surfaces with rose, lilac, cyan, and mint accents."
builtin = false
api_version = 1

[[themes]]
id = "dracula-sakura"
label = "Dracula-Sakura"
background = "#282a36"
accent = "#ff9fe3"
selection = "#4b4963"
search = "#232530"
button = "#ff9fe3"
gradient = false
osk_key = "#323448"
osk_special = "#232530"
osk_armed = "#d4b2ff"
tab_strip = "#2f3144"
tab_inactive = "#323448"
tab_active = "#4b4963"
tab_hover = "#5d5878"
tab_close_pill = "#ff9fe3"
syn_comment = "#8a88c7"
syn_keyword = "#ff9fe3"
syn_string = "#fff0a8"
syn_constant = "#d4b2ff"
syn_function = "#8af7cf"
syn_type = "#9be7ff"
syn_tag = "#ff7aa8"
syn_fg = "#f8f8f2"
ansi = ["#232530","#ff7aa8","#8af7cf","#fff0a8","#8bb8ff","#ff9fe3","#9be7ff","#f8f8f2","#6f6990","#ff9abb","#a8ffe3","#fff5bf","#a8c8ff","#ffc2ec","#b9eeff","#ffffff"]
CROFT_THEME_CONF

if merge_json_defaults "$CROFT_CONFIG" '.theme = "dracula-sakura"' <<'CROFT_CONFIG_CONF'
{
  "theme": "dracula-sakura",
  "format_on_save": true,
  "render_whitespace": "selection",
  "copy_on_select": true,
  "terminal_scrollback": 20000,
  "problems_scope": "whole_project",
  "problems_project_scope": "auto",
  "diff_ignore_whitespace": "off"
}
CROFT_CONFIG_CONF
then
    configured "Croft defaults and Dracula-Sakura theme configured"
else
    _croft_merge_status=$?
    if [[ "$_croft_merge_status" -eq 2 ]]; then
        warn "Croft settings exist, but jq is missing. New defaults did not merge."
    else
        warn "Could not merge Croft settings. The script left $CROFT_CONFIG unchanged."
    fi
    unset _croft_merge_status
fi
unset CROFT_CONFIG_DIR CROFT_CONFIG CROFT_THEME

# ---- Obsidian per-vault theme ----
# Obsidian stores custom themes inside each vault. Read its registry instead of
# assuming a notes path, then refresh only theme directories this script owns.
OBSIDIAN_REGISTRY="$HOME/Library/Application Support/obsidian/obsidian.json"
OBSIDIAN_THEME_NAME="Dracula-Sakura"
OBSIDIAN_THEME_MANIFEST=$(cat <<'OBSIDIAN_MANIFEST_CONF'
{
  "name": "Dracula-Sakura",
  "version": "1.0.0",
  "minAppVersion": "1.0.0",
  "author": "vixygrey-dev-setup"
}
OBSIDIAN_MANIFEST_CONF
)
OBSIDIAN_THEME_CSS=$(cat <<'OBSIDIAN_THEME_CONF'
/*
 * Dracula-Sakura for Obsidian.
 * Dark plum surfaces use rose, lilac, cyan, and mint accents.
 */
.theme-dark,
.theme-light {
  color-scheme: dark;

  --accent-h: 319;
  --accent-s: 100%;
  --accent-l: 81%;

  --color-red: #ff7aa8;
  --color-orange: #ffcf93;
  --color-yellow: #fff0a8;
  --color-green: #8af7cf;
  --color-cyan: #9be7ff;
  --color-blue: #8bb8ff;
  --color-purple: #d4b2ff;
  --color-pink: #ff9fe3;

  --color-base-00: #282a36;
  --color-base-05: #2c2e3c;
  --color-base-10: #2f3144;
  --color-base-20: #323448;
  --color-base-25: #383a50;
  --color-base-30: #4b4963;
  --color-base-35: #5d5878;
  --color-base-40: #6f6990;
  --color-base-50: #8a88c7;
  --color-base-60: #a297cb;
  --color-base-70: #c6bce5;
  --color-base-100: #f8f8f2;

  --color-accent: #ff9fe3;
  --color-accent-1: #ffc2ec;
  --color-accent-2: #d4b2ff;

  --background-primary: #282a36;
  --background-primary-alt: #2c2e3c;
  --background-secondary: #2f3144;
  --background-secondary-alt: #323448;
  --background-modifier-hover: #3b3d52;
  --background-modifier-active-hover: #4b4963;
  --background-modifier-border: #4b4963;
  --background-modifier-border-hover: #6f6990;
  --background-modifier-border-focus: #d4b2ff;
  --background-modifier-form-field: #323448;
  --background-modifier-error: #ff7aa8;
  --background-modifier-warning: #ffcf93;
  --background-modifier-success: #8af7cf;

  --text-normal: #f8f8f2;
  --text-muted: #c6bce5;
  --text-faint: #8a88c7;
  --text-on-accent: #282a36;
  --text-on-accent-inverted: #f8f8f2;
  --text-error: #ff7aa8;
  --text-warning: #ffcf93;
  --text-success: #8af7cf;
  --text-accent: #ff9fe3;
  --text-accent-hover: #ffc2ec;
  --text-selection: rgba(212, 178, 255, 0.28);
  --text-highlight-bg: rgba(255, 240, 168, 0.28);

  --interactive-normal: #323448;
  --interactive-hover: #3b3d52;
  --interactive-accent: #ff9fe3;
  --interactive-accent-hover: #ffc2ec;

  --titlebar-background: #282a36;
  --titlebar-background-focused: #282a36;
  --titlebar-text-color: #a297cb;
  --titlebar-text-color-focused: #f8f8f2;
  --tab-container-background: #2f3144;
  --tab-outline-color: #4b4963;
  --tab-text-color: #a297cb;
  --tab-text-color-active: #f8f8f2;
  --tab-text-color-focused-active: #ffc2ec;

  --nav-item-color: #c6bce5;
  --nav-item-color-hover: #f8f8f2;
  --nav-item-color-active: #ffc2ec;
  --nav-item-background-hover: #3b3d52;
  --nav-item-background-active: #4b4963;

  --h1-color: #ffc2ec;
  --h2-color: #ff9fe3;
  --h3-color: #d4b2ff;
  --h4-color: #9be7ff;
  --h5-color: #8af7cf;
  --h6-color: #fff0a8;
  --link-color: #9be7ff;
  --link-color-hover: #b9eeff;
  --link-unresolved-color: #ff7aa8;
  --tag-color: #ffc2ec;
  --tag-background: rgba(255, 159, 227, 0.13);
  --tag-background-hover: rgba(255, 159, 227, 0.23);
  --tag-border-color: rgba(255, 159, 227, 0.34);

  --code-background: #232530;
  --code-normal: #f8f8f2;
  --code-comment: #8a88c7;
  --code-function: #8af7cf;
  --code-important: #ffcf93;
  --code-keyword: #ff9fe3;
  --code-operator: #ffc2ec;
  --code-property: #ff7aa8;
  --code-punctuation: #ddd2f7;
  --code-string: #fff0a8;
  --code-tag: #9be7ff;
  --code-value: #d4b2ff;

  --blockquote-border-color: #d4b2ff;
  --blockquote-color: #c6bce5;
  --checkbox-color: #ff9fe3;
  --checkbox-color-hover: #ffc2ec;
  --hr-color: #4b4963;
  --graph-line: #4b4963;
  --graph-node: #d4b2ff;
  --graph-node-focused: #ff9fe3;
  --graph-node-tag: #8af7cf;
  --graph-node-attachment: #9be7ff;
}

.workspace-tab-header.is-active {
  box-shadow: inset 0 -2px 0 #ff9fe3;
}

.markdown-rendered mark,
mark {
  color: #282a36;
  border-radius: 3px;
  padding: 0 0.15em;
}
OBSIDIAN_THEME_CONF
)

OBSIDIAN_VAULTS=()
if [[ -f "$OBSIDIAN_REGISTRY" ]]; then
    if ! installed jq; then
        warn "Obsidian vault registry exists, but jq is missing. Theme installation stopped."
    elif ! jq -e '.vaults | type == "object"' "$OBSIDIAN_REGISTRY" &>/dev/null; then
        warn "Obsidian vault registry is malformed. The script left all vaults unchanged."
    else
        mapfile -t OBSIDIAN_VAULTS < <(jq -r '.vaults[]? | .path // empty' "$OBSIDIAN_REGISTRY")
    fi
fi

if [[ "${#OBSIDIAN_VAULTS[@]}" -eq 0 ]]; then
    info "No registered Obsidian vaults found. After you create a vault, run --only configs."
fi

for OBSIDIAN_VAULT in "${OBSIDIAN_VAULTS[@]}"; do
    if [[ ! -d "$OBSIDIAN_VAULT" ]]; then
        warn "Obsidian vault path does not exist: $OBSIDIAN_VAULT"
        continue
    fi

    OBSIDIAN_THEME_DIR="$OBSIDIAN_VAULT/.obsidian/themes/$OBSIDIAN_THEME_NAME"
    OBSIDIAN_THEME_MARKER="$OBSIDIAN_THEME_DIR/.dev-setup-owned"
    if [[ -e "$OBSIDIAN_THEME_DIR" && ! -f "$OBSIDIAN_THEME_MARKER" ]]; then
        warn "Obsidian theme directory is not script-owned: $OBSIDIAN_THEME_DIR"
        warn "The script left this directory unchanged."
        continue
    fi

    write_generated "$OBSIDIAN_THEME_MARKER" <<'OBSIDIAN_THEME_MARKER_CONF'
Dracula-Sakura theme generated by vixygrey-dev-setup.
OBSIDIAN_THEME_MARKER_CONF
    write_generated "$OBSIDIAN_THEME_DIR/manifest.json" <<< "$OBSIDIAN_THEME_MANIFEST"
    write_generated "$OBSIDIAN_THEME_DIR/theme.css" <<< "$OBSIDIAN_THEME_CSS"

    if merge_json_defaults "$OBSIDIAN_VAULT/.obsidian/appearance.json" <<'OBSIDIAN_APPEARANCE_CONF'
{
  "baseTheme": "dark",
  "cssTheme": "Dracula-Sakura"
}
OBSIDIAN_APPEARANCE_CONF
    then
        configured "Obsidian Dracula-Sakura theme installed in $OBSIDIAN_VAULT"
    else
        warn "Could not merge the Obsidian appearance settings."
        warn "The script left $OBSIDIAN_VAULT/.obsidian/appearance.json unchanged."
    fi
done

unset OBSIDIAN_REGISTRY OBSIDIAN_THEME_NAME OBSIDIAN_THEME_MANIFEST OBSIDIAN_THEME_CSS
unset OBSIDIAN_VAULTS OBSIDIAN_VAULT OBSIDIAN_THEME_DIR OBSIDIAN_THEME_MARKER




# ---- Fonts (required for icons in eza, starship, lazygit, etc.) ----
info "Installing development fonts..."

brew_cask_install_batch \
    "font-jetbrains-mono|JetBrains Mono (primary dev font)" \
    "font-jetbrains-mono-nerd-font|JetBrains Mono Nerd Font (with icons)" \
    "font-inter|Inter (best UI font for web/design)" || true
brew_cask_install "font-jetbrains-mono" "JetBrains Mono (primary dev font)"
brew_cask_install "font-jetbrains-mono-nerd-font" "JetBrains Mono Nerd Font (with icons)"
brew_cask_install "font-inter" "Inter (best UI font for web/design)"

configured "Development fonts installed"

# ---- shellcheck config ----
SHELLCHECK_RC="$HOME/.shellcheckrc"
    info "Creating shellcheck configuration..."
    write_managed "$SHELLCHECK_RC" "#" <<'SHELLCHECK_CONF'
# Follow sourced files
external-sources=true

# Disable common false positives
# SC1091: Not following sourced file (not input)
# SC2034: Variable appears unused (often used in sourced files)
disable=SC1091,SC2034
SHELLCHECK_CONF
    configured "shellcheck configured"

# ---- leaf (Markdown previewer) config ----
# leaf is a viewer, not an editor: Ctrl+E hands the file off to an external
# editor. leaf IGNORES $EDITOR — its priority is
#   --editor flag > LEAF_EDITOR > config.toml > nano
# so without this it falls back to nano. Point it at micro to match the rest of
# the setup. micro FILE +LINE opens at the first visible source line; pair
# with `leaf --watch` for live reload. Path: $XDG_CONFIG_HOME/leaf/config.toml.
LEAF_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/leaf/config.toml"
if ! is_done "config:leaf"; then
    info "Configuring leaf (Ctrl+E opens micro)..."
    write_managed "$LEAF_CONFIG" "#" <<'LEAF_CONF'
# Ctrl+E hands off editing to micro (leaf ignores $EDITOR).
editor = 'micro {$path} +{$line}'
LEAF_CONF
    configured "leaf configured (Ctrl+E opens micro at the current line)"
    mark_done "config:leaf"
fi

# ---- ngrok config ----
# ngrok on macOS reads ~/Library/Application Support/ngrok/ngrok.yml and nothing else
# — NOT $XDG_CONFIG_HOME/ngrok, where this seed template used to land and was never
# once read (#332). `ngrok config check` and `ngrok config add-authtoken --help` both
# name that path as the default. It is hardcoded here rather than scraped out of
# --help, which is brittle; --verify is what re-checks it against the live tool.
NGROK_CONFIG_DIR="$HOME/Library/Application Support/ngrok"
NGROK_CONFIG="$NGROK_CONFIG_DIR/ngrok.yml"
NGROK_STRANDED_CONFIG="$HOME/.config/ngrok/ngrok.yml"
if ! is_done "config:ngrok"; then
# The template is materialized ONCE and then used for both jobs below — seeding a
# fresh machine, and recognizing our own stranded copy well enough to delete it. A
# second inline copy would be free to drift out of step with this one, and the only
# symptom would be the cleanup silently never matching again.
_ngrok_seed="$(mktemp)"
cat > "$_ngrok_seed" <<'NGROK_CONF'
# ngrok configuration
# Add your authtoken: ngrok config add-authtoken <TOKEN>
version: "3"
agent:
  metadata: "dev-machine"
NGROK_CONF

# Deliberately create-once (#277): this is a SEED TEMPLATE, not managed config.
# `ngrok config add-authtoken <TOKEN>` — which POST_SETUP_CHECKLIST tells you to run —
# writes the token into this file, so refreshing it on every run would clobber the
# user's credential. Changes to the template only reach fresh machines, and that is
# the correct trade here. Routed through write_seed_once, keyed on the FILE not the
# directory: add-authtoken creates both, so on a machine that ran it first the
# directory is already there (#536).
if write_seed_once "$NGROK_CONFIG" "ngrok add-authtoken writes your token here" < "$_ngrok_seed"; then
    if [[ "$DRY_RUN" != "true" ]]; then
        # Lock down: ngrok.yml will hold your authtoken.
        chmod 700 "$NGROK_CONFIG_DIR" 2>/dev/null || true
        chmod 600 "$NGROK_CONFIG" 2>/dev/null || true
    fi
    configured "ngrok config created (add authtoken: ngrok config add-authtoken <TOKEN>)"
fi

# Clear the copy stranded at ~/.config/ngrok by earlier versions — but ONLY when it is
# byte-identical to the template we shipped. Anything else is either a deliberate
# `ngrok --config` setup or an edited file, and either could hold an authtoken. Do not
# read it, do not migrate it, do not print it: say where the real config lives and stop.
if [[ -f "$NGROK_STRANDED_CONFIG" ]]; then
    if ! cmp -s "$_ngrok_seed" "$NGROK_STRANDED_CONFIG"; then
        warn "Left $NGROK_STRANDED_CONFIG alone — it differs from the template this script wrote, so it may be a deliberate 'ngrok --config' setup or hold an authtoken. ngrok itself reads $NGROK_CONFIG"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove the stranded ngrok seed config at $NGROK_STRANDED_CONFIG (#332)"
    else
        rm -f "$NGROK_STRANDED_CONFIG"
        rmdir "$HOME/.config/ngrok" 2>/dev/null || true
        info "Removed the stranded ngrok seed config — ngrok reads $NGROK_CONFIG (#332)"
    fi
fi
rm -f "$_ngrok_seed"
mark_done "config:ngrok"
fi

# ---- yt-dlp config ----
YT_DLP_CONFIG_DIR="$HOME/.config/yt-dlp"
YT_DLP_CONFIG="$YT_DLP_CONFIG_DIR/config"
    info "Creating yt-dlp configuration..."
    write_managed "$YT_DLP_CONFIG" "#" <<'YTDLP_CONF'
# yt-dlp configuration

# Best quality video + audio, merge to mp4
-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best

# Output template: organize by uploader
-o ~/Downloads/%(uploader)s/%(title)s.%(ext)s

# Embed metadata and thumbnail
--embed-metadata
--embed-thumbnail

# Download subtitles if available
--write-auto-subs
--sub-lang en

# Use aria2c for faster downloads
--downloader aria2c
--downloader-args aria2c:"-x 16 -s 16 -k 1M"

# Don't overwrite existing files
--no-overwrites

# Restrict filenames to ASCII
--restrict-filenames
YTDLP_CONF
    configured "yt-dlp configured (best quality, aria2c downloader, metadata)"

# difftastic aliases already configured in git global settings above

# Caddy was removed from the setup (#555). Its create-once Caddyfile can contain
# user changes, so normal runs and --cleanup leave that file untouched.

# ---- act config (GitHub Actions local runner) ----
ACT_CONFIG="$HOME/.actrc"
    info "Creating act configuration..."
    write_managed "$ACT_CONFIG" "#" <<'ACT_CONF'
# act configuration (run GitHub Actions locally)

# Use medium-sized Ubuntu image (good balance of speed vs compatibility)
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=catthehacker/ubuntu:act-20.04

# Reuse containers between runs (faster)
--reuse

# Force amd64 containers on Apple Silicon — many actions ship amd64-only binaries,
# and act prints a warning on every run without this (containers run under emulation).
--container-architecture linux/amd64
ACT_CONF
    configured "act configured (medium Ubuntu images, container reuse)"

# ---- Retired tflint config cleanup ----
remove_superseded_managed "$HOME/.tflint.hcl" \
    "tflint was retired from this setup" "(#578)"

# ---- trippy Dracula-Sakura theme ----
# trippy theme colors are hex WITHOUT the leading '#' (or named colors). Item names
# come from `trip --print-tui-theme-items`; trippy validates the file, so keep them exact.
TRIPPY_CONFIG="$HOME/.config/trippy/trippy.toml"
    info "Creating trippy Dracula-Sakura theme..."
    write_managed "$TRIPPY_CONFIG" "#" <<'TRIPPY_CONF'
[theme-colors]
bg-color = "282a36"
border-color = "4b4963"
text-color = "f8f8f2"
tab-text-color = "d4b2ff"
hops-table-header-bg-color = "323448"
hops-table-header-text-color = "ddd2f7"
hops-table-row-active-text-color = "ff9fe3"
hops-table-row-inactive-text-color = "8a88c7"
hops-chart-selected-color = "d4b2ff"
hops-chart-unselected-color = "8a88c7"
hops-chart-axis-color = "8a88c7"
frequency-chart-bar-color = "d4b2ff"
frequency-chart-text-color = "f8f8f2"
flows-chart-bar-selected-color = "8af7cf"
flows-chart-bar-unselected-color = "8a88c7"
flows-chart-text-current-color = "8af7cf"
flows-chart-text-non-current-color = "ddd2f7"
samples-chart-color = "9be7ff"
samples-chart-lost-color = "ff7aa8"
help-dialog-bg-color = "323448"
help-dialog-text-color = "f8f8f2"
settings-dialog-bg-color = "323448"
settings-tab-text-color = "d4b2ff"
info-bar-bg-color = "323448"
info-bar-text-color = "f8f8f2"
map-world-color = "ddd2f7"
map-radius-color = "ffcf93"
map-selected-color = "ff9fe3"
TRIPPY_CONF
    configured "trippy Dracula-Sakura theme configured"

# Retired tool configs are removed only when their managed blocks prove ownership.
remove_superseded_managed "$HOME/.mlrrc" \
    "miller was removed from the setup" "(#555)"

# ---- retired asciinema config ----
remove_superseded_managed "$HOME/.config/asciinema/config.toml" \
    "asciinema was removed from the setup" "(#542)"
remove_superseded_managed "$HOME/.config/asciinema/config" \
    "asciinema was removed from the setup" "(#542)"

# ---- gh-dash config ----
GH_DASH_CONFIG_DIR="$HOME/.config/gh-dash"
GH_DASH_CONFIG="$GH_DASH_CONFIG_DIR/config.yml"
    if installed gh && gh extension list 2>/dev/null | grep -q "gh-dash"; then
        info "Creating gh-dash configuration..."
        write_managed "$GH_DASH_CONFIG" "#" <<'GHDASH_CONF'
# gh-dash configuration
prSections:
  - title: My PRs
    filters: is:open author:@me
  - title: Needs Review
    filters: is:open review-requested:@me
  - title: Team PRs
    filters: is:open org:@me

issuesSections:
  - title: My Issues
    filters: is:open author:@me
  - title: Assigned to Me
    filters: is:open assignee:@me

defaults:
  preview:
    open: true
    width: 60

theme:
  colors:
    text:
      primary: "#f8f8f2"
      secondary: "#ddd2f7"
      inverted: "#282a36"
      faint: "#8a88c7"
      warning: "#ffcf93"
      success: "#8af7cf"
    border:
      primary: "#d4b2ff"
      secondary: "#4b4963"
      faint: "#323448"
    bg:
      selected: "#6a5d86"
GHDASH_CONF
        configured "gh-dash configured (Dracula-Sakura theme, PR/issue sections)"
    fi

# ---- Retired stern config cleanup ----
remove_superseded_managed "$HOME/.config/stern/config.yaml" \
    "stern was retired from this setup" "(#578)"

# ---- zellij config ----
if installed zellij; then
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"
ZELLIJ_CONFIG="$ZELLIJ_CONFIG_DIR/config.kdl"
info "Configuring zellij (Dracula Sakura theme, close to stock behavior)..."
write_managed "$ZELLIJ_CONFIG" "//" <<'ZELLIJ_CONF'
// Zellij configuration — Dracula Sakura theme, close to stock behavior

// Copy on select
copy_on_select true

// Dracula Sakura color theme
themes {
    dracula-sakura {
        fg "#f8f8f2"
        bg "#282a36"
        black "#21222c"
        red "#ff7aa8"
        green "#8af7cf"
        yellow "#fff0a8"
        blue "#d4b2ff"
        magenta "#ff9fe3"
        cyan "#9be7ff"
        white "#f8f8f2"
        orange "#ffcf93"
    }
}

theme "dracula-sakura"

// Default layout — "default", NOT "compact" (#481).
//
// The difference is not cosmetic. `zellij setup --dump-layout` shows the bars are
// explicit plugin panes, not implicit chrome:
//
//   default:  tab-bar + <panes> + status-bar
//   compact:            <panes> + compact-bar
//
// `status-bar` is the plugin that draws the per-mode keybinding hints, so
// "compact" does not shrink the hints, it removes them. Zellij is modal
// (Ctrl+p pane, Ctrl+t tab, Ctrl+n resize, Ctrl+s scroll, Ctrl+o session,
// Ctrl+h move, Ctrl+g lock), and a modal UI with no visible mode line is
// undiscoverable. Two rows is the right price for that.
default_layout "default"
default_mode "normal"

// Pane frames
pane_frames true
pane_frame_style "titles"

// Mouse mode
mouse_mode true
focus_follows_mouse false
mouse_hover_effects true
mouse_hover_tips true

// Scroll buffer
scroll_buffer_size 100000
styled_underlines true
show_startup_tips true
show_release_notes false
copy_command "pbcopy"
ZELLIJ_CONF
configured "zellij configured (Dracula Sakura theme, status bar with mode keybindings, pane frames, mouse)"

# Retire both generated layouts. Zellij's stock layouts cover these workflows,
# and ownership-safe removal preserves any file with user content outside our block.
ZELLIJ_LAYOUTS="$ZELLIJ_CONFIG_DIR/layouts"
remove_superseded_managed "$ZELLIJ_LAYOUTS/dev.kdl" \
    "the generated Zellij layouts were retired" "(#561)" "//"
remove_superseded_managed "$ZELLIJ_LAYOUTS/home.kdl" \
    "the generated Zellij layouts were retired" "(#561)" "//"
fi  # installed zellij

# ---- Yazi config ------------------------------------------------------------
YAZI_CONFIG_DIR="$HOME/.config/yazi"
YAZI_CONFIG="$YAZI_CONFIG_DIR/yazi.toml"
YAZI_THEME="$YAZI_CONFIG_DIR/theme.toml"
info "Configuring Yazi..."
write_managed "$YAZI_CONFIG" "#" <<'YAZI_CONF'
#:schema https://yazi-rs.github.io/schemas/yazi.json

[mgr]
ratio = [ 1, 4, 3 ]
sort_by = "natural"
sort_sensitive = false
sort_reverse = false
sort_dir_first = true
linemode = "size"
show_hidden = true
show_symlink = true
scrolloff = 5

[preview]
wrap = "yes"
tab_size = 2
max_width = 1000
max_height = 1000
image_filter = "lanczos3"
image_quality = 75
YAZI_CONF

write_managed "$YAZI_THEME" "#" <<'YAZI_THEME_CONF'
#:schema https://yazi-rs.github.io/schemas/theme.json

# Dracula-Sakura palette:
# background #282a36, foreground #f8f8f2, rose #ff7aa8,
# mint #8af7cf, yellow #fff0a8, lilac #d4b2ff, cyan #9be7ff.

[app]
overall = { bg = "#282a36" }

[mgr]
cwd = { fg = "#9be7ff", bold = true }
find_keyword = { fg = "#fff0a8", bold = true, italic = true, underline = true }
find_position = { fg = "#ff9fe3", bg = "#282a36", bold = true, italic = true }
symlink_target = { fg = "#8a88c7", italic = true }
marker_copied = { fg = "#8af7cf", bg = "#8af7cf" }
marker_cut = { fg = "#ff7aa8", bg = "#ff7aa8" }
marker_marked = { fg = "#9be7ff", bg = "#9be7ff" }
marker_selected = { fg = "#d4b2ff", bg = "#d4b2ff" }
count_copied = { fg = "#282a36", bg = "#8af7cf" }
count_cut = { fg = "#282a36", bg = "#ff7aa8" }
count_selected = { fg = "#282a36", bg = "#d4b2ff" }
border_style = { fg = "#6a5d86" }

[tabs]
active = { fg = "#282a36", bg = "#d4b2ff", bold = true }
inactive = { fg = "#8a88c7", bg = "#2f3144" }

[mode]
normal_main = { fg = "#282a36", bg = "#9be7ff", bold = true }
normal_alt = { fg = "#9be7ff", bg = "#2f3144" }
select_main = { fg = "#282a36", bg = "#ff7aa8", bold = true }
select_alt = { fg = "#ff7aa8", bg = "#2f3144" }
unset_main = { fg = "#282a36", bg = "#fff0a8", bold = true }
unset_alt = { fg = "#fff0a8", bg = "#2f3144" }

[indicator]
parent = { fg = "#8a88c7" }
current = { fg = "#d4b2ff", reversed = true }
preview = { fg = "#9be7ff", underline = true }

[status]
overall = { fg = "#f8f8f2", bg = "#282a36" }
perm_sep = { fg = "#6a5d86" }
perm_type = { fg = "#8af7cf" }
perm_read = { fg = "#fff0a8" }
perm_write = { fg = "#ff7aa8" }
perm_exec = { fg = "#9be7ff" }
progress_label = { fg = "#f8f8f2", bold = true }
progress_normal = { fg = "#8af7cf", bg = "#2f3144" }
progress_error = { fg = "#282a36", bg = "#ff7aa8" }

[which]
border = { fg = "#d4b2ff" }
cand = { fg = "#9be7ff" }
rest = { fg = "#8a88c7" }
desc = { fg = "#ff9fe3" }
separator_style = { fg = "#6a5d86" }

[confirm]
border = { fg = "#d4b2ff" }
title = { fg = "#d4b2ff", bold = true }
btn_yes = { fg = "#282a36", bg = "#8af7cf", bold = true }
btn_no = { fg = "#f8f8f2", bg = "#2f3144" }

[spot]
border = { fg = "#d4b2ff" }
title = { fg = "#d4b2ff", bold = true }
tbl_col = { fg = "#9be7ff" }
tbl_cell = { fg = "#fff0a8", reversed = true }

[notify]
title_info = { fg = "#8af7cf" }
title_warn = { fg = "#fff0a8" }
title_error = { fg = "#ff7aa8" }

[pick]
border = { fg = "#d4b2ff" }
active = { fg = "#ff9fe3", bold = true }
inactive = { fg = "#f8f8f2" }

[input]
border = { fg = "#d4b2ff" }
title = { fg = "#9be7ff" }
value = { fg = "#f8f8f2" }
selected = { fg = "#282a36", bg = "#d4b2ff" }

[cmp]
border = { fg = "#d4b2ff" }
active = { fg = "#282a36", bg = "#9be7ff" }
inactive = { fg = "#f8f8f2" }

[tasks]
border = { fg = "#d4b2ff" }
title = { fg = "#9be7ff" }
hovered = { fg = "#ff9fe3", bold = true }

[help]
border = { fg = "#d4b2ff" }
chord = { fg = "#9be7ff" }
action = { fg = "#f8f8f2" }
hovered = { fg = "#282a36", bg = "#d4b2ff", bold = true }

[filetype]
rules = [
    { mime = "**/image/*", fg = "#fff0a8" },
    { mime = "**/{audio,video}/*", fg = "#ff9fe3" },
    { mime = "**/application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "#ff7aa8" },
    { mime = "**/application/{pdf,doc,rtf}", fg = "#9be7ff" },
    { url = "*", is = "orphan", fg = "#ff7aa8" },
    { url = "*", is = "exec", fg = "#8af7cf" },
    { url = "*/", fg = "#d4b2ff" },
    { url = "*", fg = "#f8f8f2" },
]
YAZI_THEME_CONF
configured "Yazi configured (previews, natural sorting, hidden files, Dracula-Sakura theme)"

# ---- retired newsboat config ----
remove_superseded_managed "$HOME/.newsboat/config" \
    "newsboat was removed from the setup" "(#542)"
remove_superseded_managed "$HOME/.newsboat/urls" \
    "newsboat was removed from the setup" "(#542)"
# ---- mpv config ----
MPV_CONFIG_DIR="$HOME/.config/mpv"
MPV_CONFIG="$MPV_CONFIG_DIR/mpv.conf"
    info "Creating mpv config (hardware accel, sensible defaults)..."
    write_managed "$MPV_CONFIG" "#" <<'MPV_CONF'
# mpv configuration — hardware accel, quality defaults

# Hardware decoding (VideoToolbox on macOS)
hwdec=auto-safe

# Video output
vo=gpu-next
gpu-api=auto

# Audio
volume=70
volume-max=150

# Subtitles
sub-auto=fuzzy
sub-font-size=36

# OSD
osd-font-size=24
osd-duration=2000

# Keep window open at end of file
keep-open=yes

# Save position on quit
save-position-on-quit=yes

# Screenshot
screenshot-directory=~/Screenshots
screenshot-format=png
MPV_CONF
    configured "mpv configured (hardware accel, save position, screenshots)"

# cliamp self-configures on first run (point it at ~/Media/music from its UI /
# `cliamp ~/Media/music`); no hand-written config here.

# ---- Chawan terminal browser ----
# The generated zshrc sets XDG_CONFIG_HOME to ~/.config, which Chawan checks
# before ~/.chawan. Keep privacy-sensitive browser features opt-in.
write_managed "$HOME/.config/chawan/config.toml" "#" <<'CHAWAN_CONF'
[buffer]
styling = true
images = true
scripting = false
referer-from = false
cookie = false
meta-refresh = "ask"
history = true
mark-links = false

[search]
wrap = true
ignore-case = "auto"

[network]
max-redirect = 10
max-net-connections = 12
prepend-scheme = "https://"
allow-http-from-file = false

[input]
vi-numeric-prefix = true
use-mouse = "auto"
osc52-copy = "auto"
osc52-primary = "auto"
bracketed-paste = "auto"
wheel-scroll = 5

[status]
show-cursor-position = true
show-hover-link = true
format-mode = ["reverse"]

[display]
color-mode = "true-color"
image-mode = "kitty"
alt-screen = "auto"
highlight-color = "#ff9fe3"
highlight-marks = true
minimum-contrast = 100
set-title = true
default-background-color = "#282a36"
default-foreground-color = "#f8f8f2"
CHAWAN_CONF
configured "Chawan configured (private defaults, Kitty images, Dracula-Sakura display)"

# ---- Posting terminal HTTP client ----
# Posting keeps its user themes under XDG_DATA_HOME, not beside config.yaml.
# Refresh the theme asset, but seed the user-editable application config once.
POSTING_CONFIG="$HOME/.config/posting/config.yaml"
POSTING_THEME="$HOME/.local/share/posting/themes/dracula-sakura.yaml"
write_generated "$POSTING_THEME" <<'POSTING_THEME_CONF'
name: dracula-sakura
author: vixygrey-dev-setup
description: Dark plum surfaces with sakura pink, lilac, cyan, and mint accents.
primary: "#ff9fe3"
secondary: "#d4b2ff"
background: "#282a36"
surface: "#2f3144"
panel: "#3a3b52"
warning: "#ffcf93"
error: "#ff7aa8"
success: "#8af7cf"
accent: "#9be7ff"
dark: true

text_area:
  gutter: "#8a88c7 on #2f3144"
  cursor: "#282a36 on #ff9fe3"
  cursor_line: "#f8f8f2 on #2f3144"
  cursor_line_gutter: "#d4b2ff on #2f3144"
  matched_bracket: "bold #fff0a8"
  selection: "#f8f8f2 on #4b4963"

syntax:
  json_key: "#9be7ff"
  json_string: "#fff0a8"
  json_number: "#d4b2ff"
  json_boolean: "#8af7cf"
  json_null: "#ff7aa8"

url:
  base: "#f8f8f2"
  protocol: "#9be7ff"
  separator: "#8a88c7"

variable:
  resolved: "#8af7cf"
  unresolved: "#ff7aa8"

method:
  get: "#9be7ff"
  post: "#8af7cf"
  put: "#ffcf93"
  delete: "#ff7aa8"
  patch: "#ff9fe3"
  options: "#d4b2ff"
  head: "#ffc2ec"
POSTING_THEME_CONF
configured "Posting Dracula-Sakura theme written ($POSTING_THEME)"

if write_seed_once "$POSTING_CONFIG" \
    "edit Posting defaults in this user-owned YAML file" \
    <<'POSTING_CONFIG_CONF'
theme: dracula-sakura
layout: vertical
spacing: compact
animation: none
use_host_environment: false
watch_env_files: true
watch_collection_files: true
watch_themes: true

heading:
  visible: true
  show_host: true
  show_version: true

url_bar:
  show_value_preview: true
  hide_secrets_in_value_preview: true

response:
  prettify_json: true
  show_size_and_time: true

collection_browser:
  position: left
  show_on_startup: true

command_palette:
  theme_preview: true

focus:
  on_startup: url

editor: micro
POSTING_CONFIG_CONF
then
    configured "Posting configured (Dracula-Sakura, compact layout, protected host environment)"
fi

# Remove the old browser config only when its managed markers prove ownership.
remove_superseded_managed "$HOME/.w3m/config" \
    "w3m was replaced by Chawan" "(#572)"


# Nushell was removed from the setup. Clear only files whose managed blocks prove
# ownership, including the superseded pre-XDG location (#333, #555).
remove_superseded_managed "$HOME/.config/nushell/env.nu" \
    "nushell was removed from the setup" "(#555)"
remove_superseded_managed "$HOME/.config/nushell/config.nu" \
    "nushell was removed from the setup" "(#555)"
remove_superseded_managed "$HOME/Library/Application Support/nushell/env.nu" \
    "nushell was removed from the setup" "(#555)"
remove_superseded_managed "$HOME/Library/Application Support/nushell/config.nu" \
    "nushell was removed from the setup" "(#555)"

# ---- lnav Dracula-Sakura theme ----
# lnav REWRITES ~/.config/lnav/config.json itself: one `:config` command makes it
# dump `tuning`, `theme-defs` and `log.demux` into that file. So it gets the same
# treatment as omp's config.yml — never a managed block in the file the tool owns.
#
# lnav also reads every JSON file under <config-dir>/configs/, and those fragments
# merge into the same tree. That is the clean seam: the theme lives in a file this
# script owns outright, and the one setting that must reach lnav's own config is
# applied with `:config`, which is lnav's own writer.
#
# A partial theme-def is legal — verified by selecting one that defined only `vars`
# and `styles.text`, and reading `/ui/theme` back. The control matters as much: the
# same command with a name lnav does not know fails with "invalid value for
# property /ui/theme", so acceptance means something (#518).
if installed lnav; then
LNAV_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lnav"
LNAV_THEME_DIR="$LNAV_CONFIG_DIR/configs/dev-setup"
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write lnav Dracula-Sakura theme -> $LNAV_THEME_DIR/dracula-sakura.json"
    info "[DRY RUN] Would select it with: lnav -n -c ':config /ui/theme dracula-sakura'"
else
    ensure_dir "$LNAV_THEME_DIR"
    write_generated "$LNAV_THEME_DIR/dracula-sakura.json" <<'LNAV_THEME_CONF'
{
  "$schema": "https://lnav.org/schemas/config-v1.schema.json",
  "ui": {
    "theme-defs": {
      "dracula-sakura": {
        "vars": {
          "black": "#282a36",
          "red": "#ff7aa8",
          "green": "#8af7cf",
          "yellow": "#fff0a8",
          "blue": "#9be7ff",
          "magenta": "#ff9fe3",
          "cyan": "#9be7ff",
          "white": "#f8f8f2",
          "semantic_highlight_color": "semantic()"
        },
        "styles": {
          "text": { "color": "#f8f8f2", "background-color": "#282a36" },
          "alt-text": { "color": "#ddd2f7", "background-color": "#2f3144" },
          "identifier": { "color": "semantic()" },
          "error": { "color": "#ff7aa8", "bold": true },
          "warning": { "color": "#ffcf93", "bold": true },
          "ok": { "color": "#8af7cf", "bold": true },
          "info": { "color": "#9be7ff" },
          "hidden": { "color": "#8a88c7", "bold": true },
          "cursor-line": { "color": "#282a36", "background-color": "#ff9fe3", "bold": true },
          "disabled-cursor-line": { "color": "#282a36", "background-color": "#d4b2ff" },
          "adjusted-time": { "color": "#ffc2ec" },
          "skewed-time": { "color": "#ffcf93" },
          "offset-time": { "color": "#9be7ff" },
          "time-ago": { "color": "#8a88c7" },
          "time-column": { "color": "#a297cb" },
          "file-offset": { "color": "#8a88c7" },
          "invalid-msg": { "color": "#ff7aa8" },
          "focused": { "color": "#282a36", "background-color": "#ffc2ec" },
          "disabled-focused": { "color": "#f8f8f2", "background-color": "#4b4963" },
          "popup": { "color": "#f8f8f2", "background-color": "#323448" },
          "popup-border": { "color": "#d4b2ff", "background-color": "#323448" },
          "scrollbar": { "color": "#d4b2ff", "background-color": "#4b4963" },
          "h1": { "color": "#ff9fe3", "bold": true },
          "h2": { "color": "#ffc2ec", "bold": true },
          "h3": { "color": "#d4b2ff", "bold": true },
          "h4": { "color": "#9be7ff" },
          "h5": { "color": "#8af7cf" },
          "h6": { "color": "#ffcf93" },
          "hr": { "color": "#4b4963" },
          "hyperlink": { "color": "#9be7ff", "underline": true },
          "list-glyph": { "color": "#ff9fe3" },
          "breadcrumb": { "color": "#a297cb" },
          "table-border": { "color": "#4b4963" },
          "table-header": { "color": "#ff9fe3", "bold": true },
          "quote-border": { "color": "#4b4963", "background-color": "#2f3144" },
          "quoted-text": { "color": "#ddd2f7", "background-color": "#2f3144" },
          "footnote-border": { "color": "#4b4963", "background-color": "#2f3144" },
          "footnote-text": { "color": "#8a88c7", "background-color": "#2f3144" },
          "snippet-border": { "color": "#9be7ff" },
          "indent-guide": { "color": "#4b4963" },
          "fuzzy-match": { "color": "#fff0a8", "bold": true },
          "selected-text": { "color": "#282a36", "background-color": "#ffc2ec" },
          "timeline-bar": { "background-color": "#8a88c7" }
        },
        "syntax-styles": {
          "comment": { "color": "#8a88c7" },
          "doc-directive": { "color": "#8af7cf" },
          "keyword": { "color": "#ff9fe3", "bold": true },
          "string": { "color": "#fff0a8" },
          "number": { "color": "#d4b2ff" },
          "variable": { "color": "#ffcf93" },
          "symbol": { "color": "#d4b2ff" },
          "type": { "color": "#9be7ff" },
          "function": { "color": "#8af7cf" },
          "file": { "color": "#8af7cf" },
          "object-key": { "color": "#ffc2ec" },
          "null": { "color": "#8a88c7", "bold": true },
          "ascii-control": { "color": "#8af7cf" },
          "non-ascii": { "color": "#8af7cf" },
          "separators-references-accessors": { "color": "#ff9fe3" },
          "re-special": { "color": "#8af7cf" },
          "re-repeat": { "color": "#d4b2ff" },
          "diff-delete": { "color": "#ff7aa8" },
          "diff-add": { "color": "#8af7cf" },
          "diff-section": { "color": "#d4b2ff", "bold": true },
          "inline-code": { "color": "#8af7cf", "background-color": "#2f3144" },
          "quoted-code": { "color": "#f8f8f2", "background-color": "#2f3144" },
          "code-border": { "color": "#4b4963", "background-color": "#2f3144" },
          "spectrogram-low": { "background-color": "#8af7cf" },
          "spectrogram-medium": { "background-color": "#ffcf93" },
          "spectrogram-high": { "background-color": "#ff7aa8" }
        },
        "status-styles": {
          "text": { "color": "#f8f8f2", "background-color": "#323448" },
          "title": { "color": "#282a36", "background-color": "#ff9fe3", "bold": true },
          "subtitle": { "color": "#282a36", "background-color": "#9be7ff", "bold": true },
          "info": { "color": "#282a36", "background-color": "#d4b2ff" },
          "warn": { "color": "#282a36", "background-color": "#ffcf93" },
          "alert": { "color": "#282a36", "background-color": "#ff7aa8" },
          "active": { "color": "#282a36", "background-color": "#8af7cf" },
          "inactive": { "color": "#a297cb", "background-color": "#2f3144" },
          "inactive-alert": { "color": "#ff7aa8", "background-color": "#2f3144" },
          "inactive-warn": { "color": "#ffcf93", "background-color": "#2f3144" },
          "hotkey": { "color": "#fff0a8", "bold": true, "underline": true },
          "title-hotkey": { "color": "#282a36", "background-color": "#ffc2ec", "underline": true },
          "disabled-title": { "color": "#ddd2f7", "background-color": "#4b4963", "bold": true },
          "suggestion": { "color": "#8a88c7" },
          "alert-title": { "color": "#282a36", "background-color": "#ff7aa8", "bold": true }
        },
        "log-level-styles": {
          "warning": { "color": "#ffcf93" },
          "error": { "color": "#ff7aa8" },
          "critical": { "color": "#ff7aa8", "bold": true },
          "fatal": { "color": "#ff7aa8", "bold": true }
        }
      }
    }
  }
}
LNAV_THEME_CONF
    configured "lnav Dracula-Sakura theme written ($LNAV_THEME_DIR/dracula-sakura.json)"

    # Select it through lnav's own writer. `:config` validates the name against the
    # themes it loaded, so a failure here means the fragment above did not parse —
    # which is exactly what we want to hear about.
    #
    # lnav needs a real file to open, and REFUSES /dev/null with "unable to open
    # file ... Invalid argument". A one-line temp file is the smallest thing it
    # will accept; passing /dev/null makes this step fail every run while the
    # theme itself is perfectly good.
    _lnav_probe="$(mktemp)"
    printf 'dev-setup theme selection\n' > "$_lnav_probe"
    if lnav -n -c ':config /ui/theme dracula-sakura' "$_lnav_probe" >> "$LOG_FILE" 2>&1; then
        configured "lnav theme selected (dracula-sakura)"
    else
        warn "lnav did not accept the dracula-sakura theme — see $LOG_FILE"
    fi
    rm -f "$_lnav_probe"
    unset _lnav_probe
fi
fi

# ---- stu (S3 TUI) Dracula-Sakura theme ----
# stu reads $STU_ROOT_DIR/config.toml and defaults that to ~/.stu — it does NOT
# follow XDG, so this is one of the deliberate Library/dot-dir exceptions rather
# than an oversight (#519). Colours deserialize through Ratatouille's Color serde,
# which the docs record as accepting named, indexed, and hex values; hex is what
# the house palette needs.
#
# `object_dir_bold` is a BOOL, not a colour. It sits in the same table and would
# be a type error if treated as one.
STU_ROOT_DIR_PATH="${STU_ROOT_DIR:-$HOME/.stu}"
if installed stu; then
    ensure_dir "$STU_ROOT_DIR_PATH"
    write_managed "$STU_ROOT_DIR_PATH/config.toml" "#" <<'STU_CONF'
[ui.theme]
bg = "#282a36"
fg = "#f8f8f2"
divider = "#4b4963"
link = "#9be7ff"
list_selected_bg = "#ff9fe3"
list_selected_fg = "#282a36"
list_selected_inactive_bg = "#4b4963"
list_selected_inactive_fg = "#ddd2f7"
list_filter_match = "#fff0a8"
detail_selected = "#ffc2ec"
dialog_selected = "#ff9fe3"
preview_line_number = "#8a88c7"
help_key_fg = "#8af7cf"
status_help = "#a297cb"
status_info = "#9be7ff"
status_success = "#8af7cf"
status_warn = "#ffcf93"
status_error = "#ff7aa8"
object_dir_bold = true
STU_CONF
    configured "stu Dracula-Sakura theme written ($STU_ROOT_DIR_PATH/config.toml)"
fi

# ---- e1s (ECS TUI) Dracula-Sakura colours ----
# e1s takes either a built-in theme name (`--theme dracula`, from the
# alacritty-theme set) or explicit colour overrides in its config. The overrides
# are used here: the built-in dracula is Dracula, and the house palette is the
# sakura variant of it (#519).
if installed e1s; then
    ensure_dir "$HOME/.config/e1s"
    write_managed "$HOME/.config/e1s/config.yml" "#" <<'E1S_CONF'
colors:
  BgColor: "#282a36"
  FgColor: "#f8f8f2"
  BorderColor: "#d4b2ff"
  Black: "#282a36"
  Red: "#ff7aa8"
  Green: "#8af7cf"
  Yellow: "#ffcf93"
  Blue: "#9be7ff"
  Magenta: "#ff9fe3"
  Cyan: "#9be7ff"
  Gray: "#8a88c7"
E1S_CONF
    configured "e1s Dracula-Sakura colours written (~/.config/e1s/config.yml)"
fi

# ---- Claws (all-AWS TUI) Dracula-Sakura theme and safe defaults ----
# Claws supports a Dracula preset plus three documented colour overrides. Its
# read-only default remains a shell alias, because read-only is a flag rather
# than a config key. `command claws` bypasses that alias for intentional writes.
if installed claws; then
    write_managed "$HOME/.config/claws/config.yaml" "#" <<'CLAWS_CONF'
theme:
  preset: dracula
  primary: "#ff9fe3"
  danger: "#ff7aa8"
  success: "#8af7cf"

autosave:
  enabled: false

compact_header: false

startup:
  view: dashboard

navigation:
  max_stack_size: 100

ai:
  save_sessions: false
CLAWS_CONF
    configured "Claws configured (Dracula-Sakura palette, dashboard, read-only alias)"
fi

# Retired tool configs are removed only when their managed blocks prove ownership.
remove_superseded_managed "$HOME/Library/Application Support/lazyenv/config.toml" \
    "lazyenv was removed from the setup" "(#555)"
remove_superseded_managed "$HOME/.config/git-cliff/cliff.toml" \
    "git-cliff was removed from the setup" "(#555)"

# ---- SSH config ----
SSH_CONFIG="$HOME/.ssh/config"
    info "Creating SSH configuration..."
    chmod 700 "$HOME/.ssh"
    write_managed "$SSH_CONFIG" "#" <<'SSH_CONF'
# =============================================================================
# SSH Configuration
# =============================================================================

# -- Global Defaults ----------------------------------------------------------
Host *
    # Reuse connections (multiplexing) — dramatically faster repeated SSH
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600

    # Keep connections alive (prevents timeouts)
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # Use macOS Keychain for SSH keys
    AddKeysToAgent yes
    UseKeychain yes
    IdentityFile ~/.ssh/id_ed25519

    # Faster connections
    Compression yes

    # Security: only use strong algorithms
    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    PubkeyAcceptedAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# -- GitHub -------------------------------------------------------------------
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

# -- Example: shortcut for a server ------------------------------------------
# Host myserver
#     HostName 192.168.1.100
#     User deploy
#     Port 22
#     IdentityFile ~/.ssh/id_ed25519
SSH_CONF
    # Create the multiplexing sockets dir, then lock down perms (dirs must exist first)
    ensure_dir "$HOME/.ssh/sockets"
    if [[ "$DRY_RUN" != "true" ]]; then
        chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
        chmod 600 "$SSH_CONFIG"
    fi
    configured "SSH configured (multiplexing, keychain, keep-alive, strong algorithms)"

# Generate SSH key if none exists
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    info "No SSH key found. To generate one, run:"
    echo "  ssh-keygen -t ed25519 -C \"your_email@example.com\""
else
    warn "SSH key already exists at ~/.ssh/id_ed25519"
fi

# ---- Global .gitignore ----
GLOBAL_GITIGNORE="$HOME/.gitignore_global"
    info "Creating global .gitignore..."
    write_managed "$GLOBAL_GITIGNORE" "#" <<'GITIGNORE_GLOBAL'
# =============================================================================
# Global .gitignore — applied to ALL repositories
# =============================================================================

# -- macOS --------------------------------------------------------------------
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
.AppleDouble
.LSOverride
Icon?

# -- Editors ------------------------------------------------------------------
# Editor workspace metadata can be regenerated by each editor.
.vscode/settings.json
.vscode/launch.json
*.code-workspace

# JetBrains
.idea/
*.iml

# Vim
*.swp
*.swo
*~
.netrwhist

# Sublime Text
*.sublime-project
*.sublime-workspace

# -- Environment & Secrets ----------------------------------------------------
.env
.env.local
.env.*.local
.env.development.local
.env.test.local
.env.production.local
*.pem
*.key
*.p12
*.pfx
credentials.json
secrets.yaml
secrets.yml

# -- Node ---------------------------------------------------------------------
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*

# -- Python -------------------------------------------------------------------
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
.Python

# -- Build artifacts ----------------------------------------------------------
dist/
build/
*.o
*.so
*.dylib
coverage/
.nyc_output/

# -- Thumbnails & system files ------------------------------------------------
Thumbs.db
ehthumbs.db
Desktop.ini

GITIGNORE_GLOBAL
    git_global core.excludesfile "$GLOBAL_GITIGNORE"
    configured "Global .gitignore created and registered with git"

# ---- .npmrc ----
NPMRC="$HOME/.npmrc"
    info "Creating .npmrc..."
    write_managed "$NPMRC" "#" <<'NPMRC_CONF'
# Save exact versions (no ^ or ~ prefix)
save-exact=true

# Default init values
init-author-name=
init-license=MIT
init-version=0.1.0

# Disable npm telemetry / update notifications
update-notifier=false
fund=false
audit-level=moderate

# Prefer offline if cached
prefer-offline=true

# Engine strict (fail if node version doesn't match)
engine-strict=true
NPMRC_CONF
    configured ".npmrc configured (save-exact, no telemetry, prefer-offline)"

# ---- .editorconfig ----
EDITORCONFIG="$HOME/.editorconfig"
    info "Creating global .editorconfig..."
    write_managed "$EDITORCONFIG" "#" <<'EDITORCONFIG_CONF'
# EditorConfig — cross-editor consistency
# https://editorconfig.org
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false

[*.py]
indent_size = 4

[*.go]
indent_style = tab
indent_size = 4

[*.rs]
indent_size = 4

[Makefile]
indent_style = tab

[*.{yml,yaml}]
indent_size = 2

[*.{sh,bash,zsh}]
indent_size = 4
EDITORCONFIG_CONF
    configured ".editorconfig created (utf-8, lf, 2-space indent, trim whitespace)"

# ---- .prettierrc ----
PRETTIERRC="$HOME/.prettierrc"
    info "Creating global .prettierrc..."
    write_managed "$PRETTIERRC" "#" <<'PRETTIER_CONF'
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf"
}
PRETTIER_CONF
    configured ".prettierrc created (single quotes, trailing commas, 100 width)"

# ---- .curlrc ----
CURLRC="$HOME/.curlrc"
    info "Creating .curlrc..."
    write_managed "$CURLRC" "#" <<'CURLRC_CONF'
# Follow redirects automatically
--location

# Show error messages on failure
--show-error

# Fail silently on HTTP errors (return non-zero exit code)
--fail

# Set a reasonable timeout (30 seconds)
--max-time 30

# Connection timeout (10 seconds)
--connect-timeout 10

# Retry on transient errors
--retry 3
--retry-delay 2

# Compressed responses
--compressed

# User agent
--user-agent "curl/dev"
CURLRC_CONF
    configured ".curlrc configured (follow redirects, retry, compression, timeouts)"

# ---- eilmeldung ----
# The reader supports a full RGB palette. Keep behavior close to upstream defaults,
# while using the macOS URL opener and the shared Dracula-Sakura colors (#557).
EILMELDUNG_CONFIG="$HOME/.config/eilmeldung/config.toml"
info "Creating eilmeldung config..."
write_managed "$EILMELDUNG_CONFIG" "#" <<'EILMELDUNG_CONF'
mouse_support = true
enclosure_command = "open {url}"
auto_reload_config = true

[border_theme]
focused = "rounded"
unfocused = "rounded"
framing = "connected"

[icon_set]
preset = "nerd"

[theme.color_palette]
background = "#282a36"
foreground = "#f8f8f2"
muted = "#6272a4"
highlight = "#ffb7c5"
flagged = "#ff5555"
accent_primary = "#ff79c6"
accent_secondary = "#bd93f9"
accent_tertiary = "#8be9fd"
accent_quaternary = "#ffb86c"
info = "#50fa7b"
warning = "#f1fa8c"
error = "#ff5555"
EILMELDUNG_CONF
configured "eilmeldung configured (Dracula-Sakura palette, rounded borders, macOS opener)"

# ---- concord ----
# Concord validates both files with `concord --check-config`. Force Keychain storage
# instead of its plaintext fallback and keep microphone transmission opt-in (#557).
CONCORD_CONFIG_DIR="$HOME/.config/concord"
CONCORD_CONFIG="$CONCORD_CONFIG_DIR/config.toml"
CONCORD_THEME="$CONCORD_CONFIG_DIR/theme.toml"
info "Creating concord config..."
write_managed "$CONCORD_CONFIG" "#" <<'CONCORD_CONF'
[display]
image_protocol = "kitty"
show_avatars = true
show_images = true
media_playback = true
image_preview_quality = "balanced"
attachment_viewer_quality = "original"
animate_previews = "selected"
show_custom_emoji = true
hour_format_24 = true

[credentials]
store = "keychain"

[notifications]
desktop_notifications = true

[presence]
share_rich_presence = false

[voice]
allow_microphone_transmit = false
push_to_talk = true
noise_suppression = true
CONCORD_CONF
configured "concord configured (Keychain credentials, Kitty images, opt-in microphone)"

info "Creating concord Dracula-Sakura theme..."
write_managed "$CONCORD_THEME" "#" <<'CONCORD_THEME_CONF'
[highlight.Normal]
foreground = "#f8f8f2"
background = "#282a36"

[highlight.Muted]
foreground = "#6272a4"
dim = true

[highlight.Border]
foreground = "#6272a4"

[highlight.FocusBorder]
foreground = "#ff79c6"

[highlight.Selection]
foreground = "#282a36"
background = "#ffb7c5"
bold = true

[highlight.SelectionBorder]
foreground = "#bd93f9"
bold = true

[highlight.ActiveField]
foreground = "#8be9fd"
bold = true

[highlight.MessageLink]
foreground = "#8be9fd"
underline = true

[highlight.InlineCode]
foreground = "#ffb86c"

[highlight.PresenceOnline]
foreground = "#50fa7b"

[highlight.PresenceIdle]
foreground = "#f1fa8c"

[highlight.PresenceDnd]
foreground = "#ff5555"

[highlight.Error]
foreground = "#ff5555"

[highlight.Warning]
foreground = "#f1fa8c"

[highlight.Success]
foreground = "#50fa7b"

[highlight.Info]
foreground = "#8be9fd"

[ui.border]
default = "rounded"

[ui.indicator]
selection = "❯ "
CONCORD_THEME_CONF
configured "concord Dracula-Sakura theme configured"

# ---- spotatui ----
# The Settings screen rewrites behavior and theme data. Seed once so later in-app
# changes survive, and disable its optional presence and counter network calls (#557).
SPOTATUI_CONFIG="$HOME/.config/spotatui/config.yml"
if write_seed_once "$SPOTATUI_CONFIG" "edit in spotatui with Alt-," <<'SPOTATUI_CONF'
behavior:
  startup_route: home
  sidebar_position: left
  playbar_position: bottom
  banner_gradient: false
  set_window_title: true
  enable_discord_rpc: false
  enable_global_song_count: false

theme:
  preset: "Dracula"
  active: "80, 250, 123"
  banner: "255, 183, 197"
  error_border: "255, 85, 85"
  error_text: "255, 85, 85"
  hint: "241, 250, 140"
  hovered: "189, 147, 249"
  inactive: "98, 114, 164"
  playbar_background: "40, 42, 54"
  playbar_progress: "80, 250, 123"
  playbar_progress_text: "248, 248, 242"
  playbar_text: "248, 248, 242"
  selected: "139, 233, 253"
  text: "248, 248, 242"
  background: "40, 42, 54"
  header: "255, 121, 198"
  highlighted_lyrics: "255, 183, 197"
SPOTATUI_CONF
then
    configured "spotatui starter config seeded (Dracula-Sakura palette, private network defaults)"
fi

# ---- cfait ----
# cfait writes its own config after UI changes. Seed only a local-first profile,
# its built-in Dracula theme, and privacy-preserving display defaults (#557).
CFAIT_CONFIG="$HOME/.config/cfait/config.toml"
if write_seed_once "$CFAIT_CONFIG" "edit in cfait or open this self-documented TOML file" <<'CFAIT_CONF'
default_calendar = "local://default"
enable_local_mode = true
hide_completed = true
strikethrough_completed = true
show_inline_descriptions = true
theme = "Dracula"
auto_reminders = true
default_reminder_time = "09:00"
auto_refresh_interval_mins = 30
trash_retention_days = 14
blur_when_unfocused = true
description_editor = "micro"
first_day_of_week = "monday"
log_level = "Error"
CFAIT_CONF
then
    configured "cfait starter config seeded (local-first, Dracula, privacy blur)"
fi

# ---- Docker daemon config ----
DOCKER_CONFIG_DIR="$HOME/.docker"
DOCKER_DAEMON="$DOCKER_CONFIG_DIR/daemon.json"
# Docker daemon.json is strict JSON (no comment markers), so we jq deep-merge our
# keys into any existing file — adding/updating ours while preserving the user's.
info "Configuring Docker daemon.json..."
# The merge below honours DRY_RUN; this mkdir did not, so a dry run created ~/.docker
# on a machine that had never run Docker (#380).
[[ "$DRY_RUN" == "true" ]] || mkdir -p "$DOCKER_CONFIG_DIR"
DOCKER_TMP="$(mktemp)"
cat > "$DOCKER_TMP" <<'DOCKER_CONF'
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  },
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["1.1.1.1", "8.8.8.8"]
}
DOCKER_CONF
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would merge Docker daemon.json (BuildKit, log rotation, GC)"
    rm -f "$DOCKER_TMP"
elif [[ -f "$DOCKER_DAEMON" ]] && command -v jq &>/dev/null; then
    DOCKER_MERGED="$(mktemp)"
    if jq -s '.[0] * .[1]' "$DOCKER_DAEMON" "$DOCKER_TMP" > "$DOCKER_MERGED" 2>/dev/null; then
        mv "$DOCKER_MERGED" "$DOCKER_DAEMON"
        success "Docker daemon.json updated (merged; your other keys preserved)"
    else
        rm -f "$DOCKER_MERGED"; warn "Could not merge Docker daemon.json — left as-is"
    fi
    rm -f "$DOCKER_TMP"
else
    mv "$DOCKER_TMP" "$DOCKER_DAEMON"
    success "Docker configured (BuildKit, log rotation 10m x 3, garbage collection)"
fi

# ---- Docker buildx as default builder ----
if installed docker; then
    if docker buildx version &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would: docker buildx install (set buildx as the default builder)"
        else
            info "Setting Docker buildx as default builder..."
            # Writes an alias into ~/.docker/config.json — a real change, so it needs the
            # guard above (#380).
            docker buildx install 2>/dev/null || true
            success "Docker buildx set as default builder (multi-platform builds enabled)"
        fi
    fi
fi

fi  # configs (end of first configs segment)

# ---- macOS System Defaults ----
# Top-level category (NOT nested in configs) so --only macos-defaults works.
if should_run "macos-defaults"; then
info "Configuring macOS system defaults..."

if [[ "$DRY_RUN" != "true" ]]; then

# -- Menu bar --
# Keep the native macOS menu bar visible now that SketchyBar is retired.
# The change takes effect after logout or restart.
defaults write NSGlobalDomain _HIHideMenuBar -bool false

# -- Dock --
# Small Dock icon size
defaults write com.apple.dock tilesize -integer 36
# Don't show recent applications
defaults write com.apple.dock show-recents -bool false
# Minimize windows using scale effect (faster than genie)
defaults write com.apple.dock mineffect -string "scale"
# Minimize windows into their application icon
defaults write com.apple.dock minimize-to-application -bool true
configured "Dock configured (small icons, scale effect)"

# -- Screenshots --
# Save screenshots as PNG
defaults write com.apple.screencapture type -string "png"
# Save to ~/Screenshots instead of Desktop
SCREENSHOT_DIR="$HOME/Screenshots"
mkdir -p "$SCREENSHOT_DIR"
defaults write com.apple.screencapture location -string "$SCREENSHOT_DIR"
# Disable shadow on screenshots
defaults write com.apple.screencapture disable-shadow -bool true
# Don't show floating thumbnail after capture
defaults write com.apple.screencapture show-thumbnail -bool false
configured "Screenshots configured (PNG, ~/Screenshots, no shadow)"

# -- Global hotkey: restore cmd+space to Spotlight ----------------------------
# Earlier releases disabled Spotlight for Ghostty's global quick terminal.
# Restore Spotlight search (id 64) and Finder search (id 65) for existing
# machines as well as fresh installs. The change takes effect after logout.
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 64 \
    "<dict><key>enabled</key><true/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>"
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 65 \
    "<dict><key>enabled</key><true/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1572864</integer></array></dict></dict>"
configured "Spotlight cmd+space restored (takes effect after logout)"

# -- Keyboard --
# Faster key repeat rate (lower = faster, default is 6)
defaults write NSGlobalDomain KeyRepeat -int 2
# Shorter delay until key repeat (lower = shorter, default is 25)
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Disable press-and-hold for accent characters (essential for vim key repeat)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Enable full keyboard access for all controls (Tab through all UI elements)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
# Disable auto-capitalization
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
# Disable smart dashes
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
# Disable smart quotes
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
# Disable period substitution (double space -> period)
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
configured "Keyboard configured (fast repeat, no press-and-hold, no auto-correct)"

# -- Trackpad --
# Faster tracking speed (0.0 to 3.0, default ~1.0)
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.0
configured "Trackpad configured (faster tracking)"

# -- Mission Control --
# Keep Spaces in a fixed order — don't auto-rearrange by most-recent-use, so swiping
# between Spaces is predictable. The cosmetic Mission Control tweaks (animation speed,
# group-by-app) were dropped as unused.
defaults write com.apple.dock mru-spaces -bool false
configured "Mission Control: auto-rearrange Spaces disabled (fixed Space order)"

# Hot Corners: left at macOS defaults (all off). The default is already no-action and
# they aren't used here, so there's nothing to disable.

# -- Safari --
# Safari is sandboxed on modern macOS — writes may fail without Full Disk Access
safari_ok=true
defaults write com.apple.Safari IncludeDevelopMenu -bool true 2>/dev/null || safari_ok=false
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true 2>/dev/null || safari_ok=false
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true 2>/dev/null || safari_ok=false
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true 2>/dev/null || safari_ok=false

if [[ "$safari_ok" == "true" ]]; then
    configured "Safari configured (developer menu, full URL)"
else
    warn "Safari settings skipped — requires Full Disk Access (System Settings > Privacy & Security > Full Disk Access > Terminal)"
fi

# -- TextEdit --
# Default to plain text (not rich text)
defaults write com.apple.TextEdit RichText -int 0
# Open and save files as UTF-8
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
configured "TextEdit configured (plain text, UTF-8)"

# -- Reduce motion / Faster animations --
# Reduce motion for faster UI (universalaccess is protected — suppress the write error
# on machines where it's managed/denied, matching reduceTransparency below).
defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
# Speed up window resize animations
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
configured "Animations configured (reduced motion, fast resize)"

# -- Stage Manager --
# Disable Stage Manager (prevent accidental activation)
defaults write com.apple.WindowManager GloballyEnabled -bool false 2>/dev/null || true
defaults write com.apple.WindowManager AutoHide -bool true 2>/dev/null || true
configured "Stage Manager disabled"

# -- Misc --
# Disable Notification Center and remove from menu bar (restart required)
# Expand save panel by default (already set in Finder section but ensuring global)
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
# Show battery percentage in menu bar
defaults write com.apple.menuextra.battery ShowPercent -string "YES" 2>/dev/null || true
# Set highlight color to Dracula purple
defaults write NSGlobalDomain AppleHighlightColor -string "0.741176 0.576471 0.976471 Purple"
# Dark mode (captured from this machine)
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
# Keep the menu bar hidden in fullscreen
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
configured "Misc macOS defaults configured"

# -- Screensaver & display sleep timing --
# Screensaver kicks in at 45 min, display sleep at 2hr (charger) / 1hr 15min (battery)
defaults -currentHost write com.apple.screensaver idleTime -int 2700 2>/dev/null || true
sudo_run pmset -c displaysleep 120 2>/dev/null || true  # charger: 2 hours
sudo_run pmset -b displaysleep 75 2>/dev/null || true   # battery: 1hr 15min
configured "Screensaver at 45min, display sleep at 2hr (charger) / 1h15m (battery)"

# Restart Dock to apply all Dock/Mission Control changes
killall Dock 2>/dev/null || true

else
    info "[DRY RUN] Would configure macOS system defaults"
fi  # DRY_RUN

fi  # macos-defaults

if should_run "configs"; then  # resume configs (second segment)

# ---- ~/.hushlogin (suppress "Last login" message) ----
if ! is_done "config:hushlogin"; then
if [[ "$DRY_RUN" == "true" ]]; then
    [[ -f "$HOME/.hushlogin" ]] && warn "[DRY RUN] $HOME/.hushlogin — already exists" \
        || info "[DRY RUN] Would create $HOME/.hushlogin"
elif [[ -f "$HOME/.hushlogin" ]]; then
    warn "$HOME/.hushlogin already exists"
else
    touch "$HOME/.hushlogin"
    success "$HOME/.hushlogin created (suppresses 'Last login' in terminal)"
fi
mark_done "config:hushlogin"
fi

# ---- ~/.zprofile (login shell — PATH set once, not on every subshell) ----
ZPROFILE="$HOME/.zprofile"
    info "Creating ~/.zprofile..."
    write_managed "$ZPROFILE" "#" <<'ZPROFILE_CONF'
# =============================================================================
# ~/.zprofile — login shell configuration
# =============================================================================
# This runs ONCE on login (not on every subshell like .zshrc).
# Put PATH modifications and env vars here that only need to be set once.

# Homebrew (Apple Silicon)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Default editor
export EDITOR="micro"
export VISUAL="micro"

# Default pager
export PAGER="bat --style=plain --paging=always"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# Less config (used by git, man, etc. when bat isn't available)
export LESS="-R -F -X -i -J -M -W -x4"
export LESSHISTFILE="$HOME/.local/share/lesshst"

# Language
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# XDG Base Directories (standardize config locations)
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Go (only if installed)
if command -v go &>/dev/null; then
    export GOPATH="$HOME/.local/share/go"
    export PATH="$GOPATH/bin:$PATH"
fi

# Rust (only if installed via rustup)
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi


# .NET global tools — `dotnet tool install -g` puts binaries here (ilspycmd and
# friends). The .NET installer does ship a PATH entry for this, and it does not
# work: /etc/paths.d/dotnet-cli-tools contains the LITERAL string `~/.dotnet/tools`,
# and `path_helper` copies entries verbatim without expanding `~`, so the entry
# points at a directory named `~` and has never resolved. The result is a tool that
# installs "successfully" and stays invisible to every shell, script and git hook —
# which is exactly how a pre-commit guard came to skip silently (#316). Re-asserting
# it with $HOME is the fix; the dead /etc/paths.d entry is Microsoft's and is left
# alone. Guarded, so this is inert on a machine with no .NET. This setup does not
# install the .NET SDK — it only makes tools that are already there reachable.
if [[ -d "$HOME/.dotnet/tools" ]]; then
    export PATH="$HOME/.dotnet/tools:$PATH"
fi

# Increase max open files (Node.js/webpack/vite need many file handles)
ulimit -n 65536 2>/dev/null || true

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# uv tool / pipx — persistent binaries installed by `uv tool install` (e.g.
# harlequin, checkov) land in ~/.local/bin. Must be on PATH for those tools
# to be reachable as bare commands.
export PATH="$HOME/.local/bin:$PATH"

# Personal scripts
export PATH="$HOME/Scripts/bin:$PATH"

# ripgrep config
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# GPG tty (required for commit signing)
export GPG_TTY=$(tty 2>/dev/null || echo /dev/null)

# GNU coreutils (Linux-compatible versions) — deterministic prefix, no fork per pkg
: "${HOMEBREW_PREFIX:=/opt/homebrew}"
for _pkg in coreutils gnu-sed gnu-tar gawk findutils; do
    _gnubin="$HOMEBREW_PREFIX/opt/$_pkg/libexec/gnubin"
    [[ -d "$_gnubin" ]] && export PATH="$_gnubin:$PATH"
done
unset _pkg _gnubin

# mise is activated once in ~/.zshenv (sourced by every shell type), so it is not
# re-activated here — avoids a redundant `mise activate` subprocess per login shell.

# direnv is hooked in ~/.zshrc (covers non-login interactive shells too); not duplicated here
# to avoid registering the precmd hook twice (which fires direnv on every prompt redundantly).

# Deduplicate PATH
typeset -U PATH path

ZPROFILE_CONF
    configured "$HOME/.zprofile created (editor, pager, XDG, Go, Rust, pnpm, mise, direnv)"

# ---- ~/.zshenv (every zsh invocation — interactive or not) ----
ZSHENV="$HOME/.zshenv"
    info "Creating ~/.zshenv..."
    write_managed "$ZSHENV" "#" <<'ZSHENV_CONF'
# mise (version manager) is sourced by every zsh invocation. This makes managed
# runtimes available in interactive shells, IDE terminals, and scripts.
ZSHENV_CONF
    configured "$HOME/.zshenv created (mise activation for all shell types)"

# ---- ~/.vimrc (basic vim config for server editing) ----
VIMRC="$HOME/.vimrc"
    info "Creating basic ~/.vimrc..."
    write_managed "$VIMRC" "#" <<'VIM_CONF'
" =============================================================================
" ~/.vimrc — minimal but comfortable vim config for server editing
" =============================================================================

" -- Basics -------------------------------------------------------------------
set nocompatible          " Use vim, not vi
syntax on                 " Syntax highlighting
filetype plugin indent on " Filetype detection + plugins + indent

" -- Display ------------------------------------------------------------------
set number                " Line numbers
set relativenumber        " Relative line numbers
set ruler                 " Show cursor position
set showcmd               " Show partial command
set showmode              " Show current mode
set cursorline            " Highlight current line
set scrolloff=8           " Keep 8 lines above/below cursor
set sidescrolloff=8       " Keep 8 columns left/right of cursor
set signcolumn=yes        " Always show sign column
set colorcolumn=100       " Line length guide at 100
set laststatus=2          " Always show status line
set wildmenu              " Better command completion
set wildmode=longest:full,full

" -- Indentation --------------------------------------------------------------
set tabstop=2             " Tab = 2 spaces
set shiftwidth=2          " Indent = 2 spaces
set softtabstop=2         " Backspace deletes 2 spaces
set expandtab             " Tabs -> spaces
set autoindent            " Copy indent from current line
set smartindent           " Smart auto-indent

" -- Search -------------------------------------------------------------------
set incsearch             " Incremental search
set hlsearch              " Highlight matches
set ignorecase            " Case-insensitive search
set smartcase             " ...unless uppercase is used

" -- Editing ------------------------------------------------------------------
set backspace=indent,eol,start  " Backspace works everywhere
set clipboard=unnamed     " Use system clipboard
set mouse=a               " Enable mouse
set hidden                " Allow hidden buffers
set autoread              " Auto-reload changed files
set encoding=utf-8        " UTF-8 encoding
set noerrorbells          " No error bells
set novisualbell          " No visual bells

" -- Files --------------------------------------------------------------------
set nobackup              " No backup files
set nowritebackup         " No backup before overwriting
set noswapfile            " No swap files
set undofile              " Persistent undo
set undodir=~/.vim/undodir

" -- Keybindings --------------------------------------------------------------
" Leader key = Space
let mapleader = " "

" Quick save
nnoremap <leader>w :w<CR>

" Quick quit
nnoremap <leader>q :q<CR>

" Clear search highlights
nnoremap <leader>h :nohlsearch<CR>

" Move between splits
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Move lines up/down in visual mode
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Keep cursor centered when scrolling
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" -- Dracula-ish Colors (no plugin needed) ------------------------------------
set termguicolors
set background=dark
highlight Normal       guifg=#f8f8f2 guibg=#282a36
highlight CursorLine   guibg=#44475a
highlight LineNr       guifg=#6272a4
highlight CursorLineNr guifg=#f8f8f2
highlight Comment      guifg=#6272a4
highlight Visual       guibg=#44475a
highlight Search       guifg=#282a36 guibg=#f1fa8c
highlight StatusLine   guifg=#f8f8f2 guibg=#44475a
highlight ColorColumn  guibg=#44475a

" Create undo directory if it doesn't exist
if !isdirectory($HOME . "/.vim/undodir")
    call mkdir($HOME . "/.vim/undodir", "p")
endif
VIM_CONF
    configured "$HOME/.vimrc created (line numbers, clipboard, mouse, Dracula colors, space leader)"

# ---- ~/.nanorc (better nano for quick edits) ----
NANORC="$HOME/.nanorc"
    info "Creating ~/.nanorc..."
    write_managed "$NANORC" "#" <<'NANO_CONF'
# =============================================================================
# ~/.nanorc — comfortable nano config for quick edits
# =============================================================================

# Display line numbers
set linenumbers

# Show cursor position in status bar
set constantshow

# Smooth scrolling
set smooth

# Auto-indent new lines
set autoindent

# Tab size = 2, convert to spaces
set tabsize 2
set tabstospaces

# Enable mouse
set mouse

# Don't wrap long lines
set nowrap

# Show matching bracket
set matchbrackets "(<[{)>]}"

# Smart home key (jump to first non-whitespace)
set smarthome

# Soft wrapping (display only, doesn't modify file)
set softwrap

# Suspend with Ctrl+Z
set suspend

# Enable syntax highlighting (all installed syntaxes)
include "PLACEHOLDER_BREW_PREFIX/share/nano/*.nanorc"
NANO_CONF
    # Replace placeholder with actual brew prefix
    /usr/bin/sed -i '' "s|PLACEHOLDER_BREW_PREFIX|$(brew --prefix)|g" "$NANORC"
    configured "$HOME/.nanorc created (line numbers, auto-indent, mouse, syntax highlighting)"

# ---- bat extended config (file type mappings) ----
if ! is_done "config:bat-mappings"; then
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    BAT_CONFIG="$BAT_CONFIG_DIR/config"
    if [[ -n "$BAT_CONFIG_DIR" ]] && [[ -f "$BAT_CONFIG" ]]; then
        if append_block_if_missing "$BAT_CONFIG" 'map-syntax "*.env:dotenv"' 'bat file type mappings' <<'BAT_MAPPINGS'

# File type mappings for syntax highlighting
--map-syntax "*.env:dotenv"
--map-syntax "*.env.*:dotenv"
--map-syntax ".env.local:dotenv"
--map-syntax "*.Dockerfile:Dockerfile"
--map-syntax "Dockerfile.*:Dockerfile"
--map-syntax "docker-compose*.yml:YAML"
--map-syntax "*.conf:INI"
--map-syntax "*.cfg:INI"
--map-syntax "Jenkinsfile:Groovy"
--map-syntax "Brewfile:Ruby"
--map-syntax "Caddyfile:Plain Text"
--map-syntax "*.mdx:Markdown"
--map-syntax ".prettierrc:JSON"
--map-syntax ".eslintrc:JSON"
--map-syntax ".babelrc:JSON"
--map-syntax "tsconfig*.json:JSON"

# Style
--style="numbers,changes,header,grid"
--italic-text=always
BAT_MAPPINGS
        then
            configured "bat file type mappings added"
        else
            warn "bat file type mappings already configured"
        fi
    fi
fi
mark_done "config:bat-mappings"
fi

# ---- mise global config (default tool versions) ----
MISE_CONFIG="$HOME/.config/mise/config.toml"
    info "Creating mise global configuration..."
    write_managed "$MISE_CONFIG" "#" <<'MISE_CONF'
# mise global tool versions
# Docs: https://mise.jdx.dev/
# These are defaults — per-project .mise.toml takes precedence

[tools]
node = "lts"
python = "3.12"
# go = "latest"      # installed via brew
# rust = "latest"    # installed via rustup
# java = "21"
# ruby = "latest"

[settings]
# Automatically install tools when entering a directory with .mise.toml
auto_install = true

# Don't prompt to trust config files in ~/Code
trusted_config_paths = ["~/Code"]

# Quieter output
quiet = false
verbose = false
MISE_CONF
    configured "mise configured (auto-install, trust ~/Code)"

# ---- topgrade config ----
# `cleanup` is a [misc] key, NOT a top-level one (#366). It sat at the top level here, and
# topgrade rejects the WHOLE file on one unknown field — "Failed to deserialize ... unknown
# field `cleanup`" — so topgrade had never once run with the config this script generates.
# The path was never the problem; the schema was. Validate any change to the block below
# with `topgrade --config <file> --dry-run`, which fails loudly on a deserialization error
# (#367 wires exactly that into --verify, so this cannot go unnoticed again).
TOPGRADE_CONFIG="$HOME/.config/topgrade.toml"
    info "Creating topgrade configuration..."
    write_managed "$TOPGRADE_CONFIG" "#" <<'TOPGRADE_CONF'
# topgrade configuration — update everything with one command
# Run: topgrade

[misc]
# Cleanup temporary or old files after an update. NOTE: a [misc] key, not a top-level one.
cleanup = true

# Don't ask for confirmation
# assume_yes = true

# Pre-commands (run before updates)
# pre_commands = { "Backup" = "backup-dotfiles" }

[brew]
# Use --greedy (or -a with Repo Cask Upgrade) so casks that self-update are still upgraded
greedy_cask = true
TOPGRADE_CONF
    configured "topgrade configured (cleanup, greedy cask updates)"

# ---- fastfetch config ----
FASTFETCH_CONFIG="$HOME/.config/fastfetch/config.jsonc"
    info "Creating fastfetch configuration..."
    write_managed "$FASTFETCH_CONFIG" "//" <<'FASTFETCH_CONF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "small",
        "color": {
            "1": "#ff79c6",
            "2": "#bd93f9"
        },
        "padding": { "top": 1, "left": 2, "right": 3 }
    },
    "display": {
        "separator": "  ",
        "color": {
            "keys": "#bd93f9",
            "title": "#8be9fd"
        },
        "bar": {
            "char": {
                "elapsed": "█",
                "total": "░"
            },
            "width": 20
        }
    },
    "modules": [
        { "type": "title", "format": "{user-name} ✦ {host-name}" },
        { "type": "separator", "string": "─" },
        { "type": "os", "key": "  󰀵 OS" },
        { "type": "host", "key": "  󰒋 Host" },
        { "type": "kernel", "key": "  󰌽 Kernel" },
        { "type": "uptime", "key": "  󰅐 Uptime" },
        { "type": "packages", "key": "  󰏗 Packages" },
        { "type": "shell", "key": "  󰆍 Shell" },
        { "type": "terminal", "key": "   Terminal" },
        { "type": "separator", "string": "─" },
        { "type": "cpu", "key": "  󰍛 CPU", "showPeCoreCount": false },
        { "type": "gpu", "key": "  󰢮 GPU" },
        { "type": "memory", "key": "  󰘚 Memory" },
        { "type": "disk", "key": "  󰋊 Disk", "folders": "/" },
        { "type": "battery", "key": "  󰁹 Battery" },
        { "type": "separator", "string": "─" },
        {
            "type": "command",
            "key": "   Node",
            "text": "node --version 2>/dev/null | tr -d 'v' || echo '—'"
        },
        {
            "type": "command",
            "key": "   Python",
            "text": "python3 --version 2>/dev/null | cut -d' ' -f2 || echo '—'"
        },
        {
            "type": "command",
            "key": "  󰟓 Go",
            "text": "go version 2>/dev/null | awk '{print $3}' | tr -d 'go' || echo '—'"
        },
        {
            "type": "command",
            "key": "  🦀 Rust",
            "text": "rustc --version 2>/dev/null | awk '{print $2}' || echo '—'"
        },
        {
            "type": "command",
            "key": "  󰜫 Docker",
            "text": "docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo '—'"
        },
        { "type": "separator", "string": "─" },
        { "type": "colors", "symbol": "circle" }
    ]
}
FASTFETCH_CONF
    configured "fastfetch configured (Dracula-Sakura layout, Nerd Font icons, dev tool versions)"

# ---- mprocs config ----
MPROCS_CONFIG="$HOME/.config/mprocs/mprocs.yaml"
    info "Creating mprocs configuration..."
    write_managed "$MPROCS_CONFIG" "#" <<'MPROCS_CONF'
# mprocs global config — local ./mprocs.yaml overrides these defaults.
hide_keymap_window: false
mouse_scroll_speed: 4
scrollback: 5000
proc_list_width: 28
proc_log:
  enabled: true
  dir: "<CONFIG_DIR>/logs"
  mode: append
MPROCS_CONF
    configured "mprocs configured (scrollback, pane width, per-proc logs)"

# ---- broot config + Dracula-Sakura skin ----
BROOT_CONFIG_DIR="$HOME/.config/broot"
BROOT_CONF="$BROOT_CONFIG_DIR/conf.hjson"
BROOT_SKIN="$BROOT_CONFIG_DIR/skins/dracula-sakura.hjson"
    info "Creating broot configuration..."
    write_managed "$BROOT_CONF" "#" <<'BROOT_CONF_HJSON'
imports: [
  "skins/dracula-sakura.hjson"
]

default_flags: "-g"
BROOT_CONF_HJSON
    write_managed "$BROOT_SKIN" "#" <<'BROOT_SKIN_HJSON'
syntax_theme: MochaDark

skin: {
    default: rgb(248, 248, 242) none / rgb(221, 210, 247) rgb(40, 42, 54)
    tree: rgb(138, 136, 199) none / rgb(98, 114, 164) none
    parent: rgb(155, 231, 255) none bold / rgb(155, 231, 255) rgb(40, 42, 54) italic
    file: none none / none none
    directory: rgb(212, 178, 255) none bold / rgb(212, 178, 255) none
    exe: rgb(138, 247, 207) none
    link: rgb(255, 207, 147) none
    pruning: rgb(162, 151, 203) none italic
    perm__: rgb(162, 151, 203) none
    perm_r: rgb(255, 207, 147) none
    perm_w: rgb(255, 122, 168) none
    perm_x: rgb(138, 247, 207) none
    owner: rgb(155, 231, 255) none
    group: rgb(212, 178, 255) none
    count: rgb(255, 159, 227) rgb(50, 52, 72)
    dates: rgb(162, 151, 203) none
    sparse: rgb(255, 122, 168) none italic
    content_extract: rgb(255, 122, 168) none italic
    content_match: rgb(255, 240, 168) rgb(75, 73, 99) bold
    git_branch: rgb(255, 159, 227) none
    git_insertions: rgb(138, 247, 207) none
    git_deletions: rgb(255, 122, 168) none
    git_status_current: rgb(162, 151, 203) none
    git_status_modified: rgb(255, 207, 147) none
    git_status_staged: rgb(138, 247, 207) none
    git_status_new: rgb(155, 231, 255) none bold
    git_status_ignored: rgb(98, 114, 164) none
    git_status_conflicted: rgb(255, 122, 168) none
    git_status_other: rgb(255, 122, 168) none
    selected_line: none rgb(75, 73, 99) / none rgb(50, 52, 72)
    char_match: rgb(255, 240, 168) none bold
    file_error: rgb(255, 122, 168) none
    flag_label: rgb(162, 151, 203) none
    flag_value: rgb(255, 159, 227) none bold
    input: rgb(248, 248, 242) rgb(47, 49, 68) / rgb(221, 210, 247) rgb(47, 49, 68)
    status_error: rgb(248, 248, 242) rgb(74, 48, 64)
    status_job: rgb(40, 42, 54) rgb(255, 207, 147)
    status_normal: rgb(162, 151, 203) rgb(47, 49, 68) / none none
    status_italic: rgb(212, 178, 255) rgb(47, 49, 68) italic / none none
    status_bold: rgb(255, 159, 227) rgb(47, 49, 68) bold / none none
    status_code: rgb(248, 248, 242) rgb(47, 49, 68) / none none
    status_ellipsis: rgb(248, 248, 242) rgb(47, 49, 68) bold / none none
    purpose_normal: none none
    purpose_italic: rgb(155, 231, 255) none italic
    purpose_bold: rgb(155, 231, 255) none bold
    purpose_ellipsis: none none
    scrollbar_track: rgb(50, 52, 72) none / rgb(50, 52, 72) none
    scrollbar_thumb: rgb(106, 93, 134) none / rgb(106, 93, 134) none
    help_paragraph: none none
    help_bold: rgb(255, 207, 147) none bold
    help_italic: rgb(212, 178, 255) none italic
    help_code: rgb(138, 247, 207) rgb(50, 52, 72)
    help_headers: rgb(255, 194, 236) none bold
    help_table_border: rgb(98, 114, 164) none
    preview_title: rgb(248, 248, 242) rgb(40, 42, 54) / rgb(221, 210, 247) rgb(40, 42, 54)
    preview: rgb(248, 248, 242) none / rgb(221, 210, 247) none
    preview_line_number: rgb(138, 136, 199) rgb(40, 42, 54) / rgb(138, 136, 199) none
    preview_separator: rgb(98, 114, 164) none / rgb(98, 114, 164) none
    preview_match: none rgb(255, 240, 168) bold
    diff_line_number: rgb(138, 136, 199) rgb(50, 52, 72)
    diff_added: rgb(248, 248, 242) rgb(35, 59, 54)
    diff_removed: rgb(248, 248, 242) rgb(74, 48, 64)
    hex_null: rgb(138, 136, 199) none
    hex_ascii_graphic: rgb(255, 207, 147) none
    hex_ascii_whitespace: rgb(138, 247, 207) none
    hex_ascii_other: rgb(155, 231, 255) none
    hex_non_ascii: rgb(255, 122, 168) none
    staging_area_title: rgb(248, 248, 242) rgb(40, 42, 54) / rgb(221, 210, 247) rgb(40, 42, 54)
    mode_command_mark: rgb(40, 42, 54) rgb(255, 159, 227) bold
    good_to_bad_0: rgb(138, 247, 207)
    good_to_bad_1: rgb(138, 247, 207)
    good_to_bad_2: rgb(155, 231, 255)
    good_to_bad_3: rgb(212, 178, 255)
    good_to_bad_4: rgb(255, 207, 147)
    good_to_bad_5: rgb(255, 207, 147)
    good_to_bad_6: rgb(255, 159, 227)
    good_to_bad_7: rgb(255, 159, 227)
    good_to_bad_8: rgb(255, 122, 168)
    good_to_bad_9: rgb(255, 122, 168)
}
BROOT_SKIN_HJSON
    configured "broot configured (Dracula-Sakura skin, git-aware defaults)"

# ---- jqp config ----
JQP_CONFIG="$HOME/.jqp.yaml"
    info "Creating jqp configuration..."
    write_managed "$JQP_CONFIG" "#" <<'JQP_CONF'
theme:
  name: "dracula"
  styleOverrides:
    primary: "#ff9fe3"
    secondary: "#a297cb"
    error: "#ff7aa8"
    inactive: "#8a88c7"
    success: "#8af7cf"
  chromaStyleOverrides:
    kc: "#ff9fe3 bold"
    s: "#fff0a8"
    p: "#f8f8f2"
    nb: "#d4b2ff"
    nx: "#9be7ff"
JQP_CONF
    configured "jqp configured (Dracula-Sakura theme overrides)"

# ---- retired aichat config ----
remove_superseded_managed "$HOME/.config/aichat/config.yaml" \
    "aichat was removed from the setup" "(#542)"

# ---- ripgrep config ----
RIPGREPRC="$HOME/.ripgreprc"
    info "Creating ripgrep configuration..."
    write_managed "$RIPGREPRC" "#" <<'RG_CONF'
# Smart case (case-insensitive unless uppercase is used)
--smart-case

# Search hidden files/directories
--hidden

# Follow symlinks
--follow

# Don't search these directories
--glob=!.git/
--glob=!node_modules/
--glob=!.pnpm-store/
--glob=!vendor/
--glob=!dist/
--glob=!build/
--glob=!coverage/
--glob=!.next/
--glob=!__pycache__/
--glob=!*.min.js
--glob=!*.min.css
--glob=!package-lock.json
--glob=!pnpm-lock.yaml
--glob=!yarn.lock

# Max columns before truncation
--max-columns=200
--max-columns-preview

# Add custom type definitions
--type-add=web:*.{html,css,scss,js,jsx,ts,tsx,vue,svelte}
--type-add=config:*.{json,yaml,yml,toml,ini,conf}
--type-add=doc:*.{md,mdx,txt,rst}
--type-add=style:*.{css,scss,sass,less}
RG_CONF
    configured "$HOME/.ripgreprc configured (smart-case, hidden files, custom types)"

# ---- fd ignore ----
FDIGNORE="$HOME/.fdignore"
    info "Creating fd ignore patterns..."
    write_managed "$FDIGNORE" "#" <<'FD_CONF'
# fd global ignore patterns
.git/
node_modules/
.pnpm-store/
vendor/
dist/
build/
coverage/
.next/
out/
__pycache__/
.venv/
*.min.js
*.min.css
.DS_Store
.Trash/
FD_CONF
    configured "$HOME/.fdignore created"

# ---- btop Dracula-Sakura theme ----
BTOP_CONFIG_DIR="$HOME/.config/btop"
BTOP_CONFIG="$BTOP_CONFIG_DIR/btop.conf"
BTOP_THEME="$BTOP_CONFIG_DIR/themes/dracula-sakura.theme"
BTOP_OLD_THEME="$BTOP_CONFIG_DIR/themes/dracula.theme"
    info "Creating btop configuration..."
    write_managed "$BTOP_CONFIG" "#" <<'BTOP_CONF'
#? Config file for btop

# Color theme
color_theme = "dracula-sakura"

# Update time in milliseconds
update_ms = 1000

# Processes sorting
proc_sorting = "cpu lazy"

# Show CPU graph
shown_boxes = "cpu mem net proc"

# Tree view for processes
proc_tree = true

# Show memory as bytes instead of percent
mem_graphs = true

# Use truecolor
truecolor = true

# Rounded corners
rounded_corners = true
BTOP_CONF
    # Write the Dracula-Sakura theme file btop actually reads.
    write_managed "$BTOP_THEME" "#" <<'BTOP_DRACULA'
# Dracula-Sakura theme for btop
theme[main_bg]="#282a36"
theme[main_fg]="#f8f8f2"
theme[title]="#ffc2ec"
theme[hi_fg]="#d4b2ff"
theme[selected_bg]="#6a5d86"
theme[selected_fg]="#f8f8f2"
theme[inactive_fg]="#8a88c7"
theme[graph_text]="#ddd2f7"
theme[meter_bg]="#323448"
theme[proc_misc]="#9be7ff"
theme[cpu_box]="#d4b2ff"
theme[mem_box]="#8af7cf"
theme[net_box]="#ff9fe3"
theme[proc_box]="#9be7ff"
theme[div_line]="#4b4963"
theme[temp_start]="#8af7cf"
theme[temp_mid]="#ffcf93"
theme[temp_end]="#ff7aa8"
theme[cpu_start]="#d4b2ff"
theme[cpu_mid]="#ff9fe3"
theme[cpu_end]="#ff7aa8"
theme[free_start]="#8af7cf"
theme[free_mid]="#fff0a8"
theme[free_end]="#ff7aa8"
theme[cached_start]="#9be7ff"
theme[cached_mid]="#d4b2ff"
theme[cached_end]="#ff9fe3"
theme[available_start]="#8af7cf"
theme[available_mid]="#fff0a8"
theme[available_end]="#ffcf93"
theme[used_start]="#ff9fe3"
theme[used_mid]="#ffcf93"
theme[used_end]="#ff7aa8"
theme[download_start]="#d4b2ff"
theme[download_mid]="#ff9fe3"
theme[download_end]="#ff7aa8"
theme[upload_start]="#8af7cf"
theme[upload_mid]="#fff0a8"
theme[upload_end]="#ffcf93"
theme[process_start]="#9be7ff"
theme[process_mid]="#d4b2ff"
theme[process_end]="#ff9fe3"
BTOP_DRACULA
    remove_superseded_managed "$BTOP_OLD_THEME" \
        "btop reads $BTOP_THEME" "(#414)"
    configured "btop configured with Dracula-Sakura theme"

# ---- lazydocker Dracula-Sakura config ----
LAZYDOCKER_CONFIG_DIR="$HOME/.config/lazydocker"
LAZYDOCKER_CONFIG="$LAZYDOCKER_CONFIG_DIR/config.yml"
    info "Creating lazydocker configuration..."
    write_managed "$LAZYDOCKER_CONFIG" "#" <<'LAZYDOCKER_CONF'
gui:
  theme:
    activeBorderColor:
      - "#ff9fe3"
      - bold
    inactiveBorderColor:
      - "#4b4963"
    selectedLineBgColor:
      - "#6a5d86"
    inactiveViewSelectedLineBgColor:
      - "#323448"
    optionsTextColor:
      - "#9be7ff"
    defaultFgColor:
      - "#ddd2f7"
  returnImmediately: false
  wrapMainPanel: true
commandTemplates:
  restartService: docker-compose restart {{ .Service.Name }}
  dockerCompose: docker compose
logs:
  timestamps: true
  since: "60m"
LAZYDOCKER_CONF
    configured "lazydocker configured with Dracula-Sakura theme"

# ---- Git commit template ----
GIT_COMMIT_TEMPLATE="$HOME/.gitmessage"
    info "Creating git commit template..."
    write_managed "$GIT_COMMIT_TEMPLATE" "#" <<'GIT_TEMPLATE'
# <type>(<scope>): <short summary>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
#
# Body (optional): explain WHAT and WHY, not HOW
#

# Breaking changes (optional):
# BREAKING CHANGE: <description>
#
# Closes: #<issue>
GIT_TEMPLATE
    git_global commit.template "$GIT_COMMIT_TEMPLATE"
    configured "Git commit template created and registered"

# ---- Global git hooks directory ----
GIT_HOOKS_DIR="$HOME/.config/git/hooks"
info "Configuring global git hooks..."

# Setting core.hooksPath makes git read ONLY this directory: per-repo .git/hooks is
# never consulted, for any hook type. Shipping just a `pre-commit` here therefore
# killed every other per-repo hook on the machine — husky's commit-msg, a
# .pre-commit-config.yaml's pre-push, lint-staged, all of it — silently (#260).
#
# So every hook type gets a delegator, and the delegator CHAINS rather than execs:
# third-party tools write into this same directory, so a delegator that only ran the
# per-repo hook would silently disable them instead.
#
# Deliberately not covered: the server-side hooks (pre-receive, update, post-update,
# proc-receive), and the hot-path ones where a wrapper costs more than it delivers
# (reference-transaction, post-index-change, fsmonitor-watchman).
GIT_HOOK_TYPES=(
    applypatch-msg pre-applypatch post-applypatch
    pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
    pre-rebase post-checkout post-merge pre-push post-rewrite
    sendemail-validate
)

# Shared chain logic, sourced by every delegator. Not named after a hook, so git
# ignores it; keeping it in one file means the chain semantics can't drift per type.
write_managed_script "$GIT_HOOKS_DIR/dev-setup-chain.sh" <<'HOOK_CHAIN_LIB'
#!/usr/bin/env bash
# Sourced by every hook in this directory. Runs the repository's own hook, then
# each preserved third-party hook. It stops on the first nonzero status.

run_hook_chain() {
    local hook="$1"; shift
    local hooks_dir status=0 stdin_file="" repo_hook f
    hooks_dir="$(dirname "${BASH_SOURCE[0]}")"
    DEV_SETUP_REPO_HOOK_RAN=0

    # Buffer stdin once, then give each chained hook its own copy.
    case "$hook" in
        pre-push|post-rewrite|push-to-checkout)
            stdin_file="$(mktemp)"
            cat > "$stdin_file"
            ;;
    esac

    _chain_run() {
        local script="$1"; shift
        if [ -n "$stdin_file" ]; then
            "$script" "$@" < "$stdin_file"
        else
            "$script" "$@"
        fi
    }

    # 1. The repository's own hook.
    #
    #    NOT `git rev-parse --git-path hooks/<type>`: that is itself core.hooksPath
    #    aware, so with this directory configured it resolves right back to THIS
    #    delegator, which then runs itself forever — every `git commit` on the machine
    #    hangs. Use the common git dir instead (common, not absolute: a linked worktree
    #    has its own gitdir but shares the main repo's hooks/).
    local common candidate_dir hooks_real
    common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    [ -n "$common" ] || common="$(git rev-parse --git-common-dir 2>/dev/null)"
    repo_hook=""
    if [ -n "$common" ]; then
        # Belt and braces: if the repo's hooks dir IS this directory, there is no
        # per-repo hook to run — only this delegator, and re-entering it recurses.
        hooks_real="$(cd "$hooks_dir" 2>/dev/null && pwd -P)"
        candidate_dir="$(cd "$common/hooks" 2>/dev/null && pwd -P)"
        if [ -n "$candidate_dir" ] && [ "$candidate_dir" != "$hooks_real" ]; then
            repo_hook="$common/hooks/$hook"
        fi
    fi

    if [ -n "$repo_hook" ] && [ -x "$repo_hook" ]; then
        DEV_SETUP_REPO_HOOK_RAN=1
        _chain_run "$repo_hook" "$@" || status=$?
        if [ "$status" -ne 0 ]; then
            [ -n "$stdin_file" ] && rm -f "$stdin_file"
            return "$status"
        fi
    fi

    # 2. Third-party hooks preserved when a delegator took their name.
    if [ -d "$hooks_dir/$hook.d" ]; then
        for f in "$hooks_dir/$hook.d"/*; do
            [ -x "$f" ] || continue
            _chain_run "$f" "$@" || status=$?
            if [ "$status" -ne 0 ]; then
                [ -n "$stdin_file" ] && rm -f "$stdin_file"
                return "$status"
            fi
        done
    fi

    [ -n "$stdin_file" ] && rm -f "$stdin_file"
    return 0
}
HOOK_CHAIN_LIB

# Move a pre-existing third-party hook out of the way so a delegator can take its
# name, preserving it in <type>.d/ where the chain will still run it. Idempotent: a
# tool that re-creates its hooks on every invocation would otherwise stack up
# identical copies, so one that is already preserved is dropped rather than added.
preserve_foreign_hook() {
    local type="$1"
    local path="$GIT_HOOKS_DIR/$type" dest_dir="$GIT_HOOKS_DIR/$type.d" name f

    # Remove Git LFS hooks left by earlier releases. The package is retired, so
    # these hooks can only fail after its binary disappears.
    for f in "$dest_dir"/*; do
        [[ -f "$f" ]] || continue
        grep -qE 'git[- ]lfs' "$f" 2>/dev/null || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove retired Git LFS hook $type.d/${f##*/}"
        else
            rm -f "$f"
            info "Removed retired Git LFS hook $type.d/${f##*/}"
        fi
    done
    rmdir "$dest_dir" 2>/dev/null || true

    [[ -f "$path" ]] || return 0
    grep -qF "dev-setup managed block" "$path" 2>/dev/null && return 0

    if grep -qE 'git[- ]lfs' "$path" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove retired global Git LFS $type hook"
        else
            rm -f "$path"
            info "Removed retired global Git LFS $type hook"
        fi
        return 0
    fi

    name="10-preexisting"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would preserve third-party $type hook as $type.d/$name"
        return 0
    fi
    mkdir -p "$dest_dir"
    for f in "$dest_dir"/*; do
        [[ -f "$f" ]] || continue
        if cmp -s "$path" "$f"; then rm -f "$path"; return 0; fi
    done
    [[ -e "$dest_dir/$name" ]] && name="${name}.$(date +%Y%m%d%H%M%S)"
    mv "$path" "$dest_dir/$name"
    chmod +x "$dest_dir/$name"
    info "Preserved third-party $type hook as $type.d/$name (#260)"
}

# Delegators for every type except pre-commit, which carries this script's own checks
# after the chain. The body is identical for all of them: the hook derives its own
# name from $0, so one quoted heredoc serves the whole list.
for _hook_type in "${GIT_HOOK_TYPES[@]}"; do
    [[ "$_hook_type" == "pre-commit" ]] && continue
    preserve_foreign_hook "$_hook_type"
    write_managed_script "$GIT_HOOKS_DIR/$_hook_type" <<'HOOK_DELEGATOR'
#!/usr/bin/env bash
# Global hook delegator — core.hooksPath means git reads only this directory, so this
# runs the repo's own hook of the same name plus any third-party hook in <type>.d/.
_lib="$(dirname "$0")/dev-setup-chain.sh"
# Never block a git operation because the helper is missing.
[ -r "$_lib" ] || exit 0
# shellcheck source=/dev/null
. "$_lib"
run_hook_chain "$(basename "$0")" "$@"
HOOK_DELEGATOR
done
unset _hook_type

# Pre-commit hook: chain first, then this script's own checks
preserve_foreign_hook pre-commit
write_managed_script "$GIT_HOOKS_DIR/pre-commit" <<'HOOK_PRECOMMIT'
#!/usr/bin/env bash
# Global pre-commit hook — runs on ALL repos
# Note: core.hooksPath overrides per-repo .git/hooks, so this delegates first (#260)

_lib="$(dirname "$0")/dev-setup-chain.sh"
if [ -r "$_lib" ]; then
    # shellcheck source=/dev/null
    . "$_lib"
    run_hook_chain pre-commit "$@" || exit $?
    # A repo with its own pre-commit hook owns the policy: this hook used to `exec` it,
    # so its checks never ran alongside. Preserved deliberately — running the generic
    # checks too would start blocking commits that were fine yesterday.
    [ "${DEV_SETUP_REPO_HOOK_RAN:-0}" = "1" ] && exit 0
fi

# Check for leftover debug statements — scoped per language so shell/markdown/config
# files aren't false-flagged for merely *mentioning* a debug token (e.g. a script that
# documents `console.log`, or docs with a `debugger` example). Add a trailing `debug-ok`
# comment to whitelist an intentional line. (-z/-r: handle spaces in names + empty set.)
debug_hits=""
while IFS= read -r -d '' f; do
    case "$f" in
        *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro) pat='console\.log\|debugger' ;;
        *.py)              pat='import pdb\|pdb\.set_trace\|breakpoint()' ;;
        *.rb|*.rake|*.erb) pat='binding\.pry\|binding\.irb' ;;
        *) continue ;;
    esac
    hits=$(grep -nH "$pat" "$f" 2>/dev/null | grep -v 'debug-ok')
    [ -n "$hits" ] && debug_hits="${debug_hits}${hits}"$'\n'
done < <(git diff --cached --name-only --diff-filter=d -z)
if [ -n "$debug_hits" ]; then
    echo ""
    echo "ERROR: Debug statements found in staged files:"
    printf '%s' "$debug_hits"
    echo ""
    echo "Remove them, add a trailing 'debug-ok' comment, or commit with --no-verify to bypass."
    exit 1
fi

# Check for large files (> 5MB)
large_files=$(git diff --cached --name-only --diff-filter=d -z | while IFS= read -r -d '' f; do
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    if [[ "$size" -gt 5242880 ]]; then
        echo "  $f ($(( size / 1048576 ))MB)"
    fi
done)
if [[ -n "$large_files" ]]; then
    echo ""
    echo "ERROR: Large files detected (>5MB):"
    echo "$large_files"
    echo ""
    echo "Reduce the file size or commit with --no-verify to bypass."
    exit 1
fi

# Check for merge conflict markers — anchored to line start and requiring the trailing
# space/ref that real `<<<<<<< `, `||||||| `, `>>>>>>> ` markers always carry, so a
# markdown setext heading underline (`=======`) or an ASCII rule doesn't false-flag.
# The angle/pipe markers are unambiguous; a genuine conflict always contains them.
#
# Loop rather than `... | xargs -0 -r grep -l`: an `if` on that pipeline tests xargs's
# status, not grep's, and with an empty staged set `-r` makes xargs run nothing and exit 0
# — so it reported a conflict precisely when there was nothing to check, blocking every
# `git commit --amend` that staged no new changes. Same idiom as the two checks above.
conflict_files=""
while IFS= read -r -d '' f; do
    if grep -qE '^(<{7}|>{7}|\|{7}) ' "$f" 2>/dev/null; then
        conflict_files="${conflict_files}  ${f}"$'\n'
    fi
done < <(git diff --cached --name-only --diff-filter=d -z)
if [ -n "$conflict_files" ]; then
    echo ""
    echo "ERROR: Merge conflict markers found in staged files:"
    printf '%s' "$conflict_files"
    echo ""
    echo "Resolve them, or commit with --no-verify to bypass."
    exit 1
fi

exit 0
HOOK_PRECOMMIT

# Register global hooks directory
git_global core.hooksPath "$GIT_HOOKS_DIR"

configured "Global git hooks created (${#GIT_HOOK_TYPES[@]} delegators + debug/large-file/conflict checks)"

# ---- AWS config ----
AWS_CONFIG="$HOME/.aws/config"
    info "Creating AWS CLI configuration..."
    chmod 700 "$HOME/.aws"
    write_managed "$AWS_CONFIG" "#" <<'AWS_CONF'
# AWS CLI configuration
# Docs: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html

[default]
region = us-east-1
output = json
cli_pager = bat --style=plain
cli_auto_prompt = on-partial

# Retry configuration
retry_mode = adaptive
max_attempts = 3

# SSO profile template — duplicate and fill in for each account:
# [profile my-dev]
# sso_start_url = https://myorg.awsapps.com/start
# sso_region = us-east-1
# sso_account_id = 123456789012
# sso_role_name = DeveloperAccess
# region = us-east-1
# output = json
AWS_CONF
    chmod 600 "$AWS_CONFIG"
    configured "AWS CLI configured (us-east-1, json, bat pager, auto-prompt)"

# ---- GitHub CLI config ----
GH_CONFIG_DIR="$HOME/.config/gh"
GH_CONFIG="$GH_CONFIG_DIR/config.yml"
    info "Creating GitHub CLI configuration..."
    write_managed "$GH_CONFIG" "#" <<'GH_CONF'
# GitHub CLI configuration
git_protocol: ssh
editor: micro
prompt: enabled
pager: delta

aliases:
    co: pr checkout
    pv: pr view --web
    pc: pr create --web
    pl: pr list
    il: issue list
    iv: issue view --web
    ic: issue create --web
    rv: repo view --web
    rc: repo clone
    rl: repo list
    runs: run list
    watch: run watch
    rerun: run rerun --failed
    pm: pr merge --squash --delete-branch
    rel: release create --generate-notes
GH_CONF
    configured "GitHub CLI configured (SSH protocol, micro editor, delta pager, aliases)"


# ---- pip config ----
# This looks like dead weight now that uv is the package manager and there is no
# `pip` alias — it is not. Bare `pip` is absent, but `pip3` ships inside Homebrew's
# python@3.14, which ~20 installed formulae depend on (awscli, cfn-lint, checkov,
# csvkit, borgmatic, …), so it cannot be removed and stays one tab-completion away.
# `require-virtualenv = true` below is what stops an absent-minded `pip3 install`
# from polluting that shared interpreter. Keep this file.
PIP_CONFIG_DIR="$HOME/.config/pip"
PIP_CONFIG="$PIP_CONFIG_DIR/pip.conf"
    info "Creating pip configuration..."
    write_managed "$PIP_CONFIG" "#" <<'PIP_CONF'
[global]
# Require a virtualenv to install packages (prevents global pollution)
require-virtualenv = true

# Disable pip version check (less noise)
disable-pip-version-check = true

# No telemetry
no-input = true

# Timeout
timeout = 30

[install]
# Compile bytecode
compile = true
PIP_CONF
    configured "pip configured (require virtualenv, no telemetry)"

# ---- gemrc (Ruby) ----
GEMRC="$HOME/.gemrc"
    info "Creating gemrc..."
    write_managed "$GEMRC" "#" <<'GEM_CONF'
# Skip documentation when installing gems (saves time and disk)
gem: --no-document
GEM_CONF
    configured "$HOME/.gemrc created (no docs on gem install)"

# Retired database client configs are removed only when their managed blocks
# prove ownership. History files and other user data remain untouched.
remove_superseded_managed "$HOME/.config/pgcli/config" \
    "pgcli was removed from the setup" "(#555)"

# ---- harlequin config ----
# Harlequin does NOT read ~/.config (#366). Its own --help: "By default, Harlequin finds
# files named .harlequin.toml in the current directory and the home directory (~) and
# merges them." We wrote ~/.config/harlequin/config.toml for a long time, so the Dracula
# theme and vscode keymap below never applied to anything. Same shape as the lazygit bug
# in #333. The alternative — exporting HARLEQUIN_CONFIG_PATH — would only work for shells
# that source our .zshrc, so the documented home-directory path is the robust one.
HARLEQUIN_CONFIG="$HOME/.harlequin.toml"
HARLEQUIN_SUPERSEDED="$HOME/.config/harlequin/config.toml"
    info "Creating harlequin configuration..."
    write_managed "$HARLEQUIN_CONFIG" "#" <<'HARLEQUIN_CONF'
# Harlequin SQL IDE — https://harlequin.sql/docs/config-file/
[defaults]
theme = "dracula"
keymap_name = ["vscode"]
show_files = true
locale = "en_US.UTF-8"
HARLEQUIN_CONF
    remove_superseded_managed "$HARLEQUIN_SUPERSEDED" \
        "harlequin reads $HARLEQUIN_CONFIG" "(#366)"
    configured "harlequin configured (Dracula theme, vscode keymap)"

remove_superseded_managed "$HOME/.myclirc" \
    "mycli was removed from the setup" "(#555)"

# ---- just config (global justfile with common recipes) ----
JUSTFILE_GLOBAL="$HOME/.justfile"
    info "Creating global justfile with common recipes..."
    write_managed "$JUSTFILE_GLOBAL" "#" <<'JUSTFILE_CONF'
# =============================================================================
# Global Justfile — available from any directory via: just --justfile ~/.justfile
# =============================================================================
# Tip: alias gj="just --justfile ~/.justfile --working-directory ."


# List all recipes
default:
    @just --justfile {{justfile()}} --list

# ── System ───────────────────────────────────────────────────────────────────

# Update everything (brew, npm, pip, macOS)
update:
    topgrade

# Show system info
info:
    fastfetch

# Flush DNS cache
flush-dns:
    sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
    @echo "DNS cache flushed"

# Show listening ports
ports:
    lsof -iTCP -sTCP:LISTEN -n -P | tail -n +2 | sort -t: -k2 -n

# ── Git ──────────────────────────────────────────────────────────────────────

# Interactive rebase last N commits
rebase n="5":
    git rebase -i HEAD~{{n}}

# Undo last commit (keep changes staged)
undo:
    git reset --soft HEAD~1

# Show recent branches sorted by last commit
branches:
    git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:relative)\t%(refname:short)' | head -20

# ── Docker ───────────────────────────────────────────────────────────────────

# Clean Docker: unused images, containers, volumes
docker-clean:
    docker system prune -af --volumes

# Show Docker disk usage
docker-usage:
    docker system df

# ── Dev ──────────────────────────────────────────────────────────────────────

# Serve current directory on port 8080
serve port="8080":
    miniserve --color-scheme-dark dracula -qr . -p {{port}}

# Generate a UUID
uuid:
    @uuidgen | tr '[:upper:]' '[:lower:]'

# Encode/decode base64
b64-encode text:
    @echo -n "{{text}}" | base64

b64-decode text:
    @echo -n "{{text}}" | base64 -d && echo

# ── Network ──────────────────────────────────────────────────────────────────

# Show public IP address
ip:
    @curl -s https://ifconfig.me && echo

# Show local IP address
local-ip:
    @ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"

# Kill process on a specific port
kill-port port:
    @lsof -ti:{{port}} | xargs kill -9 2>/dev/null && echo "Killed process on port {{port}}" || echo "No process on port {{port}}"

# Quick HTTP status check
status url:
    @curl -o /dev/null -s -w "HTTP %{http_code} — %{time_total}s\n" "{{url}}"

# ── Cleanup ──────────────────────────────────────────────────────────────────

# Remove all node_modules directories under ~/Code
node-clean:
    @echo "Finding node_modules under ~/Code..."
    @du -sh $(find ~/Code -maxdepth 4 -name node_modules -type d -prune 2>/dev/null) 2>/dev/null | sort -rh
    @echo ""
    @echo "Run: find ~/Code -name node_modules -type d -prune -exec rm -rf {} + to delete all"

# Nuclear Docker cleanup (everything)
docker-nuke:
    docker system prune -af --volumes
    @echo "Docker wiped clean."

# Remove .DS_Store files recursively
ds-clean:
    @find . -name '.DS_Store' -type f -delete 2>/dev/null
    @echo ".DS_Store files removed"

# ── Quick Info ───────────────────────────────────────────────────────────────

# Show a cheatsheet for a command (via tldr)
cheat cmd:
    @tldr {{cmd}}

# Generate a timestamp
timestamp:
    @date '+%Y-%m-%dT%H:%M:%S%z'

# Show weather (via wttr.in)
weather city="":
    @curl -s "wttr.in/{{city}}?format=3"

# Git standup — what did I do yesterday?
standup:
    @git log --oneline --since='yesterday' --author="$(git config user.name)" 2>/dev/null || echo "Not in a git repo"

# Count lines of code in current directory
loc:
    @scc . 2>/dev/null || find . -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' -o -name '*.rs' | xargs wc -l | tail -1
JUSTFILE_CONF
    configured "Global justfile created (~/.justfile — system, git, docker, network, cleanup, info recipes)"

# ---- Retired Ghostty config and launcher ------------------------------------
# Normal reruns must stop the login agent even before the user requests package
# cleanup. Remove the config only when its managed block has no user content.
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
remove_superseded_managed "$GHOSTTY_CONFIG" "Kitty now owns the terminal configuration." "#544"

# The old launch agent predates managed plist helpers. Compare the complete file
# with the exact generated form before removal, so a user-edited agent survives.
GHOSTTY_PLIST="$HOME/Library/LaunchAgents/com.ghostty.autostart.plist"
_ghostty_plist_expected="$(cat <<'GHOSTTY_PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.ghostty.autostart</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-gW</string>
        <string>-a</string>
        <string>Ghostty</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
GHOSTTY_PLIST_EOF
)"
if [[ -f "$GHOSTTY_PLIST" ]]; then
    if ! printf '%s\n' "$_ghostty_plist_expected" | diff -q - "$GHOSTTY_PLIST" >/dev/null 2>&1; then
        warn "Left $GHOSTTY_PLIST alone. It differs from the launcher generated by this script."
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would unload and remove the retired Ghostty login agent"
    else
        launchctl bootout "gui/$(id -u)" "$GHOSTTY_PLIST" >> "$LOG_FILE" 2>&1 \
            || launchctl unload "$GHOSTTY_PLIST" >> "$LOG_FILE" 2>&1 \
            || true
        rm -f "$GHOSTTY_PLIST"
        info "Removed the retired Ghostty login agent. Kitty does not need a background launcher. #544"
    fi
fi
unset _ghostty_plist_expected

# ---- Kitty config -----------------------------------------------------------
KITTY_CONFIG_DIR="$HOME/.config/kitty"
KITTY_CONFIG="$KITTY_CONFIG_DIR/kitty.conf"
info "Configuring Kitty..."
write_managed "$KITTY_CONFIG" "#" <<'KITTY_CONF'
# Kitty configuration
# Docs: https://sw.kovidgoyal.net/kitty/conf/

# Font. Use the Nerd Font variant for eza, starship, lazygit, and other glyphs.
# If double-width glyphs misalign, use "JetBrainsMono Nerd Font Mono".
font_family JetBrainsMono Nerd Font
font_size 14.0

# Dracula-Sakura theme
background #282a36
foreground #f8f8f2
selection_background #6a5d86
selection_foreground #f8f8f2
color0 #2f3144
color1 #ff7aa8
color2 #8af7cf
color3 #fff0a8
color4 #d4b2ff
color5 #ff9fe3
color6 #9be7ff
color7 #f8f8f2
color8 #8a88c7
color9 #ff7aa8
color10 #8af7cf
color11 #fff0a8
color12 #d4b2ff
color13 #ffc2ec
color14 #9be7ff
color15 #ffffff

# Window. Kitty accepts vertical and horizontal padding as a two-value setting.
window_padding_width 4 8
hide_window_decorations no
macos_titlebar_color background

# Behavior
copy_on_select clipboard
confirm_os_window_close 0
mouse_hide_wait -1
shell_integration enabled
KITTY_CONF
configured "Kitty configured (JetBrainsMono Nerd Font, Dracula-Sakura palette, integrated titlebar)"

# ---- Retired SketchyBar config ----
# Remove only generator-owned files during normal config refreshes. The broader
# --cleanup path removes the directory after the sketchybar command is absent.
for _sketchybar_file in \
    "$HOME/.config/sketchybar/colors.sh" \
    "$HOME/.config/sketchybar/icons.sh" \
    "$HOME/.config/sketchybar/sketchybarrc" \
    "$HOME/.config/sketchybar/plugins/front_app.sh" \
    "$HOME/.config/sketchybar/plugins/clock.sh" \
    "$HOME/.config/sketchybar/plugins/battery.sh" \
    "$HOME/.config/sketchybar/plugins/bluetooth.sh" \
    "$HOME/.config/sketchybar/plugins/wifi.sh" \
    "$HOME/.config/sketchybar/plugins/volume.sh" \
    "$HOME/.config/sketchybar/plugins/cpu.sh" \
    "$HOME/.config/sketchybar/plugins/mem.sh" \
    "$HOME/.config/sketchybar/plugins/vpn.sh" \
    "$HOME/.config/sketchybar/plugins/vpn_toggle.sh" \
    "$HOME/.config/sketchybar/plugins/shottr_click.sh" \
    "$HOME/.config/sketchybar/plugins/shottr.sh"; do
    remove_superseded_managed "$_sketchybar_file" \
        "SketchyBar was removed from the setup" "(#542)"
done
if [[ "$DRY_RUN" != "true" ]]; then
    rmdir "$HOME/.config/sketchybar/plugins" 2>/dev/null || true
    rmdir "$HOME/.config/sketchybar" 2>/dev/null || true
fi
unset _sketchybar_file

# ---- clipse clipboard listener (launchd agent) ----
# clipse runs a background listener to capture clipboard history. Register a
# LaunchAgent so it starts at login.
#
# The subcommand matters: `-listen` DAEMONIZES (forks a detached listener and
# the supervised parent exits immediately). Paired with KeepAlive that made
# launchd respawn the job every 10s while the previously detached listener kept
# running — ~110 MB orphaned per respawn, ~40 GB/hour, until the machine ran out
# of RAM and WindowServer missed its watchdog check-in and hard-reset the Mac.
# `-listen-darwin` stays in the foreground, which is what launchd needs in order
# to actually supervise (and restart) a single listener. See #253.
#
# This block deliberately does NOT use is_done/`[[ -f ]]` create-once guards:
# machines provisioned before the fix already have the broken plist on disk, so
# a create-once block would leave them leaking forever. It rewrites in place
# whenever the desired content differs, and reaps orphans with `clipse -kill`.
CLIPSE_BIN="$(command -v clipse || echo "$GOBIN/clipse")"
CLIPSE_PLIST="$HOME/Library/LaunchAgents/com.clipse.listener.plist"
if [[ ! -x "$CLIPSE_BIN" ]]; then
    warn "clipse not installed — skipping clipboard listener agent"
else
    CLIPSE_PLIST_WANT="$(cat <<CLIPSE_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.clipse.listener</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLIPSE_BIN</string>
        <string>-listen-darwin</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
CLIPSE_PLIST_EOF
)"
    if [[ -f "$CLIPSE_PLIST" ]] && [[ "$(cat "$CLIPSE_PLIST")" == "$CLIPSE_PLIST_WANT" ]]; then
        info "clipse clipboard listener already up to date"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would (re)install clipse clipboard-listener launch agent"
    else
        if [[ -f "$CLIPSE_PLIST" ]]; then
            info "Repairing clipse clipboard-listener launch agent (respawn leak, #253)..."
        else
            info "Creating clipse clipboard-listener launch agent..."
        fi
        mkdir -p "$HOME/Library/LaunchAgents"
        launchctl unload "$CLIPSE_PLIST" >> "$LOG_FILE" 2>&1 || true
        # Reap any listeners orphaned by the old `-listen` respawn loop.
        "$CLIPSE_BIN" -kill >> "$LOG_FILE" 2>&1 || true
        printf '%s\n' "$CLIPSE_PLIST_WANT" > "$CLIPSE_PLIST"
        launchctl load "$CLIPSE_PLIST" >> "$LOG_FILE" 2>&1 || warn "Could not load clipse launch agent"
        success "clipse clipboard listener registered (starts at login)"
    fi
fi
mark_done "config:clipse"

# ---- email + calendar (herald) ----
# Herald owns account, server, and credential data. This block manages only a local
# theme asset and the `theme.name` selection. All other config values stay user-owned.
HERALD_CONFIG_DIR="$HOME/.herald"
HERALD_CONFIG="$HERALD_CONFIG_DIR/conf.yaml"
HERALD_THEME_FILE="$HERALD_CONFIG_DIR/themes/dracula-sakura.yaml"
    info "Writing herald Dracula-Sakura theme..."
    write_generated "$HERALD_THEME_FILE" <<'HERALD_THEME_CONF'
version: 1
name: dracula-sakura
display_name: Dracula Sakura
inherits: herald-dark
roles:
  text.primary:
    fg: "#f8f8f2"
  text.muted:
    fg: "#ddd2f7"
  text.dim:
    fg: "#a297cb"
  chrome.title_bar:
    fg: "#ffc2ec"
    bg: "#282a36"
    bold: true
  chrome.tab_active:
    fg: "#282a36"
    bg: "#ff9fe3"
    bold: true
  chrome.tab_inactive:
    fg: "#ddd2f7"
    bg: "#323448"
  chrome.status_bar:
    fg: "#f8f8f2"
    bg: "#2f3144"
  chrome.hint_bar:
    fg: "#ddd2f7"
    bg: "#323448"
  chrome.table_header:
    fg: "#9be7ff"
    bg: "#2f3144"
    bold: true
  focus.panel_border:
    fg: "#4b4963"
  focus.panel_border_focused:
    fg: "#d4b2ff"
  focus.selection_active:
    fg: "#282a36"
    bg: "#ff9fe3"
    bold: true
  focus.selection_inactive:
    fg: "#f8f8f2"
    bg: "#4b4963"
  focus.visual_selection:
    fg: "#282a36"
    bg: "#d4b2ff"
  metadata.label:
    fg: "#a297cb"
  metadata.sender:
    fg: "#8af7cf"
    bold: true
  metadata.date:
    fg: "#ddd2f7"
  metadata.subject:
    fg: "#fff0a8"
    bold: true
  metadata.tag:
    fg: "#9be7ff"
    bold: true
  severity.info:
    fg: "#9be7ff"
  severity.success:
    fg: "#8af7cf"
  severity.warning:
    fg: "#ffcf93"
  severity.error:
    fg: "#ff7aa8"
  severity.destructive:
    fg: "#fff5f5"
    bg: "#7a2844"
    bold: true
  compose.accent:
    fg: "#ff9fe3"
  compose.attachment:
    fg: "#9be7ff"
  contacts.keyword_search:
    fg: "#ff9fe3"
  contacts.company:
    fg: "#ddd2f7"
  rules.title:
    fg: "#ffc2ec"
    bold: true
  rules.selected:
    fg: "#282a36"
    bg: "#ff9fe3"
HERALD_THEME_CONF
    configured "herald theme asset written (Dracula-Sakura)"

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -f "$HERALD_CONFIG" ]]; then
        info "[DRY RUN] Would set herald theme.name to dracula-sakura in $HERALD_CONFIG"
    else
        info "[DRY RUN] Would seed $HERALD_CONFIG with theme.name = dracula-sakura"
    fi
else
    mkdir -p "$HERALD_CONFIG_DIR"
    if [[ ! -f "$HERALD_CONFIG" ]]; then
        printf 'theme:\n  name: dracula-sakura\n' > "$HERALD_CONFIG"
        chmod 600 "$HERALD_CONFIG"
        configured "herald config seeded (theme only; accounts remain unconfigured)"
    elif installed yq; then
        _herald_mode="$(stat -f '%Lp' "$HERALD_CONFIG" 2>/dev/null || true)"
        _herald_tmp="$(mktemp)"
        if yq eval '.theme.name = "dracula-sakura"' "$HERALD_CONFIG" > "$_herald_tmp" 2>/dev/null; then
            mv "$_herald_tmp" "$HERALD_CONFIG"
            [[ -n "$_herald_mode" ]] && chmod "$_herald_mode" "$HERALD_CONFIG" 2>/dev/null || true
            configured "herald config merged (theme.name set; account data left untouched)"
        else
            rm -f "$_herald_tmp"
            warn "Could not merge the herald theme name — left unchanged: $HERALD_CONFIG"
        fi
        unset _herald_mode _herald_tmp
    else
        warn "Could not merge the herald theme name because yq is unavailable"
    fi
fi
# `herald --demo` previews the TUI without account or AI configuration.


# ---- direnv config ----
DIRENV_CONFIG_DIR="$HOME/.config/direnv"
DIRENV_CONFIG="$DIRENV_CONFIG_DIR/direnv.toml"
    info "Creating direnv configuration..."
    write_managed "$DIRENV_CONFIG" "#" <<'DIRENV_CONF'
# direnv configuration

# Hide the direnv loading/unloading messages
[global]
hide_env_diff = true
warn_timeout = "10s"
load_dotenv = true

# Whitelist trusted directories
[whitelist]
prefix = [
    "~/Code"
]
DIRENV_CONF
    configured "direnv configured (hidden env diff, auto-trust ~/Code)"

# Set RIPGREP_CONFIG_PATH in zshrc (needed for ripgrep to read config)
# This will be in the managed block below

fi  # configs (end of second configs segment)

# ---- Filesystem Structure ----
# Top-level category (NOT nested in configs) so --only filesystem works.
if should_run "filesystem"; then
info "Setting up filesystem structure..."
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create the ~ directory tree, helper scripts, wallpaper asset, and Brewfile"
else

# ADD-friendly layout: few top-level roots, shallow nesting, no overlapping
# categories, and an ~/Inbox dump zone so nothing needs to be filed in the moment.
# ~/Code is kept as-is because aliases, per-directory git identity, mise/direnv
# trust, and the MCP filesystem scope all depend on it.
DIRS=(
    # -- Inbox (dump zone — drop anything here, sort later or never) -----------
    "$HOME/Inbox"

    # -- Development ----------------------------------------------------------
    "$HOME/Code/work"
    "$HOME/Code/work/scratch"
    "$HOME/Code/personal"
    "$HOME/Code/personal/scratch"
    "$HOME/Code/oss"
    "$HOME/Code/learning/courses"
    "$HOME/Code/learning/playground"

    # -- Scripts & Automation -------------------------------------------------
    "$HOME/Scripts/bin"
    "$HOME/Scripts/cron"

    # -- Screenshots ----------------------------------------------------------
    "$HOME/Screenshots"

    # -- Docs (life admin — a few flat, non-overlapping buckets) --------------
    "$HOME/Documents/finance"    # statements, taxes, invoices
    "$HOME/Documents/health"
    "$HOME/Documents/admin"      # legal, insurance, contracts
    "$HOME/Documents/receipts"
    "$HOME/Documents/travel"

    # -- Creative (flat) ------------------------------------------------------
    "$HOME/Creative/writing"
    "$HOME/Creative/design"
    "$HOME/Creative/video"

    # -- Media ----------------------------------------------------------------
    "$HOME/Media/photos"
    "$HOME/Media/videos"
    "$HOME/Media/music"

    # -- Archive (one bucket for old/done stuff) ------------------------------
    "$HOME/Archive"
)
for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
success "Directory structure created (~/Inbox, ~/Code, ~/Scripts, ~/Documents, ~/Creative, ~/Media, ~/Archive)"

# ---- Wallpaper asset ----
# Ship the Dracula-Sakura wallpaper onto every machine, but do NOT auto-apply it.
# Resolve the asset relative to this script so both the repo layout and the release
# zip layout work: scripts/setup-dev-tools-mac.sh -> ../assets/..., zip root -> ./assets/....
WALLPAPER_DEST_DIR="$HOME/Media/photos"
WALLPAPER_DEST="$WALLPAPER_DEST_DIR/dracula-sakura.jpg"
WALLPAPER_SOURCE=""
for _wall_root in "$SETUP_SCRIPT_DIR/.." "$SETUP_SCRIPT_DIR"; do
    if [[ -f "$_wall_root/assets/wallpapers/dracula-sakura.jpg" ]]; then
        WALLPAPER_SOURCE="$_wall_root/assets/wallpapers/dracula-sakura.jpg"
        break
    fi
done
unset _wall_root
if [[ -n "$WALLPAPER_SOURCE" ]]; then
    if [[ -f "$WALLPAPER_DEST" ]] && cmp -s "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"; then
        info "Dracula-Sakura wallpaper already current: $WALLPAPER_DEST"
    else
        mkdir -p "$WALLPAPER_DEST_DIR"
        if cp "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"; then
            info "Installed Dracula-Sakura wallpaper asset: $WALLPAPER_DEST"
        else
            warn "Could not install Dracula-Sakura wallpaper asset to $WALLPAPER_DEST"
        fi
    fi
else
    warn "Wallpaper asset not bundled with this copy of the setup — skipped ~/Media/photos/dracula-sakura.jpg"
fi
unset WALLPAPER_DEST_DIR WALLPAPER_DEST WALLPAPER_SOURCE


# ---- Helper Scripts ----
info "Creating helper scripts in ~/Scripts/bin..."

# -- clean-downloads: delete files older than 30 days --
write_managed_script "$HOME/Scripts/bin/clean-downloads" <<'SCRIPT'
#!/usr/bin/env bash
# Delete files in ~/Downloads older than 30 days
# Usage: clean-downloads [days]
set -euo pipefail

DAYS="${1:-30}"
DIR="$HOME/Downloads"

echo "Finding files in $DIR older than $DAYS days..."
count=$(find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" | wc -l | tr -d ' ')

if [[ "$count" -eq 0 ]]; then
    echo "No files older than $DAYS days found."
    exit 0
fi

echo "Found $count files to delete:"
find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" -exec basename {} \;
echo ""

read -r -p "Delete these $count files? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" -exec trash {} \;
    echo "Moved $count files to Trash."
else
    echo "Cancelled."
fi
SCRIPT

# -- new-project: scaffold a new project --
write_managed_script "$HOME/Scripts/bin/new-project" <<'SCRIPT'
#!/usr/bin/env bash
# Scaffold a new project with an agent-ready repository template.
# Usage: new-project <name> [work|personal|oss|learning] [--justfile] [--license SPDX]
set -euo pipefail

NAME="${1:-}"
CONTEXT="${2:-personal}"
WANT_JUSTFILE="false"
LICENSE_ID="MIT"

# A `while` loop rather than `for arg in "$@"`, because --license consumes a
# value and a for-loop cannot advance past it (#474).
shift_count=0
if [[ $# -gt 0 ]]; then shift_count=1; fi
if [[ $# -gt 1 && "$2" != --* ]]; then shift_count=2; fi
shift "$shift_count" || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --justfile) WANT_JUSTFILE="true"; shift ;;
        --license)
            if [[ -z "${2:-}" || "$2" == --* ]]; then
                echo "--license requires an SPDX identifier, e.g. --license ISC"
                exit 1
            fi
            LICENSE_ID="$2"; shift 2 ;;
        --license=*) LICENSE_ID="${1#*=}"; shift ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: new-project <name> [work|personal|oss|learning] [--justfile] [--license SPDX]"
            exit 1
            ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "Usage: new-project <name> [work|personal|oss|learning] [--justfile] [--license SPDX]"
    echo "  Contexts: work, personal, oss, learning"
    echo "  Options:  --justfile        add a minimal starter Justfile"
    echo "            --license SPDX    license for an oss project (default MIT)"
    exit 1
fi

case "$CONTEXT" in
    work)     BASE="$HOME/Code/work" ;;
    personal) BASE="$HOME/Code/personal" ;;
    oss)      BASE="$HOME/Code/oss" ;;
    learning) BASE="$HOME/Code/learning/playground" ;;
    *)
        echo "Unknown context: $CONTEXT (use work, personal, oss, or learning)"
        exit 1
        ;;
esac

# Validate the license BEFORE anything is created, so a typo fails on an empty
# machine rather than leaving a half-scaffolded directory behind. Unbundled
# identifiers fail loudly instead of writing a stub: a placeholder LICENSE is
# worse than none, because it looks like a license to a scanner and grants
# nothing (#474).
if [[ "$CONTEXT" == "oss" ]]; then
    case "$LICENSE_ID" in
        MIT|ISC|BSD-2-Clause|BSD-3-Clause|Unlicense) ;;
        *)
            echo "No bundled LICENSE text for: $LICENSE_ID"
            echo "  Bundled: MIT (default), ISC, BSD-2-Clause, BSD-3-Clause, Unlicense"
            echo "  For anything else, scaffold without --license and add the text from"
            echo "  https://spdx.org/licenses/${LICENSE_ID}.html yourself."
            exit 1
            ;;
    esac
elif [[ "$LICENSE_ID" != "MIT" ]]; then
    echo "Note: --license applies to oss projects only; ignoring it for '$CONTEXT'."
fi

PROJECT_DIR="$BASE/$NAME"

if [[ -d "$PROJECT_DIR" ]]; then
    echo "Project already exists: $PROJECT_DIR"
    exit 1
fi

echo "Creating project: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

git init -b main

# Shell and bats get 4 spaces, not the 2-space default (#494). The file carved
# out Makefile, Go and Python but left shell on the default. The explicit shell
# rule prevents editors and formatters from applying the generic 2-space
# default to a repository whose large setup script uses 4-space shell style.
cat > .editorconfig <<'EDITORCONFIG'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab

[*.go]
indent_style = tab

[*.py]
indent_size = 4

[*.{sh,bash,bats}]
indent_size = 4
EDITORCONFIG

cat > .gitattributes <<'GITATTRIBUTES'
* text=auto eol=lf
*.bat text eol=crlf
*.cmd text eol=crlf
GITATTRIBUTES

# Environment, editor, OS, log and secret rules apply to every project. The
# per-ecosystem blocks below them are grouped and labelled so a project that is
# not Node (or not Python, or not Rust) can delete the block it does not need
# rather than hunt through a flat list (#472).
cat > .gitignore <<'GITIGNORE'
# Environment and secrets
# .env* is deliberately broad. The negation keeps the one env file projects
# usually DO commit, so a checked-in template is not silently invisible.
.env*
!.env.example
*.pem
*.key

# Build output
dist/
build/
out/
coverage/

# Editors
.vscode/settings.json
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log


# --- Node (delete if this is not a Node project) ---
node_modules/
.pnpm-store/
.next/
.nyc_output/
.vercel/
.supabase/
npm-debug.log*
pnpm-debug.log*
yarn-debug.log*
yarn-error.log*

# --- Python (delete if this is not a Python project) ---
__pycache__/
*.py[cod]
.venv/
.pytest_cache/
.ruff_cache/
.mypy_cache/

# --- Go / Rust (delete if unused) ---
target/
vendor/
GITIGNORE

# The scaffold is language neutral by design (#458 deliberately writes no
# package.json), so the command surfaces must not assert a runtime either. With
# --justfile there is a real command spine to point at; without it, an honest
# placeholder beats a pnpm line that is wrong for every non-Node project (#472).
if [[ "$WANT_JUSTFILE" == "true" ]]; then
    README_COMMANDS=$(cat <<'RMCMD'
# See every available command
just

# Start development
just dev

# Run tests
just test

# Build
just build
RMCMD
)
else
    README_COMMANDS=$(cat <<'RMCMD'
# TODO: replace with this project's real commands.
#   install:
#   dev:
#   test:
#   build:
RMCMD
)
fi

cat > README.md <<README
# $NAME

A new project scaffolded with public agent instructions and a focused
repository structure.

## Getting started

\`\`\`bash
$README_COMMANDS
\`\`\`

## Project structure

- \`AGENTS.md\` — public instructions for coding agents
- \`CONVENTIONS.md\` — normative code, test, and documentation rules
- \`CHANGELOG.md\` — user facing release history

## Planning workflow

Keep project plans with the related GitHub issue or in the relevant project
documentation.
README

cat > CHANGELOG.md <<'CHANGELOG'
# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Groups, in this order, using only the ones that apply: `Added`, `Changed`, `Deprecated`,
`Removed`, `Fixed`, `Security`.

> Entries cite the **issue** number, for example `(#12)`. A GitHub release page lists pull
> requests instead, so the same change carries a different number in the two views. That is
> expected, not a mistake.

At the first release, add link reference definitions at the bottom of this file so every
version heading resolves to a diff, then add one row per release. A bare `#12` inside a
Markdown file does not become a link on GitHub, so the version heading is what makes this
file navigable:

```text
[Unreleased]: https://github.com/OWNER/REPO/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OWNER/REPO/releases/tag/v0.1.0
```

## [Unreleased]

### Added
- Initial project scaffold
CHANGELOG

if [[ "$WANT_JUSTFILE" == "true" ]]; then
cat > Justfile <<'JUSTFILE'
set shell := ["bash", "-cu"]

default:
    @just --list

dev:
    @echo "Define the development command for this project"

test:
    @echo "Define the test command for this project"

build:
    @echo "Define the build command for this project"

lint:
    @echo "Define the lint command for this project"

preflight:
    @just test
    @just lint
    @just build
JUSTFILE
fi

cat > CONVENTIONS.md <<'CONVENTIONS'
# CONVENTIONS.md

This file defines how the code and project artifacts should look and behave.

## Core rules

- Keep `AGENTS.md` procedural and public. Keep `CONVENTIONS.md` normative.
- Treat warnings as errors. Investigate and resolve them.
- Prefer the smallest correct change over broad rewrites.
- Update user facing docs when behavior changes.

## Decisions

- Record architecture decisions in the related GitHub issue.
- Record standing rules in `CONVENTIONS.md`.
- Update the rule and the issue when a decision changes.

## Line endings and text files

- All text files MUST use LF line endings.
- `.editorconfig` and `.gitattributes` enforce LF. Do not override them.
- Keep files UTF-8 with a final newline.

## Changelog

- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows Semantic Versioning.
- Groups are `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security`. Use only the ones that apply.
- Entries cite the issue number, not the pull request number.
- Version headings MUST resolve to a diff through link reference definitions at the bottom of the file. Add one row per release.

## Git and review

- Use trunk based development with short lived branches off `main`.
- Open an issue before writing code, unless the change is truly trivial and local.
- Use conventional commits.
- Use conventional pull request titles.
- Do not commit directly to `main`.
- Keep pull requests focused and easy to review.
- Preferred sequence: issue, branch, code, PR.

## Writing conventions for issues, commits, and PRs

- Use straightforward, low narrative writing for issues. State the problem, the fix, and the verification plainly.
- Use conventional commit types and keep commit titles concise.
- Use conventional pull request titles and a compact body with summary, changes, and test plan.
- Write in the first person when prose is needed.
- Favor a polished Dracula Sakura tone when there is room for voice: refined, calm, clear, and lightly feminine without becoming vague or overly cute.
- Do not pad issues, commits, or pull requests with unnecessary backstory, hype, or filler.
- Clarity and accuracy win over style every time.

## Tests and quality

- Run existing lint, test, and build commands before merging.
- Add tests when behavior changes or defects are fixed.
- Keep tests close to the code they verify when the stack supports it.

## Agent workflow

- Read `AGENTS.md` before making structural changes.
CONVENTIONS

cat > AGENTS.md <<'AGENTSMD'
# AGENTS.md

Public instructions for coding agents working in this repository.

Read `CONVENTIONS.md` first for normative rules. Read `README.md` for human oriented setup.

## Project
<!-- Replace with a one sentence project description. -->

## Commands
AGENTSMD

# Same reasoning as the README block above: the table must not claim a runtime
# the scaffold deliberately did not choose (#472). Split rather than switching
# AGENTSMD to an unquoted heredoc, which would mean escaping every backtick in
# a 50-line document to interpolate six cells.
if [[ "$WANT_JUSTFILE" == "true" ]]; then
cat >> AGENTS.md <<'AGENTSCMD'
| Action | Command |
|---|---|
| Dev | `just dev` |
| Test | `just test` |
| Build | `just build` |
| Lint | `just lint` |
| Preflight | `just preflight` |
AGENTSCMD
else
cat >> AGENTS.md <<'AGENTSCMD'
<!-- Replace the right-hand column with this project's real commands. -->
| Action | Command |
|---|---|
| Install | `TODO` |
| Dev | `TODO` |
| Test | `TODO` |
| Build | `TODO` |
| Lint | `TODO` |
| Preflight | `TODO` |
AGENTSCMD
fi

cat >> AGENTS.md <<'AGENTSMD'

## Architecture
<!-- Replace with a short module and boundary summary. -->

## Planning and decisions
- Track planning, verification, and architecture decisions in GitHub issues.
- Keep standing rules in `CONVENTIONS.md`.
- Keep project plans with the related issue or in the relevant project documentation.

## Project workflow
- Keep `AGENTS.md` stable. Do not use it for changing project status.

## Git workflow
- Use trunk based development. Keep branches short lived and merge back to `main` quickly.
- Create an issue before writing code. Then branch, implement, and open a pull request.
- Use conventional commits and conventional pull request titles.
- Keep issues straightforward and to the point. Skip unnecessary narrative.
- Write commits, pull requests, and issues in the first person when prose is needed.
- When style has room to breathe, keep it calm, polished, clear, and lightly feminine.
- Do not skip straight to code and "document later" for non trivial work.

## Changelog
- Update `CHANGELOG.md` under `## [Unreleased]` as part of the change, not as a later pass.
- Cite the issue number, for example `(#12)`. See `CONVENTIONS.md` for the group list and the format rules.
- At release, retitle `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and add the matching link reference definition at the bottom of the file. Skipping that step leaves every version heading pointing at nothing.

## Hard stops
- Do not commit secrets.
- Do not bypass failing checks without explaining why.
- Do not rewrite large areas when a smaller change will do.
- Do not write code before the issue exists for non trivial work.
AGENTSMD



mkdir -p .github
cat > .github/PULL_REQUEST_TEMPLATE.md <<'PRTEMPLATE'
## Summary
<!-- What does this PR do and why? -->

## Changes
-

## Test Plan
- [ ]

Closes #
PRTEMPLATE

# The scaffold mandates issue-first in both agent docs and backed only the second
# half of that sequence with a template (#473). These mirror the PR template's
# shape and the writing rules in the scaffolded CONVENTIONS.md: state the problem,
# the fix, and the verification, without narrative padding.
#
# `labels:` names only GitHub's DEFAULT label set. A fresh repo has `bug` and
# `enhancement` but NOT `feature`, so referencing `feature` here would tag every
# new issue with a label that does not exist in the repo it was just created in.
mkdir -p .github/ISSUE_TEMPLATE
cat > .github/ISSUE_TEMPLATE/bug_report.md <<'BUGTEMPLATE'
---
name: Bug report
about: Something behaves differently than it should
labels: bug
---

## Problem
<!-- What happens, and what should happen instead. -->

## Reproduction
<!-- The smallest steps or input that show it. -->

## Proposed fix
<!-- Optional. Leave blank if the cause is not known yet. -->

## Verification
<!-- How we will know it is fixed. -->
BUGTEMPLATE

cat > .github/ISSUE_TEMPLATE/feature_request.md <<'FEATTEMPLATE'
---
name: Feature request
about: A new capability, or an improvement to an existing one
labels: enhancement
---

## Summary
<!-- One or two sentences on what should exist. -->

## Problem
<!-- What is hard or impossible today. -->

## Proposed fix
<!-- What to build. Note anything deliberately out of scope. -->

## Verification
<!-- How we will know it is done. -->
FEATTEMPLATE

# Blank issues stay enabled on purpose: a one-line issue should not have to be
# filed through a form.
cat > .github/ISSUE_TEMPLATE/config.yml <<'ISSUECONFIG'
blank_issues_enabled: true
ISSUECONFIG

# -- oss only ---------------------------------------------------------------
# The project type was captured at the call site and then used for nothing but
# picking a parent directory, so a repo explicitly declared open source shipped
# with no LICENSE — which leaves it under exclusive copyright by default, the
# opposite of the intent (#474). work/personal/learning are unchanged.
if [[ "$CONTEXT" == "oss" ]]; then
    LICENSE_YEAR="$(date +%Y)"
    LICENSE_HOLDER="$(git config user.name 2>/dev/null || true)"
    [[ -z "$LICENSE_HOLDER" ]] && LICENSE_HOLDER="the authors"

    case "$LICENSE_ID" in
    MIT)
cat > LICENSE <<LICENSETEXT
MIT License

Copyright (c) $LICENSE_YEAR $LICENSE_HOLDER

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSETEXT
        ;;
    ISC)
cat > LICENSE <<LICENSETEXT
ISC License

Copyright (c) $LICENSE_YEAR $LICENSE_HOLDER

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
LICENSETEXT
        ;;
    BSD-2-Clause|BSD-3-Clause)
cat > LICENSE <<LICENSETEXT
BSD $([[ "$LICENSE_ID" == "BSD-2-Clause" ]] && echo 2-Clause || echo 3-Clause) License

Copyright (c) $LICENSE_YEAR $LICENSE_HOLDER
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
LICENSETEXT
        if [[ "$LICENSE_ID" == "BSD-3-Clause" ]]; then
cat >> LICENSE <<'LICENSETEXT'

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.
LICENSETEXT
        fi
cat >> LICENSE <<'LICENSETEXT'

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
LICENSETEXT
        ;;
    Unlicense)
cat > LICENSE <<'LICENSETEXT'
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
software, either in source code form or as a compiled binary, for any purpose,
commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors of this
software dedicate any and all copyright interest in the software to the public
domain. We make this dedication for the benefit of the public at large and to
the detriment of our heirs and successors. We intend this dedication to be an
overt act of relinquishment in perpetuity of all present and future rights to
this software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
LICENSETEXT
        ;;
    esac

    # Points at AGENTS.md and CONVENTIONS.md rather than restating them, the same
    # way the rest of this scaffold's docs cross-reference instead of duplicating.
cat > CONTRIBUTING.md <<'CONTRIBUTING'
# Contributing

Thanks for taking the time to contribute.

## Before you start

Two files define how this repository works, and this document does not repeat them:

- **[`AGENTS.md`](AGENTS.md)** — procedural rules: workflow, branching, and how changes get made.
- **[`CONVENTIONS.md`](CONVENTIONS.md)** — normative rules: code shape, tests, line endings, changelog format.

Read both before opening a pull request. They apply to human contributors and coding agents alike.

## The short version

1. Open an issue first, unless the change is trivial and local.
2. Branch from `main` and keep the branch short lived.
3. Use conventional commits and a conventional pull request title.
4. Update `CHANGELOG.md` under `## [Unreleased]` as part of the change, not afterwards.
5. Open a pull request with a summary, the changes, and a test plan.

## Reporting bugs and requesting features

Use the templates in `.github/ISSUE_TEMPLATE/`. State the problem, the proposed fix, and how we will know it worked.

## Security

Do not open a public issue for a security problem. See [`SECURITY.md`](SECURITY.md).
CONTRIBUTING

    # Deliberately routes through GitHub's private advisory flow rather than an
    # email address, because the scaffold has no way to know one and a wrong
    # contact is worse than a working default.
cat > SECURITY.md <<'SECURITY'
# Security Policy

## Reporting a vulnerability

Report security issues **privately**, not as a public issue.

Use GitHub's private vulnerability reporting: open the **Security** tab on this
repository and choose **Report a vulnerability**. That creates an advisory
visible only to the maintainers.

If private reporting is not enabled, open a normal issue asking for a private
channel, without including any detail of the vulnerability itself.

## What to expect

- Acknowledgement that the report arrived.
- An assessment of whether it reproduces and is in scope.
- A fix or a documented decision, with credit in the release notes if you want it.

## Scope

The default branch and the most recent release.
SECURITY

cat > CODE_OF_CONDUCT.md <<'COC'
# Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/), version 2.1.

In short: be respectful, assume good faith, and keep discussion on the work.
Harassment, personal attacks, and demeaning comments are not welcome here.

## Enforcement

Report unacceptable behaviour to the maintainers.

<!-- TODO: add a contact address or a private reporting channel above. A code of
     conduct with no working enforcement contact cannot actually be enforced. -->
COC
fi

git add -A
git commit -m "feat: initial project scaffold"

echo ""
echo "Project created at: $PROJECT_DIR"
echo "  cd $PROJECT_DIR"
if [[ "$WANT_JUSTFILE" == "true" ]]; then
    echo "  starter Justfile: created"
fi
SCRIPT

# -- clone-work: clone a work repo into the right directory --
write_managed_script "$HOME/Scripts/bin/clone-work" <<'SCRIPT'
#!/usr/bin/env bash
# Clone a work repo into ~/Code/work/<org>/<repo>
# Usage: clone-work <github-url-or-org/repo>
set -euo pipefail

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: clone-work <github-url-or-org/repo>"
    echo "  Examples:"
    echo "    clone-work https://github.com/myorg/myrepo"
    echo "    clone-work myorg/myrepo"
    echo "    clone-work git@github.com:myorg/myrepo.git"
    exit 1
fi

# Parse org and repo from various URL formats
if [[ "$INPUT" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    ORG="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
elif [[ "$INPUT" =~ ^([^/]+)/([^/]+)$ ]]; then
    ORG="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
else
    echo "Could not parse org/repo from: $INPUT"
    exit 1
fi

TARGET="$HOME/Code/work/$ORG"
mkdir -p "$TARGET"

echo "Cloning $ORG/$REPO into $TARGET/$REPO..."

if [[ -d "$TARGET/$REPO" ]]; then
    echo "Already exists: $TARGET/$REPO"
    exit 1
fi

gh repo clone "$ORG/$REPO" "$TARGET/$REPO"

# Enable background maintenance (prefetch, commit-graph, gc)
git -C "$TARGET/$REPO" maintenance start 2>/dev/null || true

echo ""
echo "Cloned to: $TARGET/$REPO"
echo "  cd $TARGET/$REPO"
SCRIPT

# -- clone-personal: clone a personal repo --
write_managed_script "$HOME/Scripts/bin/clone-personal" <<'SCRIPT'
#!/usr/bin/env bash
# Clone a personal repo into ~/Code/personal/<repo>
# Usage: clone-personal <repo-name-or-url>
set -euo pipefail

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
    echo "Usage: clone-personal <repo-name-or-url>"
    exit 1
fi

# Parse repo name
if [[ "$INPUT" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO="${BASH_REMATCH[2]}"
    CLONE_URL="$INPUT"
elif [[ "$INPUT" =~ / ]]; then
    REPO="${INPUT##*/}"
    CLONE_URL="$INPUT"
else
    REPO="$INPUT"
    CLONE_URL=""
fi

TARGET="$HOME/Code/personal/$REPO"

if [[ -d "$TARGET" ]]; then
    echo "Already exists: $TARGET"
    exit 1
fi

echo "Cloning $REPO into $TARGET..."
if [[ -n "$CLONE_URL" ]]; then
    gh repo clone "$CLONE_URL" "$TARGET"
else
    gh repo clone "$REPO" "$TARGET"
fi

# Enable background maintenance (prefetch, commit-graph, gc)
git -C "$TARGET" maintenance start 2>/dev/null || true

echo ""
echo "Cloned to: $TARGET"
echo "  cd $TARGET"
SCRIPT

# -- backup-dotfiles: push dotfiles to git via chezmoi --
write_managed_script "$HOME/Scripts/bin/backup-dotfiles" <<'SCRIPT'
#!/usr/bin/env bash
# Backup dotfiles using chezmoi
# Usage: backup-dotfiles
set -euo pipefail

if ! command -v chezmoi &>/dev/null; then
    echo "chezmoi not installed. Run: brew install chezmoi"
    exit 1
fi

# Backup crontab
echo "Backing up crontab..."
crontab -l > "$(chezmoi source-path)/crontab.backup" 2>/dev/null || echo "  (no crontab)"

# Export Brewfile
echo "Exporting Brewfile..."
brew bundle dump --file="$(chezmoi source-path)/Brewfile" --force --describe 2>/dev/null || true

# Re-add tracked files to pick up changes
echo "Updating tracked dotfiles..."
chezmoi re-add 2>/dev/null || true

# Check if there are changes
cd "$(chezmoi source-path)"
if git diff --quiet && git diff --cached --quiet; then
    echo "No dotfile changes to backup."
    exit 0
fi

echo "Changes detected:"
git status --short

echo ""
read -r -p "Commit and push? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git add -A
    git commit -m "Update dotfiles — $(date +%Y-%m-%d)"
    git push
    echo "Dotfiles backed up."
else
    echo "Cancelled."
fi
SCRIPT

# -- project-stats: show stats about all projects --
write_managed_script "$HOME/Scripts/bin/project-stats" <<'SCRIPT'
#!/usr/bin/env bash
# Show overview of all projects in ~/Code
# Usage: project-stats
set -euo pipefail

CODE_DIR="$HOME/Code"

echo "=== Project Stats ==="
echo ""

for context in work personal oss learning; do
    dir="$CODE_DIR/$context"
    if [[ -d "$dir" ]]; then
        count=$(find "$dir" -maxdepth 2 -name ".git" -type d 2>/dev/null | wc -l | tr -d ' ')
        echo "  $context: $count repos"
    fi
done

echo ""
echo "=== Disk Usage ==="
du -sh "$CODE_DIR"/* 2>/dev/null | sort -rh

echo ""
echo "=== Recently Modified (last 7 days) ==="
find "$CODE_DIR" -maxdepth 3 -name ".git" -type d -mtime -7 2>/dev/null | while read gitdir; do
    repo=$(dirname "$gitdir")
    branch=$(git -C "$repo" branch --show-current 2>/dev/null)
    echo "  ${repo#$CODE_DIR/} ($branch)"
done
SCRIPT

# -- health-check: quick system overview --
write_managed_script "$HOME/Scripts/bin/health-check" <<'SCRIPT'
#!/usr/bin/env bash
# Quick system health overview
# Usage: health-check
set -euo pipefail

echo "=== System Health Check ==="
echo ""

# Disk space
echo "-- Disk Space --"
df -h / | tail -1 | awk '{printf "  Root: %s used of %s (%s free)\n", $3, $2, $4}'

# Memory
echo ""
echo "-- Memory --"
vm_stat 2>/dev/null | awk '/Pages (free|active|inactive|speculative|wired)/ {
    gsub(/\./, "", $NF); pages[$2] = $NF
} END {
    free = (pages["free:"] + pages["inactive:"] + pages["speculative:"]) * 4096 / 1073741824
    used = (pages["active:"] + pages["wired"]) * 4096 / 1073741824
    printf "  Used: %.1fGB  Free: %.1fGB\n", used, free
}'

# Battery (macOS)
if command -v pmset &>/dev/null; then
    echo ""
    echo "-- Battery --"
    pmset -g batt 2>/dev/null | grep -o "[0-9]*%" | head -1 | xargs -I{} echo "  Charge: {}"
    BATTERY_HEALTH=$(system_profiler SPPowerDataType 2>/dev/null | grep "Maximum Capacity" | awk '{print $NF}')
    [[ -n "$BATTERY_HEALTH" ]] && echo "  Health: $BATTERY_HEALTH"
fi

# Brew outdated
if command -v brew &>/dev/null; then
    echo ""
    echo "-- Brew --"
    OUTDATED=$(brew outdated 2>/dev/null | wc -l | tr -d ' ')
    echo "  Outdated packages: $OUTDATED"
fi

# Docker disk
if command -v docker &>/dev/null && docker info &>/dev/null; then
    echo ""
    echo "-- Docker --"
    docker system df 2>/dev/null | head -4 | sed 's/^/  /'
fi

# Largest node_modules
echo ""
echo "-- Largest node_modules (top 5) --"
find "$HOME/Code" -maxdepth 4 -name "node_modules" -type d -prune 2>/dev/null | while read -r nm; do
    du -sh "$nm" 2>/dev/null
done | sort -rh | head -5 | sed 's/^/  /'

# Uptime
echo ""
echo "-- Uptime --"
uptime | sed 's/^/  /'
SCRIPT

# -- setup-ssh: generate SSH key and add to GitHub --
write_managed_script "$HOME/Scripts/bin/setup-ssh" <<'SCRIPT'
#!/usr/bin/env bash
# Generate SSH key and optionally add to GitHub
# Usage: setup-ssh [email]
set -euo pipefail

EMAIL="${1:-}"

if [[ -z "$EMAIL" ]]; then
    echo "Usage: setup-ssh <email>"
    echo "  Generates an Ed25519 SSH key and optionally adds it to GitHub."
    exit 1
fi

KEY_FILE="$HOME/.ssh/id_ed25519"

if [[ -f "$KEY_FILE" ]]; then
    echo "SSH key already exists at $KEY_FILE"
    echo "Public key:"
    cat "${KEY_FILE}.pub"
else
    echo "Generating SSH key for $EMAIL..."
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE"
    echo ""
    echo "SSH key generated."
    echo "Public key:"
    cat "${KEY_FILE}.pub"
fi

echo ""
read -p "Add this key to GitHub? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    if command -v gh &>/dev/null; then
        TITLE="$(hostname) $(date +%Y-%m-%d)"
        gh ssh-key add "${KEY_FILE}.pub" --title "$TITLE"
        echo "SSH key added to GitHub as '$TITLE'"
    else
        echo "GitHub CLI (gh) not installed. Add manually:"
        echo "  https://github.com/settings/ssh/new"
    fi
fi
SCRIPT

# -- export-brewfile: export Brewfile snapshot --
write_managed_script "$HOME/Scripts/bin/export-brewfile" <<'SCRIPT'
#!/usr/bin/env bash
# Export a Brewfile snapshot with descriptions
# Usage: export-brewfile
set -euo pipefail

BREWFILE_DIR="$HOME/.config/brewfile"
mkdir -p "$BREWFILE_DIR"
BREWFILE="$BREWFILE_DIR/Brewfile"

echo "Exporting Brewfile to $BREWFILE..."
brew bundle dump --file="$BREWFILE" --force --describe 2>/dev/null
echo "Done. $(wc -l < "$BREWFILE" | tr -d ' ') packages recorded."
echo ""
echo "Restore on a new machine:"
echo "  brew bundle install --file=$BREWFILE"
SCRIPT

# Remove the retired repository helper only when the generator still owns it.
remove_superseded_managed "$HOME/Scripts/bin/git-lfs-enable-repo" \
    "Git LFS was removed from the setup" "(#542)"

# write_managed_script sets each script executable.
success "Helper scripts written (clean-downloads, new-project, clone-work, clone-personal, backup-dotfiles, project-stats, health-check, setup-ssh, export-brewfile — merged, edits outside the markers are kept)"

# ---- Per-directory Git Config (work vs personal identity) ----
info "Setting up per-directory git config..."

GITCONFIG_WORK="$HOME/.gitconfig-work"
GITCONFIG_PERSONAL="$HOME/.gitconfig-personal"

if [[ -f "$GITCONFIG_WORK" ]]; then
    warn "$HOME/.gitconfig-work already exists"
else
    cat > "$GITCONFIG_WORK" <<'GIT_WORK'
# Git config for work projects (~/Code/work/)
# Fill in your work email:
[user]
    # name = Your Name
    # email = you@company.com
    # signingkey = YOUR_GPG_KEY_ID
# [commit]
#     gpgsign = true
GIT_WORK
    success "$HOME/.gitconfig-work created (fill in your work email)"
fi

if [[ -f "$GITCONFIG_PERSONAL" ]]; then
    warn "$HOME/.gitconfig-personal already exists"
else
    cat > "$GITCONFIG_PERSONAL" <<'GIT_PERSONAL'
# Git config for personal projects (~/Code/personal/)
# Fill in your personal email:
[user]
    # name = Your Name
    # email = you@personal.com
    # signingkey = YOUR_GPG_KEY_ID
# [commit]
#     gpgsign = true
GIT_PERSONAL
    success "$HOME/.gitconfig-personal created (fill in your personal email)"
fi

# Register includeIf directives in global gitconfig
if ! git config --global --get "includeIf.gitdir:~/Code/work/.path" &>/dev/null; then
    git_global "includeIf.gitdir:~/Code/work/.path" "$GITCONFIG_WORK"
    success "git includeIf registered for ~/Code/work/ -> ~/.gitconfig-work"
else
    warn "git includeIf for ~/Code/work/ already set"
fi

if ! git config --global --get "includeIf.gitdir:~/Code/personal/.path" &>/dev/null; then
    git_global "includeIf.gitdir:~/Code/personal/.path" "$GITCONFIG_PERSONAL"
    success "git includeIf registered for ~/Code/personal/ -> ~/.gitconfig-personal"
else
    warn "git includeIf for ~/Code/personal/ already set"
fi

fi  # end DRY_RUN (filesystem)
fi  # filesystem

if should_run "macos-defaults"; then
if [[ "$DRY_RUN" != "true" ]]; then
# ---- Finder configuration ----
info "Configuring Finder..."

# Show hidden files and folders (dotfiles)
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all file extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show path bar at bottom of Finder
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar at bottom of Finder
defaults write com.apple.finder ShowStatusBar -bool true

# Show full POSIX path in title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Default to list view in all windows
# Four-letter codes: icnv (icon), clmv (column), Flwv (cover flow), Nlsv (list)
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# Search the current folder by default (not entire Mac)
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable warning when changing file extensions
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Keep the warning when emptying trash (your preference)
defaults write com.apple.finder WarnOnEmptyTrash -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# --- Captured from this machine: Finder prefs + view settings ---
# New Finder windows open at Computer
defaults write com.apple.finder NewWindowTarget -string "PfCm"
# Show on desktop: external drives + servers + removable; hide internal drives
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
# Desktop + default (all-window) view settings — captured from "Show View
# Options -> Use as Defaults" (macOS 26). Re-capture if they drift.
defaults write com.apple.finder DesktopViewSettings '{ IconViewSettings = { arrangeBy = name; backgroundColorBlue = 1; backgroundColorGreen = 1; backgroundColorRed = 1; backgroundType = 0; gridOffsetX = 0; gridOffsetY = 0; gridSpacing = 54; iconSize = 64; labelOnBottom = 1; showIconPreview = 1; showItemInfo = 1; textSize = 14; viewOptionsVersion = 1; }; } '
defaults write com.apple.finder StandardViewSettings '{ ExtendedListViewSettingsV2 = { calculateAllSizes = 0; columns = ( { ascending = 1; identifier = name; visible = 1; width = 300; }, { ascending = 0; identifier = ubiquity; visible = 0; width = 35; }, { ascending = 0; identifier = dateModified; visible = 1; width = 181; }, { ascending = 0; identifier = dateCreated; visible = 1; width = 181; }, { ascending = 0; identifier = size; visible = 1; width = 97; }, { ascending = 1; identifier = kind; visible = 1; width = 115; }, { ascending = 1; identifier = label; visible = 0; width = 100; }, { ascending = 1; identifier = version; visible = 0; width = 75; }, { ascending = 1; identifier = comments; visible = 0; width = 300; }, { ascending = 0; identifier = dateLastOpened; visible = 0; width = 200; }, { ascending = 0; identifier = shareOwner; visible = 0; width = 200; }, { ascending = 0; identifier = shareLastEditor; visible = 0; width = 200; }, { ascending = 0; identifier = dateAdded; visible = 0; width = 181; }, { ascending = 0; identifier = invitationStatus; visible = 0; width = 210; } ); iconSize = 16; showIconPreview = 1; sortColumn = name; textSize = 14; useRelativeDates = 1; viewOptionsVersion = 1; }; GalleryViewSettings = { arrangeBy = name; iconSize = 48; showIconPreview = 1; viewOptionsVersion = 1; }; IconViewSettings = { arrangeBy = none; backgroundColorBlue = 1; backgroundColorGreen = 1; backgroundColorRed = 1; backgroundType = 0; gridOffsetX = 0; gridOffsetY = 0; gridSpacing = 54; iconSize = 64; labelOnBottom = 1; showIconPreview = 1; showItemInfo = 0; textSize = 12; viewOptionsVersion = 1; }; ListViewSettings = { calculateAllSizes = 0; columns = { comments = { ascending = 1; index = 7; visible = 0; width = 300; }; dateCreated = { ascending = 0; index = 2; visible = 1; width = 181; }; dateLastOpened = { ascending = 0; index = 8; visible = 0; width = 200; }; dateModified = { ascending = 0; index = 1; visible = 1; width = 181; }; kind = { ascending = 1; index = 4; visible = 1; width = 115; }; label = { ascending = 1; index = 5; visible = 0; width = 100; }; name = { ascending = 1; index = 0; visible = 1; width = 300; }; size = { ascending = 0; index = 3; visible = 1; width = 97; }; version = { ascending = 1; index = 6; visible = 0; width = 75; }; }; iconSize = 16; showIconPreview = 1; sortColumn = name; textSize = 14; useRelativeDates = 1; viewOptionsVersion = 1; }; SettingsType = StandardViewSettings; } '
defaults write com.apple.finder FK_StandardViewSettings '{ ExtendedListViewSettingsV2 = { calculateAllSizes = 0; columns = ( { ascending = 1; identifier = name; visible = 1; width = 300; }, { ascending = 0; identifier = dateModified; visible = 1; width = 181; }, { ascending = 0; identifier = dateCreated; visible = 0; width = 181; }, { ascending = 0; identifier = size; visible = 1; width = 97; }, { ascending = 1; identifier = kind; visible = 1; width = 115; }, { ascending = 1; identifier = label; visible = 0; width = 100; }, { ascending = 1; identifier = version; visible = 0; width = 75; }, { ascending = 1; identifier = comments; visible = 0; width = 300; }, { ascending = 0; identifier = dateLastOpened; visible = 0; width = 200; }, { ascending = 0; identifier = shareOwner; visible = 0; width = 200; }, { ascending = 0; identifier = shareLastEditor; visible = 0; width = 200; } ); iconSize = 16; showIconPreview = 1; sortColumn = name; textSize = 13; useRelativeDates = 1; viewOptionsVersion = 1; }; IconViewSettings = { arrangeBy = none; backgroundColorBlue = 1; backgroundColorGreen = 1; backgroundColorRed = 1; backgroundType = 0; gridOffsetX = 0; gridOffsetY = 0; gridSpacing = 54; iconSize = 64; labelOnBottom = 1; showIconPreview = 1; showItemInfo = 0; textSize = 12; viewOptionsVersion = 1; }; ListViewSettings = { calculateAllSizes = 0; columns = { comments = { ascending = 1; index = 7; visible = 0; width = 300; }; dateCreated = { ascending = 0; index = 2; visible = 0; width = 181; }; dateLastOpened = { ascending = 0; index = 8; visible = 0; width = 200; }; dateModified = { ascending = 0; index = 1; visible = 1; width = 181; }; kind = { ascending = 1; index = 4; visible = 1; width = 115; }; label = { ascending = 1; index = 5; visible = 0; width = 100; }; name = { ascending = 1; index = 0; visible = 1; width = 300; }; size = { ascending = 0; index = 3; visible = 1; width = 97; }; version = { ascending = 1; index = 6; visible = 0; width = 75; }; }; iconSize = 16; showIconPreview = 1; sortColumn = name; textSize = 13; useRelativeDates = 1; viewOptionsVersion = 1; }; SettingsType = "FK_StandardViewSettings"; } '

# Avoid creating .DS_Store files on network and USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Show the ~/Library folder (hidden by default)
chflags nohidden ~/Library 2>/dev/null || true

# Show the /Volumes folder
sudo_run chflags nohidden /Volumes 2>/dev/null || true

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Restart Finder to apply changes
killall Finder 2>/dev/null || true

configured "Finder configured (hidden files visible, list view, path bar, no .DS_Store on network)"

# ---- Finder Sidebar Favorites ----
# Uses LSSharedFileList API via inline-compiled Swift (mysides is deprecated and broken on macOS 13+)
info "Configuring Finder sidebar favorites..."
if [[ "$DRY_RUN" != "true" ]]; then
    SIDEBAR_TOOL="$(mktemp -d)/sidebar-tool"
    SIDEBAR_SRC="${SIDEBAR_TOOL}.swift"

    cat > "$SIDEBAR_SRC" << 'SIDEBAR_SWIFT'
import Foundation
import CoreServices

func getList() -> LSSharedFileList? {
    let listType = kLSSharedFileListFavoriteItems.takeUnretainedValue()
    guard let listRef = LSSharedFileListCreate(nil, listType, nil) else { return nil }
    return listRef.takeRetainedValue()
}

func getSnapshot(_ list: LSSharedFileList) -> [LSSharedFileListItem]? {
    var seed: UInt32 = 0
    guard let ref = LSSharedFileListCopySnapshot(list, &seed) else { return nil }
    return ref.takeRetainedValue() as! [LSSharedFileListItem]
}

func listItems() {
    guard let list = getList(), let snapshot = getSnapshot(list) else { return }
    for item in snapshot {
        if let urlRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil) {
            print((urlRef.takeRetainedValue() as URL).path)
        }
    }
}

func addItem(_ path: String) -> Bool {
    guard let list = getList(), let snapshot = getSnapshot(list) else { return false }
    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    let insertAfter = snapshot.last
    let result: LSSharedFileListItem?
    if let after = insertAfter {
        result = LSSharedFileListInsertItemURL(list, after, nil, nil, url as CFURL, nil, nil)
    } else {
        result = LSSharedFileListInsertItemURL(list, kLSSharedFileListItemBeforeFirst.takeUnretainedValue(), nil, nil, url as CFURL, nil, nil)
    }
    return result != nil
}

func removeItem(_ path: String) -> Bool {
    guard let list = getList(), let snapshot = getSnapshot(list) else { return false }
    let target = NSString(string: path).expandingTildeInPath
    for item in snapshot {
        if let urlRef = LSSharedFileListItemCopyResolvedURL(item, 0, nil) {
            if (urlRef.takeRetainedValue() as URL).path == target { return LSSharedFileListItemRemove(list, item) == noErr }
        }
    }
    return false
}

let args = CommandLine.arguments
guard args.count >= 2 else { exit(1) }
switch args[1] {
case "list": listItems()
case "add": exit(args.count >= 3 && addItem(args[2]) ? 0 : 1)
case "remove": exit(args.count >= 3 && removeItem(args[2]) ? 0 : 1)
default: exit(1)
}
SIDEBAR_SWIFT

    if swiftc -suppress-warnings -o "$SIDEBAR_TOOL" "$SIDEBAR_SRC" >> "$LOG_FILE" 2>&1; then
        # Remove default clutter items (keep AirDrop, Applications)
        "$SIDEBAR_TOOL" remove "$HOME/Movies" 2>/dev/null || true
        "$SIDEBAR_TOOL" remove "$HOME/Music" 2>/dev/null || true
        "$SIDEBAR_TOOL" remove "$HOME/Pictures" 2>/dev/null || true
        # Drop the legacy ~/Docs entry (consolidated into the default ~/Documents) so
        # re-runs on existing machines don't leave a dangling favorite.
        "$SIDEBAR_TOOL" remove "$HOME/Docs" 2>/dev/null || true

        # Add our organized folders to sidebar.
        # Inbox and Downloads (the two dump zones) go first for zero-friction access.
        SIDEBAR_FOLDERS=(
            "$HOME/Inbox"
            "$HOME/Downloads"
            "$HOME/Code"
            "$HOME/Documents"
            "$HOME/Creative"
            "$HOME/Media"
            "$HOME/Archive"
            "$HOME/Screenshots"
            "$HOME/Scripts"
        )

        sidebar_added=0
        for folder in "${SIDEBAR_FOLDERS[@]}"; do
            if [[ -d "$folder" ]]; then
                # Remove first (in case it's already there with a different position)
                "$SIDEBAR_TOOL" remove "$folder" 2>/dev/null || true
                if "$SIDEBAR_TOOL" add "$folder" 2>/dev/null; then
                    ((sidebar_added++))
                fi
            fi
        done

        rm -f "$SIDEBAR_TOOL" "$SIDEBAR_SRC"
        rmdir "$(dirname "$SIDEBAR_TOOL")" 2>/dev/null || true

        if [[ "$sidebar_added" -gt 0 ]]; then
            configured "Finder sidebar updated ($sidebar_added folders added)"
        else
            warn "Finder sidebar — no folders added (directories may not exist yet)"
        fi
    else
        rm -f "$SIDEBAR_SRC"
        warn "Finder sidebar — Swift compilation failed (Xcode CLT may need updating)"
    fi
else
    info "[DRY RUN] Would update Finder sidebar favorites"
fi

# ---- Touch ID for sudo ----
SUDO_TOUCHID="/etc/pam.d/sudo_local"
if [[ -f "$SUDO_TOUCHID" ]] && grep -q "pam_tid" "$SUDO_TOUCHID" 2>/dev/null; then
    warn "Touch ID for sudo already configured"
else
    info "Enabling Touch ID for sudo..."
    # sudo_local is the Apple-recommended way (survives macOS updates)
    if [[ ! -f "$SUDO_TOUCHID" ]]; then
        sudo_run bash -c 'cat > /etc/pam.d/sudo_local <<EOF
# sudo_local: local config for sudo (survives macOS updates)
auth       sufficient     pam_tid.so
EOF'
        configured "Touch ID for sudo enabled (use fingerprint instead of password)"
    else
        sudo_run bash -c 'echo "auth       sufficient     pam_tid.so" >> /etc/pam.d/sudo_local'
        configured "Touch ID for sudo enabled"
    fi
fi

# ---- DNS configuration (speed + privacy) ----
info "Configuring DNS..."
info "Backing up current DNS settings..."
networksetup -getdnsservers Wi-Fi > "$LOG_DIR/dns-backup-wifi.txt" 2>/dev/null || true
networksetup -getdnsservers Ethernet > "$LOG_DIR/dns-backup-ethernet.txt" 2>/dev/null || true
# Get all network services
NETWORK_SERVICES=$(networksetup -listallnetworkservices 2>/dev/null | tail -n +2)
DNS_SET=false
while IFS= read -r service; do
    if [[ "$service" == "Wi-Fi" ]] || [[ "$service" == "Ethernet" ]]; then
        current_dns=$(networksetup -getdnsservers "$service" 2>/dev/null)
        if echo "$current_dns" | grep -q "1.1.1.1"; then
            warn "DNS already configured for $service"
        else
            sudo_run networksetup -setdnsservers "$service" 1.1.1.1 1.0.0.1 9.9.9.9 8.8.8.8
            DNS_SET=true
        fi
    fi
done <<< "$NETWORK_SERVICES"
if [[ "$DNS_SET" == "true" ]]; then
    # Flush DNS cache
    sudo_run dscacheutil -flushcache 2>/dev/null || true
    sudo_run killall -HUP mDNSResponder 2>/dev/null || true
    configured "DNS set to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) + Google (8.8.8.8)"
fi

# ---- Spotlight exclusions (stop indexing dev directories) ----
info "Configuring Spotlight exclusions..."
SPOTLIGHT_EXCLUSIONS=(
    "$HOME/Code"
    "$HOME/.config"
    "$HOME/node_modules"
    "$HOME/.npm"
    "$HOME/.pnpm-store"
    "$HOME/.docker"
    "$HOME/Library/Caches"
    "$HOME/.cache"
)
for dir in "${SPOTLIGHT_EXCLUSIONS[@]}"; do
    if [[ -d "$dir" ]]; then
        # Add .metadata_never_index to prevent Spotlight indexing
        touch "$dir/.metadata_never_index" 2>/dev/null || true
    fi
done
# Note: mdutil -i off on /usr/local or /opt/homebrew fails on macOS Ventura+
# (they live on /System/Volumes/Data which doesn't support per-path indexing control).
# The .metadata_never_index approach above is the reliable method.
configured "Spotlight exclusions set (node_modules, caches via .metadata_never_index)"

# ---- Time Machine exclusions ----
# tmutil exclusions ONLY affect Time Machine. Skip entirely when TM has no destination
# configured — the calls would be inert no-ops, and this setup's real backups (borg/
# borgmatic, rclone, rsync) carry their own excludes (see the borgmatic config's
# exclude_patterns). If you add a TM destination later, re-run to apply these.
if tmutil destinationinfo 2>/dev/null | grep -q 'No destinations configured'; then
    info "Time Machine not configured — skipping TM exclusions (borg/rclone/rsync carry their own excludes)"
else
    info "Configuring Time Machine exclusions..."
    TM_EXCLUSIONS=(
        "$HOME/node_modules"
        "$HOME/.npm"
        "$HOME/.pnpm-store"
        "$HOME/.docker"
        "$HOME/Library/Caches"
        "$HOME/.cache"
        "$HOME/.Trash"
        "$HOME/Downloads"
    )
    for dir in "${TM_EXCLUSIONS[@]}"; do
        if [[ -d "$dir" ]]; then
            # Use sticky exclusion (-p) so it persists even if the directory is recreated
            # tmutil fails with "Invalid argument" on some paths (e.g., non-existent or special volumes)
            tmutil addexclusion -p "$dir" >> "$LOG_FILE" 2>&1 || tmutil addexclusion "$dir" >> "$LOG_FILE" 2>&1 || true
        fi
    done
    configured "Time Machine exclusions set (node_modules, Docker, caches, Downloads)"
fi

# ---- Disable Siri ----
if defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null | grep -q "1"; then
    info "Disabling Siri..."
    defaults write com.apple.assistant.support "Assistant Enabled" -bool false
    defaults write com.apple.Siri StatusMenuVisible -bool false
    defaults write com.apple.Siri UserHasDeclinedEnable -bool true
    configured "Siri disabled and removed from menubar"
else
    warn "Siri already disabled"
fi

# ---- Trackpad: Disable three-finger drag ----
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false 2>/dev/null || true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false 2>/dev/null || true
# Also disable via Accessibility (required on newer macOS)
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false 2>/dev/null || true
configured "Three-finger drag disabled"

# ---- Trackpad/mouse: disable natural scrolling and force click ----
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false 2>/dev/null || true
defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false 2>/dev/null || true
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true 2>/dev/null || true
configured "Natural scrolling and force click disabled"

# ---- Trackpad: captured from this machine (tap-to-click off, secondary click, gestures) ----
for _tp in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    defaults write "$_tp" Clicking -bool false 2>/dev/null || true                        # tap to click OFF
    defaults write "$_tp" DragLock -bool false 2>/dev/null || true
    defaults write "$_tp" TrackpadRightClick -bool true 2>/dev/null || true                # two-finger secondary click
    defaults write "$_tp" TrackpadCornerSecondaryClick -int 0 2>/dev/null || true
    defaults write "$_tp" TrackpadThreeFingerTapGesture -int 0 2>/dev/null || true         # look up OFF
    defaults write "$_tp" TrackpadTwoFingerDoubleTapGesture -bool false 2>/dev/null || true # smart zoom OFF
    defaults write "$_tp" Dragging -bool false 2>/dev/null || true
done
unset _tp
# Built-in trackpad only: click firmness (1 = medium) + haptic detents
defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 1 2>/dev/null || true
defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 1 2>/dev/null || true
defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -bool true 2>/dev/null || true
configured "Trackpad preferences captured (tap-to-click off, two-finger secondary click, gestures)"

# ---- Half-brightness step before the display sleeps ----
# `halfdim` only. The `dim` argument is a DEPRECATED ALIAS for `displaysleep`
# (man pmset), so `pmset -c dim 30` here silently overwrote the 120/75 minute
# display sleep set earlier in this same category, and both blocks reported
# success. The machine ended at 30 on both power sources while the run claimed
# 2 hours (#508). Display sleep is owned by the earlier block; this one owns
# halfdim, which is a genuinely separate setting.
sudo_run pmset -a halfdim 1 2>/dev/null || true
configured "Half-brightness step before display sleep enabled"

# ---- Disable startup sound ----
sudo_run nvram StartupMute=%01 2>/dev/null || true
configured "Startup sound disabled"

# ---- Reduce transparency (slight performance boost, easier to read) ----
defaults write com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
configured "Transparency reduced"

# ---- Show Bluetooth in menu bar ----
defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool true 2>/dev/null || true
configured "Bluetooth shown in menu bar"

# ---- Auto-set timezone ----
# Marked applied-once, because the matching -get needs admin to read and would
# therefore cost the password the sudo predicate exists to avoid (#502). Mark
# only on success, so a run that never obtained sudo does not claim it.
if sudo_run systemsetup -setusingnetworktime on 2>/dev/null; then
    priv_mark "systemsetup:networktime"
    configured "Network time enabled (timezone auto-detected)"
else
    warn "Network time not set (no administrator access this run)"
fi
# Use current timezone (don't override user's existing setting)
# sudo systemsetup -settimezone "America/Chicago" 2>/dev/null || true

# ---- Software Update: auto-check but don't auto-install ----
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null || true
defaults write com.apple.commerce AutoUpdate -bool false 2>/dev/null || true
configured "Software Update configured (auto-check, no auto-install)"

# ---- Disable iCloud Desktop & Documents sync (prevents dev files syncing) ----
# This prevents projects in ~/Desktop and ~/Documents from being uploaded to iCloud
defaults write com.apple.bird optimize-storage -bool false 2>/dev/null || true

# ---- macOS defaults for installed apps ----
info "Setting macOS defaults for apps..."

else
    info "[DRY RUN] Would configure Finder, Touch ID, DNS, Spotlight, Time Machine, Siri, and app defaults"
fi  # DRY_RUN

fi  # macos-defaults (Finder, Touch ID, DNS, Spotlight, TM, Siri, app defaults)

# =============================================================================
if should_run "configs"; then
# OMP CONFIGURATION
# =============================================================================
banner "Oh My Pi Configuration"

# ---- Global ~/.ignore shared by ripgrep and compatible tools ----
GLOBAL_IGNORE="$HOME/.ignore"
info "Creating global .ignore..."
write_managed "$GLOBAL_IGNORE" "#" <<'GLOBAL_IGNORE_CONF'
package-lock.json
pnpm-lock.yaml
yarn.lock
*.min.js
*.min.css
*.bundle.js
*.bundle.css
*.map
GLOBAL_IGNORE_CONF
configured "Global .ignore created (lock files and minified bundles hidden)"

# ---- Agent preferences (omp) ----
# Written to ~/.omp/agent/AGENTS.md. The function keeps the generated passage
# isolated from the surrounding shell logic.
emit_agent_preferences() {
    local harness="$1"
    printf '# Global %s Preferences\n' "$harness"
    /bin/cat <<'AGENT_PREFS_BODY'

## Core working style

- Be calm, technically sharp, and warm.
- Prefer clarity over flourish.
- Keep answers concise by default, but expand when the task benefits from detail.
- When making changes, explain what changed, where, and any follow up action.
- When useful, present results as short bullets with clear file paths.

## Dracula Sakura house voice

- Keep the voice polished, composed, and lightly elegant.
- Favor a Dracula Sakura aesthetic when asked for visual styling: dark plum foundations, rose and lilac accents, cyan and mint for information and healthy states.
- Prefer refined, feminine leaning presentation without becoming childish or overly cute.
- Use tasteful softness sparingly. No roleplay, emoji clutter, or chirpy filler.
- Recommend the smallest high leverage next step first.

## Output preferences and anti trope writing

- Do not use em dashes in user facing prose.
- Limit hyphen heavy phrasing. Prefer cleaner sentences and simpler punctuation.
- Avoid AI writing tropes such as filler praise, sales language, inflated certainty, and canned encouragement.
- Do not say things like "great question", "absolutely", "certainly", "game changer", "seamless", or "hope this helps" unless the wording is genuinely necessary.
- Do not narrate intent at length. Act, then summarize results.
- Keep confidence proportional to evidence. State uncertainty plainly when it exists.

## Durable context rules

- Prefer durable preferences over session only ones when the user clearly wants persistence.
- Keep stable instructions in agent context files. Keep volatile project state in project local status, planning, or changelog files instead.
- Before compaction, or when context grows large, persist important project state to the repo's existing status, planning, or memory files when that workflow exists.
- Never write secrets into agent instruction files, memory files, or committed project docs.

## Task tracking

- Mark each TODO item complete immediately after its work finishes.
- Do not defer completed TODO updates until a batch or phase ends.

## Token discipline and recovery

- Use targeted file reads and concise summaries to protect context.
- Prefer staged exploration over broad repeated reads.
- If an approach fails twice, stop, summarize what was tried and what remains unknown, then ask for the smallest missing input.
- Treat warnings as real signals. Investigate and resolve them rather than dismissing them.

## Coding behavior

- Be practical and implementation first.
- Preserve existing project style unless asked to redesign it.
- Avoid unnecessary rewrites.
- Call out risks, edge cases, or irreversible actions before taking them.
- For config or theme work, optimize for readability, coherence, and aesthetics together.

AGENT_PREFS_BODY
}

# ---- Shared writing rules (Simplified Technical English) ----
# One definition feeds the generated OMP context. This keeps the long ruleset
# separate from shell control flow and preserves byte-for-byte output.
emit_writing_rules() {
    /bin/cat <<'WRITING_RULES_BODY'
# Writing Rules (Simplified Technical English)

The 53 rules of ASD-STE100 Issue 9, the aerospace maintenance-documentation standard,
paraphrased with software examples. The official dictionary (about 900 approved words,
about 1200 banned words) is copyrighted by ASD and is not reproduced here. The free
standard is a download at asd-ste100.org. The mechanics work without the dictionary:
one word, one meaning, one part of speech.

## Scope: two tiers

Membership is by document type, not by whether the text lands in a file. Decide the
tier before you decide anything else.

| Tier | Applies to |
|---|---|
| **Strict** | Commit messages. PR titles and bodies. Specs. Technical documentation (READMEs, runbooks, procedures, API guides, architecture notes). Changelogs and release notes. Incident reports. Error messages and CLI output. UI copy. Instructions for AI agents. |
| **Loose** | Issues and their comments. Wikis. Chat replies. |

**Strict** means every rule below, including passage classification, the 20-word and
25-word limits, and Rule 4.2.

**Loose** means the mechanical subset only: no slop words, no filler adverbs, no Latin
abbreviations, no hedging, one term per concept. The sentence-length limits and Rule
4.2 (no contractions) do NOT apply.

Why those three are loose. An issue is the first draft of a thought and often a
dialogue, so a 20-word imperative register makes people write less than the problem
needs. A wiki is collaborative prose that many hands edit, and a rule that every editor
must relearn will not hold. Chat written as a maintenance manual contradicts the house
voice in `style.md`. In all three the rules cost more than the slop they remove.

Note the asymmetry inside one workflow: **an issue body is loose, its PR body is
strict**. The issue argues for a change while the shape of the change is still open.
The PR records what the change is, and that record gets read later by someone who was
not there.

**One carve-out, and it overrides the tier.** A warning about data loss, an
irreversible action, or a destructive flag follows Section 7 wherever it appears,
including inside a loose document. Command or condition first, risk second. The tier
controls register. It does not control safety.

## Before you write

1. Classify each passage as procedural or descriptive. Every length limit and verb
   form below depends on this choice.
2. Fix the vocabulary first. Pick one noun and one verb per concept, then hold them
   for the whole document.
3. Leave code, identifiers, CLI flags, file paths, quoted error messages, and proper
   nouns exactly as they are. These are untouchable.
4. Do not claim STE compliance. No tool can guarantee it. Final approval rests with
   the writer.

| | Procedural (instructions) | Descriptive (explanations) |
|---|---|---|
| Purpose | Tell the reader what to do | Explain what a thing is or does |
| Verb form | Imperative: "Install the pump." | Simple present, past, or future |
| Sentence limit | **20 words** (Rule 5.1) | **25 words** (Rule 6.3) |
| Unit rule | One instruction per sentence (5.2) | One topic per paragraph (6.5), max six sentences (6.6) |

## Section 1: Words (Rules 1.1 to 1.14)

| Rule | Instruction |
|---|---|
| 1.1 | Use only approved words, technical nouns, or technical verbs. |
| 1.2 | Use an approved word only as its listed part of speech. |
| 1.3 | Use an approved word only with its approved meaning. |
| 1.4 | Use only the approved forms of verbs and adjectives. |
| 1.5 | Use domain words as technical nouns ("webhook", "commit", "endpoint"). |
| 1.6 | Use an unapproved word only when it is a technical noun or part of one. |
| 1.7 | Do not use technical nouns as verbs. |
| 1.8 | Use the technical nouns of your project or industry. |
| 1.9 | Pick a short and clear technical noun. |
| 1.10 | Do not use regional, slang, or jargon words as technical nouns. |
| 1.11 | One item, one name. Do not call it "config" here and "settings" there. |
| 1.12 | Use domain verbs as technical verbs ("deploy", "compile", "merge"). |
| 1.13 | Do not use technical verbs as nouns. |
| 1.14 | Use American English spelling. |

Your domain vocabulary is legal: rules 1.5, 1.8, and 1.12 do that work. The rules
agents break most often are 1.7, 1.11, and 1.13.

| Before | After |
|---|---|
| You can webhook the event, then do a deploy. | Send the event to the webhook. Then deploy the service. |

## Section 2: Multi-word nouns (Rules 2.1 to 2.2)

| Rule | Instruction |
|---|---|
| 2.1 | Write multi-word nouns of three words or fewer. |
| 2.2 | When a technical noun needs more than three words, write it in full once. Then give a short form or hyphenate the units. |

Break long noun chains with prepositions (of, on, in, for):

| Before | After |
|---|---|
| the connection pool timeout configuration value | the timeout value for the connection pool |

## Section 3: Verbs (Rules 3.1 to 3.7)

| Rule | Instruction |
|---|---|
| 3.1 | Use only the verb forms the dictionary gives. |
| 3.2 | Use only: infinitive, imperative, simple present, simple past, simple future, past participle as adjective. |
| 3.3 | Use the past participle only as an adjective ("the cached response"). |
| 3.4 | Do not use auxiliary verbs for complex constructions. No present perfect. No "is to be installed". |
| 3.5 | Use an "-ing" form only as a technical noun or inside one ("logging", "the mounting bracket"). Never as a verb. |
| 3.6 | Active voice. In descriptive text, passive is legal only when the agent is unknown. |
| 3.7 | Describe an action with a verb, not a noun. Write "compress the file", not "perform compression of the file". |

| Before | After |
|---|---|
| The migration has completed and the table is being rebuilt. | The migration is complete. The database rebuilds the table. |
| The flag can be set in the config, making restarts unnecessary. | You can set the flag in the config file. Then a restart is not necessary. |
| The temperature must be adjusted. | Adjust the temperature. |

## Section 4: Sentences (Rules 4.1 to 4.5)

| Rule | Instruction |
|---|---|
| 4.1 | Write short and clear sentences. |
| 4.2 | Do not omit words or use contractions. Keep articles. Keep "that". |
| 4.3 | Use a vertical list for complex text. |
| 4.4 | Use connecting words between sentences on related topics ("Then", "As a result"). |
| 4.5 | Put an article (the, a, an) or a demonstrative adjective (this, these) before nouns where applicable. |

Rule 4.2 is the anti-terseness rule. This is short sentences with complete grammar,
not telegraph style:

| Wrong shortening | Correct |
|---|---|
| Ensure file exists before running. | Make sure that the file exists before you run the command. |

## Section 5: Procedural writing (Rules 5.1 to 5.5)

| Rule | Instruction |
|---|---|
| 5.1 | Maximum 20 words per sentence. Warnings and cautions included. |
| 5.2 | One instruction per sentence, unless two actions occur at the same time. |
| 5.3 | Write instructions in the imperative: "Run the migration." |
| 5.4 | Put a required condition before the command, divided by a comma. |
| 5.5 | Notes give information, never instructions. Notes get the 25-word limit. |

| Before | After |
|---|---|
| Grab the API key from the dashboard before configuring the client, which you can do under Settings. | Get the API key from the dashboard, under Settings. Then configure the client with this key. |

## Section 6: Descriptive writing (Rules 6.1 to 6.6)

| Rule | Instruction |
|---|---|
| 6.1 | Give information gradually: one new fact per sentence. |
| 6.2 | Use key words and phrases to give the text a logical structure. |
| 6.3 | Maximum 25 words per sentence. |
| 6.4 | Group related information in paragraphs. |
| 6.5 | One topic per paragraph. |
| 6.6 | Maximum six sentences per paragraph. |

Do not use the imperative in descriptive text. Descriptions explain. Procedures
instruct.

## Section 7: Safety instructions (Rules 7.1 to 7.3)

| Rule | Instruction |
|---|---|
| 7.1 | Use a word that shows the risk level. "WARNING" equals injury. "CAUTION" equals damage. |
| 7.2 | Start with a clear command or condition. |
| 7.3 | Then give the risk or the possible result. |

Do not bury the instruction after the explanation. The pattern transfers to
destructive CLI flags, irreversible migrations, and dangerous API options.

| Before | After |
|---|---|
| Note that data loss can occur if the destructive flag is enabled against production. | CAUTION: Do not use the `--force` flag against production. The flag deletes rows that do not match the source. |

## Section 8: Punctuation and word count (Rules 8.1 to 8.7)

| Rule | Instruction |
|---|---|
| 8.1 | All standard punctuation is legal except the semicolon. Write two sentences instead. |
| 8.2 | Use hyphens to connect words that act as one unit. |
| 8.3 | Parentheses are legal for references, item numbers, abbreviations, and explanations. |
| 8.4 | In a vertical list, the lead-in colon ends a sentence for word count. |
| 8.5 | Text inside parentheses counts as one word. |
| 8.6 | Count as one word each: numbers, numbers with units, abbreviations, identifiers, quoted text, titles, proper nouns. |
| 8.7 | A hyphenated word counts as one word. |

Rule 8.6 matters for software text. A backticked command such as
`sqlpipe run --config sqlpipe.yaml` is quoted text and counts as one word. Long
identifiers do not blow the sentence budget.

## Section 9: Writing practices (Rules 9.1 to 9.4, GR-1 to GR-8)

| Rule | Instruction |
|---|---|
| 9.1 | When a word-for-word replacement does not work, restructure the sentence. |
| 9.2 | Use each approved word correctly: approved meaning, approved part of speech. |
| 9.3 | Do not build phrasal verbs. Write "decrease" not "go down". Write "install" not "set up". |
| 9.4 | Keep one consistent style and terminology through the whole document. |

General recommendations:

| Rule | Instruction |
|---|---|
| GR-1 | Keep the conjunction "that". |
| GR-2 | Be careful with "with". |
| GR-3 | Give pronouns clear referents. |
| GR-4 | Prefer "this plus noun" over a bare "this". |
| GR-5 | Avoid false friends. |
| GR-6 | Avoid Latin abbreviations. Write "for example", "that is". Name the items instead of "etc.". |
| GR-7 | Use inclusive language (primary and replica, not master and slave). |
| GR-8 | Use the possessive apostrophe only when you are sure it is correct. If unsure, do not use it. |

## Approved modals and slop substitutions

Approved modals: `can`, `will`, `must`. Nothing else.

| Instead of | Write |
|---|---|
| should | `must` for a requirement, or delete it for a recommendation |
| may, might, could | can |
| leverage, utilize | use |
| in order to | to |
| prior to | before |
| ensure | make sure that |
| functionality | function, or feature |
| simply, easily, seamlessly, robust | delete, they carry no fact |

## Known part-of-speech rulings

| Word | Ruling |
|---|---|
| test, check, work | Noun only. "Do a test", not "test the pump". "Check that X" becomes "make sure that X". |
| oil | Noun only. For the verb, use "lubricate". |
| help | Verb only. For the noun, use "aid". |
| fall | "To move down by gravity" only. Never "decrease". |
| follow | "To come after" only. Never "obey". Write "obey the instructions". |
| above, below | Physical positions only. For limits, write "more than" or "less than". |

## Mechanical self-check before delivery

Search the draft for each pattern. Every hit outside code blocks and quoted text is a
violation.

| Search for | Violation | Fix |
|---|---|---|
| contractions (`n't`, `'ll`, `'re`, `'ve`, `it's`) | Contraction (4.2) | Expand it. |
| `has been`, `have been`, `had been` | Perfect tense (3.4) | Simple past or simple present. |
| `has` or `have` plus a past participle | Present perfect (3.4) | Simple past. |
| `is being`, `are being`, `was being` | Progressive passive (3.4, 3.5) | Active, simple tense. |
| a comma plus `making`, `allowing`, `enabling`, `ensuring` | "-ing" clause as verb (3.5) | New sentence with a real subject. |
| semicolon `;` | Semicolon (8.1) | Two sentences. |
| `e.g.`, `i.e.`, `etc.` | Latin abbreviation (GR-6) | "for example", "that is", name the items. |
| `simply`, `easily`, `seamlessly`, `robust` | Filler, no fact | Delete. |
| ` if ` or ` when ` mid-sentence | Trailing condition (5.4) | Move the condition to the start. Add a comma. |

Then count. Sentences: 20 words procedural, 25 words descriptive and notes.
Paragraphs: six sentences. Noun chains: three words. Instructions per sentence: one.

Then judge. Is each passage cleanly procedural or descriptive? For each passive
sentence, is the agent truly unknown and the passage descriptive? Does every condition
stand before its command, with a comma? Does one term per concept hold across the
whole document? Does each warning put the command first and the risk second? Are the
articles present, and is "that" present after "make sure"? Are code, identifiers,
quoted errors, and proper nouns unchanged?

## Doc-type modes

| Document | Mode | Adaptation |
|---|---|---|
| Error messages, CLI output | Procedural | State what happened in the simple past. State the cause if known. Give the command that fixes it. Delete "Oops" and "Please ensure". |
| Runbooks, SOPs | Strict procedural | Imperative every step. One instruction per step. Conditions first. Warnings before the step, command first, risk second. |
| Incident reports, postmortems | Descriptive | Simple past only. A timeline in the present perfect hides when things happened. State what is known and write "unknown" for the rest. |
| Commit messages, PR bodies | Imperative subject, descriptive body | Plain past facts in the body. Delete "this PR aims to". |
| Changelogs, release notes | Descriptive | One entry, one change, one sentence where possible. Breaking entries follow the warning pattern, command first. |
| Instructions for AI agents | Procedural | One instruction per sentence, so each rule stays quotable and hard to half-follow. One word, one meaning, so "check", "verify", and "validate" are not read as three operations. Delete the banned modals. A model reads them as optional. |
| UI copy, empty states | Procedural, hard length limits | Buttons and labels are technical names and stay exempt. Body copy follows the rules. |
| Translation and localization prep | Strict | One meaning per word plus complete grammar removes most translation ambiguity. |

## When reporting violations

Give the rule number, the offending text, and a compliant rewrite. Cite only rule
numbers that appear above. End the report with this statement: "No tool can guarantee
ASD-STE100 compliance. Final approval rests with the writer. The official standard is
a free download at asd-ste100.org."

WRITING_RULES_BODY
}

# ---- OMP shared skills ----
AGENTS_SKILLS="$HOME/.agents/skills"

write_generated "$AGENTS_SKILLS/office-layout-check/SKILL.md" <<'SKILL_OFFICE_LAYOUT'
---
name: office-layout-check
description: Verify the visual layout of local Office and OpenDocument files. Use when exact page, slide, or sheet rendering matters.
---

# Office layout check

Use the harness read tool for text extraction and basic inspection. Use this skill only when visual fidelity matters.

## Visual check

1. Create a scratch directory outside the source directory.
2. Convert the source file to PDF with LibreOffice.
3. Rasterize the PDF pages to PNG files.
4. Read every PNG file and inspect the layout.
5. Report clipping, overflow, spacing, font, image, or pagination defects.

```bash
soffice --headless --convert-to pdf --outdir /tmp/office-check "deck.pptx"
pdftoppm -png -r 150 /tmp/office-check/deck.pdf /tmp/office-check/deck-page
```

Keep scratch output outside the source directory. Do not edit or author documents unless the user asks.
SKILL_OFFICE_LAYOUT

write_generated "$AGENTS_SKILLS/d2-diagrams/SKILL.md" <<'SKILL_D2'
---
name: d2-diagrams
description: Create reproducible diagram artifacts with D2. Use when the user requests a rendered diagram file or maintainable diagram source.
---

# D2 diagrams

Use D2 for persisted or rendered diagram artifacts.

1. Write a focused `.d2` source file.
2. Keep the source beside the rendered output.
3. Render the source to SVG or PNG.
4. Read the rendered output and inspect its layout.

```bash
d2 architecture.d2 architecture.svg
d2 --layout elk architecture.d2 architecture.svg
```

Use the default layout first. Use ELK only when the default layout tangles a dense graph.

SKILL_D2

write_generated "$AGENTS_SKILLS/api-testing/SKILL.md" <<'SKILL_API'
---
name: api-testing
description: Exercise HTTP APIs from the terminal. Use for live requests, response diagnosis, or repeatable protocol assertions.
---

# API testing

Use `xh` for one-off HTTP requests. Use Hurl for repeatable HTTP assertions.

```bash
xh GET api.example.com/users limit==20 Authorization:"Bearer $TOKEN"
xh POST api.example.com/users name=Ada email=ada@example.com
```

Store durable HTTP checks in `.hurl` files.

```hurl
GET https://api.example.com/users
HTTP 200
[Asserts]
jsonpath "$.data[0].id" exists
```

Run durable checks with `hurl --test <file>`.

Reference secrets through environment variables. Do not store tokens in commands, fixtures, or checked-in files.
SKILL_API

write_generated "$AGENTS_SKILLS/inspect-machine/SKILL.md" <<'SKILL_INSPECT_MACHINE'
---
name: inspect-machine
description: Discovers CLI tools, terminal apps, GUI apps, and shell aliases on machines provisioned by vixygrey-dev-setup. Use when choosing a local tool, checking availability, translating aliases, or explaining machine capabilities.
---

# Inspect machine

Use the generated machine records before you select a local tool.

> **HARD GATE** — Read `~/Desktop/TOOL_REFERENCE.md` before you recommend an installed tool.

Never infer current availability from the reference alone. Verify the target surface.

## Sources

1. Read `~/Desktop/TOOL_REFERENCE.md` for the intended CLI, TUI, and GUI inventory.
2. Read `~/Desktop/TOOLKIT_SUMMARY.md` for a shorter capability map.
3. Search `~/.zshrc` only when you must translate an alias or launcher function.
4. Use the harness file tools for these records. Do not use shell paging or search commands.

Treat the generated reference as intended state. Treat live resolution as observed state.

## CLI tools

Verify a command with `command -v -- <command>` in the target shell.

Use the command name from the reference, not its Homebrew package name.

Compare `zsh -c`, `zsh -l -i -c`, and `sh -c` only when command-path context matters.

Report every resolved path when the shell contexts disagree.

Use the canonical binary from an agent shell. Do not use human aliases.

## GUI applications

Verify an application with `open -Ra "<Application Name>"`.

This command does not launch the target application. Finder reveals the application and becomes visible.

Run `open -a "<Application Name>"` only when the user requests a launch.

## Aliases and launchers

Treat aliases inside the interactive `~/.zshrc` guard as human-only conveniences.

Translate an alias to its canonical command before you act.

Do not start terminal interfaces from a detached or non-interactive task.

Use the agent shell `rm` wrapper for recoverable deletion.

Use `/bin/rm` only for isolated test cleanup that requires permanent deletion.

## Safety

Do not read shell history, credentials, tokens, keychains, or environment-variable values.

Report intended and observed state separately when installation is incomplete.

→ verify: `test -r "$HOME/Desktop/TOOL_REFERENCE.md" && test -r "$HOME/.zshrc" && command -v omp >/dev/null`
SKILL_INSPECT_MACHINE

configured "OMP shared skills written (api-testing, d2-diagrams, inspect-machine, office-layout-check)"
# ---- Oh My Pi (omp) coding agent (~/.omp/agent) ----
# omp is the coding agent in this setup. It provides tools, LSP, DAP, subagents,
# and workload-routed model roles. Credentials stay user-owned.
#
# Two vocabulary traps upstream, both worth naming here because the ids share one
# namespace and the wrong one fails silently:
#   * `google` is the MODEL provider (the Gemini API). `gemini` is a DISCOVERY
#     provider — the source that reads GEMINI.md. Disabling or configuring the
#     wrong one does nothing visible. Roles below are all `google/...`.
#   * `~/.agents/skills` is omp's canonical shared skills location. The four
#     generated skills need no copies under ~/.omp/agent/skills.
OMP_DIR="$HOME/.omp/agent"
OMP_THEME_DIR="$OMP_DIR/themes"
OMP_THEME_FILE="$OMP_THEME_DIR/dracula-sakura.json"
KIRO_STEERING_DIR="$HOME/.kiro/steering"
KIRO_AGENTS="$KIRO_STEERING_DIR/AGENTS.md"
# Two skill directories, both verified against omp's source rather than its docs,
# which describe the layout without pinning the user-level path (#513):
#   ~/.omp/agent/skills  — the `native` provider, priority 100.
#   ~/.agents/skills     — the `agents` provider, priority 70.
OMP_SKILLS_DIR="$OMP_DIR/skills"
OMP_EXTENSIONS_DIR="$OMP_DIR/extensions"
OMP_RETIRED_SKILLS=(tiki-capture tiki-review tiki-groom tiki-arc tiki-journal)
OMP_RETIRED_EXTENSIONS=(
    turn-counter.ts
    permission-gate.ts
    permissions-gate.ts
    confirm-destructive.ts
    git-checkpoint.ts
    dirty-repo-guard.ts
    notify.ts
)
# config.yml is canonical. Preserve config.yaml when omp already uses that name.
OMP_CONFIG_FILE="$OMP_DIR/config.yml"
OMP_ENV_FILE="$OMP_DIR/.env"
OMP_LSP_FILE="$OMP_DIR/lsp.yml"
[[ -f "$OMP_DIR/config.yaml" && ! -f "$OMP_CONFIG_FILE" ]] && OMP_CONFIG_FILE="$OMP_DIR/config.yaml"

# OMP loads provider credentials from this exact path after the process and project
# environments. Seed blank entries once, then leave the credential file user-owned.
if write_seed_once "$OMP_ENV_FILE" "paste your Anthropic and Gemini API keys into the blank entries" <<'OMP_ENV_CONF'
# OMP provider credentials. Paste each key after the equals sign.
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
OMP_ENV_CONF
then
    if [[ "$DRY_RUN" != "true" ]]; then
        chmod 600 "$OMP_ENV_FILE"
        configured "omp provider key template seeded ($OMP_ENV_FILE)"
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write omp config -> $OMP_DIR (AGENTS.md, themes/dracula-sakura.json)"
    info "[DRY RUN] Would merge omp settings -> $OMP_CONFIG_FILE (theme, model routing, provider settings)"
    info "[DRY RUN] Would write omp LSP policy -> $OMP_LSP_FILE"
    info "[DRY RUN] Would retire obsolete omp skills and extensions"
    info "[DRY RUN] Would write the protected-paths guard -> $OMP_EXTENSIONS_DIR/protected-paths.ts"
    info "[DRY RUN] Would write Kiro global AGENTS.md -> $KIRO_AGENTS"
else
    mkdir -p "$OMP_THEME_DIR" "$OMP_SKILLS_DIR" "$OMP_EXTENSIONS_DIR" "$AGENTS_SKILLS"
    for _skill in "${OMP_RETIRED_SKILLS[@]}"; do
        rm -f "$OMP_SKILLS_DIR/$_skill/SKILL.md"
        rmdir "$OMP_SKILLS_DIR/$_skill" 2>/dev/null || true
    done
    for _extension in "${OMP_RETIRED_EXTENSIONS[@]}"; do
        rm -f "$OMP_EXTENSIONS_DIR/$_extension"
    done
    unset _skill _extension

    # -- AGENTS.md ----------------------------------------------------------------
    # Same two-part shape as pi's: shared preferences, then the shared writing rules.
    # Both come from the same emitters, so the two harnesses cannot drift (#504).
    # omp gives this file the highest precedence of any user-level context source.
    # Its `native` provider outranks the other providers.
    {
    emit_agent_preferences "Oh My Pi"
    emit_writing_rules
    } | write_generated "$OMP_DIR/AGENTS.md"
    success "omp: AGENTS.md written, with the shared writing rules (~/.omp/agent/AGENTS.md)"

    # Kiro consumes the same global AGENTS.md instructions through its global
    # steering directory. Keep both copies generated from the same emitters.
    {
    emit_agent_preferences "Oh My Pi"
    emit_writing_rules
    } | write_generated "$KIRO_AGENTS"
    success "Kiro global AGENTS.md written (~/.kiro/steering/AGENTS.md)"

    # -- Dracula-Sakura theme -----------------------------------------------------
    # Same palette as pi's theme, different schema: omp requires every one of its
    # colour tokens, including thirteen statusLine* entries and a `link` and
    # `toolText` that pi has no equivalent for. So this is authored against omp's
    # own schema rather than inherited from pi, whose theme had a different token set.
    write_generated "$OMP_THEME_FILE" <<'OMP_THEME_CONF'
{
  "$schema": "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/modes/theme/theme-schema.json",
  "name": "dracula-sakura",
  "vars": {
    "bg": "#282a36",
    "panel": "#323448",
    "panelSoft": "#2f3144",
    "current": "#4b4963",
    "selection": "#6a5d86",
    "fg": "#f8f8f2",
    "muted": "#ddd2f7",
    "dim": "#a297cb",
    "comment": "#8a88c7",
    "cyan": "#9be7ff",
    "mint": "#8af7cf",
    "peach": "#ffcf93",
    "rose": "#ff9fe3",
    "blush": "#ffc2ec",
    "lilac": "#d4b2ff",
    "red": "#ff7aa8",
    "yellow": "#fff0a8"
  },
  "colors": {
    "accent": "rose",
    "border": "lilac",
    "borderAccent": "cyan",
    "borderMuted": "current",
    "success": "mint",
    "error": "red",
    "warning": "peach",
    "muted": "muted",
    "dim": "dim",
    "text": "fg",
    "thinkingText": "comment",
    "selectedBg": "selection",
    "userMessageBg": "panel",
    "userMessageText": "fg",
    "customMessageBg": "panelSoft",
    "customMessageText": "fg",
    "customMessageLabel": "cyan",
    "toolPendingBg": "#34364b",
    "toolSuccessBg": "#233b36",
    "toolErrorBg": "#4a3040",
    "toolTitle": "rose",
    "toolOutput": "muted",
    "mdHeading": "blush",
    "mdLink": "cyan",
    "mdLinkUrl": "comment",
    "mdCode": "mint",
    "mdCodeBlock": "yellow",
    "mdCodeBlockBorder": "current",
    "mdQuote": "muted",
    "mdQuoteBorder": "lilac",
    "mdHr": "current",
    "mdListBullet": "rose",
    "toolDiffAdded": "mint",
    "toolDiffRemoved": "red",
    "toolDiffContext": "comment",
    "syntaxComment": "comment",
    "syntaxKeyword": "rose",
    "syntaxFunction": "mint",
    "syntaxVariable": "peach",
    "syntaxString": "yellow",
    "syntaxNumber": "lilac",
    "syntaxType": "cyan",
    "syntaxOperator": "rose",
    "syntaxPunctuation": "fg",
    "thinkingOff": "current",
    "thinkingMinimal": "comment",
    "thinkingLow": "lilac",
    "thinkingMedium": "cyan",
    "thinkingHigh": "rose",
    "thinkingXhigh": "blush",
    "thinkingMax": "red",
    "bashMode": "mint",
    "pythonMode": "lilac",
    "statusLineBg": "panel",
    "statusLineSep": "current",
    "statusLineModel": "rose",
    "statusLinePath": "cyan",
    "statusLineGitClean": "mint",
    "statusLineGitDirty": "peach",
    "statusLineContext": "lilac",
    "statusLineSpend": "cyan",
    "statusLineStaged": "mint",
    "statusLineDirty": "peach",
    "statusLineUntracked": "blush",
    "statusLineOutput": "blush",
    "statusLineCost": "rose",
    "statusLineSubagents": "lilac"
  },
  "export": {
    "pageBg": "#1f2030",
    "cardBg": "#282a36",
    "infoBg": "#3e3148"
  }
}
OMP_THEME_CONF
    success "omp: Dracula-Sakura theme written (~/.omp/agent/themes/dracula-sakura.json)"

    # -- lsp.yml ------------------------------------------------------------------
    # OMP merges this low-precedence user policy onto its built-in server registry.
    # A user can override it with lsp.yaml or lsp.json in the same directory.
    # Pyright owns Python type intelligence, Ruff owns lint and format operations,
    # and Docker's current server replaces the retired docker-langserver command.
    write_managed "$OMP_LSP_FILE" "#" <<'OMP_LSP_CONF'
servers:
  ty:
    disabled: true
  basedpyright:
    disabled: true
  dockerls:
    command: docker-language-server
    args:
      - start
      - --stdio
    initOptions:
      telemetry: "off"
OMP_LSP_CONF
    configured "omp LSP policy written ($OMP_LSP_FILE)"


    # -- Protected paths ----------------------------------------------------------
    # This extension blocks native file mutations to credential stores, dependency
    # trees, and repository metadata. It does not claim to sandbox Bash or Eval.
    # omp's native approval policies govern those execution surfaces.
    write_generated "$OMP_EXTENSIONS_DIR/protected-paths.ts" <<'OMP_PROTECTED_PATHS_EXT'
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import {
    basename,
    dirname,
    isAbsolute,
    relative,
    resolve,
    sep,
} from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type Input = Record<string, unknown>;

const SAFE_ENV_SUFFIXES = [".example", ".sample", ".template", ".dist"];
const PROTECTED_COMPONENTS = new Map([
    [".git", "version-control metadata"],
    [".hg", "version-control metadata"],
    [".svn", "version-control metadata"],
    ["node_modules", "the dependency tree"],
]);
const EXACT_HOME_SECRETS = new Set([
    ".npmrc",
    ".netrc",
    ".config/gh/hosts.yml",
    ".docker/config.json",
    ".kube/config",
    ".omp/auth-broker.token",
    ".omp/auth-gateway.token",
]);

function isRecord(value: unknown): value is Input {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function withoutContainerSelector(value: string): string {
    const match = value.match(/^(.+\.(?:db3?|sqlite3?))(?::.*)?$/i);
    return match?.[1] ?? value;
}

function expandPath(value: string, cwd: string, home: string): string | null {
    let candidate = withoutContainerSelector(value.trim());
    if (!candidate) return null;
    if (candidate.startsWith("file://")) {
        try {
            candidate = fileURLToPath(candidate);
        } catch {
            return null;
        }
    } else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(candidate)) {
        return null;
    }
    if (candidate === "~") candidate = home;
    if (candidate.startsWith(`~${sep}`)) {
        candidate = resolve(home, candidate.slice(2));
    }
    return isAbsolute(candidate) ? resolve(candidate) : resolve(cwd, candidate);
}

function canonicalPath(candidate: string): string {
    const suffix: string[] = [];
    let cursor = candidate;
    while (!existsSync(cursor)) {
        const parent = dirname(cursor);
        if (parent === cursor) return candidate;
        suffix.unshift(basename(cursor));
        cursor = parent;
    }
    try {
        return resolve(realpathSync.native(cursor), ...suffix);
    } catch {
        return candidate;
    }
}

function isWithin(candidate: string, root: string): boolean {
    const offset = relative(root, candidate);
    return offset === "" ||
        (offset !== ".." && !offset.startsWith(`..${sep}`) && !isAbsolute(offset));
}

function homeRelative(candidate: string, home: string): string | null {
    if (!isWithin(candidate, home)) return null;
    return relative(home, candidate).split(sep).join("/");
}

function reasonFor(candidate: string, home: string): string | null {
    const components = candidate.split(sep).filter(Boolean);
    for (const component of components) {
        const reason = PROTECTED_COMPONENTS.get(component.toLowerCase());
        if (reason) return reason;
    }

    const fileName = basename(candidate).toLowerCase();
    if (fileName === ".env" || fileName.startsWith(".env.")) {
        if (!SAFE_ENV_SUFFIXES.some((suffix) => fileName.endsWith(suffix))) {
            return "an environment secret file";
        }
    }

    const homePath = homeRelative(candidate, home);
    if (homePath === null) return null;
    if (
        homePath === ".ssh" ||
        homePath.startsWith(".ssh/") ||
        homePath === ".aws" ||
        homePath.startsWith(".aws/") ||
        homePath === "Library/Keychains" ||
        homePath.startsWith("Library/Keychains/")
    ) {
        return "a credential directory";
    }

    if (EXACT_HOME_SECRETS.has(homePath)) return "a credential file";
    if (
        /^\.omp\/agent\/agent\.db(?:-(?:wal|shm))?$/.test(homePath) ||
        /^\.omp\/profiles\/[^/]+\/agent\/agent\.db(?:-(?:wal|shm))?$/.test(homePath) ||
        /^\.omp\/profiles\/[^/]+\/auth-(?:broker|gateway)\.token$/.test(homePath)
    ) {
        return "the omp credential database";
    }
    return null;
}

export function classifyProtectedPath(
    value: string,
    cwd = process.cwd(),
    home = homedir(),
): string | null {
    const lexical = expandPath(value, cwd, home);
    if (!lexical) return null;
    const canonical = canonicalPath(lexical);
    const canonicalHome = canonicalPath(resolve(home));
    return reasonFor(lexical, home) ?? reasonFor(canonical, canonicalHome);
}

function addPath(value: unknown, paths: Set<string>): void {
    if (typeof value === "string") {
        paths.add(value);
        return;
    }
    if (Array.isArray(value)) {
        for (const item of value) addPath(item, paths);
    }
}

function addCommonPaths(input: Input, paths: Set<string>): void {
    for (const key of ["path", "paths", "file", "files", "file_path"]) {
        addPath(input[key], paths);
    }
}

function addPatchPaths(value: unknown, paths: Set<string>): void {
    if (typeof value !== "string") return;
    for (const match of value.matchAll(/^\[([^#\r\n]+)#[0-9A-F]{4}\]$/gm)) {
        paths.add(match[1]);
    }
    for (const match of value.matchAll(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm)) {
        paths.add(match[1]);
    }
}

function addLspPaths(input: Input, paths: Set<string>): void {
    const mutates = input.action === "rename" ||
        input.action === "rename_file" ||
        (input.action === "code_actions" && input.apply === true);
    if (!mutates) return;
    addPath(input.file, paths);
    if (input.action === "rename_file") addPath(input.new_name, paths);
}

function addDevicePaths(input: Input, paths: Set<string>): void {
    if (typeof input.content !== "string") return;
    let args: Input;
    try {
        const parsed: unknown = JSON.parse(input.content);
        if (!isRecord(parsed)) return;
        args = parsed;
    } catch {
        return;
    }

    if (input.path === "xd://ast_edit") {
        addPath(args.paths, paths);
        return;
    }
    if (input.path === "xd://lsp") addLspPaths(args, paths);
}

export function collectMutationPaths(toolName: string, input: unknown): string[] {
    if (!isRecord(input)) return [];
    const paths = new Set<string>();
    if (toolName === "write") {
        addCommonPaths(input, paths);
        addDevicePaths(input, paths);
    } else if (toolName === "edit" || toolName === "apply_patch") {
        addCommonPaths(input, paths);
        addPatchPaths(input.patch, paths);
        addPatchPaths(input.input, paths);
    } else if (toolName === "ast_edit") {
        addPath(input.paths, paths);
    } else if (toolName === "lsp") {
        addLspPaths(input, paths);
    }
    return [...paths];
}

export default function protectedPaths(pi: ExtensionAPI): void {
    pi.on("tool_call", (event, ctx) => {
        for (const path of collectMutationPaths(event.toolName, event.input)) {
            const reason = classifyProtectedPath(path, ctx.cwd);
            if (reason) {
                return {
                    block: true,
                    reason: `Blocked a write to ${path}. The target is protected: ${reason}.`,
                };
            }
        }
        return undefined;
    });
}
OMP_PROTECTED_PATHS_EXT
    configured "omp protected-paths guard written (~/.omp/agent/extensions/protected-paths.ts)"


    # -- config.yml ---------------------------------------------------------------
    # MERGE, never write_managed. omp owns this file: `/settings`, `omp config set`
    # and `omp config reset` all write it back through their own YAML serializer,
    # which would not preserve managed-block comments. So this is the same shape as
    # the pi models.json merge — our keys, everything else untouched — except with
    # yq, because the file is YAML. omp re-reads it under a lock on save, so an edit
    # made here while a session is open is preserved rather than clobbered.
    #
    # These keys are RE-ASSERTED every run, so a role reassigned in-session with
    # `/model` reverts on the next setup. That is the generator doctrine working as
    # intended, but it is a surprise for a model choice specifically. To pin a
    # different model for one repo, write `<repo>/.omp/config.yml`: project settings
    # outrank global and this block never touches them.
    if command -v yq &>/dev/null; then
        OMP_TMP=$(mktemp)
        OMP_OURS=$(mktemp)
        /bin/cat > "$OMP_OURS" <<'OMP_CONFIG_CONF'
theme:
  dark: dracula-sakura
  # Both slots, so a light terminal background does not fall back to omp's
  # stock `light` theme and lose the palette entirely (#525).
  light: dracula-sakura
# Use automatic reasoning for ordinary turns. Role suffixes below set fixed
# levels where latency, cost, or depth has a clear priority.
defaultThinkingLevel: auto

# Nerd-font glyphs. This machine installs the nerd fonts and configures Kitty
# with one, so the default `unicode` preset understates what the terminal can draw.
symbolPreset: nerd

composer:
  shape: box

# Keep macOS dictionary completions out of the composer. Typo detection remains
# active, but omp no longer inserts inline word suggestions while typing (#561).
spelling:
  autocomplete: false
github:
  enabled: true

# Diagnostics as omp edits, not only when it writes. omp ships lsp.enabled and
# debug.enabled on, and edit.mode already defaults to hashline, so those need no
# configuring; this one defaults to off (#527).
lsp:
  diagnosticsOnEdit: true

# The advisor is a SECOND model watching every turn. Off deliberately (#525).
# Written as an explicit `false` rather than omitted: the schema default is
# already false, but stating it records the decision and survives an upstream
# default change. `modelRoles.advisor` below stays on Pro, which costs nothing
# while this is off and is the right assignment if it is ever switched on.
advisor:
  enabled: false
# Hosted roles follow workload strengths. Luna handles ordinary interactive work,
# while GPT-5.6-Sol handles delegated tasks. Gemini handles vision, the advisor,
# and cheap fan-out. Claude Sonnet is primary for slow and plan (#538, #598).
modelRoles:
  default: openai-codex/gpt-5.6-luna
  task: openai-codex/gpt-5.6-sol
  vision: google/gemini-3.8-flash:medium
  slow: anthropic/claude-sonnet-5:high
  plan: anthropic/claude-sonnet-5:high
  advisor: google/gemini-3.1-pro-preview:low
  smol: google/gemini-3.1-flash-lite:minimal
  tiny: google/gemini-3.1-flash-lite:minimal
  commit: google/gemini-3.1-flash-lite:minimal
# MiniMax is intentionally disabled and must not participate in model routing.
disabledProviders:
  - minimax-code
# Anthropic never appears in a fallback chain. Gemini is the first hosted
# fallback for ordinary work. The Vulkan-backed local Qwen coder is final in
# every chain, so a second provider failure stays on this machine.
retry:
  modelFallback: true
  # Return to the primary model when its suppression window ends. Route away
  # automatically before a coding-plan account spends its final 10 percent.
  fallbackRevertPolicy: cooldown-expiry
  usageAwareFallback: true
  usageReservePct: 10
  usageReservePolicy: auto
  fallbackChains:
    openai-codex/gpt-5.6-luna:
      - google/gemini-3.8-flash:medium
      - llama.cpp/qwen2.5-coder:14b
    openai-codex/gpt-5.6-sol:
      - google/gemini-3.8-flash:medium
      - llama.cpp/qwen2.5-coder:14b
    anthropic/claude-sonnet-5:
      - google/gemini-3.1-pro-preview:high
      - llama.cpp/qwen2.5-coder:14b
    google/gemini-3.1-pro-preview:
      - openai-codex/gpt-5.6-sol:high
      - llama.cpp/qwen2.5-coder:14b
    google/gemini-3.1-flash-lite:
      - openai-codex/gpt-5.3-codex-spark:low
      - llama.cpp/qwen2.5-coder:14b
    google/gemini-3.8-flash:
      - openai-codex/gpt-5.6-sol:medium
      - llama.cpp/qwen2.5-coder:14b
    default:
      - google/gemini-3.8-flash:medium
      - llama.cpp/qwen2.5-coder:14b
# Local SearXNG, first in the web_search chain. This replaces the ~300-line
# TypeScript extension the pi block generated (#513): omp carries `searxng` as
# one of 23 built-in web_search backends, with site-aware extraction, so the
# whole feature is two keys instead of a tool to maintain.
#
# The endpoint is the default for a local instance. Override it here, or with
# SEARXNG_ENDPOINT, if yours is elsewhere. The remaining backends stay in their
# built-in order behind this one, so search still works when the instance is
# down — several of them need no key at all.
searxng:
  endpoint: http://127.0.0.1:8080
providers:
  # Preserve each provider's supported prompt-cache behavior.
  cacheRetention: auto
  webSearchOrder:
    - searxng
OMP_CONFIG_CONF
        [[ -f "$OMP_CONFIG_FILE" ]] || echo '{}' > "$OMP_CONFIG_FILE"
        if yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' \
            "$OMP_CONFIG_FILE" "$OMP_OURS" > "$OMP_TMP" 2>/dev/null && [[ -s "$OMP_TMP" ]]; then
            mv "$OMP_TMP" "$OMP_CONFIG_FILE"
            configured "omp: theme + model routing + provider settings merged ($OMP_CONFIG_FILE)"
        else
            rm -f "$OMP_TMP"
            warn "omp: could not merge $OMP_CONFIG_FILE"
        fi
        rm -f "$OMP_OURS"
        unset OMP_TMP OMP_OURS
    else
        warn "omp: yq missing — skipping config.yml merge"
    fi


    # The seed above owns only the initial template. OMP reads any pasted values
    # directly, while later setup runs leave the credential file byte-for-byte intact.
fi

# Run the Vulkan build as a login service. Port 8081 avoids the local SearXNG
# endpoint on 8080. OMP reads LLAMA_CPP_BASE_URL from the managed shell block.
LLAMA_SERVER="$HOME/.local/share/llama.cpp-vulkan/bin/llama-server"
LLAMA_MODEL="$HOME/.local/share/llama.cpp/models/qwen2.5-coder-14b-instruct-q4_k_m.gguf"
LLAMA_PLIST="$HOME/Library/LaunchAgents/dev.vixygrey.llama-cpp.plist"
LLAMA_LOG="$HOME/Library/Logs/llama.cpp-server.log"
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write and load the llama.cpp Vulkan login service on 127.0.0.1:8081"
elif [[ ! -x "$LLAMA_SERVER" || ! -f "$LLAMA_MODEL" ]]; then
    warn "llama.cpp binary or model missing — skipping the login service"
else
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    _llama_plist_new="$(/bin/cat <<LLAMA_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>dev.vixygrey.llama-cpp</string>
    <key>ProgramArguments</key>
    <array>
        <string>$LLAMA_SERVER</string>
        <string>--model</string><string>$LLAMA_MODEL</string>
        <string>--alias</string><string>qwen2.5-coder:14b</string>
        <string>--host</string><string>127.0.0.1</string>
        <string>--port</string><string>8081</string>
        <string>--ctx-size</string><string>32768</string>
        <string>--n-gpu-layers</string><string>99</string>
        <string>--jinja</string>
        <string>--sleep-idle-seconds</string><string>300</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>VK_ICD_FILENAMES</key><string>$(brew --prefix molten-vk)/etc/vulkan/icd.d/MoltenVK_icd.json</string>
        <key>VK_DRIVER_FILES</key><string>$(brew --prefix molten-vk)/etc/vulkan/icd.d/MoltenVK_icd.json</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>StandardOutPath</key><string>$LLAMA_LOG</string>
    <key>StandardErrorPath</key><string>$LLAMA_LOG</string>
</dict>
</plist>
LLAMA_PLIST_EOF
)"
    if [[ ! -f "$LLAMA_PLIST" ]] || ! printf '%s\n' "$_llama_plist_new" | diff -q - "$LLAMA_PLIST" >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)" "$LLAMA_PLIST" >> "$LOG_FILE" 2>&1 || true
        printf '%s\n' "$_llama_plist_new" > "$LLAMA_PLIST"
        if launchctl bootstrap "gui/$(id -u)" "$LLAMA_PLIST" >> "$LOG_FILE" 2>&1; then
            configured "llama.cpp Vulkan service loaded (127.0.0.1:8081)"
        else
            warn "Could not load the llama.cpp service — see $LOG_FILE"
        fi
    else
        launchctl kickstart -k "gui/$(id -u)/dev.vixygrey.llama-cpp" >> "$LOG_FILE" 2>&1 || true
        configured "llama.cpp Vulkan service already current (127.0.0.1:8081)"
    fi
    unset _llama_plist_new
fi
unset LLAMA_SERVER LLAMA_MODEL LLAMA_PLIST LLAMA_LOG
unset OMP_DIR OMP_THEME_DIR OMP_THEME_FILE OMP_SKILLS_DIR OMP_EXTENSIONS_DIR
unset AGENTS_SKILLS OMP_RETIRED_SKILLS OMP_RETIRED_EXTENSIONS OMP_CONFIG_FILE OMP_ENV_FILE


fi  # configs

# =============================================================================
if should_run "shell"; then
banner "Shell Configuration"

ZSHRC="$HOME/.zshrc"

# Back up an existing .zshrc and migrate any pre-6.x marker, then hand the block to
# write_managed (same splice logic as every other managed config). A brand-new file
# is created fresh by write_managed; personal edits outside the markers are preserved.
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write the ~/.zshrc managed block (backing up first)"
elif [[ -f "$ZSHRC" ]]; then
    cp "$ZSHRC" "$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    # Pre-6.x blocks used a shorter begin marker; rename it in place so
    # write_managed recognizes the block and replaces it instead of appending a dupe.
    if grep -qxF "# >>> dev-setup managed block >>>" "$ZSHRC"; then
        # /usr/bin/sed = BSD sed; bare `sed` may be GNU (gnubin on PATH), where -i '' differs.
        /usr/bin/sed -i '' 's|^# >>> dev-setup managed block >>>$|# >>> dev-setup managed block (do not edit between the markers) >>>|' "$ZSHRC"
    fi
fi

write_managed "$ZSHRC" "#" <<'MANAGED_ZSHRC'
# This block is managed by setup-dev-tools-mac.sh — edits may be overwritten on re-run.
# Add personal customizations OUTSIDE this block (above or below).

# -- PATH additions -----------------------------------------------------------

# Deduplicate PATH
typeset -U PATH path

# uv tool / pipx persistent binaries (harlequin, checkov, anything user
# installs via `uv tool install`). .zprofile sets this too — re-asserting
# here for non-login interactive shells.
export PATH="$HOME/.local/bin:$PATH"

# Personal scripts
export PATH="$HOME/Scripts/bin:$PATH"

# .NET global tools (`dotnet tool install -g`). .zprofile sets this too —
# re-asserting here for non-login interactive shells. Not redundant with
# /etc/paths.d/dotnet-cli-tools: that file holds a literal `~` that never
# expands (#316). Guarded: inert without .NET.
[[ -d "$HOME/.dotnet/tools" ]] && export PATH="$HOME/.dotnet/tools:$PATH"

# -- Environment Variables ----------------------------------------------------

# ripgrep config path
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# OMP local provider. Port 8080 belongs to the managed SearXNG instance.
export LLAMA_CPP_BASE_URL="http://127.0.0.1:8081"

# GPG tty (required for commit signing to work)
export GPG_TTY=$(tty)

# Shared per-shell cache dir (delete ~/.cache/dev-setup to regenerate after updates)
_cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/dev-setup"; mkdir -p "$_cachedir" 2>/dev/null

# LS_COLORS via vivid — cached (regenerating vivid on every shell is slow)
if [[ ! -r "$_cachedir/ls_colors" ]] && command -v vivid &>/dev/null; then
    vivid generate dracula > "$_cachedir/ls_colors" 2>/dev/null
fi
[[ -r "$_cachedir/ls_colors" ]] && export LS_COLORS="$(< "$_cachedir/ls_colors")"

# -- Tool Initialization ------------------------------------------------------

# GNU coreutils on PATH — deterministic prefix, no per-pkg `brew --prefix` fork
: "${HOMEBREW_PREFIX:=/opt/homebrew}"
for _pkg in coreutils gnu-sed gnu-tar gawk findutils; do
    _gnubin="$HOMEBREW_PREFIX/opt/$_pkg/libexec/gnubin"
    [[ -d "$_gnubin" ]] && export PATH="$_gnubin:$PATH"
done
unset _pkg _gnubin

# mise is activated in ~/.zshenv so EVERY shell type gets it, and again at the bottom of
# this file so it also wins on PATH. See the block above the welcome screen for why.

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# starship prompt
command -v starship &>/dev/null && eval "$(starship init zsh)"

# fzf (sourced BEFORE atuin so atuin's Ctrl-R bind wins — fzf key-bindings also grab Ctrl-R)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# atuin (replaces ctrl-r shell history)
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# granted — `assume` is a POSIX sh script that must be SOURCED to export AWS creds into the shell.
# Interactive only, for the same reason as the alias section below: sourcing exports creds into the
# shell you are sitting in, which is meaningless for a one-shot agent command, and shadowing the
# binary with `source` makes plain invocations (`assume --help`) behave unexpectedly.
if [[ -o interactive && -z "$AI_AGENT" ]]; then
    command -v assume &>/dev/null && alias assume="source assume"
fi

# fzf — Dracula-Sakura colors + fd for file finding + bat for preview
export FZF_DEFAULT_OPTS=" \
  --color=fg:#f8f8f2,bg:#282a36,hl:#8be9fd \
  --color=fg+:#f8f8f2,bg+:#44475a,hl+:#8be9fd \
  --color=info:#ffb86c,prompt:#ff79c6,pointer:#bd93f9 \
  --color=marker:#50fa7b,spinner:#ff79c6,header:#6272a4 \
  --color=border:#bd93f9 \
  --height=60% --layout=reverse --border=rounded \
  --prompt='find ❯ ' --pointer='▶' --marker='✓' \
  --header='ctrl-/ preview • ctrl-y copy • ctrl-u/d scroll' \
  --header-first \
  --bind='ctrl-/:toggle-preview' \
  --bind='ctrl-d:half-page-down,ctrl-u:half-page-up' \
  --bind='ctrl-y:execute-silent(echo -n {+} | pbcopy)+abort' \
  --preview-window='right:50%:wrap:hidden' \
  --info=inline"

# Use fd instead of find (respects .gitignore, faster)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'

# CTRL-T: paste file path (with bat preview)
export FZF_CTRL_T_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {}' --preview-window='right:50%:wrap'"

# ALT-C: cd into directory (with eza tree preview)
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --tree --icons --level=2 --color=always {}' --preview-window='right:50%:wrap'"

# Yazi uses theme.toml for its house palette. The `y` alias starts the manager.

# zsh plugins (deterministic prefix — no `brew --prefix` fork)
: "${HOMEBREW_PREFIX:=/opt/homebrew}"
[[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# -- Completions --------------------------------------------------------------
FPATH="$HOMEBREW_PREFIX/share/zsh/site-functions:${FPATH}"
autoload -Uz compinit && compinit -C
autoload -Uz bashcompinit && bashcompinit   # bash-style complete (aws_completer)
# Tool completions cached to files — live-generating each per shell was the
# dominant startup cost. Delete ~/.cache/dev-setup to refresh after tool updates.
_compcache() { local f="$_cachedir/comp_$1"; shift; [[ -r "$f" ]] || "$@" > "$f" 2>/dev/null; [[ -r "$f" ]] && source "$f"; }
command -v gh            &>/dev/null && _compcache gh gh completion -s zsh
command -v aws_completer &>/dev/null && complete -C aws_completer aws
# Leaf writes its completion script through the setup block. It must load after
# compinit, which defines the compdef command that the script uses.
[[ -r "$HOME/.local/share/leaf/completions/_leaf" ]] &&
    source "$HOME/.local/share/leaf/completions/_leaf"
unset -f _compcache
unset _cachedir

# -- Modern Tool Aliases (replacements for built-in commands) -----------------
# Note: we avoid aliasing cd, sed, find, grep, diff globally since they have
# different syntax from their replacements and would break scripts/muscle memory.
# Instead, we provide short aliases for the modern tools.
#
# INTERACTIVE ONLY — and the guard opened here stays open until the end of the
# System section, covering EVERY alias and the fzf launcher functions, not just the
# replacements immediately below.
#
# That same reasoning applies throughout: none of the replacements accept the flags
# the original takes. `du -sh` prints dust's help text, `top -l1` is an unknown
# argument, and `pip install X` becomes `uv pip install X` and dies with "No virtual environment found".
# `ps aux` and `dig +short` silently ignore the argument and return
# differently-shaped output that looks correct. A human notices; a script or an AI
# agent parses the garbage. The TUI launchers (br, lg, lzd, hq, y, n, clip,
# claws) and the fzf-backed a/ff/rgf simply block when no terminal is attached.
#
# Coding agents run commands through a non-interactive shell that still sources
# this file, so they inherit these aliases without a guard. Gate on interactivity,
# plus the agent variable as a backstop for an agent that invokes `zsh -i`.
# Gating the section also covers aliases added later.
# Remove the legacy managed alias on reload. Do not change a user-defined alias.
[[ "$(alias rm 2>/dev/null)" == "rm=trash" ]] && unalias rm

if [[ -o interactive && -z "$AI_AGENT" ]]; then
    alias ls="eza --icons"
    alias ll="eza -la --icons --git"
    alias la="eza -a --icons"
    alias lt="eza --tree --icons --level=3"
    alias cat="bat --paging=never"
    alias top="btop"
    alias du="dust"
    alias df="duf"
    alias ps="procs"
    alias ping="gping"
    alias dig="doggo"
    alias watch="viddy"
    alias hexdump="hexyl"

# Short aliases for modern tools (don't override builtins)
alias f="fd"           # fd (fast find)
alias dft="difft"      # difftastic
# Yazi's recommended wrapper changes the parent shell directory after exit.
# Press `Q` instead of `q` in Yazi to leave the shell directory unchanged.
y() {
  local tmp cwd
  tmp="$(mktemp -t 'yazi-cwd.XXXXXX')"
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp" || true
  [[ "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
  /bin/rm -f -- "$tmp"
}
# Broot's generated launcher applies `cd` and other shell commands in this shell.
function br {
    local cmd cmd_file code
    cmd_file=$(mktemp)
    if broot --outcmd "$cmd_file" "$@"; then
        cmd=$(<"$cmd_file")
        command rm -f "$cmd_file"
        eval "$cmd"
    else
        code=$?
        command rm -f "$cmd_file"
        return "$code"
    fi
}
alias jx="fx"          # fx interactive JSON viewer

# -- Download & Transfer ------------------------------------------------------
# `dl` is a shortcut for a tool that IS installed. There is deliberately no
# `wget` alias: wget is not installed, aria2c takes different flags, and aliasing
# turned a clean "command not found" into a confusing aria2c exception. Use
# `curl`, `xh`, or `aria2c`/`dl` directly.
alias dl="aria2c"

# -- Git & GitHub -------------------------------------------------------------
alias lg="lazygit"
alias ghd="gh dash"
alias gdft="git dft"
alias gha="act"

# -- Containers & Kubernetes --------------------------------------------------
alias lzd="lazydocker"

# -- File Tools ---------------------------------------------------------------
alias md="leaf"
alias serve="miniserve --color-scheme-dark dracula -qr ."
alias csvp="csvlook"

# -- Media & Conversion -------------------------------------------------------
alias ytdl="yt-dlp"
alias ytmp3="yt-dlp -x --audio-format mp3"
alias resize="magick mogrify -resize"
alias md2pdf="pandoc -f markdown -t pdf"
alias md2html="pandoc -f markdown -t html -s"
alias md2docx="pandoc -f markdown -t docx"

# -- Python (uv) -------------------------------------------------------------
# No `pip` alias. Bare `pip` is not installed, so the alias only redirected muscle
# memory — and it redirected badly: `pip install X` became `uv pip install X`,
# which fails with "No virtual environment found" and reads like a broken Python
# setup. `uv pip …` is one word longer and unambiguous. (`pip3` does exist, inside
# Homebrew's python@3.14 that 20 other formulae depend on; ~/.config/pip/pip.conf
# is what keeps it from installing globally by accident.)
alias venv="uv venv"
alias pyrun="uv run"

# -- Global Justfile ----------------------------------------------------------
alias gj="just --justfile ~/.justfile --working-directory ."

# -- Dev & Testing ------------------------------------------------------------
alias watchrun="watchexec --exts ts,tsx --restart"
alias lint-sh="shellcheck"
alias fmt-sh="shfmt -w -i 4"

# -- Terminal Apps ------------------------------------------------------------
alias prog="progress -m"
alias clip="clipse"    # clipboard-history TUI (replaces Raycast clipboard)
alias nerdlog="nerdlog --set transport=ssh-bin"  # honor the generated OpenSSH config

# -- Dracula theming for tools that theme via env/flags (config-file tools themed elsewhere) --
alias claws="claws --read-only"         # safe default; use `command claws` for writes
export D2_THEME=200                     # d2 diagrams — dark theme (d2 has no exact Dracula; 200 = Dark Mauve)
export D2_DARK_THEME=200

# -- Terminal search helpers --------------------------------------------------
# ff: find a file by name and open it
ff() {
  local file
  file=$(fd --type f --hidden --exclude .git 2>/dev/null \
         | fzf --prompt='files ❯ ' --header='↩ open file • ctrl-/ preview' --preview 'bat --color=always {} 2>/dev/null | head -100') \
    && [[ -n "$file" ]] && open "$file"
}
# rgf: live content search (ripgrep + fzf with a bat preview)
rgf() {
  rg --line-number --no-heading --color=always "${1:-}" 2>/dev/null \
    | fzf --ansi --delimiter=: --prompt='matches ❯ ' --header='live code matches' \
          --preview 'bat --color=always {1} --highlight-line {2} 2>/dev/null'
}
# s: Spotlight-index search from the terminal
s() { mdfind "$@"; }

# -- Database -----------------------------------------------------------------
alias hq="harlequin"

# -- Directory Shortcuts (using zoxide for smart jumping) --------------------
alias cw="z ~/Code/work"
alias cper="z ~/Code/personal"
alias coss="z ~/Code/oss"
alias clearn="z ~/Code/learning"
alias cscratch="z ~/Code/work/scratch"
alias cscripts="z ~/Scripts"

# -- Helper Script Shortcuts --------------------------------------------------
alias nproj="new-project"
alias cwork="clone-work"
alias cpers="clone-personal"
alias dotback="backup-dotfiles"
alias pstats="project-stats"
alias cleandl="clean-downloads"
alias hc="health-check"
alias sshsetup="setup-ssh"
alias brewsnap="export-brewfile"

# -- System -------------------------------------------------------------------
alias update="topgrade"
alias sysinfo="fastfetch"

fi

# -- mise, last word on PATH --------------------------------------------------
# Activated once in ~/.zshenv (so non-interactive shells and agents get it) and AGAIN
# here, last, because ordering is the whole point (#343).
#
# ~/.zshenv runs BEFORE ~/.zprofile and ~/.zshrc. So `brew shellenv` in ~/.zprofile, the
# gnubin loop, ~/.local/bin, ~/Scripts/bin and $PNPM_HOME all prepended themselves ahead
# of mise afterwards. The result was a shell that disagreed with itself: an interactive
# login shell served Homebrew's node 26.8.1 while `mise current node` reported the
# 24.18.1 this script pins, and a non-interactive shell served mise's. Which `npm` ran —
# and therefore which global node_modules tree `npm install -g` wrote into — came down
# to whether the shell was a login shell.
#
# Re-activating here puts mise back in front, so its managed runtimes — currently
# Node and Python — resolve consistently in both kinds of shell. `mise activate`
# registers its precmd hook with `add-zsh-hook`, which is idempotent for a given function name,
# so running it twice does not double-fire it.
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# -- Terminal Welcome Screen --------------------------------------------------
# Show the managed Dracula-Sakura system dashboard in interactive terminals.
# Editor-integrated terminals stay quiet. If fastfetch is unavailable, retain a
# compact themed identity and workspace fallback instead of a date-only greeting.
if [[ -o interactive ]] && [[ "$TERM_PROGRAM" != "vscode" ]] && [[ -z "$INSIDE_EMACS" ]]; then
    if command -v fastfetch &>/dev/null; then
        fastfetch
    else
        printf "\n\033[38;2;255;121;198m  ✦ %s@%s\033[0m\n" \
            "${USER:-developer}" "${HOST%%.*}"
        printf "\033[38;2;189;147;249m  workspace\033[0m  \033[38;2;248;248;242m%s\033[0m\n" \
            "${PWD/#$HOME/~}"
        printf "\033[38;2;139;233;253m  shell\033[0m      \033[38;2;248;248;242mzsh %s\033[0m\n\n" \
            "$ZSH_VERSION"
    fi
fi

MANAGED_ZSHRC
[[ "$DRY_RUN" == "true" ]] || success "$HOME/.zshrc managed block written (edits outside the markers are kept)"

fi  # shell

# =============================================================================
banner "Brewfile Snapshot"

BREWFILE_DIR="$HOME/.config/brewfile"
BREWFILE="$BREWFILE_DIR/Brewfile"

if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would export a Brewfile snapshot to $BREWFILE"
else
mkdir -p "$BREWFILE_DIR"
info "Exporting Brewfile snapshot (with descriptions)..."
brew bundle dump --file="$BREWFILE" --force --describe 2>/dev/null || true
success "Brewfile exported to $BREWFILE"
echo "  -> Restore on a new machine: brew bundle install --file=$BREWFILE"
fi  # DRY_RUN (#380)

# -----------------------------------------------------------------------------
# Final Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Setup complete — machine ready"
echo "=========================================="
echo ""
info "Configured highlights:"
echo "  [~/.zshrc]              Shell config (auto-written with managed block)"
echo "  [~/.ssh/config]         SSH multiplexing, keychain, keep-alive"
echo "  [~/.gitignore_global]   Global gitignore (.DS_Store, .env, node_modules)"
echo "  [~/.gitconfig]          Git aliases, rebase, delta, difftastic"
echo "  [~/.gnupg/]             GPG with pinentry-mac"
echo "  [~/.npmrc]              save-exact, no telemetry"
echo "  [~/.editorconfig]       Cross-editor consistency"
echo "  [~/.prettierrc]         Global Prettier defaults"
echo "  [~/.curlrc]             Follow redirects, retry, compression"
echo "  [~/.docker/daemon.json] BuildKit, log rotation"
echo "  [~/.aria2/aria2.conf]   16 connections, auto-resume"
echo "  [~/.config/starship]    Dracula-Sakura prompt"
echo "  [~/.config/atuin]       Fuzzy search, local-only"
echo "  [~/.config/mprocs]      Multi-process TUI defaults + per-proc logs"
echo "  [~/.config/broot]       Broot git-aware defaults and Dracula-Sakura skin"
echo "  [~/.jqp.yaml]           jq playground theme overrides"
echo "  [~/.omp/agent]          OMP settings, LSP policy, model routing, theme, and path guard"
echo "  [~/.agents/skills]      Curated skills Oh My Pi reads natively"
echo "  [Application Support/Kiro]  Kiro defaults and named Dracula-Sakura theme"
echo "  [~/.config/croft]       Croft defaults and native Dracula-Sakura theme"
echo "  [Application Support/emeraldian]  User-owned defaults and native Dracula-Sakura theme"
echo "  [Obsidian vaults]       Per-vault Dracula-Sakura theme and appearance defaults"
echo "  [~/.herald]             Herald email/calendar config and Dracula-Sakura theme"
echo "  [~/.config/eilmeldung] Dracula-Sakura RSS reader theme"
echo "  [~/.config/concord]    Keychain credentials and Dracula-Sakura theme"
echo "  [~/.config/spotatui]   User-owned Dracula-Sakura music player seed"
echo "  [~/.config/cfait]      User-owned local-first task manager seed"
echo "  [llama.cpp]             Vulkan local model server on 127.0.0.1:8081"
echo "  [~/.local/share/llama.cpp]  Verified Qwen2.5 Coder GGUF model"
echo "  [leaf]                  Terminal Markdown previewer (live watch, fuzzy picker, Mermaid)"
echo "  [~/.config/yt-dlp]      Best quality, aria2c downloader"
echo "  [~/.config/gh-dash]     GitHub dashboard, Dracula-Sakura theme"
echo "  [~/.config/zellij]      Modern terminal multiplexer with Dracula-Sakura theme"
echo "  [~/.config/mpv]         Video player (hardware accel, save position)"
echo "  [Mullvad]               VPN app, bundled CLI, and source-built mullvad-tui"
echo "  [~/Media/photos/dracula-sakura.jpg]  Dracula-Sakura wallpaper asset"
echo "  [cliamp]                Music player (self-configured; point at ~/Media/music)"
echo "  [~/.justfile]           Global task runner recipes (run them with: gj --list)"
echo "  [~/.config/brewfile]    Brewfile snapshot for reproducibility"
echo "  [~/.config/micro]       micro — Dracula, on-screen key menu, house indent rules"
echo "  [lazygit]               Dracula-Sakura theme, delta pager"
echo "  [Finder]                Hidden files, path bar, list view"
echo "  [macOS]                 Dock, keyboard, screenshots, Spotlight hotkey, Stage Manager"
echo ""
info "Optional Chrome extensions (manual install):"
echo "  - axe DevTools (accessibility testing)"
echo "  - React Developer Tools"
echo "  - JSON Formatter"
echo ""
info "Terminal and search:"
echo "  - cmd+space           open Spotlight (log out/in after migration)"
echo "  - ff                  find and open a file"
echo "  - rgf <pattern>       live code/content search    s <q>  Spotlight-index search"
echo "  - clip                clipboard history (clipse)"
echo ""
info "Chezmoi quickstart (bring dotfiles under version control):"
echo "  chezmoi init                          # Initialize"
echo "  chezmoi add ~/.zshrc                  # Track dotfiles"
echo "  chezmoi cd && git remote add origin <repo>  # Link to git repo"
echo "  chezmoi update                        # Pull on new machine"
echo ""
info "A few useful next moves:"
echo "  - Keep ~/Desktop empty — use 'ff' / 's' (mdfind) to find files from the terminal"
echo "  - Disable iCloud Desktop & Documents: System Settings > Apple ID > iCloud > iCloud Drive > Options"
echo "  - watchexec: watch files with 'watchexec --exts ts,tsx -- npm test'"
echo "  - pv: add progress bars with 'pv largefile.tar.gz | tar xz'"
echo ""
# =============================================================================
# GENERATE DESKTOP DOCS (checklist, shortcuts, toolkit summary)
# Regenerated from these heredocs on every run.
# =============================================================================
if [[ "$DRY_RUN" != "true" ]]; then
    DESKTOP="$HOME/Desktop"
    mkdir -p "$DESKTOP"
    info "Writing setup docs to ~/Desktop..."

    # ---- 1. POST_SETUP_CHECKLIST.md ----
    cat > "$DESKTOP/POST_SETUP_CHECKLIST.md" <<'CHECKLIST_EOF'
# Post-Setup Checklist

Complete the manual permissions, credentials, and account steps after the script finishes.

## macOS permissions and settings
- [ ] Log out, then log in to apply the restored Spotlight shortcuts and visible menu bar.
- [ ] Open Kitty and confirm the Dracula-Sakura palette and JetBrains Mono Nerd Font.
- [ ] Select `~/Media/photos/dracula-sakura.jpg` in System Settings if you want the bundled wallpaper.

## Local inference
- [ ] Run `curl -s http://127.0.0.1:8081/v1/models | jq` to confirm the llama.cpp service.
- [ ] Run `llama-server --list-devices` and confirm that the output lists a Vulkan device.
- [ ] Set `GEMINI_API_KEY` before you use OMP roles that route to Gemini.
- [ ] Run `omp models llama.cpp` to confirm that OMP discovers Qwen2.5 Coder.

## Accounts and keys
- [ ] Run `gh auth login` to enable the GitHub issue and pull request workflow.
- [ ] Run `aws configure sso` or `aws configure` before you use AWS tools.
- [ ] Run `atuin register` to enable optional encrypted shell-history synchronization.
- [ ] Run `ngrok config add-authtoken <TOKEN>` before you create public tunnels.
- [ ] Run `herald --demo`, then run `herald` to configure email and calendar accounts.
- [ ] Run `mullvad account login <ACCOUNT_NUMBER>`, then open `mullvad-tui`.
- [ ] Open Kiro and confirm that **Dracula-Sakura** is the selected color theme.
- [ ] Sign in to Bitwarden.
- [ ] Select the dark Bitwarden appearance.
- [ ] Run `concord`.
- [ ] Complete the Discord login.
- [ ] Run `eilmeldung`.
- [ ] Run `emeraldian` to open the most recent Obsidian vault.
- [ ] Run `watchtower` to choose a location and optional model provider.
- [ ] Select an RSS provider.
- [ ] Open the Firefox theme page at `https://draculatheme.com/firefox`.
- [ ] Install the theme in the Firefox profile.
- [ ] Open each registered Obsidian vault and confirm Dracula-Sakura under Settings > Appearance > Themes.

## Services and storage
- [ ] Configure repositories and Keychain credentials in `~/.config/borgmatic/config.yaml`.
- [ ] Run `borgmatic create --dry-run` before you schedule automatic backups.
- [ ] Run `chezmoi init <repository>` before you place generated configuration under version control.
- [ ] Place music under `~/Media/music`, then run `cliamp ~/Media/music`.
- [ ] Open Docker Desktop once to install its required privileged helper.
- [ ] Run `chamber init` to create the first encrypted local vault.
- [ ] Run `spotatui` and select a music source.
- [ ] Run `cfait` to open its local task collection.

## Standard machine setup
- [ ] Generate an SSH key with `ssh-keygen -t ed25519 -C "you@example.com"` if required.
- [ ] Add the public key with `gh ssh-key add ~/.ssh/id_ed25519.pub`.
- [ ] Enable FileVault and the macOS firewall in System Settings.
CHECKLIST_EOF

    # ---- 2. KEYBOARD_SHORTCUTS.md ----
    cat > "$DESKTOP/KEYBOARD_SHORTCUTS.md" <<'SHORTCUTS_EOF'
# Keyboard Shortcuts

A compact map of the highest-frequency keys and commands this setup wires in.
This is the **quick card**, deliberately kept to one screen.

> The full reference is `docs/SHORTCUTS.md` in the dev-setup repository.
> It includes zellij, lazygit, lazydocker, micro, lnav, and mpv.

## Search and clipboard
| Keys / command | Action |
|------|--------|
| `cmd + space` | Open Spotlight for application, file, and web search |
| `ff` | Find a file by name and open it |
| `rgf <pattern>` | Live code/content search (ripgrep + fzf) |
| `s <query>` | Spotlight-index search (mdfind) |
| `clip` | Clipboard history (clipse) |

## micro — the `$EDITOR` (non-modal)
Every binding is on screen: the **key menu** sits along the bottom, and there are no modes.
| Keys | Action |
|------|--------|
| `Ctrl + s` | Save · `Ctrl + q` quit |
| `Ctrl + g` | Full help / key reference |
| `Ctrl + e` | Command bar (`> set …`, `> replace …`) |
| `Ctrl + o` | Open file · `Ctrl + w` next split |
| `Ctrl + f` | Find · `Ctrl + n` next match |
| `Ctrl + z` | Undo · `Ctrl + y` redo |
| `Ctrl + c/v/x` | Copy / paste / cut (system clipboard) |
| `Alt + click` | Add a cursor · `Ctrl + d` select next occurrence |

## AI tools
| Tool | Use |
|------|-----|
| `omp` | Primary coding agent with hosted roles and local Vulkan fallback |
| Kiro | Native project editor with the generated Dracula-Sakura theme |
| `llama-server` | Local Qwen2.5 Coder endpoint on `127.0.0.1:8081` |

## Terminal multiplexer & tools
| Keys | Action |
|------|--------|
| `Ctrl + r` | atuin history search (fuzzy, across machines) |
| `Ctrl + t` | fzf file finder · `Alt + c` fzf cd |
| zellij `Ctrl + p` then `n` | New pane. zellij is **modal**: press a mode key, then act |
| zellij mode keys | `Ctrl + p` pane · `Ctrl + t` tab · `Ctrl + n` resize · `Ctrl + s` scroll · `Ctrl + o` session · `Ctrl + g` lock (toggles) |
| lazygit / lazydocker / lazynpm / lazyssh / lazyrsync | Full-screen TUIs (arrows + on-screen keys) |
| `y` Yazi | File manager |
| `br` Broot | Directory browser that keeps shell directory changes |
| `mullvad-tui` | Terminal controller for the Mullvad VPN app and daemon |
| `cliamp` | Terminal music player (Winamp-style) — playback, EQ, cycle visualizers |
| `posting` | HTTP client TUI with git-friendly YAML collections |
| `caligula` | Disk imaging TUI with write verification |
| `nerdlog` | Multi-host log viewer through OpenSSH |
| `cha` | Terminal web browser and pager |
| `claws` | Broad AWS TUI with a read-only shell default |
| `eilmeldung` | RSS reader with vim-style navigation |
| `concord` | Discord client with Keychain token storage |
| `cfait` | Local-first task manager |
| `emeraldian` | Obsidian vault TUI with backlinks, graph, and an optional assistant |
| `watchtower` | Global news, markets, weather, and intelligence dashboard |
| `chamber` | Local encrypted secrets vault and terminal interface |
| `spotatui` | Multi-source terminal music player |

SHORTCUTS_EOF

    # ---- 3. TOOLKIT_SUMMARY.md ----
    cat > "$DESKTOP/TOOLKIT_SUMMARY.md" <<'SUMMARY_EOF'
# Toolkit Summary

This terminal-first macOS setup keeps development, automation, and local inference accessible from the keyboard.

The setup installs a Dracula-Sakura wallpaper at `~/Media/photos/dracula-sakura.jpg`.

## Editor and AI
- **micro** is the primary editor for files and commit messages.
- **Kiro** provides a native project editor with practical Code OSS defaults.
- **OMP** provides coding-agent tools, hosted model roles, and a local fallback.
- **llama.cpp** serves Qwen2.5 Coder 14B through Vulkan on `127.0.0.1:8081`.

## Terminal and search
- **Kitty** provides the GPU-accelerated terminal with the Dracula-Sakura theme.
- **Spotlight** provides global application, file, and web search.
- **zellij** provides panes, tabs, and persistent terminal sessions.
- `ff`, `rgf`, `s`, and `clip` provide file, search, and clipboard access.
- **Broot** provides tree navigation through the directory-changing `br` launcher.
- **atuin**, **starship**, **fzf**, and **zoxide** improve shell history, prompts, search, and navigation.

## Development workflow
- **lazygit**, **gh**, and **scc** support GitHub workflows and repository maintenance.
- **Posting**, **xh**, and **Hurl** support API development.
- **harlequin** and **usql** provide database clients.
- **d2** provides diagrams as code.
- **LibreOffice** and **poppler** support visual checks of Office documents.
- **Draw.io** provides a local desktop diagram editor.
- **Croft** provides a terminal IDE with LSP, debugging, source control, and PDF previews.
- **Herald** provides terminal email and calendar access.
- **eilmeldung** provides RSS reading with a managed Dracula-Sakura palette.
- **concord** provides Discord access with Keychain token storage.
- **cfait** provides local-first tasks with optional CalDAV synchronization.
- **Emeraldian** provides a themed Obsidian vault TUI with graph and backlink views.
- **Watchtower** provides a global news, markets, and weather dashboard.
- **Caligula** provides verified disk imaging with compressed-image support.
- **Nerdlog** provides multi-host log viewing through OpenSSH.
- **Chawan** provides terminal web browsing and paging with private defaults.
- **Claws** provides broad read-only AWS resource inspection by default.

## Data, media, and storage
- **Yazi** provides file management, previews, and bulk tasks.
- **eza**, **bat**, **fd**, **ripgrep**, **dust**, **duf**, and **sd** replace common file utilities.
- **cliamp** and **spotatui** provide music playback.
- **aria2** manages downloads.
- **rclone**, **borg**, and **borgmatic** provide synchronization and backups.

## Infrastructure and security
- **Docker Desktop**, **lazydocker**, and **dive** support container workflows.
- **awscli**, **granted**, **checkov**, and **trivy** support cloud infrastructure.
- **gitleaks** and **age** protect repository secrets.
- **Bitwarden** and **chamber** provide encrypted secret storage.
- **LuLu** provides the remaining graphical network security control.
- **Mullvad VPN**, its bundled CLI, and **mullvad-tui** provide VPN control.

## Configuration flow
The script writes managed configuration under `~/.config` and tool-specific directories.
Use **chezmoi** and **cheznav** to place selected files under version control.
Terminal tools remain usable in local and SSH shell sessions, subject to the
remote terminal's capabilities.

## Full tool reference
See **TOOL_REFERENCE.md** for commands and examples for the principal installed tools.
SUMMARY_EOF

    # ---- 4. TOOL_REFERENCE.md ----
    cat > "$DESKTOP/TOOL_REFERENCE.md" <<'REFERENCE_EOF'
# Tool Reference

This long-form field guide covers the principal command-line tools, TUIs, and apps
that the setup installs. The entries are grouped by use and include current command
examples, so a freshly provisioned machine remains legible.

**How to read this:** headings show the command you actually type (e.g. `rg`,
not "ripgrep"). Where a tool replaces a classic command, that's called out.
Some tools are aliased over the classic name — see the table just below.

- Curated highlights of the whole setup: **TOOLKIT_SUMMARY.md**
- Keyboard shortcuts & click actions: **KEYBOARD_SHORTCUTS.md**
- Manual steps the script can't do (credentials, permissions): **POST_SETUP_CHECKLIST.md**

## Modern replacements (aliased over the classic command)

Your shell aliases these classic commands to modern equivalents — type the name
on the left, get the tool on the right. Each is documented in full in its
section below.

| Type… | …and you get | For |
|-------|--------------|-----|
| `cat` | **bat** | syntax-highlighted file printing (use `/bin/cat` in heredocs) |
| `ls` | **eza** | icons, git status, tree view |
| `ps` | **procs** | sortable, tree, docker-aware process list |
| `du` | **dust** | visual disk-usage tree |
| `df` | **duf** | colorful disk-free table |
| `top` | **btop** | graphed system monitor |
| `rm` | **trash** | moves to macOS Trash (recoverable) |
| `ping` | **gping** | live latency graph |
| `dig` | **doggo** | colorized DNS, DoH |
| `watch` | **viddy** | diff-highlighted repeated runs |

> These aliases are **interactive only**. Scripts and AI agents get the real
> POSIX commands, because none of the replacements accept the original's flags
> (`du -sh` prints dust's help, `ps aux` silently ignores `aux`). `rm` is the one
> exception — it still routes to Trash everywhere, and accepts `-r`/`-f`.
>
> Tools without a classic-name alias, reached by their own names: **sd**
> (find & replace — its own syntax, *not* a sed drop-in), **zoxide** (`z`/`zi`
> for frecency jumping; plain `cd` is untouched), **aria2c** (`dl`),
> **rg**, **fd**. `bat`, `eza`, `dust`, `duf`, `btop` and `procs` are covered in
> their categories below.


## Editors, AI & the shell

### `micro` — micro
A non-modal terminal editor with familiar save, quit, copy, and paste keys. It is the primary editor for files and commit messages.

```bash
# open a file
micro src/main.rs
# jump straight to a line
micro src/main.rs +42
# open the command bar inside the editor, e.g. > set tabsize 4
```

> Configured with the Dracula theme, the key menu on, 2-space indents (4 for Python, real tabs for Go and Makefiles), and trailing whitespace stripped on save. Change anything from inside the editor with `> set <option> <value>` — it persists to `~/.config/micro/settings.json`, and re-running the setup script merges new defaults without discarding your changes.

### `omp` — Oh My Pi
The primary coding agent includes LSP, DAP, subagents, memory, and workload-routed models. Hosted providers fall back to the local Vulkan runtime.
Automatic reasoning handles ordinary turns. Usage-aware fallback preserves 10 percent of coding-plan quotas and returns to the primary model after cooldown.

```bash
# start a session
omp
# what the nine roles resolve to (a record — read it whole)
omp config get modelRoles
# where the active agent directory is
omp config path
# one-shot, no session
omp -p "summarise the diff on this branch"
```

> Tip: omp's config lives under `~/.omp/agent/`, not `~/.config`. It reads four scoped skills from `~/.agents/skills/`: `api-testing`, `d2-diagrams`, `inspect-machine`, and `office-layout-check`. The `protected-paths.ts` extension guards native file mutations to sensitive paths. Its `AGENTS.md` outranks other user-level context files. Settings merge into `config.yml` because omp writes that file.
>
> `web_search` includes selectable provider backends. This setup configures `http://127.0.0.1:8080`
> as the preferred SearXNG endpoint but does not install or manage that service.
> Keyless backends remain available if the endpoint is unavailable.
> Paste the API keys into `ANTHROPIC_API_KEY=` and `GEMINI_API_KEY=` in `~/.omp/agent/.env`.
> OMP loads this file directly.
>
> The final fallback is `llama.cpp/qwen2.5-coder:14b`, served locally through Vulkan.

### `llama-server` — Vulkan Local LLM Runtime
The setup builds llama.cpp v0.4.0 with Vulkan enabled and Metal disabled.
MoltenVK translates Vulkan operations to Metal on macOS.
The login service exposes Qwen2.5 Coder 14B on `127.0.0.1:8081`.
OMP discovers the server through `LLAMA_CPP_BASE_URL`.

```bash
# List the model that the local server exposes.
curl -s http://127.0.0.1:8081/v1/models | jq
# Send a direct completion request.
curl -s http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-coder:14b","messages":[{"role":"user","content":"Hello"}]}' | jq
```

### `starship` — Starship Prompt
A fast, cross-shell prompt written in Rust that shows contextual info — git branch/status, language versions, exit codes — without the lag some frameworks introduce. It replaces heavier prompt frameworks (like Powerlevel10k or Oh My Posh) with a single static binary and a TOML config. You mostly don't invoke it directly; it's wired into your shell init and just renders on every prompt.

```bash
# edit the prompt configuration
micro ~/.config/starship.toml
# print current config as a starting point
starship print-config
```

> Tip: `starship explain` shows which modules are active and why, which is the fastest way to debug a slow or cluttered prompt.

### `atuin` — Atuin
Replaces plain zsh history with a searchable SQLite database that records timestamps, exit codes, and duration for every command, with optional end-to-end-encrypted sync across machines. It's a major upgrade over `ctrl+r`'s default fuzzy history search, which has no concept of context or success/failure. It's bound to `Ctrl+r` in this setup, so muscle memory carries over — you just get a much richer search experience.

```bash
# search history interactively (same as pressing Ctrl+r)
atuin search
# see stats on your most-used commands
atuin stats
# import existing zsh history into atuin's database
atuin import auto
```

> Tip: `atuin search --exit 0` filters to only commands that succeeded — handy when hunting for "that command that actually worked."

### `z` — Zoxide
A smarter `cd` that learns which directories you visit most often and how recently (a "frecency" score), so you can jump to them with a short fuzzy fragment instead of a full path. It replaces plain `cd` for anywhere you go regularly, cutting deep `cd ~/Code/personal/some-project` typing down to a couple of letters. It builds its database automatically just by you `cd`-ing around normally.

```bash
# jump to the best match for "dev-setup"
z dev-setup
# jump to a directory matching two fragments
z code personal
# list tracked directories with their scores
zoxide query -l
```

> Tip: Use plain `cd` for a path you'll only visit once — `z` learns from every jump, so one-off detours pollute its rankings.

### `zellij` — Zellij
A terminal multiplexer that provides panes, tabs, and persistent sessions. It shows key bindings and supports project-specific layouts.

```bash
# Start a session.
zellij
# list running sessions
zellij list-sessions
# reattach to a detached session
zellij attach <session-name>
```

> Tip: `Ctrl+g` locks/unlocks keybinding mode — if keys stop doing anything inside a pane, you've probably entered a plugin's own input mode.

### `mprocs` — Multi-Process TUI
A terminal UI for running several long-lived development processes at once — app server, frontend watcher, tests, worker — with each command's output in its own pane instead of interleaved in one scrollback. Use it when a project normally costs you three terminal tabs just to boot the stack.

```bash
# run a few commands directly
mprocs "npm run dev" "npm test -- --watch"
# run the processes declared in ./mprocs.yaml
mprocs
# load scripts from package.json without starting them automatically
mprocs --npm
```

> Tip: this setup writes a global `~/.config/mprocs/mprocs.yaml` with sane scrollback and per-process logging, while a project-local `mprocs.yaml` overrides it whenever you need a real stack definition.

### `direnv` — direnv
Automatically loads and unloads environment variables per-directory based on an `.envrc` file, so project-specific secrets, API keys, or `PATH` additions apply only while you're inside that directory and vanish when you leave. It replaces manually sourcing `.env` files or juggling global exports for project-specific config. Use it for anything that needs local env vars — database URLs, per-project tool versions, feature flags — without leaking them into your global shell.

```bash
# create a project-local env file
echo 'export API_KEY=dev-key-123' > .envrc
# approve it (required before direnv will load it)
direnv allow
# edit and re-approve in one step
direnv edit .
```

> Tip: direnv refuses to load an `.envrc` you haven't explicitly `allow`ed — it's a deliberate guard against silently executing shell code from a repo you just cloned.

### `gum` — Gum
A toolkit of small interactive UI components — prompts, spinners, confirmations, single/multi-select menus, text input — for making plain shell scripts feel like real CLI tools instead of `read`-and-hope. It replaces hand-rolled `select` loops and bare `read` prompts with polished, themeable widgets that still just output plain text you can capture. Reach for it any time a script needs to ask the user something.

```bash
# ask for confirmation before a destructive action
gum confirm "Delete all build artifacts?" && rm -rf dist/
# let the user pick from a list
gum choose "staging" "production" "dev"
# show a spinner while a long command runs
gum spin --title "Installing..." -- npm install
```

> Tip: Because gum's output is just text on stdout, you can capture a choice directly into a variable: `env=$(gum choose staging production)`.


### `topgrade` — Topgrade
A single command that updates everything on the machine — Homebrew formulae and casks, npm/pnpm global packages, mise-managed runtimes, macOS system updates, shell plugins, and more — instead of remembering and running a dozen separate update commands. It replaces a personal checklist (or a stale update script) with one tool that knows how to detect and update each package manager it finds installed. Run it periodically as routine maintenance.

```bash
# update everything topgrade can detect
topgrade
# preview what would run without making changes
topgrade --dry-run
# skip a specific step
topgrade --disable brew
```

> Tip: Run `--dry-run` first on a new machine — the full run touches a lot of package managers at once and it's worth knowing what it'll do.

### `fastfetch` — fastfetch
Prints a fast system-info summary — OS, kernel, shell, terminal, CPU, memory — often alongside an ASCII/image logo, purely for a quick at-a-glance snapshot of the machine. It's the modern, much faster successor to neofetch (which is now unmaintained). Most people drop it into their shell startup for a nice banner, or run it manually when reporting a bug that needs system details.

```bash
# print the system info banner
fastfetch
# run without the logo, for a compact/scriptable view
fastfetch --logo none
```

> Tip: Piping `fastfetch --logo none` output into a bug report is a fast way to give someone your exact environment without typing it out by hand.

### `vivid` — Vivid
Generates `LS_COLORS` theme strings from named color schemes (including Dracula, matching this setup's theme), so directory listings from `ls` and `eza` color files consistently by type and extension. It replaces hand-writing or copy-pasting a `LS_COLORS` string, which is famously unreadable and tedious to customize by hand. You typically run it once during shell setup and export the result.

```bash
# generate a Dracula LS_COLORS string
vivid generate dracula
# export it directly into the current shell
export LS_COLORS="$(vivid generate dracula)"
# list available built-in themes
vivid themes
```

> Tip: Put the `export LS_COLORS="$(vivid generate dracula)"` line in `.zshrc` so it's set once per shell rather than regenerated on every command.

### `clip` — Clipse
A TUI clipboard-history manager — it keeps a scrollable, searchable history of things you've copied so you can grab something from three copies ago instead of losing it the moment you copy again. It replaces the single-slot macOS clipboard with a proper history, similar to what tools like Maccy or Alfred's clipboard manager provide, but terminal-native. This setup binds it to the `clip` command; run it any time you need to paste something older than your last copy.

```bash
# open the clipboard history TUI
clip
```

> Tip: Inside the TUI, typing filters the history live — no need to scroll manually through a long list of old copies.

### zsh-autosuggestions — [—]
Shows a faint, greyed-out inline suggestion as you type, based on your command history and completions — press the right arrow (or `End`) to accept it, similar to fish shell's autosuggestions. It replaces the need to retype or history-search commands you've run before; it just proposes the likely rest of the line as you go. It loads automatically with this shell setup — there's no command to invoke, only keys to accept or ignore what it suggests.

```bash
# start typing a previously-run command...
git comm
# ...then press the right arrow key to accept the suggested rest: "git commit -m ..."
```

> Tip: Accept only part of a suggestion with `Alt+f` (forward-word) instead of the full line with `End`, if you just want the next word.

### zsh-syntax-highlighting — [—]
Colorizes the command line as you type it — valid commands turn one color, unknown commands or syntax errors turn another (usually red) — so you catch a typo'd binary name or an unclosed quote before you hit enter. It replaces the "type it, run it, read the error" loop with instant visual feedback. Like zsh-autosuggestions, it loads automatically; there's nothing to invoke, just something to notice while typing.

```bash
# a known, valid command highlights normally
ls -la
# a typo'd or nonexistent command is visibly flagged (e.g. in red) before you press enter
lsx -la
```

> Tip: If highlighting looks wrong after installing a new CLI tool, open a fresh shell — it caches known commands at shell start.


## Finding, files & disk

### `bat` — Syntax-Highlighted `cat`
A `cat` replacement with syntax highlighting, line numbers, git change markers, and automatic paging. Aliased over `cat` interactively; scripts and AI agents get the real POSIX `cat`, and you want `/bin/cat` inside heredocs where exact bytes matter.

```bash
# view a file with highlighting and line numbers
bat src/main.ts
# plain output, no decorations — safe to pipe
bat -p config.json
# force a language when the extension does not give it away
bat -l yaml deploy.txt
# show only lines changed against git
bat --diff src/main.ts
```

> `--style=plain,numbers,changes` picks exactly which decorations appear. `bat --config-dir` prints where its config lives, which is the reliable way to find it rather than guessing a path.

### `eza` — Modern `ls`
A colourful `ls` with icons, git status per file, and a built-in tree mode. Aliased over `ls` interactively, with `ll`, `la`, and `lt` for the common shapes.

```bash
# long listing with git status
eza -l --git
# everything, including dotfiles
eza -la
# tree view, three levels deep
eza --tree --level=3
# directories first, with icons
eza -l --icons --group-directories-first
```

### `dust` — Visual Disk Usage
A `du` replacement that prints a sorted, bar-charted tree of what is actually consuming space, biggest first, with no flag archaeology.

```bash
# what is using space here
dust
# limit how deep the tree goes
dust -d 2
# a specific directory
dust ~/Code
# smallest first
dust -r
```

> `du -sh` in an interactive shell prints **dust's help**, not a size, because the alias does not accept `du`'s flags. Use `/usr/bin/du -sh` when you want the classic behaviour.

### `duf` — Disk Free, Readable
A `df` replacement that groups devices sensibly and renders usage bars instead of a wall of blocks. Note its flags are **single-dash**, Go style, not GNU style.

```bash
# all mounted filesystems, grouped
duf
# only local disks
duf -only local
# hide the noisy special filesystems
duf -hide special
# machine-readable
duf -json
```

### `zoxide` — Frecency Directory Jumping
Learns the directories you visit and lets you jump by fragment. It **adds** `z` and `zi`; plain `cd` is left completely untouched, so nothing you already do changes.

```bash
# jump to the best match for "proj"
z proj
# match on two fragments
z code work
# interactive picker over the database
zi
# inspect what it has learned
zoxide query -l
```

### `sd` — Find and Replace
A find-and-replace tool with sane syntax: no escaping a regex twice, no `-i ''` portability trap. It is **not** a `sed` drop-in — the syntax is its own, and it does not do `sed`'s stream-editing commands.

```bash
# replace across a file, in place
sd 'oldName' 'newName' src/app.ts
# preview the change without writing it
sd -p 'oldName' 'newName' src/app.ts
# literal strings, no regex interpretation
sd -F '1.2.3' '1.3.0' README.md
# across many files, via fd
fd -e ts -x sd 'oldName' 'newName'
```

> `-A/--across` lets a pattern match across line boundaries, which plain `sed` cannot do without contortions.

### `fzf` — Fuzzy Finder
A general-purpose interactive fuzzy finder that filters any list of lines from stdin — files, history, process names, git branches, whatever you pipe into it. It replaces manually scrolling or grepping through long lists, letting you type a few loose characters and instantly narrow down to the match you want. In this setup it's wired into the shell: Ctrl+T fuzzy-inserts a file path, Alt+C fuzzy-cd's into a directory, and Ctrl+R fuzzy-searches command history (via atuin). Reach for it any time you'd otherwise pipe something into `grep` and eyeball the result.

```bash
# fuzzy-filter piped input interactively
fd . | fzf
# preview file contents while selecting
fzf --preview 'bat --color=always {}'
# open the fuzzy-selected file in your editor
micro $(fzf)
```

> Tip: Ctrl+T (insert file path), Alt+C (cd into directory), and Ctrl+R (search shell history) work anywhere at the prompt without typing `fzf` explicitly.

### `rg` — ripgrep
A drop-in replacement for `grep` that recursively searches file contents by default, is dramatically faster on large trees, and automatically skips files ignored by `.gitignore`. Use it whenever you need to find where a string, function name, or pattern appears across a codebase — it's the default "search code" tool here. It supports regex, file-type filters, and context lines out of the box.

```bash
# search recursively for a string in the current directory
rg "TODO"
# case-insensitive search restricted to Python files
rg -i -t py "def main"
# list only filenames that contain a match
rg -l "deprecated"
```

> Tip: `rg -t rg --type-list` shows all supported file-type filters (`-t py`, `-t js`, etc.).

### `fd` — fd
A friendlier, faster replacement for `find`: simple syntax (no `-name`, no leading `.`), colorized output, respects `.gitignore`, and skips hidden files unless asked. Use it to locate files or directories by name pattern instead of wrestling with `find`'s flags. It composes well with `fzf` and `xargs`-style execution via `-x`.

```bash
# find files matching a name pattern
fd config
# find only files with a given extension
fd -e md
# include hidden/ignored files in the search
fd -H -I node_modules
# run a command against each match
fd -e log -x rm
```

### `ast-grep` — ast-grep
A structural code search-and-replace tool that matches against a language's actual syntax tree instead of raw text, so it understands code shape (function calls, imports, JSX) rather than just character patterns. It replaces fragile regex-based codemods — reach for it when you need to rewrite a pattern like `console.log($ARG)` across a whole repo without false positives inside strings or comments.

```bash
# find all console.log calls in JS/TS files
ast-grep run -p 'console.log($$$ARGS)' -l js
# rewrite a pattern across the codebase
ast-grep run -p 'var $NAME = $VAL' -r 'let $NAME = $VAL' -l js
# run a project's configured ast-grep rules
ast-grep scan
```

### `yazi` — Yazi
Yazi is a fast terminal file manager with previews, fuzzy search, bulk operations, and asynchronous file tasks. The `y` wrapper preserves Yazi's final directory in the parent shell.

```bash
# launch Yazi in the current directory
y
# launch Yazi in a specific directory
y ~/Downloads
```

Press `q` to quit and change the parent shell directory. Press `Q` to quit without changing it.

### `ouch` — ouch
A single tool for compressing and decompressing archives that auto-detects the format from the file extension, so you don't need to remember whether a given archive needs `tar`, `zip`, `unzip`, or `7z`. Reach for it as the default "just compress/extract this" command instead of picking the right tool per format.

```bash
# compress a directory into a .zip
ouch compress project/ project.zip
# extract any supported archive format
ouch decompress project.zip
# list the contents of an archive without extracting
ouch list project.zip
```

### `rsync` — rsync
An incremental file-copy and sync tool that only transfers the parts of files that changed, making it far faster than `cp` for large trees or repeated transfers, and it works both locally and over SSH. It's the go-to for syncing project directories, backing up folders, or deploying files to a remote server. `-a` (archive) preserves permissions, timestamps, and symlinks.

```bash
# sync a local directory, preserving attributes
rsync -avh src/ dest/
# sync to a remote host over SSH
rsync -avz src/ user@host:/remote/dest/
# sync and delete files at the destination that no longer exist at the source
rsync -av --delete src/ dest/
```

> Tip: always keep the trailing slash on the source directory (`src/`) if you want its *contents* copied into `dest/` rather than `dest/src/`.

### `rclone` — rclone
Often described as "rsync for cloud storage" — it syncs, copies, and manages files across dozens of cloud backends (Google Drive, S3, Dropbox, and more) using the same mental model as `rsync`. Use it for backing up local folders to the cloud, mirroring buckets, or moving files between cloud providers without downloading them to your machine first.

```bash
# interactively configure a new cloud remote
rclone config
# sync a local folder to a configured remote
rclone sync ~/Documents remote:Documents
# list files in a remote path
rclone ls remote:Documents
```

### `miniserve` — miniserve
Spins up an instant HTTP file server for the current (or a given) directory — no config, no setup — so you can quickly share files with another device on the network or test static content. Reach for it when you need to grab a file from your phone, hand a teammate a quick download link, or sanity-check a static site build.

```bash
# serve the current directory over HTTP
miniserve .
# serve on a specific port
miniserve . -p 8080
# allow browser-based file uploads into the served directory
miniserve . --upload-files
```

### `monolith` — monolith
Saves a complete web page — HTML, CSS, JavaScript, and images — as a single self-contained `.html` file with everything inlined, so the page still renders correctly when opened offline with no external requests. Use it to archive a web page or documentation article exactly as it appeared, for offline reading or long-term reference.

```bash
# save a page as a single self-contained HTML file
monolith https://example.com -o page.html
# save without executing embedded JavaScript
monolith -j https://example.com -o page.html
```

### `pv` — pipe viewer
Inserted into a shell pipeline, `pv` shows a live progress bar, throughput, and ETA for the data flowing through it — something a plain pipe gives you zero visibility into. Use it when copying, compressing, or transferring large amounts of data through pipes and you want to know it's actually moving (and how much longer it'll take).

```bash
# show progress while copying a large file
pv bigfile.iso > /dev/null
# monitor throughput while piping into gzip
tar cf - mydir | pv | gzip > archive.tar.gz
# specify a known total size for an accurate ETA
pv -s 4G bigfile.iso | ssh host 'cat > bigfile.iso'
```

### `progress` — progress
Unlike `pv`, which you insert into a pipeline in advance, `progress` inspects an *already-running* coreutils command (`cp`, `mv`, `dd`, `tar`, etc.) and reports its progress and ETA after the fact. Use it when you forgot to wrap a long-running copy in `pv` and just want to know how far along it is.

```bash
# show progress of currently running cp/mv/dd/tar commands
progress
# continuously refresh progress until the command finishes
progress -w
```

### `watchexec` — watchexec
Watches a set of files or directories and automatically re-runs a command whenever something changes — the general-purpose engine behind test-watch and rebuild-on-save loops, independent of any specific language's tooling. Use it to build a live test-runner or dev-rebuild loop for a project that doesn't have its own watch mode.

```bash
# re-run tests whenever a .py file changes
watchexec -e py -- pytest
# watch a specific directory and rebuild on change
watchexec -w src -- npm run build
# clear the screen before each re-run
watchexec --clear -- npm test
```

### `trash` — trash
A safe drop-in replacement for `rm` that moves files to the macOS Trash instead of permanently deleting them, so a mistyped command doesn't mean unrecoverable data loss. Use it as your default delete command for anything you're not 100% sure about — you can still empty the Trash normally when you're done.

```bash
# move a file to the Trash instead of deleting it
trash file.txt
# trash multiple files with a glob
trash *.tmp
# verbose output showing what was trashed
trash -v old-project/
```

> Tip: `trash` is aliased over `rm` in this setup — plain `rm` still works, but `trash` is the recoverable default.

## Data, Git & GitHub

### `jq` — JSON Processor
A command-line JSON processor that lets you filter, transform, and reshape JSON using a small, powerful query language. It's the standard tool for slicing API responses or config files in a pipeline without writing a script. Reach for it whenever you need to extract a field, filter an array, or reformat JSON on the fly.

```bash
# extract a field from every element of an array
curl -s api.example.com/users | jq '.[].name'
# filter objects matching a condition
jq '.items[] | select(.active == true)' data.json
# reshape into a new object
jq '{id: .id, total: (.price * .qty)}' order.json
```

> Tip: `jq -r` strips the surrounding quotes from string output, handy for feeding results into shell loops.

### `yq` — YAML Processor
The "jq for YAML" — Mike Farah's Go implementation lets you read, edit, and convert YAML with jq-style syntax, without the footguns of Python-based yq clones. It's essential for editing Kubernetes manifests, CDK-synthesized templates, or CloudFormation YAML from the command line. Use it anywhere you'd reach for jq but the file is YAML.

```bash
# read a nested value
yq '.spec.replicas' deployment.yaml
# update a value in place
yq -i '.spec.replicas = 3' deployment.yaml
# convert YAML to JSON
yq -o=json '.' deployment.yaml
```

> Tip: `yq` merges multi-document YAML (`---` separated) by default — use `eval-all` for filters that need to see every document at once.

### `jc` — Command Output to JSON
A converter that takes the output of many classic Unix commands and turns it into structured JSON, which makes old text-shaped tools much easier to pipe into `jq`, scripts, or AI workflows. Reach for it when the command you need exists already, but its default output is annoying to parse safely.

```bash
# convert ps output to JSON
ps aux | jc --ps | jq '.[0]'
# convert df output to JSON
df -h | jc --df | jq '.[].filesystem'
# convert dig output to JSON
/opt/homebrew/bin/dig example.com | jc --dig
```

### `fx` — Interactive JSON Viewer
An interactive terminal JSON viewer for browsing large or unfamiliar JSON payloads — collapsible tree navigation instead of squinting at jq output. It's the better choice over jq when you don't yet know the shape of the data and want to explore it visually before writing a filter. Great for poking at a big API response for the first time.

```bash
# explore an API response interactively
curl -s api.example.com/data | fx
# open a file directly
fx package.json
# run a quick inline reducer
cat data.json | fx 'this.items.length'
```

> Tip: press `.` inside fx to start typing a JS-style path and see the result live.

### `jnv` — Interactive JSON Navigator
An interactive JSON navigator that lets you build a jq filter incrementally while previewing the filtered output live, side by side. Where fx is for browsing, jnv is for composing the actual jq query you'll eventually script — you leave with a working filter, not just an answer. Use it when a jq one-liner isn't obvious and you want to iterate visually.

```bash
# open a file and build a filter interactively
jnv data.json
# pipe JSON in from a command
curl -s api.example.com/data | jnv
```

> Tip: once you land on the right filter, copy it out and drop it straight into a jq command for scripting.

### `jqp` — jq Playground TUI
A TUI for experimenting with `jq` filters against live JSON or NDJSON input. Compared with `jnv`, which is about interactively arriving at a useful filter, `jqp` feels more like a focused jq workbench — query editor, live output, themeable UI — and is especially nice when you already think in jq but want a less blind feedback loop.

```bash
# open a file in the playground
jqp -f data.json
# stream API output into it
curl -s api.example.com/data | jqp
# start with an initial jq query
jqp '.items[] | {name, id}' -f data.json
```

> Tip: this setup writes `~/.jqp.yaml` with a Dracula-Sakura-flavored override layer on top of jqp's built-in Dracula theme, so it matches the rest of the terminal palette.

### `csvstat` [csvkit: csvcut/csvgrep/csvjson] — CSV Utility Suite
A suite of small Unix-style utilities for working with CSV files: cutting columns, grepping rows, computing summary stats, and converting to JSON or SQL. It brings classic Unix text-tool ergonomics to tabular data that plain grep/cut mangle because of quoting and commas. Reach for it for quick, composable CSV inspection without opening a spreadsheet.

```bash
# summary stats for every column
csvstat data.csv
# select specific columns by name
csvcut -c name,email data.csv
# filter rows matching a pattern in a column
csvgrep -c status -m active data.csv
# convert CSV to JSON
csvjson data.csv > data.json
```

### `git` — Version Control System
The distributed version control system underlying the whole trunk-based workflow — branches, commits, merges, and history. In this setup it's configured with delta as the diff pager, difftastic available for structural diffs, and commit signing enabled. Every change here starts with a feature branch and ends in a squash-merged PR.

```bash
# check working tree status
git status
# stage and commit with a conventional message
git add src/auth.ts && git commit -m "feat(auth): add login page"
# create and switch to a short-lived feature branch
git switch -c feature/add-oauth
# view history through the configured delta pager
git log -p
```

### `gh` — GitHub CLI
The official GitHub CLI for managing pull requests, issues, releases, and repo settings without leaving the terminal. It's central to this PR-first workflow — `gh pr create` opens the PR, and the project's `gh pm` alias squash-merges and deletes the branch in one step. Reach for it anywhere you'd otherwise open github.com.

```bash
# create a pull request referencing an issue
gh pr create --title "feat(auth): add login" --body "Closes #42"
# list open issues
gh issue list
# check out a PR locally to review it
gh pr checkout 123
# squash-merge and delete the branch (project alias)
gh pm
```

### `lazygit` — Terminal UI for Git
A full-screen terminal UI for git that turns staging, committing, branching, rebasing, and pushing into keyboard-driven panels instead of memorized flags. It's the fast path for everyday git work — interactive rebases and partial-file staging are far quicker here than in raw git. Launch it inside any repo when you want a visual overview of what's changed.

```bash
# launch the TUI in the current repo
lazygit
# launch it pointed at a different repo path
lazygit -p ~/Code/other-repo
```

> Tip: press `p` to stage individual hunks/lines interactively instead of whole files.

### `delta` [git-delta] — Syntax-Highlighting Diff Pager
A syntax-highlighting pager for git diffs that renders side-by-side views with line numbers, replacing git's plain-text diff output. It's wired in here as git's default pager, so `git diff` and `git log -p` are readable by default — no extra flags needed day to day. Call it directly when piping a diff from somewhere else.

```bash
# pipe a diff through delta directly
git diff | delta
# compare two arbitrary files
delta file_old.py file_new.py
```

### `difft` [difftastic] — Structural Diff Tool
A structural, syntax-aware diff tool that compares parsed syntax trees instead of raw text lines, so it doesn't get confused by reformatting or reordered code that a line-based diff would flag as a huge change. Reach for it when a normal diff is noisy — e.g., after a formatter run — and you want to see what actually changed logically.

```bash
# compare two files structurally
difft old.py new.py
# use it as git's diff tool for one command
git difftool --extcmd=difft HEAD~1
```

### `git-absorb` [git absorb] — Automatic Fixup Commits
Automatically figures out which earlier commit your currently staged changes belong to and creates a matching `fixup!` commit, instead of you manually hunting through history and running `git commit --fixup`. It's built for the "oops, small fix belongs in an earlier commit on this branch" moment before a PR is opened. Follow it with an autosquash rebase to actually fold the fixups in.

```bash
# stage your fix, then let absorb find its target commit
git absorb
# preview what would be absorbed without committing
git absorb --dry-run
# fold the fixup commits into their targets
git rebase -i --autosquash main
```

### `pre-commit` — Git Hook Framework
A framework for managing git pre-commit hooks — linters, formatters, secret scanners — declared in a single `.pre-commit-config.yaml` instead of hand-rolled shell scripts in `.git/hooks`. It installs and runs a whole toolchain of checks automatically before each commit, and the config is versioned with the repo so every contributor gets the same hooks. Set it up once per project, then forget about it.

```bash
# install the hooks defined in .pre-commit-config.yaml
pre-commit install
# run all configured hooks against the whole repo
pre-commit run --all-files
# update hook versions to their latest releases
pre-commit autoupdate
```

**`pre-commit install` refuses to run on this machine**, and the error does not explain itself:

```
[ERROR] Cowardly refusing to install hooks with `core.hooksPath` set.
```

This setup points `core.hooksPath` at `~/.config/git/hooks` (global hooks that run in every
repo). `pre-commit` will not write into `.git/hooks` while that is set, because git would
normally ignore what it wrote. Here it would not — the global hooks **delegate** to the
per-repo hook of the same name — but `pre-commit` has no way to know that. Unset it for the
length of the install:

```bash
saved=$(git config --global --get core.hooksPath)
git config --global --unset core.hooksPath
pre-commit install --install-hooks
git config --global core.hooksPath "$saved"
```

The hooks it writes then run normally, chained after the global checks.

### `scc` — Source Code Counter
Counts lines of code by language across a codebase, along with cyclomatic complexity and COCOMO cost/effort estimates — a much faster, more informative replacement for `cloc` or `wc -l`. Use it to get a quick sense of a new codebase's size and language mix, or to track complexity trends over time. It's fast enough to run on large monorepos without waiting.

```bash
# get a full breakdown of the current project
scc .
# sort output by complexity instead of line count
scc --sort complexity .
# output machine-readable JSON for other tooling
scc --format json .
```


## HTTP, APIs & networking

### `xh` — Friendly HTTP Client
A fast, HTTPie-compatible HTTP client written in Rust. It replaces `curl` for everyday API poking with colorized, JSON-first output, sensible defaults (assumes `https://`, sends/parses JSON automatically), and simple `key=value` syntax for bodies. Reach for it when testing or debugging a REST API from the terminal.

```bash
# GET request with colorized JSON output
xh https://api.example.com/users
# POST a JSON body using key=value pairs
xh POST https://api.example.com/users name=Ada role=admin
# download a file to disk
xh --download https://example.com/file.zip
# verbose mode: show the full request and response
xh -v POST httpbin.org/post foo=bar
```

> Tip: use `:=` instead of `=` for non-string JSON values, e.g. `xh POST url active:=true count:=3`.

### `hurl` — HTTP Requests as Testable Text Files
Runs and tests HTTP requests written in plain-text `.hurl` files, chaining multiple requests and asserting on status codes, headers, and body/JSON content. Because tests are just text files, they version well in git and drop straight into CI — no client library or GUI required.

```bash
# run a .hurl file and print the last response body
hurl request.hurl
# run as a test suite; exits non-zero on any failed assertion
hurl --test api-tests.hurl
# inject a variable into the requests
hurl --variable base_url=https://staging.example.com api.hurl
# run a whole test suite and generate an HTML report
hurl --test --report-html report/ tests/*.hurl
```

### `posting` — Terminal HTTP Client
Posting builds and sends HTTP requests from a keyboard-driven interface. It stores collections as git-friendly YAML files.

The seed uses a compact layout and hides secret values. It does not expose the host environment to requests.

```bash
# open the request workspace
posting
# inspect the active config and theme paths
posting locate config
posting locate themes
```

The custom theme covers the interface, syntax colors, URLs, variables, and HTTP methods.


### `ngrok` — Public HTTPS Tunnel to Localhost
Exposes a port on your local machine as a public HTTPS URL, so you can share a dev server, test webhooks from a third-party service, or demo something running locally. Requires a free account and an authtoken configured once via `ngrok config add-authtoken`.

```bash
# tunnel local port 3000 to a public https URL
ngrok http 3000
# tunnel a specific local host:port
ngrok http 127.0.0.1:8080
# use a reserved endpoint URL
ngrok http 3000 --url https://myapp.ngrok.app
```

> Tip: ngrok prints a local web UI at `http://127.0.0.1:4040` where you can inspect and replay every request that hit the tunnel.

### `mkcert` — Locally-Trusted TLS Certificates
Creates TLS certificates that your browser and OS actually trust for local development, by installing a local certificate authority (CA) into your system trust store. It replaces self-signed certs (and the browser warnings that come with them) when you need HTTPS on `localhost` or a local dev domain.

```bash
# install the local CA into system/browser trust stores (one-time)
mkcert -install
# generate a cert+key for localhost
mkcert localhost
# generate a cert covering multiple names/IPs
mkcert localhost 127.0.0.1 myapp.local
```

### `carbonyl` — Chromium in the Terminal
A real Chromium browser rendered entirely inside the terminal, including images, CSS, JavaScript, and video. It supports full pages over SSH or in headless environments.

```bash
# open a URL in the terminal browser
carbonyl https://example.com
```

### `cha` [Chawan] — Terminal Web Browser
Chawan is a terminal browser and pager with CSS, JavaScript, and Kitty image support.

The config disables cookies, referrers, and scripting by default. It uses the Dracula-Sakura true-color display.

```bash
# open a page in the browser
cha https://example.com
# render a page to standard output
cha -d https://example.com
# browse a local HTML file
cha ./notes.html
```

### `trip` [trippy] — Traceroute + Ping TUI
Combines traceroute and ping into a single live TUI, charting latency and packet loss per network hop over time so you can see where a connection is degrading, not just a one-shot snapshot. Needs raw sockets, so it runs elevated by default (`sudo`) unless `--unprivileged` is supported and used.

```bash
# trace a target with the interactive TUI (needs sudo)
sudo trip example.com
# trace without elevated privileges, where supported
trip example.com --unprivileged
# trace using TCP to a specific port (e.g. through firewalls that block ICMP)
sudo trip example.com -p tcp -P 443
# generate a one-shot pretty text report instead of the live TUI
sudo trip example.com -m pretty
```

### `gping` — Ping with a Live Graph
Pings one or more hosts and plots the results as a live latency graph in the terminal, instead of a scrolling list of numbers. It's aliased over `ping` in this setup, so typing the familiar command gets you the graph.

```bash
# ping one host with a live latency graph
gping example.com
# compare multiple hosts on the same graph
gping example.com 1.1.1.1 8.8.8.8
# set the interval between pings
gping --watch-interval 0.5 example.com
```

### `doggo` — Modern DNS Client
A modern replacement for `dig` with colorized, human-readable tabular output by default (with JSON available for scripting), plus support for encrypted DNS protocols (DNS-over-HTTPS/TLS). It's aliased over `dig` here, so the familiar habit gets the friendlier output.

```bash
# look up A records for a domain
doggo example.com
# query a specific record type
doggo example.com MX
# query against a specific resolver
doggo example.com @1.1.1.1
# machine-readable output for scripts
doggo --json example.com A | jq '.responses[0].answers[].address'
```


### `nmap` — Network Scanner
The standard network scanner for host discovery, port scanning, and service/version detection. Use it to find what's alive on a network, which ports are open on a host, and what software is listening on them — common for auditing your own infrastructure or debugging connectivity.

```bash
# discover live hosts on a subnet
nmap -sn 192.168.1.0/24
# scan the common ports on a host
nmap example.com
# detect service and version info on open ports
nmap -sV example.com
# scan a specific port range
nmap -p 1-1000 example.com
```

> Tip: some scan types (e.g. `-sS` SYN scans) need `sudo` for raw socket access; a plain `-sV` connect scan usually doesn't.

### `ssh-audit` — SSH Configuration Auditor
Connects to an SSH server (or inspects a client config) and reports which key exchange, cipher, and MAC algorithms it offers, flagging weak or deprecated ones against current best practices. Use it to check your own servers aren't offering outdated crypto before they go anywhere near the internet.

```bash
# audit a server's SSH configuration on the default port
ssh-audit example.com
# audit a non-standard port
ssh-audit example.com -p 2222
# output results as JSON for scripting/CI
ssh-audit --json example.com
```

### `lazyssh` — TUI SSH Connection Manager
A keyboard-driven TUI for browsing, searching, and connecting to hosts defined in `~/.ssh/config`. It replaces memorized addresses and long `ssh` commands while keeping OpenSSH in control of keys and credentials.

```bash
# launch the TUI (lists hosts from ~/.ssh/config)
lazyssh
```

> Tip: press `a` inside the TUI to add a new host profile through a guided form (alias, host/IP, user, port, identity file) — there's no CLI flag for adding hosts, it's TUI-only.

### `duckdb` — Local Analytics Database
An in-process analytical SQL engine for local data work — query CSV, JSON, and Parquet directly with SQL, join files together, and run serious aggregations without provisioning a server. It fills the gap between text-first tools like `jq`/`mlr` and a full external database, and pairs especially well with `harlequin` for a richer interactive surface.

```bash
# start an interactive SQL session
duckdb
# query a CSV file directly
duckdb -c "select count(*) from read_csv_auto('data.csv');"
# query JSON directly
duckdb -c "select * from read_json_auto('events.json') limit 5;"
```

### `harlequin` — Harlequin SQL IDE
A full SQL IDE that runs in your terminal as a TUI, with a results grid, schema browser, and query editor. It connects to DuckDB (its default), Postgres, MySQL, SQLite, and S3-hosted data via adapter plugins, replacing the need to open a heavyweight desktop DB client just to poke around. Reach for it when you want to interactively explore or query a database without leaving the terminal.

```bash
# open (or create) a local DuckDB file
harlequin mydata.db
# connect to Postgres via the postgres adapter
harlequin -a postgres "postgres://user:pass@localhost:5432/mydb"
# connect to MySQL via the mysql adapter
harlequin -a mysql -h localhost -p 3306 -U user --database mydb
```

> Tip: run `harlequin --help` after installing an adapter — each one adds its own connection flags.

### `usql` — Universal SQL CLI
One CLI that speaks to many databases through one consistent connection URL and command interface. Use it for cross-engine scripts and quick queries.

```bash
# connect to Postgres
usql pg://user@localhost/mydb
# connect to a local SQLite file
usql sqlite:./local.db
# run one query non-interactively and exit
usql pg://user@localhost/mydb -c "select count(*) from users;"
```

### `dbmate` — Database Migrations
A lightweight, framework-agnostic schema migration tool that works with plain `.sql` up/down files instead of a language-specific DSL. It reads the target database from a `DATABASE_URL` environment variable, so it fits into any stack without pulling in an ORM's migration system. Use it to version-control and apply schema changes consistently across environments.

```bash
# point dbmate at your database
export DATABASE_URL="postgres://user:pass@localhost:5432/mydb?sslmode=disable"
# scaffold a new migration file
dbmate new create_users
# apply all pending migrations
dbmate up
# undo the most recent migration
dbmate rollback
```

### `lazydocker` — Lazy Docker TUI
A full-screen terminal UI for Docker: browse containers, images, volumes, and Compose stacks, tail logs, and view live stats, all navigable with the keyboard. It's the Docker equivalent of `lazygit` — far faster than repeatedly typing `docker ps` / `docker logs` / `docker stats` by hand. Launch it from any project directory to manage whatever's running there.

```bash
# launch the TUI; auto-detects a docker-compose.yml in the current directory
lazydocker
# point it at a specific compose file
DOCKER_COMPOSE_FILE=./docker/docker-compose.yml lazydocker
```

> Tip: press `d` on a container to remove it, `[`/`]` to switch panels — check the in-app help (`?`) for the full keymap.

### `dive` — Docker Image Layer Explorer
Inspects a Docker image layer-by-layer, showing exactly what each layer added and how much space is wasted by duplicated or unnecessary files. It's the tool for shrinking bloated images and understanding *why* an image is as large as it is, beyond what `docker history` shows. It can also run non-interactively in CI to fail a build that regresses on image efficiency.

```bash
# analyze an existing image interactively
dive myimage:latest
# build an image and analyze it in one step
dive build -t myimage:latest .
# non-interactive CI mode: pass/fail on efficiency thresholds
CI=true dive myimage:latest
```

> Tip: add a `.dive-ci` file to your repo root to set the efficiency and wasted-space thresholds used in CI mode.

### `hadolint` — Dockerfile Linter
A linter purpose-built for Dockerfiles that flags anti-patterns like missing version pins, unnecessary layers, and insecure practices, backed by Docker's own best-practice rules. It catches issues `docker build` won't warn you about. Run it before building any image, ideally wired into pre-commit or CI.

```bash
# lint a Dockerfile
hadolint Dockerfile
# ignore a specific rule you've deliberately chosen not to follow
hadolint --ignore DL3008 Dockerfile
# emit machine-readable output for CI
hadolint -f json Dockerfile
```

### `trivy` — All-in-One Security Scanner
A single scanner covering container images, filesystems, and IaC misconfigurations, replacing the need for separate tools per concern (it absorbed what `tfsec` used to do, now available via `trivy config`). It's usually the first thing to run before pushing an image or applying infrastructure changes. Use it in CI as a gate against known CVEs and misconfigurations.

```bash
# scan a container image for vulnerabilities
trivy image myimage:latest
# scan the local filesystem/project
trivy fs .
# scan IaC (Terraform, Kubernetes manifests, Dockerfiles) for misconfigurations
trivy config .
```

### `cosign` — Container Signing
Signs and verifies container images and other artifacts as part of a software supply-chain security practice, built around the Sigstore project. It lets you (and downstream consumers) cryptographically confirm an image came from you and hasn't been tampered with. Reach for it when publishing images you want consumers or a cluster admission controller to trust.

```bash
# generate a signing key pair
cosign generate-key-pair
# sign an image with your private key
cosign sign --key cosign.key myimage:latest
# verify an image's signature with the public key
cosign verify --key cosign.pub myimage:latest
```

> Tip: `cosign sign myimage:latest` without `--key` does keyless signing via OIDC (e.g. GitHub Actions identity) — no key management needed.


### `aws` [awscli] — AWS CLI
The official command-line interface for every AWS service, used both directly and as the foundation many other AWS tools (like `granted` and `session-manager-plugin`) build on. It's how you configure credentials, inspect resources, and script anything AWS from the terminal. Nearly every AWS workflow starts or ends with an `aws` command.

```bash
# set up SSO-based login
aws configure sso
# list objects in an S3 bucket
aws s3 ls s3://mybucket
# describe EC2 instances using a specific profile
aws ec2 describe-instances --profile myprofile
# confirm which identity/role is currently active
aws sts get-caller-identity
```

### `assume` — Granted (AWS SSO Role Switching)
Granted's `assume` command makes switching between AWS SSO profiles and roles fast — it exports temporary credentials for a chosen profile straight into your current shell instead of you hand-editing `~/.aws/credentials` or juggling `--profile` flags everywhere. It also has a browser-console mode for when you just want to click around in the AWS Console. Reach for it constantly if you work across multiple AWS accounts/roles.

```bash
# fuzzy-search and assume a profile, exporting creds into this shell
assume
# assume a specific named profile directly
assume myprofile
# open the AWS web console for a profile instead of exporting creds
assume myprofile -c
```

> Tip: `assume myprofile -c -s ec2` opens the console directly on a specific service (EC2 in this case).

### `cdk` — AWS CDK CLI
The command-line tool for the AWS Cloud Development Kit — synthesizes CloudFormation templates from infrastructure defined in real code (TypeScript, Python, etc.) and deploys them. It replaces hand-written CloudFormation/YAML with type-checked, reusable infrastructure code. Use it for any AWS infrastructure project defined via CDK.

```bash
# scaffold a new CDK app
cdk init app --language typescript
# synthesize CloudFormation templates without deploying
cdk synth
# preview what would change before deploying
cdk diff
# deploy a specific stack
cdk deploy MyStack
```

### `sam` — AWS SAM CLI
Builds, locally tests, and deploys AWS serverless applications (Lambda, API Gateway, Step Functions, etc.) defined with the Serverless Application Model. Its standout feature is local invocation and API emulation — you can run a Lambda function or an entire API locally in a Docker container before ever deploying. Use it for serverless projects where fast local iteration matters.

```bash
# scaffold a new serverless app
sam init
# invoke a single function locally
sam local invoke MyFunction
# run a local API Gateway emulator for the whole app
sam local start-api
# deploy, prompting for any missing config
sam deploy --guided
```

### `cfn-lint` — CloudFormation Linter
Validates CloudFormation templates against the actual AWS resource specification and a large set of best-practice rules, catching errors like invalid property names or type mismatches long before a deploy fails. It's much more thorough than CloudFormation's own template validation. Run it on any hand-written or CDK-synthesized CloudFormation template before deploying.

```bash
# lint a single template
cfn-lint template.yaml
# lint every template in a directory
cfn-lint templates/*.yaml
# ignore a specific rule
cfn-lint --ignore-checks W3011 template.yaml
```

### `steampipe` — Cloud Infrastructure via SQL
Lets you query live cloud infrastructure — AWS resources, and many other sources — using plain SQL, powered by a Postgres foreign-data-wrapper engine under the hood. It's excellent for inventory audits, posture checks, and ad hoc "which resources have X" questions that would otherwise mean scripting the AWS CLI plus `jq`. Requires installing a plugin for whichever provider you're querying.

```bash
# install the AWS plugin (one-time setup)
steampipe plugin install aws
# open the interactive SQL query shell
steampipe query
# run a single query directly
steampipe query "select instance_id, instance_type from aws_ec2_instance"
```

> Tip: `steampipe query` results are just SQL, so you can join across services — e.g. correlate IAM roles with the EC2 instances that use them.

### `s5cmd` — Fast S3 Client
A massively parallel S3 client that's 10–30x faster than `aws s3` for bulk copy and sync operations, because it parallelizes transfers far more aggressively. Reach for it whenever you're moving large numbers of objects or large volumes of data in or out of S3 and `aws s3 sync` feels too slow.

```bash
# copy a single file to S3
s5cmd cp localfile.txt s3://mybucket/path/
# sync a local directory to S3 in parallel
s5cmd sync ./localdir s3://mybucket/path/
# list objects in a bucket
s5cmd ls s3://mybucket/
```

### `stu` — S3 TUI
A terminal UI for browsing S3 buckets, previewing objects, and downloading files, without needing the AWS Console or scripting `aws s3` commands. It behaves like the AWS CLI in terms of credential resolution — it just picks up your default profile or environment variables. Use it when you want to visually explore what's in a bucket rather than list-and-grep.

```bash
# launch and browse using your default AWS profile
stu
# connect using a specific named profile
stu --profile myprofile
# jump straight into a specific bucket
stu --bucket mybucket
```

### `e1s` — ECS TUI
A terminal UI for Amazon ECS resources. Browse clusters, services, and tasks, exec into containers, and tail logs without chaining `aws ecs describe-*` commands.

```bash
# launch using your default AWS profile/region
e1s
# launch against a specific profile
e1s --profile myprofile
# launch against a specific region
e1s --region us-east-1
```

### `e2c` — EC2 TUI
A terminal UI for Amazon EC2 instances. View state and details, then start, stop, reboot, terminate, or connect through SSH. It complements `e1s` for instance-level work.

```bash
# launch using default credentials/region
e2c
# launch against a specific region
e2c --region us-east-1
```

> Tip: set `AWS_PROFILE` in your shell to point `e2c` at a non-default profile.

### `dy` — Dynein (DynamoDB CLI)
An ergonomic DynamoDB CLI from AWS Labs that gives you shorthand commands for common table and item operations, plus import/export, instead of the verbose JSON-heavy syntax of `aws dynamodb`. Use it for quick interactive exploration and scripting against DynamoDB tables.

```bash
# list tables in the current region
dy ls
# list tables across every AWS region
dy ls --all-regions
# scan a table
dy scan -t my-table
```

### `claws` — Broad AWS TUI
Claws provides one terminal interface for approximately 70 AWS services.

The generated config selects the Dracula preset and applies Sakura color overrides. The shell alias starts Claws in read-only mode.

```bash
# inspect resources with writes disabled
claws
# bypass the alias for an intentional write session
command claws
```

### `iamlive` — IAM Policy Generator
Watches the AWS API calls your application or script actually makes and generates a least-privilege IAM policy from that observed traffic, instead of you guessing which permissions are needed. It runs either as a local HTTPS proxy or via AWS's client-side monitoring (CSM) protocol. Use it while running a script or app to derive the minimal IAM policy it truly needs, rather than over-granting.

```bash
# start in proxy mode (set HTTPS_PROXY to iamlive's bind address to capture calls)
iamlive --mode proxy
# start in CSM mode instead (AWS-only, captures actions but not resource ARNs)
iamlive --mode csm
```

> Tip: proxy mode captures full resource ARNs for a tighter policy; CSM mode only captures actions with wildcard resources.

### `session-manager-plugin` — SSM Session Manager Plugin
A plugin for the AWS CLI that enables `aws ssm start-session`, letting you open an interactive shell or port-forward to an EC2 instance without SSH keys, bastion hosts, or open inbound ports. It's not invoked directly — it's automatically used by the `aws ssm` subcommands once installed. Use it whenever you need shell access or a tunnel into a private instance managed by SSM.

```bash
# open an interactive shell on an instance, no SSH required
aws ssm start-session --target i-0123456789abcdef0

# forward a local port to a port on the remote instance
aws ssm start-session --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["5432"],"localPortNumber":["15432"]}'
```


### `terraform-docs` — Module Documentation Generator
Auto-generates Markdown documentation of a Terraform module's inputs, outputs, providers, and resources directly from the code, so module docs do not drift. Use it to keep each module README accurate.

```bash
# generate a markdown table and write it to a new file
terraform-docs markdown table --output-file README.md .
# inject/update generated docs between markers in an existing README
terraform-docs markdown table --output-file README.md --output-mode inject .
```

> Tip: add `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers to a README so `--output-mode inject` knows where to update.

### `checkov` — IaC Static Analysis
Runs static analysis over infrastructure-as-code — Terraform, CloudFormation, Kubernetes manifests, Dockerfiles — against hundreds of built-in security and compliance policies. It catches misconfigurations like overly permissive IAM policies or unencrypted storage before they're ever applied. Run it as a pre-deploy gate alongside `trivy config`.

```bash
# scan the current directory (auto-detects IaC type)
checkov -d .
# scan a single file
checkov -f template.yaml
# scan only Terraform resources in a directory
checkov -d . --framework terraform
```



## Security, testing, runtimes & backups

### `gitleaks` — Gitleaks
Scans a git repo's full history (or a directory, or staged changes) for hardcoded secrets like API keys and tokens using regex/entropy rules. It replaces manually grepping for leaked credentials and catches what got committed before you noticed. Run it locally before pushing, or wire it into pre-commit/CI to block leaks automatically.

```bash
# scan a repo's full git history
gitleaks detect --source . -v
# scan only staged changes (pre-commit hook)
gitleaks protect --staged -v
# write findings to a JSON report
gitleaks detect --source . --report-path gitleaks-report.json
```

> Tip: `gitleaks protect --staged` is the one to wire into a pre-commit hook — `detect` scans history, which is too slow to run on every commit.

### `semgrep` — Semgrep
A fast static analysis tool that finds bugs and security issues by matching simple, code-like pattern rules across dozens of languages — no deep AST expertise needed to write or read a rule. It's a lighter-weight alternative to heavier SAST tools, backed by a large community ruleset for OWASP-style issues. Use it in CI or before a PR to catch injection risks and common mistakes automatically.

```bash
# run with the default auto-selected ruleset for this repo
semgrep --config auto .
# run a specific curated security ruleset
semgrep --config p/security-audit .
# scan only files changed since main
semgrep scan --config p/ci --baseline-commit main
```

### `age` — age
A modern, simple file encryption tool built as a friendlier alternative to GPG — no keyring management, no web-of-trust ceremony, just a keypair or a passphrase. Generate a keypair once, then encrypt files to a recipient's public key or with a shared passphrase. Reach for it whenever you need to encrypt a file for yourself or someone else without GPG's complexity.

```bash
# generate a new keypair
age-keygen -o key.txt
# encrypt a file to a recipient's public key
age -r age1ql3z7hjy54... -o secret.age secret.txt
# decrypt with your private key
age -d -i key.txt -o secret.txt secret.age
# encrypt with a passphrase instead of a key
age -p -o secret.age secret.txt
```


### LuLu — Outbound Firewall
LuLu is a free, open-source macOS outbound firewall that watches for and blocks unexpected outbound network connections — the reverse of most firewalls, which focus on inbound traffic. It alerts the first time an app tries to phone home, letting you allow or block it, which is useful for catching malware, trackers, or apps being unexpectedly chatty. There's no CLI; everything happens through its menu-bar icon and the alert popups it shows when a new connection is attempted.

*No CLI — manage via the menu-bar icon and its connection-alert popups.*

### `just` — Just
A command/task runner that reads recipes from a `Justfile` in your project root — a simpler `make`, without tab-vs-space pitfalls or file-target semantics getting in the way. Recipes are just named shell commands, so it's a natural home for `just build`, `just test`, `just deploy` style project shortcuts. Reach for it any time a project needs a handful of common one-liners that new contributors shouldn't have to memorize.

```bash
# list all available recipes in this project's Justfile
just --list
# run the recipe named "test"
just test
# run a recipe with arguments
just deploy staging
```

**This setup also writes a global `~/.justfile`** with machine-wide recipes (`flush-dns`,
`docker-clean`, `ports`, `standup`, `loc`, `ip`, `ds-clean`, …). Plain `just` will **not** find
it — outside `$HOME` it reports `error: no justfile found`, because `just` only searches upward
from the current directory. Use the **`gj`** alias this setup provides:

```bash
# list the global recipes (works from any directory)
gj --list
# run one
gj flush-dns
gj docker-clean
```

`gj` expands to `just --justfile ~/.justfile --working-directory .`, so the recipes run against
whatever directory you are standing in. `docs/SHORTCUTS.md` lists every recipe.

### `act` — act
Runs your GitHub Actions workflows locally in Docker containers, so you can debug a CI pipeline without committing, pushing, and waiting on GitHub's runners. It reads `.github/workflows/*.yml` and simulates the triggering event locally. Reach for it while iterating on a workflow file — much faster than the push-wait-check loop.

```bash
# run the workflows triggered by a push event (the default)
act
# run only jobs triggered by pull_request
act pull_request
# list the jobs/workflows act would run, without running them
act -l
# run a specific job by name
act -j build
```

### `actionlint` — GitHub Actions Workflow Linter
A linter purpose-built for GitHub Actions workflows, catching mistakes plain YAML parsing misses: bad `${{ }}` expressions, invalid `needs` wiring, unsupported keys in the wrong place, and suspicious action references. It complements `act` nicely: actionlint finds structural/workflow bugs fast, while act helps reproduce runtime behavior locally.

```bash
# lint every workflow in the repo
actionlint
# lint a specific workflow file
actionlint .github/workflows/lint.yml
# keep shell analysis on embedded run: blocks when shellcheck is installed
actionlint -shellcheck=shellcheck
```

### `ruff` — Ruff
An extremely fast Python linter and formatter, written in Rust, that replaces flake8 (linting), Black (formatting), and isort (import sorting) with a single tool and config. It runs orders of magnitude faster than the tools it replaces, which matters on large codebases and in pre-commit hooks. Use it as the default Python linter/formatter for both one-off checks and CI.

```bash
# lint the current project
ruff check .
# lint and auto-fix what's safely fixable
ruff check --fix .
# format code (Black-compatible style)
ruff format .
```

### `shellcheck` — ShellCheck
A static analysis linter for shell scripts that catches quoting mistakes, unsafe globbing, portability issues, and other classic bash/sh footguns before they bite in production. Each warning comes with a rationale and suggested fix, which makes it genuinely useful for learning shell pitfalls, not just flagging them. Run it on any script before committing, or wire it into CI/pre-commit for shell-heavy repos.

```bash
# check a single script
shellcheck deploy.sh
# check all shell scripts in a directory
shellcheck scripts/*.sh
# output in a format editors/CI can parse
shellcheck -f json deploy.sh
```

### `shfmt` — shfmt
A gofmt-style formatter for shell scripts that enforces one consistent style (indentation, spacing, line breaks) across a codebase, removing style bikeshedding from code review. It pairs naturally with shellcheck — shfmt handles formatting, shellcheck handles correctness. Run it before committing shell scripts, or in CI to enforce a house style.

```bash
# print a formatted version of a script to stdout
shfmt deploy.sh
# format a file in place with 2-space indentation
shfmt -w -i 2 deploy.sh
# check whether files are already formatted (for CI)
shfmt -d scripts/*.sh
```

### `typos` — typos
A fast source-code spell checker tuned for low false positives on code (it understands identifiers, camelCase, etc.), catching typos in comments, strings, and docs that regular spell checkers choke on. It's designed to be safe to run unattended in CI. Add it as a pre-push or CI check to catch embarrassing typos before they ship.

```bash
# check the current directory
typos
# check and interactively fix typos
typos -w
# check a specific file or path
typos README.md
```

### `mise` — mise
A universal runtime/version manager for Node, Python, Go, Ruby, and more — one tool instead of nvm + pyenv + rbenv + gvm — plus a lightweight task runner. It reads a `.tool-versions` or `.mise.toml` file per project and switches versions automatically when you `cd` in. Reach for it any time a project needs a pinned language/runtime version or a simple project task.

```bash
# install and pin a Node version for this project
mise use node@20
# install every tool version listed in .mise.toml/.tool-versions
mise install
# list installed and active tool versions
mise ls
```

### `uv` — uv
An extremely fast Python package manager and virtual environment tool written in Rust, replacing pip, venv, and pip-tools with a single 10-100x faster binary. It also runs one-off Python tools in isolated environments without polluting a project (`uvx`). Use it for creating venvs, installing dependencies, and locking, instead of raw pip.

```bash
# create a virtual environment
uv venv
# install dependencies from requirements/pyproject
uv pip install -r requirements.txt
# run a tool in an ephemeral environment, no install needed
uvx ruff check .
```

### `yaml-py` — PyYAML Helper Python
A tiny dedicated Python interpreter with the `PyYAML` library preinstalled in its own isolated `uv` venv, exposed on PATH as `yaml-py`. It exists for the cases where you want one-off YAML parsing or a short local script without polluting the main Python runtime this setup pins via mise.

```bash
# parse a YAML file and print a field
yaml-py -c 'import pathlib, yaml; print(yaml.safe_load(pathlib.Path("config.yml").read_text())["name"])'
# turn stdin YAML into JSON-ish Python output quickly
printf 'a: 1\nb: 2\n' | yaml-py -c 'import sys, yaml; print(yaml.safe_load(sys.stdin.read()))'
```

### `go` — Go
The official Go toolchain: compiler, module/dependency manager, test runner, and formatter in one binary. It's what you use to build, run, test, and manage dependencies for any Go project — there's no separate package manager to install. Reach for it for anything Go-related.

```bash
# run a Go program without building a binary first
go run main.go
# build a binary
go build ./...
# run the test suite
go test ./...
# add/update a dependency in go.mod
go get example.com/pkg@latest
```

### `tsc` — TypeScript Compiler
The TypeScript compiler and type checker: it type-checks `.ts`/`.tsx` files and can emit compiled JavaScript. In modern setups it's often used purely for type-checking (`--noEmit`) while a separate bundler handles the actual build. Run it before a PR to catch type errors a linter alone would miss.

```bash
# type-check the project without emitting output files
tsc --noEmit
# compile according to tsconfig.json
tsc
# watch mode: re-check on every file save
tsc --noEmit --watch
```

### `tsx` — tsx
Runs TypeScript and ESM files directly with no separate build/compile step, powered by esbuild under the hood — great for scripts, small tools, or trying something quickly without setting up a bundler. It's a common drop-in replacement for `ts-node` with much faster startup. Reach for it for one-off scripts or a project's dev entrypoint.

```bash
# run a TypeScript file directly
tsx script.ts
# watch mode: re-run on file changes
tsx watch server.ts
```

### `cheznav` — cheznav
A dual-pane terminal UI for chezmoi: your home directory on one side, chezmoi-managed dotfiles on the other, with synced selection between them so you can visually add, diff, and apply dotfiles instead of remembering `chezmoi add`/`chezmoi apply` paths. Handy for a quick visual sanity check before applying changes. Requires chezmoi itself to already be set up.

```bash
# launch the TUI
cheznav
# launch in dry-run mode (no actual chezmoi changes applied)
cheznav --dry-run
```

### `borg` — BorgBackup
A deduplicated, compressed, and encrypted backup tool — because it dedupes at the chunk level, incremental backups after the first are fast and tiny even across many snapshots. It's designed for efficient offsite or local snapshot backups you can prune by retention policy. Reach for it (directly, or via borgmatic) any time you need real backups, not just a folder copy.

```bash
# initialize an encrypted backup repository
borg init --encryption=repokey /path/to/repo
# create a new backup archive
borg create /path/to/repo::'{now}' ~/Documents
# list archives in a repository
borg list /path/to/repo
# extract a named archive
borg extract /path/to/repo::2026-08-09
```

### `borgmatic` — borgmatic
A configuration and scheduling layer on top of borg: instead of remembering borg's flags, you declare sources, retention policy, and hooks in a YAML config, and borgmatic drives borg (create, prune, check) for you. It's what turns borg into a "set it and forget it" backup system, often paired with cron/launchd. Reach for it once your borg setup outgrows a couple of manual commands.

```bash
# run backup, prune, and consistency check per config
borgmatic
# create a backup only, skipping prune/check
borgmatic create
# list archives in the configured repository
borgmatic list
# restore files from the most recent archive
borgmatic extract --archive latest
```

### `chezmoi` — chezmoi
Manages your dotfiles across multiple machines from a single git-backed source directory, with templating for per-machine differences and built-in secrets integration (age, pass, 1Password, etc.) so secrets never land in the repo in plaintext. It replaces ad hoc symlink scripts or copying dotfiles by hand between machines. Reach for it to add a new dotfile, sync changes, or bring a fresh machine up to your configured state.

```bash
# add an existing dotfile to chezmoi's source state
chezmoi add ~/.zshrc
# preview what would change before applying
chezmoi diff
# apply the managed dotfiles to this machine
chezmoi apply
# pull the latest changes from git and apply them
chezmoi update
```


## Docs, media, terminal apps & extras

### `btop` — Graphed System Monitor
A `top` replacement with CPU, memory, network, and disk graphs, a searchable process list, and mouse support. Aliased over `top` interactively. It is a full TUI, so the keymap lives in the app itself rather than in any published table.

```bash
# launch it
btop
# start on a saved preset (0-9)
btop -p 1
# open already filtered to a process
btop -f node
# slower refresh, less CPU of its own
btop -u 2000
# print the default config, e.g. to seed your own
btop --default-config
```

> Press `Esc` or `F2` inside btop for its options menu; the key list is in-app only. `-t/--tty` forces 16-colour ANSI mode for terminals that need it.

### `procs` — Modern `ps`
A `ps` replacement with colourized columns, a tree mode, docker awareness, and search by name rather than by grepping the output of something else.

```bash
# a readable process list
procs
# only processes matching a name
procs node
# parent/child tree
procs --tree
# live-updating view
procs --watch
# sort descending by a column
procs --sortd cpu
```

> `ps aux` in an interactive shell **silently ignores** the `aux` argument, because the alias does not accept `ps`'s flags. Use `/bin/ps aux` when you want the classic output.

### `viddy` — Modern `watch`
A `watch` replacement that highlights what changed between runs, keeps history you can scroll back through, and can page the output. Aliased over `watch` interactively.

```bash
# re-run every 2 seconds
viddy -n 2 docker ps
# highlight the differences between runs
viddy -d docker ps
# drop the header for a clean full-screen view
viddy --no-title tail -n 40 app.log
```

> The scrollable run history is the real reason to reach for it over `watch`: you can go back and see the state three refreshes ago rather than only the latest frame.

### `d2` — Text-to-Diagram Language
A declarative diagramming language that converts plain-text boxes, arrows, and containers into SVG, PNG, or PDF. Use it for diagrams that must live and diff in a repository.

```bash
# render a .d2 file to SVG (default output)
d2 architecture.d2
# live-reload in the browser while editing
d2 --watch architecture.d2
# render to PNG using the ELK layout engine
d2 --layout elk architecture.d2 architecture.png
```

> Tip: `d2 fmt architecture.d2` reformats the source file in place.

### `pandoc` — Universal Document Converter
The Swiss-army knife of document conversion: it moves content between Markdown, HTML, Word (docx), PDF, LaTeX, EPUB, and dozens of other formats. It's the backbone of a terminal-first writing workflow — reach for it any time you need to turn a Markdown note into something you can send someone who doesn't live in a terminal.

```bash
# Markdown to a Word document
pandoc notes.md -o notes.docx
# Markdown to PDF (needs a PDF engine, e.g. tectonic)
pandoc notes.md -o notes.pdf --pdf-engine=tectonic
# standalone HTML page from Markdown
pandoc notes.md -o notes.html -s
```

> Tip: use `-f`/`-t` to force the input/output format when pandoc can't infer it from the file extension.

### `tectonic` — Self-Contained LaTeX Engine
A modern, self-contained TeX/LaTeX engine that fetches only the packages a document needs instead of requiring a multi-gigabyte TeX Live install. On a bare Mac it's what gives pandoc a PDF engine, so `pandoc ... -o out.pdf` actually works.

```bash
# compile a .tex file straight to PDF
tectonic paper.tex
# use it as pandoc's PDF engine
pandoc report.md -o report.pdf --pdf-engine=tectonic
```

### `leaf` — Terminal Markdown Previewer
A live-reloading Markdown viewer for the terminal, with a fuzzy file picker and built-in Mermaid/LaTeX rendering. It replaces switching to a browser tab or GUI previewer just to check how a document will look while you write it.

```bash
# open the fuzzy picker to browse Markdown files
leaf --picker
# preview one file with live reload on save
leaf --watch README.md
# render straight to stdout, no TUI
leaf --inline notes.md
```

> Tip: leaf is a viewer, not an editor — Ctrl+E hands the open file to your configured editor (`-e/--editor`, not `$EDITOR`, which leaf ignores).

### `pdftotext`/`pdftoppm`/`pdfinfo` — Poppler PDF Utilities
A trio of small, fast utilities built on the Poppler PDF library: `pdftotext` pulls text out of a PDF, `pdftoppm` rasterizes pages to images, and `pdfinfo` prints metadata (page count, size, producer). Reach for these when you need to script something against a PDF rather than open it in a viewer.

```bash
# extract text, preserving the original layout
pdftotext -layout report.pdf report.txt
# render each page to a PNG
pdftoppm -png report.pdf page
# print page count, size, and other metadata
pdfinfo report.pdf
```

### `soffice` — LibreOffice (Headless)
LibreOffice run in headless mode, used here purely as a conversion/validation engine rather than an interactive office suite — actual document authoring stays in Google Workspace. It's the tool of choice for batch-converting or sanity-checking `.docx`/`.xlsx`/`.pptx` files from a script.

```bash
# convert a Word doc to PDF, no GUI
soffice --headless --convert-to pdf report.docx
# convert a spreadsheet to CSV
soffice --headless --convert-to csv data.xlsx
```

> Tip: add `--outdir <path>` to control where the converted file lands.

### Draw.io
Draw.io provides local diagram editing without a browser dependency.
The application owns its preferences because it has no stable managed settings file.

```bash
# open the application
open -a draw.io
# open a diagram from the terminal
drawio architecture.drawio
```

### `magick` — ImageMagick
The all-purpose image toolkit: resize, crop, rotate, composite, convert between formats, and batch-process images from the command line. It replaces opening Preview/Photoshop for anything mechanical — resizing a folder of screenshots, converting HEIC to PNG, stitching a thumbnail.

```bash
# convert between formats
magick input.heic output.png
# resize an image to a max width, keeping aspect ratio
magick input.jpg -resize 800x output.jpg
# batch-resize every PNG in a directory
magick mogrify -resize 50% *.png
```

### `oxipng` — Lossless PNG Optimizer
Recompresses PNG files to shrink their size with zero quality loss — no visible difference, just a smaller file. It's scriptable and CI-friendly, so it's the natural choice for optimizing images before committing them to a repo or shipping them on a site.

```bash
# optimize a PNG in place at the default level
oxipng image.png
# push harder for maximum compression (slower)
oxipng -o max image.png
# optimize every PNG in a directory
oxipng -o 4 *.png
```

### `jpegoptim` — JPEG Optimizer
Shrinks JPEG file size by stripping unnecessary metadata and optimizing encoding, either losslessly or with a controlled quality cap. Use it right before committing or publishing photos/screenshots when you want smaller files without a visible quality hit.

```bash
# optimize losslessly, overwriting the original
jpegoptim photo.jpg
# cap quality at 85 for a bigger size reduction
jpegoptim --max=85 photo.jpg
# preview what would happen without writing changes
jpegoptim --noaction photo.jpg
```

### `yt-dlp` — Video/Audio Downloader
Downloads video and audio from YouTube and thousands of other sites, picking up where the now-dormant `youtube-dl` left off with far more active maintenance. Use it to grab a video for offline viewing or pull just the audio track from a talk or podcast episode.

```bash
# download a video at best quality
yt-dlp "https://youtube.com/watch?v=..."
# extract audio only, saved as mp3
yt-dlp -x --audio-format mp3 "https://youtube.com/watch?v=..."
# download an entire playlist
yt-dlp --yes-playlist "https://youtube.com/playlist?list=..."
```

### `mpv` — Media Player
A minimal, keyboard-driven media player that runs from the terminal, handling essentially any video or audio format with hardware-accelerated playback. It replaces reaching for QuickTime/VLC for a quick local playback check.

```bash
# play a video file
mpv movie.mkv
# play audio only, skipping the video track
mpv --no-video song.flac
# start playback partway through
mpv --start=00:10:00 movie.mkv
```

### `qalc` — Terminal Calculator (libqalculate)
A serious calculator for the command line: arbitrary math expressions, unit conversion, live currency exchange rates, variables, and symbolic computation, all from one line. It replaces reaching for a GUI calculator or a spreadsheet cell for anything beyond trivial arithmetic.

```bash
# evaluate an expression directly
qalc "2^10 + sqrt(144)"
# convert units
qalc "5 miles to km"
# start an interactive REPL session
qalc -interactive
```

> Tip: `qalc -exrates` refreshes currency exchange rates before a conversion.

### `tldr` — Community Cheat Sheets
Installed as **tlrc**, the official Rust client; the command is still `tldr`. Pulls up short, example-first cheat sheets for a command instead of a full man page — a handful of the most common real-world invocations rather than an exhaustive flag reference. Use it when you just want to remember "how do I usually run this thing."

```bash
# show simplified examples for a command
tldr tar
# refresh the local cheat-sheet database
tldr --update
# list every page available locally
tldr --list
```

### `lnav` — Log File Navigator
An advanced log viewer that auto-detects log formats, merges multiple files into one time-ordered view, and lets you run SQL queries over the parsed log data. It replaces `less`/`tail -f` plus manual `grep` gymnastics when you're trying to make sense of real log files.

```bash
# open one or more log files
lnav app.log
# merge and tail every log in a directory, following new lines
lnav -r /var/log/myapp/
# run a command (e.g. a query) after loading
lnav -c ':filter-in ERROR' app.log
```

### `hexyl` — Hex Viewer
A colorized hex dump tool with an ASCII sidebar, making binary file contents actually readable — a friendlier, faster alternative to `hexdump`/`xxd`. Use it when you need to eyeball the raw bytes of a file, e.g. checking a file's magic number or debugging a binary format.

```bash
# view a file as hex + ASCII
hexyl file.bin
# only look at the first 64 bytes
hexyl --length 64 file.bin
# skip a header and view what follows
hexyl --skip 512 file.bin
```

### `cliamp` — Terminal Music Player
A Winamp-inspired terminal music player with local playback, streaming provider integration (Spotify/Qobuz), an equalizer, and 20+ visualizers. Point it at a music folder and control playback, queueing, and shuffle entirely from the keyboard.

```bash
# launch and load a directory of local music
cliamp ~/Media/music
# check current playback status
cliamp status
# skip to the next track
cliamp next
```

> Tip: `cliamp setup` walks through connecting streaming providers like Spotify or Qobuz.

### `yazi` (Terminal File Manager)
Yazi provides file previews, fuzzy search, bulk operations, and directory navigation.
The generated theme uses the Dracula-Sakura house palette.

```bash
# open Yazi in the current directory
y
# open a specific directory
yazi ~/Code
```


### `aria2c` — Multi-Protocol Download Utility
A multi-connection, multi-protocol downloader supporting HTTP(S), FTP, BitTorrent, and Metalink, capable of splitting a single download across multiple connections for much higher throughput. Reach for it for large files, resumable downloads, or bulk/scripted downloading where a browser's download manager isn't enough.

```bash
# download a file with multiple connections
aria2c -x4 -s4 "https://example.com/large-file.zip"
# resume a partially completed download
aria2c -c "https://example.com/large-file.zip"
# download a list of URLs from a file
aria2c -i urls.txt
```

### `lazynpm` — TUI for npm
A terminal UI for npm projects — browsing and running scripts, inspecting and updating dependencies — from the same team and interaction model as `lazygit`/`lazydocker`. Launch it inside a Node project instead of memorizing `npm run` script names.

```bash
# launch inside an npm project directory
lazynpm
```

### `lazyrsync` — TUI for rsync
A terminal UI over `rsync`, built around reusable sync "profiles" so you don't have to re-type long `rsync` invocations for the same source/destination pairs. Define a profile once, then run or inspect it from the TUI or a one-shot command.

```bash
# list configured profiles and their resolved rsync commands
lazyrsync list
# run a profile's tasks without opening the TUI
lazyrsync run myprofile
# launch the interactive TUI
lazyrsync
```

### `choose` — Simple Field Selector
A simpler alternative to `cut`/`awk` for pulling specific fields or columns out of lines of text, using intuitive index and range syntax instead of `awk`'s programming-language overhead. It supports negative indices to count from the end of a line, something `cut` can't do at all. Reach for it any time you're piping command output and just need "give me column 3."

```bash
# select the second field (0-indexed) on each line
echo "a b c" | choose 1
# select a range of fields
echo "a b c d e" | choose 1:3
# use a custom field separator
echo "a,b,c" | choose -f ',' 0
```

> Tip: `choose -1` (a negative index) grabs the last field on each line.


## Restored Workstation Tools

### `br` (Broot)
Broot displays a searchable directory tree with previews and Git state.
The `br` wrapper applies directory changes to the parent shell.

```bash
br
br ~/Code
```

### `caligula`
Caligula writes and verifies compressed or uncompressed disk images.

CAUTION: Confirm the output device before you start a burn. Caligula overwrites the selected device.

```bash
caligula --help
caligula burn image.iso
```

Caligula uses named terminal colors, which Kitty maps to the Dracula-Sakura palette.


### `nerdlog`
Nerdlog reads and filters logs from the local system or several SSH hosts.

The shell alias selects the OpenSSH transport. This transport honors the generated `~/.ssh/config`.

Nerdlog uses terminal colors, which Kitty maps to the Dracula-Sakura palette.

```bash
nerdlog
nerdlog --lstreams web-* --time 1h
```

### `emeraldian`
Emeraldian provides a keyboard-first interface for existing Obsidian vaults.
The seed starts in reading mode with safe image defaults and an offline, read-only assistant.
The native custom theme uses the full Dracula-Sakura interface, Markdown, syntax, and graph palette.

```bash
emeraldian
emeraldian ~/Notes
```

### `watchtower`
Watchtower provides global news, markets, local weather, and optional model-generated briefs.
Run the setup wizard to choose the required location and any model provider.
Watchtower hardcodes its colors, so this release cannot apply the house theme through configuration.

```bash
watchtower
```


### `eilmeldung`
Eilmeldung provides a fast RSS reader with vim-style navigation.
The managed config uses Dracula-Sakura colors and the macOS URL opener.

```bash
eilmeldung
```

### `concord`
Concord provides Discord access in the terminal.
It stores the token in Keychain and keeps microphone transmission disabled until enabled.

```bash
concord
concord --check-config
```

### `cfait`
Cfait provides offline-first tasks with optional CalDAV synchronization.
The seed uses its Dracula theme and leaves credentials to the OS keyring.

```bash
cfait
```

### `chamber`
Chamber stores secrets in an encrypted local vault.
The script installs the binary but never creates a vault or password.

```bash
chamber init
chamber
```

### `spotatui`
Spotatui plays Spotify, local files, radio, YouTube, Subsonic, and Qobuz sources.
Its user-owned seed applies Dracula-Sakura colors and disables optional presence calls.

```bash
spotatui
spotatui --help
```

### `croft`
Croft provides a VS Code-style IDE in the terminal.
The generated extension supplies the Dracula-Sakura interface, syntax, terminal, and tab palettes.
The generated defaults enable format on save, selection whitespace, copy on select, and 20,000 terminal scrollback lines.

```bash
croft .
croft --help
```


### `herald`
Herald provides email and calendar workflows in the terminal.
Its core features do not require an AI provider.

```bash
herald --demo
herald
```

### `mullvad` and `mullvad-tui`
The Mullvad app bundles the supported `mullvad` CLI.
The script builds `mullvad-tui` v0.10.1 from pinned source for macOS.

```bash
mullvad account login <ACCOUNT_NUMBER>
mullvad status
mullvad-tui
```

Mullvad uses fixed application colors and exposes no theme setting.

### Kiro
Kiro uses JetBrains Mono for code and the named Dracula-Sakura local theme.
The script preserves unrelated settings in the standard macOS settings file.

```bash
kiro .
kiro --version
```

## GUI apps & under-the-hood

These are the deliberate GUI survivors — apps kept because a terminal equivalent
would cost real capability — plus the invisible plumbing the toolkit depends on
but you rarely invoke by hand.

### Kitty (Terminal Emulator)
The GPU-accelerated terminal that hosts this setup uses the Dracula-Sakura theme,
JetBrains Mono Nerd Font, compact padding, and an integrated titlebar. Config
lives at `~/.config/kitty/kitty.conf`.

### Google Chrome — Primary Browser
The primary GUI browser handles sites that need extensions and DevTools.
Carbonyl and Chawan cover terminal browsing.

### Firefox
Firefox provides an independent browser engine for privacy and compatibility work.
Theme installation stays profile-owned.

### Obsidian
Obsidian provides a local Markdown knowledge base.
The script installs Dracula-Sakura in each registered vault.
An existing theme choice remains unchanged.
After you create another vault, run `setup-dev-tools-mac.sh --only configs` to install the theme there.

### Docker Desktop
Docker Desktop provides the macOS Docker engine, Compose, and Buildx.
Docker Desktop owns its application settings.
The script does not replace account, resource, or interface state.

### Bitwarden
Bitwarden provides encrypted native and browser credential access.
The application owns its account, vault, and appearance state.

### Language servers
OMP discovers these servers from project markers and command names on `PATH`.

| Languages | Command | Package |
|---|---|---|
| TypeScript and JavaScript | `typescript-language-server` | `typescript-language-server` |
| HTML | `vscode-html-language-server` | `vscode-langservers-extracted` |
| CSS, SCSS, Sass, and Less | `vscode-css-language-server` | `vscode-langservers-extracted` |
| JSON and JSONC | `vscode-json-language-server` | `vscode-langservers-extracted` |
| ESLint | `vscode-eslint-language-server` | `vscode-langservers-extracted` |
| YAML | `yaml-language-server` | `yaml-language-server` |
| Bash and Zsh | `bash-language-server` | `bash-language-server` |
| Python types | `pyright-langserver` | `pyright` |
| Python lint and format | `ruff server` | `ruff` |
| C, C++, and Objective-C | `clangd` | `llvm` |
| Rust | `rust-analyzer` | `rust-analyzer` |
| C# | `omnisharp` | Official OmniSharp release and .NET SDK |
| Lua | `lua-language-server` | `lua-language-server` |
| Dockerfile | `docker-language-server start --stdio` | `docker-language-server` |
| Markdown | `marksman` | `marksman` |
| TypeScript, JavaScript, JSON, and CSS lint | `biome lsp-proxy` | `@biomejs/biome` |

The OMP policy disables `ty` and `basedpyright`, so Pyright provides Python type intelligence.
Ruff remains the Python linter and formatter.

### Build and runtime dependencies
These packages support builds and local inference:
`cmake`, `ninja`, `pkgconf`, `vulkan-loader`, `molten-vk`, `shaderc`,
`coreutils`, `findutils`, `gawk`, `gnu-sed`, `gnu-tar`, `gnupg`, and
`pinentry-mac`.

### Fonts
The terminal and editors use JetBrains Mono, JetBrains Mono Nerd Font, and Inter.

---

*This file is regenerated from the setup script on every run. Edit the
`TOOL_REFERENCE.md` heredoc in the generator when the toolset changes.*
REFERENCE_EOF

    success "Desktop docs written: POST_SETUP_CHECKLIST.md, KEYBOARD_SHORTCUTS.md, TOOLKIT_SUMMARY.md, TOOL_REFERENCE.md"
fi

info "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Work through ~/Desktop/POST_SETUP_CHECKLIST.md."
echo "  3. Review KEYBOARD_SHORTCUTS.md, TOOLKIT_SUMMARY.md, and TOOL_REFERENCE.md."
echo "  4. Log out, then log in to apply the Spotlight and menu bar settings."
echo "  5. Enable FileVault and the macOS firewall."
echo "  6. Confirm llama.cpp at http://127.0.0.1:8081/v1/models."

# =============================================================================
# FIRST-RUN SETUP (interactive — only runs if not already configured)
# =============================================================================
if [[ "$DRY_RUN" == "false" ]]; then
banner "First-Run Setup"

# ---- SSH Key Generation ----
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    echo ""
    ssh_confirm=$(prompt_ask "Generate an SSH key? [Y/n] " "n")
    if [[ ! "$ssh_confirm" =~ ^[Nn]$ ]]; then
        ssh_email=$(prompt_ask "Email for SSH key: " "")
        if [[ -n "$ssh_email" ]]; then
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            ssh-keygen -t ed25519 -C "$ssh_email" -f "$HOME/.ssh/id_ed25519"
            eval "$(ssh-agent -s)" 2>/dev/null || true
            ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
            success "SSH key generated at ~/.ssh/id_ed25519"
        fi
    fi
else
    warn "SSH key already exists at ~/.ssh/id_ed25519"
fi

# ---- GitHub Authentication ----
if installed gh; then
    if ! gh auth status &>/dev/null; then
        echo ""
        gh_confirm=$(prompt_ask "Authenticate with GitHub? [Y/n] " "n")
        if [[ ! "$gh_confirm" =~ ^[Nn]$ ]]; then
            info "Opening GitHub authentication..."
            gh auth login
            # Add SSH key to GitHub if it was just generated
            if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
                ssh_gh_confirm=$(prompt_ask "Add SSH key to GitHub? [Y/n] " "n")
                if [[ ! "$ssh_gh_confirm" =~ ^[Nn]$ ]]; then
                    gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname) $(date +%Y-%m-%d)"
                    success "SSH key added to GitHub"
                fi
            fi
        fi
    else
        warn "GitHub CLI already authenticated"
    fi
fi

# ---- Git Identity ----
GITCONFIG_WORK="$HOME/.gitconfig-work"
GITCONFIG_PERSONAL="$HOME/.gitconfig-personal"

# Work identity
if [[ -f "$GITCONFIG_WORK" ]] && grep -q "^    # name = " "$GITCONFIG_WORK" 2>/dev/null; then
    echo ""
    work_confirm=$(prompt_ask "Set up your work git identity? [Y/n] " "n")
    if [[ ! "$work_confirm" =~ ^[Nn]$ ]]; then
        work_name=$(prompt_ask "Work name: " "")
        work_email=$(prompt_ask "Work email: " "")
        if [[ -n "$work_name" ]] && [[ -n "$work_email" ]]; then
            cat > "$GITCONFIG_WORK" <<GIT_WORK_ID
[user]
    name = $work_name
    email = $work_email
GIT_WORK_ID
            success "Work git identity set ($work_email)"
        fi
    fi
fi

# Personal identity
if [[ -f "$GITCONFIG_PERSONAL" ]] && grep -q "^    # name = " "$GITCONFIG_PERSONAL" 2>/dev/null; then
    echo ""
    personal_confirm=$(prompt_ask "Set up your personal git identity? [Y/n] " "n")
    if [[ ! "$personal_confirm" =~ ^[Nn]$ ]]; then
        personal_name=$(prompt_ask "Personal name: " "")
        personal_email=$(prompt_ask "Personal email: " "")
        if [[ -n "$personal_name" ]] && [[ -n "$personal_email" ]]; then
            cat > "$GITCONFIG_PERSONAL" <<GIT_PERSONAL_ID
[user]
    name = $personal_name
    email = $personal_email
GIT_PERSONAL_ID
            success "Personal git identity set ($personal_email)"
            # Use personal as the GLOBAL default so commits outside ~/Code/{work,personal}
            # still have a committer (otherwise `git commit` fails with "unknown identity"
            # in ~/Code/oss, ~/Inbox, /tmp, etc.). git reads config top-to-bottom, so the
            # work includeIf must sit AFTER [user] to override it — re-assert it here so it
            # lands after the [user] block git config just appended.
            git_global user.name "$personal_name"
            git_global user.email "$personal_email"
            git_global --unset-all "includeIf.gitdir:~/Code/work/.path" 2>/dev/null || true
            git_global "includeIf.gitdir:~/Code/work/.path" "$GITCONFIG_WORK"
            success "Global git default = personal ($personal_email); ~/Code/work still overrides it"
        fi
    fi
fi

fi  # DRY_RUN

# =============================================================================
# MISE SHIM LINKS  (must run AFTER every install — #357)
# =============================================================================
# Deliberately last, and deliberately outside every `should_run` guard.
#
# This block used to sit in `core`, next to the PATH fix it was written with. That put it
# at line ~2105 while the `npm_global_install` calls start at ~2292 — so a tool installed
# during a run got its mise shim but no ~/.local/bin link until the NEXT run. It self-healed,
# which is exactly why it went unnoticed: every tool that looked correctly linked had been
# installed by an earlier run than the one that linked it. Installing the Copilot CLI (#356)
# is what exposed it — `copilot` resolved in a login shell and not in a bare `sh`.
#
# The two jobs have opposite timing requirements and cannot share a home:
#   * putting mise's node on THIS run's PATH (#343) must happen EARLY, before any
#     npm_global_install, or `installed npm` is false for the rest of the run;
#   * linking shims into ~/.local/bin (#353) must happen LATE, after every install,
#     or it cannot see what was just installed.
# The PATH fix stays in `core`. This half lives here.
#
# Unguarded by category on purpose: `--only dx` installs tools, so `--only dx` must link
# them. A `should_run "configs"` guard would reintroduce the same gap for anyone who runs a
# single category. Re-linking is idempotent (`ln -sfn` plus a prune), so running it on every
# invocation costs nothing.
if installed mise; then
    # Make every mise-managed tool reachable OUTSIDE a mise-activated shell (#345, #353). `mise activate` runs for
    # zsh only, via ~/.zshenv and ~/.zshrc. Git hooks run under `sh`, which reads neither —
    # so once #344 removed Homebrew's node they had no node, npm or npx at all, and a
    # prettier pre-commit hook in another repo failed with `npx not found`. Homebrew's copy
    # lived in $HOMEBREW_PREFIX/bin and was therefore on essentially every PATH on the
    # machine. That was accidental, but real tooling depended on it.
    #
    # mise ships SHIMS for exactly this case: they resolve the active version with no shell
    # activation at all. The shims directory itself cannot go on a system-wide PATH without
    # sudo, but ~/.local/bin is already on PATH in that `sh` environment and this script
    # already uses it for soffice and yaml-py, so link the shims there.
    #
    # Two constraints, both verified rather than assumed:
    #   * The link NAME must match the shim name. mise dispatches on argv[0], so a link
    #     called anything else fails with "<name> is not a valid shim".
    #   * Link the SHIM, not the versioned installs/node/<ver>/bin path. The shim follows a
    #     Node upgrade; a versioned path silently rots at the next `mise use node@...`.
    # Which shims NOT to link. Everything else is linked, so a tool added to mise later is
    # picked up automatically instead of silently missing until someone notices — that
    # silent-gap shape is the whole reason this block exists.
    #
    # The Python family is excluded deliberately. `pre-commit` builds its hook environments
    # against whichever `python3` it finds, and ~/.local/bin outranks $HOMEBREW_PREFIX/bin
    # in every context — so linking mise's 3.12 here would retarget hook envs machine-wide
    # and break ones already built against Homebrew's. That is #345 again, one language over.
    # corepack is excluded because it manages package-manager shims and collides with pnpm.
    SHIM_EXCLUDE=(
        python python3 python3.12 python3-config python3.12-config
        pip pip3 pip3.12 2to3 2to3-3.12 idle3 idle3.12 pydoc3 pydoc3.12
        corepack
    )
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would link mise shims -> ~/.local/bin (all but the Python family; for git hooks + non-zsh callers)"
    else
        # A tool installed since the last reshim has no shim yet; cheap and idempotent.
        mise reshim >> "$LOG_FILE" 2>&1 || true
        _mise_shims="$HOME/.local/share/mise/shims"
        if [[ -d "$_mise_shims" ]]; then
            _shim_n="$(link_mise_shims "$_mise_shims" "$HOME/.local/bin" "${SHIM_EXCLUDE[@]}")"
            success "$_shim_n mise shims linked to ~/.local/bin — git hooks, editors and non-zsh shells can find them"
            unset _shim_n
        else
            warn "mise shims directory not found ($_mise_shims) — non-zsh callers will not see mise tools"
        fi
        unset _mise_shims
    fi
fi

# =============================================================================
# POST-INSTALL VERIFICATION
# =============================================================================
banner "Post-install Verification"

if [[ "$DRY_RUN" == "false" ]]; then
    info "Verifying critical tools..."

    VERIFY_TOOLS=(
        "git:git --version"
        "gh:gh --version"
        "node:node --version"
        "npm:npm --version"
        "python3:python3 --version"
        "go:go version"
        "rustc:rustc --version"
        "uv:uv --version"
        "brew:brew --version"
        "micro:micro -version"
        "kiro:kiro --version"
        "llama.cpp Vulkan:llama-server --list-devices | grep -i vulkan"
        "starship:starship --version"
        "fzf:fzf --version"
        "eza:eza --version"
        "bat:bat --version"
        "rg:rg --version"
        "fd:fd --version"
        "zoxide:zoxide --version"
        "atuin:atuin --version"
        "lazygit:lazygit --version"
        "just:just --version"
        "delta:delta --version"
    )

    VERIFY_PASS=0
    VERIFY_FAIL=0
    for entry in "${VERIFY_TOOLS[@]}"; do
        tool="${entry%%:*}"
        cmd="${entry##*:}"
        if version=$(bash -c "$cmd" 2>/dev/null | head -1); then
            echo -e "  ${GREEN}✓${NC} $tool: $version"
            ((VERIFY_PASS++))
        else
            echo -e "  ${RED}✗${NC} $tool: not found or not working"
            ((VERIFY_FAIL++))
        fi
    done
    echo ""
    success "Verification: $VERIFY_PASS passed, $VERIFY_FAIL failed"

    # Brew cleanup
    info "Running brew cleanup..."
    brew cleanup >> "$LOG_FILE" 2>&1
    success "Brew cleanup complete"

    # Brew doctor
    if brew_doctor_needed; then
        run_brew_doctor
    else
        info "Skipping brew doctor — no new Homebrew install or package failure"
    fi
else
    info "[DRY RUN] Skipping verification"
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================

SCRIPT_END=$(date +%s)
DURATION=$((SCRIPT_END - SCRIPT_START))
MINUTES=$((DURATION / 60))
SECONDS_REMAINING=$((DURATION % 60))
timing_report

echo ""
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}${BOLD}  Setup complete — machine ready${NC}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Installed:${NC}  $INSTALL_SUCCESS"
echo -e "  ${GREEN}${BOLD}Configured:${NC} $INSTALL_CONFIGURED"
echo -e "  ${YELLOW}${BOLD}Skipped:${NC}   $INSTALL_SKIPPED (already installed)"
echo -e "  ${RED}${BOLD}Failed:${NC}    $INSTALL_FAILED"
echo -e "  ${BLUE}${BOLD}Duration:${NC}  ${MINUTES}m ${SECONDS_REMAINING}s"
echo -e "  ${DIM}Log:       $LOG_FILE${NC}"
if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    echo -e "  ${DIM}Errors:    $ERROR_LOG${NC}"
fi
echo ""

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    echo -e "${RED}${BOLD}Failed items:${NC}"
    for item in "${FAILED_ITEMS[@]}"; do
        echo -e "  ${RED}•${NC} $item"
    done
    echo ""
    echo -e "  Review errors: ${DIM}cat $ERROR_LOG${NC}"
    echo ""
fi

# Managed-block repairs and leftovers (#259). A repair is a fix worth announcing;
# leftover outside-marker content is expected for files you edit yourself, so it stays
# a single quiet line rather than a per-file warning that trains you to ignore it.
MANAGED_REPAIRED_LIST=$(managed_list repaired)
MANAGED_OUTSIDE_LIST=$(managed_list outside)
MANAGED_REFRESHED_LIST=$(managed_list refreshed)

# Files rewritten by write_generated because their content changed. Worth naming:
# the previous copy is kept alongside as *.replaced.*
if [[ -n "$MANAGED_REFRESHED_LIST" ]]; then
    echo -e "${GREEN}${BOLD}Refreshed $(echo "$MANAGED_REFRESHED_LIST" | wc -l | tr -d ' ') generated file(s)${NC} (previous copies kept as .replaced.<timestamp>):"
    while IFS= read -r item; do
        echo -e "  ${GREEN}•${NC} ${item/#$HOME/\~}"
    done <<< "$MANAGED_REFRESHED_LIST"
    echo ""
fi

if [[ -n "$MANAGED_REPAIRED_LIST" ]]; then
    _verb="Repaired"; [[ "$DRY_RUN" == "true" ]] && _verb="Would repair"
    echo -e "${GREEN}${BOLD}${_verb} $(echo "$MANAGED_REPAIRED_LIST" | wc -l | tr -d ' ') config(s)${NC} carrying a duplicate pre-managed copy of the block:"
    while IFS= read -r item; do
        echo -e "  ${GREEN}•${NC} ${item/#$HOME/\~}"
    done <<< "$MANAGED_REPAIRED_LIST"
    echo ""
fi

if [[ -n "$MANAGED_OUTSIDE_LIST" ]]; then
    echo -e "${DIM}$(echo "$MANAGED_OUTSIDE_LIST" | wc -l | tr -d ' ') managed file(s) carry content outside the markers:${NC}"
    while IFS= read -r item; do
        echo -e "${DIM}  • ${item/#$HOME/\~}${NC}"
    done <<< "$MANAGED_OUTSIDE_LIST"
    echo -e "${DIM}  Expected for files you edit yourself (~/.zshrc, ~/.ssh/config, ~/.aws/config).${NC}"
    echo -e "${DIM}  If unexpected, it may be a pre-7.x duplicate that has since drifted — see issue #259.${NC}"
    echo ""
fi

# Repeat the install-vs-config notice here (#258). "Installed: 10, Failed: 0" is
# exactly what made a half-run look complete, so the caveat belongs beside it —
# and last, so it is the final thing read before the run ends. The separate
# `Configured:` count added in #381 makes the same point numerically: `--only git`
# now reports Configured: 0 rather than folding its zero configuration work into a
# healthy-looking install number.
config_split_notice

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}${BOLD}  This was a dry run — no changes were made.${NC}"
    echo -e "${YELLOW}  Run without --dry-run to install everything.${NC}"
    echo ""
fi

# All work is done; everything below is a convenience prompt. Release the lock HERE
# rather than leaving it to the EXIT trap: a run parked on this question is finished,
# but it used to keep the lock for as long as it sat there — and since the prompt
# comes after the success banner, it is easy to walk away from. One such run held the
# lock for 5.5 hours and every later run was refused with "Another instance is
# running", which was true but read as "work in progress" (#265).
release_lock
trap - EXIT

if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    source_confirm=$(prompt_ask "Source ~/.zshrc now to activate everything? [Y/n] " "n")
    if [[ ! "$source_confirm" =~ ^[Nn]$ ]]; then
        # Use exec to replace the current shell so the new zshrc takes effect
        echo -e "${GREEN}${BOLD}  Reloading shell for the new session...${NC}"
        release_lock
        exec zsh -l
    else
        echo -e "${GREEN}${BOLD}  Run 'source ~/.zshrc' or restart your terminal when you're ready to activate it.${NC}"
    fi
else
    echo -e "${GREEN}${BOLD}  Restart your terminal when you're ready to activate it.${NC}"
fi
echo ""

# Turn the counted failures back into an exit status (#370).
#
# `set +e` is deliberate — one failed formula must not abandon the other 200 — but
# nothing ever converted the count back, and the last statement in the file was a bare
# `echo`, so EVERY run exited 0. A run could print `Failed: 12` and still satisfy
# `./setup-dev-tools-mac.sh && echo ok`. The only failure signal was notify_failure,
# which no-ops without terminal-notifier, so launchd jobs, `topgrade` steps, `&&` chains
# and CI had no signal at all.
#
# The interactive `exec zsh -l` branch above replaces this process and takes the status
# with it. That is acceptable and not worth contorting the flow for: exec is only
# reached when a human answered the prompt having just read the red summary, and
# --no-prompt answers "n" (#265), so every unattended run reaches this line.
#
# --dry-run is included on purpose. It counts errors too (a bad --only category, a
# missing prerequisite), and a preview that cannot fail is no use as a CI gate.
if [[ "$INSTALL_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
