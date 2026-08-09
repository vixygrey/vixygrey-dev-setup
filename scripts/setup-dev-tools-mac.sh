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

SCRIPT_VERSION="6.0.0"
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

# Dynamic total — count all install calls in this script so the progress bar stays accurate
# when tools are added or removed. Counts brew_install, brew_cask_install, npm_global_install,
# including those inside conditionals.
# Count all install calls + standalone progress calls for accurate progress bar
# Note: `grep -c` prints "0" AND exits 1 on zero matches, so `|| echo 0` would append
# a SECOND "0" ("0\n0") and break the arithmetic. Use `|| true` + a default instead.
_INSTALL_CALLS=$(grep -cE '^\s*(brew_install|brew_cask_install|npm_global_install|go_install|uv_tool_install) ' "$0" 2>/dev/null || true)
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
INTERACTIVE=false
SKIP_CATEGORIES=()
ONLY_CATEGORIES=()

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
        error "Another instance is running (PID: $old_pid)"
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
    [git]="Git, GitHub CLI, delta, lazygit, pre-commit"
    [aws]="AWS CLI, CDK, SAM, Granted, cfn-lint, e1s/e2c/stu/claws (TUIs), s5cmd, steampipe, dynein, iamlive"
    [iac]="OpenTofu (Terraform), tflint, terraform-docs, checkov, infracost"
    [security]="detect-secrets, gitleaks, trivy, semgrep, ClamAV"
    [replacements]="eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, rovr"
    [data-processing]="yq, miller, csvkit, pandoc, ffmpeg, ImageMagick"
    [code-quality]="shellcheck, shfmt, act, hadolint, ruff, commitizen"
    [perf-testing]="hyperfine, oha"
    [dev-servers]="ngrok, miniserve, caddy"
    [terminal-productivity]="leaf, watchexec, gum, nushell, topgrade, fastfetch, doxx, taproom, qalc, vhs, lazyssh, wiper, jolt"
    [k8s-github]="stern, gh-dash"
    [database]="pgcli, mycli, lazysql, harlequin, usql, sq"
    [containers]="lazydocker, dive, kubectl, k9s"
    [api]="ATAC, grpcurl"
    [networking]="mtr, bandwhich, nmap"
    [dx]="fzf, starship, atuin, Helix, Ghostty, zellij, aider, llm"
    [ux]="Lighthouse"
    [docs]="d2, Mermaid CLI"
    [mac-system]="Pearcleaner, Quick Look plugins, dockutil"
    [mac-productivity]="tiki, Skim"
    [mac-browsers]="Carbonyl, w3m"
    [mac-media]="mpv, oxipng, jpegoptim, 7zip, kew"
    [mac-cloud]="rclone, borg"
    [mac-focus]="newsboat"
    [mac-bloat]="Remove pre-installed Apple apps (GarageBand)"
    [dracula]="Dracula theme for all tools"
    [configs]="All dotfiles and tool configurations"
    [filesystem]="Directory structure, helper scripts, git identity"
    [macos-defaults]="Dock, Finder, keyboard, screenshots, Touch ID, DNS"
    [shell]="\$HOME/.zshrc, Brewfile export"
)

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
    echo "  --interactive, -i   Interactively pick which categories to install"
    echo "  --skip <cats>       Skip categories (comma-separated)"
    echo "  --only <cats>       Only run these categories (comma-separated)"
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
    echo "  ./setup-dev-tools-mac.sh --skip mac-media,mac-cloud"
    echo "  ./setup-dev-tools-mac.sh --only core,git,aws,dx"
    echo ""
}

list_categories() {
    echo ""
    echo -e "${BOLD}Available categories:${NC}"
    echo ""
    printf "  %-25s %s\n" "prerequisites"       "Xcode CLI Tools, Homebrew, GNU coreutils"
    printf "  %-25s %s\n" "core"                "mise (Node, Python), Go, Rust, OrbStack, bun, uv, pnpm"
    printf "  %-25s %s\n" "git"                 "Git, GitHub CLI, delta, lazygit, pre-commit"
    printf "  %-25s %s\n" "aws"                 "AWS CLI, CDK, SAM, Granted, cfn-lint, e1s/e2c/stu/claws (TUIs), s5cmd, steampipe, dynein, iamlive"
    printf "  %-25s %s\n" "iac"                 "OpenTofu (Terraform), tflint, terraform-docs, checkov, infracost"
    printf "  %-25s %s\n" "security"            "detect-secrets, gitleaks, trivy, semgrep, ClamAV, Objective-See"
    printf "  %-25s %s\n" "replacements"        "eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, rovr, fx, etc."
    printf "  %-25s %s\n" "data-processing"     "yq, miller, csvkit, pandoc, ffmpeg, ImageMagick"
    printf "  %-25s %s\n" "code-quality"        "shellcheck, shfmt, act, act3, hadolint, ruff, commitizen, ni"
    printf "  %-25s %s\n" "perf-testing"        "hyperfine, oha"
    printf "  %-25s %s\n" "dev-servers"         "ngrok, miniserve, caddy"
    printf "  %-25s %s\n" "terminal-productivity" "leaf, watchexec, gum, nushell, topgrade, fastfetch, nnn, doxx, taproom, qalc, vhs, lazyssh/rsync/npm, cheznav, apw, has, jolt, wiper, starlit"
    printf "  %-25s %s\n" "k8s-github"          "stern, gh-dash"
    printf "  %-25s %s\n" "database"            "pgcli, mycli, lazysql, harlequin, usql, sq"
    printf "  %-25s %s\n" "containers"          "lazydocker, dive, kubectl, k9s"
    printf "  %-25s %s\n" "api"                 "ATAC, grpcurl"
    printf "  %-25s %s\n" "networking"          "mtr, bandwhich, nmap"
    printf "  %-25s %s\n" "dx"                  "fzf, starship, atuin, Helix, Ghostty, zellij, aider, llm, repomix"
    printf "  %-25s %s\n" "ux"                  "Lighthouse"
    printf "  %-25s %s\n" "docs"                "d2, Mermaid CLI"
    printf "  %-25s %s\n" "mac-system"          "Pearcleaner, Quick Look plugins, dockutil, terminal-notifier"
    printf "  %-25s %s\n" "mac-productivity"    "tiki, Skim"
    printf "  %-25s %s\n" "mac-browsers"        "Carbonyl, w3m, monolith"
    printf "  %-25s %s\n" "mac-media"           "mpv, oxipng, jpegoptim, 7zip, kew"
    printf "  %-25s %s\n" "mac-cloud"           "rclone, borg"
    printf "  %-25s %s\n" "mac-focus"           "newsboat"
    printf "  %-25s %s\n" "mac-bloat"           "Remove pre-installed Apple apps (GarageBand)"
    printf "  %-25s %s\n" "dracula"             "Dracula theme for all tools"
    printf "  %-25s %s\n" "configs"             "All dotfiles and tool configurations"
    printf "  %-25s %s\n" "filesystem"          "Directory structure, helper scripts, git identity"
    printf "  %-25s %s\n" "macos-defaults"      "Dock, Finder, keyboard, screenshots, Touch ID, DNS"
    printf "  %-25s %s\n" "shell"               "$HOME/.zshrc, Brewfile export"
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
        --interactive|-i)
            INTERACTIVE=true
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

# write_managed <file> [comment-prefix]   (config content on stdin)
# Idempotent config writer that MERGES on re-run instead of overwriting:
#   - new file            -> create it wrapped in dev-setup markers
#   - file has our markers -> replace ONLY the block between markers (edits outside survive)
#   - file exists, no markers -> append our block (preserves the existing file)
# Comment prefix defaults to '#'. Honors DRY_RUN. This is the .zshrc managed-block
# pattern generalized so re-running the setup pulls config updates without clobbering
# personal edits placed outside the markers.
write_managed() {
    local file="$1" cp="${2:-#}"
    local mb="$cp >>> dev-setup managed block (do not edit between the markers) >>>"
    local me="$cp <<< dev-setup managed block <<<"
    local tmp; tmp="$(mktemp)"
    { printf '%s\n' "$mb"; cat; printf '%s\n' "$me"; } > "$tmp"
    if [[ "$DRY_RUN" == "true" ]]; then rm -f "$tmp"; return 0; fi
    mkdir -p "$(dirname "$file")"
    if [[ ! -f "$file" ]]; then
        cp "$tmp" "$file"
    elif grep -qF "$mb" "$file" 2>/dev/null; then
        local out; out="$(mktemp)"
        awk -v mb="$mb" -v me="$me" -v blk="$tmp" '
            index($0, mb) { while ((getline line < blk) > 0) print line; close(blk); inb=1; next }
            index($0, me) { inb=0; next }
            !inb { print }
        ' "$file" > "$out" && mv "$out" "$file"
    else
        { printf '\n'; cat "$tmp"; } >> "$file"
    fi
    rm -f "$tmp"
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
        if npm install -g "$pkg" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
            mark_done "npm:$pkg"
        else
            error "Failed to install $name"
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
        info "[DRY RUN] Would: uv tool install $* ${spec}"
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
    brew trust --tap "$tap" >> "$LOG_FILE" 2>&1 \
        || warn "Could not trust tap $tap — installs from it may be refused by Homebrew"
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
        read -r -p "Continue anyway? [y/N] " confirm
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
        read -r -p "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        success "Disk space: ${free_space:-unknown}GB free"
    fi

    # Admin check (some steps need sudo)
    # Prompt for password ONCE here so it's cached for all later sudo calls
    if sudo -n true 2>/dev/null; then
        success "Admin privileges available"
    else
        info "Some steps require admin privileges. Enter your password once now:"
        sudo -v
        success "Admin privileges granted"
        # Keep sudo alive in background for the duration of the script
        ( while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null ) &
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
    echo "  rm -f ~/.curlrc ~/.npmrc ~/.ripgreprc ~/.fdignore ~/.nanorc ~/.vimrc"
    echo "  rm -f ~/.hushlogin ~/.gitmessage ~/.myclirc ~/.gemrc ~/.actrc ~/.mlrrc"
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
        "cask:protonvpn:Proton VPN:Mullvad VPN"
        "cask:proton-mail:Proton Mail:removed"
        "cask:proton-pass:Proton Pass:removed"
        "cask:proton-drive:Proton Drive:removed"
        "cask:docker:Docker Desktop:OrbStack:Docker"
        "cask:warp:Warp terminal:Ghostty:Warp"
        "cask:iterm2:iTerm2:Ghostty:iTerm"
        "cask:cursor:Cursor (AI editor):Helix + Claude Code:Cursor"
        "cask:kiro:Kiro:Helix + Claude Code:Kiro"
        "cask:visual-studio-code:Visual Studio Code:Helix:Visual Studio Code"
        "cask:bruno:Bruno:ATAC:Bruno"
        "cask:dbeaver-community:DBeaver Community:harlequin + lazysql:DBeaver"
        "cask:cyberduck:Cyberduck:rclone:Cyberduck"
        "cask:google-drive:Google Drive:rclone:Google Drive"
        "cask:drawio:draw.io:d2 + mermaid-cli:draw.io"
        "cask:notion:Notion:tiki:Notion"
        "cask:notion-calendar:Notion Calendar:khal + vdirsyncer:Notion Calendar"
        "brew:yazi:yazi:rovr"
        "brew:cmus:cmus:kew"
        "brew:glow:glow:leaf"
        "cask:raycast:Raycast:Ghostty quick-terminal + clipse:Raycast"
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
        "cask:zed:Zed:Helix:Zed"
        "cask:slack:Slack:removed"
        "cask:telegram:Telegram:removed"
        "cask:notion-mail:Notion Mail:removed (retired by Notion):Notion Mail"
        "cask:libreoffice:LibreOffice:Google Workspace:LibreOffice"
    )

    CLEANUP_COUNT=0
    CLEANUP_SKIPPED=0

    for entry in "${DEPRECATED_TOOLS[@]}"; do
        IFS=':' read -r type name display replacement appname <<< "$entry"
        # appname defaults to display name when not specified (5th field)
        appname="${appname:-$display}"

        case "$type" in
            formula)
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
        esac
    done

    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        success "Cleanup complete: $CLEANUP_COUNT removed, $CLEANUP_SKIPPED not found (already clean)"
        if [[ "$CLEANUP_COUNT" -gt 0 ]]; then
            info "Running brew cleanup..."
            brew cleanup >> "$LOG_FILE" 2>&1 || true
        fi
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
# PREREQUISITES (always runs — required for everything else)
# =============================================================================
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
brew_install "git-delta" "delta (better git diffs)"
brew_install "git-lfs" "Git LFS"
brew_install "gnupg" "GnuPG (commit signing)"
brew_install "pinentry-mac" "pinentry-mac (GPG passphrase)"
brew_install "lazygit" "lazygit (terminal UI for git)"
brew_install "git-absorb" "git-absorb (auto-fixup commits)"
brew_install "git-cliff" "git-cliff (generate changelogs from conventional commits)"

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
if installed granted || installed assume; then
    warn "Granted already installed"
    progress
else
    trust_tap common-fate/granted
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

# man -> tldr: community-driven simplified man pages with examples
brew_install "tldr" "tldr (replaces man — simplified with examples)"

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

# wc -> tokei: count lines of code by language with stats
brew_install "tokei" "tokei (replaces wc for code — lines of code by language)"

# tree (enhanced built-in) - if not using eza --tree
brew_install "tree" "tree (directory listing)"

# watch -> viddy: modern watch with diff highlighting, history
brew_install "viddy" "viddy (replaces watch — diff highlighting, history)"

# cp/mv -> rsync is already on mac, but add progress
brew_install "rsync" "rsync (latest — better cp/mv for large transfers)"

# hexdump -> hexyl: colorized hex viewer with ASCII sidebar
brew_install "hexyl" "hexyl (replaces hexdump — colorized hex viewer)"

# curl/wget -> aria2: multi-connection parallel downloads, 3-10x faster
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

# imagemagick: image manipulation CLI
brew_install "imagemagick" "ImageMagick (image resize, convert, composite)"

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
brew_install "typos-cli" "typos (source code spell checker — fast, low false positives)"
brew_install "ast-grep" "ast-grep (structural code search/replace using AST)"

# JS/TS workflow
if installed npm; then
    npm_global_install "npkill" "npkill (find and nuke node_modules folders — reclaim disk)"
    npm_global_install "commitizen" "commitizen (interactive conventional commits)"
    npm_global_install "@commitlint/cli" "commitlint (enforce conventional commit format)"
    npm_global_install "@antfu/ni" "ni (universal package runner — auto-detects npm/yarn/pnpm/bun)"
else
    progress; progress; progress; progress  # keep progress bar accurate when npm unavailable
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
# usql — not in Homebrew, install via Go
progress
if installed go; then
    if command -v usql &>/dev/null; then
        warn "usql (universal SQL CLI) already installed"
    else
        info "Installing usql (universal SQL CLI)..."
        # Note: @latest is intentionally unpinned for usql
        go install github.com/xo/usql@latest >> "$LOG_FILE" 2>&1 || error "Failed to install usql (requires Go)"
    fi
else
    warn "Skipping usql — Go not installed (run: brew install go)"
fi
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
brew_install "helix" "Helix (post-modern modal editor — built-in LSP, tree-sitter, multiple selections, zero-config)"
brew_cask_install "ghostty" "Ghostty (fast GPU-accelerated terminal)"
brew_install "zellij" "zellij (modern terminal multiplexer — discoverable UI, layouts)"

# Language servers for Helix (so `hx` has LSP for the main languages out of the box).
# Python uses ruff's built-in server (already installed). TOML/Markdown via brew:
brew_install "taplo" "taplo (TOML language server + formatter — used by Helix)"
brew_install "marksman" "marksman (Markdown language server — used by Helix)"
if installed npm; then
    npm_global_install "typescript-language-server" "TypeScript/JavaScript language server (Helix LSP)"
    npm_global_install "vscode-langservers-extracted" "HTML/CSS/JSON/ESLint language servers (Helix LSP)"
    npm_global_install "bash-language-server" "Bash language server (Helix LSP)"
    npm_global_install "yaml-language-server" "YAML language server (Helix LSP)"
else
    progress; progress; progress; progress  # keep progress bar accurate when npm unavailable
fi
if [[ "$DRY_RUN" != "true" ]]; then
    # rust-analyzer (Rust LSP) via rustup component; gopls (Go LSP) via go install.
    if installed rustup; then
        rustup component add rust-analyzer >> "$LOG_FILE" 2>&1 || warn "Could not add rust-analyzer component (Rust LSP for Helix)"
    fi
    if installed go; then
        info "Installing gopls (Go LSP for Helix) — compiles, may take a moment..."
        go install golang.org/x/tools/gopls@latest >> "$LOG_FILE" 2>&1 || warn "Could not install gopls (Go LSP for Helix)"
    fi
fi

# AI tools
# Claude Code (installed via npm, not brew)
if installed npm; then
    npm_global_install "@anthropic-ai/claude-code" "Claude Code (AI-assisted coding in terminal)"
else
    progress  # keep progress bar accurate when npm unavailable
fi
# GitHub Copilot CLI (built-in on newer gh versions, or installed as gh extension)
progress
if installed gh; then
    if gh copilot --help &>/dev/null; then
        warn "GitHub Copilot CLI already available (built-in or extension)"
    elif gh extension list 2>/dev/null | grep -q "gh-copilot"; then
        warn "GitHub Copilot CLI already installed"
    else
        info "Installing GitHub Copilot CLI..."
        if gh extension install github/gh-copilot >> "$LOG_FILE" 2>&1; then
            success "GitHub Copilot CLI installed (run: gh copilot suggest)"
        else
            error "Failed to install GitHub Copilot CLI extension"
        fi
    fi
fi

# Additional agentic / LLM CLIs that pair with Claude Code + Helix
brew_install "aider" "aider (terminal AI pair programmer — git-aware edit loops)"
brew_install "llm" "llm (Simon Willison's CLI — one-shot prompts, plugins, SQLite logs, embeddings)"
brew_install "repomix" "repomix (pack a repo into a single LLM-friendly file with token counts)"

# Claude via the llm CLI: install the Anthropic plugin (used by the Helix/aerc :pipe binds).
if [[ "$DRY_RUN" != "true" ]] && installed llm; then
    llm install llm-anthropic >> "$LOG_FILE" 2>&1 && success "llm-anthropic plugin installed" \
        || warn "Could not install llm-anthropic plugin (run: llm install llm-anthropic)"
fi
# helix-assist: Claude-as-an-LSP for Helix (ghost-text completions + Space A code-actions).
# Successor to the archived helix-gpt; supports Anthropic natively. Needs ANTHROPIC_API_KEY.
if [[ "$DRY_RUN" != "true" ]] && installed go; then
    if command -v helix-assist &>/dev/null; then
        warn "helix-assist already installed"
    else
        info "Installing helix-assist (Claude AI LSP for Helix) via go..."
        go install github.com/leona/helix-assist/cmd/helix-assist@latest >> "$LOG_FILE" 2>&1 \
            && success "helix-assist installed" || warn "Could not install helix-assist (needs Go)"
    fi
fi

# Window management, status bar & clipboard (replaces Raycast + Spotlight)
# AeroSpace — tiling window manager. No SIP disable required (emulated workspaces).
trust_tap nikitabobko/tap
brew_cask_install "aerospace" "AeroSpace (tiling window manager — keyboard-driven, no SIP)"
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

# Quick Look plugins (preview files in Finder with spacebar)
brew_cask_install "qlmarkdown" "QLMarkdown (preview Markdown in Finder)"
brew_cask_install "qlstephen" "QLStephen (preview plain text files without extension)"
# QuickLookJSON — removed from Homebrew (disabled 2025-12); macOS handles JSON preview natively now

fi  # mac-system

# =============================================================================
if should_run "mac-productivity"; then
banner "Mac Apps — Productivity"

brew_cask_install "claude" "Claude (AI assistant)"
# Notion (GUI) replaced by tiki — terminal Markdown workspace (tasks/docs/kanban/wiki, git-backed).
trust_tap boolean-maybe/tap
brew_install "tiki" "tiki (terminal Markdown workspace — tasks, docs, kanban, wiki; git-backed)"
# Notion Calendar (GUI) replaced by khal + vdirsyncer (unified Gmail + iCloud, below).
# Terminal email (Gmail work + iCloud personal):
brew_install "aerc" "aerc (terminal email — Gmail XOAUTH2 + iCloud IMAP, multi-account)"
brew_install "khal" "khal (terminal calendar — unified Gmail + iCloud via vdirsyncer)"
brew_install "vdirsyncer" "vdirsyncer (sync CalDAV to local storage for khal)"
brew_cask_install "shottr" "Shottr (fast native screenshots — scrolling capture, OCR, annotations)"

# PDF & documents
brew_cask_install "skim" "Skim (lightweight PDF reader with annotations — faster than Preview)"

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
brew_install "kew" "kew (terminal music player — search-to-play, gapless, spectrum visualizer)"

fi  # mac-media

# =============================================================================
if should_run "mac-cloud"; then
banner "Mac Apps — Cloud Storage"

# Google Drive (GUI) removed — rclone handles Google Drive (and S3/Dropbox/etc.) from the terminal.

# Backup & sync
brew_install "rclone" "rclone (sync files to any cloud — Google Drive, S3, Dropbox, etc.)"
brew_install "borgbackup" "borg (deduplicated encrypted backups — better than Time Machine for offsite)"
brew_install "borgmatic" "borgmatic (automated borg backup scheduling and config)"

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

# Helix - Dracula theme is bundled with Helix and set via ~/.config/helix/config.toml
# (see the Helix config block below). No extension install needed.

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
"Docs" = "󰈙 "
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
git config --global alias.cleanup "!git branch --merged main | grep -v '\\*\\|main\\|master' | xargs -n 1 git branch -d"
git config --global alias.gone "!git fetch -p && git branch -vv | grep ': gone]' | awk '{print \$1}' | xargs -r git branch -d"

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
LAZYGIT_CONFIG_DIR="$HOME/Library/Application Support/lazygit"
LAZYGIT_CONFIG="$LAZYGIT_CONFIG_DIR/config.yml"
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
  edit: 'hx {{filename}}'
  editAtLine: 'hx {{filename}}:{{line}}'
  editAtLineAndWait: 'hx {{filename}}:{{line}}'
  editInTerminal: true
  open: "open {{filename}}"
  openLink: "open {{link}}"
notARepository: skip
promptToReturnFromSubprocess: false
LAZYGIT_CONF
    success "lazygit configured (Dracula theme, delta pager, auto-fetch, Helix editor)"
fi  # installed lazygit

# ---- k9s Dracula skin ----
K9S_SKINS_DIR="$HOME/Library/Application Support/k9s/skins"
K9S_CONFIG_DIR="$HOME/Library/Application Support/k9s"
K9S_SKIN="$K9S_SKINS_DIR/dracula.yaml"
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
    success "k9s Dracula skin configured"

# ---- Helix editor config ----
HELIX_CONFIG_DIR="$HOME/.config/helix"
info "Configuring Helix (Dracula theme, LSP, auto-format)..."
write_managed "$HELIX_CONFIG_DIR/config.toml" "#" <<'HELIX_CONF'
theme = "dracula"

[editor]
line-number = "relative"
mouse = true
cursorline = true
color-modes = true
true-color = true
bufferline = "multiple"
rulers = [100]
scrolloff = 8
completion-trigger-len = 1
auto-format = true
auto-save = true

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.file-picker]
hidden = false

[editor.lsp]
display-messages = true
display-inlay-hints = true

[editor.statusline]
left = ["mode", "spinner", "file-name", "file-modification-indicator"]
center = []
right = ["diagnostics", "selections", "position", "file-encoding", "file-type"]

[editor.indent-guides]
render = true
character = "▏"

[editor.soft-wrap]
enable = true

[keys.normal]
"C-s" = ":w"
# Claude via llm: pipe the selection to Claude and replace it with the result.
# Set your default model to Claude first:  llm models default claude-sonnet-4-5
# (For "explain"/chat, use the Claude Code pane — see the 'dev' zellij layout.)
"A-a" = ":pipe llm 'Improve the selection. Output only the replacement text, no explanation.'"
HELIX_CONF
write_managed "$HELIX_CONFIG_DIR/languages.toml" "#" <<'HELIX_LANG'
# Ruff as the Python language server (matches the project's ruff-first Python rule)
[language-server.ruff]
command = "ruff"
args = ["server"]

# helix-assist: Claude AI as an LSP (ghost-text completions + `Space A` code-actions).
# Needs ANTHROPIC_API_KEY in the environment; if unset it simply provides nothing.
[language-server.helix-assist]
command = "helix-assist"
args = ["--handler", "anthropic", "--num-suggestions", "2"]

[[language]]
name = "python"
language-servers = ["ruff", "helix-assist"]
auto-format = true

[[language]]
name = "typescript"
language-servers = ["typescript-language-server", "helix-assist"]
auto-format = true

[[language]]
name = "tsx"
language-servers = ["typescript-language-server", "helix-assist"]
auto-format = true

[[language]]
name = "javascript"
language-servers = ["typescript-language-server", "helix-assist"]
auto-format = true

[[language]]
name = "jsx"
language-servers = ["typescript-language-server", "helix-assist"]
auto-format = true

[[language]]
name = "rust"
language-servers = ["rust-analyzer", "helix-assist"]
auto-format = true

[[language]]
name = "go"
language-servers = ["gopls", "helix-assist"]
auto-format = true

[[language]]
name = "json"
auto-format = true

[[language]]
name = "yaml"
auto-format = true

[[language]]
name = "toml"
auto-format = true
HELIX_LANG
success "Helix configured (Dracula, ruff LSP, auto-format; managed block — edits outside the markers are kept)"

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
        add_mcp github --transport stdio --env "GITHUB_PERSONAL_ACCESS_TOKEN=\${GITHUB_TOKEN}" github -- npx -y @modelcontextprotocol/server-github
        add_mcp git --transport stdio git -- uvx mcp-server-git
        add_mcp fetch --transport stdio fetch -- uvx mcp-server-fetch
        add_mcp context7 --transport stdio context7 -- npx -y @upstash/context7-mcp
        add_mcp aws-docs --transport stdio aws-docs -- uvx awslabs.aws-documentation-mcp-server
        add_mcp aws-pricing --transport stdio aws-pricing -- uvx awslabs.aws-pricing-mcp-server@latest
        add_mcp aws-iac --transport stdio aws-iac -- uvx awslabs.aws-iac-mcp-server@latest
        add_mcp aws-knowledge --transport stdio aws-knowledge -- uvx awslabs.aws-knowledge-mcp-server@latest
        add_mcp cloudwatch --transport stdio --env "AWS_REGION=\${AWS_REGION}" --env "AWS_PROFILE=\${AWS_PROFILE}" cloudwatch -- uvx awslabs.cloudwatch-mcp-server@latest
        add_mcp iam --transport stdio --env "AWS_REGION=\${AWS_REGION}" --env "AWS_PROFILE=\${AWS_PROFILE}" iam -- uvx awslabs.iam-mcp-server@latest
        unset -f add_mcp

        success "Claude Code MCP servers configured (user scope)"
        info "  Added: filesystem, github, git, fetch, context7, aws-docs, aws-pricing,"
        info "         aws-iac, aws-knowledge, cloudwatch, iam"
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

# leaf (Markdown previewer) runs on sensible defaults; no config block generated.

# ---- ngrok config ----
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
if ! is_done "config:ngrok"; then
if [[ ! -d "$NGROK_CONFIG_DIR" ]]; then
    info "Creating ngrok config directory..."
    mkdir -p "$NGROK_CONFIG_DIR"
    cat > "$NGROK_CONFIG_DIR/ngrok.yml" <<'NGROK_CONF'
# ngrok configuration
# Add your authtoken: ngrok config add-authtoken <TOKEN>
version: "3"
agent:
  metadata: "dev-machine"
NGROK_CONF
    # Lock down: ngrok.yml will hold your authtoken.
    chmod 700 "$NGROK_CONFIG_DIR" 2>/dev/null || true
    chmod 600 "$NGROK_CONFIG_DIR/ngrok.yml" 2>/dev/null || true
    success "ngrok config created (add authtoken: ngrok config add-authtoken <TOKEN>)"
else
    warn "ngrok config directory already exists"
fi
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
if [[ ! -d "$CADDY_CONFIG_DIR" ]]; then
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
else
    warn "Caddy config directory already exists"
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
ACT_CONF
    success "act configured (medium Ubuntu images, container reuse)"

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
ASCIINEMA_CONFIG="$ASCIINEMA_CONFIG_DIR/config"
    info "Creating asciinema configuration..."
    write_managed "$ASCIINEMA_CONFIG" "#" <<'ASCIINEMA_CONF'
[record]
# Idle time limit (seconds) — trims long pauses
idle_time_limit = 2

# Input recording (disable for security — don't record keystrokes)
stdin = no

# Default command to record
command = /bin/zsh -l

# Overwrite existing file without prompt
overwrite = yes
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
            command "hx"
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

# ---- kew config ----
# kew stores its config at ~/Library/Preferences/kew/kewrc on macOS. Format is
# key=value (no spaces); keys verified against kew source. Written as a managed
# block so re-runs refresh our keys while any of your own (outside the markers) stay.
KEW_CONFIG_DIR="$HOME/Library/Preferences/kew"
KEW_CONFIG="$KEW_CONFIG_DIR/kewrc"
info "Configuring kew (music library, visualizer)..."
write_managed "$KEW_CONFIG" "#" <<'KEW_CONF'
[miscellaneous]
path=~/Media/music
allowNotifications=1

[track cover]
coverEnabled=1
coverStyle=auto

[visualizer]
visualizerColorType=3
visualizerHeight=6
KEW_CONF
success "kew configured (music library ~/Media/music, party visualizer)"

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
NUSHELL_CONFIG_DIR="$HOME/Library/Application Support/nushell"
NUSHELL_ENV="$NUSHELL_CONFIG_DIR/env.nu"
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
# VS Code layout (still common in shared repos even though local editor is Helix)
.vscode/settings.json
.vscode/launch.json
*.code-workspace
# Helix keeps no per-repo state by default (config lives in ~/.config/helix).

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
# Don't automatically rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false
# Speed up Mission Control animations
defaults write com.apple.dock expose-animation-duration -float 0.15
# Group windows by application in Mission Control
defaults write com.apple.dock expose-group-apps -bool true
success "Mission Control configured (fixed spaces, fast animations)"

# -- Hot Corners (all disabled to prevent accidental triggers) --
defaults write com.apple.dock wvous-tl-corner -int 1
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-corner -int 1
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-br-modifier -int 0
success "Hot corners disabled (all corners off)"

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
# Reduce motion for faster UI
defaults write com.apple.universalaccess reduceMotion -bool true
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
success "Misc macOS defaults configured"


# -- Screensaver & display sleep timing --
# Screensaver kicks in at 45 min, display sleep at 2hr (charger) / 1hr 15min (battery)
defaults -currentHost write com.apple.screensaver idleTime -int 2700 2>/dev/null || true
sudo pmset -c displaysleep 120 2>/dev/null || true  # charger: 2 hours
sudo pmset -b displaysleep 75 2>/dev/null || true   # battery: 1hr 15min
success "Screensaver at 45min, display sleep at 2hr (charger) / 1h15m (battery)"

# Restart Dock to apply all Dock/Hot Corner/Mission Control changes
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
export EDITOR="hx"
export VISUAL="hx"

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

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

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

# Pre-commit hook: check for common issues
write_managed_script "$GIT_HOOKS_DIR/pre-commit" <<'HOOK_PRECOMMIT'
#!/usr/bin/env bash
# Global pre-commit hook — runs on ALL repos
# Note: core.hooksPath overrides per-repo .git/hooks — this hook delegates to per-repo hooks if they exist

# Delegate to per-repo hook if it exists
if [ -x ".git/hooks/pre-commit" ]; then
    exec .git/hooks/pre-commit "$@"
fi

# Check for debug statements (-z/-0/-r: handle spaces in names + empty staged set)
if git diff --cached --name-only -z | xargs -0 -r grep -l 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null; then
    echo ""
    echo "WARNING: Debug statements found in staged files:"
    git diff --cached --name-only -z | xargs -0 -r grep -n 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null
    echo ""
    echo "Remove them or commit with --no-verify to bypass."
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
    echo "WARNING: Large files detected (>5MB):"
    echo "$large_files"
    echo ""
    echo "Consider using git-lfs or commit with --no-verify to bypass."
    exit 1
fi

# Check for merge conflict markers
if git diff --cached --name-only -z | xargs -0 -r grep -l '<<<<<<<\|=======\|>>>>>>>' 2>/dev/null; then
    echo ""
    echo "ERROR: Merge conflict markers found in staged files."
    exit 1
fi

exit 0
HOOK_PRECOMMIT

# Register global hooks directory
git config --global core.hooksPath "$GIT_HOOKS_DIR"

success "Global git hooks created (debug check, large file check, conflict markers)"

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
editor: hx
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
    success "GitHub CLI configured (SSH protocol, Helix editor, delta pager, aliases)"

# ---- pip config ----
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
    @tokei . 2>/dev/null || find . -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' -o -name '*.rs' | xargs wc -l | tail -1
JUSTFILE_CONF
    success "Global justfile created (~/.justfile — system, git, docker, network, cleanup, info recipes)"

# ---- Ghostty config ----
GHOSTTY_CONFIG_DIR="$HOME/.config/ghostty"
GHOSTTY_CONFIG="$GHOSTTY_CONFIG_DIR/config"
info "Configuring Ghostty..."
write_managed "$GHOSTTY_CONFIG" "#" <<'GHOSTTY_CONF'
# Ghostty configuration
# Docs: https://ghostty.org/docs/config

# Font
font-family = "JetBrains Mono"
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
quick-terminal-screen = main
quick-terminal-animation-duration = 0.15
quick-terminal-autohide = true
GHOSTTY_CONF
success "Ghostty configured (JetBrains Mono, Dracula theme, transparent titlebar)"

# ---- AeroSpace config (tiling window manager) ----
AEROSPACE_DIR="$HOME/.config/aerospace"
info "Configuring AeroSpace (i3-style keys, gaps, SketchyBar hook)..."
write_managed "$AEROSPACE_DIR/aerospace.toml" "#" <<'AEROSPACE_CONF'
# AeroSpace — tiling window manager. Docs: https://nikitabobko.github.io/AeroSpace/guide
# No SIP disable required. Set macOS "Displays have separate Spaces" = OFF.
start-at-login = true

enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

# Notify SketchyBar when the focused workspace changes (updates the bar pills).
exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE']

[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.bottom = 8
outer.top = 8
outer.right = 8

[mode.main.binding]
# Focus (Option + hjkl)
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# Move window (Option + Shift + hjkl)
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

# Layout + fullscreen
alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'
alt-f = 'fullscreen'

# Resize
alt-minus = 'resize smart -50'
alt-equal = 'resize smart +50'

# Workspaces
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'

# Move focused window to workspace
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'
alt-shift-6 = 'move-node-to-workspace 6'
alt-shift-7 = 'move-node-to-workspace 7'
alt-shift-8 = 'move-node-to-workspace 8'
alt-shift-9 = 'move-node-to-workspace 9'

alt-tab = 'workspace-back-and-forth'
alt-shift-c = 'reload-config'
alt-shift-semicolon = 'mode service'

[mode.service.binding]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
f = ['layout floating tiling', 'mode main']
backspace = ['close-all-windows-but-current', 'mode main']
AEROSPACE_CONF
success "AeroSpace configured (Option+hjkl focus, workspaces 1-9, SketchyBar hook)"

# ---- SketchyBar config (Dracula status bar + AeroSpace workspaces) ----
# Shell-based config (no SbarLua build step). Plugins are simple + label-based so
# they render without depending on specific Nerd Font glyphs; tune styling later.
SBAR_DIR="$HOME/.config/sketchybar"
SBAR_PLUGINS="$SBAR_DIR/plugins"
    info "Creating SketchyBar configuration (Dracula, AeroSpace pills, system widgets)..."

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
SBAR_COLORS

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
                     label.font="$FONT:Semibold:13.0" label.color=$FG \
                     padding_left=5 padding_right=5 \
                     background.color=$LINE background.corner_radius=6 background.height=22

# --- Left: AeroSpace workspaces ---
sketchybar --add event aerospace_workspace_change
for sid in $(aerospace list-workspaces --all 2>/dev/null); do
  sketchybar --add item space.$sid left \
             --subscribe space.$sid aerospace_workspace_change \
             --set space.$sid label="$sid" icon.drawing=off \
                   background.color=$LINE \
                   click_script="aerospace workspace $sid" \
                   script="$PLUGIN_DIR/aerospace.sh $sid"
done

# --- Left: focused app ---
sketchybar --add item front_app left \
           --subscribe front_app front_app_switched \
           --set front_app icon.drawing=off label.color=$PURPLE label.font="$FONT:Bold:13.0" \
                 script="$PLUGIN_DIR/front_app.sh"

# --- Center: clock (click opens khal in a Ghostty quick terminal) ---
sketchybar --add item clock center \
           --set clock update_freq=10 icon.drawing=off \
                 click_script="open -a Ghostty; sleep 0.2; osascript -e 'tell application \"System Events\" to keystroke \"khal\" & return' >/dev/null 2>&1" \
                 script="$PLUGIN_DIR/clock.sh"

# --- Right (added right-to-left visually) ---
sketchybar --add item battery right \
           --subscribe battery system_woke power_source_change \
           --set battery update_freq=120 script="$PLUGIN_DIR/battery.sh"

sketchybar --add item bluetooth right \
           --set bluetooth update_freq=30 icon.drawing=off label.color=$PURPLE \
                 click_script="blueutil --power toggle" \
                 script="$PLUGIN_DIR/bluetooth.sh"

sketchybar --add item wifi right \
           --set wifi update_freq=30 icon.drawing=off label.color=$GREEN \
                 script="$PLUGIN_DIR/wifi.sh"

sketchybar --add item volume right \
           --subscribe volume volume_change \
           --set volume icon.drawing=off script="$PLUGIN_DIR/volume.sh"

sketchybar --add item cpu right \
           --set cpu update_freq=5 icon.drawing=off label.color=$ORANGE \
                 script="$PLUGIN_DIR/cpu.sh"

sketchybar --add item mem right \
           --set mem update_freq=10 icon.drawing=off label.color=$YELLOW \
                 script="$PLUGIN_DIR/mem.sh"

sketchybar --add item vpn right \
           --set vpn update_freq=15 icon.drawing=off \
                 click_script="$PLUGIN_DIR/vpn_toggle.sh" \
                 script="$PLUGIN_DIR/vpn.sh"

sketchybar --update
SBAR_RC

    # -- plugins --
    write_managed_script "$SBAR_PLUGINS/aerospace.sh" <<'P_AERO'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
    sketchybar --set "$NAME" background.color=$PURPLE label.color=$BG
else
    sketchybar --set "$NAME" background.color=$LINE label.color=$FG
fi
P_AERO

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
LABEL="${PCT}%"
[ "$CHARGING" -gt 0 ] && LABEL="${PCT}%+"
sketchybar --set "$NAME" drawing=on icon.drawing=off label="$LABEL" label.color=$COLOR
P_BATT

    write_managed_script "$SBAR_PLUGINS/bluetooth.sh" <<'P_BT'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
if command -v blueutil >/dev/null 2>&1 && [ "$(blueutil --power)" = "1" ]; then
    sketchybar --set "$NAME" label="BT" label.color=$PURPLE
else
    sketchybar --set "$NAME" label="BT" label.color=$COMMENT
fi
P_BT

    write_managed_script "$SBAR_PLUGINS/wifi.sh" <<'P_WIFI'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
SSID=$(ipconfig getsummary en0 2>/dev/null | awk -F ' SSID : ' '/ SSID : / {print $2; exit}')
if [ -n "$SSID" ]; then
    sketchybar --set "$NAME" label="$SSID" label.color=$GREEN
else
    sketchybar --set "$NAME" label="off" label.color=$COMMENT
fi
P_WIFI

    write_managed_script "$SBAR_PLUGINS/volume.sh" <<'P_VOL'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
VOL="${INFO:-$(osascript -e 'output volume of (get volume settings)')}"
sketchybar --set "$NAME" label="vol ${VOL}%" label.color=$CYAN
P_VOL

    write_managed_script "$SBAR_PLUGINS/cpu.sh" <<'P_CPU'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%d", s/'"$(sysctl -n hw.ncpu)"'}')
sketchybar --set "$NAME" label="cpu ${CPU}%" label.color=$ORANGE
P_CPU

    write_managed_script "$SBAR_PLUGINS/mem.sh" <<'P_MEM'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
USED=$(memory_pressure 2>/dev/null | awk -F ': ' '/System-wide memory free percentage/ {print 100-$2}' | tr -d '%')
[ -z "$USED" ] && USED="?"
sketchybar --set "$NAME" label="mem ${USED}%" label.color=$YELLOW
P_MEM

    write_managed_script "$SBAR_PLUGINS/vpn.sh" <<'P_VPN'
#!/usr/bin/env bash
source "$HOME/.config/sketchybar/colors.sh"
if command -v mullvad >/dev/null 2>&1 && mullvad status 2>/dev/null | grep -qi 'Connected'; then
    sketchybar --set "$NAME" label="VPN" label.color=$GREEN
else
    sketchybar --set "$NAME" label="VPN" label.color=$RED
fi
P_VPN

    write_managed_script "$SBAR_PLUGINS/vpn_toggle.sh" <<'P_VPNT'
#!/usr/bin/env bash
command -v mullvad >/dev/null 2>&1 || exit 0
if mullvad status 2>/dev/null | grep -qi 'Connected'; then mullvad disconnect; else mullvad connect; fi
P_VPNT

    if [[ "$DRY_RUN" != "true" ]] && installed sketchybar; then
        brew services restart sketchybar >> "$LOG_FILE" 2>&1 || warn "Could not start sketchybar service (grant it Accessibility if needed)"
    fi
    success "SketchyBar configured (Dracula, AeroSpace pills, system widgets)"

# ---- clipse clipboard listener (launchd agent) ----
# clipse runs a background listener to capture clipboard history. Register a
# LaunchAgent so it starts at login.
CLIPSE_BIN="$(command -v clipse || echo "$GOBIN/clipse")"
CLIPSE_PLIST="$HOME/Library/LaunchAgents/com.clipse.listener.plist"
if ! is_done "config:clipse"; then
if [[ ! -x "$CLIPSE_BIN" ]]; then
    warn "clipse not installed — skipping clipboard listener agent"
elif [[ -f "$CLIPSE_PLIST" ]]; then
    warn "clipse launch agent already exists"
else
    info "Creating clipse clipboard-listener launch agent..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$CLIPSE_PLIST" <<CLIPSE_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.clipse.listener</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLIPSE_BIN</string>
        <string>-listen</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
CLIPSE_PLIST_EOF
    if [[ "$DRY_RUN" != "true" ]]; then
        launchctl unload "$CLIPSE_PLIST" >> "$LOG_FILE" 2>&1 || true
        launchctl load "$CLIPSE_PLIST" >> "$LOG_FILE" 2>&1 || warn "Could not load clipse launch agent"
    fi
    success "clipse clipboard listener registered (starts at login)"
fi
mark_done "config:clipse"
fi

# ---- aerc email config (skeleton — secrets are manual) ----
# aerc handles Gmail (XOAUTH2) + iCloud (app-specific password) in one client.
# We write a commented skeleton; fill the placeholders per POST_SETUP_CHECKLIST.md.
AERC_DIR="$HOME/.config/aerc"
if ! is_done "config:aerc"; then
if [[ -f "$AERC_DIR/accounts.conf" ]]; then
    warn "aerc config already exists"
else
    info "Creating aerc config skeleton (Gmail + iCloud accounts)..."
    mkdir -p "$AERC_DIR"
    cat > "$AERC_DIR/accounts.conf" <<'AERC_ACCOUNTS'
# aerc accounts — fill in the placeholders (see ~/Desktop/POST_SETUP_CHECKLIST.md).
# Personal (iCloud): generate an app-specific password at appleid.apple.com.
# aerc will prompt for the password on first connect (or use a source-cred-cmd).

[Personal (iCloud)]
source   = imaps://YOUR_APPLEID%40icloud.com@imap.mail.me.com:993
outgoing = smtps://YOUR_APPLEID%40icloud.com@smtp.mail.me.com:587
from     = Your Name <YOUR_APPLEID@icloud.com>
copy-to  = Sent Messages

# Work (Gmail): create a Google Cloud OAuth "Desktop" app, then obtain a refresh
# token. Paste client id/secret + token below (aerc refreshes the token itself).
[Work (Gmail)]
source   = imaps+xoauth2://YOUR_ADDR%40gmail.com@imap.gmail.com:993
outgoing = smtps+xoauth2://YOUR_ADDR%40gmail.com@smtp.gmail.com:465
from     = Your Name <YOUR_ADDR@gmail.com>
oauth2_client_id     = YOUR_GOOGLE_CLIENT_ID
oauth2_client_secret = YOUR_GOOGLE_CLIENT_SECRET
oauth2_token_endpoint = https://accounts.google.com/o/oauth2/token
outgoing-cred-cmd = # set by aerc after OAuth; leave blank initially
copy-to  = "[Gmail]/Sent Mail"
AERC_ACCOUNTS
    cat > "$AERC_DIR/aerc.conf" <<'AERC_CONF'
[general]
unsafe-accounts-conf = false

[ui]
threading-enabled = true
sidebar-width = 22
index-columns = date<20,name<20,flags>4,subject<*
timestamp-format = 2006-01-02 15:04
this-day-time-format = 15:04

[viewer]
pager = less -R
alternatives = text/plain,text/html
html = false

[filters]
text/plain = colorize
text/html = pandoc -f html -t plain 2>/dev/null || cat
AERC_CONF
    # binds.conf: start from aerc's shipped defaults so we don't clobber them,
    # then append an AI summarize/triage bind (Claude via llm + llm-anthropic).
    AERC_SHARE="$(brew --prefix 2>/dev/null)/share/aerc"
    if [[ -f "$AERC_SHARE/binds.conf" ]]; then
        cp "$AERC_SHARE/binds.conf" "$AERC_DIR/binds.conf"
    else
        : > "$AERC_DIR/binds.conf"
    fi
    cat >> "$AERC_DIR/binds.conf" <<'AERC_BINDS'

# AI: summarize/triage the selected message with Claude (llm + llm-anthropic).
# Set your default llm model to Claude first: llm models default claude-sonnet-4-5
[messages]
S = :pipe -m llm "Summarize this email in 3 concise bullets and suggest a triage label"<Enter>
AERC_BINDS
    # Lock down: accounts.conf holds the iCloud app-password + Gmail OAuth secret.
    # aerc also requires 0600 here (unsafe-accounts-conf = false) to use the password.
    chmod 700 "$AERC_DIR" 2>/dev/null || true
    chmod 600 "$AERC_DIR/accounts.conf" "$AERC_DIR/aerc.conf" 2>/dev/null || true
    success "aerc config skeleton created (edit accounts.conf with your credentials)"
fi
mark_done "config:aerc"
fi

# ---- khal + vdirsyncer config (unified Gmail + iCloud calendar) ----
# vdirsyncer syncs both CalDAV sources to local .ics; khal reads them.
# Credentials (iCloud app-password, Google OAuth client) are filled in manually.
if ! is_done "config:khal-vdirsyncer"; then
VDIR_DIR="$HOME/.config/vdirsyncer"
KHAL_DIR="$HOME/.config/khal"
if [[ -f "$VDIR_DIR/config" ]]; then
    warn "vdirsyncer/khal config already exists"
else
    info "Creating khal + vdirsyncer config skeletons..."
    mkdir -p "$VDIR_DIR" "$KHAL_DIR" \
             "$HOME/.local/share/calendars/personal" \
             "$HOME/.local/share/calendars/work" \
             "$HOME/.local/share/vdirsyncer/status"
    cat > "$VDIR_DIR/config" <<'VDIR_CONF'
# vdirsyncer — fill in usernames + credentials (see POST_SETUP_CHECKLIST.md).
[general]
status_path = "~/.local/share/vdirsyncer/status/"

# --- iCloud (personal) via CalDAV + app-specific password ---
[pair icloud]
a = "icloud_local"
b = "icloud_remote"
collections = ["from a", "from b"]
metadata = ["color", "displayname"]

[storage icloud_local]
type = "filesystem"
path = "~/.local/share/calendars/personal/"
fileext = ".ics"

[storage icloud_remote]
type = "caldav"
url = "https://caldav.icloud.com/"
username = "YOUR_APPLEID@icloud.com"
# App-specific password from appleid.apple.com:
password = "YOUR_ICLOUD_APP_SPECIFIC_PASSWORD"

# --- Google (work) via the native google_calendar storage (OAuth) ---
[pair google]
a = "google_local"
b = "google_remote"
collections = ["from a", "from b"]
metadata = ["color", "displayname"]

[storage google_local]
type = "filesystem"
path = "~/.local/share/calendars/work/"
fileext = ".ics"

[storage google_remote]
type = "google_calendar"
token_file = "~/.local/share/vdirsyncer/google_token"
client_id = "YOUR_GOOGLE_CLIENT_ID"
client_secret = "YOUR_GOOGLE_CLIENT_SECRET"
VDIR_CONF
    # Lock down: vdirsyncer config holds the iCloud app-password + Google client_secret.
    chmod 700 "$VDIR_DIR" 2>/dev/null || true
    chmod 600 "$VDIR_DIR/config" 2>/dev/null || true
    cat > "$KHAL_DIR/config" <<'KHAL_CONF'
[calendars]

[[personal]]
path = ~/.local/share/calendars/personal/*
type = discover
color = light magenta

[[work]]
path = ~/.local/share/calendars/work/*
type = discover
color = light cyan

[locale]
timeformat = %H:%M
dateformat = %Y-%m-%d
longdateformat = %Y-%m-%d %a
datetimeformat = %Y-%m-%d %H:%M
weeknumbers = left

[default]
default_calendar = personal
highlight_event_days = True
KHAL_CONF
    success "khal + vdirsyncer skeletons created (run 'vdirsyncer discover' after adding creds)"
fi
mark_done "config:khal-vdirsyncer"
fi

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
    "$HOME/Docs/finance"    # statements, taxes, invoices
    "$HOME/Docs/health"
    "$HOME/Docs/admin"      # legal, insurance, contracts
    "$HOME/Docs/receipts"
    "$HOME/Docs/travel"

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
success "Directory structure created (~/Inbox, ~/Code, ~/Scripts, ~/Docs, ~/Creative, ~/Media, ~/Archive)"

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

# Create project-level CLAUDE.md for AI context
mkdir -p .claude
cat > CLAUDE.md <<CLAUDEMD
# $NAME

## Overview
<!-- Describe what this project does -->

## Tech Stack
<!-- Languages, frameworks, key libraries -->

## Development
- Install: \`pnpm install\`
- Dev: \`pnpm dev\`
- Test: \`pnpm test\`
- Build: \`pnpm build\`

## Conventions
<!-- Project-specific conventions not in the global CLAUDE.md -->
CLAUDEMD

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

# (write_managed_script sets +x on each script; no blanket chmod needed.)
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

# Disable warning when emptying trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

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

        # Add our organized folders to sidebar.
        # Inbox and Downloads (the two dump zones) go first for zero-friction access.
        SIDEBAR_FOLDERS=(
            "$HOME/Inbox"
            "$HOME/Downloads"
            "$HOME/Code"
            "$HOME/Docs"
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

# ---- Spaces: one space spans all displays (AeroSpace needs this) ----
# Equivalent to "Displays have separate Spaces = OFF". Takes effect after logout.
defaults write com.apple.spaces spans-displays -bool true 2>/dev/null || true
success "Displays set to share one Space (for AeroSpace) — takes effect after logout"

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
    CLAUDE_ADD_ALLOW='["Bash(qalc *)","Bash(has *)","Bash(doxx *)","Bash(mdfind *)","Bash(atac *)","Bash(leaf *)","Bash(git status *)","Bash(git diff *)","Bash(git log *)","Bash(git show *)","Bash(git branch *)","Bash(git remote -v)","Bash(git stash list)"]'
    CLAUDE_DENY_ALLOW='["Bash(npm *)","Bash(npx *)","Bash(pnpm *)","Bash(bun *)","Bash(node *)","Bash(tsx *)","Bash(ts-node *)","Bash(python3 *)","Bash(pip *)","Bash(uv *)","Bash(uvx *)","Bash(cargo *)","Bash(go *)","Bash(just *)","Bash(make *)","Bash(nu *)","Bash(nushell *)","Bash(aider *)","Bash(topgrade *)","Bash(watchexec *)","Bash(viddy *)","Bash(parallel *)","Bash(act *)","Bash(curl *)","Bash(xh *)","Bash(wget *)","Bash(curlie *)","Bash(aria2c *)","Bash(grpcurl *)","Bash(yt-dlp *)","Bash(aws *)","Bash(cdk *)","Bash(sam *)","Bash(docker *)","Bash(docker-compose *)","Bash(docker compose *)","Bash(kubectl *)","Bash(tofu *)","Bash(s5cmd *)","Bash(dynein *)","Bash(steampipe *)","Bash(iamlive *)","Bash(granted *)","Bash(assume *)","Bash(mitmproxy *)","Bash(mitmdump *)","Bash(nmap *)","Bash(chezmoi *)","Bash(dbmate *)","Bash(env *)","Bash(export *)","Bash(git *)","Bash(git-*)","Bash(gh *)","Bash(cp *)","Bash(mv *)","Bash(trash *)","Bash(sd *)","Bash(sed *)","Bash(awk *)","Bash(find *)","Bash(npkill *)","Bash(ouch *)","Bash(7z *)","Write"]'
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would merge settings.json: add safe allow entries + statusline, strip dangerous ones"
    elif command -v jq &>/dev/null; then
        info "Merging + hardening Claude settings.json permissions..."
        CLAUDE_TMP=$(mktemp)
        if jq --argjson add "$CLAUDE_ADD_ALLOW" --argjson deny "$CLAUDE_DENY_ALLOW" \
            '.permissions.allow = (((.permissions.allow // []) + $add) - $deny | unique)
             | .statusLine = (.statusLine // {"type":"command","command":"~/.claude/statusline.sh"})' \
            "$CLAUDE_SETTINGS" > "$CLAUDE_TMP" 2>/dev/null; then
            mv "$CLAUDE_TMP" "$CLAUDE_SETTINGS"
            success "Claude settings.json hardened (safe allowlist + statusline; dangerous auto-approvals stripped)"
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
      "Bash(tokei *)",
      "Bash(dust *)",
      "Bash(wc -l *)",
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
      "Bash(trippy *)",
      "Bash(oxipng *)",
      "Bash(jpegoptim *)",
      "Bash(mpv *)",
      "Bash(newsboat *)",
      "Bash(zellij *)",
      "Bash(gum *)",
      "Bash(llm *)",
      "Bash(repomix *)",
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
      "Bash(rm -rf ~)",
      "Bash(rm -rf /*)",
      "Bash(sudo rm *)",
      "Bash(chmod 777 *)",
      "Bash(> /dev/sda*)",
      "Bash(mkfs *)"
    ]
  },

  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/format-on-edit.sh"
      },
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/lint-python.sh"
      },
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/lint-dockerfile.sh"
      }
    ]
  },

  "env": {
    "DISABLE_PROMPT_CACHING": "0"
  },

  "fileSuggestionSettings": {
    "ignoredPatterns": [
      "node_modules/**",
      ".git/**",
      ".next/**",
      "dist/**",
      "build/**",
      ".turbo/**",
      "coverage/**",
      ".nyc_output/**",
      "__pycache__/**",
      ".venv/**",
      ".terraform/**",
      "cdk.out/**",
      "target/**",
      "*.min.js",
      "*.min.css",
      "package-lock.json",
      "pnpm-lock.yaml",
      "yarn.lock",
      "Cargo.lock",
      "go.sum"
    ]
  },

  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
CLAUDE_SETTINGS_CONF
    success "Claude Code settings.json created (permissions, file ignore patterns, statusline)"
fi

# ---- Claude Code global CLAUDE.md (memory/instructions) ----
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    warn "Claude Code global CLAUDE.md already exists"
else
    info "Creating Claude Code global CLAUDE.md..."
    cat > "$CLAUDE_MD" <<'CLAUDE_MD_CONF'
# Global Development Standards

## Workflow Philosophy
- **Trunk-based development** — short-lived feature branches off main, merge back fast
- **PRs over direct commits** — every change goes through a pull request, no direct pushes to main
- **Issues for everything** — create GitHub issues before starting work, reference in PRs
- **README-driven development** — every project and significant module gets a README
- **Industry best practices** — follow established patterns, OWASP, 12-factor, SOLID, DRY

## Environment
- Shell: zsh with starship prompt, atuin history, fzf fuzzy finder, zsh-autosuggestions, zsh-syntax-highlighting
- Editor: Helix (`hx`) — modal terminal editor with built-in LSP, tree-sitter, Dracula theme; also the `EDITOR` for git/gh/lazygit. Agentic coding via Claude Code (`claude`).
- Terminal: Ghostty (Dracula theme)
- Package managers: pnpm (preferred), npm, bun
- Python: uv for packages (not pip), ruff for linting (not flake8/black)
- JS/TS runtimes: Node (via mise), Bun, Deno
- Version manager: mise (Node, Python, Go, Ruby — all in one)
- Container runtime: OrbStack (provides docker + kubectl)
- Task runner: just (prefer over make for project-level tasks)
- Shell note: `bat` is aliased to `cat`; use `/bin/cat` only inside heredoc subshells where bat breaks syntax
- Dotfiles: chezmoi
- Launcher: Ghostty quick terminal (global cmd+space) + shell functions `a` (app launcher), `ff`/`rgf`/`s` (file/content/Spotlight search). Window mgmt: AeroSpace (Option+hjkl). Bar: SketchyBar. Clipboard: clipse (`clip`)
- API client: ATAC (terminal — TUI + scriptable CLI; JSON/YAML collections, Postman import). Plus hurl / xh / curlie / grpcurl
- Database: pgcli, mycli, lazysql, harlequin (SQL IDE TUI), usql, sq; migrations via dbmate
- Diagrams: d2 / Mermaid (code-based, in the terminal)
- Screenshots: Shottr (saved to ~/Screenshots)
- File transfer: rclone (CLI — SFTP/S3/cloud)
- Proxy/debugger: mitmproxy
- Tunneling: ngrok
- Docs / PM: tiki (terminal Markdown workspace — tasks/docs/kanban/wiki, git-backed)
- Email: aerc (terminal — Gmail work + iCloud personal, multi-account)
- Calendar: khal + vdirsyncer (terminal — unified Google + iCloud CalDAV)
- Cloud storage: rclone (Google Drive, S3, Dropbox, etc.); borg for versioned backups
- Browser: Google Chrome (primary); Carbonyl / w3m in the terminal
- Password manager: Apple Passwords (iCloud Keychain) — no third-party manager installed

## Working Context
- Independent **fractional CIO/CTO and consultant**; company is **VixenTec LLC**.
- All company work runs on **Google Workspace** (Gmail, Docs/Sheets/Slides, Drive, Meet, Chat, Vids). Produce documents/deliverables in Google Workspace, not a local office suite (no LibreOffice/MS Office installed). Use **Google Meet** for calls (no Zoom); **Google Chat** for messaging (no Slack).
- Tool philosophy: prefer **open-source, CLI-first, privacy-preserving, and minimal** options; declutter aggressively. When recommending tools, lead with one option that fits these and flag any that don't.
- **ADD-friendly home layout** (low-decision, shallow): `~/Inbox` (dump zone — drop anything, sort later), `~/Code` (work/personal/oss/learning), `~/Docs` (finance, health, admin, receipts, travel), `~/Creative`, `~/Media`, `~/Archive`, `~/Screenshots`, `~/Scripts`. When in doubt where a file goes, suggest `~/Inbox` rather than a deep path.

## Available CLI Tools (use these instead of manual approaches)
- **Search**: `rg` (ripgrep) for content, `fd` for files, `fzf` for interactive
- **Data**: `jq` for JSON, `yq` for YAML, `mlr` for CSV, `fx`/`jnv` for interactive JSON, `csvkit` for CSV
- **Git**: `lazygit` for interactive UI, `delta` for diffs, `difft` for syntax-aware diffs, `git-cliff` for changelogs, `git-absorb` for auto fixup commits, `git-lfs` for large files
- **Docker**: `lazydocker` for UI, `dive` to inspect layers, `hadolint` for Dockerfile linting
- **Testing**: `hyperfine` to benchmark, `oha` for load testing, `hurl` for HTTP test files, `act` for local GitHub Actions
- **Code quality**: `typos` for spell checking, `ast-grep` for structural search/replace, `shellcheck`/`shfmt` for shell
- **Security**: `trivy` to scan containers/IaC, `gitleaks` for secrets, `semgrep` for static analysis, `detect-secrets` for pre-commit secret detection, `sops` for secrets encryption
- **IaC**: `tofu` (Terraform), `tflint` for linting, `terraform-docs` for module READMEs, `checkov` for static analysis, `infracost` for cost estimation, `cfn-lint` for CloudFormation, `aws-sam-cli` for SAM (note: `tfsec` checks live in `trivy config`)
- **AI / agentic**: `claude` (Claude Code) for in-terminal pair programming, `aider` for git-aware AI edit loops, `llm` for one-shot prompts and embeddings, `repomix` to pack a repo into a single LLM-friendly file
- **HTTP**: `xh` for colorized requests, `curlie` for curl with httpie output, `grpcurl` for gRPC
- **Network**: `trip` (trippy) for traceroute TUI, `sudo mtr` (requires root, lives in sbin), `bandwhich` for bandwidth, `nmap` for scanning, `mkcert` for local TLS certs
- **Docs**: `d2` for diagrams, `pandoc` for conversion, `leaf` for Markdown preview
- **Database**: `pgcli`/`mycli` for auto-completing SQL, `lazysql` for TUI, `sq` for cross-database queries, `dbmate` for migrations
- **File management**: `rovr` for the TUI file manager (`nnn` as a minimal fallback), `wiper` for interactive disk-usage cleanup (ncdu-like, Trash-safe), `watchexec` for running commands on file changes, `rclone` for cloud storage sync
- **Kubernetes**: `k9s` for TUI, `stern` for log tailing (kubectl via OrbStack)
- **AWS**: `granted`/`assume` for role switching; TUIs `e1s` (ECS), `stu` (S3), `e2c` (EC2), `claws` (broad, k9s-style); `steampipe` for SQL over AWS, `s5cmd` for fast S3 bulk ops, `dynein` for DynamoDB, `iamlive` to generate least-privilege IAM from observed calls
- **Shell scripting**: `gum` for interactive prompts/spinners, `nushell` for structured data pipelines, `parallel` for parallel execution
- **Terminal**: `tmux` or `zellij` for multiplexing, `mpv` for video playback, `kew` for a terminal music player, `asciinema` for recording
- **Images/Media**: `imagemagick` for image processing, `oxipng` for PNG optimization, `yt-dlp` for video downloads
- **Logs**: `lnav` for log file navigation
- **Modern replacements** (aliased over defaults): `bat`→cat, `eza`→ls, `procs`→ps, `dust`→du, `duf`→df, `btop`→top, `trash`→rm, `gping`→ping, `doggo`→dig, `viddy`→watch, `aria2c`→wget, `sd`→sed

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
    success "Claude Code global CLAUDE.md created"
fi

# ---- Claude Code rules directory ----
CLAUDE_RULES_DIR="$HOME/.claude/rules"
if [[ -d "$CLAUDE_RULES_DIR" ]]; then
    warn "Claude Code rules directory already exists"
else
    info "Creating Claude Code rules..."
    mkdir -p "$CLAUDE_RULES_DIR"

    # Workflow rules (trunk-based, PR-first)
    cat > "$CLAUDE_RULES_DIR/workflow.md" <<'WORKFLOW_RULES'
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
    cat > "$CLAUDE_RULES_DIR/git.md" <<'GIT_RULES'
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
    cat > "$CLAUDE_RULES_DIR/security.md" <<'SEC_RULES'
# Security Rules

- Never hardcode API keys, tokens, passwords, or secrets
- Use environment variables or AWS Secrets Manager for sensitive values
- Never log sensitive information (passwords, tokens, PII)
- Always validate and sanitize user input
- Use parameterized queries — never string-concatenate SQL
- Check npm audit before adding new dependencies
SEC_RULES

    # TypeScript rules
    cat > "$CLAUDE_RULES_DIR/typescript.md" <<'TS_RULES'
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
    cat > "$CLAUDE_RULES_DIR/python.md" <<'PY_RULES'
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
    cat > "$CLAUDE_RULES_DIR/docker.md" <<'DOCKER_RULES'
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
    cat > "$CLAUDE_RULES_DIR/iac.md" <<'IAC_RULES'
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

    success "Claude Code rules created (workflow, git, security, typescript, python, docker, iac)"
fi

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
    if [[ -f "$FILE" ]] && command -v prettier &>/dev/null; then
        # Only format if a prettier config exists in the project
        PROJECT_DIR=$(dirname "$FILE")
        while [[ "$PROJECT_DIR" != "/" ]]; do
            if [[ -f "$PROJECT_DIR/.prettierrc" ]] || [[ -f "$PROJECT_DIR/.prettierrc.json" ]] || [[ -f "$PROJECT_DIR/prettier.config.js" ]]; then
                prettier --write "$FILE" 2>/dev/null || true
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
        ruff check --fix "$FILE" 2>/dev/null || true
        ruff format "$FILE" 2>/dev/null || true
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
if [[ -d "$CLAUDE_AGENTS_DIR" ]] && [[ -n "$(ls -A "$CLAUDE_AGENTS_DIR" 2>/dev/null)" ]]; then
    warn "Claude Code agents directory already has agents"
else
    info "Creating Claude Code subagents (code-reviewer, aws-helper)..."
    mkdir -p "$CLAUDE_AGENTS_DIR"
    cat > "$CLAUDE_AGENTS_DIR/code-reviewer.md" <<'AGENT_REVIEWER'
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
    cat > "$CLAUDE_AGENTS_DIR/aws-helper.md" <<'AGENT_AWS'
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
fi

# ---- Claude Code custom slash commands ----
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
if [[ -d "$CLAUDE_COMMANDS_DIR" ]] && [[ "$(ls -A "$CLAUDE_COMMANDS_DIR" 2>/dev/null)" ]]; then
    warn "Claude Code commands directory already has commands"
else
    info "Creating Claude Code custom slash commands..."
    mkdir -p "$CLAUDE_COMMANDS_DIR"

    # /pr-review — review the current branch's changes
    cat > "$CLAUDE_COMMANDS_DIR/pr-review.md" <<'CMD_PR_REVIEW'
Review the changes on the current branch compared to main. For each file changed:
1. Summarize what changed and why
2. Flag any security issues, bugs, or performance concerns
3. Check for missing error handling or edge cases
4. Note any style inconsistencies

Use `git diff main...HEAD` to see all changes. Be concise — focus on issues, not praise.
CMD_PR_REVIEW

    # /test-plan — generate a test plan for recent changes
    cat > "$CLAUDE_COMMANDS_DIR/test-plan.md" <<'CMD_TEST_PLAN'
Look at the recent changes in this repo (use git diff or git log) and generate a test plan:
1. List what should be tested (unit, integration, e2e)
2. Identify edge cases and error scenarios
3. Suggest specific test cases with expected inputs/outputs
4. Note any areas that are hard to test and why

Output as a Markdown checklist.
CMD_TEST_PLAN

    # /dep-audit — audit dependencies
    cat > "$CLAUDE_COMMANDS_DIR/dep-audit.md" <<'CMD_DEP_AUDIT'
Audit the project dependencies:
1. Check for known vulnerabilities (run npm audit or pip audit)
2. Identify outdated packages (run npm outdated or pip list --outdated)
3. Flag any packages with no recent maintenance (>2 years)
4. Check for duplicate/redundant dependencies
5. Estimate total bundle size impact of each dependency if this is a frontend project

Summarize findings with severity (critical/high/medium/low) and recommended actions.
CMD_DEP_AUDIT

    # /quick-doc — generate docs for a file or function
    cat > "$CLAUDE_COMMANDS_DIR/quick-doc.md" <<'CMD_QUICK_DOC'
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
    cat > "$CLAUDE_COMMANDS_DIR/cleanup.md" <<'CMD_CLEANUP'
Scan the project for cleanup opportunities:
1. Unused imports and variables
2. Dead code (unreachable functions, unused exports)
3. Console.log / debug statements left in
4. TODO/FIXME comments that should be addressed
5. Empty catch blocks or swallowed errors

List each finding with file path and line number. Don't fix anything — just report.
CMD_CLEANUP

    # /security-scan — run all security tools
    cat > "$CLAUDE_COMMANDS_DIR/security-scan.md" <<'CMD_SECURITY'
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
    cat > "$CLAUDE_COMMANDS_DIR/perf-check.md" <<'CMD_PERF'
Analyze the performance of this project: $ARGUMENTS

1. If a command/script is given, benchmark it with `hyperfine`
2. If a URL is given, load test with `oha -n 500 -c 10 <url>`
3. If no argument, look at package.json scripts and suggest which to benchmark
4. Check for common performance anti-patterns in the code (N+1 queries, missing indexes, unbounded loops, sync I/O in async code)
5. Check bundle size if this is a frontend project (`npx @next/bundle-analyzer` or similar)

Report findings with concrete numbers and suggested optimizations.
CMD_PERF

    # /docker-lint — lint and optimize Docker setup
    cat > "$CLAUDE_COMMANDS_DIR/docker-lint.md" <<'CMD_DOCKER'
Analyze the Docker setup in this project:

1. Lint all Dockerfiles with `hadolint`
2. If images are built, analyze with `dive` for layer optimization opportunities
3. Check docker-compose.yml for best practices (health checks, resource limits, named volumes)
4. Verify .dockerignore exists and excludes node_modules, .git, etc.
5. Check for security issues: running as root, secrets in build args, latest tags

Fix any issues found and explain the changes.
CMD_DOCKER

    # /iac-review — review infrastructure code
    cat > "$CLAUDE_COMMANDS_DIR/iac-review.md" <<'CMD_IAC'
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
    cat > "$CLAUDE_COMMANDS_DIR/convert.md" <<'CMD_CONVERT'
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
    cat > "$CLAUDE_COMMANDS_DIR/new-feature.md" <<'CMD_NEW_FEATURE'
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
    cat > "$CLAUDE_COMMANDS_DIR/fix-bug.md" <<'CMD_FIX_BUG'
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
    cat > "$CLAUDE_COMMANDS_DIR/create-readme.md" <<'CMD_README'
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
    cat > "$CLAUDE_COMMANDS_DIR/init-project.md" <<'CMD_INIT'
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

## 3. Project-Level CLAUDE.md
Create a `.claude/CLAUDE.md` with project-specific context:
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
<Any project-specific conventions not in the global CLAUDE.md>
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
    cat > "$CLAUDE_COMMANDS_DIR/refactor.md" <<'CMD_REFACTOR'
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
    cat > "$CLAUDE_COMMANDS_DIR/add-endpoint.md" <<'CMD_ENDPOINT'
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
    cat > "$CLAUDE_COMMANDS_DIR/add-component.md" <<'CMD_COMPONENT'
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
    cat > "$CLAUDE_COMMANDS_DIR/ci-fix.md" <<'CMD_CIFIX'
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
    cat > "$CLAUDE_COMMANDS_DIR/changelog.md" <<'CMD_CHANGELOG'
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
    cat > "$CLAUDE_COMMANDS_DIR/commit-msg.md" <<'CMD_COMMIT'
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
fi

fi  # configs (Claude Code)

# =============================================================================
if should_run "shell"; then
banner "Shell Configuration"

ZSHRC="$HOME/.zshrc"

# Back up, migrate any pre-6.x marker, and seed a header on a brand-new file, then
# hand the block to write_managed so .zshrc uses the SAME splice logic as every
# other managed config. Personal edits outside the markers are preserved.
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
else
    cat > "$ZSHRC" <<'ZSHRC_HEADER'
# =============================================================================
# ~/.zshrc — generated by setup-dev-tools-mac.sh
# =============================================================================
# Add personal customizations OUTSIDE the managed block below.

ZSHRC_HEADER
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

# mise activation lives in ~/.zshenv (runs for all shell types) — not duplicated here.

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# starship prompt
command -v starship &>/dev/null && eval "$(starship init zsh)"

# atuin (replaces ctrl-r shell history)
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

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
command -v atac          &>/dev/null && _compcache atac atac completions zsh
command -v aws_completer &>/dev/null && complete -C aws_completer aws
unset -f _compcache
unset _cachedir

# -- Modern Tool Aliases (replacements for built-in commands) -----------------
# Note: we avoid aliasing cd, sed, find, grep, diff globally since they have
# different syntax from their replacements and would break scripts/muscle memory.
# Instead, we provide short aliases for the modern tools.
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
alias make="just"

# Short aliases for modern tools (don't override builtins)
alias rg="rg"          # ripgrep (already the command name)
alias f="fd"           # fd (fast find)
alias sd="sd"          # sd (fast sed)
alias dft="difft"      # difftastic
alias y="rovr"         # rovr file manager (mouse-first TUI; nnn 'n' is the minimal fallback)
alias jx="fx"          # fx interactive JSON viewer

# -- Download & Transfer ------------------------------------------------------
alias dl="aria2c"
alias wget="aria2c"

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
alias pip="uv pip"
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

# -- System -------------------------------------------------------------------
alias update="topgrade"
alias sysinfo="fastfetch"

# -- Terminal Welcome Screen --------------------------------------------------
# Colorful greeting on new terminal sessions (skip inside editor-integrated terminals)
if [[ "$TERM_PROGRAM" != "vscode" ]] && [[ -z "$INSIDE_EMACS" ]]; then
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
echo "  [~/.config/stern]       K8s log tailing"
echo "  [~/.config/zellij]      Modern terminal multiplexer with Dracula theme"
echo "  [~/.config/mpv]         Video player (hardware accel, save position)"
echo "  [~/Library/Preferences/kew]  Music player (library ~/Media/music, spectrum visualizer)"
echo "  [~/.config/git-cliff]   Changelog generator (conventional commits)"
echo "  [~/.newsboat]           RSS reader (vim keys, Dracula colors, starter URLs)"
echo "  [~/.config/ghostty]     GPU-accelerated terminal + quick-terminal launcher (cmd+space)"
echo "  [~/.config/aerospace]   Tiling window manager (Option+hjkl, workspaces 1-9)"
echo "  [~/.config/sketchybar]  Dracula status bar (AeroSpace pills, battery/wifi/vpn/cpu/mem)"
echo "  [~/.config/aerc]        Terminal email skeleton (Gmail + iCloud — add credentials)"
echo "  [~/.config/khal]        Terminal calendar (unified Gmail + iCloud via vdirsyncer)"
echo "  [~/.justfile]           Global task runner recipes"
echo "  [~/.config/brewfile]    Brewfile snapshot for reproducibility"
echo "  [~/.config/helix]       Helix — Dracula theme, ruff LSP, auto-format; MCP servers migrated to Claude Code"
echo "  [lazygit]               Dracula theme, delta pager"
echo "  [k9s]                   Dracula skin"
echo "  [Finder]                Hidden files, path bar, list view"
echo "  [macOS]                 Dock, keyboard, screenshots, hot corners, Stage Manager"
echo "  [Claude Code]           Custom commands (/pr-review, /test-plan, /dep-audit, /quick-doc, /cleanup)"
echo ""
info "Optional Chrome extensions to install manually:"
echo "  - axe DevTools (accessibility testing)"
echo "  - React Developer Tools"
echo "  - Lighthouse"
echo "  - JSON Formatter"
echo ""
info "Terminal launcher & window management (replaces Raycast/Spotlight):"
echo "  - cmd+space           Ghostty quick terminal (after disabling Spotlight's cmd+space)"
echo "  - a                   fuzzy-launch an app        ff   find & open a file"
echo "  - rgf <pattern>       search file contents        s <q>  Spotlight-index search"
echo "  - clip                clipboard history (clipse)"
echo "  - Option + hjkl       AeroSpace: focus windows;   Option+1..9  switch workspace"
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
- [ ] **Accessibility** — grant to **Ghostty** and **AeroSpace**: System Settings -> Privacy & Security -> Accessibility. (Required for the global launcher hotkey and window management.)
- [ ] **Disable Spotlight's cmd+space** so the Ghostty quick terminal can use it: System Settings -> Keyboard -> Keyboard Shortcuts -> Spotlight -> uncheck "Show Spotlight search". (Or change the Ghostty bind to `global:cmd+backquote` in `~/.config/ghostty/config`.)
- [ ] **Auto-hide the menu bar** (so SketchyBar is the bar): System Settings -> Control Center -> "Automatically hide and show the menu bar" -> Always.
- [ ] **Displays have separate Spaces = OFF** — already set by the script (`spans-displays`), but it needs a **logout/login** to take effect.
- [ ] Log out and back in once so AeroSpace + the Spaces setting apply cleanly.

## Email — aerc (`~/.config/aerc/accounts.conf`)
- [ ] **iCloud (personal):** create an **app-specific password** at appleid.apple.com -> Sign-In & Security -> App-Specific Passwords. Put your address in the `Personal (iCloud)` source/outgoing/from lines.
- [ ] **Gmail (work):** create a Google Cloud OAuth **Desktop app** (console.cloud.google.com -> APIs & Services -> Credentials), enable the Gmail API, then obtain a refresh token. Fill `oauth2_client_id` / `oauth2_client_secret` in the `Work (Gmail)` account.
- [ ] Launch `aerc` and confirm both accounts connect.

## Calendar — khal + vdirsyncer (`~/.config/vdirsyncer/config`)
- [ ] **iCloud:** set `username` + the app-specific password in `storage icloud_remote`.
- [ ] **Google:** set `client_id` / `client_secret` in `storage google_remote` (reuse or make another Google OAuth client).
- [ ] Run `vdirsyncer discover` then `vdirsyncer sync`. Launch `khal` (or `ikhal`) to see the unified calendar.
- [ ] Optional: add `vdirsyncer sync` to a cron/launchd job for periodic refresh.

## Accounts, keys & first-run
- [ ] **Apple Passwords CLI (`apw`):** run `brew services start apw`, then `apw auth`, and install the **iCloud Passwords browser extension**.
- [ ] **Mullvad:** `mullvad account login <ACCOUNT_NUMBER>` (CLI is bundled with the app at `/usr/local/bin/mullvad`).
- [ ] **starlit** (weather): `starlit --setup` and paste a free OpenWeatherMap API key.
- [ ] **MCP servers:** export tokens your Claude Code MCP servers need, e.g. `export GITHUB_TOKEN=...` (and `AWS_REGION` / `AWS_PROFILE` for the AWS servers). Requires `claude auth login` at least once.
- [ ] **Claude AI in Helix/aerc:** set an Anthropic key — `export ANTHROPIC_API_KEY=sk-ant-...` in `~/.zshrc.local` (used by **helix-assist**, the in-editor AI LSP). For the `llm` pipe binds (`A-a` in Helix, `S` in aerc): `llm keys set anthropic` then `llm models default claude-sonnet-4-5`.
- [ ] **AI side-pane:** `zellij --layout dev` opens your editor + a Claude Code pane side by side (the strongest AI workflow).
- [ ] **chezmoi:** `chezmoi init <your-dotfiles-repo>` to bring these configs under version control across the MacBook + Mac mini.
- [ ] **tiki** (notes): run `tiki` once and point it at (or init) your notes git repo.
- [ ] **kew** (music): drop music into `~/Media/music` (the configured library path).
- [ ] **leaf** (Markdown): if tab-completion isn't working, run `leaf --auto-complete` and restart your shell (the script attempts this automatically).

## Standard machine setup
- [ ] Generate an SSH key if needed: `ssh-keygen -t ed25519 -C "you@example.com"` and `gh ssh-key add ~/.ssh/id_ed25519.pub`.
- [ ] Enable **FileVault** and the **macOS Firewall** (System Settings -> Privacy & Security / Network).
- [ ] Open **OrbStack** once to finish Docker setup.
- [ ] `ngrok config add-authtoken <TOKEN>`.
CHECKLIST_EOF

    # ---- 2. KEYBOARD_SHORTCUTS.md ----
    cat > "$DESKTOP/KEYBOARD_SHORTCUTS.md" <<'SHORTCUTS_EOF'
# Keyboard Shortcuts

## AeroSpace (tiling window manager) — Option (alt) based
| Keys | Action |
|------|--------|
| `Option + h/j/k/l` | Focus window left/down/up/right |
| `Option + Shift + h/j/k/l` | Move window |
| `Option + 1..9` | Switch to workspace 1-9 |
| `Option + Shift + 1..9` | Move focused window to workspace |
| `Option + Tab` | Back-and-forth between workspaces |
| `Option + /` | Tiles layout (horizontal/vertical) |
| `Option + ,` | Accordion layout |
| `Option + f` | Fullscreen |
| `Option + - / =` | Resize smaller / larger |
| `Option + Shift + c` | Reload AeroSpace config |
| `Option + Shift + ;` | Enter service mode (then `esc`/`r`/`f`/`backspace`) |

## Launcher & search (Ghostty quick terminal)
| Keys / command | Action |
|------|--------|
| `cmd + space` | Toggle the Ghostty quick terminal (global dropdown) |
| `a` | Fuzzy-launch an installed app |
| `ff` | Find a file by name and open it |
| `rgf <pattern>` | Live content search (ripgrep + fzf) |
| `s <query>` | Spotlight-index search (mdfind) |
| `clip` | Clipboard history (clipse) |

## Helix (`hx`) — modal editor
| Keys | Action |
|------|--------|
| `Space` | Open the command menu (leader) |
| `Space + f` | File picker · `Space + b` buffer picker |
| `Space + /` | Global search (ripgrep) |
| `Space + k` | Hover docs · `g d` go to definition · `g r` references |
| `Ctrl + s` | Save (added binding) |
| `Alt + a` | Send selection to Claude (via `llm`), replace with the result |
| `Space + a` | helix-assist code-action (fix/improve/refactor via Claude, if `ANTHROPIC_API_KEY` set) |
| `:w` `:q` | Write / quit |

## Claude AI
| Where | How |
|-------|-----|
| Side-pane (best) | `zellij --layout dev` — editor + Claude Code panes |
| Helix inline | `Alt + a` on a selection (llm pipe); `Space + a` (helix-assist LSP) |
| aerc | `S` on a message — summarize/triage via Claude |

## Terminal multiplexer & tools
| Keys | Action |
|------|--------|
| `Ctrl + r` | atuin history search (fuzzy, across machines) |
| `Ctrl + t` | fzf file finder · `Alt + c` fzf cd |
| zellij `Ctrl + p` then `n` | New pane (see zellij status bar for modes) |
| lazygit / lazydocker / lazysql / lazynpm / lazyssh / lazyrsync | Full-screen TUIs (arrows + on-screen keys) |
| `y` rovr · `n` nnn | File managers |
| `kew <search>` | Play matching tracks; in-app `Space` play/pause, `v` visualizer |
| `atac` | API client TUI (or `atac request send <coll>/<req>` headless) |

## SketchyBar (click actions)
| Item | Click |
|------|-------|
| Clock | Opens khal in a Ghostty quick terminal |
| VPN pill | Toggles `mullvad connect` / `disconnect` |
| Bluetooth | Toggles Bluetooth power |
| Workspace pill | Switches to that AeroSpace workspace |
SHORTCUTS_EOF

    # ---- 3. TOOLKIT_SUMMARY.md ----
    cat > "$DESKTOP/TOOLKIT_SUMMARY.md" <<'SUMMARY_EOF'
# Toolkit Summary

A terminal-first macOS setup: GUI apps replaced with TUI/CLI equivalents wherever
it doesn't cost real capability. Below: what each tool is for, then how it fits
together.

## Editor & AI
- **Helix (`hx`)** — modal terminal editor, built-in LSP + tree-sitter, auto-format on save. The sole editor (`EDITOR`).
- **Claude Code (`claude`)** — agentic coding in the terminal; hosts the MCP servers. Best via `zellij --layout dev` (editor + Claude pane).
- **Claude in Helix/aerc** — `Alt+a` pipes a selection to Claude (via `llm`); **helix-assist** adds Claude as an LSP (`Space A`); aerc `S` summarizes an email. All powered by `llm-anthropic` / `ANTHROPIC_API_KEY`.

## Window management, bar & launcher
- **AeroSpace** — keyboard-driven tiling WM (no SIP disable). Option+hjkl, workspaces 1-9.
- **SketchyBar** — Dracula status bar: workspace pills, app, clock, battery, wifi, volume, cpu, mem, bluetooth, VPN.
- **Ghostty quick terminal** — global cmd+space dropdown that hosts the launcher.
- **Launcher functions** — `a` (apps), `ff` (files), `rgf` (contents), `s` (Spotlight index), `clip` (clipboard via clipse).

## Files, data & shell
- **rovr** (file manager, nnn fallback), **eza/bat/fd/ripgrep/zoxide/dust/duf/sd** (modern coreutils), **fzf** (fuzzy), **atuin** (history), **starship** (prompt), **zellij** (multiplexer), **yazi**->rovr.
- **wiper** — interactive disk cleanup (Trash-safe). **taproom** — Homebrew TUI. **has** — tool/version checker.

## Dev workflow
- **lazygit / lazydocker / lazysql / lazynpm / lazyssh / lazyrsync** — full-screen TUIs for git, containers, SQL, npm, SSH, rsync.
- **ATAC** — terminal API client (TUI + scriptable CLI) replacing Bruno; **hurl/xh/curlie/grpcurl** for one-shot + tests.
- **harlequin / pgcli / mycli / usql / sq** — database CLIs/TUIs (replaced DBeaver).
- **d2 / mermaid** — diagrams as code (replaced draw.io). **qalc** — calculator. **vhs** — scripted terminal recordings. **doxx** — .docx viewer.

## Communication & knowledge
- **aerc** — terminal email (Gmail work + iCloud personal, one client).
- **khal + vdirsyncer** — unified terminal calendar (Google + iCloud).
- **tiki** — Markdown workspace (tasks/docs/kanban/wiki) replacing Notion.
- **newsboat** — RSS. **kew** — music. **starlit** — weather.

## Infra, cloud & security
- **rclone** — cloud sync (replaced Cyberduck + Google Drive). **borg** — backups.
- **kubectl/k9s/stern/dive**, **awscli/granted**, **opentofu/terraform-docs/checkov/trivy**, **gitleaks/detect-secrets/sops/age**.
- **apw** — Apple Passwords from the CLI. **mullvad** CLI. **LuLu** firewall (GUI).

## How it fits together
The whole thing is one keyboard-driven loop. **cmd+space** drops the Ghostty quick
terminal from anywhere; `a`/`ff`/`rgf`/`s` make it a launcher and search bar, so
Spotlight/Raycast aren't needed. **AeroSpace** tiles windows and **SketchyBar** shows
state (workspaces, VPN, battery) — the bar's clock even opens **khal**, and its VPN
pill drives the **mullvad** CLI. Editing is **Helix**; the agent is **Claude Code**,
which reuses the same **MCP servers** the setup migrated over. The script writes
these configs to `~/.config`; use **chezmoi** (`chezmoi add`, with **cheznav** as its
TUI) to track them in git and keep the MacBook and Mac mini in sync — that step is
yours, the script doesn't auto-add them. Because almost everything is a CLI/TUI, the same tools work
locally, over SSH, and — where it matters — can be driven by Claude Code
(`atac`, `hurl`, `xh` are on its allowlist). GUI survivors are only the irreducible
ones: Ghostty, Chrome, the container runtime (OrbStack), security tools that need a
GUI (LuLu, Mullvad), and inherently-visual apps (Shottr, Skim), plus the Claude app.
SUMMARY_EOF

    success "Desktop docs written: POST_SETUP_CHECKLIST.md, KEYBOARD_SHORTCUTS.md, TOOLKIT_SUMMARY.md"
fi

info "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. >>> Work through ~/Desktop/POST_SETUP_CHECKLIST.md <<< (email/calendar creds,"
echo "        macOS permissions, apw/mullvad/starlit setup — the manual bits)."
echo "        Also on the Desktop: KEYBOARD_SHORTCUTS.md and TOOLKIT_SUMMARY.md."
echo "  3. Log out/in once so AeroSpace + the Spaces setting take effect."
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
    read -r -p "Generate an SSH key? [Y/n] " ssh_confirm
    if [[ ! "$ssh_confirm" =~ ^[Nn]$ ]]; then
        read -r -p "Email for SSH key: " ssh_email
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
        read -r -p "Authenticate with GitHub? [Y/n] " gh_confirm
        if [[ ! "$gh_confirm" =~ ^[Nn]$ ]]; then
            info "Opening GitHub authentication..."
            gh auth login
            # Add SSH key to GitHub if it was just generated
            if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
                read -r -p "Add SSH key to GitHub? [Y/n] " ssh_gh_confirm
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
    read -r -p "Set up your work git identity? [Y/n] " work_confirm
    if [[ ! "$work_confirm" =~ ^[Nn]$ ]]; then
        read -r -p "Work name: " work_name
        read -r -p "Work email: " work_email
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
    read -r -p "Set up your personal git identity? [Y/n] " personal_confirm
    if [[ ! "$personal_confirm" =~ ^[Nn]$ ]]; then
        read -r -p "Personal name: " personal_name
        read -r -p "Personal email: " personal_email
        if [[ -n "$personal_name" ]] && [[ -n "$personal_email" ]]; then
            cat > "$GITCONFIG_PERSONAL" <<GIT_PERSONAL_ID
[user]
    name = $personal_name
    email = $personal_email
GIT_PERSONAL_ID
            success "Personal git identity set ($personal_email)"
        fi
    fi
fi

fi  # DRY_RUN

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
        "helix:hx --version"
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

if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    read -r -p "Source ~/.zshrc now to activate everything? [Y/n] " source_confirm
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
