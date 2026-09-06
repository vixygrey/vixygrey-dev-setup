#!/usr/bin/env bash

# Require bash 4+ (this script uses associative arrays). macOS ships bash 3.2 as
# /bin/bash, so on a clean Mac re-exec under a newer bash if one is installed;
# otherwise tell the user how to get one. (This guard is itself 3.2-compatible.)
if ((BASH_VERSINFO[0] < 4)); then
    for _newbash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [[ -x "$_newbash" ]] && exec "$_newbash" "$0" "$@"
    done
    echo "This setup script needs bash 4+ (macOS ships bash 3.2)." >&2
    echo "Install a newer bash and re-run:  brew install bash" >&2
    exit 1
fi

# =============================================================================
# Development Environment Setup Script (macOS)
# =============================================================================
# Version:  see SCRIPT_VERSION below (source of truth)
# Platform: macOS (Apple Silicon + Intel), requires bash 4+
# Run:      chmod +x setup-dev-tools-mac.sh && ./setup-dev-tools-mac.sh
# Flags:    --dry-run, --list, --list-categories, --only <cats>, --skip <cats>,
#           --interactive/-i, --resume, --cleanup, --uninstall, --version, --help
# =============================================================================

SCRIPT_VERSION="7.15.0"
SCRIPT_START=$(date +%s)
PYTHON_VERSION="3.12"

# Where `go install` writes binaries. The generated login shell adds
# $GOPATH/bin (== ~/.local/share/go/bin) to PATH, but `go install` defaults to
# ~/go/bin unless GOBIN is set — so pin GOBIN here to the dir the shell expects,
# and put it on THIS run's PATH so freshly-installed Go tools resolve immediately.
export GOBIN="$HOME/.local/share/go/bin"
export PATH="$GOBIN:$PATH"
mkdir -p "$GOBIN"

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
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
ERROR_LOG="$LOG_DIR/setup-errors-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }

info() {
    printf '\033[2K\r'
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

success() {
    printf '\033[2K\r'
    echo -e "${GREEN}[  OK]${NC} $1"
    log "OK: $1"
    ((INSTALL_SUCCESS++)) || true
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
    printf '\033[2K\r'
    echo ""
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}${BOLD}  $title${NC}"
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "=== $title ==="
}

# macOS notification helpers — silently no-op if terminal-notifier isn't installed yet
notify_success() {
    local message="$1"
    command -v terminal-notifier >/dev/null 2>&1 || return 0
    terminal-notifier -title "Dev Setup" -subtitle "Completed" -message "$message" -sound Glass -group vixygrey-dev-setup >/dev/null 2>&1 || true
}

notify_failure() {
    local message="$1"
    command -v terminal-notifier >/dev/null 2>&1 || return 0
    terminal-notifier -title "Dev Setup" -subtitle "Failed" -message "$message" -sound Basso -group vixygrey-dev-setup >/dev/null 2>&1 || true
}

# -- Counters -----------------------------------------------------------------
INSTALL_SUCCESS=0
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
# when tools are added or removed. Counts brew_install, brew_cask_install, npm_global_install,
# go_install, uv_tool_install and vscode_ext_install, including those inside conditionals.
# A new install helper MUST be added to this pattern or its calls run un-counted and the
# bar overshoots 100%.
# Count all install calls + standalone progress calls for accurate progress bar
# Note: `grep -c` prints "0" AND exits 1 on zero matches, so `|| echo 0` would append
# a SECOND "0" ("0\n0") and break the arithmetic. Use `|| true` + a default instead.
_INSTALL_CALLS=$(grep -cE '^\s*(brew_install|brew_cask_install|npm_global_install|go_install|uv_tool_install|vscode_ext_install) ' "$0" 2>/dev/null || true)
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
VERIFY=false
INTERACTIVE=false
NO_PROMPT=false
SKIP_CATEGORIES=()
ONLY_CATEGORIES=()

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

mark_done() {
    echo "$1" >> "$STATE_FILE"
}

is_done() {
    [[ "$RESUME" == "true" ]] && grep -qxF "$1" "$STATE_FILE" 2>/dev/null
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
    ux
    docs
    mac-system
    mac-productivity
    mac-browsers
    mac-media
    mac-cloud
    mac-focus
    mac-bloat
    dracula
    configs
    filesystem
    macos-defaults
    shell
)

# Category descriptions for interactive picker (must match ALL_CATEGORIES order)
declare -A CATEGORY_DESC=(
    [prerequisites]="Xcode CLI Tools, Homebrew, GNU coreutils"
    [core]="mise (Node, Python), Go, Rust, OrbStack, bun, uv, pnpm"
    [git]="Git, GitHub CLI, glab, delta, lazygit, gk, pre-commit framework (hooks + config: configs)"
    [aws]="AWS CLI, CDK, SAM, Granted, cfn-lint, e1s/e2c/stu/claws (TUIs), s5cmd, steampipe, dynein, iamlive"
    [iac]="OpenTofu (Terraform), tflint, terraform-docs, checkov, infracost"
    [security]="detect-secrets, gitleaks, trivy, semgrep, ClamAV, Objective-See"
    [replacements]="eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, rovr, fx, etc."
    [data-processing]="yq, miller, csvkit, pandoc, ffmpeg, ImageMagick"
    [code-quality]="shellcheck, shfmt, act, act3, hadolint, ruff, prettier, commitizen, ni"
    [perf-testing]="hyperfine, oha"
    [dev-servers]="ngrok, miniserve, caddy"
    [terminal-productivity]="leaf, watchexec, gum, nushell, topgrade, fastfetch, nnn, doxx, taproom, qalc, vhs, lazyssh/rsync/npm, lazyenv, keyward, bmm, manly, cheznav, apw, has, jolt, wiper, starlit"
    [k8s-github]="stern, gh-dash"
    [database]="pgcli, mycli, lazysql, harlequin, usql, sq"
    [containers]="lazydocker, dive, kubectl, k9s"
    [api]="ATAC, grpcurl"
    [networking]="mtr, bandwhich, nmap"
    [dx]="fzf, starship, atuin, croft, micro, VS Code (+ extensions), Ghostty, zellij, llm"
    [ux]="Lighthouse"
    [docs]="d2, Mermaid CLI"
    [mac-system]="Pearcleaner, dockutil, terminal-notifier"
    [mac-productivity]="tiki, reminders-cli, Skim, LibreOffice"
    [mac-browsers]="Carbonyl, w3m, monolith"
    [mac-media]="mpv, oxipng, jpegoptim, 7zip, cliamp"
    [mac-cloud]="rclone, borg"
    [mac-focus]="newsboat"
    [mac-bloat]="Remove pre-installed Apple apps (GarageBand)"
    [dracula]="Dracula theme for all tools"
    [configs]="EVERY tool's generated config + git hooks + Claude setup (not in the tool's own category)"
    [filesystem]="Directory structure, helper scripts, git identity"
    [macos-defaults]="Dock, Finder, keyboard, screenshots, Touch ID, DNS"
    [shell]="\$HOME/.zshrc, Brewfile export"
)

# -- Install-vs-config split --------------------------------------------------
# A category INSTALLS its tools; it does not CONFIGURE them. Every generated config
# file lives in one ordered `configs` segment (with starship in `dracula`, ~/Scripts
# in `filesystem` and ~/.zshrc in `shell`), so `--only git` installs git tooling and
# refreshes NONE of its configuration — including the global pre-commit hook — while
# still reporting "Failed: 0". That silent half-run is #258.
#
# This table is what `--only` uses to say so out loud. It is descriptive text only —
# no control flow keys off it — but a typo'd category name would make a notice
# silently never appear, so the keys are validated against ALL_CATEGORIES below.
declare -A CONFIG_LIVES_IN_CONFIGS=(
    [core]="mise, direnv, ~/.npmrc, pip, gemrc"
    [git]="the global pre-commit hook, lazygit, gh, git-cliff, the commit template, global gitignore"
    [aws]="the AWS CLI config (\$HOME/.aws/config)"
    [iac]="tflint"
    [code-quality]="shellcheck, act, prettier, editorconfig"
    [replacements]="btop, ripgreprc, fdignore, aria2"
    [data-processing]="yt-dlp, miller"
    [terminal-productivity]="leaf, nushell, topgrade, fastfetch, asciinema"
    [k8s-github]="stern, gh-dash"
    [database]="pgcli, mycli, harlequin"
    [containers]="lazydocker, k9s (config + Dracula skin)"
    [networking]="trippy"
    [dx]="atuin, zellij, Ghostty, VS Code settings — and starship, which is in the \`dracula\` category"
    [mac-focus]="newsboat"
    [mac-media]="mpv"
    [mac-browsers]="w3m"
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
    [mac-bloat]="removing pre-installed Apple apps from /Applications"
)

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
sudo_reasons() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    local c
    for c in "${!SUDO_CATEGORY_REASON[@]}"; do
        should_run "$c" && printf '%s (%s)\n' "${SUDO_CATEGORY_REASON[$c]}" "$c"
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
    echo "  --cleanup           Remove tools from previous versions no longer in this script"
    echo "  --verify            Check each generated config is at the path its tool reads"
    echo "                      and that the tool accepts it. CI proves these files parse;"
    echo "                      only a machine with the tools installed can prove anything"
    echo "                      reads them. Exits 1 if any tool is ignoring our config"
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
    echo "  --list              List all tools that would be installed"
    echo "  --version           Show script version"
    echo ""
    echo "Examples:"
    echo "  ./setup-dev-tools-mac.sh                          # Install everything"
    echo "  ./setup-dev-tools-mac.sh -i                       # Interactive category picker"
    echo "  ./setup-dev-tools-mac.sh --dry-run                # Preview only"
    echo "  ./setup-dev-tools-mac.sh --list                   # List all tools"
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
            echo -e "${BOLD}Tools installed by this script:${NC}"
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
            _f=$(grep -cE '^\s*brew_install ' "$0")
            _c=$(grep -cE '^\s*brew_cask_install ' "$0")
            _n=$(grep -cE '^\s*npm_global_install ' "$0")
            echo -e "${DIM}Total: ${_f} formulae, ${_c} casks, ${_n} npm packages ($((_f + _c + _n)) tools)${NC}"
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

# remove_superseded_managed <file> <explanation> [issue-ref]
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
    local file="$1" what="$2" ref="${3:-}"
    [[ -f "$file" ]] || return 0
    local mb="# >>> dev-setup managed block (do not edit between the markers) >>>"
    local me="# <<< dev-setup managed block <<<"
    if ! grep -qF "$mb" "$file" 2>/dev/null; then
        warn "Left $file alone — this script did not write it. $what"
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
    if [[ ! -f "$file" ]]; then
        [[ "$DRY_RUN" == "true" ]] || cp "$tmp" "$file"
    elif grep -qF "$mb" "$file" 2>/dev/null; then
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
    if [[ "$DRY_RUN" == "true" ]]; then return 0; fi
    mkdir -p "$(dirname "$file")"
    local bt; bt="$(mktemp)"; printf '%s\n' "$body" > "$bt"
    if [[ ! -f "$file" ]] || ! grep -qF "$mb" "$file" 2>/dev/null; then
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
# For script-owned files that CANNOT carry managed-block markers:
#   - Claude agents start with YAML frontmatter, which must be on line 1
#   - Claude slash commands are prompts — the whole file is fed to the model, so a
#     marker line would end up as part of the instruction
# Refreshes only when the content differs, and backs up whatever it replaces, so an
# edit made on the machine is recoverable. The alternative in use before this was a
# create-once guard ("directory already has agents"), under which one pre-existing
# file froze the entire set and no later addition or edit ever arrived (#277).
write_generated() {
    local file="$1"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp"
    if [[ "$DRY_RUN" == "true" ]]; then
        [[ -f "$file" ]] && ! cmp -s "$tmp" "$file" && info "[DRY RUN] Would refresh $file"
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

brew_install() {
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

brew_cask_install() {
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
_npm_has() {
    _ensure_npm_snapshot
    local line
    while IFS= read -r line; do [[ "$line" == */node_modules/"$1" ]] && return 0; done <<< "$_NPM_GLOBALS"
    return 1
}

npm_global_install() {
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
            success "$name installed"
            mark_done "npm:$pkg"
        else
            error "Failed to install $name"
        fi
    fi
}

# vscode_ext_install <publisher.extension-id> <description>
# Installs a VS Code extension via the `code` CLI. The visual-studio-code cask ships
# `code` as a Binary artifact, so it lands on PATH with the app — no in-app "Shell
# Command: Install 'code' command" step needed.
#
# Two details worth keeping:
#   - The installed-extension list is read ONCE into _VSCODE_EXTS (see the dx section)
#     rather than shelling out per extension. `code --list-extensions` boots Electron
#     and takes ~1s; at 27 extensions that is ~27s of nothing on an already-provisioned
#     machine. The cached list is compared case-insensitively because the marketplace
#     is case-preserving but `code` matches IDs case-insensitively.
#   - Extension IDs must be verified against the marketplace before being added here.
#     A wrong ID is not a loud failure — `code` prints "not found" and exits non-zero,
#     which lands as one red line in a 300-line run. See CONTRIBUTING/AGENTS on naming
#     the real thing rather than the plausible thing.
vscode_ext_install() {
    local ext="$1"
    local name="${2:-$1}"
    progress
    is_done "vscode-ext:$ext" && { warn "$name already completed (resume)"; return 0; }
    # DRY_RUN is checked BEFORE the `code` guard on purpose. A dry run reports what a real
    # run would do, and a real run installs the cask (which provides `code`) a few lines
    # above this. Guarding first made a fresh-machine dry run say it would install VS Code
    # and then refuse to preview a single extension — the preview was useless exactly where
    # it matters most.
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install VS Code extension: $name ($ext)"
        return 0
    fi
    if ! installed code; then
        warn "Skipping $name — the 'code' CLI is not available (cask install failed?)"
        return 0
    fi
    # Cached list from the dx section; falls back to a live query if unset.
    [[ -z "${_VSCODE_EXTS+x}" ]] && _VSCODE_EXTS=$(code --list-extensions 2>/dev/null || true)
    if printf '%s\n' "$_VSCODE_EXTS" | grep -qix -- "$ext"; then
        warn "$name already installed"
        mark_done "vscode-ext:$ext"
    else
        info "Installing VS Code extension: $name..."
        if code --install-extension "$ext" --force >> "$LOG_FILE" 2>&1; then
            success "$name installed"
            mark_done "vscode-ext:$ext"
        else
            error "Failed to install VS Code extension: $name ($ext)"
        fi
    fi
}

# go_install <import-path@ver> <cmd-name> <description>
# Installs a Go tool into $GOBIN (the dir the login shell puts on PATH), so it's
# reachable both during this run and in new shells. Skips if already present,
# honors DRY_RUN, and advances the progress bar in every branch.
go_install() {
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
uv_tool_install() {
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
    # isn't (launchd / `brew services` at login). Write BOTH, so tapped-formula SERVICES
    # (e.g. sketchybar via `brew services`) auto-start at login — not just interactive
    # installs. Writing to one location only leaves the other context refusing the tap.
    XDG_CONFIG_HOME="$HOME/.config" brew trust --tap "$tap" >> "$LOG_FILE" 2>&1 \
        || warn "Could not trust tap $tap — installs from it may be refused by Homebrew"
    env -u XDG_CONFIG_HOME brew trust --tap "$tap" >> "$LOG_FILE" 2>&1 || true
}

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
        success "macOS $macos_version detected"
    fi

    # Architecture
    local arch
    arch=$(uname -m)
    success "Architecture: $arch"

    # Internet connectivity
    if curl -s --max-time 5 https://raw.githubusercontent.com > /dev/null 2>&1; then
        success "Internet connection OK"
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
        success "Disk space: ${free_space:-unknown}GB free"
    fi

    # Admin check — only when a step in THIS run will actually use sudo, and saying
    # what for. Asking unconditionally meant `--dry-run` demanded a password to
    # produce a preview that changes nothing, and the message named no step, so the
    # only way to judge the request was to trust it (#269).
    local reasons
    reasons=$(sudo_reasons)
    if [[ -z "$reasons" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            success "No admin privileges needed (dry run changes nothing)"
        else
            success "No admin privileges needed for the selected categories"
        fi
    elif sudo -n true 2>/dev/null; then
        success "Admin privileges available"
    else
        info "Admin privileges are needed for:"
        while IFS= read -r reason; do
            [[ -n "$reason" ]] && echo "         • $reason"
        done <<< "$reasons"
        info "Enter your password once now:"
        sudo -v
        success "Admin privileges granted"
        # Keep sudo alive for the duration of the script. Test liveness BEFORE each
        # refresh, not only after the sleep: the old order could refresh the sudo
        # timestamp once more after the parent had already exited.
        ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done 2>/dev/null ) &
        SUDO_KEEPALIVE_PID=$!
    fi

    # Homebrew health check (warn early if there are issues)
    if command -v brew &>/dev/null; then
        if ! brew doctor >> "$LOG_FILE" 2>&1; then
            warn "brew doctor found issues (may cause install failures — see $LOG_FILE)"
        else
            success "Homebrew healthy (brew doctor passed)"
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
    success "Log file: $LOG_FILE"

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
echo "  ║  200+ tools · 50+ configs · Dracula theme · macOS defaults  ║"
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
    echo "  rm -f ~/.hushlogin ~/.gitmessage ~/.myclirc ~/.gemrc ~/.actrc ~/.mlrrc ~/.czrc ~/.tflint.hcl"
    echo "  rm -rf ~/.aria2 ~/.config/atuin ~/.config/ngrok"
    echo "  rm -rf ~/.config/yt-dlp ~/.config/gh-dash ~/.config/stern"
    echo "  rm -rf ~/.config/btop ~/.config/lazydocker ~/.config/mise"
    echo "  rm -rf ~/.config/topgrade.toml ~/.config/fastfetch ~/.config/pgcli"
    echo "  rm -rf ~/.config/direnv ~/.config/caddy ~/.config/ghostty"
    echo "  rm -f ~/.justfile"
    echo ""
    echo "# Remove Rust (installed via rustup):"
    echo "  rustup self uninstall"
    echo ""
    echo "# Remove tools not managed by brew (--cleanup can't reach these):"
    echo "  npm uninstall -g @github/copilot         # GitHub Copilot CLI"
    echo "  gh extension remove github/gh-copilot   # the RETIRED gh-extension Copilot CLI, if still present"
    echo "  rm -f ~/.local/share/go/bin/helix-assist  # dropped Claude LSP for Helix"
    echo "  cargo uninstall croft                    # the terminal IDE (if you want it gone)"
    echo ""
    echo "# Remove VS Code's per-user trees (the cask uninstall leaves these behind):"
    echo "  rm -rf ~/.vscode                          # installed extensions"
    echo "  rm -rf \"\$HOME/Library/Application Support/Code\"   # settings, state, workspace storage"
    echo ""
    echo "# Remove Claude Code config (CAREFUL — contains your custom rules):"
    echo "  rm -rf ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.claude/rules ~/.claude/hooks ~/.claude/commands ~/.claude/agents ~/.claude/statusline.sh"
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
    DEPRECATED_TOOLS=(
        "brew:tmux:tmux:zellij"
        "brew:helix:Helix (hx):micro"
        "brew:aider:aider:Claude Code"
        "brew:repomix:repomix:Claude Code"
        "brew:aerc:aerc:herald"
        "brew:khal:khal:herald"
        "brew:vdirsyncer:vdirsyncer:herald"
        "brew:tldr:tldr (unmaintained, disabled upstream):tlrc"
        "cask:qlmarkdown:QLMarkdown (Quick Look):removed"
        "cask:qlstephen:QLStephen (Quick Look):removed"
        "cask:protonvpn:Proton VPN:Mullvad VPN"
        "cask:proton-mail:Proton Mail:removed"
        "cask:proton-pass:Proton Pass:removed"
        "cask:proton-drive:Proton Drive:removed"
        "cask:docker:Docker Desktop:OrbStack:Docker"
        "cask:warp:Warp terminal:Ghostty:Warp"
        "cask:iterm2:iTerm2:Ghostty:iTerm"
        "cask:cursor:Cursor (AI editor):croft + Claude Code:Cursor"
        "cask:kiro:Kiro:croft + Claude Code:Kiro"
        # NOTE: visual-studio-code is deliberately NOT here. It was retired in favour of
        # croft and reinstated as the GUI editor alongside it (#303) — croft is still
        # primary. Cursor and Kiro stay retired; the objection was to three overlapping
        # Electron editors, not to having one.
        "cask:bruno:Bruno:ATAC:Bruno"
        "cask:dbeaver-community:DBeaver Community:harlequin + lazysql:DBeaver"
        "cask:cyberduck:Cyberduck:rclone:Cyberduck"
        "cask:google-drive:Google Drive:rclone:Google Drive"
        "cask:drawio:draw.io:d2 + mermaid-cli:draw.io"
        "cask:notion:Notion:tiki:Notion"
        "cask:notion-calendar:Notion Calendar:herald:Notion Calendar"
        "brew:yazi:yazi:rovr"
        "brew:cmus:cmus:cliamp"
        "brew:kew:kew:cliamp"
        "brew:tokei:tokei:scc"
        "brew:glow:glow:leaf"
        "cask:raycast:Raycast:Ghostty quick-terminal + clipse:Raycast"
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
        "cask:firefox:Firefox:removed"
        "cask:brave-browser:Brave Browser:removed:Brave Browser"
        "cask:postman:Postman:Bruno"
        "cask:daisydisk:DaisyDisk:dust + duf (CLI)"
        "cask:proxyman:Proxyman:mitmproxy"
        "cask:appcleaner:AppCleaner:Pearcleaner"
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
        "formula:git-secrets:git-secrets:gitleaks + detect-secrets"
        "formula:trufflehog:trufflehog:gitleaks + detect-secrets"
        "cask:the-unarchiver:The Unarchiver:p7zip (CLI)"
        "cask:transmit:Transmit:Cyberduck:Transmit"
        "cask:colima:colima:OrbStack"
        "cask:blockblock:BlockBlock:removed"
        "cask:oversight:OverSight:removed"
        "cask:knockknock:KnockKnock:removed"
        "cask:reikey:ReiKey:removed"
        "cask:syntax-highlight:Syntax Highlight:removed"
        "mas:937984704:Amphetamine:removed"
        "cask:stats:Stats:removed"
        "cask:rectangle:Rectangle:removed"
        "cask:snagit:Snagit:Shottr:Snagit"
        "cask:signal:Signal:removed"
        "formula:gifski:gifski:removed"
        "mas:6475002485:Reeder:newsboat"
        "formula:mas:mas:removed"
        "cask:tableplus:TablePlus:DBeaver:TablePlus"
        "cask:iina:IINA:mpv (CLI)"
        "cask:imageoptim:ImageOptim:oxipng + jpegoptim (CLI)"
        "cask:keka:Keka:p7zip (CLI)"
        "formula:entr:entr:watchexec"
        "cask:zed:Zed:croft:Zed"
        "cask:slack:Slack:removed"
        "cask:telegram:Telegram:removed"
        "cask:notion-mail:Notion Mail:removed (retired by Notion):Notion Mail"
    )

    CLEANUP_COUNT=0
    CLEANUP_SKIPPED=0

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
                        if brew uninstall --cask "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
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
                            sudo rm -rf "/Applications/$appname.app" 2>/dev/null && success "$display removed" || error "Failed to remove $display"
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
                        sudo rm -rf "/Applications/$appname.app" 2>/dev/null || true
                        ((CLEANUP_COUNT++))
                        success "$display removed"
                    fi
                elif [[ -d "/Applications/$appname.app" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        sudo rm -rf "/Applications/$appname.app" 2>/dev/null || true
                        ((CLEANUP_COUNT++))
                        success "$display removed"
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

    # -- Orphaned editor support trees ----------------------------------------
    # Uninstalling the VS Code / Kiro / Cursor casks above removes the .app, but
    # Homebrew never owned their per-user trees — the extension folders and the
    # Application Support state stay behind indefinitely. On the maintainer's
    # machine that was ~1.5 GB across 73 extension folders for three editors that
    # had already been replaced by croft + Claude Code.
    #
    # Guarded two ways: only touch a tree whose .app is genuinely absent (so a
    # manual reinstall is never gutted), and prefer `trash` over `rm -rf` so a
    # mistake is recoverable from the Finder Trash rather than final.
    # VS Code is absent from this list by design: the script now installs it
    # (#303), so `~/.vscode` holds extensions we put there and Application Support holds
    # settings we merge into. The `.app`-present guard below would spare them on a normal
    # machine, but a failed cask install or an app moved out of /Applications would make
    # cleanup eat a managed tree. Only genuinely retired editors belong here.
    ORPHANED_EDITOR_DIRS=(
        "Kiro|$HOME/.kiro"
        "Kiro|$HOME/Library/Application Support/Kiro"
        "Cursor|$HOME/.cursor"
        "Cursor|$HOME/Library/Application Support/Cursor"
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

    # -- Orphaned config dirs -------------------------------------------------
    # Uninstalling a tool above removes the binary, never its ~/.config tree, so
    # replaced tools leave a working config behind forever — the aerc/khal/
    # vdirsyncer trio is an entire stale mail+calendar setup for tools herald
    # replaced in 7.3.0.
    #
    # The guard is binary PRESENCE, not a static list of what is retired. That
    # matters twice: a tool still installed keeps its config (you may be using
    # it), and because this sweep runs AFTER the uninstall loop above, anything
    # retired earlier in this same invocation is already gone from PATH and gets
    # swept in the same pass. hash -r first, or bash serves a cached path for a
    # binary that was deleted moments ago.
    #
    # ~/.docker is deliberately ABSENT from this list even though Docker Desktop
    # is in DEPRECATED_TOOLS. OrbStack took over that directory: config.json
    # holds `currentContext: orbstack` and the registry `auths`, with daemon.json
    # beside it. Removing it would break the docker CLI and destroy stored
    # credentials. The presence guard already saves us (OrbStack provides
    # `docker`), but do not "fix" this omission by adding the path.
    hash -r 2>/dev/null || true
    CONFIG_ORPHANS=(
        "aerc|$HOME/.config/aerc|herald"
        "khal|$HOME/.config/khal|herald"
        "vdirsyncer|$HOME/.config/vdirsyncer|herald"
        "hx|$HOME/.config/helix|micro"
        "cmus|$HOME/.config/cmus|cliamp"
        "kew|$HOME/.config/kew|cliamp"
        "glow|$HOME/.config/glow|leaf"
        "yazi|$HOME/.config/yazi|rovr"
        "tmux|$HOME/.tmux.conf|zellij"
        "aerospace|$HOME/.aerospace.toml|native Spaces + tiling"
        "nvm|$HOME/.nvm|mise"
        "pyenv|$HOME/.pyenv|mise"
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

    # -- Orphaned taps --------------------------------------------------------
    # Uninstalling a formula leaves its tap cloned and trusted forever. Only taps
    # THIS script previously used are listed — untapping anything that merely has
    # zero installed packages would delete taps the user added by hand. The
    # zero-package check is still enforced, so a tap the user has since installed
    # something else from is left alone.
    DEPRECATED_TAPS=(
        "nikitabobko/tap|AeroSpace"
        "snyk/tap|snyk"
    )
    for entry in "${DEPRECATED_TAPS[@]}"; do
        _tap="${entry%%|*}"
        _why="${entry#*|}"
        if ! brew tap 2>/dev/null | grep -qix "$_tap"; then
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if brew list --full-name 2>/dev/null | grep -qi "^${_tap}/"; then
            info "Keeping tap $_tap — still provides installed packages"
            ((CLEANUP_SKIPPED++))
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would untap $_tap (was $_why; provides nothing)"
        else
            info "Untapping $_tap (was $_why; provides nothing)..."
            if brew untap "$_tap" >> "$LOG_FILE" 2>&1; then
                ((CLEANUP_COUNT++)); success "$_tap untapped"
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

    # asciinema has no `config check`. It does fail loudly on a config it cannot
    # read, so drive its cheapest subcommand and look for a CONFIG complaint —
    # not the unrelated "Device not configured" that a non-tty play always emits.
    _verify_asciinema() {
        local out cast; cast="$(mktemp)"
        printf '{"version":2,"width":80,"height":24}\n' > "$cast"
        out="$(asciinema play "$cast" 2>&1)"
        rm -f "$cast"
        ! grep -qiE 'TOML parse error|asciinema 2\.x|invalid type' <<<"$out"
    }

    VERIFY_TARGETS=(
        "validate|ghostty|$HOME/.config/ghostty/config|ghostty +validate-config"
        "validate|zellij|$HOME/.config/zellij/config.kdl|zellij setup --check 2>&1 | grep -q 'Well defined'"
        "validate|ngrok|$HOME/Library/Application Support/ngrok/ngrok.yml|ngrok config check"
        "validate|asciinema|$HOME/.config/asciinema/config.toml|_verify_asciinema"
        "template|borgmatic|$HOME/.config/borgmatic/config.yaml|borgmatic config validate"
        "path|k9s|$HOME/.config/k9s/config.yaml|k9s info 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^Config: *//p'"
        "path|mise|$HOME/.config/mise/config.toml|mise config ls 2>/dev/null | awk 'NR==1 {print \$1}' | sed \"s|^~|\$HOME|\""
        "path|lazygit|$HOME/.config/lazygit/config.yml|echo \"\$(lazygit --print-config-dir)/config.yml\""
        "path|nu|$HOME/.config/nushell/env.nu|nu -c '\$nu.env-path' 2>/dev/null | tail -1"
        "path|atuin|$HOME/.config/atuin/config.toml|atuin info 2>/dev/null | awk -F'\"' '/client config:/ {print \$2}'"
        "path|bat|$(bat --config-file 2>/dev/null)|bat --config-file"
        "unchecked|starship|$HOME/.config/starship.toml|"
        "unchecked|topgrade|$HOME/.config/topgrade.toml|"
        "unchecked|trippy|$HOME/.config/trippy/trippy.toml|"
        "unchecked|git-cliff|$HOME/.config/git-cliff/cliff.toml|"
        "unchecked|harlequin|$HOME/.config/harlequin/config.toml|"
        "unchecked|gh-dash|$HOME/.config/gh-dash/config.yml|"
        "unchecked|stern|$HOME/.config/stern/config.yaml|"
        "unchecked|lazydocker|$HOME/.config/lazydocker/config.yml|"
        "unchecked|yt-dlp|$HOME/.config/yt-dlp/config|"
        "unchecked|micro|$HOME/.config/micro/settings.json|"
    )

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
                if [[ -z "$_vp" ]]; then
                    printf "  ${YELLOW}%-12s${NC} %s — could not read its config path back\n" "UNKNOWN" "$label"
                    ((VERIFY_GAP++))
                elif [[ "$_vp" == "$path" ]]; then
                    printf "  ${GREEN}%-12s${NC} %s — reads the path we write\n" "OK" "$label"
                    ((VERIFY_OK++))
                else
                    printf "  ${RED}%-12s${NC} %s — reads a DIFFERENT path than we write\n" "FAIL" "$label"
                    printf "               ${DIM}we write:  %s${NC}\n" "$path"
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

    echo ""
    echo -e "  ${GREEN}${BOLD}Verified:${NC}    $VERIFY_OK"
    echo -e "  ${RED}${BOLD}Failed:${NC}      $VERIFY_BAD"
    echo -e "  ${YELLOW}${BOLD}Seed:${NC}        $VERIFY_SEED"
    echo -e "  ${DIM}Unverified:  $VERIFY_GAP${NC}"
    echo -e "  ${DIM}Skipped:     $VERIFY_SKIP${NC}"
    echo ""
    if [[ "$VERIFY_BAD" -gt 0 ]]; then
        echo -e "${RED}A FAIL means the file is fine and the tool is not reading it.${NC}"
        echo -e "${DIM}That is the #329/#332 shape: valid config, wrong address, no error anywhere.${NC}"
        echo ""
        exit 1
    fi
    exit 0
fi

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

# Xcode Command Line Tools (required for git, homebrew, compilers, etc.)
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
    installer="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" -o "$installer"
    if [[ ! -s "$installer" ]]; then
        error "Failed to download Homebrew installer"
        rm -f "$installer"
        exit 1
    fi
    /bin/bash "$installer"
    rm -f "$installer"
    # Add to path for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    success "Homebrew installed"
else
    warn "Homebrew already installed"
    info "Updating Homebrew..."
    brew update
fi

# Prevent brew from auto-updating on every install (we already updated above)
export HOMEBREW_NO_AUTO_UPDATE=1

# GNU coreutils (Linux-compatible sed, tar, awk, grep for script portability)
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
    # did not already have mise's node in front, and every npm_global_install below (Claude
    # Code, prettier, commitizen, copilot, …) silently no-ops while the run still reports
    # "Failed: 0". `mise which` resolves the real binary without needing the hook.
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
brew_install "jq" "jq (JSON processor)"
brew_install "direnv" "direnv (per-project env vars)"
brew_install "watchman" "Watchman (file watcher)"
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
        installer="$(mktemp)"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download rustup installer"
        elif sh "$installer" -y --no-modify-path >> "$LOG_FILE" 2>&1; then
            source "$HOME/.cargo/env" 2>/dev/null || true
            success "Rust installed via rustup"
        else
            error "Failed to install Rust via rustup (check $LOG_FILE)"
        fi
        rm -f "$installer"
    fi
else
    warn "Rust (rustup) already installed"
fi
mark_done "install:rust"
fi

# Docker (OrbStack is faster alternative — both installed, pick your preference)
brew_cask_install "orbstack" "OrbStack (Docker runtime — faster, 2-5x less memory than Docker Desktop)"

# bun (fast JS runtime, bundler, test runner — alternative to Node for scripts)
# Trust the tap explicitly. A fully-qualified `user/tap/formula` install auto-taps,
# but Homebrew 6's trust gate is separate from tapping — every other tapped formula
# here is preceded by trust_tap, and these two were the only ones relying on the
# fully-qualified form instead. Already-provisioned machines have the trust recorded
# from earlier runs, so the gap only bites a FRESH install. Redundant if brew treats
# the qualified form as consent; correct either way.
trust_tap oven-sh/bun
brew_install "oven-sh/bun/bun" "bun (fast JS runtime/bundler/test runner)"

# pnpm
progress
if ! is_done "install:pnpm"; then
if ! installed pnpm; then
    info "Installing pnpm..."
    installer="$(mktemp)"
    curl -fsSL "https://get.pnpm.io/install.sh" -o "$installer"
    if [[ ! -s "$installer" ]]; then
        error "Failed to download pnpm installer"
        rm -f "$installer"
    elif bash "$installer" >> "$LOG_FILE" 2>&1; then
        success "pnpm installed"
        rm -f "$installer"
    else
        error "Failed to install pnpm (check $LOG_FILE)"
        rm -f "$installer"
    fi
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
# bun
if ! installed bun && [[ -d "$HOME/.bun/bin" ]]; then
    export PATH="$HOME/.bun/bin:$PATH"
fi
# Report what's available
for tool in node npm go cargo rustc bun pnpm uv; do
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

brew_install "git" "Git"
brew_install "gh" "GitHub CLI"
# GitHub stays primary; glab is the GitLab CLI for client repos hosted on GitLab.
brew_install "glab" "glab (GitLab CLI — mirrors gh conveniences for GitLab repos)"
brew_install "git-delta" "delta (better git diffs)"
brew_install "git-lfs" "Git LFS"
brew_install "gnupg" "GnuPG (commit signing)"
brew_install "pinentry-mac" "pinentry-mac (GPG passphrase)"
brew_install "lazygit" "lazygit (terminal UI for git)"
brew_install "git-absorb" "git-absorb (auto-fixup commits)"
brew_install "git-cliff" "git-cliff (generate changelogs from conventional commits)"
# gk — GitKraken's CLI, installed for exactly one reason: it serves the GitKraken MCP
# server registered with Claude Code further down. It used to arrive as a 19 MB binary
# that the GitLens VS Code extension downloaded into its own globalStorage, which meant
# an MCP server this setup depends on lived inside an extension no generator step owned
# and that uninstalling the extension silently killed 31 agent tools (#362). The cask
# ships `gk` as a Binary artifact, so it is on PATH straight after install.
brew_cask_install "gitkraken-cli" "GitKraken CLI (gk — serves the GitKraken MCP server)"

# pre-commit
brew_install "pre-commit" "pre-commit (git hook framework)"

# Configure delta as default git pager if not already set
if ! git config --global core.pager | grep -q delta 2>/dev/null; then
    info "Configuring delta as git pager..."
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global merge.conflictstyle diff3
    success "delta configured as git pager"
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
    npm_global_install "cdk-nag" "cdk-nag"
else
    progress; progress  # keep progress bar accurate when npm unavailable
fi

# -- AWS TUIs (k9s-style, per service) --
brew_install "e1s" "e1s (ECS TUI — clusters/services/tasks, exec, logs, port-forward)"
brew_install "stu" "stu (S3 TUI — browse/preview/download buckets)"
# e2c (EC2 TUI) — young project; not on Homebrew, install via Go.
go_install github.com/nlamirault/e2c/cmd/e2c@latest e2c "e2c (EC2 TUI)"
# claws — broad all-AWS TUI (young); cask from the clawscli tap.
trust_tap clawscli/tap
brew_cask_install "claws" "claws (all-AWS TUI — ~70 services, k9s-style; young project)"

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
brew_install "iamlive" "iamlive (generate least-privilege IAM policies from observed API calls)"

fi  # aws

# =============================================================================
if should_run "iac"; then
banner "Infrastructure as Code"

brew_install "opentofu" "OpenTofu (open-source Terraform — multi-cloud IaC)"
trust_tap terraform-linters/tap
brew_install "tflint" "tflint (Terraform linter — terraform-linters tap, not homebrew-core)"
brew_install "terraform-docs" "terraform-docs (auto-generate module docs from variables/outputs)"
brew_install "checkov" "checkov (IaC static analysis — Terraform, CloudFormation, Kubernetes, Dockerfile)"
brew_install "infracost" "infracost (cost estimation for Terraform changes before apply)"
# Note: tfsec was folded into trivy (installed under 'security'). Run `trivy config .`
# instead — same Terraform misconfig coverage, broader scan surface.

fi  # iac

# =============================================================================
if should_run "security"; then
banner "Security & Secrets"

# Secret management
brew_install "age" "age (modern file encryption)"
brew_install "sops" "sops (encrypt secrets in YAML/JSON, works with AWS KMS)"

# detect-secrets (Yelp's pre-commit secret detection) — available as brew formula
brew_install "detect-secrets" "detect-secrets (Yelp pre-commit secret detection)"

# Code & dependency security
brew_install "gitleaks" "gitleaks (fast git secret scanning — great for CI/pre-commit)"
brew_install "trivy" "trivy (container & IaC vulnerability scanning)"
brew_install "semgrep" "semgrep (static analysis — bugs & security issues)"
brew_install "cosign" "cosign (sign & verify container images)"

# Network security
brew_install "mkcert" "mkcert (local HTTPS certs for dev)"
brew_install "ssh-audit" "ssh-audit (audit SSH server/client config)"

# ClamAV (open-source antivirus)
brew_install "clamav" "ClamAV (open-source antivirus)"
# ClamAV ships no virus database and only *.conf.sample files, so `clamscan` fails with
# "No supported database files" until freshclam.conf exists and `freshclam` has run.
# Seed a minimal freshclam.conf and register a LaunchAgent that fetches the DB on load
# (in the background, so setup isn't blocked on a ~250 MB download) and refreshes daily.
# On-demand scanner — no resident clamd daemon.
if [[ "$DRY_RUN" != "true" ]] && installed clamav; then
    CLAMAV_ETC="$(brew --prefix)/etc/clamav"
    mkdir -p "$CLAMAV_ETC"
    if [[ ! -f "$CLAMAV_ETC/freshclam.conf" ]]; then
        if [[ -f "$CLAMAV_ETC/freshclam.conf.sample" ]]; then
            grep -v '^Example' "$CLAMAV_ETC/freshclam.conf.sample" > "$CLAMAV_ETC/freshclam.conf"
        else
            printf 'DatabaseMirror database.clamav.net\n' > "$CLAMAV_ETC/freshclam.conf"
        fi
    fi
    FRESHCLAM_PLIST="$HOME/Library/LaunchAgents/com.freshclam.update.plist"
    if [[ ! -f "$FRESHCLAM_PLIST" ]]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$FRESHCLAM_PLIST" <<FRESHCLAM_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.freshclam.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(brew --prefix)/bin/freshclam</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
</dict>
</plist>
FRESHCLAM_PLIST_EOF
        launchctl load "$FRESHCLAM_PLIST" >> "$LOG_FILE" 2>&1 || true
        success "ClamAV freshclam.conf seeded + daily DB updater registered (first fetch runs in background)"
    fi
fi

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
    if mkcert -install >> "$LOG_FILE" 2>&1; then
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
banner "Modern Tool Replacements"
echo "  (upgrades for standard macOS/Unix utilities)"
echo ""

# ls -> eza (formerly exa): icons, git status, tree view, colors
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
brew_install "curlie" "curlie (curl with httpie-like output)"

# dig -> doggo: colorized DNS, supports DoH/DoT (dog is abandoned, doggo is the maintained successor)
brew_install "doggo" "doggo (replaces dig — colorized DNS, DoH support)"

# wc -> scc: lines of code by language + COCOMO cost/effort + complexity estimates
brew_install "scc" "scc (replaces wc for code — LOC by language, complexity + COCOMO cost)"

# tree (enhanced built-in) - if not using eza --tree
brew_install "tree" "tree (directory listing)"

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

# surge — interactive TUI download manager whose browser extension intercepts
# browser-started downloads and hands them to a background daemon (port 1700).
# Complements aria2 (aria2 = CLI/scripts; surge = interactive + browser capture).
trust_tap SurgeDM/tap
# surge is distributed as a cask (prebuilt binary) in SurgeDM/tap, not a formula.
brew_cask_install "surge" "surge (TUI download manager — browser-download capture via a daemon + extension)"
# Register the surge background service so the browser extension has something to
# talk to. May prompt for your password; non-fatal if it doesn't (do it later via
# `surge service install`). Extension install + token are in the POST_SETUP checklist.
if [[ "$DRY_RUN" != "true" ]] && command -v surge &>/dev/null; then
    if surge service install >> "$LOG_FILE" 2>&1; then
        success "surge daemon service installed (browser extension can now connect on :1700)"
    else
        warn "Could not install surge service now — run 'surge service install' later (see checklist)"
    fi
fi

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

# file manager -> rovr: mouse-first, VS Code-Explorer-style TUI file manager (Textual).
# nnn is kept (below) as a fast, minimal fallback. rovr is not on Homebrew — install
# via uv (needs Python 3.13, which uv fetches automatically).
uv_tool_install rovr rovr "rovr (mouse-first TUI file manager; uv fetches Python 3.13)" \
    "rovr installed (mouse-first TUI file manager)" --python 3.13

# jq (interactive) -> fx: interactive JSON viewer/processor
brew_install "fx" "fx (interactive JSON viewer — better than jq for exploring)"
brew_install "jnv" "jnv (interactive JSON navigator with jq filtering)"

fi  # replacements

# =============================================================================
if should_run "data-processing"; then
banner "Data & File Processing"

# yq: jq for YAML (essential for k8s/CDK)
brew_install "yq" "yq (jq for YAML — essential for k8s/CDK work)"

# miller: awk/sed/jq for CSV, JSON, tabular data
brew_install "miller" "miller (awk/sed/jq for CSV, JSON, tabular data)"

# csvkit: suite of CSV tools
brew_install "csvkit" "csvkit (CSV tools — csvcut, csvgrep, csvstat)"

# pandoc: universal document converter
brew_install "pandoc" "pandoc (universal document converter — md, pdf, docx, html)"

# tectonic: self-contained LaTeX engine so pandoc can actually produce PDFs. A bare
# Mac has no PDF engine, so `pandoc -o x.pdf` fails with "pdflatex not found".
# tectonic is a single binary that fetches TeX packages on demand (fits CLI-first,
# minimal). pandoc won't auto-pick it, so pass the flag: pandoc in.md -o out.pdf --pdf-engine=tectonic
brew_install "tectonic" "tectonic (self-contained LaTeX/PDF engine for pandoc — md → pdf via --pdf-engine=tectonic)"

# imagemagick: image manipulation CLI
brew_install "imagemagick" "ImageMagick (image resize, convert, composite)"

# poppler: PDF utilities — pdftoppm (PDF->PNG), pdftotext, pdfinfo. Lets Claude
# rasterize the PDFs LibreOffice produces so it can visually inspect slides/pages.
brew_install "poppler" "poppler (PDF tools — pdftoppm, pdftotext, pdfinfo)"

# ffmpeg: video/audio processing
brew_install "ffmpeg" "ffmpeg (video/audio processing swiss army knife)"

# yt-dlp: video/audio downloader
brew_install "yt-dlp" "yt-dlp (video/audio downloader)"

fi  # data-processing

# =============================================================================
if should_run "code-quality"; then
banner "Code Quality"

brew_install "shellcheck" "shellcheck (shell script linter)"
brew_install "shfmt" "shfmt (shell script formatter)"
brew_install "act" "act (run GitHub Actions locally)"
trust_tap dhth/tap
brew_install "act3" "act3 (glance at last 3 GitHub Actions runs — dhth tap, not homebrew-core)"
brew_install "hadolint" "hadolint (Dockerfile linter — catches bad practices)"

# Python linting (ruff — extremely fast, replaces flake8+black+isort)
brew_install "ruff" "ruff (fast Python linter+formatter — replaces flake8+black+isort)"
# prettier — the JS/TS/CSS/MD formatter the generated CLAUDE.md mandates and the
# pre-push checklist runs. It was documented but never installed, so the Claude
# format-on-edit hook found nothing on PATH and silently no-opped.
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

# JS/TS workflow
if installed npm; then
    npm_global_install "npkill" "npkill (find and nuke node_modules folders — reclaim disk)"
    npm_global_install "commitizen" "commitizen (interactive conventional commits)"
    # Adapter for commitizen — without it (+ ~/.czrc below) `cz`/`git cz` errors with
    # "cannot load your commitizen adapter". Installed into the same global root as
    # commitizen so it resolves as a sibling.
    npm_global_install "cz-conventional-changelog" "cz-conventional-changelog (commitizen adapter)"
    # commitlint is PROJECT-SCOPED: its resolve-extends runs from the repo cwd, so a
    # global config can't resolve @commitlint/config-conventional. Wire commitlint +
    # config-conventional as per-project devDeps (e.g. via pre-commit/husky); no global
    # config is shipped here — it wouldn't resolve.
    npm_global_install "@commitlint/cli" "commitlint (conventional-commit linter — wire per-project)"
    npm_global_install "@antfu/ni" "ni (universal package runner — auto-detects npm/yarn/pnpm/bun)"
else
    progress; progress; progress; progress; progress  # keep progress bar accurate when npm unavailable
fi

# commitizen adapter config — JSON, so written directly (write_managed would inject
# comment markers and break the JSON). Points cz at the conventional-changelog adapter.
if ! is_done "config:czrc"; then
    if [[ "$DRY_RUN" != "true" ]]; then
        printf '{ "path": "cz-conventional-changelog" }\n' > "$HOME/.czrc"
        success "commitizen adapter wired (~/.czrc → cz-conventional-changelog)"
    fi
    mark_done "config:czrc"
fi

fi  # code-quality

# =============================================================================
if should_run "perf-testing"; then
banner "Performance & Load Testing"

brew_install "hyperfine" "hyperfine (command benchmarking)"
brew_install "oha" "oha (HTTP load testing, Rust-based)"
brew_install "hurl" "hurl (HTTP requests from plain text files — curl + test runner)"

fi  # perf-testing

# =============================================================================
if should_run "dev-servers"; then
banner "Dev Servers & Tunnels"

brew_cask_install "ngrok" "ngrok (expose localhost to the internet)"
brew_install "miniserve" "miniserve (instant file server from any directory)"
brew_install "caddy" "caddy (modern web server with automatic HTTPS)"

fi  # dev-servers

# =============================================================================
if should_run "terminal-productivity"; then
banner "Terminal Productivity"

brew_install "leaf-markdown-viewer" "leaf (terminal Markdown previewer — live watch, fuzzy picker, Mermaid/LaTeX, inline mode)"
# leaf shell completions: `leaf --auto-complete` auto-detects the login shell
# (from $SHELL) and installs completions; a shell restart activates them. One-time.
if [[ "$DRY_RUN" != "true" ]] && command -v leaf &>/dev/null && ! is_done "config:leaf-completions"; then
    if leaf --auto-complete >> "$LOG_FILE" 2>&1; then
        success "leaf shell completions installed (restart shell to activate)"
    else
        warn "Could not install leaf completions (run manually: leaf --auto-complete)"
    fi
    mark_done "config:leaf-completions"
fi
brew_install "watchexec" "watchexec (run commands on file changes — better entr)"
brew_install "pv" "pv (pipe viewer — progress bars for pipes)"
brew_install "parallel" "parallel (GNU parallel — run commands in parallel)"
brew_install "asciinema" "asciinema (record & share terminal sessions)"
brew_install "gum" "gum (shell script UI toolkit — prompts, spinners, confirmations)"
brew_install "nushell" "nushell (structured data shell — pipelines output tables)"
brew_install "topgrade" "topgrade (update everything — brew, npm, pip, macOS, all at once)"
brew_install "fastfetch" "fastfetch (quick system info display — faster neofetch)"
brew_install "nano" "nano (latest — better than macOS built-in)"
brew_install "lnav" "lnav (advanced log file viewer — auto-format, SQL queries on logs)"
brew_install "nnn" "nnn (tiny, fast terminal file manager)"
brew_install "progress" "progress (coreutils progress viewer — cp, mv, dd, tar)"

# -- Additional TUI/CLI tools (homebrew-core) --
brew_install "doxx" "doxx (.docx viewer in the terminal)"
brew_install "taproom" "taproom (interactive Homebrew TUI — browse formulae & casks)"
brew_install "lazyssh" "lazyssh (SSH connection manager TUI)"
brew_install "lazyrsync" "lazyrsync (rsync TUI with reusable profiles)"
brew_install "libqalculate" "qalc (powerful CLI calculator — units, live currency, variables)"
brew_install "vhs" "vhs (scripted terminal GIF/MP4 recorder — pairs with asciinema)"

# -- Additional TUI/CLI tools (third-party taps) --
trust_tap jesseduffield/lazynpm
brew_install "lazynpm" "lazynpm (npm TUI — joins lazygit/lazydocker/lazysql)"
trust_tap djetelina/tap
brew_install "cheznav" "cheznav (chezmoi dotfiles TUI — dual-pane add/apply/diff)"
trust_tap bendews/tap
brew_install "apw" "apw (Apple Passwords + OTP from the CLI)"
trust_tap kdabir/tap
brew_install "has" "has (checks presence & versions of CLI tools)"
trust_tap jordond/tap
brew_install "jolt" "jolt (battery / energy monitor TUI)"
trust_tap ikebastuz/wiper
brew_install "wiper" "wiper (interactive disk usage + cleanup — Trash-safe, ncdu-like)"

# lazyenv — TUI for managing .env files across projects (diff/sync, secret masking,
# .gitignore checks). Complements direnv (direnv loads; lazyenv edits/compares).
trust_tap lazynop/tap
brew_install "lazyenv" "lazyenv (TUI for .env files — diff/sync across projects, secret masking)"
# keyward — TUI SSH-key manager + A–F security audit + encrypted key backups.
trust_tap gateway-of-last-resort/tap
brew_install "keyward" "keyward (SSH-key manager + security audit — offline, single binary)"
# bmm — CLI/TUI bookmark manager (local, fzf-friendly). dhth/tap already trusted above.
brew_install "bmm" "bmm (bookmark manager — CLI + TUI, local, import HTML/JSON/TXT)"
# manly — explains the flags in a command by pulling the relevant man-page lines.
uv_tool_install manly manly "manly (man-page explainer — 'manly tar -xzf')" "manly installed"

# starlit (weather CLI) — PyPI package 'starlit-cli', installed via uv.
uv_tool_install starlit-cli starlit "starlit (weather CLI)" \
    "starlit installed (run 'starlit --setup' to add an OpenWeatherMap key)"

fi  # terminal-productivity

# =============================================================================
if should_run "k8s-github"; then
banner "Kubernetes & GitHub Extras"

brew_install "stern" "stern (multi-pod log tailing for k8s)"

# gh-dash (GitHub dashboard extension)
progress
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-dash"; then
        warn "gh-dash already installed"
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

brew_install "pgcli" "pgcli (auto-completing Postgres CLI)"
brew_install "mycli" "mycli (auto-completing MySQL CLI)"
brew_install "lazysql" "lazysql (TUI for databases — interactive SQL in terminal)"

# harlequin (terminal SQL IDE — DuckDB/Postgres/MySQL, multi-tab, autocomplete)
uv_tool_install 'harlequin[postgres,mysql,s3]' harlequin \
    "harlequin (terminal SQL IDE; postgres,mysql,s3 adapters)" \
    "harlequin installed (DuckDB + Postgres + MySQL + S3 adapters)"
# usql — not in Homebrew, install via Go (@latest intentionally unpinned).
# go_install is DRY_RUN-aware and lands the binary in GOBIN (on PATH).
go_install github.com/xo/usql@latest usql "usql (universal SQL CLI)"
# Trust the tap explicitly — see the bun install for why the fully-qualified
# formula name is not sufficient on a fresh machine.
trust_tap neilotoole/sq
brew_install "neilotoole/sq/sq" "sq (jq for databases — query SQLite, Postgres, CSV from one tool)"
brew_install "dbmate" "dbmate (lightweight DB migrations)"
# DBeaver (GUI) removed — TUI/CLI coverage: harlequin (SQL IDE), lazysql,
# pgcli, mycli, usql, sq (all installed above).

fi  # database

# =============================================================================
if should_run "containers"; then
banner "Containers & Orchestration"

brew_install "lazydocker" "lazydocker (terminal UI for Docker)"
brew_install "dive" "dive (explore Docker image layers)"
brew_install "kubectl" "kubectl (Kubernetes CLI)"
brew_install "k9s" "k9s (terminal UI for Kubernetes)"

fi  # containers

# =============================================================================
if should_run "api"; then
banner "API Development"

brew_install "atac" "ATAC (terminal API client — TUI + scriptable CLI, Postman import, git-friendly collections)"
brew_install "grpcurl" "grpcurl (curl for gRPC)"

fi  # api

# =============================================================================
if should_run "networking"; then
banner "Networking & Debugging"

brew_install "mtr" "mtr (combines ping + traceroute)"
brew_install "bandwhich" "bandwhich (real-time bandwidth by process)"
brew_install "nmap" "nmap (network scanning)"
brew_install "trippy" "trippy (modern traceroute TUI with charts)"

fi  # networking

# =============================================================================
if should_run "dx"; then
banner "Developer Experience"

# Terminal tools
brew_install "fzf" "fzf (fuzzy finder)"
brew_install "starship" "Starship (shell prompt)"

# Shell plugins
brew_install "zsh-autosuggestions" "zsh-autosuggestions (Fish-like inline suggestions)"
brew_install "zsh-syntax-highlighting" "zsh-syntax-highlighting (command coloring)"
brew_install "atuin" "atuin (replaces shell history — SQLite-backed, searchable)"

# mise (single tool version manager — can replace nvm + pyenv)
# mise already installed in core section

# Editors & terminals
# micro is the $EDITOR for git/gh/lazygit commit messages and quick edits (a full IDE is
# clunky for those); croft (below) is the primary IDE. It replaced Helix in 7.6.0: modal
# editing was friction rather than help here, and micro is the opposite trade — non-modal
# (Ctrl+S/Ctrl+Q/Ctrl+C-V, nothing to learn) with a `keymenu` strip that keeps the
# bindings on screen. Ships dracula-tc as a built-in colorscheme, so there is no theme
# file to maintain.
brew_install "micro" "micro (non-modal terminal editor — \$EDITOR for git; on-screen key menu)"
# croft — VS Code-style terminal IDE (primary editor). Rust, not on Homebrew; installed
# from git main via cargo. Build in a .noindex dir so macOS Spotlight doesn't churn/heat
# during the compile. AI pairing via `croft pair` rides the existing `claude` CLI
# auth by default (--provider claude); no separate ANTHROPIC_API_KEY needed.
if command -v croft &>/dev/null; then
    warn "croft already installed"
    progress
elif installed cargo; then
    info "Installing croft (primary terminal IDE) via cargo — compiles from source, may take a few minutes..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would: cargo install --git https://github.com/vitali87/croft.git --locked"
    else
        _croft_target="$HOME/.cache/croft-build.noindex"
        mkdir -p "$_croft_target"
        if CARGO_TARGET_DIR="$_croft_target" cargo install --git https://github.com/vitali87/croft.git --locked >> "$LOG_FILE" 2>&1; then
            success "croft installed (primary IDE — run 'croft' to open, 'croft pair' for the AI navigator)"
        else
            error "Failed to install croft via cargo"
        fi
        unset _croft_target
    fi
    progress
else
    warn "Skipping croft — Rust/cargo not installed (rustup provides it)"
    progress
fi
# Visual Studio Code — the GUI editor, secondary to croft (#303). croft covers the
# terminal case and stays primary; this is the escape hatch for the things a TUI still
# loses at (long refactors across many tabs, graphical diffs, extension-backed previews)
# and for .editorconfig repos, which croft does not read at all. Reinstated after the 7.x
# declutter removed all three Electron editors: the objection was to running VS Code *and*
# Cursor *and* Kiro, not to having one.
#
# The cask ships `code` as a Binary artifact, so the CLI is on PATH straight after
# install — the extension loop below depends on that.
brew_cask_install "visual-studio-code" "Visual Studio Code (GUI editor — croft stays primary)"

# Extensions. Every entry mirrors a CLI this script already installs, so the GUI editor
# enforces the same rules as the terminal: ruff not black, taplo for TOML, shellcheck +
# shfmt for shell, d2 for diagrams, EditorConfig honoured (which croft itself does not
# support). Verified against the marketplace before landing — a wrong ID is a single red
# line in a long run, not a loud failure.
#
# Read the installed list ONCE: `code --list-extensions` boots Electron (~1s), so the
# per-extension check inside vscode_ext_install reads this cache instead of shelling out
# 27 times on an already-provisioned machine.
if installed code && [[ "$DRY_RUN" != "true" ]]; then
    _VSCODE_EXTS=$(code --list-extensions 2>/dev/null || true)
fi
# Core — the ones that apply regardless of language
vscode_ext_install "anthropic.claude-code" "Claude Code for VS Code"
vscode_ext_install "dracula-theme.theme-dracula" "Dracula Official (theme — matches every other tool here)"
vscode_ext_install "editorconfig.editorconfig" "EditorConfig (per-repo indent rules)"
vscode_ext_install "esbenp.prettier-vscode" "Prettier (JS/TS/CSS/MD formatter)"
vscode_ext_install "dbaeumer.vscode-eslint" "ESLint"
vscode_ext_install "github.vscode-pull-request-github" "GitHub Pull Requests (matches the gh PR workflow)"
vscode_ext_install "github.vscode-github-actions" "GitHub Actions (workflow syntax + run status)"
vscode_ext_install "usernamehw.errorlens" "Error Lens (inline diagnostics)"
vscode_ext_install "streetsidesoftware.code-spell-checker" "Code Spell Checker (GUI counterpart to typos)"
vscode_ext_install "mikestead.dotenv" ".env syntax highlighting"
# Languages — pairs with the language servers installed above for croft
vscode_ext_install "ms-python.python" "Python"
vscode_ext_install "detachhead.basedpyright" "basedpyright (Python type server — the same one croft uses)"
vscode_ext_install "charliermarsh.ruff" "Ruff (Astral — the linter/formatter this setup mandates)"
vscode_ext_install "rust-lang.rust-analyzer" "rust-analyzer (Rust)"
vscode_ext_install "golang.go" "Go"
vscode_ext_install "tamasfe.even-better-toml" "Even Better TOML (taplo-backed)"
vscode_ext_install "redhat.vscode-yaml" "YAML"
vscode_ext_install "bradlc.vscode-tailwindcss" "Tailwind CSS IntelliSense"
# Infrastructure
vscode_ext_install "ms-azuretools.vscode-docker" "Docker"
vscode_ext_install "hashicorp.terraform" "HashiCorp Terraform (reads OpenTofu .tf files)"
vscode_ext_install "ms-vscode-remote.remote-containers" "Dev Containers (OrbStack provides the runtime)"
# Shell — the editors' half of shellcheck + shfmt
vscode_ext_install "timonwong.shellcheck" "ShellCheck"
vscode_ext_install "foxundermoon.shell-format" "shell-format (shfmt-backed)"
# Docs & tasks
vscode_ext_install "terrastruct.d2" "D2 (diagram syntax + preview)"
vscode_ext_install "bierner.markdown-mermaid" "Mermaid in Markdown preview"
vscode_ext_install "nefrob.vscode-just-syntax" "just (Justfile syntax)"

# GitLens is NOT installed here, deliberately (#362). It was, for a long time, described in
# this list as "blame, history, authorship" — three things lazygit, delta, difft and
# git-cliff already do, in the terminal, which is where the work happens. GitLens 19 is a
# much bigger freemium product than that description admits (Launchpad, Cloud Patches, Code
# Suggest, workspaces, AI commit messages), most of it Pro-gated or duplicating a CLI above,
# on an editor that is the escape hatch rather than the daily driver. 34 MB and an account
# nag for a feature surface that went unused, which is the opposite of the rule stated at the
# top of this list: every entry mirrors a CLI this script already installs.
#
# It was NOT a clean removal, and that is the part worth remembering. GitLens had
# auto-registered the GitKraken MCP server into ~/.claude.json pointing at a `gk` binary
# inside its own globalStorage — so 31 Claude Code tools depended on an extension no step in
# this script owned, and uninstalling it would have killed them silently. `gitkraken-cli` is
# now installed in the git section above and the MCP server is registered from here, so the
# generator owns both ends. The standalone `gk mcp` serves the same 31 tools and reads the
# same auth store; verified at tool-list and tool-call parity before the extension went.
#
# The one feature with no CLI equivalent is the inline blame annotation on the current line.
# If it is ever missed, waderyan.gitblame is ~200 KB for that single behaviour.

# GitHub Copilot is NOT installed here, deliberately (#356). Current VS Code ships it
# BUILT IN — 1.136.1 carries copilot-chat 0.64.1 inside the app bundle
# (Contents/Resources/app/extensions/copilot). `code --install-extension github.copilot`
# pulls github.copilot-chat as a dependency and then fails:
#
#   Extension 'github.copilot-chat' is a built-in extension with version '0.64.1'
#   and cannot be downgraded to version '0.48.1'.
#
# So adding it to this list buys nothing and prints a red "Failed" on every run — the kind
# of routine noise that trains you to skim past real failures (the #327 lesson). Sign in to
# the bundled extension instead; nothing needs installing. The CLI is a separate package and
# IS managed, in the dx section.

# Pylance — remove it (#308). `ms-python.python` declares an `extensionPack` of
# [vscode-pylance, debugpy, vscode-python-envs], so installing Python silently also
# installs Microsoft's *proprietary* type server. That contradicts the decision made in
# #296, which chose basedpyright for croft precisely because it is the same server with
# the closed-source parts restored as open source. Worse, it is not inert: with Pylance
# installed, `python.languageServer: "Default"` resolves TO Pylance, so it — not
# basedpyright — is what actually analyses Python in VS Code. The settings block pins
# `python.languageServer: "None"` so ms-python starts no server of its own.
#
# Done HERE rather than in DEPRECATED_TOOLS, following the tlrc precedent from 7.11.0: a
# swap left to `--cleanup` only ever reaches fresh machines. Pylance ships as a pack
# member to every machine that installs ms-python.python, so the removal has to run where
# the install runs, on every run, idempotently.
#
# debugpy and vscode-python-envs are kept — both MIT, and genuinely useful.
if installed code && [[ "$DRY_RUN" != "true" ]]; then
    if printf '%s\n' "$_VSCODE_EXTS" | grep -qix -- "ms-python.vscode-pylance" \
       || code --list-extensions 2>/dev/null | grep -qix -- "ms-python.vscode-pylance"; then
        info "Removing Pylance (proprietary — basedpyright is the type server here)..."
        if code --uninstall-extension ms-python.vscode-pylance >> "$LOG_FILE" 2>&1; then
            success "Pylance removed (VS Code now uses basedpyright, same as croft)"
        else
            warn "Could not remove Pylance — uninstall it manually from the Extensions pane"
        fi
    fi
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would remove Pylance if present (proprietary; basedpyright replaces it)"
fi
unset _VSCODE_EXTS

brew_cask_install "ghostty" "Ghostty (fast GPU-accelerated terminal)"
brew_install "zellij" "zellij (modern terminal multiplexer — discoverable UI, layouts)"

# Language servers for croft (LSP for the main languages out of the box). These outlived
# the Helix removal in 7.6.0 — croft consumes them too, so retiring Helix orphaned nothing.
# Python uses ruff's built-in server (already installed). TOML/Markdown via brew:
brew_install "taplo" "taplo (TOML language server + formatter — used by croft)"
brew_install "marksman" "marksman (Markdown language server — used by croft)"
if installed npm; then
    npm_global_install "typescript-language-server" "TypeScript/JavaScript language server (croft LSP)"
    npm_global_install "vscode-langservers-extracted" "HTML/CSS/JSON/ESLint language servers (croft LSP)"
    npm_global_install "bash-language-server" "Bash language server (croft LSP)"
    npm_global_install "yaml-language-server" "YAML language server (croft LSP)"
else
    progress; progress; progress; progress  # keep progress bar accurate when npm unavailable
fi

# Python language servers. croft ships a built-in manifest — "Python (ty +
# basedpyright + ruff)" — that expects these by exact command name, with `ty` at
# priority 0 ("wins every capability it advertises"), basedpyright as the fallback
# for what ty does not yet cover, and ruff for lint. Without them croft falls
# through to ruff alone: lint and format, no type checking or go-to-definition,
# which left Python the one language here without full coverage (#288). PyPI, so
# uv rather than npm — and basedpyright rather than Microsoft's pyright, which is
# the same server with the closed-source parts removed.
uv_tool_install ty ty "ty (Astral Python type server — croft LSP, priority 0)" \
    "ty installed (Python type checking in croft)"
uv_tool_install basedpyright basedpyright-langserver \
    "basedpyright (open-source pyright fork — croft LSP fallback)" \
    "basedpyright installed (Python completion + go-to-definition)"
if [[ "$DRY_RUN" != "true" ]]; then
    # rust-analyzer (Rust LSP) via rustup component; gopls (Go LSP) via go install.
    if installed rustup; then
        rustup component add rust-analyzer >> "$LOG_FILE" 2>&1 || warn "Could not add rust-analyzer component (Rust LSP for croft)"
    fi
    if installed go; then
        info "Installing gopls (Go LSP for croft) — compiles, may take a moment..."
        go install golang.org/x/tools/gopls@latest >> "$LOG_FILE" 2>&1 || warn "Could not install gopls (Go LSP for croft)"
    fi
fi

# AI tools
# Claude Code (installed via npm, not brew)
if installed npm; then
    npm_global_install "@anthropic-ai/claude-code" "Claude Code (AI-assisted coding in terminal)"
    # GitHub Copilot CLI (#356). A STANDALONE npm package now — `gh extension install
    # github/gh-copilot` is the retired path, and the uninstall notes still pointed at it.
    # Requires Node 22+; mise pins 24.18.1. Installing it here rather than via Homebrew keeps
    # it in the one npm tree (#343) and gets it a mise shim, so #353 links it into
    # ~/.local/bin and `copilot` resolves from git hooks and GUI editors, not just zsh.
    npm_global_install "@github/copilot" "GitHub Copilot CLI (\`copilot\`)"
else
    progress  # keep progress bar accurate when npm unavailable
fi
# Additional LLM CLIs that pair with Claude Code.
# Install llm as an isolated uv tool WITH the Anthropic plugin bundled. Homebrew's
# llm is externally-managed, so `llm install llm-anthropic` can't upgrade llm to the
# version the plugin needs and fails — `llm` then has no Anthropic backend at all.
# The uv venv also makes `llm models default` stick. (uv bin ~/.local/bin is on PATH.)
uv_tool_install llm llm "llm (Simon Willison's CLI — one-shot prompts, plugins, embeddings) + Anthropic plugin" "llm installed via uv (Anthropic plugin bundled)" --with llm-anthropic

# Point `llm` at Claude — its built-in default is OpenAI gpt-4o-mini,
# so without this the bind routes to the wrong provider. Non-secret and scriptable;
# only the API key stays manual (llm keys set anthropic).
if [[ "$DRY_RUN" != "true" ]] && installed llm; then
    llm models default anthropic/claude-sonnet-4-5 >> "$LOG_FILE" 2>&1 \
        && success "llm default model set to Claude (anthropic/claude-sonnet-4-5)" \
        || warn "Could not set llm default model (run: llm models default anthropic/claude-sonnet-4-5)"
fi

# Window management, status bar & clipboard (replaces Raycast + Spotlight)
# SketchyBar — status bar / menu-bar replacement (Dracula), + app-icon font + bluetooth helper.
trust_tap FelixKratz/formulae
brew_install "sketchybar" "SketchyBar (customizable macOS status bar)"
brew_cask_install "font-sketchybar-app-font" "sketchybar-app-font (app glyphs for SketchyBar)"
brew_install "blueutil" "blueutil (Bluetooth control from CLI — SketchyBar widget)"
# clipse — TUI clipboard manager (replaces Raycast clipboard history). Not on Homebrew.
go_install github.com/savedra1/clipse@latest clipse "clipse (TUI clipboard manager)"

# Dotfile management
brew_install "chezmoi" "chezmoi (dotfile manager — backup/restore configs across machines)"

# HTTP debugging
# HTTP debugging (mitmproxy — free, open-source)
brew_cask_install "mitmproxy" "mitmproxy (HTTP/HTTPS debugging proxy — free Proxyman alternative)"

# Node/JS tooling (via npm)
if installed npm; then
    npm_global_install "typescript" "TypeScript"
    npm_global_install "tsx" "tsx (TS execute)"
    npm_global_install "turbo" "Turborepo"
else
    progress; progress; progress  # keep progress bar accurate when npm unavailable
fi

# fzf key bindings
if ! is_done "install:fzf-keybindings"; then
FZF_INSTALL_SCRIPT="$(brew --prefix 2>/dev/null)/opt/fzf/install"
if [[ ! -f "$HOME/.fzf.zsh" ]] && installed fzf && [[ -x "$FZF_INSTALL_SCRIPT" ]]; then
    info "Setting up fzf key bindings..."
    "$FZF_INSTALL_SCRIPT" --key-bindings --completion --no-update-rc --no-bash --no-fish
    success "fzf key bindings configured"
fi
mark_done "install:fzf-keybindings"
fi

fi  # dx

# =============================================================================
if should_run "ux"; then
banner "UX & Design"

# Lighthouse (via npm)
if installed npm; then
    npm_global_install "lighthouse" "Lighthouse CLI"
else
    progress  # keep progress bar accurate when npm unavailable
fi

fi  # ux

# =============================================================================
if should_run "docs"; then
banner "Documentation & Diagrams"

brew_install "d2" "d2 (code-to-diagram scripting language)"

if installed npm; then
    npm_global_install "@mermaid-js/mermaid-cli" "Mermaid CLI (render diagrams from CLI)"
else
    progress  # keep progress bar accurate when npm unavailable
fi

# draw.io (GUI) removed — diagrams via d2 + mermaid-cli (installed above).

fi  # docs

# =============================================================================
if should_run "mac-system"; then
banner "Mac Apps — System & Utilities"

# UniFi Identity Endpoint removed (dropped from setup).
brew_cask_install "lulu" "LuLu (outbound firewall)"
# Bundles the `mullvad` CLI at /usr/local/bin/mullvad (no separate install needed).
brew_cask_install "mullvad-vpn" "Mullvad VPN (privacy-focused; bundles the mullvad CLI)"

# Utilities
brew_cask_install "pearcleaner" "Pearcleaner (open-source deep app uninstaller)"

# macOS scripting helpers — used by this script (Dock pins, notifications)
brew_install "dockutil" "dockutil (manage Dock pins programmatically)"
brew_install "terminal-notifier" "terminal-notifier (send macOS notifications from shell scripts)"

# No Quick Look plugins. QLMarkdown and QLStephen were dropped in 7.11.0 — Finder
# preview is not part of this workflow (files get read in the terminal), qlstephen was
# deprecated upstream, and QuickLookJSON had already been disabled. The qlmanage reload
# that registered them went with them; both are retired via DEPRECATED_TOOLS so
# --cleanup removes them from machines that have them (#299).

fi  # mac-system

# =============================================================================
if should_run "mac-productivity"; then
banner "Mac Apps — Productivity"

brew_cask_install "claude" "Claude (AI assistant)"
# Notion (GUI) replaced by tiki — terminal Markdown workspace (tasks/docs/kanban/wiki, git-backed).
trust_tap boolean-maybe/tap
brew_install "tiki" "tiki (terminal Markdown workspace — tasks, docs, kanban, wiki; git-backed)"
# tiki's official Claude Code skill — teaches Claude to manage the user's notes/tasks
# via `tiki exec '<ruki>'` (CRUD with auto git-staging). The brew formula ships only
# the binary, so fetch the skill into ~/.claude/skills/ (refreshed each run to track
# upstream). See https://github.com/boolean-maybe/tiki/tree/main/ai/skills/tiki
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would install tiki's Claude Code skill -> ~/.claude/skills/tiki/SKILL.md"
else
    _tiki_skill_dir="$HOME/.claude/skills/tiki"
    mkdir -p "$_tiki_skill_dir"
    if curl -fsSL "https://raw.githubusercontent.com/boolean-maybe/tiki/main/ai/skills/tiki/SKILL.md" \
        -o "$_tiki_skill_dir/SKILL.md" 2>>"$LOG_FILE" && [[ -s "$_tiki_skill_dir/SKILL.md" ]]; then
        success "tiki Claude Code skill installed (~/.claude/skills/tiki/)"
    else
        warn "Could not fetch tiki Claude skill — install manually from github.com/boolean-maybe/tiki (ai/skills/tiki)"
    fi
    unset _tiki_skill_dir
fi
# Terminal email + calendar → herald: one app for email AND calendar (Gmail work +
# iCloud personal, IMAP/SMTP + CalDAV), with built-in AI triage/summaries and an MCP
# server for Claude. Replaced aerc + khal + vdirsyncer (three tools → one). Herald
# self-configures via its own onboarding (no hand-written config); see the checklist.
trust_tap herald-email/herald
brew_install "herald" "herald (terminal email + calendar — Gmail + iCloud, AI triage, MCP server)"
# Ollama — local LLM runtime that backs herald's built-in AI (triage, summaries, compose
# styler) and `croft pair --provider ollama`. Both default to a local Ollama server on
# 127.0.0.1:11434, so without it that "local, no-key" AI path is dead. The formula (not the
# GUI cask) gives the `ollama` CLI + server; it stores models under ~/.ollama and needs no
# config file of its own. We run it as a login service so herald's default endpoint is always
# live, then seed the two models herald needs: gemma3:4b for text tasks (triage, summaries,
# compose styler) + croft pair, and nomic-embed-text-v2-moe as the embedding model for
# herald's semantic search. Every step is idempotent and honors --dry-run.
brew_install "ollama" "ollama (local LLM runtime — backs herald AI + croft pair --provider ollama)"
# Default model set, pulled on every run (skipped if already present). Keep the chat model
# first — docs/onboarding refer to it as the default general model.
OLLAMA_DEFAULT_MODELS=(
    "gemma3:4b"                 # chat: herald triage/summaries/compose + croft pair (~3.3 GB)
    "nomic-embed-text-v2-moe"   # embeddings: herald semantic search (~0.96 GB)
)
# A model is "present" if its name matches an `ollama list` row exactly — either as given
# (an explicit tag like gemma3:4b) or with the implicit :latest tag Ollama adds to untagged
# pulls (nomic-embed-text-v2-moe -> nomic-embed-text-v2-moe:latest).
ollama_model_present() {
    local model="$1" installed="$2"
    printf '%s\n' "$installed" | grep -Fxq "$model" && return 0
    printf '%s\n' "$installed" | grep -Fxq "${model}:latest"
}
if installed ollama; then
    if [[ "$DRY_RUN" == "true" ]]; then
        if brew services list 2>/dev/null | awk '$1=="ollama"{print $2}' | grep -qx started; then
            warn "[DRY RUN] ollama service — already running"
        else
            info "[DRY RUN] Would run ollama as a login service (brew services start ollama)"
        fi
        _installed_models="$(ollama list 2>/dev/null | awk 'NR>1{print $1}')"
        for _model in "${OLLAMA_DEFAULT_MODELS[@]}"; do
            if ollama_model_present "$_model" "$_installed_models"; then
                warn "[DRY RUN] ollama model $_model — already pulled"
            else
                info "[DRY RUN] Would pull ollama model $_model (one-time download)"
            fi
        done
    else
        if brew services list 2>/dev/null | awk '$1=="ollama"{print $2}' | grep -qx started; then
            warn "ollama service already running"
        else
            info "Starting ollama as a login service..."
            if brew services start ollama >> "$LOG_FILE" 2>&1; then
                success "ollama service started (127.0.0.1:11434)"
            else
                warn "Could not start ollama service — start it later with 'brew services start ollama'"
            fi
        fi
        # Wait for the server to accept connections before pulling a model.
        for _ in {1..15}; do
            curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
        _installed_models="$(ollama list 2>/dev/null | awk 'NR>1{print $1}')"
        for _model in "${OLLAMA_DEFAULT_MODELS[@]}"; do
            if ollama_model_present "$_model" "$_installed_models"; then
                warn "ollama model $_model already pulled"
            else
                info "Pulling ollama model $_model (one-time download)..."
                if ollama pull "$_model" >> "$LOG_FILE" 2>&1; then
                    success "ollama model $_model pulled"
                else
                    warn "Could not pull $_model — pull it later with 'ollama pull $_model'"
                fi
            fi
        done
    fi
fi
# reminders-cli — Apple Reminders (EventKit) from the terminal, so time/location alerts
# that should reach iPhone/Watch via iCloud have a home. Complements rather than overlaps
# the neighbours: tiki keeps notes/tasks in git, herald owns mail + calendar events.
# First invocation triggers a macOS TCC consent prompt for Reminders access — a GUI
# dialog this script cannot pre-grant, so the checklist covers it as a first-run step.
trust_tap keith/formulae
brew_install "reminders-cli" "reminders-cli (Apple Reminders from the terminal — 'reminders')"
# google-workspace-cli (gws) — one CLI for Drive/Gmail/Docs/Sheets/Calendar/Chat with
# structured JSON output, built for humans + AI agents (ships 95 Claude Code skills).
# All company work is on Google Workspace, so this is Claude's read/query surface there.
# NOTE: the Homebrew core formula literally named `gws` is a DIFFERENT tool
# (git-workspace — "manage workspaces of git repositories"). The Google Workspace
# CLI is the `googleworkspace-cli` formula; both ship a `gws` binary and therefore
# conflict, so remove the wrong one if an earlier run (which installed plain `gws`)
# left it behind, then install the right formula.
if [[ "$DRY_RUN" != "true" ]] && brew list --formula gws >/dev/null 2>&1; then
    info "Removing conflicting 'gws' formula (git-workspace) so googleworkspace-cli can install..."
    brew uninstall gws >> "$LOG_FILE" 2>&1 || warn "Could not remove git-workspace 'gws' (continuing)"
fi
brew_install "googleworkspace-cli" "google-workspace-cli (Drive/Gmail/Docs/Sheets/Calendar — JSON output, AI-agent-friendly)"
# gcloud CLI — a hard prerequisite for `gws auth setup`, which shells out to gcloud to
# bootstrap the OAuth project/credentials. Without it that first auth step dies with
# "gcloud CLI not found" and gws is unusable. The Homebrew cask was renamed from
# google-cloud-sdk to `gcloud-cli`, so install by the current name.
brew_cask_install "gcloud-cli" "Google Cloud CLI (gcloud — required by 'gws auth setup')"
# gws Claude skills — SCOPED to Drive / Docs / Slides / Sheets / Forms ONLY. Upstream
# ships ~95 skills spanning Gmail, Calendar, Chat, Meet, Tasks, Contacts, admin, etc.;
# we deliberately install just the file/document surface so Claude gets the recipes for
# those services and nothing that would drive your inbox, calendar, or chats. Refreshed
# each run to track upstream. IMPORTANT: skills are convenience recipes — they do NOT
# gate access. The real boundary is the OAuth scopes granted at `gws auth setup/login`
# (called out in the post-setup checklist). recipe-create-feedback-form is intentionally
# omitted: it depends on gws-gmail for its email-the-link step (outside the fence).
GWS_SKILLS=(
    # core service skills (gws-shared is the required base the others build on)
    gws-shared
    gws-drive gws-drive-upload
    gws-docs gws-docs-write
    gws-sheets gws-sheets-read gws-sheets-append
    gws-slides
    gws-forms
    # recipes — Drive
    recipe-bulk-download-folder recipe-find-large-files recipe-organize-drive-folder
    recipe-create-shared-drive recipe-share-folder-with-team
    # recipes — Docs
    recipe-create-doc-from-template
    # recipes — Slides
    recipe-create-presentation
    # recipes — Sheets
    recipe-backup-sheet-as-csv recipe-compare-sheet-tabs recipe-copy-sheet-for-new-month
    recipe-create-expense-tracker recipe-generate-report-from-sheet recipe-log-deal-update
    # recipes — Forms
    recipe-collect-form-responses
)
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would install ${#GWS_SKILLS[@]} scoped Google Workspace Claude skills (Drive/Docs/Slides/Sheets/Forms) -> ~/.claude/skills/"
elif ! installed git; then
    warn "Skipping Google Workspace Claude skills — git not available"
else
    info "Installing ${#GWS_SKILLS[@]} scoped Google Workspace Claude skills (Drive/Docs/Slides/Sheets/Forms)..."
    _gws_tmp="$(mktemp -d)"
    if git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/googleworkspace/cli "$_gws_tmp" >> "$LOG_FILE" 2>&1 \
        && git -C "$_gws_tmp" sparse-checkout set skills >> "$LOG_FILE" 2>&1; then
        mkdir -p "$HOME/.claude/skills"
        _gws_ok=0; _gws_miss=0
        for _skill in "${GWS_SKILLS[@]}"; do
            if [[ -d "$_gws_tmp/skills/$_skill" ]]; then
                rm -rf "$HOME/.claude/skills/$_skill"
                cp -R "$_gws_tmp/skills/$_skill" "$HOME/.claude/skills/" && _gws_ok=$((_gws_ok + 1))
            else
                warn "  gws skill not found upstream (skipped): $_skill"
                _gws_miss=$((_gws_miss + 1))
            fi
        done
        success "Google Workspace skills installed: $_gws_ok in ~/.claude/skills/ ($_gws_miss missing upstream)"
    else
        warn "Could not fetch Google Workspace skills — clone manually from github.com/googleworkspace/cli (skills/)"
    fi
    rm -rf "$_gws_tmp"
    unset _gws_tmp _skill _gws_ok _gws_miss
fi
brew_cask_install "shottr" "Shottr (fast native screenshots — scrolling capture, OCR, annotations)"

# PDF & documents
brew_cask_install "skim" "Skim (lightweight PDF reader with annotations — faster than Preview)"

# LibreOffice — headless office suite so Claude can validate & convert presentations,
# spreadsheets, and documents (soffice --headless --convert-to ...). Authoring still
# happens in Google Workspace; this is for local file validation/conversion only.
brew_cask_install "libreoffice" "LibreOffice (headless doc/sheet/slide validation + conversion)"
# The cask ships only the .app, so put `soffice` on PATH (~/.local/bin is on PATH)
# — that's what Claude invokes for headless validation.
if [[ "$DRY_RUN" != "true" ]]; then
    _soffice="/Applications/LibreOffice.app/Contents/MacOS/soffice"
    if [[ -x "$_soffice" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$_soffice" "$HOME/.local/bin/soffice"
        success "soffice linked to ~/.local/bin (headless: soffice --headless --convert-to pdf file.pptx)"
    fi
    unset _soffice
fi

# Office-file structural validation for Claude: an isolated uv venv with the
# python trio (python-docx / openpyxl / python-pptx), exposed as `office-py` on
# PATH. Lets Claude assert on document/sheet/slide CONTENT (soffice renders;
# office-py inspects), e.g. office-py -c 'from pptx import Presentation; Presentation("deck.pptx")'.
if ! installed uv; then
    warn "Skipping office-validation venv — uv not installed"
else
    OFFICE_VENV="$HOME/.local/share/dev-setup/office-venv"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create office-validation venv (python-docx, openpyxl, python-pptx) -> office-py"
    elif [[ -x "$OFFICE_VENV/bin/python" ]] && "$OFFICE_VENV/bin/python" -c 'import docx, openpyxl, pptx' 2>/dev/null; then
        warn "office-py venv already present"
    else
        info "Creating office-validation venv (python-docx, openpyxl, python-pptx)..."
        if uv venv --python 3.13 "$OFFICE_VENV" >> "$LOG_FILE" 2>&1 \
            && uv pip install --python "$OFFICE_VENV/bin/python" python-docx openpyxl python-pptx >> "$LOG_FILE" 2>&1; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$OFFICE_VENV/bin/python" "$HOME/.local/bin/office-py"
            success "office-py ready (structural checks for .docx/.xlsx/.pptx)"
        else
            warn "Could not create office-validation venv"
        fi
    fi
fi
progress

# File transfer — Cyberduck (GUI) removed; rclone (installed below) covers SFTP/S3/cloud.

fi  # mac-productivity

# =============================================================================
if should_run "mac-browsers"; then
banner "Mac Apps — Browsers"

brew_cask_install "google-chrome" "Google Chrome"

npm_global_install "carbonyl" "Carbonyl (Chromium-based browser for the terminal)"
brew_install "w3m" "w3m (text-based terminal browser and pager)"
brew_install "monolith" "monolith (save complete web pages as a single HTML file)"

fi  # mac-browsers

# =============================================================================
if should_run "mac-media"; then
banner "Mac Apps — Media"

brew_install "mpv" "mpv (terminal video player)"
brew_install "oxipng" "oxipng (lossless PNG compression)"
brew_install "jpegoptim" "jpegoptim (lossless JPEG compression)"
brew_install "p7zip" "7zip (archive tool — zip, 7z, rar, tar)"
# cliamp — Winamp-inspired terminal music player (MIT): many formats, streaming
# (YouTube/SoundCloud/Spotify/radio), parametric EQ, 20+ visualizations. Replaced kew.
trust_tap bjarneo/cliamp
brew_install "cliamp" "cliamp (terminal music player — Winamp-style, streaming, EQ, 20+ visualizers)"

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
if [[ "$DRY_RUN" != "true" ]] && installed borgmatic; then
    BORGMATIC_CONFIG="$HOME/.config/borgmatic/config.yaml"
    if [[ ! -f "$BORGMATIC_CONFIG" ]]; then
        mkdir -p "$(dirname "$BORGMATIC_CONFIG")"
        cat > "$BORGMATIC_CONFIG" <<'BORGMATIC_CONF'
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
        success "borgmatic starter config scaffolded (~/.config/borgmatic/config.yaml — fill in repositories)"
    else
        warn "borgmatic config already exists — leaving it untouched"
    fi
fi

fi  # mac-cloud

# =============================================================================
if should_run "mac-focus"; then
banner "Mac Apps — Focus & Learning"

brew_install "newsboat" "newsboat (terminal RSS/Atom reader)"

fi  # mac-focus

# mac-disk: Disk analysis handled by dust and duf (installed in "replacements" section)
# No additional tools needed — section removed to avoid empty banner

# =============================================================================
if should_run "mac-bloat"; then
banner "Remove Pre-installed Apple Apps"

# Only removes apps in /Applications (not SIP-protected).
# System apps in /System/Applications require SIP disabled and are skipped.

BLOAT_APPS=(
    "/Applications/GarageBand.app|GarageBand"
)

BLOAT_REMOVED=0
BLOAT_SKIPPED=0

for entry in "${BLOAT_APPS[@]}"; do
    app_path="${entry%%|*}"
    app_name="${entry##*|}"

    if [[ ! -d "$app_path" ]]; then
        warn "$app_name — not found (already removed or not installed)"
        ((BLOAT_SKIPPED++))
        continue
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove: $app_name ($app_path)"
        continue
    fi

    info "Removing $app_name..."
    if sudo rm -rf "$app_path" 2>> "$LOG_FILE"; then
        success "$app_name removed"
        ((BLOAT_REMOVED++))
    else
        warn "$app_name could not be removed"
        ((BLOAT_SKIPPED++))
    fi
done

echo ""
if [[ "$DRY_RUN" != "true" ]]; then
    info "Bloat removal: $BLOAT_REMOVED removed, $BLOAT_SKIPPED skipped"
fi

fi  # mac-bloat

# =============================================================================
if should_run "dracula"; then
banner "Dracula Theme"

# micro - Dracula (dracula-tc) is bundled with micro and set via ~/.config/micro/settings.json
# (see the micro config block below). No theme file to install.

# bat (Dracula is built-in, just needs to be set)
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    if [[ -n "$BAT_CONFIG_DIR" ]]; then
        mkdir -p "$BAT_CONFIG_DIR"
        if ! is_done "config:bat-dracula"; then
        if [[ -f "$BAT_CONFIG_DIR/config" ]] && grep -q 'Dracula' "$BAT_CONFIG_DIR/config" 2>/dev/null; then
            warn "bat Dracula theme already configured"
        else
            echo '--theme="Dracula"' >> "$BAT_CONFIG_DIR/config"
            success "bat Dracula theme configured"
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
    git config --global delta.syntax-theme Dracula
    success "delta Dracula theme configured"
fi
mark_done "config:delta-dracula"
fi

# Starship prompt (rich config with Dracula palette)
STARSHIP_CONFIG="$HOME/.config/starship.toml"
    info "Creating rich Starship prompt config..."
    write_managed "$STARSHIP_CONFIG" "#" <<'STARSHIP_CONF'
# =============================================================================
# Starship Prompt — Dracula themed, info-rich
# =============================================================================

# Use Dracula colors everywhere
palette = "dracula"

# Prompt format: directory, git, languages, duration, newline, character
format = """
[┌──](comment)\
$os\
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$git_state\
$nodejs\
$python\
$rust\
$go\
$docker_context\
$aws\
$terraform\
$cmd_duration\
$jobs\
$fill\
$battery\
$time
[└─](comment)$character"""

# Right prompt disabled (everything is on the left two-line prompt)
right_format = ""

# Wait 10ms for starship to check files (snappy)
scan_timeout = 10
command_timeout = 500

# Don't add blank line between prompts
add_newline = false

# -- Prompt character ---------------------------------------------------------
[character]
success_symbol = "[❯](bold purple)"
error_symbol = "[❯](bold red)"
vimcmd_symbol = "[❮](bold green)"

# -- Fill (pushes battery/time to the right) ----------------------------------
[fill]
symbol = " "

# -- OS icon ------------------------------------------------------------------
[os]
disabled = false
style = "fg:comment"
format = "[$symbol ]($style)"

[os.symbols]
Macos = ""
Linux = ""
Windows = ""
Arch = ""
Ubuntu = ""
Fedora = ""
Debian = ""

# -- Username (only show if SSH or root) --------------------------------------
[username]
show_always = false
style_user = "fg:purple"
style_root = "bold fg:red"
format = "[$user]($style) "

# -- Hostname (only show if SSH) ----------------------------------------------
[hostname]
ssh_only = true
style = "fg:pink"
format = "[@$hostname]($style) "

# -- Directory ----------------------------------------------------------------
[directory]
style = "bold cyan"
format = "[$path]($style)[$read_only]($read_only_style) "
truncation_length = 4
truncation_symbol = "…/"
read_only = " 󰌾"
read_only_style = "fg:red"

[directory.substitutions]
"Inbox" = "📥 "
"Documents" = "󰈙 "
"Downloads" = " "
"Code" = " "
"Creative" = "🎨"
"Media" = "🎵"
"Archive" = "📦 "

# -- Git branch ---------------------------------------------------------------
[git_branch]
symbol = " "
style = "fg:purple"
format = "[$symbol$branch(:$remote_branch)]($style) "
truncation_length = 24

# -- Git status ---------------------------------------------------------------
[git_status]
style = "fg:red"
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
style = "bold fg:orange"
format = "[$state( $progress_current/$progress_total)]($style) "
rebase = "REBASING"
merge = "MERGING"
revert = "REVERTING"
cherry_pick = "CHERRY-PICKING"
bisect = "BISECTING"

# -- Node.js ------------------------------------------------------------------
[nodejs]
symbol = " "
style = "fg:green"
format = "[$symbol$version]($style) "
detect_files = ["package.json", ".nvmrc"]
detect_extensions = []

# -- Python -------------------------------------------------------------------
[python]
symbol = " "
style = "fg:yellow"
format = '[$symbol$version( \($virtualenv\))]($style) '
detect_extensions = ["py"]

# -- Rust ---------------------------------------------------------------------
[rust]
symbol = "🦀 "
style = "fg:orange"
format = "[$symbol$version]($style) "

# -- Go ----------------------------------------------------------------------
[golang]
symbol = " "
style = "fg:cyan"
format = "[$symbol$version]($style) "

# -- Docker context -----------------------------------------------------------
[docker_context]
symbol = " "
style = "fg:cyan"
format = "[$symbol$context]($style) "
only_with_files = true

# -- AWS profile --------------------------------------------------------------
[aws]
symbol = "☁️ "
style = "bold fg:orange"
format = "[$symbol$profile(\\($region\\))]($style) "

# -- Terraform ----------------------------------------------------------------
[terraform]
symbol = "💠 "
style = "fg:purple"
format = "[$symbol$workspace]($style) "

# -- Command duration (show if > 3 seconds) -----------------------------------
[cmd_duration]
min_time = 3_000
style = "fg:yellow"
format = "[⏱ $duration]($style) "
show_milliseconds = false

# -- Background jobs ----------------------------------------------------------
[jobs]
symbol = "✦"
style = "bold fg:cyan"
number_threshold = 1
format = "[$symbol$number]($style) "

# -- Battery (show if < 30%) --------------------------------------------------
[battery]
format = "[$symbol$percentage]($style) "

[[battery.display]]
threshold = 15
style = "bold fg:red"

[[battery.display]]
threshold = 30
style = "fg:orange"

# -- Time (always show) -------------------------------------------------------
[time]
disabled = false
style = "fg:comment"
format = "[$time]($style)"
time_format = "%H:%M"

# -- Dracula color palette ----------------------------------------------------
[palettes.dracula]
background = "#282a36"
current_line = "#44475a"
foreground = "#f8f8f2"
comment = "#6272a4"
cyan = "#8be9fd"
green = "#50fa7b"
orange = "#ffb86c"
pink = "#ff79c6"
purple = "#bd93f9"
red = "#ff5555"
yellow = "#f1fa8c"
STARSHIP_CONF
    success "Starship prompt configured (rich two-line prompt, Dracula theme)"

fi  # dracula

# =============================================================================
if should_run "configs"; then
banner "Tool Configurations"

# ---- git global config ----
info "Configuring git global settings..."

# Default branch
git config --global init.defaultBranch main 2>/dev/null

# Pull strategy (rebase to keep history clean)
git config --global pull.rebase true

# Auto-stash on rebase
git config --global rebase.autoStash true

# Better diff algorithm
git config --global diff.algorithm histogram

# Show diff in commit message editor
git config --global commit.verbose true

# Auto-correct typos (0.5s delay)
git config --global help.autocorrect 5

# Column output for branch listing
git config --global column.ui auto

# Sort branches by most recent commit
git config --global branch.sort -committerdate

# Remember merge conflict resolutions and auto-apply next time
git config --global rerere.enabled true

success "  git core settings configured (rebase, histogram diff, rerere)"

# Useful aliases
# Basic shortcuts
git config --global alias.st "status -sb"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.ci "commit"
git config --global alias.sw "switch"

# Undo & reset
git config --global alias.unstage "reset HEAD --"
git config --global alias.undo "reset --soft HEAD~1"
git config --global alias.discard "checkout -- ."
git config --global alias.amend "commit --amend --no-edit"

# Quick commits
git config --global alias.wip "!git add -A && git commit -m 'WIP'"
git config --global alias.save "!git add -A && git commit -m 'chore: savepoint'"

# Stash
git config --global alias.stash-all "stash push --include-untracked"
git config --global alias.stash-peek "stash show -p"

# Log & history
git config --global alias.last "log -1 HEAD --stat"
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.log-stats "log --oneline --stat"
git config --global alias.log-since "log --oneline --since='1 week ago'"
git config --global alias.contributors "shortlog -sne --no-merges"
git config --global alias.standup "!git log --oneline --since='yesterday' --author=\"\$(git config user.name)\""

# Branch management
git config --global alias.recent "branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)' -n 15"
# `gone` deletes local branches whose upstream is gone — which is exactly what a
# squash merge plus `--delete-branch` leaves behind. Two things it must NOT do,
# both of which the pre-#321 one-liners did:
#
#   * Select by ancestry. `git branch --merged main` is an ancestry test, and a
#     squash merge writes a NEW commit that the branch tip is not an ancestor of.
#     Every squash-merged branch is invisible to it, so `cleanup` selected
#     nothing, forever, on a workflow that squash-merges everything — then died
#     on `xargs` with `fatal: branch name required`, which reads as a usage error
#     rather than "nothing to do".
#   * Delete with `-d`. That applies the same ancestry test and refuses a
#     squash-merged branch, so `gone` — whose SELECTION was always correct —
#     failed at the last step instead of the first.
#
# So: select on upstream `[gone]`, delete with `-D`, and print each deleted
# branch with the SHA to restore it from. `-D` gives up git's safety net, and the
# echoed SHA is what replaces it: recovery is `git branch <name> <sha>`, with the
# reflog behind that. Silence is the bug here, not politeness — an alias that
# finds nothing says so.
#
# Single-quoted so the body reaches git verbatim; keep single quotes OUT of it.
# `for-each-ref` rather than `branch -vv | awk` so that no `$1` has to survive
# three levels of quoting.
git config --global alias.gone '!f() {
    git fetch --prune --quiet
    current=$(git branch --show-current)
    stale=$(git for-each-ref --format="%(refname:short) %(upstream:track)" refs/heads | grep "\[gone\]$" | cut -d" " -f1)
    if [ -z "$stale" ]; then
        echo "No local branches whose upstream is gone - nothing to delete."
        return 0
    fi
    echo "$stale" | while read -r b; do
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

# cleanup delegates: ancestry selection is the bug above, so there is only one
# correct implementation and this is a second name for it (#321).
git config --global alias.cleanup "!git gone"

# Diff
git config --global alias.dft "!git -c diff.external=difft diff"
git config --global alias.dfl "!git -c diff.external=difft log -p --ext-diff"
git config --global alias.diff-names "diff --name-only"
git config --global alias.diff-stat "diff --stat"

# Worktree shortcuts
git config --global alias.wt "worktree"
git config --global alias.wta "worktree add"
git config --global alias.wtl "worktree list"

success "  git aliases configured (30+ shortcuts for status, log, branch, diff, worktree)"

# ---- GPG + pinentry-mac ----
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
    info "Configuring GPG to use pinentry-mac..."
    chmod 700 "$HOME/.gnupg"
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
        gpgconf --kill gpg-agent 2>/dev/null || true
        success "GPG pinentry-mac configured (passphrases cached 8 hours)"
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
    success "aria2 configured (16 connections, auto-resume, BitTorrent)"

# ---- atuin ----
ATUIN_CONFIG_DIR="$HOME/.config/atuin"
ATUIN_CONFIG="$ATUIN_CONFIG_DIR/config.toml"
    info "Creating atuin configuration..."
    write_managed "$ATUIN_CONFIG" "#" <<'ATUIN_CONF'
## atuin configuration

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
    success "atuin configured (fuzzy search, local-only, history filter, enter=paste)"

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
    info "Creating lazygit Dracula config..."
    write_managed "$LAZYGIT_CONFIG" "#" <<'LAZYGIT_CONF'
gui:
  nerdFontsVersion: "3"
  showBottomLine: false
  showPanelJumps: true
  showRandomTip: false
  showCommandLog: false
  border: rounded
  theme:
    activeBorderColor:
      - "#bd93f9"  # purple
      - bold
    inactiveBorderColor:
      - "#6272a4"  # comment
    selectedLineBgColor:
      - "#44475a"  # current_line
    cherryPickedCommitFgColor:
      - "#50fa7b"  # green
    cherryPickedCommitBgColor:
      - "#44475a"  # current_line
    unstagedChangesColor:
      - "#ff5555"  # red
    defaultFgColor:
      - "#f8f8f2"  # foreground
    searchingActiveBorderColor:
      - "#ffb86c"  # orange
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
    success "lazygit configured (Dracula theme, delta pager, auto-fetch, micro editor)"
fi  # installed lazygit

# ---- k9s Dracula skin ----
# k9s follows XDG too, so the Library path this used to write was read by nobody and
# the Dracula skin never applied (#333). `k9s info` reports the config file it will
# use; strip its ANSI colouring, and match on the whole rest of the line because these
# paths contain a space ("Application Support") that a field-splitting read truncates.
K9S_CONFIG_DIR="$(XDG_CONFIG_HOME="$HOME/.config" k9s info 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's|^Config: *||p' | head -1)"
K9S_CONFIG_DIR="${K9S_CONFIG_DIR%/config.yaml}"
K9S_CONFIG_DIR="${K9S_CONFIG_DIR:-$HOME/.config/k9s}"
K9S_SKINS_DIR="$K9S_CONFIG_DIR/skins"
K9S_SKIN="$K9S_SKINS_DIR/dracula.yaml"
K9S_SUPERSEDED_DIR="$HOME/Library/Application Support/k9s"
    info "Creating k9s Dracula skin..."
    write_managed "$K9S_SKIN" "#" <<'K9S_DRACULA'
k9s:
  body:
    fgColor: "#f8f8f2"
    bgColor: "#282a36"
    logoColor: "#bd93f9"
  prompt:
    fgColor: "#f8f8f2"
    bgColor: "#282a36"
    suggestColor: "#bd93f9"
  info:
    fgColor: "#8be9fd"
    sectionColor: "#f8f8f2"
  dialog:
    fgColor: "#f8f8f2"
    bgColor: "#44475a"
    buttonFgColor: "#f8f8f2"
    buttonBgColor: "#bd93f9"
    buttonFocusFgColor: "#f8f8f2"
    buttonFocusBgColor: "#ff79c6"
    labelFgColor: "#ffb86c"
    fieldFgColor: "#f8f8f2"
  frame:
    border:
      fgColor: "#44475a"
      focusColor: "#bd93f9"
    menu:
      fgColor: "#f8f8f2"
      keyColor: "#bd93f9"
      numKeyColor: "#bd93f9"
    crumbs:
      fgColor: "#282a36"
      bgColor: "#bd93f9"
      activeColor: "#ff79c6"
    status:
      newColor: "#50fa7b"
      modifyColor: "#bd93f9"
      addColor: "#8be9fd"
      errorColor: "#ff5555"
      highlightColor: "#ffb86c"
      killColor: "#6272a4"
      completedColor: "#6272a4"
    title:
      fgColor: "#f8f8f2"
      bgColor: "#282a36"
      highlightColor: "#bd93f9"
      counterColor: "#8be9fd"
      filterColor: "#ff79c6"
  views:
    charts:
      bgColor: default
      defaultDialColors:
        - "#bd93f9"
        - "#ff5555"
      defaultChartColors:
        - "#bd93f9"
        - "#ff5555"
    table:
      fgColor: "#f8f8f2"
      bgColor: "#282a36"
      header:
        fgColor: "#6272a4"
        bgColor: "#282a36"
        sorterColor: "#8be9fd"
    xray:
      fgColor: "#f8f8f2"
      bgColor: "#282a36"
      cursorColor: "#44475a"
      graphicColor: "#bd93f9"
      showColor: "#50fa7b"
    yaml:
      keyColor: "#8be9fd"
      colonColor: "#bd93f9"
      valueColor: "#f8f8f2"
    logs:
      fgColor: "#f8f8f2"
      bgColor: "#282a36"
      indicator:
        fgColor: "#f8f8f2"
        bgColor: "#bd93f9"
        toggleOnColor: "#50fa7b"
        toggleOffColor: "#6272a4"
K9S_DRACULA

    # Set dracula as active skin in k9s config
    K9S_MAIN_CONFIG="$K9S_CONFIG_DIR/config.yaml"
    if [[ -f "$K9S_MAIN_CONFIG" ]]; then
        if ! grep -q "skin:" "$K9S_MAIN_CONFIG" 2>/dev/null; then
            echo "  skin: dracula" >> "$K9S_MAIN_CONFIG"
        fi
    else
        write_managed "$K9S_MAIN_CONFIG" "#" <<'K9S_CFG'
k9s:
  ui:
    skin: dracula
K9S_CFG
    fi
    remove_superseded_managed "$K9S_SUPERSEDED_DIR/skins/dracula.yaml" \
        "k9s reads $K9S_SKIN" "(#333)"
    remove_superseded_managed "$K9S_SUPERSEDED_DIR/config.yaml" \
        "k9s reads $K9S_CONFIG_DIR/config.yaml" "(#333)"
    success "k9s Dracula skin configured"

# ---- micro editor config ----
# micro is the $EDITOR: git/gh/lazygit commit messages, leaf's Ctrl+E, quick file edits.
# Non-modal by design, so the settings below lean on discoverability and on matching the
# code standards in the generated CLAUDE.md rather than on remapping keys.
#   keymenu    - persistent key-binding strip along the bottom (the whole point)
#   dracula-tc - built into micro; needs truecolor, which Ghostty advertises via COLORTERM
#   rmtrailingws/eofnewline - match what prettier and ruff would do on save anyway
# Indentation follows the house rules: 2 spaces, 4 for Python, real tabs for Go/Makefiles.
MICRO_CONFIG_DIR="$HOME/.config/micro"
info "Configuring micro (Dracula, on-screen key menu, house indent rules)..."
mkdir -p "$MICRO_CONFIG_DIR"
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
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write micro settings (Dracula, key menu, house indent rules)"
elif [[ ! -f "$MICRO_CONFIG_DIR/settings.json" ]]; then
    printf '%s\n' "$MICRO_DEFAULTS" > "$MICRO_CONFIG_DIR/settings.json"
    success "micro configured (Dracula, key menu, 2-space default / 4 for Python / tabs for Go)"
elif command -v jq &>/dev/null; then
    _micro_tmp=$(mktemp)
    if jq -s '.[0] * .[1]' <(printf '%s\n' "$MICRO_DEFAULTS") "$MICRO_CONFIG_DIR/settings.json" > "$_micro_tmp" 2>/dev/null; then
        mv "$_micro_tmp" "$MICRO_CONFIG_DIR/settings.json"
        success "micro settings merged (your in-editor changes kept; new defaults added)"
    else
        rm -f "$_micro_tmp"
        warn "Could not merge micro settings — check $MICRO_CONFIG_DIR/settings.json"
    fi
    unset _micro_tmp
else
    warn "micro settings exist but jq is missing — not merging new defaults"
fi
unset MICRO_DEFAULTS

# ---- Visual Studio Code ----
# Same shape as the micro block above, and for the same reasons: NOT write_managed,
# because JSON has no comment syntax for the managed markers and VS Code rewrites this
# file itself every time a setting is changed from the UI or the Settings editor. So
# merge with the ON-DISK FILE WINNING (`.[0] * .[1]` — defaults first, yours second):
# your hand edits and anything Settings Sync pulls down survive a re-run, while options
# added in later releases still land on an existing machine.
#
# One VS Code-specific trap: settings.json is JSONC, so a file with `//` comments or a
# trailing comma is valid to VS Code and INVALID to jq. That merge fails, and the right
# response is to warn and leave the file completely alone — never to overwrite, which
# would silently eat a config the user considers valid.
#
# Every default here is one the terminal side already enforces, so the GUI editor cannot
# disagree with the CLI: ruff for Python (not black), prettier for web, shfmt for shell,
# tabs for Go, LF endings, trailing whitespace stripped. The EditorConfig extension is
# installed too and outranks all of it per-repo, which is the intended precedence.
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_SETTINGS="$VSCODE_USER_DIR/settings.json"
# "Dracula Theme" is the exact `contributes.themes[].label` from the extension manifest —
# not "Dracula", which silently does nothing (an unknown theme name leaves the default).
VSCODE_DEFAULTS=$(cat <<'VSCODE_CONF'
{
    "workbench.colorTheme": "Dracula Theme",
    "workbench.startupEditor": "none",
    "editor.fontFamily": "'JetBrains Mono', Menlo, monospace",
    "editor.fontLigatures": true,
    "editor.fontSize": 13,
    "editor.formatOnSave": true,
    "editor.tabSize": 2,
    "editor.insertSpaces": true,
    "editor.rulers": [100],
    "editor.renderWhitespace": "boundary",
    "editor.bracketPairColorization.enabled": true,
    "editor.linkedEditing": true,
    "editor.inlineSuggest.enabled": true,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.trimFinalNewlines": true,
    "files.eol": "\n",
    "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font",
    "terminal.integrated.defaultProfile.osx": "zsh",
    "git.autofetch": true,
    "git.confirmSync": false,
    "explorer.confirmDragAndDrop": false,
    "telemetry.telemetryLevel": "off",
    "python.languageServer": "None",
    "basedpyright.importStrategy": "fromEnvironment",
    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.tabSize": 4,
        "editor.codeActionsOnSave": {
            "source.fixAll": "explicit",
            "source.organizeImports": "explicit"
        }
    },
    "[javascript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[javascriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[typescript]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[typescriptreact]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[json]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[jsonc]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[css]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[html]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[markdown]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[yaml]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
    "[go]": { "editor.defaultFormatter": "golang.go", "editor.insertSpaces": false, "editor.tabSize": 4 },
    "[rust]": { "editor.defaultFormatter": "rust-lang.rust-analyzer" },
    "[shellscript]": { "editor.defaultFormatter": "foxundermoon.shell-format" },
    "[terraform]": { "editor.defaultFormatter": "hashicorp.terraform" },
    "[toml]": { "editor.defaultFormatter": "tamasfe.even-better-toml" }
}
VSCODE_CONF
)
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write VS Code settings (Dracula, format-on-save, ruff/prettier/shfmt)"
elif [[ ! -f "$VSCODE_SETTINGS" ]]; then
    mkdir -p "$VSCODE_USER_DIR"
    printf '%s\n' "$VSCODE_DEFAULTS" > "$VSCODE_SETTINGS"
    success "VS Code configured (Dracula, format-on-save, ruff for Python, prettier for web)"
elif command -v jq &>/dev/null; then
    _vscode_tmp=$(mktemp)
    if jq -s '.[0] * .[1]' <(printf '%s\n' "$VSCODE_DEFAULTS") "$VSCODE_SETTINGS" > "$_vscode_tmp" 2>/dev/null; then
        mv "$_vscode_tmp" "$VSCODE_SETTINGS"
        success "VS Code settings merged (your changes kept; new defaults added)"
    else
        rm -f "$_vscode_tmp"
        # Almost always JSONC: comments or a trailing comma, which VS Code accepts and jq
        # does not. Leave the file untouched and say so.
        warn "Could not merge VS Code settings (comments or trailing commas?) — left as-is: $VSCODE_SETTINGS"
    fi
    unset _vscode_tmp
else
    warn "VS Code settings exist but jq is missing — not merging new defaults"
fi
unset VSCODE_DEFAULTS

# ---- MCP servers -> Claude Code (migrated from Kiro) ----
# Claude Code stores user-scoped MCP servers in ~/.claude.json. We use the
# `claude mcp add` CLI (never hand-edit that live state file) to register the
# everyday servers at user scope. `claude mcp add` is NOT idempotent, so we
# remove-then-add. Heavier/opt-in servers are intentionally NOT added globally --
# add them per project with `claude mcp add --scope project <name> ...`.
# The Notion server is dropped (Notion is no longer part of this setup).
if ! is_done "config:claude-mcp"; then
if installed claude; then
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would configure Claude Code MCP servers (user scope, minus Notion)"
    else
        info "Configuring Claude Code MCP servers (user scope)..."
        # add_mcp <name-for-removal> <full args to `claude mcp add` incl. name> -- <command...>
        add_mcp() {
            local name="$1"; shift
            claude mcp remove --scope user "$name" >> "$LOG_FILE" 2>&1 || true
            if claude mcp add --scope user "$@" >> "$LOG_FILE" 2>&1; then
                success "MCP: $name"
            else
                warn "MCP: failed to add $name (see $LOG_FILE)"
            fi
        }

        add_mcp filesystem --transport stdio filesystem -- npx -y @modelcontextprotocol/server-filesystem "$HOME/Code"
        # `claude mcp add`'s -e/--env is variadic and greedily eats the following
        # positional, so the server NAME must come first and each -e must sit right
        # before `--` (env servers only — see #-note). Literal ${VAR} is expanded by
        # Claude Code at server-launch time from the user's environment.
        add_mcp github github --transport stdio -e "GITHUB_PERSONAL_ACCESS_TOKEN=\${GITHUB_TOKEN}" -- npx -y @modelcontextprotocol/server-github
        add_mcp git --transport stdio git -- uvx mcp-server-git
        add_mcp fetch --transport stdio fetch -- uvx mcp-server-fetch
        add_mcp context7 --transport stdio context7 -- npx -y @upstash/context7-mcp
        add_mcp aws-docs --transport stdio aws-docs -- uvx awslabs.aws-documentation-mcp-server
        add_mcp aws-pricing --transport stdio aws-pricing -- uvx awslabs.aws-pricing-mcp-server@latest
        add_mcp aws-iac --transport stdio aws-iac -- uvx awslabs.aws-iac-mcp-server@latest
        # aws-knowledge is REMOTE — a fully managed HTTP endpoint, not a local stdio server,
        # and the only one here that is (#364). No auth, no AWS account, rate-limited. This
        # was registered as `uvx awslabs.aws-knowledge-mcp-server@latest` and had therefore
        # never once connected: there is no legitimate PyPI distribution, and the name that
        # was on PyPI (single 0.1.0, 2025-10-15) is YANKED with the reason "Not ours" — it
        # was not published by AWS Labs despite claiming their repo as its homepage. uv
        # refuses a yanked-only resolution rather than falling back to it, so the package was
        # never fetched or executed here; ~/.cache/uv has no trace of it. Failing closed is
        # the only reason a wrong `uvx` line pointed at a squatted name stayed harmless.
        add_mcp aws-knowledge --transport http aws-knowledge https://knowledge-mcp.global.api.aws
        add_mcp cloudwatch cloudwatch --transport stdio -e "AWS_REGION=\${AWS_REGION}" -e "AWS_PROFILE=\${AWS_PROFILE}" -- uvx awslabs.cloudwatch-mcp-server@latest
        add_mcp iam iam --transport stdio -e "AWS_REGION=\${AWS_REGION}" -e "AWS_PROFILE=\${AWS_PROFILE}" -- uvx awslabs.iam-mcp-server@latest
        # herald (email + calendar) — read-only after initial sync; mutations need `herald serve`.
        # Inert until herald accounts are configured (see the POST_SETUP checklist).
        add_mcp herald --transport stdio herald -- herald mcp -config "$HOME/.herald/conf.yaml"
        # GitKraken (31 tools: git_*, pull_request_*, issues_*, gitlens_launchpad). Served by
        # the standalone `gk` from the gitkraken-cli cask. Registered here because it used to
        # register ITSELF: the GitLens extension wrote this server into ~/.claude.json pointing
        # at a gk binary inside its own VS Code globalStorage, so removing the extension would
        # have taken the server with it (#362). Name kept capitalised — it is the name GitLens
        # used and the one already in every transcript. `--no-telemetry` suppresses gk's OTel
        # spans and Sentry reporting, matching "telemetry.telemetryLevel": "off" above.
        add_mcp GitKraken --transport stdio GitKraken -- gk mcp --host=claude-cli --no-telemetry
        unset -f add_mcp

        success "Claude Code MCP servers configured (user scope)"
        info "  Added: filesystem, github, git, fetch, context7, aws-docs, aws-pricing,"
        info "         aws-iac, aws-knowledge, cloudwatch, iam, herald, GitKraken"
        info "  Opt-in per project (claude mcp add --scope project <name> ...):"
        info "         playwright, postgres, aws-ccapi, aws-serverless, aws-lambda-tool,"
        info "         aws-eks, aws-ecs, aws-dynamodb"
        info "  github: export GITHUB_TOKEN=...   AWS servers use the standard AWS"
        info "          credential chain (AWS_REGION / AWS_PROFILE / 'assume <profile>')."
    fi
else
    warn "Claude Code CLI not found -- skipping MCP server setup"
    info "  After installing Claude Code + 'claude auth login', re-run:  $0 --only dracula"
fi
mark_done "config:claude-mcp"
fi

# ---- Fonts (required for icons in eza, starship, lazygit, etc.) ----
info "Installing development fonts..."

brew_cask_install "font-jetbrains-mono" "JetBrains Mono (primary dev font)"
brew_cask_install "font-jetbrains-mono-nerd-font" "JetBrains Mono Nerd Font (with icons)"
brew_cask_install "font-meslo-lg-nerd-font" "MesloLGS Nerd Font (terminal icons)"
brew_cask_install "font-fira-code" "Fira Code (ligature font)"
brew_cask_install "font-fira-code-nerd-font" "Fira Code Nerd Font (with icons)"
brew_cask_install "font-inter" "Inter (best UI font for web/design)"
brew_cask_install "font-hack-nerd-font" "Hack Nerd Font (classic terminal font)"

success "Development fonts installed"

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
    success "shellcheck configured"

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
    success "leaf configured (Ctrl+E opens micro at the current line)"
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
# the correct trade here. Keyed on the FILE, not the directory: add-authtoken creates
# both, so on a machine that ran it first the directory is already there.
if [[ -f "$NGROK_CONFIG" ]]; then
    info "ngrok config already exists — leaving it alone (it may hold your authtoken)"
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create the ngrok seed config at $NGROK_CONFIG"
else
    info "Creating ngrok config..."
    mkdir -p "$NGROK_CONFIG_DIR"
    cp "$_ngrok_seed" "$NGROK_CONFIG"
    # Lock down: ngrok.yml will hold your authtoken.
    chmod 700 "$NGROK_CONFIG_DIR" 2>/dev/null || true
    chmod 600 "$NGROK_CONFIG" 2>/dev/null || true
    success "ngrok config created (add authtoken: ngrok config add-authtoken <TOKEN>)"
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
    success "yt-dlp configured (best quality, aria2c downloader, metadata)"

# difftastic aliases already configured in git global settings above

# ---- caddy config ----
CADDY_CONFIG_DIR="$HOME/.config/caddy"
if ! is_done "config:caddy"; then
# Deliberately create-once (#277): a commented-out starting point ("uncomment and
# adjust as needed") that the user is expected to edit into their own site config.
# Refreshing it on every run would discard their edits.
# Unlike ngrok, this path is correct: the template is used with an explicit
# `caddy run --config ~/.config/caddy/Caddyfile`, which is what its own first
# line documents. Only the missing DRY_RUN guard was wrong here (#332).
if [[ -d "$CADDY_CONFIG_DIR" ]]; then
    warn "Caddy config directory already exists"
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create the Caddy config template at $CADDY_CONFIG_DIR/Caddyfile"
else
    info "Creating Caddy config template..."
    mkdir -p "$CADDY_CONFIG_DIR"
    cat > "$CADDY_CONFIG_DIR/Caddyfile" <<'CADDY_CONF'
# Caddy development server template
# Usage: caddy run --config ~/.config/caddy/Caddyfile
#
# Uncomment and adjust as needed:

# localhost:3000 {
#     reverse_proxy localhost:8080
#     tls internal
# }

# :8080 {
#     root * /path/to/site
#     file_server browse
# }
CADDY_CONF
    success "Caddy config template created at $CADDY_CONFIG_DIR/Caddyfile"
fi
mark_done "config:caddy"
fi

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
    success "act configured (medium Ubuntu images, container reuse)"

# ---- tflint config (Terraform linter) ----
# tflint core only catches syntax/deprecations; the real rules live in the AWS
# ruleset plugin, which must be declared here and fetched via `tflint --init`.
# Without it, "lint with tflint" gives near-zero coverage.
TFLINT_CONFIG="$HOME/.tflint.hcl"
    info "Creating tflint configuration..."
    write_managed "$TFLINT_CONFIG" "#" <<'TFLINT_CONF'
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
TFLINT_CONF
    if [[ "$DRY_RUN" != "true" ]] && installed tflint; then
        tflint --init >> "$LOG_FILE" 2>&1 \
            && success "tflint configured (recommended preset + AWS ruleset v0.48.0)" \
            || warn "tflint config written; run 'tflint --init' to fetch the AWS ruleset"
    fi

# ---- trippy Dracula theme ----
# trippy theme colors are hex WITHOUT the leading '#' (or named colors). Item names
# come from `trip --print-tui-theme-items`; trippy validates the file, so keep them exact.
TRIPPY_CONFIG="$HOME/.config/trippy/trippy.toml"
    info "Creating trippy Dracula theme..."
    write_managed "$TRIPPY_CONFIG" "#" <<'TRIPPY_CONF'
[theme-colors]
bg-color = "282a36"
border-color = "6272a4"
text-color = "f8f8f2"
tab-text-color = "bd93f9"
hops-table-header-bg-color = "44475a"
hops-table-header-text-color = "f8f8f2"
hops-table-row-active-text-color = "50fa7b"
hops-table-row-inactive-text-color = "6272a4"
hops-chart-selected-color = "bd93f9"
hops-chart-unselected-color = "6272a4"
hops-chart-axis-color = "6272a4"
frequency-chart-bar-color = "bd93f9"
frequency-chart-text-color = "f8f8f2"
flows-chart-bar-selected-color = "50fa7b"
flows-chart-bar-unselected-color = "6272a4"
flows-chart-text-current-color = "50fa7b"
flows-chart-text-non-current-color = "f8f8f2"
samples-chart-color = "8be9fd"
samples-chart-lost-color = "ff5555"
help-dialog-bg-color = "44475a"
help-dialog-text-color = "f8f8f2"
settings-dialog-bg-color = "44475a"
settings-tab-text-color = "bd93f9"
info-bar-bg-color = "44475a"
info-bar-text-color = "f8f8f2"
map-world-color = "f8f8f2"
map-radius-color = "ffb86c"
map-selected-color = "50fa7b"
TRIPPY_CONF
    success "trippy Dracula theme configured"

# ---- miller config ----
MLR_CONFIG="$HOME/.mlrrc"
    info "Creating miller configuration..."
    write_managed "$MLR_CONFIG" "#" <<'MLR_CONF'
# miller (mlr) configuration
# Default output format: pretty-printed table
--opprint
# Use CSV for input by default
--icsv
# Allow comments in data files
--skip-trivial-records
MLR_CONF
    success "miller configured (CSV input, pretty table output)"

# ---- asciinema config ----
ASCIINEMA_CONFIG_DIR="$HOME/.config/asciinema"
ASCIINEMA_CONFIG="$ASCIINEMA_CONFIG_DIR/config.toml"
ASCIINEMA_LEGACY_CONFIG="$ASCIINEMA_CONFIG_DIR/config"
    info "Creating asciinema configuration..."
    # asciinema 3.x moved the config to config.toml and switched INI -> TOML, so the
    # 2.x file this script used to write is not read at all — and asciinema prints a
    # three-line banner about it on every invocation for as long as it sits there.
    remove_superseded_managed "$ASCIINEMA_LEGACY_CONFIG" \
        "asciinema 3.x reads $ASCIINEMA_CONFIG and warns on every run while this exists" "(#329)"
    write_managed "$ASCIINEMA_CONFIG" "#" <<'ASCIINEMA_CONF'
# asciinema 3.x configuration. Keys live under [session]; the 2.x [record] section at
# ~/.config/asciinema/config is a different file in a different format and is ignored.

[session]
# Idle time limit (seconds) — trims long pauses
idle_time_limit = 2

# Input recording (disable for security — don't record keystrokes)
capture_input = false

# Default command to record
command = "/bin/zsh -l"
ASCIINEMA_CONF
    success "asciinema configured (2s idle limit, no keystroke recording)"

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
      secondary: "#6272a4"
    border:
      primary: "#bd93f9"
      secondary: "#44475a"
    bg:
      selected: "#44475a"
GHDASH_CONF
        success "gh-dash configured (Dracula theme, PR/issue sections)"
    fi

# ---- stern config ----
if installed stern; then
STERN_CONFIG="$HOME/.config/stern/config.yaml"
    info "Creating stern configuration..."
    write_managed "$STERN_CONFIG" "#" <<'STERN_CONF'
# stern configuration (multi-pod log tailing)

# Output format: default, json, or custom template
template: '{{color .PodColor .PodName}} {{color .ContainerColor .ContainerName}} {{.Message}}{{"\n"}}'

# Tail last N lines on start
tail: 50

# Timestamps
timestamps: short

# Only show logs from last 5 minutes on connect
since: 5m
STERN_CONF
    success "stern configured (50 tail lines, 5m lookback, timestamps)"
fi  # installed stern

# ---- zellij config ----
if installed zellij; then
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"
ZELLIJ_CONFIG="$ZELLIJ_CONFIG_DIR/config.kdl"
info "Configuring zellij (Dracula theme, tmux-like keybindings)..."
write_managed "$ZELLIJ_CONFIG" "//" <<'ZELLIJ_CONF'
// Zellij configuration — Dracula theme, tmux-like prefix

// Use Ctrl-a as prefix (matches tmux config)
keybinds {
    unbind "Ctrl b"
}

// Copy on select
copy_on_select true

// Dracula color theme
themes {
    dracula {
        fg "#f8f8f2"
        bg "#282a36"
        black "#21222c"
        red "#ff5555"
        green "#50fa7b"
        yellow "#f1fa8c"
        blue "#bd93f9"
        magenta "#ff79c6"
        cyan "#8be9fd"
        white "#f8f8f2"
        orange "#ffb86c"
    }
}

theme "dracula"

// Default layout
default_layout "compact"

// Pane frames
pane_frames false

// Mouse mode
mouse_mode true

// Scroll buffer
scroll_buffer_size 50000
ZELLIJ_CONF
success "zellij configured (Dracula theme, compact layout, mouse)"

# 'dev' layout: editor pane + a Claude Code pane side-by-side (AI integration tier 1).
# Launch with:  zellij --layout dev
ZELLIJ_LAYOUTS="$ZELLIJ_CONFIG_DIR/layouts"
info "Creating zellij 'dev' layout..."
write_managed "$ZELLIJ_LAYOUTS/dev.kdl" "//" <<'ZELLIJ_DEV'
// Editor + Claude Code side-by-side. Run:  zellij --layout dev
layout {
    pane split_direction="vertical" {
        pane {
            name "editor"
            command "micro"
        }
        pane size="38%" {
            name "claude"
            command "claude"
        }
    }
}
ZELLIJ_DEV
success "zellij 'dev' layout created (editor + Claude pane: zellij --layout dev)"
fi  # installed zellij

# ---- newsboat config ----
NEWSBOAT_DIR="$HOME/.newsboat"
NEWSBOAT_CONFIG="$NEWSBOAT_DIR/config"
NEWSBOAT_URLS="$NEWSBOAT_DIR/urls"
    info "Creating newsboat config (vim keys, Dracula colors)..."
    write_managed "$NEWSBOAT_CONFIG" "#" <<'NEWSBOAT_CONF'
# Newsboat configuration — vim keys, Dracula colors

# General
auto-reload yes
reload-time 30
reload-threads 4
show-read-feeds no
show-read-articles no

# Vim-like navigation
bind-key j down
bind-key k up
bind-key j next articlelist
bind-key k prev articlelist
bind-key J next-feed articlelist
bind-key K prev-feed articlelist
bind-key G end
bind-key g home
bind-key l open
bind-key h quit

# Dracula colors
color background          color253  color236
color listnormal          color253  color236
color listfocus           color236  color141  bold
color listnormal_unread   color154  color236
color listfocus_unread    color236  color154  bold
color info                color236  color141
color article             color253  color236

# Browser
browser "open %u"

# Date format
datetime-format "%Y-%m-%d"
NEWSBOAT_CONF

    # Starter URLs file
    write_managed "$NEWSBOAT_URLS" "#" <<'NEWSBOAT_URLS_CONF'
# Dev blogs and release feeds — add your own below
https://github.com/anthropics/claude-code/releases.atom "~Claude Code Releases"
https://nodejs.org/en/feed/blog.xml "~Node.js Blog"
https://blog.rust-lang.org/feed.xml "~Rust Blog"
https://github.blog/feed/ "~GitHub Blog"
NEWSBOAT_URLS_CONF
    success "newsboat configured (vim keys, Dracula colors, starter URLs)"

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
    success "mpv configured (hardware accel, save position, screenshots)"

# cliamp self-configures on first run (point it at ~/Media/music from its UI /
# `cliamp ~/Media/music`); no hand-written config here.

# ---- w3m config ----
W3M_CONFIG_DIR="$HOME/.w3m"
W3M_CONFIG="$W3M_CONFIG_DIR/config"
    info "Creating w3m config (UTF-8, cookies off, colors)..."
    write_managed "$W3M_CONFIG" "#" <<'W3M_CONF'
# w3m configuration — sensible privacy + display defaults
display_charset UTF-8
document_charset UTF-8
system_charset UTF-8
auto_detect 2

# Rendering
display_image 0
use_mouse 1
tabstop 8
show_lnum 0

# Colors
color 1
basic_color terminal
anchor_color blue
image_color green
form_color red
mark_color cyan

# Privacy — disable cookies by default
use_cookie 0
accept_cookie 0
show_cookie 0

# Don't follow redirects silently
follow_redirection 5

# Proxy — inherit from env (http_proxy, https_proxy)
use_proxy 1

# Bookmarks
bookmark bookmark.html
keep_cache_in_memory 0
W3M_CONF
    success "w3m configured (UTF-8, cookies off)"

# ---- nushell config ----
# nushell follows XDG as well, and is the one tool that said so out loud: with
# XDG_CONFIG_HOME set it prints "Nushell will not move your configuration files from
# ~/Library/Application Support/nushell" on every invocation, while loading nothing
# from either place. `$nu.env-path` is the file it will actually read (#333).
NUSHELL_ENV="$(XDG_CONFIG_HOME="$HOME/.config" nu -c '$nu.env-path' 2>/dev/null | tail -1)"
NUSHELL_ENV="${NUSHELL_ENV:-$HOME/.config/nushell/env.nu}"
NUSHELL_SUPERSEDED="$HOME/Library/Application Support/nushell/env.nu"
    info "Creating nushell env config..."
    write_managed "$NUSHELL_ENV" "#" <<'NUSHELL_ENV_CONF'
# Nushell environment config

# Use starship prompt if available
if (which starship | is-not-empty) {
    $env.STARSHIP_SHELL = "nu"
    $env.PROMPT_COMMAND = { || starship prompt }
    $env.PROMPT_INDICATOR = ""
}

# Homebrew paths
$env.PATH = ($env.PATH | prepend "/opt/homebrew/bin" | prepend ($env.HOME + "/.local/bin"))
NUSHELL_ENV_CONF
    remove_superseded_managed "$NUSHELL_SUPERSEDED" \
        "nushell reads $NUSHELL_ENV" "(#333)"
    success "nushell env configured (starship prompt, Homebrew paths)"

# ---- git-cliff config ----
GIT_CLIFF_CONFIG_DIR="$HOME/.config/git-cliff"
GIT_CLIFF_CONFIG="$GIT_CLIFF_CONFIG_DIR/cliff.toml"
    info "Creating git-cliff config (conventional commits template)..."
    write_managed "$GIT_CLIFF_CONFIG" "#" <<'GIT_CLIFF_CONF'
# git-cliff configuration — conventional commits changelog

[changelog]
header = """
# Changelog\n
"""
body = """
{% if version %}\
    ## [{{ version | trim_start_matches(pat="v") }}] - {{ timestamp | date(format="%Y-%m-%d") }}
{% else %}\
    ## [Unreleased]
{% endif %}\
{% for group, commits in commits | group_by(attribute="group") %}
    ### {{ group | striptags | trim | upper_first }}
    {% for commit in commits %}
        - {% if commit.scope %}**{{ commit.scope }}**: {% endif %}\
            {{ commit.message | upper_first }}\
            {% if commit.breaking %} (**BREAKING**){% endif %}\
    {% endfor %}
{% endfor %}\n
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true
split_commits = false
commit_parsers = [
    { message = "^feat", group = "Features" },
    { message = "^fix", group = "Bug Fixes" },
    { message = "^perf", group = "Performance" },
    { message = "^doc", group = "Documentation" },
    { message = "^refactor", group = "Refactoring" },
    { message = "^style", group = "Styling" },
    { message = "^test", group = "Testing" },
    { message = "^build", group = "Build" },
    { message = "^ci", group = "CI/CD" },
    { message = "^chore", group = "Miscellaneous" },
]
filter_commits = false
tag_pattern = "v[0-9].*"
sort_commits = "newest"
GIT_CLIFF_CONF
    success "git-cliff configured (conventional commits, grouped changelog)"

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
    mkdir -p "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
    chmod 600 "$SSH_CONFIG"
    success "SSH configured (multiplexing, keychain, keep-alive, strong algorithms)"

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
# VS Code layout (still common in shared repos even though the local editor is croft/micro)
.vscode/settings.json
.vscode/launch.json
*.code-workspace
# croft and micro keep no per-repo state (config lives in ~/.config).

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

# -- Private agent instructions -----------------------------------------------
# The convention on this machine: AGENTS.md is tracked and public (written for
# anyone's agent), CLAUDE.md is private and holds personal preferences and notes.
# Ignored globally rather than per-repo because forgetting the per-repo line
# publishes private notes, and that cannot be undone once pushed. A repo that
# genuinely wants a tracked CLAUDE.md can still `git add -f CLAUDE.md`.
CLAUDE.md
GITIGNORE_GLOBAL
    git config --global core.excludesfile "$GLOBAL_GITIGNORE"
    success "Global .gitignore created and registered with git"

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
    success ".npmrc configured (save-exact, no telemetry, prefer-offline)"

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
    success ".editorconfig created (utf-8, lf, 2-space indent, trim whitespace)"

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
    success ".prettierrc created (single quotes, trailing commas, 100 width)"

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
    success ".curlrc configured (follow redirects, retry, compression, timeouts)"

# ---- Docker daemon config ----
DOCKER_CONFIG_DIR="$HOME/.docker"
DOCKER_DAEMON="$DOCKER_CONFIG_DIR/daemon.json"
# Docker daemon.json is strict JSON (no comment markers), so we jq deep-merge our
# keys into any existing file — adding/updating ours while preserving the user's.
info "Configuring Docker daemon.json..."
mkdir -p "$DOCKER_CONFIG_DIR"
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
        info "Setting Docker buildx as default builder..."
        docker buildx install 2>/dev/null || true
        success "Docker buildx set as default builder (multi-platform builds enabled)"
    fi
fi

fi  # configs (end of first configs segment)

# ---- macOS System Defaults ----
# Top-level category (NOT nested in configs) so --only macos-defaults works.
if should_run "macos-defaults"; then
info "Configuring macOS system defaults..."

if [[ "$DRY_RUN" != "true" ]]; then

# -- Menu bar --
# Auto-hide the native macOS menu bar so SketchyBar owns the top strip (the system
# bar slides down only when you push the cursor to the very top). Without this,
# SketchyBar renders *under* the native bar. Takes effect after logout/restart.
defaults write NSGlobalDomain _HIHideMenuBar -bool true

# -- Dock --
# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true
# Small Dock icon size
defaults write com.apple.dock tilesize -integer 36
# Don't show recent applications
defaults write com.apple.dock show-recents -bool false
# Minimize windows using scale effect (faster than genie)
defaults write com.apple.dock mineffect -string "scale"
# Minimize windows into their application icon
defaults write com.apple.dock minimize-to-application -bool true
# Clear all pinned apps from the Dock (Finder + Trash are permanent fixtures and remain).
if [[ "$DRY_RUN" != "true" ]] && installed dockutil; then
    dockutil --remove all --no-restart >> "$LOG_FILE" 2>&1 || true
    killall Dock >/dev/null 2>&1 || true
fi
success "Dock configured (cleared to Finder + Trash, small icons, auto-hide, scale effect)"

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
success "Screenshots configured (PNG, ~/Screenshots, no shadow)"

# -- Global hotkey: free cmd+space for Ghostty's quick terminal --
# Ghostty binds global:cmd+space, which macOS Spotlight owns by default. Disable
# Spotlight's cmd+space (id 64) and its Finder-search-window variant (id 65) so the
# OS doesn't swallow the hotkey. Takes effect after logout (or `killall SystemUIServer`).
# To keep Spotlight on cmd+space instead, re-enable these and rebind Ghostty to cmd+`.
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 64 \
    "<dict><key>enabled</key><false/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>"
defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 65 \
    "<dict><key>enabled</key><false/></dict>"
success "Spotlight cmd+space disabled (freed for Ghostty; takes effect after logout)"

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
success "Keyboard configured (fast repeat, no press-and-hold, no auto-correct)"

# -- Trackpad --
# Faster tracking speed (0.0 to 3.0, default ~1.0)
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.0
success "Trackpad configured (faster tracking)"

# -- Mission Control --
# Keep Spaces in a fixed order — don't auto-rearrange by most-recent-use, so swiping
# between Spaces is predictable. The cosmetic Mission Control tweaks (animation speed,
# group-by-app) were dropped as unused.
defaults write com.apple.dock mru-spaces -bool false
success "Mission Control: auto-rearrange Spaces disabled (fixed Space order)"

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
    success "Safari configured (developer menu, full URL)"
else
    warn "Safari settings skipped — requires Full Disk Access (System Settings > Privacy & Security > Full Disk Access > Terminal)"
fi

# -- TextEdit --
# Default to plain text (not rich text)
defaults write com.apple.TextEdit RichText -int 0
# Open and save files as UTF-8
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4
success "TextEdit configured (plain text, UTF-8)"

# -- Reduce motion / Faster animations --
# Reduce motion for faster UI (universalaccess is protected — suppress the write error
# on machines where it's managed/denied, matching reduceTransparency below).
defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
# Speed up window resize animations
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
success "Animations configured (reduced motion, fast resize)"

# -- Stage Manager --
# Disable Stage Manager (prevent accidental activation)
defaults write com.apple.WindowManager GloballyEnabled -bool false 2>/dev/null || true
defaults write com.apple.WindowManager AutoHide -bool true 2>/dev/null || true
success "Stage Manager disabled"

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
success "Misc macOS defaults configured"

# -- Screensaver & display sleep timing --
# Screensaver kicks in at 45 min, display sleep at 2hr (charger) / 1hr 15min (battery)
defaults -currentHost write com.apple.screensaver idleTime -int 2700 2>/dev/null || true
sudo pmset -c displaysleep 120 2>/dev/null || true  # charger: 2 hours
sudo pmset -b displaysleep 75 2>/dev/null || true   # battery: 1hr 15min
success "Screensaver at 45min, display sleep at 2hr (charger) / 1h15m (battery)"

# Restart Dock to apply all Dock/Mission Control changes
killall Dock 2>/dev/null || true

else
    info "[DRY RUN] Would configure macOS system defaults"
fi  # DRY_RUN

fi  # macos-defaults

if should_run "configs"; then  # resume configs (second segment)

# ---- ~/.hushlogin (suppress "Last login" message) ----
if ! is_done "config:hushlogin"; then
if [[ -f "$HOME/.hushlogin" ]]; then
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

# bun
if [[ -d "$HOME/.bun" ]]; then
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
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

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
ZPROFILE_CONF
    success "$HOME/.zprofile created (editor, pager, XDG, Go, Rust, bun, pnpm, mise, direnv, OrbStack)"

# ---- ~/.zshenv (every zsh invocation — interactive or not) ----
ZSHENV="$HOME/.zshenv"
    info "Creating ~/.zshenv..."
    write_managed "$ZSHENV" "#" <<'ZSHENV_CONF'
# mise (version manager) — sourced by every zsh invocation (interactive,
# non-interactive, login or not). This ensures tools like node/npx are
# available in Claude Code, IDE terminals, and scripted shells.
command -v mise &>/dev/null && eval "$(mise activate zsh)"
ZSHENV_CONF
    success "$HOME/.zshenv created (mise activation for all shell types)"

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
    success "$HOME/.vimrc created (line numbers, clipboard, mouse, Dracula colors, space leader)"

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
    success "$HOME/.nanorc created (line numbers, auto-indent, mouse, syntax highlighting)"

# ---- bat extended config (file type mappings) ----
if ! is_done "config:bat-mappings"; then
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    BAT_CONFIG="$BAT_CONFIG_DIR/config"
    if [[ -n "$BAT_CONFIG_DIR" ]] && [[ -f "$BAT_CONFIG" ]]; then
        # Add mappings if not already present
        if ! grep -q "map-syntax" "$BAT_CONFIG" 2>/dev/null; then
            info "Adding bat file type mappings..."
            cat >> "$BAT_CONFIG" <<'BAT_MAPPINGS'

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
            success "bat file type mappings added"
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
    success "mise configured (auto-install, trust ~/Code)"

# ---- topgrade config ----
TOPGRADE_CONFIG="$HOME/.config/topgrade.toml"
    info "Creating topgrade configuration..."
    write_managed "$TOPGRADE_CONFIG" "#" <<'TOPGRADE_CONF'
# topgrade configuration — update everything with one command
# Run: topgrade

# Don't ask for confirmation
#assume_yes = true

# Cleanup after update
cleanup = true

# Disable things you don't want updated automatically
[misc]
# Pre-commands (run before updates)
# pre_commands = { "Backup" = "backup-dotfiles" }

[brew]
greedy_cask = true

[linux]
TOPGRADE_CONF
    success "topgrade configured (cleanup, greedy cask updates)"

# ---- fastfetch config ----
FASTFETCH_CONFIG="$HOME/.config/fastfetch/config.jsonc"
    info "Creating fastfetch configuration..."
    write_managed "$FASTFETCH_CONFIG" "#" <<'FASTFETCH_CONF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "small",
        "color": {
            "1": "magenta",
            "2": "cyan"
        },
        "padding": { "top": 1, "left": 2, "right": 2 }
    },
    "display": {
        "separator": "  ",
        "color": {
            "keys": "magenta",
            "title": "cyan"
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
        { "type": "title", "format": "{user-name}@{host-name}" },
        { "type": "separator", "string": "─" },
        { "type": "os", "key": "  OS" },
        { "type": "host", "key": " 󰒋 Host" },
        { "type": "kernel", "key": "  Kernel" },
        { "type": "uptime", "key": " 󰅐 Uptime" },
        { "type": "packages", "key": " 󰏗 Packages" },
        { "type": "shell", "key": "  Shell" },
        { "type": "terminal", "key": "  Terminal" },
        { "type": "separator", "string": "─" },
        { "type": "cpu", "key": " 󰍛 CPU", "showPeCoreCount": false },
        { "type": "gpu", "key": " 󰢮 GPU" },
        { "type": "memory", "key": "  Memory" },
        { "type": "disk", "key": " 󰋊 Disk", "folders": "/" },
        { "type": "battery", "key": " 󰁹 Battery" },
        { "type": "separator", "string": "─" },
        {
            "type": "command",
            "key": "  Node",
            "text": "node --version 2>/dev/null | tr -d 'v' || echo '—'"
        },
        {
            "type": "command",
            "key": "  Python",
            "text": "python3 --version 2>/dev/null | cut -d' ' -f2 || echo '—'"
        },
        {
            "type": "command",
            "key": "  Go",
            "text": "go version 2>/dev/null | awk '{print $3}' | tr -d 'go' || echo '—'"
        },
        {
            "type": "command",
            "key": " 🦀 Rust",
            "text": "rustc --version 2>/dev/null | awk '{print $2}' || echo '—'"
        },
        {
            "type": "command",
            "key": " 󰜫 Docker",
            "text": "docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo '—'"
        },
        { "type": "separator", "string": "─" },
        { "type": "colors", "symbol": "circle" }
    ]
}
FASTFETCH_CONF
    success "fastfetch configured (themed layout, Nerd Font icons, dev tool versions)"

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
    success "$HOME/.ripgreprc configured (smart-case, hidden files, custom types)"

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
    success "$HOME/.fdignore created"

# ---- btop Dracula theme ----
BTOP_CONFIG_DIR="$HOME/.config/btop"
BTOP_CONFIG="$BTOP_CONFIG_DIR/btop.conf"
    info "Creating btop configuration..."
    write_managed "$BTOP_CONFIG" "#" <<'BTOP_CONF'
#? Config file for btop

# Color theme
color_theme = "dracula"

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
    # Download Dracula theme for btop
    write_managed "$BTOP_CONFIG_DIR/themes/dracula.theme" "#" <<'BTOP_DRACULA'
# Dracula theme for btop
theme[main_bg]="#282a36"
theme[main_fg]="#f8f8f2"
theme[title]="#f8f8f2"
theme[hi_fg]="#bd93f9"
theme[selected_bg]="#44475a"
theme[selected_fg]="#f8f8f2"
theme[inactive_fg]="#6272a4"
theme[graph_text]="#f8f8f2"
theme[meter_bg]="#44475a"
theme[proc_misc]="#8be9fd"
theme[cpu_box]="#bd93f9"
theme[mem_box]="#50fa7b"
theme[net_box]="#ff79c6"
theme[proc_box]="#8be9fd"
theme[div_line]="#44475a"
theme[temp_start]="#50fa7b"
theme[temp_mid]="#ffb86c"
theme[temp_end]="#ff5555"
theme[cpu_start]="#bd93f9"
theme[cpu_mid]="#ff79c6"
theme[cpu_end]="#ff5555"
theme[free_start]="#50fa7b"
theme[free_mid]="#f1fa8c"
theme[free_end]="#ff5555"
theme[cached_start]="#8be9fd"
theme[cached_mid]="#bd93f9"
theme[cached_end]="#ff79c6"
theme[available_start]="#50fa7b"
theme[available_mid]="#f1fa8c"
theme[available_end]="#ffb86c"
theme[used_start]="#ff79c6"
theme[used_mid]="#ffb86c"
theme[used_end]="#ff5555"
theme[download_start]="#bd93f9"
theme[download_mid]="#ff79c6"
theme[download_end]="#ff5555"
theme[upload_start]="#50fa7b"
theme[upload_mid]="#f1fa8c"
theme[upload_end]="#ffb86c"
theme[process_start]="#8be9fd"
theme[process_mid]="#bd93f9"
theme[process_end]="#ff79c6"
BTOP_DRACULA
    success "btop configured with Dracula theme"

# ---- lazydocker Dracula config ----
LAZYDOCKER_CONFIG_DIR="$HOME/.config/lazydocker"
LAZYDOCKER_CONFIG="$LAZYDOCKER_CONFIG_DIR/config.yml"
    info "Creating lazydocker configuration..."
    write_managed "$LAZYDOCKER_CONFIG" "#" <<'LAZYDOCKER_CONF'
gui:
  theme:
    activeBorderColor:
      - "#bd93f9"
      - bold
    inactiveBorderColor:
      - "#6272a4"
    selectedLineBgColor:
      - "#44475a"
    optionsTextColor:
      - "#8be9fd"
  returnImmediately: false
  wrapMainPanel: true
commandTemplates:
  restartService: docker-compose restart {{ .Service.Name }}
  dockerCompose: docker compose
logs:
  timestamps: true
  since: "60m"
LAZYDOCKER_CONF
    success "lazydocker configured with Dracula theme"

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
    git config --global commit.template "$GIT_COMMIT_TEMPLATE"
    success "Git commit template created and registered"

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
# git-lfs is the exception, and is deliberately NOT chained (#311). It is
# core.hooksPath aware, so `git lfs install` writes its four hooks here from any
# repo — which made `git lfs pre-push` run on EVERY push on the machine, including
# in repositories that have never held an LFS object. That is normally just a wasted
# lock-verification round-trip, but against a GitHub wiki remote the lock API cannot
# authorise a wiki push at all, so it fails, and the chain aborts on the first
# non-zero status: every wiki push blocked, with an error naming authentication
# rather than LFS. A global hook cannot know which repositories use LFS, so LFS is
# opted into per repository instead — see `git-lfs-enable-repo`, which writes the
# hooks to .git/hooks, where the chain runs them as the repo's own hook.
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
# Sourced by every hook in this directory. Runs, in order:
#   1. the repository's own hook (.git/hooks/<type>)
#   2. any third-party hook preserved in <type>.d/ (e.g. git-lfs)
# aborting on the first non-zero status, which is the hook contract.

run_hook_chain() {
    local hook="$1"; shift
    local hooks_dir status=0 stdin_file="" repo_hook f
    hooks_dir="$(dirname "${BASH_SOURCE[0]}")"
    DEV_SETUP_REPO_HOOK_RAN=0

    # These hook types are fed data on stdin. Buffer it once, then hand every link in
    # the chain its own copy — stdin can only be consumed by the first reader, so
    # without this a chained git-lfs pre-push would see an empty ref list.
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
    # 1a. Git LFS is not chained globally (#311), so it is possible to have a repo
    #     that tracks paths through the lfs filter but has no LFS pre-push hook. That
    #     pushes the POINTER FILES WITHOUT THE OBJECTS behind them, and the push
    #     SUCCEEDS — the breakage lands on whoever clones next. It is the one failure
    #     this arrangement can produce silently, so it is refused here rather than
    #     discovered later (#313).
    #
    #     Aborting rather than warning is deliberate: a warning scrolls past in push
    #     output and would not stop the bad push, which is the entire point. Unlike
    #     the wiki case in #311 this cannot misfire on a healthy repo — LFS-tracked
    #     paths with no LFS hook is always wrong. `--no-verify` still bypasses it,
    #     and `dev-setup.lfsguard false` disables it for a repo that pushes its LFS
    #     objects some other way (CI, a mirror).
    if [ "$hook" = "pre-push" ] && command -v git-lfs >/dev/null 2>&1 &&
       [ -n "$(git ls-files ':(attr:filter=lfs)' 2>/dev/null | head -n 1)" ] &&
       ! grep -qs 'git lfs pre-push' "$common/hooks/pre-push" &&
       [ "$(git config --bool --get dev-setup.lfsguard 2>/dev/null)" != "false" ]; then
        echo "ERROR: this repository tracks files with Git LFS, but has no LFS pre-push hook." >&2
        echo "       Pushing now would upload the pointer files WITHOUT the objects behind" >&2
        echo "       them, and the push would succeed — leaving the remote broken." >&2
        echo "" >&2
        echo "  Fix:      git-lfs-enable-repo" >&2
        echo "  Bypass:   git push --no-verify" >&2
        echo "  Disable:  git config dev-setup.lfsguard false" >&2
        [ -n "$stdin_file" ] && rm -f "$stdin_file"
        return 1
    fi

    if [ -n "$repo_hook" ] && [ -x "$repo_hook" ]; then
        DEV_SETUP_REPO_HOOK_RAN=1
        _chain_run "$repo_hook" "$@" || status=$?
        if [ "$status" -ne 0 ]; then
            [ -n "$stdin_file" ] && rm -f "$stdin_file"
            return "$status"
        fi
    fi

    # 2. Third-party hooks that were already installed in this directory and moved
    #    aside so a delegator could take the name (git-lfs, most likely).
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
#
# git-lfs is the exception — its hooks are DISCARDED rather than preserved (#311).
# Nothing is lost by deleting them: `git lfs install` re-creates them on demand, and
# a repository that actually uses LFS opts in with `git-lfs-enable-repo`, which
# installs them where the chain runs them as the repo's own hook. Copies preserved
# by earlier versions are purged too, so a machine provisioned while LFS was still
# chained is repaired on the next run rather than keeping the hook forever.
preserve_foreign_hook() {
    local type="$1"
    local path="$GIT_HOOKS_DIR/$type" dest_dir="$GIT_HOOKS_DIR/$type.d" name f

    for f in "$dest_dir"/10-git-lfs*; do
        [[ -f "$f" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would unchain preserved git-lfs hook $type.d/${f##*/} (#311)"
        else
            rm -f "$f"
            info "Unchained preserved git-lfs $type hook — LFS is per-repo now (#311)"
        fi
    done
    rmdir "$dest_dir" 2>/dev/null || true   # tidy up if that was the only link

    [[ -f "$path" ]] || return 0
    grep -qF "dev-setup managed block" "$path" 2>/dev/null && return 0   # already ours

    if grep -qE 'git[- ]lfs' "$path" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove global git-lfs $type hook (LFS is per-repo, #311)"
        else
            rm -f "$path"
            info "Removed global git-lfs $type hook — enable LFS per repo with git-lfs-enable-repo (#311)"
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
        if cmp -s "$path" "$f"; then rm -f "$path"; return 0; fi   # already preserved
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
    echo "Consider using git-lfs or commit with --no-verify to bypass."
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
git config --global core.hooksPath "$GIT_HOOKS_DIR"

success "Global git hooks created (${#GIT_HOOK_TYPES[@]} delegators + debug/large-file/conflict checks)"

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
    success "AWS CLI configured (us-east-1, json, bat pager, auto-prompt)"

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
    success "GitHub CLI configured (SSH protocol, micro editor, delta pager, aliases)"

# ---- glab (GitLab CLI) config — mirror the gh conveniences ----
# GitLab uses merge requests, so the pr* aliases point at `mr` (same alias NAMES as
# gh, so muscle memory carries over). glab owns its config schema, so drive it via
# `glab config set` / `glab alias set` rather than hand-writing YAML.
if [[ "$DRY_RUN" != "true" ]] && installed glab && ! is_done "config:glab"; then
    info "Configuring glab (SSH, micro, gh-style aliases → merge requests)..."
    _glab_failed=0
    glab config set git_protocol ssh >> "$LOG_FILE" 2>&1 || _glab_failed=$((_glab_failed + 1))
    glab config set editor micro >> "$LOG_FILE" 2>&1 || _glab_failed=$((_glab_failed + 1))
    # No pager is set here. `glab config set glab_pager delta` is REJECTED by glab
    # 1.113.0 ("not a recognized glab config key") even though `glab config` help
    # documents the key, and plain `pager` is refused too — so the call could only ever
    # print an error and configure nothing (#285). The binary does carry a GLAB_PAGER
    # env var; it is exported from ~/.zshrc instead, where a failure costs nothing.
    # NOTE: the heredoc below is a DATA table — every line is parsed as
    # "<alias>|<command>", so it cannot carry comments. gh's `rc` (repo clone) is not
    # mirrored because `glab rc` is a real command (runner controllers); `rcl` is the
    # nearest free name (#285).
    while IFS='|' read -r _glab_alias _glab_cmd; do
        [[ -z "$_glab_alias" ]] && continue
        glab alias set "$_glab_alias" "$_glab_cmd" >> "$LOG_FILE" 2>&1 \
            || { warn "glab alias '$_glab_alias' not set (name taken by a glab command?)"; _glab_failed=$((_glab_failed + 1)); }
    done <<'GLAB_ALIASES'
co|mr checkout
pv|mr view --web
pc|mr create --web
pl|mr list
pm|mr merge --squash --remove-source-branch
il|issue list
iv|issue view --web
ic|issue create --web
rv|repo view --web
rcl|repo clone
rl|repo list
runs|ci list
watch|ci view
rerun|ci retry
rel|release create
GLAB_ALIASES
    unset _glab_alias _glab_cmd
    mark_done "config:glab"
    if [[ "$_glab_failed" -eq 0 ]]; then
        success "glab configured (SSH, micro; gh-style aliases mapped to GitLab MRs/CI)"
    else
        warn "glab configured with $_glab_failed problem(s) — see $LOG_FILE"
    fi
    unset _glab_failed
fi

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
    success "pip configured (require virtualenv, no telemetry)"

# ---- gemrc (Ruby) ----
GEMRC="$HOME/.gemrc"
    info "Creating gemrc..."
    write_managed "$GEMRC" "#" <<'GEM_CONF'
# Skip documentation when installing gems (saves time and disk)
gem: --no-document
GEM_CONF
    success "$HOME/.gemrc created (no docs on gem install)"

# ---- pgcli config ----
PGCLI_CONFIG_DIR="$HOME/.config/pgcli"
PGCLI_CONFIG="$PGCLI_CONFIG_DIR/config"
    info "Creating pgcli configuration..."
    write_managed "$PGCLI_CONFIG" "#" <<'PGCLI_CONF'
[main]
# Multi-line mode (enter doesn't execute, use F5 or ctrl+enter)
multi_line = True

# Auto-expand tables if they fit
auto_expand = True

# Expanded output (like \x in psql)
expand = False

# Pager
pager = bat --style=plain --paging=always

# Prompt format
prompt = '\u@\h:\d> '

# History file
log_file = ~/.config/pgcli/log
history_file = ~/.config/pgcli/history

# Enable destructive warning (DROP, DELETE, TRUNCATE, ALTER)
destructive_warning = all

# Syntax style (Dracula-ish)
syntax_style = monokai

# Keyword casing
keyword_casing = upper

# Auto-completion
smart_completion = True
PGCLI_CONF
    success "pgcli configured (multi-line, auto-expand, destructive warnings, bat pager)"

# ---- harlequin config ----
HARLEQUIN_CONFIG_DIR="$HOME/.config/harlequin"
HARLEQUIN_CONFIG="$HARLEQUIN_CONFIG_DIR/config.toml"
    info "Creating harlequin configuration..."
    write_managed "$HARLEQUIN_CONFIG" "#" <<'HARLEQUIN_CONF'
# Harlequin SQL IDE — https://harlequin.sql/docs/config-file/
[defaults]
theme = "dracula"
keymap_name = ["vscode"]
show_files = true
locale = "en_US.UTF-8"
HARLEQUIN_CONF
    success "harlequin configured (Dracula theme, vscode keymap)"

# ---- mycli config ----
MYCLIRC="$HOME/.myclirc"
    info "Creating mycli configuration..."
    write_managed "$MYCLIRC" "#" <<'MYCLI_CONF'
[main]
# Multi-line mode
multi_line = True

# Auto-expand tables
auto_expand = True

# Pager
pager = bat --style=plain --paging=always

# Prompt format
prompt = '\u@\h:\d> '

# Syntax style
syntax_style = monokai

# Keyword casing
keyword_casing = upper

# Smart completion
smart_completion = True

# Destructive warning
destructive_warning = True

# Log and history
log_file = ~/.mycli.log
history_file = ~/.mycli-history

# Wider output before wrapping
wider_completion_menu = True
MYCLI_CONF
    success "$HOME/.myclirc configured (multi-line, auto-expand, destructive warnings)"

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
    success "Global justfile created (~/.justfile — system, git, docker, network, cleanup, info recipes)"

# ---- Ghostty config ----
GHOSTTY_CONFIG_DIR="$HOME/.config/ghostty"
GHOSTTY_CONFIG="$GHOSTTY_CONFIG_DIR/config"
info "Configuring Ghostty..."
write_managed "$GHOSTTY_CONFIG" "#" <<'GHOSTTY_CONF'
# Ghostty configuration
# Docs: https://ghostty.org/docs/config

# Font — the Nerd Font variant so glyph icons (eza, starship, lazygit, Claude
# Code, etc.) render natively in the terminal instead of relying on font
# fallback. Same family SketchyBar uses. If any double-width nerd glyphs
# misalign, switch to "JetBrainsMono Nerd Font Mono" (forces single-width).
font-family = "JetBrainsMono Nerd Font"
font-size = 14

# Dracula theme
background = 282a36
foreground = f8f8f2
selection-background = 44475a
selection-foreground = f8f8f2
palette = 0=#21222c
palette = 1=#ff5555
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#bd93f9
palette = 5=#ff79c6
palette = 6=#8be9fd
palette = 7=#f8f8f2
palette = 8=#6272a4
palette = 9=#ff6e6e
palette = 10=#69ff94
palette = 11=#ffffa5
palette = 12=#d6acff
palette = 13=#ff92df
palette = 14=#a4ffff
palette = 15=#ffffff

# Window
window-padding-x = 8
window-padding-y = 4
window-decoration = true
macos-titlebar-style = transparent

# Behavior
copy-on-select = clipboard
confirm-close-surface = false
mouse-hide-while-typing = true

# Quick terminal — global dropdown launcher (Spotlight/Raycast replacement).
# Requires Accessibility permission for Ghostty and disabling Spotlight's
# cmd+space first (see ~/Desktop/POST_SETUP_CHECKLIST.md). In the dropdown,
# type `a` to fuzzy-launch an app, `ff` to find files, `s <q>` for Spotlight search.
keybind = global:cmd+space=toggle_quick_terminal
quick-terminal-position = top
# `mouse` puts the dropdown on the display the cursor is on (multi-monitor correct);
# on a single display it is identical to `main`.
quick-terminal-screen = mouse
quick-terminal-animation-duration = 0.15
quick-terminal-autohide = true

# Global "new Ghostty window on the current Space". The `a` launcher uses `open`, which
# for an already-running app just re-activates its existing window (yanking you to whatever
# Space that window is on) instead of making a new one where you are. A freshly-created
# window lands on the active Space, so this hotkey reliably drops a Ghostty window onto the
# Space you're actually looking at. Rebind the chord to taste.
keybind = global:cmd+alt+t=new_window
GHOSTTY_CONF
success "Ghostty configured (JetBrainsMono Nerd Font, Dracula theme, transparent titlebar)"

# ---- Ghostty auto-start + keep-alive (launchd agent) ----
# Ghostty's global cmd+space quick-terminal keybind only works while Ghostty is running:
# a fresh login with no Ghostty leaves the hotkey dead, and if you later quit Ghostty the
# hotkey stays dead until you relaunch it by hand. This agent keeps Ghostty alive.
# `open -gW -a Ghostty` launches it in the BACKGROUND (`-g`, no focus steal at login) and
# WAITS for it to exit (`-W`), so launchd can track the process and — with KeepAlive —
# relaunch it within seconds whenever it quits. Because `-W` also attaches to an
# already-running Ghostty, re-loading the agent never spawns a duplicate window. To stop
# Ghostty for good, unload the agent:
#   launchctl unload ~/Library/LaunchAgents/com.ghostty.autostart.plist
# Refreshed on every run (content-diffed, not create-once) so existing machines pick up
# plist changes. Still needs Accessibility permission for Ghostty (see the checklist).
GHOSTTY_APP="/Applications/Ghostty.app"
GHOSTTY_PLIST="$HOME/Library/LaunchAgents/com.ghostty.autostart.plist"
if [[ ! -d "$GHOSTTY_APP" ]]; then
    warn "Ghostty.app not found in /Applications — skipping keep-alive launch agent"
elif [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would (re)write Ghostty keep-alive launch agent (open -gW, KeepAlive)"
else
    mkdir -p "$HOME/Library/LaunchAgents"
    _ghostty_plist_new="$(cat <<'GHOSTTY_PLIST_EOF'
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
    if [[ ! -f "$GHOSTTY_PLIST" ]] || ! printf '%s\n' "$_ghostty_plist_new" | diff -q - "$GHOSTTY_PLIST" >/dev/null 2>&1; then
        printf '%s\n' "$_ghostty_plist_new" > "$GHOSTTY_PLIST"
        launchctl unload "$GHOSTTY_PLIST" >> "$LOG_FILE" 2>&1 || true
        launchctl load "$GHOSTTY_PLIST" >> "$LOG_FILE" 2>&1 || warn "Could not load Ghostty launch agent"
        success "Ghostty keep-alive agent (re)written and reloaded (open -gW, KeepAlive)"
    else
        warn "Ghostty keep-alive agent already current"
    fi
fi

# ---- SketchyBar config (Dracula status bar) ----
# Shell-based config (no SbarLua build step). Items show a Nerd Font glyph icon
# (icons.sh) + a value label; the plugins swap the glyph by state (battery level,
# wifi/bt/vpn on-off, volume level). Glyphs need JetBrainsMono Nerd Font (installed).
SBAR_DIR="$HOME/.config/sketchybar"
SBAR_PLUGINS="$SBAR_DIR/plugins"
    info "Creating SketchyBar configuration (Dracula, system widgets)..."

    # Shared Dracula palette (sourced by plugins)
    write_managed_script "$SBAR_DIR/colors.sh" <<'SBAR_COLORS'
#!/usr/bin/env bash
export BG=0xff282a36
export FG=0xfff8f8f2
export LINE=0xff44475a
export COMMENT=0xff6272a4
export CYAN=0xff8be9fd
export GREEN=0xff50fa7b
export ORANGE=0xffffb86c
export PINK=0xffff79c6
export PURPLE=0xffbd93f9
export RED=0xffff5555
export YELLOW=0xfff1fa8c
# Nerd Font glyphs (sourced here so every plugin + the rc get them via colors.sh).
[ -r "$HOME/.config/sketchybar/icons.sh" ] && source "$HOME/.config/sketchybar/icons.sh"
SBAR_COLORS

    # Shared Nerd Font glyphs (JetBrainsMono Nerd Font). Bash $'\U...' escapes expand
    # to the glyph at source time. Codepoints: nf-fa/nf-oct/nf-md sets.
    write_managed_script "$SBAR_DIR/icons.sh" <<'SBAR_ICONS'
#!/usr/bin/env bash
export ICON_CLOCK=$'\uf017'             # nf-fa-clock
export ICON_CPU=$'\uf4bc'               # nf-oct-cpu
export ICON_MEM=$'\U000F035B'          # nf-md-memory
export ICON_BATT=$'\U000F0079'         # nf-md-battery
export ICON_BATT_CHARGE=$'\U000F0084'  # nf-md-battery-charging
export ICON_BATT_LOW=$'\U000F0083'     # nf-md-battery-alert
export ICON_BT_ON=$'\U000F00AF'        # nf-md-bluetooth
export ICON_BT_OFF=$'\U000F00B2'       # nf-md-bluetooth-off
export ICON_WIFI=$'\U000F05A9'         # nf-md-wifi
export ICON_WIFI_OFF=$'\U000F05AA'     # nf-md-wifi-off
export ICON_VOL=$'\U000F057E'          # nf-md-volume-high
export ICON_VOL_MUTE=$'\U000F0581'     # nf-md-volume-off
export ICON_VPN_ON=$'\U000F0565'       # nf-md-shield-check
export ICON_VPN_OFF=$'\U000F099D'      # nf-md-shield-off-outline
export ICON_SHOT=$'\U000F0100'         # nf-md-camera (Shottr capture menu)
export ICON_SHOT_AREA=$'\U000F0126'    # nf-md-crop (area selection)
export ICON_SHOT_WINDOW=$'\U000F0379'  # nf-md-window-maximize (window capture)
export ICON_SHOT_FULL=$'\U000F0293'    # nf-md-fullscreen (fullscreen capture)
export ICON_SHOT_SCROLL=$'\U000F0619'  # nf-md-arrow-expand-vertical (scrolling capture)
SBAR_ICONS

    write_managed_script "$SBAR_DIR/sketchybarrc" <<'SBAR_RC'
#!/usr/bin/env bash
# SketchyBar — Dracula. Docs: https://felixkratz.github.io/SketchyBar
source "$HOME/.config/sketchybar/colors.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
FONT="JetBrainsMono Nerd Font"

sketchybar --bar height=32 position=top blur_radius=30 color=$BG \
                 padding_left=8 padding_right=8 sticky=on

sketchybar --default updates=when_shown \
                     icon.font="$FONT:Bold:13.0" icon.color=$FG \
                     icon.padding_left=6 icon.padding_right=3 \
                     label.font="$FONT:Semibold:13.0" label.color=$FG \
                     label.padding_left=3 label.padding_right=6 \
                     padding_left=6 padding_right=6 \
                     background.color=$LINE background.corner_radius=6 background.height=22

# --- Left: date/time (far left), then focused app ---
# Click the clock to open herald's calendar in a Ghostty quick terminal.
sketchybar --add item clock left \
           --set clock update_freq=10 icon="$ICON_CLOCK" icon.color=$PURPLE \
                 label.padding_left=6 \
                 click_script="open -a Ghostty; sleep 0.2; osascript -e 'tell application \"System Events\" to keystroke \"herald\" & return' >/dev/null 2>&1" \
                 script="$PLUGIN_DIR/clock.sh"

sketchybar --add item front_app left \
           --subscribe front_app front_app_switched \
           --set front_app icon.drawing=off label.color=$PURPLE label.font="$FONT:Bold:13.0" \
                 label.padding_left=6 \
                 script="$PLUGIN_DIR/front_app.sh"

# --- Right (added right-to-left visually) ---
sketchybar --add item battery right \
           --subscribe battery system_woke power_source_change \
           --set battery update_freq=120 script="$PLUGIN_DIR/battery.sh"

sketchybar --add item bluetooth right \
           --set bluetooth update_freq=30 label.drawing=off icon.padding_right=6 \
                 click_script="blueutil --power toggle" \
                 script="$PLUGIN_DIR/bluetooth.sh"

sketchybar --add item wifi right \
           --set wifi update_freq=30 label.color=$GREEN \
                 script="$PLUGIN_DIR/wifi.sh"

sketchybar --add item volume right \
           --subscribe volume volume_change \
           --set volume script="$PLUGIN_DIR/volume.sh"

sketchybar --add item cpu right \
           --set cpu update_freq=5 icon="$ICON_CPU" icon.color=$ORANGE label.color=$ORANGE \
                 script="$PLUGIN_DIR/cpu.sh"

sketchybar --add item mem right \
           --set mem update_freq=10 icon="$ICON_MEM" icon.color=$YELLOW label.color=$YELLOW \
                 script="$PLUGIN_DIR/mem.sh"

sketchybar --add item vpn right \
           --set vpn update_freq=15 \
                 click_script="$PLUGIN_DIR/vpn_toggle.sh" \
                 script="$PLUGIN_DIR/vpn.sh"

# --- Right: Shottr capture menu (camera glyph -> click-to-open popup) ---
# Native menu bar is auto-hidden, so this stands in for Shottr's own menu-bar icon.
# Left-click toggles a capture menu; right-click is a quick area grab. Each entry
# drives Shottr via its shottr:// URL scheme. Auto-closes on mouse.exited.global.
sketchybar --add item shottr right \
           --set shottr icon="$ICON_SHOT" icon.color=$CYAN icon.font="$FONT:Bold:14.0" \
                 label.drawing=off \
                 popup.horizontal=off popup.background.color=$BG \
                 popup.background.corner_radius=8 popup.background.border_width=2 \
                 popup.background.border_color=$LINE popup.background.shadow.drawing=on \
                 click_script="$PLUGIN_DIR/shottr_click.sh" \
                 script="$PLUGIN_DIR/shottr.sh" \
           --subscribe shottr mouse.exited.global

sketchybar --add item shottr.area popup.shottr \
           --set shottr.area icon="$ICON_SHOT_AREA" icon.color=$CYAN label="Area" \
                 background.drawing=off label.padding_right=14 \
                 click_script="open 'shottr://grab/area'; sketchybar --set shottr popup.drawing=off"
sketchybar --add item shottr.window popup.shottr \
           --set shottr.window icon="$ICON_SHOT_WINDOW" icon.color=$CYAN label="Window" \
                 background.drawing=off label.padding_right=14 \
                 click_script="open 'shottr://grab/window'; sketchybar --set shottr popup.drawing=off"
sketchybar --add item shottr.full popup.shottr \
           --set shottr.full icon="$ICON_SHOT_FULL" icon.color=$CYAN label="Fullscreen" \
                 background.drawing=off label.padding_right=14 \
                 click_script="open 'shottr://grab/fullscreen'; sketchybar --set shottr popup.drawing=off"
sketchybar --add item shottr.scroll popup.shottr \
           --set shottr.scroll icon="$ICON_SHOT_SCROLL" icon.color=$CYAN label="Scrolling" \
                 background.drawing=off label.padding_right=14 \
                 click_script="open 'shottr://grab/scrolling'; sketchybar --set shottr popup.drawing=off"

sketchybar --update
SBAR_RC

    # -- plugins --
    write_managed_script "$SBAR_PLUGINS/front_app.sh" <<'P_FRONT'
#!/usr/bin/env bash
[ "$SENDER" = "front_app_switched" ] && sketchybar --set "$NAME" label="$INFO"
P_FRONT

    write_managed_script "$SBAR_PLUGINS/clock.sh" <<'P_CLOCK'
#!/usr/bin/env bash
sketchybar --set "$NAME" label="$(date '+%a %d %b  %H:%M')"
P_CLOCK

    write_managed_script "$SBAR_PLUGINS/battery.sh" <<'P_BATT'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
PCT=$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
# Mac mini / no battery: hide the item entirely.
if [ -z "$PCT" ]; then sketchybar --set "$NAME" drawing=off; exit 0; fi
CHARGING=$(pmset -g batt | grep -c 'AC Power')
COLOR=$GREEN
[ "$PCT" -lt 40 ] && COLOR=$YELLOW
[ "$PCT" -lt 20 ] && COLOR=$RED
ICON="$ICON_BATT"
[ "$PCT" -lt 20 ] && ICON="$ICON_BATT_LOW"
[ "$CHARGING" -gt 0 ] && ICON="$ICON_BATT_CHARGE"
sketchybar --set "$NAME" drawing=on icon="$ICON" icon.color=$COLOR label="${PCT}%" label.color=$COLOR
P_BATT

    write_managed_script "$SBAR_PLUGINS/bluetooth.sh" <<'P_BT'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
if command -v blueutil >/dev/null 2>&1 && [ "$(blueutil --power)" = "1" ]; then
    sketchybar --set "$NAME" icon="$ICON_BT_ON" icon.color=$PURPLE
else
    sketchybar --set "$NAME" icon="$ICON_BT_OFF" icon.color=$COMMENT
fi
P_BT

    write_managed_script "$SBAR_PLUGINS/wifi.sh" <<'P_WIFI'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
SSID=$(ipconfig getsummary en0 2>/dev/null | awk -F ' SSID : ' '/ SSID : / {print $2; exit}')
if [ -n "$SSID" ]; then
    sketchybar --set "$NAME" icon="$ICON_WIFI" icon.color=$GREEN label.drawing=off
else
    sketchybar --set "$NAME" icon="$ICON_WIFI_OFF" icon.color=$COMMENT label.drawing=off
fi
P_WIFI

    write_managed_script "$SBAR_PLUGINS/volume.sh" <<'P_VOL'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
VOL="${INFO:-$(osascript -e 'output volume of (get volume settings)')}"
ICON="$ICON_VOL"; [ "${VOL:-0}" -eq 0 ] 2>/dev/null && ICON="$ICON_VOL_MUTE"
sketchybar --set "$NAME" icon="$ICON" icon.color=$CYAN label="${VOL}%" label.color=$CYAN
P_VOL

    write_managed_script "$SBAR_PLUGINS/cpu.sh" <<'P_CPU'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%d", s/'"$(sysctl -n hw.ncpu)"'}')
sketchybar --set "$NAME" label="${CPU}%" label.color=$ORANGE
P_CPU

    write_managed_script "$SBAR_PLUGINS/mem.sh" <<'P_MEM'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
USED=$(memory_pressure 2>/dev/null | awk -F ': ' '/System-wide memory free percentage/ {print 100-$2}' | tr -d '%')
[ -z "$USED" ] && USED="?"
sketchybar --set "$NAME" label="${USED}%" label.color=$YELLOW
P_MEM

    write_managed_script "$SBAR_PLUGINS/vpn.sh" <<'P_VPN'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
if command -v mullvad >/dev/null 2>&1 && mullvad status 2>/dev/null | grep -qi 'Connected'; then
    sketchybar --set "$NAME" icon="$ICON_VPN_ON" icon.color=$GREEN label="VPN" label.color=$GREEN
else
    sketchybar --set "$NAME" icon="$ICON_VPN_OFF" icon.color=$RED label="VPN" label.color=$RED
fi
P_VPN

    write_managed_script "$SBAR_PLUGINS/vpn_toggle.sh" <<'P_VPNT'
#!/usr/bin/env bash
command -v mullvad >/dev/null 2>&1 || exit 0
if mullvad status 2>/dev/null | grep -qi 'Connected'; then mullvad disconnect; else mullvad connect; fi
P_VPNT

    write_managed_script "$SBAR_PLUGINS/shottr_click.sh" <<'P_SHOTC'
#!/usr/bin/env bash
# Left-click toggles the capture menu; right-click is a quick area grab.
if [ "$BUTTON" = "right" ]; then
    open "shottr://grab/area"
    sketchybar --set shottr popup.drawing=off
else
    sketchybar --set shottr popup.drawing=toggle
fi
P_SHOTC

    write_managed_script "$SBAR_PLUGINS/shottr.sh" <<'P_SHOT'
#!/usr/bin/env bash
# Close the capture menu when the pointer leaves the item and its popup.
[ "$SENDER" = "mouse.exited.global" ] && sketchybar --set shottr popup.drawing=off
P_SHOT

    if [[ "$DRY_RUN" != "true" ]] && installed sketchybar; then
        brew services restart sketchybar >> "$LOG_FILE" 2>&1 || warn "Could not start sketchybar service (grant it Accessibility if needed)"
    fi
    success "SketchyBar configured (Dracula, system widgets)"

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
# herald self-configures through its own onboarding (accounts, calendars, themes) —
# there is no hand-written config here. Complete setup from the POST_SETUP checklist:
#   herald                                      # first run: add Gmail + iCloud, CalDAV
#   herald serve -config ~/.herald/conf.yaml    # background server (MCP mutations need it)
# The herald MCP server is registered for Claude in the MCP section below.

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
    success "direnv configured (hidden env diff, auto-trust ~/Code)"

# Set RIPGREP_CONFIG_PATH in zshrc (needed for ripgrep to read config)
# This will be in the managed block below

fi  # configs (end of second configs segment)

# ---- Filesystem Structure ----
# Top-level category (NOT nested in configs) so --only filesystem works.
if should_run "filesystem"; then
info "Setting up filesystem structure..."
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would create the ~ directory tree, helper scripts, and Brewfile"
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
    "$HOME/Documents/notes"      # tiki notes/tasks repo (git-backed; git-initialized below)

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

# Git-init the tiki notes repo so it's ready as a git-backed workspace (idempotent).
if installed git && [[ ! -d "$HOME/Documents/notes/.git" ]]; then
    if git init -q "$HOME/Documents/notes" >> "$LOG_FILE" 2>&1; then
        success "Initialized tiki notes repo at ~/Documents/notes (git-backed)"
    else
        warn "Could not git init ~/Documents/notes"
    fi
fi

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
# Scaffold a new project with git, .editorconfig, .gitignore
# Usage: new-project <name> [work|personal|oss|learning]
set -euo pipefail

NAME="${1:-}"
CONTEXT="${2:-personal}"

if [[ -z "$NAME" ]]; then
    echo "Usage: new-project <name> [work|personal|oss|learning]"
    echo "  Contexts: work, personal, oss, learning"
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

PROJECT_DIR="$BASE/$NAME"

if [[ -d "$PROJECT_DIR" ]]; then
    echo "Project already exists: $PROJECT_DIR"
    exit 1
fi

echo "Creating project: $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Initialize git
git init -b main

# Copy global .editorconfig if it exists
if [[ -f "$HOME/.editorconfig" ]]; then
    cp "$HOME/.editorconfig" .editorconfig
fi

# Create .gitignore
cat > .gitignore <<'GITIGNORE'
# Dependencies
node_modules/
.pnpm-store/

# Build
dist/
build/
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/settings.json
.idea/

# OS
.DS_Store
Thumbs.db

# Test & Coverage
coverage/
.nyc_output/

# Logs
*.log
npm-debug.log*
GITIGNORE

# Create README
cat > README.md <<README
# $NAME

## Getting Started

\`\`\`bash
# Install dependencies
pnpm install

# Start development
pnpm dev
\`\`\`
README

# Create AGENTS.md — the PUBLIC agent instructions. This is tracked: it is written
# for whoever contributes, not for you. Personal preferences and private notes go in
# CLAUDE.md, which is gitignored below and never committed.
mkdir -p .claude
cat > AGENTS.md <<AGENTSMD
# Notes for coding agents — $NAME

If you're an AI assistant working in this repository, start here. Keep this file short and
free of personal preference: point at the documents that already exist rather than
restating them.

## Overview
<!-- What this project does, in two or three sentences -->

## Tech Stack
<!-- Languages, frameworks, key libraries -->

## Read these first
<!-- | File | What it settles | -->
<!-- |---|---| -->
<!-- | \`README.md\` | Setup and usage | -->

## Development
- Install: \`pnpm install\`
- Dev: \`pnpm dev\`
- Test: \`pnpm test\`
- Build: \`pnpm build\`

## The things most likely to trip you
<!-- Repo-specific traps: silent failures, things that look wrong but aren't -->

## Before you commit
<!-- The command that must pass. Never commit to main — branch, then open a PR. -->
AGENTSMD

# CLAUDE.md is private: personal preferences, lessons, anything not for the public.
# It is in the global gitignore too, but the per-repo line makes the rule visible to
# anyone reading the repo.
if ! grep -qxF 'CLAUDE.md' .gitignore 2>/dev/null; then
    printf '\n# Private agent notes (personal; see AGENTS.md for the public ones)\nCLAUDE.md\n' >> .gitignore
fi

# Create GitHub PR template
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

# Initial commit
git add -A
git commit -m "Initial project scaffold"

echo ""
echo "Project created at: $PROJECT_DIR"
echo "  cd $PROJECT_DIR"
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

# -- git-lfs-enable-repo: opt one repository into Git LFS hooks --
write_managed_script "$HOME/Scripts/bin/git-lfs-enable-repo" <<'SCRIPT'
#!/usr/bin/env bash
# Enable Git LFS hooks for THIS repository only.
# Usage: git-lfs-enable-repo [path-to-repo]
#
# `git lfs install` cannot do this job on a machine with core.hooksPath set: git-lfs
# is core.hooksPath aware, so it writes its hooks to the GLOBAL directory even when
# asked for --local, which would put them back on every push in every repo (#311).
# This writes them to .git/hooks instead, where the global delegator runs them as the
# repository's own hook.
set -euo pipefail

cd "${1:-.}"
command -v git-lfs >/dev/null 2>&1 || { echo "git-lfs is not installed." >&2; exit 1; }

GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
HOOKS="$GIT_DIR/hooks"
mkdir -p "$HOOKS"

for hook in pre-push post-checkout post-commit post-merge; do
    target="$HOOKS/$hook"
    if [ -e "$target" ] && ! grep -q "git lfs $hook" "$target" 2>/dev/null; then
        echo "Refusing to overwrite existing hook: $target" >&2
        echo "Merge 'git lfs $hook \"\$@\"' into it by hand." >&2
        continue
    fi
    cat > "$target" <<HOOK
#!/bin/sh
command -v git-lfs >/dev/null 2>&1 || {
    printf >&2 '\n%s\n\n' "This repository is configured for Git LFS but 'git-lfs' was not found on your path."
    exit 2
}
git lfs $hook "\$@"
HOOK
    chmod +x "$target"
done

git lfs install --local --skip-repo >/dev/null 2>&1 || true
echo "Git LFS hooks enabled for $(basename "$PWD") (.git/hooks)."
echo "Track files with: git lfs track '*.psd'"
SCRIPT

# (write_managed_script sets +x on each script; no blanket chmod needed.)
success "Helper scripts written (clean-downloads, new-project, clone-work, clone-personal, backup-dotfiles, project-stats, health-check, setup-ssh, export-brewfile, git-lfs-enable-repo — merged, edits outside the markers are kept)"

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
    git config --global "includeIf.gitdir:~/Code/work/.path" "$GITCONFIG_WORK"
    success "git includeIf registered for ~/Code/work/ -> ~/.gitconfig-work"
else
    warn "git includeIf for ~/Code/work/ already set"
fi

if ! git config --global --get "includeIf.gitdir:~/Code/personal/.path" &>/dev/null; then
    git config --global "includeIf.gitdir:~/Code/personal/.path" "$GITCONFIG_PERSONAL"
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
sudo chflags nohidden /Volumes 2>/dev/null || true

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Restart Finder to apply changes
killall Finder 2>/dev/null || true

success "Finder configured (hidden files visible, list view, path bar, no .DS_Store on network)"

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
            success "Finder sidebar updated ($sidebar_added folders added)"
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
        sudo bash -c 'cat > /etc/pam.d/sudo_local <<EOF
# sudo_local: local config for sudo (survives macOS updates)
auth       sufficient     pam_tid.so
EOF'
        success "Touch ID for sudo enabled (use fingerprint instead of password)"
    else
        sudo bash -c 'echo "auth       sufficient     pam_tid.so" >> /etc/pam.d/sudo_local'
        success "Touch ID for sudo enabled"
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
            sudo networksetup -setdnsservers "$service" 1.1.1.1 1.0.0.1 9.9.9.9 8.8.8.8
            DNS_SET=true
        fi
    fi
done <<< "$NETWORK_SERVICES"
if [[ "$DNS_SET" == "true" ]]; then
    # Flush DNS cache
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    success "DNS set to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) + Google (8.8.8.8)"
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
success "Spotlight exclusions set (node_modules, caches via .metadata_never_index)"

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
    success "Time Machine exclusions set (node_modules, Docker, caches, Downloads)"
fi

# ---- Disable Siri ----
if defaults read com.apple.assistant.support "Assistant Enabled" 2>/dev/null | grep -q "1"; then
    info "Disabling Siri..."
    defaults write com.apple.assistant.support "Assistant Enabled" -bool false
    defaults write com.apple.Siri StatusMenuVisible -bool false
    defaults write com.apple.Siri UserHasDeclinedEnable -bool true
    success "Siri disabled and removed from menubar"
else
    warn "Siri already disabled"
fi

# ---- Trackpad: Disable three-finger drag ----
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false 2>/dev/null || true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false 2>/dev/null || true
# Also disable via Accessibility (required on newer macOS)
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false 2>/dev/null || true
success "Three-finger drag disabled"

# ---- Trackpad/mouse: disable natural scrolling and force click ----
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false 2>/dev/null || true
defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false 2>/dev/null || true
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true 2>/dev/null || true
success "Natural scrolling and force click disabled"

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
success "Trackpad preferences captured (tap-to-click off, two-finger secondary click, gestures)"

# ---- Screen dim when idle: 30 minutes ----
sudo pmset -a halfdim 1 2>/dev/null || true
sudo pmset -c dim 30 2>/dev/null || true
sudo pmset -b dim 30 2>/dev/null || true
success "Screen dim set to 30 min"

# ---- Disable startup sound ----
sudo nvram StartupMute=%01 2>/dev/null || true
success "Startup sound disabled"

# ---- Reduce transparency (slight performance boost, easier to read) ----
defaults write com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
success "Transparency reduced"

# ---- Show Bluetooth in menu bar ----
defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool true 2>/dev/null || true
success "Bluetooth shown in menu bar"

# ---- Auto-set timezone ----
sudo systemsetup -setusingnetworktime on 2>/dev/null || true
# Use current timezone (don't override user's existing setting)
# sudo systemsetup -settimezone "America/Chicago" 2>/dev/null || true
success "Network time enabled (timezone auto-detected)"

# ---- Software Update: auto-check but don't auto-install ----
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false 2>/dev/null || true
defaults write com.apple.commerce AutoUpdate -bool false 2>/dev/null || true
success "Software Update configured (auto-check, no auto-install)"

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
# CLAUDE CODE CONFIGURATION
# =============================================================================
banner "Claude Code Configuration"

# ---- Claude Code global settings ----
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # MERGE into an existing settings.json (preserves your own keys), and SECURITY-HARDEN
    # the allowlist: add safe read-only entries + scoped git reads, and STRIP the
    # dangerous auto-approvals (interpreters, network, cloud/infra mutation, secret
    # reveal, broad git/gh, file destruction, unrestricted Write) so old machines get
    # cleaned too. Note: re-runs re-strip these — re-add any you truly want by editing
    # the CLAUDE_DENY_ALLOW list below, not settings.json.
    #
    # This branch also MIGRATES three defects written by older versions of this script
    # (see #206), since machines provisioned before the fix never re-run the create
    # heredoc below:
    #   1. PostToolUse entries shaped {matcher, command} — schema-invalid, so the hooks
    #      silently never ran. Normalized to {matcher, hooks:[{type,command}]}.
    #   2. A "fileSuggestionSettings" key that Claude Code does not implement (ignored
    #      outright) — dropped; ~/.ignore below replaces it.
    #   3. A Linux-flavoured deny list (/dev/sda, mkfs) on a macOS-only target.
    CLAUDE_ADD_ALLOW='["Bash(qalc *)","Bash(has *)","Bash(doxx *)","Bash(mdfind *)","Bash(atac *)","Bash(leaf *)","Bash(manly *)","Bash(soffice *)","Bash(office-py *)","Bash(pdftoppm *)","Bash(pdftotext *)","Bash(pdfinfo *)","Bash(tiki exec *)","Bash(reminders show*)","Bash(git status *)","Bash(git diff *)","Bash(git log *)","Bash(git show *)","Bash(git branch *)","Bash(git remote -v)","Bash(git stash list)"]'
    CLAUDE_DENY_ALLOW='["Bash(npm *)","Bash(npx *)","Bash(pnpm *)","Bash(bun *)","Bash(node *)","Bash(tsx *)","Bash(ts-node *)","Bash(python3 *)","Bash(pip *)","Bash(uv *)","Bash(uvx *)","Bash(cargo *)","Bash(go *)","Bash(just *)","Bash(make *)","Bash(nu *)","Bash(nushell *)","Bash(topgrade *)","Bash(watchexec *)","Bash(viddy *)","Bash(parallel *)","Bash(act *)","Bash(curl *)","Bash(xh *)","Bash(wget *)","Bash(curlie *)","Bash(aria2c *)","Bash(grpcurl *)","Bash(yt-dlp *)","Bash(aws *)","Bash(cdk *)","Bash(sam *)","Bash(docker *)","Bash(docker-compose *)","Bash(docker compose *)","Bash(kubectl *)","Bash(tofu *)","Bash(s5cmd *)","Bash(dynein *)","Bash(steampipe *)","Bash(iamlive *)","Bash(granted *)","Bash(assume *)","Bash(mitmproxy *)","Bash(mitmdump *)","Bash(nmap *)","Bash(chezmoi *)","Bash(dbmate *)","Bash(env *)","Bash(export *)","Bash(git *)","Bash(git-*)","Bash(gh *)","Bash(glab *)","Bash(cp *)","Bash(mv *)","Bash(trash *)","Bash(sd *)","Bash(sed *)","Bash(awk *)","Bash(find *)","Bash(npkill *)","Bash(ouch *)","Bash(7z *)","Write"]'
    # Allowlist entries that are dead rather than dangerous: renamed binaries or rules
    # already covered by a broader prefix. Stripped on re-run so they don't accumulate.
    CLAUDE_STALE_ALLOW='["Bash(trippy *)","Bash(wc -l *)"]'
    # Deny rules retargeted from Linux to macOS, plus the common rm spellings the
    # original literal-prefix rules missed. These are fat-finger guardrails, NOT a
    # security boundary — permission rules match literally, so variants still pass.
    CLAUDE_ADD_DENY='["Bash(rm -rf /)","Bash(rm -fr /)","Bash(rm -rf /*)","Bash(rm -fr /*)","Bash(rm -rf ~)","Bash(rm -fr ~)","Bash(rm -rf ~/*)","Bash(rm -fr ~/*)","Bash(sudo rm *)","Bash(chmod 777 *)","Bash(> /dev/disk*)","Bash(dd of=/dev/disk*)","Bash(diskutil erase*)","Bash(diskutil partitionDisk*)","Bash(newfs_*)"]'
    CLAUDE_DROP_DENY='["Bash(> /dev/sda*)","Bash(mkfs *)"]'
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would merge settings.json: add safe allow entries + statusline, strip dangerous ones, migrate legacy hooks shape"
    elif command -v jq &>/dev/null; then
        info "Merging + hardening Claude settings.json permissions..."
        CLAUDE_TMP=$(mktemp)
        if jq --argjson add "$CLAUDE_ADD_ALLOW" --argjson deny "$CLAUDE_DENY_ALLOW" \
               --argjson stale "$CLAUDE_STALE_ALLOW" \
               --argjson adddeny "$CLAUDE_ADD_DENY" --argjson dropdeny "$CLAUDE_DROP_DENY" \
            'def normalize_hook:
               if (type == "object") and (has("hooks") | not) and has("command")
               then {matcher: (.matcher // ""), hooks: [{type: "command", command: .command}]}
               else . end;
             .permissions.allow = (((.permissions.allow // []) + $add) - $deny - $stale | unique)
             | .permissions.deny = (((.permissions.deny // []) + $adddeny) - $dropdeny | unique)
             | .statusLine = (.statusLine // {"type":"command","command":"~/.claude/statusline.sh"})
             | del(.fileSuggestionSettings)
             | if (.hooks? | type) == "object"
               then .hooks |= with_entries(.value |= (if type == "array" then map(normalize_hook) else . end))
               else . end' \
            "$CLAUDE_SETTINGS" > "$CLAUDE_TMP" 2>/dev/null; then
            mv "$CLAUDE_TMP" "$CLAUDE_SETTINGS"
            success "Claude settings.json hardened + migrated (allowlist, macOS deny rules, PostToolUse hooks shape)"
        else
            rm -f "$CLAUDE_TMP"
            warn "Could not merge settings.json — add the new Bash(...) allow entries + statusLine manually"
        fi
    else
        warn "Claude settings.json exists but jq is missing — can't auto-merge the new entries"
    fi
else
    info "Creating Claude Code global settings..."
    cat > "$CLAUDE_SETTINGS" <<'CLAUDE_SETTINGS_CONF'
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(npm install *)",
      "Bash(npm test *)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git show *)",
      "Bash(git branch *)",
      "Bash(git remote -v)",
      "Bash(git stash list)",
      "Bash(k9s *)",
      "Bash(stern *)",
      "Bash(cat *)",
      "Bash(bat *)",
      "Bash(ls *)",
      "Bash(eza *)",
      "Bash(grep *)",
      "Bash(rg *)",
      "Bash(fd *)",
      "Bash(fzf *)",
      "Bash(tree *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(sort *)",
      "Bash(uniq *)",
      "Bash(cut *)",
      "Bash(jq *)",
      "Bash(yq *)",
      "Bash(fx *)",
      "Bash(mlr *)",
      "Bash(csvlook *)",
      "Bash(which *)",
      "Bash(type *)",
      "Bash(echo *)",
      "Bash(printf *)",
      "Bash(cd *)",
      "Bash(mkdir -p *)",
      "Bash(touch *)",
      "Bash(diff *)",
      "Bash(difft *)",
      "Bash(delta *)",
      "Bash(scc *)",
      "Bash(dust *)",
      "Bash(du -sh *)",
      "Bash(date *)",
      "Bash(pwd)",
      "Bash(shellcheck *)",
      "Bash(shfmt *)",
      "Bash(prettier *)",
      "Bash(eslint *)",
      "Bash(ruff *)",
      "Bash(hadolint *)",
      "Bash(tsc *)",
      "Bash(jest *)",
      "Bash(vitest *)",
      "Bash(tflint *)",
      "Bash(terraform-docs *)",
      "Bash(checkov *)",
      "Bash(infracost *)",
      "Bash(trivy *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)",
      "Bash(cosign *)",
      "Bash(hyperfine *)",
      "Bash(oha *)",
      "Bash(pandoc *)",
      "Bash(manly *)",
      "Bash(soffice *)",
      "Bash(office-py *)",
      "Bash(tiki exec *)",
      "Bash(reminders show*)",
      "Bash(pdftoppm *)",
      "Bash(pdftotext *)",
      "Bash(pdfinfo *)",
      "Bash(d2 *)",
      "Bash(mmdc *)",
      "Bash(ffmpeg *)",
      "Bash(magick *)",
      "Bash(lazygit *)",
      "Bash(lazydocker *)",
      "Bash(dive *)",
      "Bash(pgcli *)",
      "Bash(mycli *)",
      "Bash(sq *)",
      "Bash(commitizen *)",
      "Bash(commitlint *)",
      "Bash(typos *)",
      "Bash(ast-grep *)",
      "Bash(git-cliff *)",
      "Bash(hurl *)",
      "Bash(atac *)",
      "Bash(jnv *)",
      "Bash(lazysql *)",
      "Bash(trip *)",
      "Bash(oxipng *)",
      "Bash(jpegoptim *)",
      "Bash(mpv *)",
      "Bash(newsboat *)",
      "Bash(zellij *)",
      "Bash(gum *)",
      "Bash(llm *)",
      "Bash(dockutil *)",
      "Bash(terminal-notifier *)",
      "Bash(harlequin *)",
      "Bash(hq *)",
      "Bash(git-absorb *)",
      "Bash(act3 *)",
      "Bash(mkcert *)",
      "Bash(bandwhich *)",
      "Bash(gping *)",
      "Bash(doggo *)",
      "Bash(procs *)",
      "Bash(btop *)",
      "Bash(lnav *)",
      "Bash(leaf *)",
      "Bash(fastfetch *)",
      "Bash(qalc *)",
      "Bash(has *)",
      "Bash(doxx *)",
      "Bash(mdfind *)",
      "Read",
      "Edit",
      "WebFetch"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -fr /)",
      "Bash(rm -rf /*)",
      "Bash(rm -fr /*)",
      "Bash(rm -rf ~)",
      "Bash(rm -fr ~)",
      "Bash(rm -rf ~/*)",
      "Bash(rm -fr ~/*)",
      "Bash(sudo rm *)",
      "Bash(chmod 777 *)",
      "Bash(> /dev/disk*)",
      "Bash(dd of=/dev/disk*)",
      "Bash(diskutil erase*)",
      "Bash(diskutil partitionDisk*)",
      "Bash(newfs_*)"
    ]
  },

  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/format-on-edit.sh"
          },
          {
            "type": "command",
            "command": "~/.claude/hooks/lint-python.sh"
          },
          {
            "type": "command",
            "command": "~/.claude/hooks/lint-dockerfile.sh"
          }
        ]
      }
    ]
  },

  "env": {
    "DISABLE_PROMPT_CACHING": "0"
  },

  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
CLAUDE_SETTINGS_CONF
    success "Claude Code settings.json created (permissions, statusline)"
fi

# ---- Global ~/.ignore (replaces the non-existent fileSuggestionSettings key) ----
# Claude Code honours .ignore files and, via respectGitignore (default true), each
# repo's .gitignore. So build/dependency dirs — node_modules, dist, .venv, cdk.out —
# are already filtered out of @ file-suggestions by .gitignore. What .gitignore can
# never hide is the noise that is deliberately COMMITTED: lock files, minified
# bundles, sourcemaps. Those go here. Note this also applies to ripgrep searches run
# under $HOME, which is usually desirable but is a real side effect.
CLAUDE_IGNORE="$HOME/.ignore"
    info "Creating global .ignore (Claude Code @ suggestions + ripgrep)..."
    write_managed "$CLAUDE_IGNORE" "#" <<'CLAUDE_IGNORE_CONF'
package-lock.json
pnpm-lock.yaml
yarn.lock
bun.lockb
Cargo.lock
go.sum
uv.lock
poetry.lock
*.min.js
*.min.css
*.map
CLAUDE_IGNORE_CONF
    success "Global .ignore created (lock files + minified bundles hidden from @ suggestions)"

# ---- Claude Code global CLAUDE.md (memory/instructions) ----
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
# REFRESHED on every run, not create-once. This file used to be written only when
# absent, which meant a machine provisioned once never received another correction:
# the maintainer's copy had drifted 33 lines and still named eight tools the script
# had removed (aider, repomix, kew, aerc, khal, tmux, snyk, trippy). That drift is
# actively harmful — it is what Claude reads as ground truth about this machine, and
# it sent one audit chasing "stale" references that had already been fixed here.
# write_managed refreshes the block in place and keeps anything outside the markers;
# a pre-existing unmarked file is backed up to *.pre-managed.<timestamp> first.
info "Writing Claude Code global CLAUDE.md..."
write_managed "$CLAUDE_MD" "#" <<'CLAUDE_MD_CONF'
# Global Development Standards

## Workflow Philosophy
- **Trunk-based development** — short-lived feature branches off main, merge back fast
- **PRs over direct commits** — every change goes through a pull request, no direct pushes to main
- **Issues for everything** — create GitHub issues before starting work, reference in PRs
- **README-driven development** — every project and significant module gets a README
- **Industry best practices** — follow established patterns, OWASP, 12-factor, SOLID, DRY

## Agent instructions in a repo: public `AGENTS.md`, private `CLAUDE.md`
Two files, two audiences. Keep them separate in every repository.

- **`AGENTS.md` — tracked, public, for anyone's agent.** Short. It points at the documents that
  already exist (`CONTRIBUTING.md`, `docs/*`) rather than restating them, and names the traps
  specific to that repo. Read it first in any repo that has one. Claude Code discovers it the
  same way it discovers `CLAUDE.md`, and other agents read it too, so it is the file a
  contributor's tooling will find.
- **`CLAUDE.md` — untracked, private, mine.** Personal preferences, lessons, and anything not
  relevant to the public. It is in the global gitignore, so it will not appear in `git status`.

Rules that follow from this:

- **Never commit `CLAUDE.md`.** If a repo needs it tracked (rare — this setup's own repo used to),
  that is a deliberate `git add -f`, not an accident.
- **Never put personal preferences in `AGENTS.md`.** It is written for someone else's contributor,
  who has their own way of working. Describe the repo, not the maintainer.
- When asked to "write the agent instructions" for a public repo, that means `AGENTS.md`. Offer a
  private `CLAUDE.md` separately if there is anything personal to record.
- `~/Code/personal/qud-mods/qud-expanded/AGENTS.md` is the reference for the shape: purpose line,
  a table of *file → what it settles*, a short list of traps, the pre-commit command.

## This machine's config is GENERATED — edit the generator, not the output
- `~/.zshrc`, `~/.claude/` (this file, `rules/`, `agents/`, `commands/`, `hooks/`, `settings.json`), `~/.config/*` and the Desktop docs are all written by **`~/Code/personal/vixygrey-dev-setup-main/scripts/setup-dev-tools-mac.sh`**, and refreshed on every run.
- **Never hand-edit those files to make a change stick** — anything between the `>>> dev-setup managed block` markers is overwritten on the next run. Edit the matching heredoc in that script instead, then re-run it. A direct edit is fine as a temporary local patch, but say so explicitly, because it will be reverted.
- Edits *outside* the markers survive, as does `settings.json` (merged with `jq`, not replaced — your own permission rules are kept).
- The script is the source of truth for what is installed. Before recommending a tool, check it is actually present (`command -v <tool>`) — and note the **binary name often differs from the package name** (`trippy`→`trip`, `nushell`→`nu`, `dynein`→`dy`, `imagemagick`→`magick`, `aws-sam-cli`→`sam`, `csvkit`→`csvlook`/`in2csv`).

## Environment
- Shell: zsh with starship prompt, atuin history, fzf fuzzy finder, zsh-autosuggestions, zsh-syntax-highlighting
- Editor / IDE: **croft** is the primary editor (VS Code-style terminal IDE — `croft` to open a workspace, `croft pair` for the AI navigator). **Visual Studio Code** is installed as the **GUI** editor for when a TUI is the wrong tool (`code .`) — secondary to croft, not a replacement; it carries the same rules via extensions (Dracula, ruff, **basedpyright** — the same Python type server croft uses, never Microsoft's proprietary Pylance, which the setup removes — prettier, ESLint, shellcheck/shfmt, EditorConfig) so it cannot disagree with the CLI. **micro** is the `EDITOR` for git/gh/lazygit commit messages and quick edits — non-modal, Dracula, with an on-screen key menu (`Ctrl+G` for full help). Helix was retired in 7.6.0. Agentic coding via Claude Code (`claude`) — see **AI / agentic** below.
- **croft does not support EditorConfig** (verified in croft 0.1.700 — no reference anywhere in its source). Its indentation is a language default (2 spaces for YAML, 4 otherwise) plus a per-buffer status-bar override that does not persist. VS Code *does* honour `.editorconfig`, so on a repo with one, the two editors will disagree unless you flip croft's status-bar pill. Croft's extensions are declarative `extension.toml` manifests (languages, LSP servers, themes, debug adapters, test runners, MCP sidecars) under `~/.config/croft/extensions/` — pure data, no code, no marketplace, so an EditorConfig reader cannot be added as one.
- Terminal: Ghostty (Dracula theme)
- Package managers: pnpm (preferred), npm, bun
- Python: uv for packages (not pip), ruff for linting (not flake8/black)
- JS/TS runtimes: Node (via mise), Bun, Deno
- Version manager: mise (Node, Python, Go, Ruby — all in one)
- Container runtime: OrbStack (provides docker + kubectl)
- Task runner: just (prefer over make for project-level tasks)
- Shell note: `bat` is aliased to `cat`; use `/bin/cat` only inside heredoc subshells where bat breaks syntax
- Dotfiles: chezmoi
- Launcher: Ghostty quick terminal (global cmd+space) + shell functions `a` (app launcher), `ff`/`rgf`/`s` (file/content/Spotlight search). Window mgmt: native macOS Spaces + built-in window tiling (no tiling WM). Bar: SketchyBar. Clipboard: clipse (`clip`)
- API testing/exploration → **use ATAC** (terminal — scriptable CLI + TUI; JSON/YAML collections, Postman import; allow-listed) for anything collection-based or repeatable; reach for `hurl` / `xh` / `curlie` / `grpcurl` for quick one-offs
- Database: pgcli, mycli, lazysql, harlequin (SQL IDE TUI), usql, sq; migrations via dbmate
- Diagrams: d2 / Mermaid (code-based, in the terminal)
- Screenshots → Shottr saves them to **~/Screenshots**. When the user mentions "a screenshot" without a path, read the newest file in ~/Screenshots (`ls -t ~/Screenshots | head`) rather than asking where it is
- File transfer: rclone (CLI — SFTP/S3/cloud)
- Proxy/debugger: mitmproxy
- Tunneling: ngrok
- Notes, tasks & project boards → **use tiki** (git-backed Markdown workspace), not ad-hoc scratch files, for anything worth keeping. The `tiki` **skill is installed** (~/.claude/skills/tiki) — use it: CRUD via `tiki exec '<ruki>'` (SQL-like; auto-validates + git-stages), quick-capture via `echo "note" | tiki` (first line = title). Tikis live in the cwd as Markdown. Personal (non-project) notes/tasks go in **~/Documents/notes** (a git repo) — cd there for general notes; for project-specific tasks, use the project's cwd.
- Email & calendar: **herald** (one terminal app for both — Gmail work + iCloud personal, unified CalDAV calendar, built-in AI triage/summaries). Herald exposes an **MCP server** (registered in Claude Code) — prefer its MCP tools for reading/searching mail and calendar. **Never send, reply, delete, archive, or modify mail or events without explicit user confirmation** (mutations also require `herald serve` running).
- Reminders → **use `reminders`** (reminders-cli) for anything that should fire as an alert on the user's iPhone/Watch via iCloud. This is the deciding line between three neighbours: **tiki** holds notes/tasks worth keeping in git, **herald** owns mail and calendar *events*, and **`reminders`** owns time- and location-triggered *alerts*. When the user says "remind me", that is this tool — do not write it into a scratch file or a tiki task and call it done. Read freely (`reminders show-lists`, `reminders show <list>`); creating, completing, or deleting a reminder changes state on every synced device, so **do that only when the user actually asked for it**, and echo back what you created. Common forms: `reminders add <list> "<text>" --due-date "tomorrow 9am"`, `reminders complete <list> <index>`. First run triggers a one-time macOS Reminders permission prompt.
- Cloud storage: rclone (Google Drive, S3, Dropbox, etc.); borg for versioned backups
- Browser: Google Chrome (primary); Carbonyl / w3m in the terminal
- Credentials → **never read, type, enter, or exfiltrate passwords, tokens, API keys, or secrets**, and never echo them into a terminal. Auth is handled by Apple Passwords (iCloud Keychain) and the OS credential tools; defer to the user for anything that needs a credential (no third-party password manager is installed)

## Working Context
- Independent **fractional CIO/CTO and consultant**; company is **VixenTec LLC**.
- All company work runs on **Google Workspace** (Gmail, Docs/Sheets/Slides, Drive, Meet, Chat, Vids). Produce documents/deliverables in Google Workspace, not a local office suite — **author** in Workspace, not MS Office. LibreOffice is installed **only** for headless **validation/conversion** of office files (`soffice --headless --convert-to …`), e.g. checking a `.pptx`/`.xlsx`/`.docx` opens cleanly or rendering it to PDF — not for authoring. Use **Google Meet** for calls (no Zoom); **Google Chat** for messaging (no Slack).
- To work with Workspace from the terminal, use **`gws`** (google-workspace-cli — Drive/Gmail/Docs/Sheets/Calendar/Chat with structured JSON output; run `gws auth login` first). **Read/list/search/get freely**; but **never send, reply, share, move, delete, or modify** mail, files, or events **without explicit user confirmation** — state exactly what will change first.
- **gws Claude skills you have (pre-installed in `~/.claude/skills/`)** — a scoped set covering **Drive, Docs, Slides, Sheets, and Forms only**; Gmail/Calendar/Chat/Meet/Tasks/Contacts skills were deliberately left out. Prefer these skills over hand-rolling `gws` invocations:
  - **Service skills**: `gws-shared` (auth/flags/output — the base), `gws-drive`, `gws-drive-upload`, `gws-docs`, `gws-docs-write`, `gws-sheets`, `gws-sheets-read`, `gws-sheets-append`, `gws-slides`, `gws-forms`.
  - **Recipes** (canned multi-step workflows): Drive — `recipe-bulk-download-folder`, `recipe-find-large-files`, `recipe-organize-drive-folder`, `recipe-create-shared-drive`, `recipe-share-folder-with-team`; Docs — `recipe-create-doc-from-template`; Slides — `recipe-create-presentation`; Sheets — `recipe-backup-sheet-as-csv`, `recipe-compare-sheet-tabs`, `recipe-copy-sheet-for-new-month`, `recipe-create-expense-tracker`, `recipe-generate-report-from-sheet`, `recipe-log-deal-update`; Forms — `recipe-collect-form-responses`.
  - Skills are recipes, **not** an access boundary: having only these does not stop `gws` from reaching Gmail/Calendar if those OAuth scopes were granted. The fence is the scopes chosen at `gws auth setup` — treat email/calendar/chat as out of scope unless the user says otherwise.
- Tool philosophy: prefer **open-source, CLI-first, privacy-preserving, and minimal** options; declutter aggressively. When recommending tools, lead with one option that fits these and flag any that don't.
- **ADD-friendly home layout** (low-decision, shallow): `~/Inbox` (dump zone — drop anything, sort later), `~/Code` (work/personal/oss/learning), `~/Documents` (finance, health, admin, receipts, travel), `~/Creative`, `~/Media`, `~/Archive`, `~/Screenshots`, `~/Scripts`. When in doubt where a file goes, suggest `~/Inbox` rather than a deep path.

## Available CLI Tools (use these instead of manual approaches)
- **Search**: `rg` (ripgrep) for content, `fd` for files, `fzf` for interactive, `mdfind` for Spotlight/metadata search (filename, tags, content across the disk)
- **Data**: `jq` for JSON, `yq` for YAML, `mlr` for CSV, `fx`/`jnv` for interactive JSON, `csvlook`/`in2csv`/`csvjson` for CSV (the csvkit suite)
- **Git**: `lazygit` for interactive UI, `delta` for diffs, `difft` for syntax-aware diffs, `git-cliff` for changelogs, `git-absorb` for auto fixup commits, `git-lfs` for large files
- **Docker**: `lazydocker` for UI, `dive` to inspect layers, `hadolint` for Dockerfile linting
- **Testing**: `hyperfine` to benchmark, `oha` for load testing, `hurl` for HTTP test files, `act` for local GitHub Actions
- **Code quality**: `typos` for spell checking, `ast-grep` for structural search/replace, `shellcheck`/`shfmt` for shell, `scc` to count lines of code by language with complexity + COCOMO cost, `manly` to explain a command's flags from its man page
- **Security**: `trivy` to scan containers/IaC, `gitleaks` for secrets, `semgrep` for static analysis, `detect-secrets` for pre-commit secret detection, `sops` for secrets encryption
- **IaC**: `tofu` (Terraform), `tflint` for linting, `terraform-docs` for module READMEs, `checkov` for static analysis, `infracost` for cost estimation, `cfn-lint` for CloudFormation, `sam` for SAM (note: `tfsec` checks live in `trivy config`)
- **AI / agentic**: `claude` (Claude Code) is the coding agent — do agentic, multi-file edits yourself. `llm` for one-shot prompts and embeddings. `copilot` (GitHub Copilot CLI) is available too.
- **HTTP**: `xh` for colorized requests, `curlie` for curl with httpie output, `grpcurl` for gRPC
- **Network**: `trip` (trippy) for traceroute TUI, `sudo mtr` (requires root, lives in sbin), `bandwhich` for bandwidth, `nmap` for scanning, `mkcert` for local TLS certs
- **Docs**: `d2` for diagrams, `pandoc` for conversion, `leaf` for Markdown preview, `doxx` to read/preview `.docx` files in the terminal
- **Office files** (.pptx/.xlsx/.docx) — three complementary tools:
  - **Render**: `soffice --headless --convert-to pdf --outdir /tmp file.pptx` (LibreOffice) — the fidelity renderer
  - **See it**: `pdftoppm -png -r 150 /tmp/file.pdf /tmp/page` (poppler) rasterizes the PDF to PNGs you can inspect (this is the PDF→image tool — `magick` needs ghostscript for PDFs and is for editing the resulting images: resize/crop/composite); `pdftotext`/`pdfinfo` for text/metadata
  - **Assert on content**: `office-py` (a venv with python-docx/openpyxl/python-pptx), e.g. `office-py -c 'from pptx import Presentation; p=Presentation("deck.pptx"); print(len(p.slides))'`
  - **Skills**: the `office-docs` skill wraps this render→see→assert loop into one recipe; Claude Code's **bundled** `docx`/`pptx`/`xlsx`/`pdf` skills author & edit local files with the same libraries (preview results via the render step above). Local files only — cloud Google Docs/Sheets/Slides use `gws`.
- **Database**: `pgcli`/`mycli` for auto-completing SQL, `lazysql` for TUI, `sq` for cross-database queries, `dbmate` for migrations
- **File management**: `rovr` for the TUI file manager (`nnn` as a minimal fallback), `wiper` for interactive disk-usage cleanup (ncdu-like, Trash-safe), `watchexec` for running commands on file changes, `rclone` for cloud storage sync
- **Kubernetes**: `k9s` for TUI, `stern` for log tailing (kubectl via OrbStack)
- **AWS**: `granted`/`assume` for role switching; TUIs `e1s` (ECS), `stu` (S3), `e2c` (EC2), `claws` (broad, k9s-style); `steampipe` for SQL over AWS, `s5cmd` for fast S3 bulk ops, `dy` for DynamoDB (dynein), `iamlive` to generate least-privilege IAM from observed calls
- **Shell scripting**: `gum` for interactive prompts/spinners, `nu` for structured data pipelines (nushell), `parallel` for parallel execution
- **Terminal**: `zellij` for multiplexing (tmux is intentionally not installed), `mpv` for video playback, `cliamp` for a terminal music player, `asciinema` for recording
- **Images/Media**: `magick` for image processing (ImageMagick), `oxipng` for PNG optimization, `yt-dlp` for video downloads
- **Logs**: `lnav` for log file navigation
- **Misc**: `qalc` for precise calculations + unit/currency conversions, `has` to check which tool versions are installed (e.g. `has node git jq`), `reminders` for Apple Reminders (see Environment above for when to use it)
- **Modern replacements are interactive-only — in your shell, `du`, `df`, `ps`, `top`, `cat`, `ls`, `dig`, `ping`, `watch`, `hexdump` are the REAL POSIX tools.** The user's interactive shell aliases them to `dust`/`duf`/`procs`/`btop`/`bat`/`eza`/`doggo`/`gping`/`viddy`/`hexyl`, but those aliases are gated off for non-interactive and agent shells precisely because none of them accept the original's flags. So write ordinary POSIX commands (`du -sh`, `ps aux`, `dig +short`) and they will work — no `/bin/` prefixes or workarounds needed. The modern tools are still available **by their own names** (`dust`, `procs`, `rg`, `fd`, `sd`, …) when you actually want them; prefer those for search and structured output, and note `sd` and `rg` have their own syntax, unrelated to `sed`/`grep`. The one exception: `rm` still routes to Trash so deletions stay recoverable, but it accepts `-r`/`-f` normally.

## Code Standards
- Use TypeScript strict mode for all TS projects
- Use ESLint + Prettier for formatting (2-space indent, single quotes, trailing commas)
- Use ruff for Python linting and formatting (not flake8/black/isort)
- Write tests alongside code (colocated, not in separate test dirs)
- Use conventional commit messages: type(scope): description
- Prefer named exports over default exports
- Use path aliases (@/ for src/) in TypeScript projects
- Lint Dockerfiles with hadolint before building

## React / Next.js
- Functional components only — no class components
- React hooks for state and effects
- Next.js App Router (not Pages Router) for new projects
- Use server components by default, 'use client' only when needed
- Tailwind CSS + shadcn/ui for styling

## Python
- Use uv for package management (not pip directly)
- Use ruff for linting and formatting
- Type hints on all public functions
- Use pydantic or dataclasses for data structures

## AWS / CDK / IaC
- CDK stacks in infrastructure/ directory
- Use L2/L3 constructs when available
- Always tag resources with project, environment, owner
- Use environment-specific config (dev/staging/prod)
- Follow least-privilege IAM principles
- Run `trivy config .` to scan IaC before deploying
- Use `infracost` to estimate costs before applying changes

## Git Workflow (Trunk-Based)
- Default host is **GitHub** (`gh`). For a repo hosted on **GitLab**, use **`glab`** — it's configured with the same alias names (`co`, `pv`, `pc`, `pl`, `pm`, …) mapped to merge requests, so the flow below translates 1:1 (PR → MR).
- **Never commit directly to main** — always use a feature branch + PR
- Branch naming: feature/, fix/, chore/, docs/ (e.g., feature/add-auth)
- Branches should be short-lived (< 2 days ideally)
- Squash merge to main (use `gh pm` alias) — keeps history clean
- Delete branch after merge (automatic with `gh pm`)
- Keep PRs small and focused (< 400 lines)
- Include tests with feature PRs
- Reference GitHub issues in PR descriptions (Closes #123)
- **Never auto-push** — always show a commit/diff summary and wait for explicit "push" approval
- Always `git pull --rebase` on main before creating any new branch
- Always `git checkout main` after submitting a PR — feature branches are ephemeral
- Use `git standup` to see yesterday's work
- Use `git cleanup` to prune merged branches
- Use `git recent` to see branches by last commit date

## PR Workflow
When asked to implement a feature or fix:
1. Create a GitHub issue first: `gh issue create --title "..." --body "..."`
2. Create a branch: `git switch -c feature/short-description`
3. Implement with small, atomic commits (conventional commit format)
4. Push and create PR: `gh pr create --title "..." --body "Closes #<issue>"`
5. PR body should include: Summary, Changes (bullet list), Test plan
6. Comment on the referenced issue linking to the PR
7. Use `/bin/cat` (not `cat`) inside heredoc subshells for `gh pr create --body` and `gh issue create --body`
8. After approval, merge with: `gh pm` (squash + delete branch)

## Issue Tracking
- Create issues for bugs, features, chores, and tech debt
- Use labels: bug, feature, chore, docs, tech-debt, security
- Reference issues in commits and PRs (Closes #N, Fixes #N)
- Use `gh il` to list issues, `gh ic` to create via browser

## README Standards
Every project should have a README.md with:
- Project name and one-line description
- Getting started (prerequisites, install, run)
- Architecture overview (for non-trivial projects)
- Environment variables (with descriptions, not values)
- Scripts/commands available (npm scripts, Justfile recipes)
- Testing instructions
- Deployment process
- Contributing guidelines (for shared projects)

## File Organization
- Components: src/components/[Feature]/
- Utilities: src/lib/ or src/utils/
- Types: src/types/
- API routes: src/app/api/ (Next.js) or src/api/
- Tests: colocated with source (*.test.ts)
- CDK: infrastructure/lib/
- Justfile in project root for common tasks

## When Writing Code
- Prefer early returns over nested conditions
- Use descriptive variable names (no single letters except loop counters)
- Add JSDoc comments for public APIs and complex functions
- Handle errors explicitly — no silent catches
- Use async/await over .then() chains
- Use zod for runtime validation at API boundaries
- Always choose the architecturally correct solution — no quick hacks, no type casts to bypass issues, no eslint-disable comments
- When multiple valid implementation approaches exist, present the options and let the user choose

## Error Handling Patterns
- **TypeScript**: Use Result types or discriminated unions for expected errors, throw for unexpected
- **Python**: Use specific exception types, never bare `except:`, always log context
- **API routes**: Return structured error responses `{ error: { code, message, details } }`
- **Async**: Always handle promise rejections, use try/catch with async/await
- **Never**: Swallow errors silently, use `console.log` for error handling, expose stack traces to users

## API Design Standards
- RESTful naming: plural nouns for collections (`/users`, `/posts`)
- HTTP methods: GET (read), POST (create), PUT (replace), PATCH (update), DELETE (remove)
- Response format: `{ data: T }` for success, `{ error: { code, message } }` for errors
- Always paginate list endpoints: `?page=1&limit=20` or cursor-based
- Use proper HTTP status codes: 200, 201, 204, 400, 401, 403, 404, 409, 422, 500
- Version APIs: `/api/v1/...` or via headers
- Validate all inputs at the boundary (zod for TS, pydantic for Python)

## Database Conventions
- Table names: plural, snake_case (`user_accounts`, `order_items`)
- Column names: snake_case (`created_at`, `is_active`, `user_id`)
- Always include: `id` (primary key), `created_at`, `updated_at`
- Use migrations (dbmate) — never modify schema manually
- Foreign keys: `<table_singular>_id` (e.g., `user_id`)
- Index foreign keys and columns used in WHERE/ORDER BY

## Testing Standards
- Write tests alongside code (colocated: `foo.ts` + `foo.test.ts`)
- Test behavior, not implementation (test what it does, not how)
- Follow Arrange-Act-Assert (AAA) pattern
- Unit tests: fast, isolated, no external dependencies
- Integration tests: test real interactions (DB, API, services)
- E2E tests: critical user flows only (login, checkout, etc.)
- Minimum coverage: aim for 80% on business logic, don't test trivial code
- Name tests clearly: "should return 404 when user not found"

## Pre-Push Checklist (follow before every PR)
1. All tests pass (`npm test` / `pytest` / `cargo test`)
2. Linting passes (`eslint .` / `ruff check .`)
3. Formatting applied (`prettier --write .` / `ruff format .`)
4. Spell check passes (`typos .`)
5. No secrets committed (`gitleaks detect`)
6. Dependencies audited (`npm audit` / `uv pip audit`)
7. README updated (if behavior changed)
8. Types check (`tsc --noEmit` for TypeScript)
9. Build succeeds (`npm run build`)

## Security Checks (run before PRs)
- `gitleaks detect` — check for leaked secrets
- `trivy fs .` — scan for vulnerabilities
- `npm audit` / `uv pip audit` — dependency audit
- `semgrep --config auto .` — static analysis
- `detect-secrets scan` — pre-commit secret detection
CLAUDE_MD_CONF
success "Claude Code global CLAUDE.md written (refreshed each run; edits outside the markers are kept)"

# ---- Claude Code rules directory ----
CLAUDE_RULES_DIR="$HOME/.claude/rules"
# Refreshed every run, same reasoning as the global CLAUDE.md above: these files are
# what Claude treats as standing instructions, so a machine provisioned once must not
# be stuck with the rules as they were that day. write_managed replaces the block in
# place and keeps anything outside the markers.
info "Writing Claude Code rules..."
mkdir -p "$CLAUDE_RULES_DIR"

    # Workflow rules (trunk-based, PR-first)
    write_managed "$CLAUDE_RULES_DIR/workflow.md" "#" <<'WORKFLOW_RULES'
# Workflow Rules (Trunk-Based Development)

## PR-First Approach
- NEVER commit directly to main — always create a feature branch and PR
- When implementing a feature or fix, follow this order:
  1. Create a GitHub issue (`gh issue create`) to track the work
  2. Create a short-lived branch (`git switch -c feature/description`)
  3. Implement with small, atomic conventional commits
  4. Create a PR referencing the issue (`gh pr create`, body includes "Closes #N")
  5. Merge via squash (`gh pm`)

## Issues
- Create an issue BEFORE starting implementation work
- Use clear titles: "Add user authentication" not "auth stuff"
- Label appropriately: bug, feature, chore, docs, tech-debt, security
- Reference issues in all commits and PRs

## PRs
- PR title: concise, imperative mood (< 70 chars)
- PR body: Summary (what/why), Changes (bullet list), Test Plan (checklist)
- Keep PRs small (< 400 lines changed)
- Include tests with feature PRs
- One concern per PR — don't mix features with refactoring

## READMEs
- Every new project MUST have a README.md
- Update README when adding significant features or changing setup steps
- README should cover: purpose, setup, usage, architecture, environment variables
WORKFLOW_RULES

    # Git rules
    write_managed "$CLAUDE_RULES_DIR/git.md" "#" <<'GIT_RULES'
# Git Rules

- Never force-push to main or master
- Never commit directly to main — use feature branches + PRs
- Never commit .env files, secrets, or credentials
- Use conventional commit format: type(scope): description
  - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
- Keep commits atomic — one logical change per commit
- Run tests before committing
- Reference GitHub issues in commits: "feat(auth): add login page (closes #42)"
- Branch names: feature/, fix/, chore/, docs/ (e.g., feature/add-oauth)
- Delete branches after merging (automatic with `gh pm`)
GIT_RULES

    # Security rules
    write_managed "$CLAUDE_RULES_DIR/security.md" "#" <<'SEC_RULES'
# Security Rules

- Never hardcode API keys, tokens, passwords, or secrets
- Use environment variables or AWS Secrets Manager for sensitive values
- Never log sensitive information (passwords, tokens, PII)
- Always validate and sanitize user input
- Use parameterized queries — never string-concatenate SQL
- Check npm audit before adding new dependencies
SEC_RULES

    # TypeScript rules
    write_managed "$CLAUDE_RULES_DIR/typescript.md" "#" <<'TS_RULES'
# TypeScript Rules

- Enable strict mode in tsconfig.json
- No `any` types — use `unknown` if type is truly unknown
- Use discriminated unions for complex state
- Prefer interfaces for object shapes, types for unions/intersections
- Use `as const` for literal types
- Export types alongside their implementations
- Use zod schemas that infer TypeScript types (z.infer<typeof schema>)
TS_RULES

    # Python rules
    write_managed "$CLAUDE_RULES_DIR/python.md" "#" <<'PY_RULES'
# Python Rules

- Use uv for package management (not pip directly)
- Use ruff for linting and formatting (not flake8, black, isort)
- Type hints on all public functions and method signatures
- Use pydantic for data validation, dataclasses for simple data structures
- Virtual environments via `uv venv` — never install globally
- Use `async def` for I/O-bound operations
- Prefer pathlib over os.path
PY_RULES

    # Docker rules
    write_managed "$CLAUDE_RULES_DIR/docker.md" "#" <<'DOCKER_RULES'
# Docker Rules

- Multi-stage builds for production images (builder + runtime)
- Run as non-root user (add USER directive)
- Use specific base image tags (not :latest)
- Lint Dockerfiles with `hadolint` before building
- Use .dockerignore to exclude node_modules, .git, etc.
- Scan images with `trivy image <name>` before pushing
- Use `dive <image>` to inspect and minimize layer sizes
DOCKER_RULES

    # IaC rules
    write_managed "$CLAUDE_RULES_DIR/iac.md" "#" <<'IAC_RULES'
# Infrastructure as Code Rules

- Use OpenTofu/Terraform with state stored remotely (S3 + DynamoDB)
- Lint with `tflint` before applying
- Document modules with `terraform-docs` (auto-generate variable/output sections)
- Run `checkov -d .` for IaC static analysis (Terraform, CloudFormation, Kubernetes, Dockerfile)
- Scan with `trivy config .` for misconfigurations (covers what tfsec used to)
- Estimate costs with `infracost` before applying changes
- Use modules for reusable infrastructure patterns
- Tag all resources: project, environment, owner, managed-by
- Use workspaces or separate state files per environment
IAC_RULES

success "Claude Code rules written (workflow, git, security, typescript, python, docker, iac — refreshed each run)"

# ---- Claude Code hooks ----
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
    info "Creating Claude Code hooks..."

    # Post-edit hook: auto-format with prettier
    write_managed_script "$CLAUDE_HOOKS_DIR/format-on-edit.sh" <<'HOOK_FORMAT'
#!/usr/bin/env bash
# Auto-format TypeScript/JavaScript files after Claude edits them
# Used by PostToolUse hook

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -n "$FILE" ]] && [[ "$FILE" =~ \.(ts|tsx|js|jsx|css|scss|json|md)$ ]]; then
    if [[ -f "$FILE" ]]; then
        # Only format if a prettier config exists in the project.
        #
        # The walk stops BEFORE $HOME. It used to run all the way to /, which meant
        # it passed through $HOME — where this same setup installs a global
        # ~/.prettierrc. Every path under $HOME therefore looked like "a project that
        # uses prettier", so the guard was unconditionally true and this hook
        # reformatted repos that had never opted in. It went unnoticed because a
        # duplicated ~/.prettierrc made prettier fail on every file (failures are
        # swallowed below); repairing that config in 7.8.2 brought the hook to life
        # and the behaviour with it (#268).
        #
        # A file directly in $HOME is not a project, so it is left alone too.
        PROJECT_DIR=$(dirname "$FILE")
        while [[ "$PROJECT_DIR" != "/" && "$PROJECT_DIR" != "$HOME" ]]; do
            if [[ -f "$PROJECT_DIR/.prettierrc" ]] || [[ -f "$PROJECT_DIR/.prettierrc.json" ]] \
               || [[ -f "$PROJECT_DIR/.prettierrc.yaml" ]] || [[ -f "$PROJECT_DIR/.prettierrc.yml" ]] \
               || [[ -f "$PROJECT_DIR/.prettierrc.js" ]] || [[ -f "$PROJECT_DIR/.prettierrc.mjs" ]] \
               || [[ -f "$PROJECT_DIR/prettier.config.js" ]] || [[ -f "$PROJECT_DIR/prettier.config.mjs" ]]; then
                # Prefer the PROJECT's own prettier over the global one: a repo that
                # pins prettier 2.x must not be reformatted by the global 3.x (major
                # versions disagree on trailing commas, etc., producing diff churn
                # nobody asked for). --no-install keeps npx offline — it resolves
                # node_modules/.bin or fails, never downloads. Global is the fallback
                # for projects with a prettier config but no local install.
                if command -v npx &>/dev/null && npx --no-install prettier --write "$FILE" 2>/dev/null; then
                    :
                elif command -v prettier &>/dev/null; then
                    prettier --write "$FILE" 2>/dev/null || true
                fi
                break
            fi
            PROJECT_DIR=$(dirname "$PROJECT_DIR")
        done
    fi
fi

exit 0
HOOK_FORMAT

    # Post-edit hook: auto-lint Python files with ruff
    write_managed_script "$CLAUDE_HOOKS_DIR/lint-python.sh" <<'HOOK_RUFF'
#!/usr/bin/env bash
# Auto-lint and fix Python files after Claude edits them

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -n "$FILE" ]] && [[ "$FILE" =~ \.py$ ]]; then
    if [[ -f "$FILE" ]] && command -v ruff &>/dev/null; then
        # Only touch a project that opted into ruff.
        #
        # `ruff check --fix` REWRITES code — it deletes imports it judges unused, so an
        # import kept for its side effects (plugin/codec registration, `matplotlib.use`,
        # Django signals, `import readline`) is removed and the program breaks at runtime.
        # In a repo that never chose ruff that is not a formatting convenience, it is an
        # unrequested edit — and with output swallowed below, an invisible one. A repo
        # that DID configure ruff has asked for exactly this behaviour.
        #
        # The walk stops before $HOME for the same reason as format-on-edit: a config
        # sitting in $HOME is not a project opting in, and treating it as one is what
        # made that hook reformat every repo on the machine (#268, #276).
        PROJECT_DIR=$(dirname "$FILE")
        while [[ "$PROJECT_DIR" != "/" && "$PROJECT_DIR" != "$HOME" ]]; do
            if [[ -f "$PROJECT_DIR/ruff.toml" ]] || [[ -f "$PROJECT_DIR/.ruff.toml" ]] \
               || { [[ -f "$PROJECT_DIR/pyproject.toml" ]] \
                    && grep -q '^\[tool\.ruff' "$PROJECT_DIR/pyproject.toml" 2>/dev/null; }; then
                ruff check --fix "$FILE" 2>/dev/null || true
                ruff format "$FILE" 2>/dev/null || true
                break
            fi
            PROJECT_DIR=$(dirname "$PROJECT_DIR")
        done
    fi
fi

exit 0
HOOK_RUFF

    # Post-edit hook: lint Dockerfiles with hadolint
    write_managed_script "$CLAUDE_HOOKS_DIR/lint-dockerfile.sh" <<'HOOK_HADOLINT'
#!/usr/bin/env bash
# Lint Dockerfiles after Claude edits them

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ -n "$FILE" ]] && [[ "$(basename "$FILE")" =~ ^Dockerfile ]]; then
    if [[ -f "$FILE" ]] && command -v hadolint &>/dev/null; then
        ISSUES=$(hadolint "$FILE" 2>/dev/null)
        if [[ -n "$ISSUES" ]]; then
            echo "$ISSUES" >&2
        fi
    fi
fi

exit 0
HOOK_HADOLINT

    success "Claude Code hooks created (auto-format JS/TS, auto-lint Python, lint Dockerfiles)"

# ---- Claude Code statusline (Dracula) ----
CLAUDE_STATUSLINE="$HOME/.claude/statusline.sh"
info "Configuring Claude Code Dracula statusline..."
write_managed_script "$CLAUDE_STATUSLINE" <<'STATUSLINE'
#!/usr/bin/env bash
# Claude Code statusline — Dracula. Reads session JSON on stdin.
input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."' 2>/dev/null)
dir=$(basename "$cwd")
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
P='\033[38;2;189;147;249m'   # purple
C='\033[38;2;139;233;253m'   # cyan
G='\033[38;2;80;250;123m'    # green
D='\033[38;2;98;114;164m'    # comment
R='\033[0m'
out="${P}${model}${R} ${D}in${R} ${C}${dir}${R}"
[ -n "$branch" ] && out="${out} ${D}on${R} ${G}${branch}${R}"
printf '%b' "$out"
STATUSLINE
success "Claude Code Dracula statusline created (model, dir, git branch)"

# ---- Claude Code subagents ----
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
# Refreshed every run via write_generated. This used to be gated on "directory
# already has agents", so a single pre-existing file froze the whole set and no
# later edit or addition ever reached a provisioned machine (#277).
info "Writing Claude Code subagents (code-reviewer, aws-helper)..."
mkdir -p "$CLAUDE_AGENTS_DIR"
write_generated "$CLAUDE_AGENTS_DIR/code-reviewer.md" <<'AGENT_REVIEWER'
---
name: code-reviewer
description: Reviews changed code for bugs, security issues, and adherence to this setup's conventions (ruff, strict TypeScript, conventional commits, parameterized SQL, no hardcoded secrets). Use after writing or modifying code, or when asked for a review.
tools: Read, Grep, Glob, Bash
---
You are a precise, senior code reviewer for this developer's projects.

Review priorities (most important first):
1. Correctness — logic bugs, edge cases, error handling, race conditions.
2. Security — no hardcoded secrets/keys/tokens; validate & sanitize input; parameterized queries (never string-concatenated SQL); never log PII/secrets.
3. Conventions:
   - Python: ruff for lint/format; type hints on public functions; pydantic for validation, dataclasses for simple data; pathlib over os.path; async for I/O.
   - TypeScript: strict mode; no `any` (use `unknown`); zod schemas; interfaces for object shapes.
   - Git: conventional commits (type(scope): description); atomic commits; never commit .env/secrets.
4. Simplicity — dead code, needless complexity, duplication.

Method: read the diff/files, then report findings ranked most-severe first. For each: file:line, the concrete problem, and a specific fix. Cite exact lines. If unsure a finding is real, say so. End with a one-line verdict. Point precisely; don't rewrite large sections unasked.
AGENT_REVIEWER
write_generated "$CLAUDE_AGENTS_DIR/aws-helper.md" <<'AGENT_AWS'
---
name: aws-helper
description: AWS specialist for this setup — knows the installed AWS tooling and prefers read-only, least-privilege, cost-aware operations. Use for AWS resource inspection, IaC (CDK/SAM/Terraform), IAM, and cost questions.
tools: Read, Grep, Glob, Bash, WebFetch
---
You are an AWS specialist working in this developer's terminal-first setup.

Credentials: this machine uses `granted` — assume a profile with `assume <profile>` (exports AWS_PROFILE), or rely on AWS_REGION/AWS_PROFILE in the environment. Never print or store credentials.

Installed tooling to prefer (don't reinvent):
- Inspect (interactive TUIs): e1s (ECS), e2c (EC2), stu (S3), claws (broad), k9s (EKS).
- Query/inventory: `steampipe query` (SQL over AWS), `aws` CLI, `aws logs tail --follow`.
- S3 bulk: `s5cmd`. DynamoDB: `dynein`. IAM least-privilege: `iamlive`.
- IaC: CDK (+ cdk-nag), SAM, OpenTofu/Terraform (+ tflint, checkov, `trivy config`, infracost).

Operating rules:
1. Default to READ-ONLY (describe/list/get/query). Before any mutating or costly action, state exactly what will change and its blast radius, then ask for confirmation.
2. Right-size IAM — least privilege; suggest `iamlive` to generate policies from observed calls.
3. Be cost-aware — mention `infracost` for IaC changes and pricing implications for new resources.
4. Prefer the installed TUIs/CLIs over manual console steps; give exact commands.
AGENT_AWS
success "Claude Code subagents created (code-reviewer, aws-helper)"

# ---- Claude Code custom slash commands ----
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
# Refreshed every run via write_generated — same reasoning as the agents block (#277).
info "Writing Claude Code custom slash commands..."
mkdir -p "$CLAUDE_COMMANDS_DIR"

# /pr-review — review the current branch's changes
write_generated "$CLAUDE_COMMANDS_DIR/pr-review.md" <<'CMD_PR_REVIEW'
Review the changes on the current branch compared to main. For each file changed:
1. Summarize what changed and why
2. Flag any security issues, bugs, or performance concerns
3. Check for missing error handling or edge cases
4. Note any style inconsistencies

Use `git diff main...HEAD` to see all changes. Be concise — focus on issues, not praise.
CMD_PR_REVIEW

# /test-plan — generate a test plan for recent changes
write_generated "$CLAUDE_COMMANDS_DIR/test-plan.md" <<'CMD_TEST_PLAN'
Look at the recent changes in this repo (use git diff or git log) and generate a test plan:
1. List what should be tested (unit, integration, e2e)
2. Identify edge cases and error scenarios
3. Suggest specific test cases with expected inputs/outputs
4. Note any areas that are hard to test and why

Output as a Markdown checklist.
CMD_TEST_PLAN

# /dep-audit — audit dependencies
write_generated "$CLAUDE_COMMANDS_DIR/dep-audit.md" <<'CMD_DEP_AUDIT'
Audit the project dependencies:
1. Check for known vulnerabilities (run npm audit or uv pip audit)
2. Identify outdated packages (run npm outdated or uv pip list --outdated)
3. Flag any packages with no recent maintenance (>2 years)
4. Check for duplicate/redundant dependencies
5. Estimate total bundle size impact of each dependency if this is a frontend project

Summarize findings with severity (critical/high/medium/low) and recommended actions.
CMD_DEP_AUDIT

# /quick-doc — generate docs for a file or function
write_generated "$CLAUDE_COMMANDS_DIR/quick-doc.md" <<'CMD_QUICK_DOC'
Generate documentation for the file or function I specify: $ARGUMENTS

Include:
1. A brief description of what it does
2. Parameters/props with types and descriptions
3. Return value
4. Usage example
5. Any gotchas or important notes

Format as JSDoc/docstring appropriate for the language.
CMD_QUICK_DOC

# /cleanup — find dead code, unused imports, etc.
write_generated "$CLAUDE_COMMANDS_DIR/cleanup.md" <<'CMD_CLEANUP'
Scan the project for cleanup opportunities:
1. Unused imports and variables
2. Dead code (unreachable functions, unused exports)
3. Console.log / debug statements left in
4. TODO/FIXME comments that should be addressed
5. Empty catch blocks or swallowed errors

List each finding with file path and line number. Don't fix anything — just report.
CMD_CLEANUP

# /security-scan — run all security tools
write_generated "$CLAUDE_COMMANDS_DIR/security-scan.md" <<'CMD_SECURITY'
Run a comprehensive security scan of this project using the available tools:

1. **Secrets**: Run `gitleaks detect --source .` to check for leaked credentials
2. **Dependencies**: Run `npm audit` (Node) or `uv pip audit` (Python) for known vulnerabilities
3. **Static analysis**: Run `semgrep --config auto .` for security anti-patterns
4. **Container scan**: If there's a Dockerfile, run `trivy fs .` to scan for vulnerabilities
5. **IaC scan**: If there are Terraform/CDK files, run `trivy config .` for misconfigurations

For each finding, report: severity, file, line, description, and recommended fix.
Prioritize: critical > high > medium > low. Skip informational findings.
CMD_SECURITY

# /perf-check — benchmark and profile
write_generated "$CLAUDE_COMMANDS_DIR/perf-check.md" <<'CMD_PERF'
Analyze the performance of this project: $ARGUMENTS

1. If a command/script is given, benchmark it with `hyperfine`
2. If a URL is given, load test with `oha -n 500 -c 10 <url>`
3. If no argument, look at package.json scripts and suggest which to benchmark
4. Check for common performance anti-patterns in the code (N+1 queries, missing indexes, unbounded loops, sync I/O in async code)
5. Check bundle size if this is a frontend project (`npx @next/bundle-analyzer` or similar)

Report findings with concrete numbers and suggested optimizations.
CMD_PERF

# /docker-lint — lint and optimize Docker setup
write_generated "$CLAUDE_COMMANDS_DIR/docker-lint.md" <<'CMD_DOCKER'
Analyze the Docker setup in this project:

1. Lint all Dockerfiles with `hadolint`
2. If images are built, analyze with `dive` for layer optimization opportunities
3. Check docker-compose.yml for best practices (health checks, resource limits, named volumes)
4. Verify .dockerignore exists and excludes node_modules, .git, etc.
5. Check for security issues: running as root, secrets in build args, latest tags

Fix any issues found and explain the changes.
CMD_DOCKER

# /iac-review — review infrastructure code
write_generated "$CLAUDE_COMMANDS_DIR/iac-review.md" <<'CMD_IAC'
Review the infrastructure-as-code in this project:

1. Run `tflint` on any Terraform/OpenTofu files
2. Run `trivy config .` to scan for misconfigurations (broad surface — IaC + Dockerfile + K8s)
3. Run `checkov -d .` for IaC-focused static analysis (different rule set than trivy — they're complementary)
4. Run `infracost breakdown --path .` to estimate costs (if infracost is configured)
5. If Terraform modules are present, run `terraform-docs markdown table .` and verify the README's variable/output sections are up to date
6. Check for: missing tags, overly permissive IAM, unencrypted resources, missing backups
7. Check CDK code for L1 constructs that should be L2/L3

Report findings with severity and recommended fixes.
CMD_IAC

# /convert — convert between formats using pandoc
write_generated "$CLAUDE_COMMANDS_DIR/convert.md" <<'CMD_CONVERT'
Convert files between formats: $ARGUMENTS

Use the available tools:
- `pandoc` for document conversion (md, html, pdf, docx, rst)
- `d2` for diagram generation from text
- `mmdc` (mermaid) for flowcharts, sequence diagrams, ERDs
- `ffmpeg` for audio/video conversion
- `magick` for image conversion and manipulation

Parse the user's intent from the arguments and run the appropriate conversion command.
Examples: "convert README.md to pdf", "resize logo.png to 200x200", "diagram from architecture.d2"
CMD_CONVERT

# /new-feature — full trunk-based feature workflow
write_generated "$CLAUDE_COMMANDS_DIR/new-feature.md" <<'CMD_NEW_FEATURE'
Implement a new feature following trunk-based development: $ARGUMENTS

Follow this workflow in order:
1. **Create issue**: Run `gh issue create --title "<feature title>" --body "<description>" --label "feature"` and note the issue number
2. **Create branch**: Run `git switch -c feature/<short-kebab-name>`
3. **Implement**: Write the code with tests. Use conventional commits (feat, test, docs).
4. **Create/update README**: If this adds a new capability, update the project README
5. **Push and PR**: Run `git push -u origin HEAD` then `gh pr create --title "feat: <title>" --body "## Summary\n<what and why>\n\n## Changes\n- <bullet list>\n\n## Test Plan\n- [ ] <test items>\n\nCloses #<issue-number>"`

Make each commit small and atomic. Write tests alongside the implementation, not after.
CMD_NEW_FEATURE

# /fix-bug — full trunk-based bug fix workflow
write_generated "$CLAUDE_COMMANDS_DIR/fix-bug.md" <<'CMD_FIX_BUG'
Fix a bug following trunk-based development: $ARGUMENTS

Follow this workflow in order:
1. **Create issue**: Run `gh issue create --title "fix: <bug title>" --body "<description of bug, steps to reproduce, expected vs actual>" --label "bug"` and note the issue number
2. **Create branch**: Run `git switch -c fix/<short-kebab-name>`
3. **Write failing test first**: Write a test that reproduces the bug (should fail)
4. **Fix**: Implement the fix so the test passes
5. **Verify**: Run the full test suite to confirm no regressions
6. **Push and PR**: Run `git push -u origin HEAD` then `gh pr create --title "fix: <title>" --body "## Bug\n<what was broken>\n\n## Root Cause\n<why it happened>\n\n## Fix\n<what changed>\n\n## Test Plan\n- [ ] Repro test passes\n- [ ] No regressions\n\nFixes #<issue-number>"`
CMD_FIX_BUG

# /create-readme — generate a comprehensive README
write_generated "$CLAUDE_COMMANDS_DIR/create-readme.md" <<'CMD_README'
Generate a comprehensive README.md for this project.

Analyze the codebase to determine:
1. **Project name and description** — from package.json, Cargo.toml, go.mod, or directory name
2. **Tech stack** — languages, frameworks, key dependencies
3. **Prerequisites** — runtime versions, required tools, env vars
4. **Getting started** — install deps, run dev server, build, test
5. **Project structure** — key directories and what they contain
6. **Available scripts/commands** — from package.json scripts, Justfile, Makefile
7. **Environment variables** — list all referenced env vars with descriptions (NOT values)
8. **Architecture** — high-level overview if the project has multiple services/modules
9. **API documentation** — if there are API routes, list endpoints with methods
10. **Deployment** — if there are Docker/CI/CD files, document the process
11. **Contributing** — branch naming, commit format, PR process

Use clean Markdown formatting. Be concise but complete. If information isn't available, leave a placeholder with a TODO comment.
CMD_README

# /init-project — set up a new project with all best practices
write_generated "$CLAUDE_COMMANDS_DIR/init-project.md" <<'CMD_INIT'
Initialize a new project with industry best practices: $ARGUMENTS

Set up the following in order:

## 1. Git
- Initialize repo with `git init -b main`
- Create comprehensive .gitignore (language-appropriate)

## 2. README.md
- Project name, one-line description, tech stack
- Getting started (prerequisites, install, run, test)
- Available scripts/commands
- Project structure overview
- Environment variables (with descriptions, not values)

## 3. AGENTS.md (public agent instructions)
Create a tracked `AGENTS.md` at the repo root. It is written for whoever contributes, so
keep it free of personal preference and point at documents rather than restating them.
Add `CLAUDE.md` to `.gitignore` — that file is private, for personal notes only:
```markdown
# <Project Name>

## Overview
<One-paragraph description of what this project does>

## Tech Stack
<Languages, frameworks, key libraries>

## Architecture
<How the project is structured, key directories>

## Development
- Run dev: `just dev` or `npm run dev`
- Run tests: `just test` or `npm test`
- Build: `just build` or `npm run build`

## Conventions
<Any project-specific conventions not in the global instructions>
```

## 4. Code Quality
- **EditorConfig**: Copy global defaults or create project-specific
- **Prettier**: Create .prettierrc if JS/TS project
- **Linting**: ESLint (TS/JS), ruff.toml (Python), clippy (Rust)

## 5. Testing
- Set up framework: vitest (preferred for TS), pytest (Python), cargo test (Rust)
- Create example test file

## 6. CI/CD
Create `.github/workflows/ci.yml`:
```yaml
on: [push, pull_request]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps: [checkout, setup-node/python/rust, install deps, lint, test, build]
```

## 7. Justfile
Create with recipes: dev, test, build, lint, format, clean

## 8. Docker (if appropriate)
- Multi-stage Dockerfile (builder + runtime, non-root user)
- .dockerignore (node_modules, .git, .env, dist)
- docker-compose.yml for local development

## 9. Environment
- .env.example with all variables documented
- .env in .gitignore

## 10. GitHub Templates
Create `.github/PULL_REQUEST_TEMPLATE.md`:
```markdown
## Summary
<!-- What does this PR do and why? -->

## Changes
-

## Test Plan
- [ ]

Closes #
```

Create `.github/ISSUE_TEMPLATE/feature.md`:
```markdown
---
name: Feature Request
about: Suggest a new feature
labels: feature
---
## Problem
<!-- What problem does this solve? -->

## Proposed Solution
<!-- How should it work? -->

## Acceptance Criteria
- [ ]
```

Create `.github/ISSUE_TEMPLATE/bug.md`:
```markdown
---
name: Bug Report
about: Report a bug
labels: bug
---
## Bug Description
<!-- What happened? -->

## Steps to Reproduce
1.

## Expected Behavior
## Actual Behavior
## Environment
```

## 11. License
- Add MIT license (or ask which)

## 12. Initial commit and push
- `git add -A && git commit -m "feat: initial project scaffold"`
- Create GitHub repo if not exists: `gh repo create <name> --private --source=.`
- Push: `git push -u origin main`
CMD_INIT

# /refactor — refactor code with tests preserved
write_generated "$CLAUDE_COMMANDS_DIR/refactor.md" <<'CMD_REFACTOR'
Refactor the specified code: $ARGUMENTS

Follow this process:
1. **Understand**: Read the code and its tests. Identify what the code does and its public API.
2. **Plan**: Describe the refactoring approach before changing anything.
3. **Preserve tests**: Ensure all existing tests still pass after refactoring. Do NOT modify test assertions.
4. **Refactor**: Apply the changes. Focus on:
   - Reducing complexity (extract functions, simplify conditions)
   - Improving naming (descriptive, consistent)
   - Removing duplication (DRY, extract shared logic)
   - Applying SOLID principles
   - Improving type safety
5. **Verify**: Run tests to confirm nothing broke.
6. **Commit**: Use `refactor(scope): description` commit format.

If tests don't exist, write them FIRST before refactoring.
CMD_REFACTOR

# /add-endpoint — add an API endpoint with full stack
write_generated "$CLAUDE_COMMANDS_DIR/add-endpoint.md" <<'CMD_ENDPOINT'
Add a new API endpoint: $ARGUMENTS

Implement the full vertical slice:
1. **Types**: Define request/response types (zod schema for TS, pydantic for Python)
2. **Route handler**: Implement the endpoint with proper HTTP method and status codes
3. **Validation**: Validate all inputs at the boundary
4. **Error handling**: Return structured errors with appropriate status codes
5. **Tests**: Write unit tests for the handler and integration tests for the route
6. **Documentation**: Add JSDoc/docstring, update API docs or README if they exist

Follow REST conventions:
- GET for retrieval (200), POST for creation (201), PUT/PATCH for updates (200), DELETE for removal (204)
- Response format: `{ data: T }` for success, `{ error: { code, message } }` for errors
- Always paginate list endpoints

Commit with: `feat(api): add <METHOD> <path> endpoint`
CMD_ENDPOINT

# /add-component — add a React component with tests and stories
write_generated "$CLAUDE_COMMANDS_DIR/add-component.md" <<'CMD_COMPONENT'
Add a new React component: $ARGUMENTS

Create the full component package:
1. **Component file**: `ComponentName.tsx` — functional component with TypeScript props interface
2. **Tests**: `ComponentName.test.tsx` — test rendering, user interactions, edge cases
3. **Types**: Export the props interface for consumers
5. **Index**: Add to barrel export (`index.ts`) if the directory uses one

Follow these patterns:
- Functional components only, use hooks for state/effects
- Props interface named `ComponentNameProps`, exported
- Use `forwardRef` if the component wraps a native element
- Tailwind CSS for styling (or whatever the project uses)
- Handle loading, error, and empty states
- Accessibility: proper ARIA attributes, keyboard navigation, semantic HTML

Place in: `src/components/ComponentName/` (colocated structure)
Commit with: `feat(ui): add <ComponentName> component`
CMD_COMPONENT

# /ci-fix — diagnose and fix CI failures
write_generated "$CLAUDE_COMMANDS_DIR/ci-fix.md" <<'CMD_CIFIX'
Diagnose and fix the CI/CD pipeline failure.

Steps:
1. **Check CI status**: Run `gh run list --limit 5` to see recent runs
2. **Get failure details**: Run `gh run view <run-id> --log-failed` to see the error
3. **Diagnose**: Identify the root cause (test failure, lint error, build error, dependency issue, flaky test)
4. **Fix**: Apply the fix
5. **Verify locally**: Run the same checks locally (`act` for GitHub Actions, or the individual commands)
6. **Push**: Commit with `ci: fix <description of what broke>`

Common CI issues to check:
- Node/Python version mismatch between local and CI
- Missing environment variables in CI
- Dependency resolution differences (lockfile out of date)
- Flaky tests (timing-dependent, order-dependent)
- ESLint/Prettier formatting differences
CMD_CIFIX

# /changelog — generate changelog from git history
write_generated "$CLAUDE_COMMANDS_DIR/changelog.md" <<'CMD_CHANGELOG'
Generate a changelog from git history: $ARGUMENTS

Use `git-cliff` if available (preferred — uses ~/.config/git-cliff/cliff.toml config).
Fall back to manual parsing if git-cliff is not installed.

**With git-cliff:**
1. If no range specified: `git-cliff --unreleased`
2. For a full changelog: `git-cliff -o CHANGELOG.md`
3. For a specific range: `git-cliff v1.0.0..HEAD`

**Without git-cliff (manual fallback):**
1. Get commits: `git log <range> --oneline --format="%h %s"`
2. Parse conventional commits and group by type:
   - **Features** (feat:) — new functionality
   - **Bug Fixes** (fix:) — bug fixes
   - **Performance** (perf:) — performance improvements
   - **Documentation** (docs:) — documentation changes
   - **Other** (chore:, refactor:, style:, test:, build:, ci:)
3. Format as Markdown with:
   - Version header with date
   - Grouped sections (only include sections that have entries)
   - Each entry: short description with commit hash link
   - Breaking changes highlighted at the top
4. If a CHANGELOG.md exists, prepend the new entry. Otherwise create it.

Format: Keep it concise — one line per change, no fluff.
CMD_CHANGELOG

# /commit-msg — generate commit message from staged changes
write_generated "$CLAUDE_COMMANDS_DIR/commit-msg.md" <<'CMD_COMMIT'
Generate a conventional commit message for the currently staged changes.

1. Run `git diff --cached --stat` to see what files changed
2. Run `git diff --cached` to see the actual changes
3. Analyze the changes and determine:
   - **Type**: feat, fix, docs, style, refactor, perf, test, build, ci, chore
   - **Scope**: the module or area affected (optional but preferred)
   - **Description**: concise summary in imperative mood
   - **Body**: explain WHAT changed and WHY (not HOW) — only if non-obvious
   - **Footer**: reference issues if applicable (Closes #N)
4. Output the commit message in this format:
   ```
   type(scope): short description

   Optional body explaining what and why.

   Closes #N
   ```
5. Run the commit: `git commit -m "<message>"`

Keep the first line under 72 characters. Use imperative mood ("add" not "added").
CMD_COMMIT

success "Claude Code commands created (20 commands: /pr-review, /test-plan, /dep-audit, /quick-doc, /cleanup, /security-scan, /perf-check, /docker-lint, /iac-review, /convert, /new-feature, /fix-bug, /create-readme, /init-project, /refactor, /add-endpoint, /add-component, /ci-fix, /changelog, /commit-msg)"

# ---- Claude Code first-party skills (authored here) ----
# Skills that teach Claude to use tools THIS script installs, written fresh each run
# (script-owned, like the gws skills, so updates propagate). Unlike the commands above,
# a SKILL.md must start with its YAML frontmatter on line 1 — so these use plain
# heredocs, NOT write_managed (its leading comment marker would break the frontmatter).
if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] Would write first-party Claude skills (office-docs, d2-diagrams, dbmate-migrations, api-testing) -> ~/.claude/skills/"
else
    info "Writing first-party Claude Code skills..."
    mkdir -p "$HOME/.claude/skills/office-docs"
    cat > "$HOME/.claude/skills/office-docs/SKILL.md" <<'SKILL_OFFICE_DOCS'
---
name: office-docs
description: Inspect, validate, convert, and visually verify LOCAL Office / OpenDocument files (.docx, .pptx, .xlsx, .odt, .ods, .odp) from the terminal — render to PDF/PNG to actually see them, extract text/metadata, and assert on structured content. Use when handed a local office file to check, screenshot, convert, or verify. NOT for authoring (that stays in Google Workspace) and NOT for cloud Drive files (use the gws skills).
---

# office-docs — work with local Office / OpenDocument files

This machine has a purpose-built local toolchain for `.docx`/`.pptx`/`.xlsx` (installed by the dev setup). Authoring belongs in Google Workspace; this skill is for **inspecting, validating, converting, and visually verifying files already on the local filesystem**.

## The three moves

1. **Render (fidelity) — see what it actually looks like.** LibreOffice headless is the renderer; rasterize the PDF to PNGs you can open and read:
   ```bash
   soffice --headless --convert-to pdf --outdir /tmp "deck.pptx"
   pdftoppm -png -r 150 /tmp/deck.pdf /tmp/deck-page   # -> /tmp/deck-page-1.png, -2.png, ...
   ```
   Then Read the PNGs to judge layout and visuals. `soffice` also converts formats: `--convert-to csv` (xlsx->csv), `--convert-to docx`, `--convert-to txt`.

2. **Extract text / metadata** without rendering:
   ```bash
   pdftotext /tmp/deck.pdf -     # text to stdout
   pdfinfo   /tmp/deck.pdf       # page count, dimensions, metadata
   doxx report.docx             # read a .docx directly in the terminal
   ```

3. **Assert on structured content** with `office-py` (a venv carrying python-docx / openpyxl / python-pptx):
   ```bash
   office-py -c 'from pptx import Presentation; p=Presentation("deck.pptx"); print(len(p.slides))'
   office-py -c 'import openpyxl; wb=openpyxl.load_workbook("data.xlsx"); print(wb.sheetnames)'
   office-py -c 'import docx; d=docx.Document("report.docx"); print(len(d.paragraphs))'
   ```

## Guidance

- To **create or heavily edit** a local `.docx`/`.pptx`/`.xlsx`, prefer Claude Code's bundled `docx` / `pptx` / `xlsx` skills (same underlying libraries); use move #1 to preview the result.
- For **cloud** Google Docs/Sheets/Slides, use the `gws` skills — this skill is for local files only.
- Always render into `/tmp` (or the scratch dir), never next to the source file.
- If `soffice` errors on a file, report it — usually a corrupt or password-protected document. `soffice` needs no running instance; it runs fully headless.
SKILL_OFFICE_DOCS

    mkdir -p "$HOME/.claude/skills/d2-diagrams"
    cat > "$HOME/.claude/skills/d2-diagrams/SKILL.md" <<'SKILL_D2'
---
name: d2-diagrams
description: Create and render diagrams as code — architecture, flowcharts, sequence, ER, network — with d2 (primary) or mermaid/mmdc (fallback), producing SVG/PNG. Use when the user asks to diagram, visualize, sketch, or draw a system/flow/architecture, or to turn a description or code into a diagram file.
---

# d2-diagrams — diagrams as code

This setup uses **`d2`** as the primary diagram tool (it replaced draw.io); `mmdc` (mermaid) is the fallback when the user specifically wants mermaid or a diagram type d2 handles awkwardly.

## d2 workflow

1. Write the diagram source to a `.d2` file (keep it next to the output so it stays regenerable):
   ```d2
   # arch.d2
   user -> api: request
   api -> db: query
   api -> cache: read-through
   ```
2. Render, then Read the PNG (or open the SVG) to actually see it:
   ```bash
   d2 arch.d2 arch.svg              # SVG (default, crisp, scalable)
   d2 arch.d2 arch.png              # PNG (for inline viewing)
   d2 --theme 200 arch.d2 arch.svg  # apply a theme
   d2 --layout elk arch.d2 out.svg  # ELK engine for dense graphs (default is dagre)
   d2 --watch arch.d2               # live-reload preview in the browser
   ```

## mermaid fallback

```bash
mmdc -i flow.mmd -o flow.svg     # flowcharts, sequence, ER, gantt
```

## Guidance

- Default to d2 unless the user asks for mermaid.
- Commit the `.d2`/`.mmd` source, not just the rendered image.
- For big graphs, try `--layout elk` if dagre gets tangled.
SKILL_D2

    mkdir -p "$HOME/.claude/skills/dbmate-migrations"
    cat > "$HOME/.claude/skills/dbmate-migrations/SKILL.md" <<'SKILL_DBMATE'
---
name: dbmate-migrations
description: Create and run database schema migrations with dbmate — new timestamped up/down SQL files, apply, roll back, and check status. Use when the user wants to add or alter a table/column, create a migration, or manage schema changes. Follows this setup's DB conventions.
---

# dbmate-migrations — database migrations

`dbmate` manages plain-SQL migrations, driven by `DATABASE_URL` (it reads `.env` by default).

## Workflow

```bash
dbmate new add_users_table   # -> db/migrations/<timestamp>_add_users_table.sql
dbmate up                    # apply all pending migrations
dbmate down                  # roll back the most recent migration
dbmate status                # list applied + pending
```

Each file has an up and a down section:

```sql
-- migrate:up
create table users (
  id         bigint generated always as identity primary key,
  email      text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_users_email on users (email);

-- migrate:down
drop table users;
```

## Conventions (from the global DB rules)

- Table names **plural, snake_case** (`user_accounts`, `order_items`).
- Always include `id`, `created_at`, `updated_at`.
- Foreign keys are `<table_singular>_id`; **index** FKs and any column used in WHERE/ORDER BY.
- **Never edit an already-applied migration** — write a new one.
- Always provide a working `-- migrate:down` so rollbacks are safe.
SKILL_DBMATE

    mkdir -p "$HOME/.claude/skills/api-testing"
    cat > "$HOME/.claude/skills/api-testing/SKILL.md" <<'SKILL_API'
---
name: api-testing
description: Test and debug HTTP/gRPC APIs from the terminal — send requests, write repeatable test files with assertions, and inspect responses. Use when the user wants to hit an endpoint, verify an API response, write an API test, or debug a request. Leads with headless tools (hurl, xh, curlie, grpcurl); atac is the interactive TUI for saved collections.
---

# api-testing — HTTP/gRPC from the terminal

## One-off requests — `xh` (or `curlie`)

```bash
xh GET api.example.com/users limit==20 Authorization:"Bearer $TOKEN"   # ==  query param,  :  header
xh POST api.example.com/users name=Ada email=ada@example.com           # =  builds a JSON body
```
`curlie` is curl's interface with httpie-style colored output.

## Repeatable tests with assertions — `hurl` (preferred for anything worth keeping)

```hurl
# users.hurl
GET https://api.example.com/users
HTTP 200
[Asserts]
jsonpath "$.data" count > 0
jsonpath "$.data[0].id" exists
```
```bash
hurl --test users.hurl   # run as a test: assertions + exit code + report
hurl users.hurl          # just execute and print the response body
```

## gRPC — `grpcurl`

```bash
grpcurl -plaintext localhost:50051 list
grpcurl -d '{"id":1}' localhost:50051 svc.Users/Get
```

## Interactive / saved collections — `atac`

`atac` is the TUI API client (Postman-like; imports Postman collections, stores JSON/YAML on disk). Point the user there for exploratory work; use `hurl`/`xh` for anything Claude should run headlessly.

## Guidance

- Save anything worth rerunning as a `.hurl` file (assertable, version-controlled) rather than ad-hoc `xh` commands.
- Never hard-code secrets — reference env vars / `{{token}}` variables.
SKILL_API
    success "First-party Claude skills written: office-docs, d2-diagrams, dbmate-migrations, api-testing -> ~/.claude/skills/"
fi


fi  # configs (Claude Code)

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
if [[ -o interactive && -z "$CLAUDECODE" && -z "$AI_AGENT" ]]; then
    command -v assume &>/dev/null && alias assume="source assume"
fi

# fzf — Dracula colors + fd for file finding + bat for preview
export FZF_DEFAULT_OPTS=" \
  --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 \
  --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 \
  --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 \
  --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4 \
  --color=border:#6272a4 \
  --height=60% --layout=reverse --border=rounded \
  --prompt='❯ ' --pointer='▶' --marker='✓' \
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

# -- nnn (terminal file manager) ----------------------------------------------
export NNN_OPTS="deH"
export NNN_COLORS="2136"
export NNN_FCOLORS="c1e2272e006033f7c6d6abc4"
export NNN_PLUG="f:fzcd;o:fzopen;p:preview-tui"

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
command -v kubectl       &>/dev/null && _compcache kubectl kubectl completion zsh
command -v gh            &>/dev/null && _compcache gh gh completion -s zsh
# Note: atac is intentionally NOT cached here — `atac completions zsh` writes a
# _atac FILE to a directory and prints a status line to stdout (it has no
# print-to-stdout mode), so `_compcache` would capture the message, not the
# completion (and litter the cwd). Skip it rather than break shell startup.
command -v aws_completer &>/dev/null && complete -C aws_completer aws
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
# the original takes. `du -sh` prints dust's help text, `rm -rf` is rejected by
# trash, `top -l1` is an unknown argument, `pip install X` becomes `uv pip install`
# and dies with "No virtual environment found" — and the quiet ones are worse:
# `ps aux` and `dig +short` silently ignore the argument and return
# differently-shaped output that looks correct. A human notices; a script or an AI
# agent parses the garbage. The TUI launchers (lg, lzd, hq, y, n, clip, claws) and
# the fzf-backed a/ff/rgf simply block when no terminal is attached.
#
# Claude Code and similar agents run commands through a NON-interactive shell that
# still sources this file, so they inherited all of it. Gate on interactivity (the
# principled test — scripts should get real tools too), plus the agent env vars as
# a backstop in case an agent ever runs `zsh -i`. Gating the whole section rather
# than a hazard list means aliases added later are covered automatically.
if [[ -o interactive && -z "$CLAUDECODE" && -z "$AI_AGENT" ]]; then
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
    alias rm="trash"

# Short aliases for modern tools (don't override builtins)
alias rg="rg"          # ripgrep (already the command name)
alias f="fd"           # fd (fast find)
alias sd="sd"          # sd (fast sed)
alias dft="difft"      # difftastic
alias y="rovr"         # rovr file manager (mouse-first TUI; nnn 'n' is the minimal fallback)
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
alias gha3="act3"

# -- Containers & Kubernetes --------------------------------------------------
alias lzd="lazydocker"
alias k="kubectl"
alias klog="stern"

# -- File Tools ---------------------------------------------------------------
alias md="leaf"
alias serve="miniserve --color-scheme-dark dracula -qr ."
alias csvp="csvlook"

# -- Media & Conversion -------------------------------------------------------
alias ytdl="yt-dlp"
alias ytmp3="yt-dlp -x --audio-format mp3"
alias resize="magick mogrify -resize"
alias ffq="ffmpeg -hide_banner -loglevel warning"
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
alias bench="hyperfine"
alias loadtest="oha"
alias par="parallel"
alias lint-sh="shellcheck"
alias fmt-sh="shfmt -w -i 4"

# -- Terminal Apps ------------------------------------------------------------
alias n="nnn -de"
alias prog="progress -m"
alias clip="clipse"    # clipboard-history TUI (replaces Raycast clipboard)

# -- Dracula theming for tools that theme via env/flags (config-file tools themed elsewhere) --
alias claws="claws --theme dracula"    # claws AWS TUI — built-in Dracula theme
# glab has no working pager CONFIG key — `glab config set glab_pager` is rejected by
# 1.113.0 despite being documented — but the binary carries a GLAB_PAGER env var.
# Best-effort: if glab ignores it nothing is lost, since no pager is set either way.
# It must live HERE and not in the justfile heredoc — `export X="y"` is invalid just
# syntax and breaks every recipe in ~/.justfile (#291).
export GLAB_PAGER="delta"
export D2_THEME=200                     # d2 diagrams — dark theme (d2 has no exact Dracula; 200 = Dark Mauve)
export D2_DARK_THEME=200

# -- Terminal launcher & search (replaces Raycast / Spotlight) ----------------
# Run these in the Ghostty quick terminal (global cmd+space) for a launcher feel.
# a: fuzzy-launch an installed macOS app
a() {
  local app
  app=$(mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null \
        | sort -u | fzf --prompt='launch ❯ ' --with-nth=-1 --delimiter=/) \
    && [[ -n "$app" ]] && open "$app"
}
# ff: find a file by name and open it
ff() {
  local file
  file=$(fd --type f --hidden --exclude .git 2>/dev/null \
         | fzf --prompt='files ❯ ' --preview 'bat --color=always {} 2>/dev/null | head -100') \
    && [[ -n "$file" ]] && open "$file"
}
# rgf: live content search (ripgrep + fzf with a bat preview)
rgf() {
  rg --line-number --no-heading --color=always "${1:-}" 2>/dev/null \
    | fzf --ansi --delimiter=: \
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
alias lfsinit="git-lfs-enable-repo"

# -- System -------------------------------------------------------------------
alias update="topgrade"
alias sysinfo="fastfetch"

else
    # ---- Non-interactive / agent shell ------------------------------------
    # Everything above is an interactive convenience and stays out of here, so
    # `pip`, `wget`, `du`, `ps` and friends resolve to the real binaries. The
    # replacements do not accept the originals' flags — `pip install X` becomes
    # `uv pip install X` and dies with "No virtual environment found", `wget
    # -qO- URL` throws — and the TUI launchers (lg, lzd, hq, y, n, clip, claws)
    # would block a shell with no terminal attached.
    #
    # One deliberate exception: dropping rm="trash" would make agent deletions
    # permanent. Keep the recoverable-delete net but tolerate the flags trash
    # rejects — strip options, pass the paths. `--` ends option parsing, as with
    # real rm; with no paths left it is a no-op rather than an error.
    rm() {
        local -a paths
        local arg endopts=0
        for arg in "$@"; do
            if (( endopts )); then
                paths+=("$arg")
            elif [[ "$arg" == "--" ]]; then
                endopts=1
            elif [[ "$arg" == -* ]]; then
                continue
            else
                paths+=("$arg")
            fi
        done
        (( ${#paths[@]} )) || return 0
        command trash "${paths[@]}"
    }
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
# Re-activating here puts mise back in front, so node, python, go and ruby resolve to the
# versions mise manages in BOTH kinds of shell. `mise activate` registers its precmd hook
# with `add-zsh-hook`, which is idempotent for a given function name, so running it twice
# does not double-fire it.
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# -- Terminal Welcome Screen --------------------------------------------------
# Colorful greeting on new terminal sessions (skip inside editor-integrated terminals).
# Also requires an interactive shell: sourcing this file from a script or an agent
# should not emit a banner into captured output.
if [[ -o interactive ]] && [[ "$TERM_PROGRAM" != "vscode" ]] && [[ -z "$INSIDE_EMACS" ]]; then
    if command -v fastfetch &>/dev/null; then
        fastfetch --logo small 2>/dev/null
    fi
    echo ""
    printf "\033[0;35m  %s\033[0m\n" "$(date '+%A, %B %d %Y  •  %H:%M')"
    echo ""
fi

MANAGED_ZSHRC
[[ "$DRY_RUN" == "true" ]] || success "$HOME/.zshrc managed block written (edits outside the markers are kept)"

fi  # shell

# =============================================================================
banner "Export Brewfile"

BREWFILE_DIR="$HOME/.config/brewfile"
mkdir -p "$BREWFILE_DIR"
BREWFILE="$BREWFILE_DIR/Brewfile"

info "Exporting Brewfile snapshot (with descriptions)..."
brew bundle dump --file="$BREWFILE" --force --describe 2>/dev/null || true
success "Brewfile exported to $BREWFILE"
echo "  -> Restore on a new machine: brew bundle install --file=$BREWFILE"

# -----------------------------------------------------------------------------
# Final Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
info "What was configured:"
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
echo "  [~/.config/starship]    Dracula prompt"
echo "  [~/.config/atuin]       Fuzzy search, local-only"
echo "  [leaf]                  Terminal Markdown previewer (live watch, fuzzy picker, Mermaid)"
echo "  [~/.config/yt-dlp]      Best quality, aria2c downloader"
echo "  [~/.config/gh-dash]     GitHub dashboard, Dracula theme"
echo "  [~/.config/glab-cli]    GitLab CLI (mirrors gh: SSH, micro, delta, aliases)"
echo "  [~/.config/stern]       K8s log tailing"
echo "  [~/.config/zellij]      Modern terminal multiplexer with Dracula theme"
echo "  [~/.config/mpv]         Video player (hardware accel, save position)"
echo "  [cliamp]                Music player (self-configured; point at ~/Media/music)"
echo "  [~/.config/git-cliff]   Changelog generator (conventional commits)"
echo "  [~/.newsboat]           RSS reader (vim keys, Dracula colors, starter URLs)"
echo "  [~/.config/ghostty]     GPU-accelerated terminal + quick-terminal launcher (cmd+space)"
echo "  [~/.config/sketchybar]  Dracula status bar (app, clock, battery/wifi/vpn/cpu/mem, Shottr menu)"
echo "  [~/.herald]             herald email + calendar (self-configured on first run)"
echo "  [~/.ollama]             Ollama local models (herald AI + croft pair --provider ollama)"
echo "  [~/.justfile]           Global task runner recipes (run them with: gj --list)"
echo "  [~/.config/brewfile]    Brewfile snapshot for reproducibility"
echo "  [~/.config/micro]       micro — Dracula, on-screen key menu, house indent rules"
echo "  [lazygit]               Dracula theme, delta pager"
echo "  [k9s]                   Dracula skin"
echo "  [Finder]                Hidden files, path bar, list view"
echo "  [macOS]                 Dock, keyboard, screenshots, Spotlight hotkey, Stage Manager"
echo "  [Claude Code]           Custom commands (/pr-review, /test-plan, /dep-audit, /quick-doc, /cleanup)"
echo ""
info "Optional Chrome extensions to install manually:"
echo "  - axe DevTools (accessibility testing)"
echo "  - React Developer Tools"
echo "  - Lighthouse"
echo "  - JSON Formatter"
echo ""
info "Terminal launcher & window management (replaces Raycast/Spotlight):"
echo "  - cmd+space           Ghostty quick terminal (Spotlight's cmd+space auto-disabled; log out/in)"
echo "  - a                   fuzzy-launch an app        ff   find & open a file"
echo "  - rgf <pattern>       search file contents        s <q>  Spotlight-index search"
echo "  - clip                clipboard history (clipse)"
echo "  - taproom             browse/install Homebrew;    k9s / lazydocker  containers"
echo ""
info "Chezmoi quickstart (dotfile backup):"
echo "  chezmoi init                          # Initialize"
echo "  chezmoi add ~/.zshrc                  # Track dotfiles"
echo "  chezmoi cd && git remote add origin <repo>  # Link to git repo"
echo "  chezmoi update                        # Pull on new machine"
echo ""
info "Tips:"
echo "  - Keep ~/Desktop empty — use 'ff' / 's' (mdfind) to find files from the terminal"
echo "  - Disable iCloud Desktop & Documents: System Settings > Apple ID > iCloud > iCloud Drive > Options"
echo "  - hyperfine: benchmark commands with 'hyperfine \"command1\" \"command2\"'"
echo "  - oha: load test with 'oha -n 1000 -c 50 http://localhost:3000'"
echo "  - watchexec: watch files with 'watchexec --exts ts,tsx -- npm test'"
echo "  - pv: add progress bars with 'pv largefile.tar.gz | tar xz'"
echo ""
# =============================================================================
# GENERATE DESKTOP DOCS (checklist, shortcuts, toolkit summary)
# Regenerated fresh each run so they always match the current toolset.
# =============================================================================
if [[ "$DRY_RUN" != "true" ]]; then
    DESKTOP="$HOME/Desktop"
    mkdir -p "$DESKTOP"
    info "Writing setup docs to ~/Desktop..."

    # ---- 1. POST_SETUP_CHECKLIST.md ----
    cat > "$DESKTOP/POST_SETUP_CHECKLIST.md" <<'CHECKLIST_EOF'
# Post-Setup Checklist

Everything the setup script could **not** do for you — credentials, external
accounts, and macOS permissions that are (deliberately) unscriptable. Work down
the list, then delete this file.

## macOS permissions & settings
- [ ] **Accessibility** — grant to **Ghostty** and **SketchyBar**: System Settings -> Privacy & Security -> Accessibility. (Ghostty: global launcher hotkey; SketchyBar: front-app observation + click actions.)
- [ ] **Screen Recording** — grant to **Shottr**: System Settings -> Privacy & Security -> Screen Recording. Without it, screenshots capture only the desktop/menu bar, not app windows.
- [ ] **Automation** — the first time you click the SketchyBar clock (it types `herald` into a Ghostty quick terminal), approve the prompt to let it control **System Events**. If the click does nothing, confirm SketchyBar also has Accessibility (above).
- [ ] **Reminders** — run `reminders show-lists` once and approve the prompt. macOS gates Reminders behind a per-app consent dialog that only appears on first use, and it is granted to the **terminal** (Ghostty), not to `reminders` itself — so approve it from the terminal you actually use. Until then every `reminders` command returns an empty list rather than an error, which is easy to mistake for "no reminders". Claude uses this tool whenever you say "remind me".
- [ ] **Spotlight's cmd+space** is disabled by the script (freed for the Ghostty quick terminal) — **log out/in** for it to take effect. To keep Spotlight on cmd+space instead, re-enable it (System Settings -> Keyboard -> Keyboard Shortcuts -> Spotlight) and change the Ghostty bind to `global:cmd+backquote` in `~/.config/ghostty/config`.
- [ ] **Menu bar auto-hide** is set by the script (`_HIHideMenuBar`) so SketchyBar owns the top — **log out/in (or restart)** for it to take effect. If it doesn't stick, toggle System Settings -> Control Center -> "Automatically hide and show the menu bar" -> Always.

## Email + calendar — herald (one app, self-configured)
- [ ] Run `herald` and follow its onboarding to add both accounts + their calendars:
  - **iCloud (personal):** create an **app-specific password** at appleid.apple.com -> Sign-In & Security -> App-Specific Passwords; herald uses it for IMAP/SMTP + iCloud CalDAV.
  - **Gmail (work):** add the Gmail account in herald (OAuth or an app password) and its Google CalDAV calendar.
- [ ] Start the background server so the **Claude MCP** (and mutations) work: `herald serve -config ~/.herald/conf.yaml` (add it to a login item / launchd if you want it always on). Read-only MCP works after the first sync.
- [ ] **No Anthropic API key is needed to use herald with Claude.** Reading or searching your mail/calendar from Claude Code goes through herald's MCP (set up above) and rides your existing `claude` login — no key. Separately, herald's *own* built-in AI (semantic search, triage, compose styler) is **optional** and runs on local **Ollama** models — setup installs Ollama, runs it as a login service on `127.0.0.1:11434`, and pulls `gemma3:4b` (chat/summaries) plus `nomic-embed-text-v2-moe` (the embedding model that powers semantic search), so it works offline with no key once you enable it in herald's onboarding (pick the **Ollama** provider + the `gemma3:4b` model, and `nomic-embed-text-v2-moe` for embeddings; `ollama pull <model>` adds others). Point it at an `ANTHROPIC_API_KEY` instead only if you'd rather that AI run on Claude.

## Google Workspace CLI — gws
- [ ] Authorize `gws`: run `gws auth setup` (walks you through a Google Cloud OAuth project — setup installs the `gcloud` CLI it shells out to) then `gws auth login`. After that, Claude can work with your Workspace via `gws` (structured JSON) — it's instructed to confirm before sending/sharing/deleting/modifying anything.
- [ ] **Scope the OAuth fence — this, not the skills, is what actually limits access.** The Claude skills installed below only give Claude *recipes* for Drive/Docs/Slides/Sheets/Forms; they do **not** restrict what `gws` can call. Any scope you grant during `gws auth setup` is reachable regardless of which skills exist. To keep Claude out of email/calendar/chat entirely, authorize **only** the Drive, Docs, Slides, Sheets, and Forms scopes there.
- [ ] The Drive/Docs/Slides/Sheets/Forms **Claude skills are pre-installed** (`~/.claude/skills/gws-*` plus the matching `recipe-*`); Gmail/Calendar/Chat/Meet skills were deliberately left out. To add more later, copy them from github.com/googleworkspace/cli (`skills/`).

## Accounts, keys & first-run
- [ ] **Apple Passwords CLI (`apw`):** run `brew services start apw`, then `apw auth`, and install the **iCloud Passwords browser extension**.
- [ ] **Mullvad:** `mullvad account login <ACCOUNT_NUMBER>` (CLI is bundled with the app at `/usr/local/bin/mullvad`).
- [ ] **starlit** (weather): `starlit --setup` and paste a free OpenWeatherMap API key.
- [ ] **surge** (download manager): the daemon service was installed by the script (if it didn't prompt, run `surge service install`). Install the browser extension so browser downloads route to surge: **Firefox** — one-click from the Mozilla Add-ons store; **Chrome** — download `extension-chrome.zip` from the [latest release](https://github.com/SurgeDM/Surge/releases) and load-unpacked at `chrome://extensions` (Developer mode). Then pair it with `surge service token` (or TUI → Settings → Extension).
- [ ] **glab** (GitLab, only if you use it): `glab auth login` to authenticate against gitlab.com or a self-managed instance. Already configured with SSH + micro + delta and the same alias names as gh (mapped to merge requests).
- [ ] **GitHub CLI (`gh`):** run `gh auth login` (pick SSH or HTTPS). The whole PR workflow (`gh pr`, `gh issue`, `gh pm`) and the `gh ssh-key add` step below all need it — fresh machines start logged out.
- [ ] **AWS auth:** the CLIs and TUIs (`awscli`, `granted`/`assume`, `steampipe`, `stu`/`e1s`/`e2c`, `s5cmd`) plus the AWS MCP servers are installed but have no credentials yet. SSO: `aws configure sso` (or `granted sso populate` then `assume <profile>`). Static keys: `aws configure`. If you'll query with SQL: `steampipe plugin install aws`.
- [ ] **atuin history sync** (optional — keeps shell history in sync across the MacBook + Mac mini): `atuin register` (or `atuin login` on the 2nd machine), then `atuin sync`. Local searchable history (`Ctrl+r`) works without an account.
- [ ] **MCP servers:** export tokens your Claude Code MCP servers need, e.g. `export GITHUB_TOKEN=...` (and `AWS_REGION` / `AWS_PROFILE` for the AWS servers). Requires `claude auth login` at least once.
- [ ] **infracost** (IaC cost estimates): run `infracost auth login` for a free API key — `infracost breakdown` errors with "No INFRACOST_API_KEY" until then.
- [ ] **borgmatic backups:** the setup scaffolds `~/.config/borgmatic/config.yaml`. Set `repositories`, store the passphrase in Keychain (`security add-generic-password -a "$USER" -s borg-passphrase -w`), run `borgmatic init --encryption repokey-blake2`, check with `borgmatic create --dry-run`, then enable a daily run (e.g. a LaunchAgent calling `borgmatic --verbosity -1`). ClamAV's virus DB downloads itself in the background after setup.
- [ ] **Claude AI in croft:** `croft pair` (the AI navigator in your primary IDE) defaults to `--provider claude`, which hands off to your existing `claude` CLI — so it just works on whatever auth that already has (a Claude Pro/Max subscription **or** an API key), no separate `ANTHROPIC_API_KEY` required. Want a fully local model with no key at all? Ollama is installed and running — use the `gemma3:4b` that setup already pulled (`croft pair --provider ollama --model gemma3:4b`), or `ollama pull qwen3-coder:30b` first for a heavier coding-tuned model. An Anthropic API key is **optional** here — the only thing that uses one is the `llm` CLI, and `llm` itself is optional: if Claude Code and the Claude desktop app already cover you, you can skip it entirely. If you do want `llm` for one-off prompts (e.g. `> ! llm …` from micro's command bar) or shell scripting, run `llm keys set anthropic` — setup already installs the plugin (via uv) and sets the default model to `anthropic/claude-sonnet-4-5`. (Email/calendar AI is built into **herald** — configured separately above.)
- [ ] **croft** (primary IDE): installed from git `main` via cargo — run `croft` in a project to open the workspace; re-run `cargo install --git https://github.com/vitali87/croft.git --locked` to upgrade.
- [ ] **AI side-pane:** `zellij --layout dev` opens your editor + a Claude Code pane side by side (the strongest AI workflow).
- [ ] **chezmoi:** `chezmoi init <your-dotfiles-repo>` to bring these configs under version control across the MacBook + Mac mini.
- [ ] **tiki** (notes): your personal notes repo is pre-created and git-initialized at `~/Documents/notes`. Run `cd ~/Documents/notes && tiki` to start. Claude can manage tikis there — its skill is installed at `~/.claude/skills/tiki/` (CRUD via `tiki exec`, quick-capture via `echo "note" | tiki`).
- [ ] **cliamp** (music): drop music into `~/Media/music`, then run `cliamp ~/Media/music` (or set the folder in its UI). Streaming (YouTube/SoundCloud/Spotify/radio) + EQ + 20+ visualizers are built in.
- [ ] **leaf** (Markdown): if tab-completion isn't working, run `leaf --auto-complete` and restart your shell (the script attempts this automatically).

## Worth knowing (nothing to do — 2 minutes)
- [ ] **Global task recipes** — this setup wrote `~/.justfile` with machine-wide one-liners (`flush-dns`, `docker-clean`, `ports`, `standup`, `loc`, `ip`, `ds-clean`, …). Plain `just` will not find it: it searches upward from the current directory, so anywhere outside `$HOME` you get `error: no justfile found`. Use the **`gj`** alias: run **`gj --list`** once to see what is there, then e.g. `gj flush-dns`. Every recipe is listed in `docs/SHORTCUTS.md`.

## Standard machine setup
- [ ] Generate an SSH key if needed: `ssh-keygen -t ed25519 -C "you@example.com"` and `gh ssh-key add ~/.ssh/id_ed25519.pub`.
- [ ] Enable **FileVault** and the **macOS Firewall** (System Settings -> Privacy & Security / Network).
- [ ] Open **OrbStack** once to finish Docker setup.
- [ ] `ngrok config add-authtoken <TOKEN>`.
CHECKLIST_EOF

    # ---- 2. KEYBOARD_SHORTCUTS.md ----
    cat > "$DESKTOP/KEYBOARD_SHORTCUTS.md" <<'SHORTCUTS_EOF'
# Keyboard Shortcuts

## Launcher & search (Ghostty quick terminal)
| Keys / command | Action |
|------|--------|
| `cmd + space` | Toggle the Ghostty quick terminal (global dropdown) |
| `a` | Fuzzy-launch an installed app |
| `ff` | Find a file by name and open it |
| `rgf <pattern>` | Live content search (ripgrep + fzf) |
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

## Claude AI
| Where | How |
|-------|-----|
| Side-pane (best) | `zellij --layout dev` — editor + Claude Code panes |
| One-shot pipe | `llm 'explain this' < file` — or `> ! llm …` from micro's command bar |
| herald | Built-in AI triage/summaries/compose styler + MCP server for Claude |

## Terminal multiplexer & tools
| Keys | Action |
|------|--------|
| `Ctrl + r` | atuin history search (fuzzy, across machines) |
| `Ctrl + t` | fzf file finder · `Alt + c` fzf cd |
| zellij `Ctrl + p` then `n` | New pane (see zellij status bar for modes) |
| lazygit / lazydocker / lazysql / lazynpm / lazyssh / lazyrsync | Full-screen TUIs (arrows + on-screen keys) |
| `y` rovr · `n` nnn | File managers |
| `cliamp` | Terminal music player (Winamp-style) — playback, EQ, cycle visualizers |
| `atac` | API client TUI (or `atac request send <coll>/<req>` headless) |

## SketchyBar (click actions)
| Item | Click |
|------|-------|
| Clock | Opens herald (email + calendar) in a Ghostty quick terminal |
| VPN pill | Toggles `mullvad connect` / `disconnect` |
| Bluetooth | Toggles Bluetooth power |
SHORTCUTS_EOF

    # ---- 3. TOOLKIT_SUMMARY.md ----
    cat > "$DESKTOP/TOOLKIT_SUMMARY.md" <<'SUMMARY_EOF'
# Toolkit Summary

A terminal-first macOS setup: GUI apps replaced with TUI/CLI equivalents wherever
it doesn't cost real capability. Below: what each tool is for, then how it fits
together.

## Editor & AI
- **croft** — VS Code-style terminal IDE; the **primary editor** (`croft pair` for the AI navigator). **Visual Studio Code** (`code .`) is the GUI editor alongside it, preconfigured with Dracula and the same formatters. **micro** is the `EDITOR` for git/gh/lazygit commit messages and quick edits (non-modal, Dracula, on-screen key menu, trailing whitespace stripped on save).
- **Claude Code (`claude`)** — agentic coding in the terminal; hosts the MCP servers. Best via `zellij --layout dev` (editor + Claude pane).
- **Claude in croft** — croft's `croft pair` AI navigator (primary IDE) defaults to `--provider claude`, riding your existing `claude` CLI auth (subscription or key, no separate `ANTHROPIC_API_KEY`); `--provider ollama` runs a local model with no key. The one path that uses an Anthropic key is the **`llm`** CLI (`llm-anthropic`) — and it's optional: reach for it only when you want Claude in a shell pipe or a `> ! llm …` one-off from micro's command bar, then run `llm keys set anthropic`. **herald** integrates with Claude two ways, neither needing a key: Claude Code reads and searches your mail/calendar through herald's **MCP** (it rides your `claude` login), and herald's *own* built-in AI (triage, summaries, compose styler, semantic search) is optional and runs on local **Ollama** models that setup installs, runs as a login service, and seeds with `gemma3:4b` (chat) + `nomic-embed-text-v2-moe` (embeddings).

## Status bar & launcher
- **SketchyBar** — Dracula status bar: app, clock, battery, wifi, volume, cpu, mem, bluetooth, VPN.
- **Ghostty quick terminal** — global cmd+space dropdown that hosts the launcher.
- **Launcher functions** — `a` (apps), `ff` (files), `rgf` (contents), `s` (Spotlight index), `clip` (clipboard via clipse).

## Files, data & shell
- **rovr** (file manager, nnn fallback), **eza/bat/fd/ripgrep/zoxide/dust/duf/sd** (modern coreutils), **fzf** (fuzzy), **atuin** (history), **starship** (prompt), **zellij** (multiplexer), **yazi**->rovr.
- **wiper** — interactive disk cleanup (Trash-safe). **taproom** — Homebrew TUI. **has** — tool/version checker.

## Dev workflow
- **lazygit / lazydocker / lazysql / lazynpm / lazyssh / lazyrsync / lazyenv** — full-screen TUIs for git, containers, SQL, npm, SSH, rsync, `.env` files.
- **gh** (GitHub) / **glab** (GitLab) — repo/PR/MR CLIs; glab mirrors gh's aliases (→ merge requests). **scc** — code counter (LOC + complexity + COCOMO). **keyward** — SSH-key manager + security audit.
- **ATAC** — terminal API client (TUI + scriptable CLI) replacing Bruno; **hurl/xh/curlie/grpcurl** for one-shot + tests.
- **harlequin / pgcli / mycli / usql / sq** — database CLIs/TUIs (replaced DBeaver).
- **d2 / mermaid** — diagrams as code (replaced draw.io). **qalc** — calculator. **vhs** — scripted terminal recordings. **doxx** — .docx viewer. **manly** — explain a command's flags. **LibreOffice/poppler/office-py** — headless validate & render .pptx/.xlsx/.docx (Claude's doc-check stack).

## Communication & knowledge
- **herald** — terminal email **+** calendar in one app (Gmail work + iCloud personal, unified CalDAV), with built-in AI triage/summaries and an MCP server for Claude.
- **tiki** — Markdown workspace (tasks/docs/kanban/wiki) replacing Notion.
- **gws** (google-workspace-cli) — Drive/Gmail/Docs/Sheets/Calendar from the terminal (structured JSON; Claude's Workspace surface).
- **newsboat** — RSS. **cliamp** — music. **starlit** — weather. **surge** — download manager (browser-download capture, alongside aria2). **bmm** — bookmarks.

## Infra, cloud & security
- **rclone** — cloud sync (replaced Cyberduck + Google Drive). **borg** — backups.
- **kubectl/k9s/stern/dive**, **awscli/granted**, **opentofu/terraform-docs/checkov/trivy**, **gitleaks/detect-secrets/sops/age**.
- **apw** — Apple Passwords from the CLI. **mullvad** CLI. **LuLu** firewall (GUI).

## How it fits together
The whole thing is one keyboard-driven loop. **cmd+space** drops the Ghostty quick
terminal from anywhere; `a`/`ff`/`rgf`/`s` make it a launcher and search bar, so
Spotlight/Raycast aren't needed. **SketchyBar** shows
state (VPN, battery) — the bar's clock even opens **herald**, and its VPN
pill drives the **mullvad** CLI. Editing is **croft** (micro for quick edits); the agent is **Claude Code**,
which reuses the same **MCP servers** the setup migrated over. The script writes
these configs to `~/.config`; use **chezmoi** (`chezmoi add`, with **cheznav** as its
TUI) to track them in git and keep the MacBook and Mac mini in sync — that step is
yours, the script doesn't auto-add them. Because almost everything is a CLI/TUI, the same tools work
locally, over SSH, and — where it matters — can be driven by Claude Code
(`atac`, `hurl`, `xh` are on its allowlist). GUI survivors are only the irreducible
ones: Ghostty, Chrome, the container runtime (OrbStack), security tools that need a
GUI (LuLu, Mullvad), and inherently-visual apps (Shottr, Skim), plus the Claude app.

## Full tool reference
This summary is a curated overview, not the whole toolbox. For every installed
tool — a description of what it's for plus usage examples — see the companion
**TOOL_REFERENCE.md** on your Desktop.
SUMMARY_EOF

    # ---- 4. TOOL_REFERENCE.md ----
    cat > "$DESKTOP/TOOL_REFERENCE.md" <<'REFERENCE_EOF'
# Tool Reference

Every command-line tool, TUI, and app this setup installs, grouped by what you
reach for it to do. Each entry says what the tool is, what it replaces or when
you'd use it, and a few worked examples. Written so someone new to the machine
can be productive without already knowing the toolkit.

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

### `croft` — Croft
A Rust-built, VS Code-style IDE that lives entirely in the terminal — panes for a file tree, editor, and terminal in one TUI. It's the primary editor in this setup, reached for over micro when you want a fuller IDE experience (multi-pane layout, mouse support) without leaving the terminal. Run it from inside a project directory so it picks up the right root; `croft pair` adds an AI navigator alongside your normal editing session for pair-programming style assistance.

```bash
# launch croft in the current project
croft
# launch with the AI pairing navigator active
croft pair
```

Croft's extension system is declarative `extension.toml` manifests — languages, LSP servers, themes, debug adapters, test runners, and MCP sidecars — browsable at `Cmd+Shift+X` and installable by dropping a manifest in `~/.config/croft/extensions/<id>/`. There is deliberately no marketplace; the MCP catalog is curated, signed, and hash-checked. Because manifests are pure data, croft has **no EditorConfig support** — indentation is a language default (2 spaces YAML, 4 otherwise) with a per-buffer status-bar override. Use VS Code below on repos where `.editorconfig` matters.

### `code` — Visual Studio Code
The GUI editor, secondary to croft. It exists for the cases a terminal IDE still loses at — long refactors across many tabs, graphical diffs and merge conflicts, extension-backed previews — and for `.editorconfig` repos, which croft ignores. It is preconfigured to agree with the terminal rather than fight it: Dracula theme, format-on-save, ruff for Python, prettier for web, shfmt for shell, tabs for Go, LF endings.

Settings live at `~/Library/Application Support/Code/User/settings.json` and are **merged, not overwritten** — your own keys and anything Settings Sync pulls down win over the defaults, so re-running the setup script is safe.

```bash
# open the current directory
code .
# open a specific file at a line
code -g src/main.ts:42
# list what's installed
code --list-extensions
```

> Tip: Start it from the project root, not a subdirectory — croft indexes the tree from wherever it's launched.

### `micro` — micro
A non-modal terminal editor: it behaves the way a GUI editor does, so there are no modes to enter or leave. `Ctrl+S` saves, `Ctrl+Q` quits, `Ctrl+C`/`Ctrl+V` use the system clipboard. It is the `$EDITOR` for git, gh, lazygit and leaf, and the right tool for a quick edit; croft is the full IDE. The **key menu** along the bottom lists the bindings as you work, and `Ctrl+G` opens the complete reference — no cheatsheet needed.

```bash
# open a file
micro src/main.rs
# jump straight to a line
micro src/main.rs +42
# open the command bar inside the editor, e.g. > set tabsize 4
```

> Configured with the Dracula theme, the key menu on, 2-space indents (4 for Python, real tabs for Go and Makefiles), and trailing whitespace stripped on save. Change anything from inside the editor with `> set <option> <value>` — it persists to `~/.config/micro/settings.json`, and re-running the setup script merges new defaults without discarding your changes.

### `claude` — Claude Code
Anthropic's agentic coding CLI: it reads your codebase, edits files, runs commands, and can operate autonomously on multi-step tasks, all from the terminal. It's also the host for this machine's MCP servers (filesystem, GitHub, AWS, etc.), so it can reach beyond the local repo when needed. Run it inside a repo so it has real project context; it pairs well with `zellij --layout dev`, which opens it next to your editor.

```bash
# start an interactive session in the current repo
claude
# run a one-off prompt non-interactively
claude -p "explain what this function does" < src/utils.ts
```

> Tip: Keep a `CLAUDE.md` in the repo root — Claude Code reads it automatically for project-specific conventions.

### `llm` — LLM CLI
Simon Willison's command-line tool for one-shot LLM prompts, piping text through models, and generating embeddings, without opening a chat UI. The Anthropic plugin ships with this setup and defaults to `anthropic/claude-sonnet-4-5`, and its plugin ecosystem covers most other providers too. It shines in shell pipelines — summarizing command output, transforming file contents, or scripting small AI steps into a larger workflow.

```bash
# one-shot prompt
llm "explain the difference between TCP and UDP"
# pipe a file through a prompt
cat error.log | llm "what's the root cause of this error?"
# start a multi-turn conversation
llm chat
```

> Tip: Set your key once with `llm keys set anthropic`; after that the model is available to every `llm` invocation without extra flags.

### `ollama` — Local LLM Runtime
Runs open-weight LLMs entirely on your Mac — no API key, no data leaving the machine. Setup installs it, runs it as a login service on `127.0.0.1:11434`, and pulls `gemma3:4b` (a small, fast general chat model) plus `nomic-embed-text-v2-moe` (the embedding model behind semantic search). It's the local backend for **herald**'s built-in AI (triage, summaries, compose styler, semantic search) and for `croft pair --provider ollama`; both talk to that same endpoint. Models live under `~/.ollama`, and there's no config file to maintain.

```bash
# list installed models
ollama list
# pull another model (e.g. a coding-tuned one for croft pair)
ollama pull qwen3-coder:30b
# quick one-off prompt against a local model
ollama run gemma3:4b "summarize this in one line: ..."
```

> Tip: The server runs as a login service. `brew services stop ollama` frees its RAM when you're not using local AI; `brew services start ollama` brings it back.

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
A terminal multiplexer (splitting one terminal into panes, tabs, and persistent sessions) that's more discoverable than tmux — it shows keybindings on-screen and ships with layout files instead of requiring a custom config to get useful pane arrangements. Reach for it whenever you want a session that survives disconnects, or a fixed layout for repeated work. The `dev` layout in this setup opens an editor pane and a Claude Code pane side by side.

```bash
# start with the pre-built dev layout (editor + Claude Code)
zellij --layout dev
# list running sessions
zellij list-sessions
# reattach to a detached session
zellij attach <session-name>
```

> Tip: `Ctrl+g` locks/unlocks keybinding mode — if keys stop doing anything inside a pane, you've probably entered a plugin's own input mode.

### `nu` — Nushell
A shell where pipelines pass structured tables and typed data instead of raw text, so commands like filtering, sorting, and reformatting output work like a query language rather than a chain of `grep`/`awk`/`cut`. It's not the default login shell here — zsh still owns that — but it's the tool to reach for when you're wrangling CSV, JSON, or command output that plain text pipes make painful. Drop into it for a data-heavy task, then drop back out to zsh.

```bash
# start a nushell session
nu
# list files as a sortable table, filtered by size
ls | where size > 1mb
# parse JSON output and pull a field
open package.json | get dependencies
```

> Tip: `open` auto-detects file type (JSON, TOML, CSV, etc.) and parses it into a table — no separate `jq`/`yq` needed inside nu.

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

### `parallel` — GNU Parallel
Runs shell commands concurrently across a list of inputs, spreading work across CPU cores instead of processing one item at a time in a `for` loop. It's a major speedup over sequential loops for embarrassingly parallel tasks — converting a folder of images, hitting an API for a list of IDs, or running the same script over many files. Reach for it whenever a loop's iterations don't depend on each other.

```bash
# run a command once per argument
parallel echo ::: alice bob carol
# convert every jpg to png, 4 at a time
ls *.jpg | parallel -j4 convert {} {.}.png
# download a list of URLs in parallel
parallel -a urls.txt curl -O
```

> Tip: `{}` is replaced with the full input and `{.}` with the input minus its extension — useful for generating output filenames.

### `has` — has
A tiny checker that tells you whether a given CLI tool is installed and, if so, which version — useful for verifying a machine or CI environment has the prerequisites a project expects before you dive into setup. It replaces manually running `<tool> --version` and eyeballing whether it errored. Reach for it at the start of onboarding a new machine or debugging "works on my machine" issues.

```bash
# check whether node is installed and its version
has node
# check multiple tools at once
has node python go docker
```

> Tip: `has` exits non-zero if a tool is missing, so it's safe to use directly in a setup script's preflight check: `has docker || echo "install docker first"`.

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

### `terminal-notifier` — terminal-notifier
Posts a native macOS notification (the same banners/alerts you get from any Mac app) from a shell command or script, so you can find out a long-running task finished without staring at the terminal. It replaces manually checking back on a build or leaving a terminal tab focused just to catch completion. Use it at the end of long commands — builds, deploys, test suites — so you get pulled back at the right moment.

```bash
# fire a notification with a title and message
terminal-notifier -title "Build" -message "Build complete"
# notify after a long-running command finishes
npm run build; terminal-notifier -message "npm build finished"
# include a sound
terminal-notifier -message "Deploy done" -sound default
```

> Tip: Chain it with `;` (not `&&`) if you want the notification even when the preceding command fails — pair it with `$?` in the message to report success/failure.

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

### `rovr` — rovr
A mouse-first TUI file manager: browse, preview, copy, move, and delete files from a full-screen terminal UI instead of typing every `mv`/`cp` by hand. It's the primary file manager in this setup (with `nnn` kept as a minimal keyboard-only fallback). Reach for it when you want to visually navigate and reorganize a messy directory rather than scripting the operations.

```bash
# launch rovr in the current directory
rovr
# launch rovr in a specific directory
rovr ~/Downloads
```

### `nnn` — nnn
A tiny, extremely fast, keyboard-driven TUI file manager — no mouse needed, minimal dependencies, near-instant startup even on huge directories. It's kept as the lightweight fallback to `rovr` for when you want pure keyboard navigation or are on a constrained/remote session. Navigate with arrow keys or hjkl, open files with Enter, and quit with `q`.

```bash
# launch nnn in the current directory
nnn
# launch nnn with the built-in file preview plugin
nnn -e
```

### `wiper` — wiper
An interactive, ncdu-style disk-usage explorer that lets you drill into directories, see what's eating space, and delete the offenders — but unlike raw `rm`, everything it removes goes to the macOS Trash so it's recoverable. Use it when your disk is filling up and you need to visually hunt down large files or directories before nuking them.

```bash
# interactively explore disk usage from the current directory
wiper
# explore disk usage starting at a specific path
wiper ~/Downloads
```

> Tip: because deletions go to Trash, `wiper` is safe to use aggressively — empty the Trash afterward once you're sure.

### `npkill` — npkill
Scans a directory tree for stray `node_modules` folders and lets you interactively select and delete them to reclaim disk space — a common problem after years of JS project churn. Use it periodically on `~/Code` to clean up old, abandoned project dependencies without deleting the projects themselves.

```bash
# scan the current directory for node_modules folders
npkill
# scan a specific directory
npkill -d ~/Code
```

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

### `7z` [p7zip] — 7-Zip CLI
The command-line port of 7-Zip, capable of creating and extracting zip, 7z, tar, gzip, and many other archive formats with strong compression ratios. Reach for it when `ouch` doesn't cover a format, when you need 7z's especially tight compression, or when working with password-protected/encrypted archives.

```bash
# create a .7z archive from a folder
7z a archive.7z folder/
# extract an archive into the current directory
7z x archive.zip
# list the contents of an archive
7z l archive.7z
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

### `watchman` — watchman
A background file-watching service that some JavaScript toolchains (React Native, Jest, Metro) use internally to detect file changes efficiently; you rarely invoke it by hand, but it's what's actually powering "watch mode" under the hood in those tools. You'd only touch it directly to debug a stuck watch or clear its state.

```bash
# start watching a project directory
watchman watch ~/Code/my-app
# list all directories currently being watched
watchman watch-list
# stop watching a directory
watchman watch-del ~/Code/my-app
```

### `dockutil` — dockutil
A command-line tool for adding, removing, and querying macOS Dock items, letting you script your Dock layout instead of dragging icons around by hand. Use it in a setup script to reproducibly pin the apps you want on a fresh machine, or to strip out Apple's default clutter.

```bash
# add an app to the Dock
dockutil --add /Applications/Ghostty.app
# remove an app from the Dock by name
dockutil --remove 'Safari'
# list current Dock items
dockutil --list
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

### `tree` — tree
Prints a directory structure as a clean, indented ASCII tree, giving you an at-a-glance overview of a project's layout that's far easier to read than a flat `ls -R`. Use it to document a project structure, check what a scaffold generated, or quickly orient yourself in an unfamiliar repo.

```bash
# print the directory tree from the current location
tree
# limit the depth to 2 levels
tree -L 2
# include hidden files, excluding a specific directory
tree -a -I 'node_modules'
```

### `nano` — nano
A simple, beginner-friendly terminal text editor with on-screen keybinding hints, used as the quick fallback when you just need to edit a file without loading a full IDE. micro is the better default for this now; nano remains for muscle memory and remote boxes — a config tweak, a commit message, a quick note — where remembering modal commands would slow you down.

```bash
# open a file for editing
nano file.txt
# open a file at a specific line number
nano +42 file.txt
```

> Tip: the key shortcuts are shown at the bottom of the screen — Ctrl+O saves, Ctrl+X exits.


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

### `miller` [mlr] — Record Processor for CSV/TSV/JSON
Miller is like awk, sed, cut, and jq combined, but name-aware and format-aware across CSV, TSV, and JSON. It processes records by field name instead of column position, so scripts stay readable and survive reordered columns. Reach for it when you need to filter, join, or aggregate tabular data faster than pandas but with more structure than raw awk.

```bash
# convert CSV to JSON
mlr --icsv --ojson cat data.csv
# filter rows and keep only some columns
mlr --csv filter '$amount > 100' then cut -f name,amount data.csv
# compute grouped statistics
mlr --csv stats1 -a sum,mean -f amount -g category data.csv
```

### `csvkit` [csvcut/csvgrep/csvstat/csvjson] — CSV Utility Suite
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

### `sq` — Database Swiss-Army Query Tool
The "jq for databases" — sq queries SQLite, Postgres, MySQL, and even CSV/Excel files through one consistent interface and can output to JSON, CSV, or another database. It's the tool to reach for when you need to poke at a database from the terminal, or move data between a spreadsheet and a real database, without switching clients. Sources are registered once and referenced by a short `@handle`.

```bash
# register a CSV file as a queryable source
sq add ./employees.csv --handle @emp
# query it (SLQ syntax)
sq '@emp | .name, .salary | .salary > 50000'
# register and query a Postgres database
sq add 'postgres://user@host/db' --handle @mydb
sq '@mydb.users'
```

> Tip: `sq ls` lists all registered sources so you don't forget your handles.

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

### `glab` — GitLab CLI
GitLab's equivalent of `gh`, mirroring its ergonomics and alias conventions but mapped onto merge requests instead of pull requests. Use it exactly like `gh` when a project lives on GitLab rather than GitHub, so the same trunk-based muscle memory applies. Handy for teams that split repos across both platforms.

```bash
# create a merge request referencing an issue
glab mr create --title "fix(api): handle nulls" --description "Closes #12"
# list open issues
glab issue list
# check out a merge request locally
glab mr checkout 45
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

### `git-delta` [delta] — Syntax-Highlighting Diff Pager
A syntax-highlighting pager for git diffs that renders side-by-side views with line numbers, replacing git's plain-text diff output. It's wired in here as git's default pager, so `git diff` and `git log -p` are readable by default — no extra flags needed day to day. Call it directly when piping a diff from somewhere else.

```bash
# pipe a diff through delta directly
git diff | delta
# compare two arbitrary files
delta file_old.py file_new.py
```

### `difftastic` [difft] — Structural Diff Tool
A structural, syntax-aware diff tool that compares parsed syntax trees instead of raw text lines, so it doesn't get confused by reformatting or reordered code that a line-based diff would flag as a huge change. Reach for it when a normal diff is noisy — e.g., after a formatter run — and you want to see what actually changed logically.

```bash
# compare two files structurally
difft old.py new.py
# use it as git's diff tool for one command
git difftool --extcmd=difft HEAD~1
```

### `git-cliff` [git cliff] — Changelog Generator
Generates a changelog automatically from conventional-commit history, grouping entries by type (feat, fix, chore, etc.) instead of hand-writing release notes. It relies on the commit message discipline this workflow already enforces, so a changelog is basically free. Run it before cutting a release or to preview what a release would contain.

```bash
# generate a full changelog
git cliff -o CHANGELOG.md
# preview only unreleased commits
git cliff --unreleased
# generate a changelog for a specific tag range
git cliff v1.0.0..v1.2.0
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

### `git-lfs` [git lfs] — Large File Storage
Git Large File Storage replaces large binaries (PSDs, datasets, video) in the repo with lightweight text pointers, storing the actual content separately so clones and fetches stay fast. Use it for any file type that's large and changes often enough that Git's normal delta compression doesn't help.

**On this machine, LFS is enabled per repository — `git lfs install` is not enough.** This setup points `core.hooksPath` at a global hooks directory, and git-lfs is `core.hooksPath` aware: `git lfs install` writes its hooks *globally*, so `git lfs pre-push` would run on every push in every repo, including ones with no LFS objects. Against a GitHub wiki remote that fails outright and blocks the push, with an error that names authentication rather than LFS. So the global LFS hooks are removed, and each repo opts in instead (#311).

**If you skip this step in a repo that uses LFS, `git push` would upload the pointer files without the objects behind them** — so the `pre-push` hook refuses the push and tells you to run this, rather than letting it succeed and leave the remote broken (#313). Run it once per LFS repo, right after `git lfs track`. To push LFS objects some other way (CI, a mirror), turn the check off with `git config dev-setup.lfsguard false`.

```bash
# enable LFS hooks for THIS repo (once per repo — do this first)
git-lfs-enable-repo
# track a file type
git lfs track "*.psd"
# check status of LFS-tracked files
git lfs status
```

### `commitizen` [cz] — Conventional Commit Prompt
An interactive command-line prompt that walks you through writing a properly formatted conventional commit — type, scope, description — instead of you recalling the exact syntax. It removes the guesswork of `type(scope): description` formatting and keeps commit history consistent across a team. Use it in place of `git commit` whenever you want a guided commit.

```bash
# launch the interactive commit prompt
cz commit
# shorthand for the same thing
cz c
```

### cz-conventional-changelog — Commitizen Adapter
Not a standalone command — this is the adapter package that defines the actual conventional-commit prompt format (types, scopes, breaking-change questions) that `cz` uses under the hood. It's installed as a dependency and wired into `commitizen` via config, not invoked directly. You'd only touch this when configuring or swapping which commit convention `cz` prompts for.

```json
// package.json — points commitizen at this adapter
{
  "config": {
    "commitizen": {
      "path": "cz-conventional-changelog"
    }
  }
}
```

### `commitlint` — Commit Message Linter
Lints commit messages against the conventional-commit spec, rejecting anything that doesn't match `type(scope): description` before it lands in history. It's typically wired into a git `commit-msg` hook so bad messages are caught at commit time rather than in review. Use it to enforce the same convention `commitizen` helps you write.

```bash
# lint the most recent commit
npx commitlint --from HEAD~1 --to HEAD
# lint a commit message file (used inside a commit-msg hook)
npx commitlint --edit "$1"
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

### `curlie` — curl with HTTPie Ergonomics
Wraps `curl` to add HTTPie-style colorized output and shorthand syntax, while still exposing curl's full flag set underneath. It's the middle ground when you need curl's power (custom certs, proxies, obscure options) but want nicer, more readable output than raw curl gives you.

```bash
# simple GET with colorized output
curlie example.com
# verbose request/response with headers
curlie -v example.com
# HTTPie-style POST with key=value body
curlie POST example.com/api key=value
# full curl flags still work
curlie -X PUT example.com/api -d '{"a":1}' -H 'Content-Type: application/json'
```

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

### `grpcurl` — curl for gRPC
Lets you list services and methods, describe message schemas, and invoke gRPC endpoints from the shell — the gRPC equivalent of curl for REST. Works via server reflection when available, or against local `.proto` files otherwise. Use it to poke at a gRPC service during development without writing a client.

```bash
# list all services exposed by a server (needs reflection enabled)
grpcurl -plaintext localhost:50051 list
# describe a service's methods and message types
grpcurl -plaintext localhost:50051 describe mypackage.MyService
# call a method with a JSON payload
grpcurl -plaintext -d '{"id": 1}' localhost:50051 mypackage.MyService/GetItem
# no reflection available: point at local proto files instead
grpcurl -plaintext -import-path ./protos -proto myservice.proto localhost:50051 list
```

### `atac` — Terminal API Client
"Arguably a Terminal API Client" — a Postman/Insomnia alternative that runs fully offline in the terminal, with no account required. It's TUI-first for building and running requests interactively, but collections are stored as plain files so they're git-friendly, and it can import existing Postman, cURL, or OpenAPI collections.

```bash
# launch the TUI in the current directory (creates a workspace)
atac
# use a specific directory for collections/config/logs
atac -d ~/api-collections
# import an existing Postman collection
atac import postman_collection.json
```

> Tip: `atac --dry-run` runs without writing changes to disk — handy for trying it out risk-free.

### `oha` — HTTP Load Testing
A Rust-based HTTP load-testing tool (an alternative to `ab`/`wrk`) that fires many requests at an endpoint and shows a live TUI of latency percentiles and throughput as results come in. Reach for it when you want a quick, visual sense of how an API endpoint holds up under load.

```bash
# 200 requests total against an endpoint
oha https://example.com/api
# fixed number of requests
oha -n 1000 https://example.com/api
# run for a fixed duration instead of a fixed count
oha -z 30s https://example.com/api
# set concurrency level
oha -c 50 -n 2000 https://example.com/api
```

### `hyperfine` — Command-Line Benchmarking
Runs a command many times and reports statistically sound timing (mean, min/max, standard deviation), optionally comparing multiple commands side by side. It replaces ad hoc `time` loops for answering "which of these is actually faster?"

```bash
# benchmark a single command
hyperfine 'grep foo bigfile.txt'
# compare two commands directly
hyperfine 'fd pattern' 'find . -name pattern'
# warm up caches with 3 runs before timing
hyperfine --warmup 3 'npm run build'
```

### `ngrok` — Public HTTPS Tunnel to Localhost
Exposes a port on your local machine as a public HTTPS URL, so you can share a dev server, test webhooks from a third-party service, or demo something running locally. Requires a free account and an authtoken configured once via `ngrok config add-authtoken`.

```bash
# tunnel local port 3000 to a public https URL
ngrok http 3000
# tunnel a specific local host:port
ngrok http 127.0.0.1:8080
# use a reserved/custom subdomain (paid plans)
ngrok http --subdomain=myapp 3000
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

### `caddy` — Web Server with Automatic HTTPS
A modern web server that provisions and renews TLS certificates automatically. Beyond production use, it doubles as a zero-config static file server and reverse proxy for local development — no config file needed for the common cases.

```bash
# serve a directory of static files
caddy file-server --root /path/to/files --listen :8080
# reverse-proxy one local port to another
caddy reverse-proxy --from localhost:80 --to localhost:8000
# run using a Caddyfile
caddy run --config Caddyfile
# format a Caddyfile in place
caddy fmt Caddyfile --overwrite
```

### `carbonyl` — Chromium in the Terminal
A real Chromium browser rendered entirely inside the terminal, including images, CSS, JavaScript, and video. Unlike `w3m`, it renders actual web pages rather than just text, which makes it useful for quickly checking how a page looks over SSH or in a headless environment.

```bash
# open a URL in the terminal browser
carbonyl https://example.com
# open with a specific window size
carbonyl --width=120 --height=40 https://example.com
```

### `w3m` — Classic Text-Based Browser
A lightweight, text-only terminal web browser and pager that renders HTML as formatted plain text (tables, links, basic layout) without images or JS. It's useful for quickly reading a page or man-page-like HTML over SSH where a full browser isn't practical.

```bash
# open a page in the browser
w3m https://example.com
# render a page straight to stdout, no interactive session
w3m -dump https://example.com | less
# browse a local HTML file
w3m ./notes.html
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

### `mtr` — Combined Ping + Traceroute
Continuously updates a live view combining ping and traceroute, showing per-hop latency, jitter, and packet loss so you can pinpoint which hop on a route is causing problems. Needs raw sockets (`sudo`), and on this setup it lives in `/usr/sbin` rather than the default `PATH`.

```bash
# live interactive report (needs sudo)
sudo mtr example.com
# generate a fixed-count text report instead of the live view
sudo mtr --report --report-cycles 10 example.com
# use TCP instead of ICMP (helps when ICMP is filtered)
sudo mtr --tcp example.com
```

### `gping` — Ping with a Live Graph
Pings one or more hosts and plots the results as a live latency graph in the terminal, instead of a scrolling list of numbers. It's aliased over `ping` in this setup, so typing the familiar command gets you the graph.

```bash
# ping one host with a live latency graph
gping example.com
# compare multiple hosts on the same graph
gping example.com 1.1.1.1 8.8.8.8
# ping by specifying an interval between pings
gping --interval 0.5 example.com
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

### `bandwhich` — Live Network Utilization by Process
Shows a live TUI breakdown of current network bandwidth usage per process and per connection, so you can immediately see what's saturating your link. It needs raw socket access, so it must be run with `sudo`.

```bash
# launch the live bandwidth-by-process view (needs sudo)
sudo bandwhich
# only watch a specific network interface
sudo bandwhich -i en0
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
A keyboard-driven TUI for browsing, searching, and connecting to hosts defined in `~/.ssh/config`, inspired by `lazydocker`/`k9s`. It saves you from memorizing IPs or retyping long `ssh` invocations — pick a host from a list and connect, all through the standard `ssh` binary underneath so it never touches your keys or credentials directly.

```bash
# launch the TUI (lists hosts from ~/.ssh/config)
lazyssh
```

> Tip: press `a` inside the TUI to add a new host profile through a guided form (alias, host/IP, user, port, identity file) — there's no CLI flag for adding hosts, it's TUI-only.

### `keyward` — Offline SSH Key Manager
A single-binary, keyboard-driven TUI (with scriptable CLI commands) for discovering, inspecting, generating, rotating, and auditing SSH keys and `~/.ssh/config` — with no daemon and no network access. Use the CLI subcommands in scripts or CI, and the TUI for everyday interactive key management.

```bash
# launch the interactive TUI
keyward
# run a security audit, failing CI on critical findings
keyward audit --fail-on=critical
# list discovered keys as JSON
keyward list --json
# write an encrypted backup of ~/.ssh
keyward backup --out ~/Archive/ssh-backup.tar.age
```

### `blueutil` — CLI Bluetooth Control
Controls macOS Bluetooth from the command line — power state, listing paired/connected devices, and connecting or disconnecting a specific device by address or name. It's what drives the Bluetooth toggle in the SketchyBar menu bar on this setup, but it's just as usable directly.

```bash
# turn Bluetooth on (or off / toggle)
blueutil --power on
# list currently paired devices
blueutil --paired
# list currently connected devices
blueutil --connected
# connect to a device by its MAC address
blueutil --connect AA-BB-CC-DD-EE-FF
```


## Databases, containers & cloud

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

### `pgcli` — Postgres CLI
A drop-in replacement for `psql` with auto-completion, syntax highlighting, and smarter multi-line editing. It knows Postgres table/column names as you type, which makes ad hoc querying much faster than the stock client. Use it any time you're working directly against a Postgres database from the terminal.

```bash
# connect with a full connection URL
pgcli postgres://user@localhost:5432/mydb
# connect with discrete flags, like psql
pgcli -h localhost -U myuser -d mydb
# connect to a non-default port
pgcli -h localhost -U myuser -d mydb -p 5433
```

> Tip: it supports the same `\d`, `\dt`, `\l` meta-commands you already know from `psql`.

### `mycli` — MySQL CLI
The MySQL/MariaDB sibling of `pgcli` — a `mysql` client replacement with auto-completion, syntax highlighting, and smart pagination. It's the tool to reach for whenever you're running ad hoc queries against MySQL or MariaDB and want a friendlier interactive experience than the stock client.

```bash
# connect the same way you would with the mysql client
mycli -u root -h 127.0.0.1 mydb
# connect via a connection URL
mycli mysql://user:pass@localhost/mydb
# connect to a remote host on a custom port
mycli -u myuser -h db.example.com -P 3307 mydb
```

### `usql` — Universal SQL CLI
One CLI that speaks to nearly any database — Postgres, MySQL, SQLite, SQL Server, and more — through a single consistent interface and connection-URL syntax. It's handy when you bounce between different database engines and don't want to context-switch between `psql`, `mycli`, etc. Use it for quick cross-engine scripting or when a project's DB type isn't fixed.

```bash
# connect to Postgres
usql pg://user@localhost/mydb
# connect to a local SQLite file
usql sqlite:./local.db
# run one query non-interactively and exit
usql pg://user@localhost/mydb -c "select count(*) from users;"
```

### `lazysql` — Lazy SQL TUI
A keyboard-driven, `lazygit`-style TUI for browsing tables and running queries interactively, supporting Postgres, MySQL, and SQLite. It's a good middle ground between a full SQL IDE and a bare CLI client when you mainly want to poke around a schema and run quick queries with the mouse out of the loop. Connections can be saved for reuse instead of retyping a URL each time.

```bash
# connect directly with a connection URL
lazysql postgres://user:pass@localhost:5432/mydb
# connect to a local SQLite database
lazysql sqlite:///path/to/local.db
# open in read-only mode to browse safely
lazysql --read-only postgres://user:pass@localhost:5432/mydb
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

### `orbstack` — OrbStack
A fast, low-memory replacement for Docker Desktop that transparently provides working `docker` and `kubectl` commands, plus lightweight Linux VMs, without the resource overhead. It's mostly a background macOS app — open it once to finish setup, and it keeps `docker`/`kubectl` working from any terminal afterward. Reach for its own `orb` CLI when you specifically need a general-purpose Linux VM rather than a container.

```bash
# first run: launches the app and finishes setup, then it sits in the background
open -a OrbStack
# once running, docker/kubectl "just work" against it
docker ps
kubectl get nodes
# spin up a lightweight Linux VM
orb create ubuntu dev
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

### `kubectl` — Kubernetes CLI
The standard command-line client for inspecting and managing Kubernetes resources — pods, deployments, services, and everything else in a cluster. OrbStack provides a working `kubectl` automatically once it's running. It's the baseline tool everything else in the Kubernetes toolchain (like `k9s` and `stern`) sits on top of.

```bash
# list pods in the current namespace
kubectl get pods
# see detailed info and recent events for a pod
kubectl describe pod mypod
# stream logs from a pod
kubectl logs -f mypod
# apply a manifest
kubectl apply -f deployment.yaml
```

### `k9s` — Kubernetes TUI
A real-time terminal UI for navigating and managing Kubernetes clusters — browse resources, drill into pods, view logs, and edit or delete objects, all without memorizing `kubectl` flags. It's dramatically faster for day-to-day cluster exploration than typing individual `kubectl` commands. Use it whenever you're actively debugging or monitoring what's running in a cluster.

```bash
# launch against your current kube context
k9s
# start in a specific namespace
k9s -n kube-system
# start against a specific kube context
k9s --context prod
```

### `stern` — Multi-Pod Log Tailing
Tails logs from multiple Kubernetes pods and containers at once, matching them by name or label selector and color-coding each source. It solves the problem of `kubectl logs` only following one pod at a time, which is painful once you have replicas. Use it whenever you need to watch logs across a deployment during a rollout or incident.

```bash
# tail logs from all pods matching a name prefix
stern mypod-prefix
# tail all pods in a namespace
stern . -n kube-system
# tail pods matching a label selector
stern --selector app=myapp
```

### `awscli` — AWS CLI
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

### `cdk-nag` — CDK Nag
A library (not a standalone command) that you wire into a CDK app to run curated best-practice and compliance rule packs — like AWS Solutions or NIST 800-53 — against every construct during `cdk synth`. It catches insecure or non-compliant infrastructure patterns before they're ever deployed, acting like a linter for your CDK-defined resources. Add it early in a project so violations surface as you build, not after an audit.

```typescript
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';

// apply the AWS Solutions rule pack to every construct in the app
Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
```

> Tip: findings show up as `cdk synth` warnings/errors — suppress specific, reviewed exceptions with `NagSuppressions` rather than disabling the whole check.

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
A `k9s`-style terminal UI for Amazon ECS — browse clusters, services, and tasks, exec into running containers, and tail logs, all interactively instead of chaining `aws ecs describe-*` commands. It's the fastest way to see what's actually running in an ECS cluster and poke at it. Use it for day-to-day ECS operations and debugging.

```bash
# launch using your default AWS profile/region
e1s
# launch against a specific profile
e1s --profile myprofile
# launch against a specific region
e1s --region us-east-1
```

### `e2c` — EC2 TUI
A terminal UI for browsing and managing Amazon EC2 instances — view state, type, and other details, and start/stop/reboot/terminate or connect via SSH, all without leaving the terminal or opening the Console. It's the EC2 counterpart to `e1s` and `k9s`. Reach for it when you need a quick visual view of running instances across a region.

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
A `k9s`-style terminal UI that spans roughly 70 AWS services in one browsable interface, rather than focusing on a single service like `e1s` or `e2c` do. It's useful when you want one general-purpose place to poke around AWS without switching tools per service, though as a younger project it's less polished than the service-specific TUIs. Treat it as a broad-coverage exploration tool rather than your primary daily driver for any one service.

```bash
# launch using your default AWS profile/region
claws
```

> Tip: being a younger project, expect rougher edges than `k9s`/`e1s` — fall back to `aws` CLI or a service-specific TUI if a feature is missing.

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

### `tofu` — OpenTofu
The open-source, community-governed fork of Terraform for defining and provisioning multi-cloud infrastructure as code. It's a drop-in replacement using the same HCL syntax and workflow (`init`/`plan`/`apply`), for teams that want infrastructure tooling that stays fully open source. Use it as your primary IaC tool for any cloud resources.

```bash
# initialize providers and backend
tofu init
# preview changes
tofu plan
# apply changes
tofu apply
# auto-format all .tf files recursively
tofu fmt -recursive
```

### `tflint` — Terraform/OpenTofu Linter
A linter for Terraform/OpenTofu configuration that catches provider-specific errors, deprecated syntax, and style issues that `tofu validate` won't catch, since it understands provider resource schemas. Run it before `tofu plan`/`apply` to catch mistakes early and enforce team conventions.

```bash
# install/update provider plugins tflint needs
tflint --init
# lint the current directory
tflint
# lint recursively through subdirectories/modules
tflint --recursive
```

### `terraform-docs` — Module Documentation Generator
Auto-generates Markdown documentation of a Terraform/OpenTofu module's inputs, outputs, providers, and resources directly from the code, so module docs never drift out of sync by hand. Use it to keep every module's README accurate with zero manual upkeep.

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

### `infracost` — Cloud Cost Estimation
Estimates the monthly dollar cost of Terraform/OpenTofu changes before you apply them, by combining your plan output with live cloud pricing data. It turns "will this change blow up our AWS bill" into a number you can see in a PR, rather than finding out after the fact. Run it as part of your pre-apply review process.

```bash
# estimate the cost of the infrastructure in the current directory
infracost breakdown --path .
# show the cost difference against a previous estimate
infracost diff --path . --compare-to infracost-base.json
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

### `detect-secrets` — detect-secrets
Yelp's secret scanner builds a baseline file of known/allowed secrets, then flags anything new that looks like a credential on future scans — useful for adopting scanning in an existing repo without drowning in old false positives. It's commonly wired into pre-commit to block newly introduced secrets. Reach for it when you want a living, auditable baseline rather than a full history scan.

```bash
# generate an initial baseline of existing "secrets"
detect-secrets scan > .secrets.baseline
# re-scan and update the baseline against new findings
detect-secrets scan --baseline .secrets.baseline
# interactively review/label flagged findings
detect-secrets audit .secrets.baseline
```

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

### `sops` — sops
Encrypts the values inside a YAML/JSON/ENV file while leaving the keys in plaintext, so a secrets file stays diffable and readable in git while its contents stay protected. It integrates with age, AWS KMS, GCP KMS, and PGP as the underlying encryption backend. Use it to safely commit per-environment secrets (like `secrets.prod.yaml`) straight into a repo.

```bash
# encrypt a file in place (uses .sops.yaml config for the key)
sops -e -i secrets.yaml
# decrypt a file to stdout
sops -d secrets.yaml
# open the encrypted file in $EDITOR, re-encrypting on save
sops secrets.yaml
```

> Tip: define your age recipient or KMS key once in a `.sops.yaml` at the repo root so `sops` picks it up automatically instead of passing `--age`/`--kms` every time.

### `apw` — Apple Passwords CLI
Gives shell access to Apple Passwords (iCloud Keychain) logins and TOTP codes without opening the Passwords app or a browser — handy for scripts, launcher integrations, or quickly grabbing a 2FA code in the terminal. It runs a small background daemon you authenticate against via a system prompt. Needs macOS 14+ and the daemon running before use.

```bash
# start the background daemon (once, or via `brew services start apw`)
apw start
# authenticate the CLI against the running daemon
apw auth
# look up a saved password for a domain
apw pw list google.com
# grab the current one-time (TOTP) code for a domain
apw otp get google.com
```

### `clamscan` — ClamAV
An open-source antivirus engine for on-demand scanning of files and directories — not a real-time monitor, but useful for checking downloads, USB drives, or a suspicious folder against known malware signatures. Update the virus database with `freshclam` before scanning since ClamAV is only as good as its definitions. Reach for it for a quick, free malware check without a commercial AV subscription.

```bash
# update the virus definition database
freshclam
# scan a directory recursively, reporting only infected files
clamscan -r -i ~/Downloads
# scan and move infected files into quarantine
clamscan -r --move=~/quarantine ~/Downloads
```

### LuLu — Outbound Firewall
LuLu is a free, open-source macOS outbound firewall that watches for and blocks unexpected outbound network connections — the reverse of most firewalls, which focus on inbound traffic. It alerts the first time an app tries to phone home, letting you allow or block it, which is useful for catching malware, trackers, or apps being unexpectedly chatty. There's no CLI; everything happens through its menu-bar icon and the alert popups it shows when a new connection is attempted.

*No CLI — manage via the menu-bar icon and its connection-alert popups.*

### `mullvad` — Mullvad VPN
Mullvad is a privacy-focused, no-logs VPN service; the GUI app bundles a `mullvad` CLI for scripting connections, checking status, and switching relays without opening the app window. This setup's SketchyBar VPN pill uses the CLI under the hood to toggle the connection and show status at a glance. Reach for the CLI when you want to connect/disconnect from a script or check state quickly.

```bash
# connect to the VPN
mullvad connect
# check current connection status
mullvad status
# disconnect
mullvad disconnect
# pick a specific relay location
mullvad relay set location us
```

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

### `act3` — act3
A tiny terminal dashboard that fetches and displays the last three GitHub Actions runs for a repo (or several repos), so you can glance at CI health without opening a browser. It's unrelated to `act` (which runs workflows locally) — act3 only reports on runs that already happened on GitHub. Reach for it right after pushing, to confirm CI passed without leaving the terminal.

```bash
# check the current directory's repo
act3
# check specific repositories
act3 -r owner/repo1,owner/repo2
# render output as a table instead of the default view
act3 -f table
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

### `lighthouse` — Lighthouse
Google's automated web page auditor, scoring performance, accessibility, SEO, and best practices, available as a CLI so it can run outside Chrome DevTools and in CI. It's the standard way to get an objective, repeatable audit of a page rather than eyeballing load times. Run it against a local dev server or a deployed URL before shipping a page.

```bash
# audit a URL and open the HTML report
lighthouse https://example.com --view
# output raw JSON for scripting/CI thresholds
lighthouse https://example.com --output json --output-path report.json
# audit only performance and accessibility categories
lighthouse https://example.com --only-categories=performance,accessibility
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

### `bun` — Bun
An all-in-one JavaScript/TypeScript runtime, bundler, test runner, and package manager, aiming to be a faster drop-in for Node plus npm/webpack/jest. It runs TypeScript directly with no build step and installs packages significantly faster than npm/yarn. Reach for it on projects that want one fast toolchain instead of stitching several together.

```bash
# install dependencies
bun install
# run a script directly (TS/JS, no build step)
bun run index.ts
# run the project's test suite
bun test
# add a package
bun add zod
```

### `ni` — ni
A universal Node package-manager runner that detects which package manager a project uses (npm, yarn, pnpm, or bun) from its lockfile and runs the equivalent command, so you never have to remember which one a given repo wants. `ni` installs, `nr` runs a script, `nlx` executes a package binary. Reach for it when jumping between projects that use different package managers.

```bash
# install dependencies with whichever PM the lockfile implies
ni
# run the "build" script
nr build
# execute a package binary without installing it globally
nlx eslint .
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

### `turbo` — Turborepo
A high-performance build system for JavaScript/TypeScript monorepos, providing task caching (local and remote) and dependency-aware task pipelines so you only rebuild/retest what actually changed. It dramatically speeds up `build`/`test`/`lint` across many packages compared to running each one naively. Reach for it once a repo has multiple interdependent packages and builds start feeling slow.

```bash
# run the "build" task across all packages in dependency order
turbo run build
# run multiple tasks, using the cache where possible
turbo run lint test
# force a clean run, bypassing the cache
turbo run build --force
```

### `taproom` — Taproom
An interactive terminal UI for Homebrew: browse, search, and inspect formulae and casks (description, version, dependencies, install counts) and run install/upgrade/uninstall actions directly from the list, instead of memorizing `brew` subcommands. Reach for it when exploring what's installed or available, rather than for one-off `brew` commands you already know by heart.

```bash
# launch the TUI
taproom
# launch and force a refresh of cached formula/cask data
taproom --invalidate-cache
# launch with an initial filter applied
taproom --filters installed
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

### `d2` — Text-to-Diagram Language
A declarative diagramming language: you write plain-text code describing boxes, arrows, and containers, and `d2` compiles it into a clean SVG, PNG, or PDF. It replaces GUI diagramming tools (draw.io, Visio) with something that lives in a repo, diffs cleanly, and renders from the terminal — reach for it when documenting architecture, flows, or system diagrams alongside code.

```bash
# render a .d2 file to SVG (default output)
d2 architecture.d2
# live-reload in the browser while editing
d2 --watch architecture.d2
# render to PNG using the ELK layout engine
d2 --layout elk architecture.d2 architecture.png
```

> Tip: `d2 fmt architecture.d2` reformats the source file in place.

### `mmdc` — Mermaid CLI
Renders Mermaid diagram definitions (flowcharts, sequence diagrams, gantt charts) to SVG, PNG, or PDF without a browser — the same syntax GitHub and Notion render inline in Markdown. Use it to turn a `.mmd` file (or Mermaid fences inside a Markdown doc) into a static image for docs, slides, or emails.

```bash
# render a flowchart definition to SVG
mmdc -i flow.mmd -o flow.svg
# extract and render every mermaid fence in a Markdown file
mmdc -i README.md -o diagrams
# render with a dark theme and transparent background
mmdc -i flow.mmd -o flow.png -t dark -b transparent
```

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

### `doxx` — Terminal .docx Viewer
Reads and renders Microsoft Word `.docx` files directly in the terminal, so you don't have to open Word or LibreOffice just to skim a document someone sent you. It can also export a docx's content to plain text, Markdown, or JSON for further processing.

```bash
# view a Word document in the terminal
doxx report.docx
# jump straight to the document outline view
doxx report.docx --outline
# export the content to Markdown
doxx report.docx --export markdown
```

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

### `ffmpeg` — Audio/Video Processor
The universal media processor: transcode between formats, trim clips, extract audio, adjust resolution, and pretty much anything else involving audio or video — all scriptable from the terminal, no GUI editor required.

```bash
# transcode a video to a smaller H.264 mp4
ffmpeg -i input.mov -c:v libx264 -crf 23 output.mp4
# extract the audio track as mp3
ffmpeg -i input.mp4 -vn -c:a libmp3lame output.mp3
# trim a clip from 00:01:00 for 30 seconds
ffmpeg -i input.mp4 -ss 00:01:00 -t 30 -c copy clip.mp4
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

### `asciinema` — Terminal Session Recorder
Records a terminal session as a lightweight, replayable text-based cast (not a video), which can be played back locally or uploaded and shared as a link. It's the right tool for documenting a CLI workflow in a README or ticket — far smaller and more copy-pasteable than a screen recording.

```bash
# start recording a session to a file
asciinema rec demo.cast
# play a recording back
asciinema play demo.cast
# upload a recording and get a shareable link
asciinema upload demo.cast
```

### `vhs` — Scripted Terminal Recordings
Turns a plain-text `.tape` script (a sequence of keystrokes and timings) into a reproducible GIF or MP4 of a terminal session. It replaces manually re-recording a screencast every time a demo needs updating — since the script is checked into the repo, the recording regenerates itself. Reach for it for docs and READMEs where you want a polished, repeatable demo rather than a one-off screen recording.

```bash
# scaffold a new .tape file with example content
vhs new demo.tape
# render a .tape script to its configured output(s)
vhs demo.tape
# render straight to a specific output file
vhs demo.tape -o demo.gif
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

### `manly` — Command Flag Explainer
Explains exactly what a command and the specific flags you passed it do, pulled straight from its man page — instead of you re-reading the whole page to find the three flags you care about. Reach for it right after pasting a command you don't fully trust.

```bash
# explain what these flags actually do
manly rm --preserve-root -rf
# explain a tar invocation
manly tar -xzf archive.tar.gz
```

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

### `herald` — Terminal Email + Calendar
A unified terminal client for email and calendar — Gmail (work) and iCloud (personal) in one place — with AI-assisted triage and an MCP server so Claude can read (and, with confirmation, act on) your inbox and calendar. It replaces running separate mail and calendar apps.

```bash
# first run: interactive onboarding to add accounts
herald
# run the background daemon (needed for MCP mutations)
herald serve -config ~/.herald/conf.yaml
# check daemon status
herald status
```

> Tip: herald is read-only for Claude until the daemon (`herald serve`) is running.

### `gws` — Google Workspace CLI
A single CLI for the whole of Google Workspace — Drive, Gmail, Calendar, Sheets, Docs, Chat — with structured JSON output designed for both humans and AI agents to consume. It replaces ad-hoc `curl` calls against Google's REST APIs; every subcommand mirrors a Workspace API resource and method.

```bash
# one-time setup, then log in
gws auth setup
gws auth login
# list the 10 most recently modified Drive files
gws drive files list --params '{"pageSize": 10}'
# create a new spreadsheet
gws sheets spreadsheets create --json '{"properties": {"title": "Q1 Budget"}}'
```

> Tip: add `--dry-run` to preview the request before it's sent — invaluable before anything that mutates data.

### `tiki` — Terminal Markdown Workspace
A git-backed workspace for tasks, docs, kanban boards, and a wiki — all stored as plain Markdown files you can browse and edit as a TUI or from the CLI. It replaces a Notion-style app with something that lives in a repo, diffs like code, and syncs via git.

```bash
# launch the TUI over the Markdown files in this directory
tiki
# quick-capture a note from piped input (first line = title)
echo "Follow up with client" | tiki
# run a ruki query against the workspace and exit
tiki exec 'select id, title where status = "ready"'
```

### `reminders` — Apple Reminders CLI
Reads and writes the real Apple Reminders database through EventKit, so anything you add here syncs to iPhone and Watch via iCloud like it was typed into the Reminders app. This is the piece tiki and herald deliberately leave out: tiki keeps tasks in git, herald owns mail and calendar events, and `reminders` owns alerts that need to follow you off the machine. First run raises a one-time macOS consent prompt (granted to your terminal, not to the binary); until you approve it, commands return an empty list rather than an error.

```bash
# see which lists exist, then what's on one
reminders show-lists
reminders show Inbox
# add a reminder, optionally with a natural-language due date
reminders add Inbox "Renew domain" --due-date "friday 9am"
# complete item 0 on a list
reminders complete Inbox 0
```

### `newsboat` — Terminal RSS Reader
A vim-keybinding RSS/Atom feed reader for the terminal, highly configurable via a plain-text config and URL file. Use it to follow blogs, changelogs, and news feeds without a browser tab (or a bloated GUI reader) always open.

```bash
# launch newsboat with the default feed list
newsboat
# refresh all feeds once on startup
newsboat --refresh-on-start
# use a specific URL file for feeds
newsboat --url-file=~/.newsboat/work-urls
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

### `starlit` — Weather CLI
A minimal, nicely styled weather CLI — current conditions and forecast, right in the terminal, no browser tab or app needed. Requires a free OpenWeatherMap API key on first use.

```bash
# one-time setup: store your OpenWeatherMap key
starlit --setup
# get weather for your default city
starlit
# get weather for a specific city
starlit tokyo
```

### `bmm` — Bookmark Manager
A local bookmark manager with both a scriptable CLI and a TUI browser, storing bookmarks in a local database you can search and tag. It replaces a browser's built-in (and un-scriptable) bookmark bar — reach for it when you want bookmarks that work the same way across browsers and are easy to search from a terminal.

```bash
# save a new bookmark
bmm save "https://example.com" --title "Example"
# search bookmarks by term
bmm search terraform
# open the interactive TUI browser
bmm tui
```

> Tip: `bmm import` pulls bookmarks in from an HTML, JSON, or plain-text export.

### `surge` — Download Manager (TUI)
A TUI download manager that pairs with a browser extension: the extension intercepts downloads in Chrome and hands them to a local `surge` daemon, giving you a manageable, resumable download queue instead of the browser's own download tray. It complements `aria2` — `aria2` is for scripted/CLI downloads, `surge` is for downloads you start by clicking a link in the browser.

```bash
# install the background daemon service (one-time)
surge service install
# open the TUI to manage the download queue
surge
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

### `jolt` — Battery/Energy Monitor
A terminal battery and power monitor: charge level, health, power draw, and history, at a glance or as a live TUI. Use it to check battery health trends over time instead of digging through macOS's own battery settings.

```bash
# launch the live terminal UI
jolt
# print current battery/power metrics as JSON
jolt pipe
# view historical battery data
jolt history
```

### `lazynpm` — TUI for npm
A terminal UI for npm projects — browsing and running scripts, inspecting and updating dependencies — from the same team and interaction model as `lazygit`/`lazydocker`. Launch it inside a Node project instead of memorizing `npm run` script names.

```bash
# launch inside an npm project directory
lazynpm
```

### `lazyenv` — TUI for .env Files
A terminal UI for managing `.env` files across projects: browse variables, diff and sync values between environments, and mask secrets on screen so they're not shown in cleartext by default. It complements `direnv` — `direnv` auto-loads variables, `lazyenv` is for editing and comparing them.

```bash
# open the TUI scanning the current directory
lazyenv
# scan a specific project recursively
lazyenv ~/Code/myapp --recursive
# reveal secret values in cleartext at startup
lazyenv --show-all
```

> Tip: it checks `.gitignore` by default and backs up the file before its first save — pass `--no-git-check`/`--no-backup` to skip either.

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


## GUI apps & under-the-hood

These are the deliberate GUI survivors — apps kept because a terminal equivalent
would cost real capability — plus the invisible plumbing the toolkit depends on
but you rarely invoke by hand.

### Ghostty — Terminal Emulator
The fast, GPU-accelerated terminal that hosts this whole setup, themed Dracula.
Its global **quick terminal** drops down from anywhere on `cmd+space` and hosts
the launcher functions (`a`, `ff`, `rgf`, `s`, `clip`). Config lives at
`~/.config/ghostty/config`.

### Google Chrome — Primary Browser
The primary GUI browser (Carbonyl and w3m cover terminal browsing). Kept for
sites that need a full modern engine, extensions, and DevTools.

### Shottr — Screenshots
Fast native screenshot tool with scrolling capture, OCR, and annotation. Saves
to `~/Screenshots`. Needs **Screen Recording** permission (see the checklist) or
it captures only the desktop, not app windows.

### Skim — PDF Reader
A lightweight PDF reader/annotator, faster than Preview and good for reading
papers and marking up documents.

### SketchyBar — Status Bar
The customizable macOS status bar (Dracula-themed) shown at the top: front app,
clock, battery, wifi, volume, cpu, mem, bluetooth, VPN. The clock opens herald;
the VPN pill drives `mullvad`; the bluetooth pill drives `blueutil`. Needs
**Accessibility** permission. Config: `~/.config/sketchybar/`.

### Pearcleaner — App Uninstaller
An open-source deep uninstaller that removes an app *and* its leftover support
files, caches, and preferences — a free AppCleaner replacement.

### Language servers (croft uses these automatically)
Installed so the editors get completion, diagnostics, and go-to-definition with
zero config — you never call them directly:
`bash-language-server`, `marksman` (Markdown), `taplo` (TOML + formatter),
`yaml-language-server`, `typescript-language-server`,
`vscode-langservers-extracted` (HTML/CSS/JSON/ESLint).

### Build & runtime dependencies
Pulled in so other tools compile and run; rarely invoked by hand:
`cmake`, `pkgconf` (provides `pkg-config`), `coreutils`, `findutils`, `gawk`,
`gnu-sed`, `gnu-tar` (GNU versions of core Unix utilities), `gnupg` +
`pinentry-mac` (commit signing / passphrase entry), `watchman` (file-watching
service used by some JS toolchains).

### Fonts
Installed for the terminal, editors, and SketchyBar glyphs:
JetBrains Mono (+ Nerd Font) — primary dev font; Fira Code (+ Nerd Font) —
ligature font; Hack Nerd Font; MesloLGS Nerd Font; Inter — UI font;
sketchybar-app-font — app glyphs for the status bar.

---

*This file is regenerated on every run of `setup-dev-tools-mac.sh`, so it always
matches the tools the script currently installs.*
REFERENCE_EOF

    success "Desktop docs written: POST_SETUP_CHECKLIST.md, KEYBOARD_SHORTCUTS.md, TOOLKIT_SUMMARY.md, TOOL_REFERENCE.md"
fi

info "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. >>> Work through ~/Desktop/POST_SETUP_CHECKLIST.md <<< (email/calendar creds,"
echo "        macOS permissions, apw/mullvad/starlit setup — the manual bits)."
echo "        Also on the Desktop: KEYBOARD_SHORTCUTS.md, TOOLKIT_SUMMARY.md, and"
echo "        TOOL_REFERENCE.md (every tool, with usage examples)."
echo "  3. Log out/in once so the menu-bar and Spotlight hotkey settings take effect."
echo "  4. Enable FileVault + macOS Firewall (System Settings > Privacy & Security / Network)."
echo "  5. Open OrbStack and complete Docker setup."

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
            git config --global user.name "$personal_name"
            git config --global user.email "$personal_email"
            git config --global --unset-all "includeIf.gitdir:~/Code/work/.path" 2>/dev/null || true
            git config --global "includeIf.gitdir:~/Code/work/.path" "$GITCONFIG_WORK"
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
    # already uses it this way (soffice, office-py, manly, starlit) — so link the shims in.
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
            mkdir -p "$HOME/.local/bin"
            _shim_n=0
            for _shim in "$_mise_shims"/*; do
                [[ -e "$_shim" ]] || continue
                _bin="$(basename "$_shim")"
                _skip=false
                for _ex in "${SHIM_EXCLUDE[@]}"; do
                    [[ "$_bin" == "$_ex" ]] && _skip=true && break
                done
                [[ "$_skip" == "true" ]] && continue
                ln -sfn "$_shim" "$HOME/.local/bin/$_bin"
                _shim_n=$((_shim_n + 1))
            done
            # Prune links whose shim has gone — a tool removed from mise otherwise leaves a
            # dangling link that resolves to nothing and reports "command not found" only at
            # the point of use. Only ever removes a SYMLINK pointing into the shims dir, so a
            # real file placed in ~/.local/bin by hand (soffice, office-py, …) is untouched.
            for _link in "$HOME/.local/bin"/*; do
                [[ -L "$_link" ]] || continue
                case "$(readlink "$_link")" in
                    "$_mise_shims/"*) [[ -e "$_link" ]] || rm -f "$_link" ;;
                esac
            done
            success "$_shim_n mise shims linked to ~/.local/bin — git hooks, editors and non-zsh shells can find them"
            unset _shim _bin _skip _ex _shim_n _link
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
        "bun:bun --version"
        "uv:uv --version"
        "brew:brew --version"
        "micro:micro -version"
        "docker/orbstack:docker --version || orbstack version"
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
    info "Running brew doctor..."
    if brew doctor >> "$LOG_FILE" 2>&1; then
        success "Brew doctor: no issues found"
    else
        warn "Brew doctor found issues (check log for details)"
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

echo ""
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}${BOLD}  Setup Complete!${NC}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Installed:${NC}  $INSTALL_SUCCESS"
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

# Files rewritten by write_generated because their content changed (Claude agents and
# slash commands). Worth naming: the previous copy is kept alongside as *.replaced.*
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
# and last, so it is the final thing read before the run ends.
config_split_notice

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}${BOLD}  This was a dry run — no changes were made.${NC}"
    echo -e "${YELLOW}  Run without --dry-run to install everything.${NC}"
    echo ""
else
    # macOS notification: success or failure summary
    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        notify_failure "${INSTALL_FAILED} item(s) failed — see $ERROR_LOG"
    else
        notify_success "Installed $INSTALL_SUCCESS, skipped $INSTALL_SKIPPED in ${MINUTES}m ${SECONDS_REMAINING}s"
    fi
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
        echo -e "${GREEN}${BOLD}  Reloading shell...${NC}"
        release_lock
        exec zsh -l
    else
        echo -e "${GREEN}${BOLD}  Run 'source ~/.zshrc' or restart your terminal to activate.${NC}"
    fi
else
    echo -e "${GREEN}${BOLD}  Restart your terminal to activate everything.${NC}"
fi
echo ""
