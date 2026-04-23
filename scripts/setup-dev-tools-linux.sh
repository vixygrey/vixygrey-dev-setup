#!/usr/bin/env bash

# =============================================================================
# Development Environment Setup Script (Linux)
# =============================================================================
# Version:  2.1.0
# Updated:  2026-04-06
# Platform: Linux (Ubuntu/Debian, Fedora/RHEL, Arch/Manjaro)
# Run:      chmod +x setup-dev-tools-linux.sh && ./setup-dev-tools-linux.sh
# Flags:    --dry-run, --skip <categories>, --only <categories>, --cleanup, --help
# =============================================================================

SCRIPT_VERSION="2.1.0"
SCRIPT_START=$(date +%s)
PYTHON_VERSION="3.12"

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
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

success() {
    echo -e "${GREEN}[  OK]${NC} $1"
    log "OK: $1"
    ((INSTALL_SUCCESS++)) || true
}

warn() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    log "SKIP: $1"
    ((INSTALL_SKIPPED++)) || true
}

error() {
    echo -e "${RED}[ ERR]${NC} $1"
    log "ERROR: $1"
    echo "[$(date +%H:%M:%S)] $1" >> "$ERROR_LOG"
    ((INSTALL_FAILED++)) || true
    FAILED_ITEMS+=("$1")
}

banner() {
    local title="$1"
    echo ""
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}${BOLD}  $title${NC}"
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log "=== $title ==="
}

# -- Counters -----------------------------------------------------------------
INSTALL_SUCCESS=0
INSTALL_SKIPPED=0
INSTALL_FAILED=0
INSTALL_CURRENT=0
FAILED_ITEMS=()

# Dynamic total — count all install calls in this script
_INSTALL_CALLS=$(grep -cE '^\s*(pkg_install|snap_install|flatpak_install|npm_global_install|pip_install|cargo_install|github_release_install|brew_install) ' "$0" 2>/dev/null || echo 0)
_PROGRESS_CALLS=$(grep -cE '^\s*progress\s*$' "$0" 2>/dev/null || echo 0)
INSTALL_TOTAL=$((_INSTALL_CALLS + _PROGRESS_CALLS))
[[ "$INSTALL_TOTAL" -eq 0 ]] && INSTALL_TOTAL=250

progress() {
    ((INSTALL_CURRENT++)) || true
    local pct=$((INSTALL_CURRENT * 100 / INSTALL_TOTAL))
    [[ "$pct" -gt 100 ]] && pct=100
    local bar_len=$((pct / 2))
    local bar
    bar=$(printf '█%.0s' $(seq 1 $bar_len 2>/dev/null) 2>/dev/null || echo "")
    local spaces
    spaces=$(printf ' %.0s' $(seq 1 $((50 - bar_len)) 2>/dev/null) 2>/dev/null || echo "")
    printf '\033[2K\r%s[%s%s%s%s] %d%% (%d/%d)%s\n' "$DIM" "$CYAN" "$bar" "$DIM" "$spaces" "$pct" "$INSTALL_CURRENT" "$INSTALL_TOTAL" "$NC"
}

# -- State flags --------------------------------------------------------------
DRY_RUN=false
RESUME=false
UNINSTALL=false
CLEANUP=false
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
}

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
    ui
    ux
    docs
    linux-system
    linux-productivity
    linux-communication
    linux-browsers
    linux-media
    linux-cloud
    linux-focus
    linux-disk
    dracula
    configs
    filesystem
    linux-defaults
    shell
)

# -- CLI argument parsing -----------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}Linux Development Environment Setup v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: ./setup-dev-tools-linux.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --dry-run           Preview what would be installed (no changes)"
    echo "  --resume            Skip items that succeeded in a previous run"
    echo "  --uninstall         Show commands to remove everything (no changes made)"
    echo "  --cleanup           Remove tools from previous versions no longer in this script"
    echo "  --skip <cats>       Skip categories (comma-separated)"
    echo "  --only <cats>       Only run these categories (comma-separated)"
    echo "  --list-categories   List all available categories"
    echo "  --version           Show script version"
    echo ""
    echo "Examples:"
    echo "  ./setup-dev-tools-linux.sh                          # Install everything"
    echo "  ./setup-dev-tools-linux.sh --dry-run                # Preview only"
    echo "  ./setup-dev-tools-linux.sh --resume                 # Continue after a failure"
    echo "  ./setup-dev-tools-linux.sh --uninstall              # Show removal commands"
    echo "  ./setup-dev-tools-linux.sh --cleanup                # Remove dropped tools from previous versions"
    echo "  ./setup-dev-tools-linux.sh --skip linux-media,linux-cloud"
    echo "  ./setup-dev-tools-linux.sh --only core,git,aws,dx"
    echo ""
}

list_categories() {
    echo ""
    echo -e "${BOLD}Available categories:${NC}"
    echo ""
    printf "  %-25s %s\n" "prerequisites"       "Build tools, zsh, snap, flatpak, Linuxbrew"
    printf "  %-25s %s\n" "core"                "mise (Node, Python), Go, Rust, Docker Engine, bun, uv, pnpm"
    printf "  %-25s %s\n" "git"                 "Git, GitHub CLI, delta, lazygit, pre-commit"
    printf "  %-25s %s\n" "aws"                 "AWS CLI, CDK, SAM, Granted, cfn-lint"
    printf "  %-25s %s\n" "iac"                 "OpenTofu (Terraform), tflint, infracost"
    printf "  %-25s %s\n" "security"            "detect-secrets, gitleaks, trivy, semgrep, Snyk, ClamAV"
    printf "  %-25s %s\n" "replacements"        "eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, yazi, fx, etc."
    printf "  %-25s %s\n" "data-processing"     "yq, miller, csvkit, pandoc, ffmpeg, ImageMagick"
    printf "  %-25s %s\n" "code-quality"        "shellcheck, shfmt, act, act3, hadolint, ruff, commitizen, ni"
    printf "  %-25s %s\n" "perf-testing"        "hyperfine, oha"
    printf "  %-25s %s\n" "dev-servers"         "ngrok, miniserve, caddy"
    printf "  %-25s %s\n" "terminal-productivity" "glow, watchexec, pv, parallel, gum, nushell, newsboat, topgrade, fastfetch, lnav, nnn, progress"
    printf "  %-25s %s\n" "k8s-github"          "stern, gh-dash"
    printf "  %-25s %s\n" "database"            "pgcli, mycli, lazysql, usql, sq"
    printf "  %-25s %s\n" "containers"          "lazydocker, dive, kubectl, k9s"
    printf "  %-25s %s\n" "api"                 "Postman, grpcurl"
    printf "  %-25s %s\n" "networking"          "mtr, bandwhich, nmap, sshclick"
    printf "  %-25s %s\n" "dx"                  "fzf, starship, atuin, VS Code, Alacritty, tmux"
    printf "  %-25s %s\n" "ui"                  "Storybook, Playwright, Chrome"
    printf "  %-25s %s\n" "ux"                  "Lighthouse"
    printf "  %-25s %s\n" "docs"                "d2, Mermaid CLI"
    printf "  %-25s %s\n" "linux-system"        "p7zip, gnome-sushi, caffeine, Mullvad VPN"
    printf "  %-25s %s\n" "linux-productivity"  "Flameshot, Espanso, Notion, Filezilla"
    printf "  %-25s %s\n" "linux-communication" "Slack, Telegram, Signal"
    printf "  %-25s %s\n" "linux-browsers"      "Firefox, Brave, Chrome, Carbonyl, w3m, monolith"
    printf "  %-25s %s\n" "linux-media"         "mpv, oxipng, jpegoptim, LibreOffice, cmus"
    printf "  %-25s %s\n" "linux-cloud"         "rclone, syncthing, borgbackup, borgmatic"
    printf "  %-25s %s\n" "linux-focus"         "NewsFlash (RSS)"
    printf "  %-25s %s\n" "linux-disk"          "ncdu"
    printf "  %-25s %s\n" "dracula"             "Dracula theme for all tools"
    printf "  %-25s %s\n" "configs"             "All dotfiles and tool configurations"
    printf "  %-25s %s\n" "filesystem"          "Directory structure, helper scripts, git identity"
    printf "  %-25s %s\n" "linux-defaults"      "GNOME settings, DNS, keyboard repeat"
    printf "  %-25s %s\n" "shell"               "\$HOME/.zshrc managed block"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "setup-dev-tools-linux.sh v${SCRIPT_VERSION}"
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
        --skip)
            IFS=',' read -ra SKIP_CATEGORIES <<< "$2"
            shift 2
            ;;
        --only)
            IFS=',' read -ra ONLY_CATEGORIES <<< "$2"
            shift 2
            ;;
        --list-categories)
            list_categories
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# -- Validate --skip/--only category names ------------------------------------
for _cat in "${SKIP_CATEGORIES[@]}" "${ONLY_CATEGORIES[@]}"; do
    _valid=false
    for _known in "${ALL_CATEGORIES[@]}"; do
        [[ "$_cat" == "$_known" ]] && _valid=true && break
    done
    if [[ "$_valid" != "true" ]]; then
        error "Unknown category: '$_cat'. Valid categories: ${ALL_CATEGORIES[*]}"
        exit 1
    fi
done
unset _cat _valid _known

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

# =============================================================================
# DISTRO DETECTION & PACKAGE MANAGER ABSTRACTION
# =============================================================================

PKG_MANAGER=""
DISTRO_ID=""
DISTRO_LIKE=""

detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}ERROR: /etc/os-release not found. Cannot detect distribution.${NC}"
        exit 1
    fi
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_LIKE="${ID_LIKE:-}"

    case "$ID" in
        ubuntu|debian|pop|linuxmint|elementary|zorin|kali)
            PKG_MANAGER="apt"
            ;;
        fedora|rhel|centos|rocky|alma|nobara)
            PKG_MANAGER="dnf"
            ;;
        arch|manjaro|endeavouros|garuda|artix)
            PKG_MANAGER="pacman"
            ;;
        *)
            # Fallback: check ID_LIKE
            case "$DISTRO_LIKE" in
                *debian*|*ubuntu*)
                    PKG_MANAGER="apt"
                    ;;
                *fedora*|*rhel*)
                    PKG_MANAGER="dnf"
                    ;;
                *arch*)
                    PKG_MANAGER="pacman"
                    ;;
                *)
                    echo -e "${RED}ERROR: Unsupported distribution: $ID (ID_LIKE=$DISTRO_LIKE)${NC}"
                    echo "  Supported: Ubuntu/Debian, Fedora/RHEL, Arch/Manjaro"
                    exit 1
                    ;;
            esac
            ;;
    esac
}

detect_distro

# System package install (handles apt/dnf/pacman)
pkg_install() {
    local pkg_apt="$1"
    local pkg_dnf="$2"
    local pkg_pacman="$3"
    local name="${4:-$1}"

    progress
    is_done "pkg:$name" && { warn "$name already completed (resume)"; return 0; }

    local pkg=""
    case "$PKG_MANAGER" in
        apt) pkg="$pkg_apt" ;;
        dnf) pkg="$pkg_dnf" ;;
        pacman) pkg="$pkg_pacman" ;;
    esac

    # Skip if package name is empty (not available for this distro)
    if [[ -z "$pkg" ]] || [[ "$pkg" == "-" ]]; then
        warn "$name — not available via $PKG_MANAGER (will try alternative)"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: $name ($pkg via $PKG_MANAGER)"
        return 0
    fi

    # Check if already installed
    case "$PKG_MANAGER" in
        apt) dpkg -s "$pkg" &>/dev/null && { warn "$name already installed"; mark_done "pkg:$name"; return 0; } ;;
        dnf) rpm -q "$pkg" &>/dev/null && { warn "$name already installed"; mark_done "pkg:$name"; return 0; } ;;
        pacman) pacman -Qi "$pkg" &>/dev/null && { warn "$name already installed"; mark_done "pkg:$name"; return 0; } ;;
    esac

    info "Installing $name..."
    case "$PKG_MANAGER" in
        apt)
            if sudo apt-get install -y "$pkg" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                success "$name installed"
                mark_done "pkg:$name"
            else
                error "Failed to install $name"
                return 1
            fi
            ;;
        dnf)
            if sudo dnf install -y "$pkg" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                success "$name installed"
                mark_done "pkg:$name"
            else
                error "Failed to install $name"
                return 1
            fi
            ;;
        pacman)
            if sudo pacman -S --noconfirm --needed "$pkg" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                success "$name installed"
                mark_done "pkg:$name"
            else
                error "Failed to install $name"
                return 1
            fi
            ;;
    esac
}

snap_install() {
    local pkg="$1"
    local name="${2:-$1}"
    local classic="${3:-}"

    progress
    is_done "snap:$pkg" && { warn "$name already completed (resume)"; return 0; }

    if ! installed snap; then
        warn "$name — snap not available, skipping"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if snap list "$pkg" &>/dev/null; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name (snap)"
        fi
        return 0
    fi

    if snap list "$pkg" &>/dev/null; then
        warn "$name already installed (snap)"
        mark_done "snap:$pkg"
    else
        info "Installing $name (snap)..."
        local -a snap_opts=()
        [[ "$classic" == "classic" ]] && snap_opts=(--classic)
        if sudo snap install "$pkg" "${snap_opts[@]}" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
            success "$name installed (snap)"
            mark_done "snap:$pkg"
        else
            error "Failed to install $name (snap)"
            return 1
        fi
    fi
}

flatpak_install() {
    local app_id="$1"
    local name="${2:-$1}"

    progress
    is_done "flatpak:$app_id" && { warn "$name already completed (resume)"; return 0; }

    if ! installed flatpak; then
        warn "$name — flatpak not available, skipping"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if flatpak info "$app_id" &>/dev/null; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name (flatpak)"
        fi
        return 0
    fi

    if flatpak info "$app_id" &>/dev/null; then
        warn "$name already installed (flatpak)"
        mark_done "flatpak:$app_id"
    else
        info "Installing $name (flatpak)..."
        if flatpak install -y flathub "$app_id" >> "$LOG_FILE" 2>&1; then
            success "$name installed (flatpak)"
            mark_done "flatpak:$app_id"
        else
            error "Failed to install $name (flatpak)"
            return 1
        fi
    fi
}

npm_global_install() {
    local pkg="$1"
    local name="${2:-$1}"
    progress
    is_done "npm:$pkg" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        if npm list -g "$pkg" &>/dev/null; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if npm list -g "$pkg" &>/dev/null; then
        warn "$name already installed globally"
        mark_done "npm:$pkg"
    else
        info "Installing $name globally..."
        if npm install -g "$pkg" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
            mark_done "npm:$pkg"
        else
            error "Failed to install $name"
            return 1
        fi
    fi
}

pip_install() {
    local pkg="$1"
    local name="${2:-$1}"
    progress
    is_done "pip:$pkg" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: $name (pip)"
        return 0
    fi
    if command -v "$pkg" &>/dev/null; then
        warn "$name already installed"
        mark_done "pip:$pkg"
        return 0
    fi
    info "Installing $name..."
    if command -v uv &>/dev/null; then
        uv tool install "$pkg" >> "$LOG_FILE" 2>&1 && { success "$name installed (uv)"; mark_done "pip:$pkg"; return 0; }
    fi
    if command -v pipx &>/dev/null; then
        pipx install "$pkg" >> "$LOG_FILE" 2>&1 && { success "$name installed (pipx)"; mark_done "pip:$pkg"; return 0; }
    fi
    if pip install --user "$pkg" >> "$LOG_FILE" 2>&1; then
        success "$name installed (pip)"
        mark_done "pip:$pkg"
        return 0
    fi
    error "Failed to install $name"
    return 1
}

cargo_install() {
    local pkg="$1"
    local name="${2:-$1}"
    progress
    is_done "cargo:$pkg" && { warn "$name already completed (resume)"; return 0; }
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: $name (cargo)"
        return 0
    fi
    if installed "$pkg" || cargo install --list 2>/dev/null | grep -q "^$pkg "; then
        warn "$name already installed (cargo)"
        mark_done "cargo:$pkg"
    else
        info "Installing $name (cargo)..."
        if cargo install "$pkg" >> "$LOG_FILE" 2>&1; then
            success "$name installed (cargo)"
            mark_done "cargo:$pkg"
        else
            error "Failed to install $name (cargo)"
            return 1
        fi
    fi
}

brew_install() {
    local formula="$1"
    local name="${2:-$1}"
    progress
    is_done "brew:$formula" && { warn "$name already completed (resume)"; return 0; }

    if ! installed brew; then
        warn "$name — Linuxbrew not available, skipping"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if brew list "$formula" &>/dev/null; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name (brew)"
        fi
        return 0
    fi
    if brew list "$formula" &>/dev/null; then
        warn "$name already installed (brew)"
        mark_done "brew:$formula"
    else
        info "Installing $name (brew)..."
        if brew install "$formula" >> "$LOG_FILE" 2>&1; then
            success "$name installed (brew)"
            mark_done "brew:$formula"
        else
            error "Failed to install $name (brew)"
            return 1
        fi
    fi
}

# Download a binary from GitHub releases
github_release_install() {
    local repo="$1"        # e.g. "ogham/exa"
    local binary="$2"      # binary name to check
    local url_pattern="$3" # URL with ARCH/VERSION placeholders
    local name="${4:-$binary}"

    progress
    is_done "gh:$binary" && { warn "$name already completed (resume)"; return 0; }

    if [[ "$DRY_RUN" == "true" ]]; then
        if installed "$binary"; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name (GitHub release)"
        fi
        return 0
    fi

    if installed "$binary"; then
        warn "$name already installed"
        mark_done "gh:$binary"
        return 0
    fi

    info "Installing $name from GitHub releases..."
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
    esac

    # Get latest version tag
    local version
    version=$(curl -sL "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')
    if [[ -z "$version" ]]; then
        error "Failed to get latest version for $repo"
        return 1
    fi

    local url
    url=$(echo "$url_pattern" | sed "s|ARCH|$arch|g;s|VERSION|$version|g;s|VVERSION|${version#v}|g")

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local filename="${url##*/}"

    if curl -sL "$url" -o "$tmp_dir/$filename" >> "$LOG_FILE" 2>&1; then
        if [[ "$filename" == *.tar.gz ]] || [[ "$filename" == *.tgz ]]; then
            tar xzf "$tmp_dir/$filename" -C "$tmp_dir" >> "$LOG_FILE" 2>&1
            local found_bin
            found_bin=$(find "$tmp_dir" -name "$binary" -type f 2>/dev/null | head -1)
            if [[ -n "$found_bin" ]]; then
                sudo install -m 755 "$found_bin" /usr/local/bin/"$binary"
            else
                error "Binary $binary not found in archive"
                rm -rf "$tmp_dir"
                return 1
            fi
        elif [[ "$filename" == *.deb ]]; then
            sudo dpkg -i "$tmp_dir/$filename" 2>&1 | tee -a "$LOG_FILE" > /dev/null || sudo apt-get install -f -y 2>&1 | tee -a "$LOG_FILE" > /dev/null
        elif [[ "$filename" == *.rpm ]]; then
            sudo rpm -i "$tmp_dir/$filename" 2>&1 | tee -a "$LOG_FILE" > /dev/null || sudo dnf install -y "$tmp_dir/$filename" 2>&1 | tee -a "$LOG_FILE" > /dev/null
        elif [[ "$filename" == *.zip ]]; then
            unzip -o "$tmp_dir/$filename" -d "$tmp_dir" >> "$LOG_FILE" 2>&1
            local found_bin
            found_bin=$(find "$tmp_dir" -name "$binary" -type f 2>/dev/null | head -1)
            if [[ -n "$found_bin" ]]; then
                sudo install -m 755 "$found_bin" /usr/local/bin/"$binary"
            fi
        else
            # Assume it's a raw binary
            sudo install -m 755 "$tmp_dir/$filename" /usr/local/bin/"$binary"
        fi
        rm -rf "$tmp_dir"
        success "$name installed"
        mark_done "gh:$binary"
    else
        error "Failed to download $name"
        rm -rf "$tmp_dir"
        return 1
    fi
}

# -- External repo setup functions ---------------------------------------------

setup_docker_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
                info "Adding Docker apt repository..."
                sudo install -m 0755 -d /etc/apt/keyrings
                if ! curl -fsSL "https://download.docker.com/linux/$DISTRO_ID/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
                    warn "Failed to import GPG key for Docker — skipping"
                    return 1
                fi
                sudo chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO_ID $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
                info "Adding Docker dnf repository..."
                sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
                sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || true
            fi
            ;;
        pacman)
            # Docker is in the official repos for Arch
            ;;
    esac
}

setup_github_cli_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
                info "Adding GitHub CLI apt repository..."
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
                sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
                    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/gh-cli.repo ]]; then
                info "Adding GitHub CLI dnf repository..."
                sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || \
                sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
            fi
            ;;
        pacman)
            # github-cli is in the community repo
            ;;
    esac
}

setup_brave_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/brave-browser-release.list ]]; then
                info "Adding Brave Browser apt repository..."
                sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
                    sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
                info "Adding Brave Browser dnf repository..."
                sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null && \
                sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null || true
            fi
            ;;
        pacman)
            # brave-bin is in AUR
            ;;
    esac
}

setup_chrome_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
                info "Adding Google Chrome apt repository..."
                if ! curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg 2>/dev/null; then
                    warn "Failed to import GPG key for Google Chrome — skipping"
                    return 1
                fi
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | \
                    sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
                info "Adding Google Chrome dnf repository..."
                if ! sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null; then
                    warn "Failed to import GPG key for Google Chrome — skipping"
                    return 1
                fi
                sudo dnf config-manager --add-repo https://dl.google.com/linux/chrome/rpm/stable/x86_64 2>/dev/null || true
            fi
            ;;
        pacman)
            # google-chrome is in AUR
            ;;
    esac
}

setup_vscode_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
                info "Adding VS Code apt repository..."
                if ! curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg 2>/dev/null; then
                    warn "Failed to import GPG key for VS Code — skipping"
                    return 1
                fi
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                    sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
                info "Adding VS Code dnf repository..."
                if ! sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null; then
                    warn "Failed to import GPG key for VS Code — skipping"
                    return 1
                fi
                cat <<'VSCODE_REPO' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_REPO
            fi
            ;;
        pacman)
            # code is in community/extra repo
            ;;
    esac
}


setup_trivy_repo() {
    case "$PKG_MANAGER" in
        apt)
            if [[ ! -f /etc/apt/sources.list.d/trivy.list ]]; then
                info "Adding Trivy apt repository..."
                sudo mkdir -p /etc/apt/keyrings
                if ! curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null; then
                    warn "Failed to import GPG key for Trivy — skipping"
                    return 1
                fi
                echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | \
                    sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            fi
            ;;
        dnf)
            if [[ ! -f /etc/yum.repos.d/trivy.repo ]]; then
                info "Adding Trivy rpm repository..."
                cat <<'TRIVY_REPO' | sudo tee /etc/yum.repos.d/trivy.repo > /dev/null
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
gpgkey=https://aquasecurity.github.io/trivy-repo/deb/public.key
enabled=1
TRIVY_REPO
            fi
            ;;
        pacman)
            # trivy-bin is in AUR
            ;;
    esac
}

# -- Pre-flight checks --------------------------------------------------------
preflight() {
    banner "Pre-flight Checks"

    # Distro
    . /etc/os-release
    success "Distribution: $PRETTY_NAME (package manager: $PKG_MANAGER)"

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
    local free_space
    free_space=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$free_space" -lt 15 ]]; then
        error "Low disk space: ${free_space}GB free (15GB+ recommended)"
        read -rp "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        success "Disk space: ${free_space}GB free"
    fi

    # Admin check
    if sudo -n true 2>/dev/null; then
        success "Admin privileges available"
    else
        info "Some steps require admin privileges. You may be prompted for your password."
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
echo "  ║         Linux Dev Environment Setup v${SCRIPT_VERSION}               ║"
echo "  ║                                                              ║"
echo "  ║  200+ tools · 50+ configs · Dracula theme · Multi-distro   ║"
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
    echo "# Remove config files:"
    echo "  rm -f ~/.tmux.conf ~/.shellcheckrc ~/.editorconfig ~/.prettierrc"
    echo "  rm -f ~/.curlrc ~/.npmrc ~/.ripgreprc ~/.fdignore ~/.nanorc ~/.vimrc"
    echo "  rm -f ~/.hushlogin ~/.gitmessage ~/.myclirc ~/.gemrc ~/.actrc ~/.mlrrc"
    echo "  rm -rf ~/.aria2 ~/.config/atuin ~/.config/glow ~/.config/ngrok"
    echo "  rm -rf ~/.config/yt-dlp ~/.config/gh-dash ~/.config/stern"
    echo "  rm -rf ~/.config/btop ~/.config/lazydocker ~/.config/mise"
    echo "  rm -rf ~/.config/topgrade.toml ~/.config/fastfetch ~/.config/pgcli"
    echo "  rm -rf ~/.config/direnv ~/.config/caddy ~/.config/yazi"
    echo "  rm -rf ~/.config/alacritty ~/.config/kitty"
    echo "  rm -f ~/.justfile"
    echo ""
    echo "# Remove Rust (installed via rustup):"
    echo "  rustup self uninstall"
    echo ""
    echo "# Remove Claude Code config (CAREFUL — contains your custom rules):"
    echo "  rm -rf ~/.claude/settings.json ~/.claude/CLAUDE.md ~/.claude/rules ~/.claude/hooks ~/.claude/commands"
    echo ""
    echo "# Remove VS Code settings:"
    echo "  rm -f ~/.config/Code/User/settings.json"
    echo "  rm -f ~/.config/Code/User/keybindings.json"
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
    echo "# Remove snap packages:"
    echo "  snap list | tail -n+2 | awk '{print \$1}' | xargs -I{} sudo snap remove {}"
    echo ""
    echo "# Remove flatpak packages:"
    echo "  flatpak list --app | awk '{print \$2}' | xargs -I{} flatpak uninstall -y {}"
    echo ""
    echo "# Remove Linuxbrew:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\""
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
    # Format: "type:name:display-name:replacement"
    DEPRECATED_TOOLS=(
        "pkg:dog:dog (DNS tool):doggo"
        "snap:cursor:Cursor (AI editor):VS Code + Claude Code"
        "pkg:tailscale:Tailscale:removed"
        "snap:discord:Discord:removed"
        "pkg:gimp:GIMP:removed"
        "flatpak:io.github.nickvision_apps.Cavalier:Figma Linux (unofficial):removed (use figma.com)"
        "flatpak:net.ankiweb.Anki:Anki:removed"
        "pkg:nvm:nvm:mise"
        "pkg:pyenv:pyenv:mise"
        "pkg:httpie:HTTPie:xh"
        "pkg:git-secrets:git-secrets:gitleaks + detect-secrets"
        "pkg:trufflehog:trufflehog:gitleaks + detect-secrets"
        "snap:cyberduck:Cyberduck:FileZilla"
    )

    CLEANUP_COUNT=0
    CLEANUP_SKIPPED=0

    for entry in "${DEPRECATED_TOOLS[@]}"; do
        IFS=':' read -r type name display replacement <<< "$entry"

        case "$type" in
            pkg)
                local_installed=false
                case "$PKG_MANAGER" in
                    apt) dpkg -s "$name" &>/dev/null && local_installed=true ;;
                    dnf) rpm -q "$name" &>/dev/null && local_installed=true ;;
                    pacman) pacman -Qi "$name" &>/dev/null && local_installed=true ;;
                esac
                if [[ "$local_installed" == "true" ]]; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        case "$PKG_MANAGER" in
                            apt) if sudo apt-get remove -y "$name" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then success "$display removed"; else error "Failed to remove $display"; fi ;;
                            dnf) if sudo dnf remove -y "$name" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then success "$display removed"; else error "Failed to remove $display"; fi ;;
                            pacman) if sudo pacman -R --noconfirm "$name" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then success "$display removed"; else error "Failed to remove $display"; fi ;;
                        esac
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            snap)
                if snap list "$name" &>/dev/null; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if sudo snap remove "$name" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
                    fi
                else
                    ((CLEANUP_SKIPPED++))
                fi
                ;;
            flatpak)
                if flatpak info "$name" &>/dev/null; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would remove: $display (replaced by $replacement)"
                    else
                        info "Removing $display (replaced by $replacement)..."
                        if flatpak uninstall -y "$name" >> "$LOG_FILE" 2>&1; then success "$display removed"; else error "Failed to remove $display"; fi
                        ((CLEANUP_COUNT++))
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
    fi
    exit 0
fi

preflight
acquire_lock

# =============================================================================
# PREREQUISITES
# =============================================================================
banner "Prerequisites"

# Update package manager
info "Updating package manager..."
case "$PKG_MANAGER" in
    apt) sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null && success "apt updated" ;;
    dnf) sudo dnf check-update 2>&1 | tee -a "$LOG_FILE" > /dev/null; success "dnf updated" ;;
    pacman) sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE" > /dev/null && success "pacman synced" ;;
esac

# Build essentials
pkg_install "build-essential" "@development-tools" "base-devel" "Build essentials (gcc, make, etc.)"
pkg_install "curl" "curl" "curl" "curl"
pkg_install "wget" "wget" "wget" "wget"
pkg_install "git" "git" "git" "git"
pkg_install "unzip" "unzip" "unzip" "unzip"
pkg_install "xclip" "xclip" "xclip" "xclip (clipboard)"
pkg_install "xsel" "xsel" "xsel" "xsel (clipboard)"
pkg_install "software-properties-common" "-" "-" "software-properties-common (apt PPA support)"

# zsh
pkg_install "zsh" "zsh" "zsh" "zsh"

# Set zsh as default shell if not already
if [[ "$SHELL" != *"zsh"* ]]; then
    if installed zsh; then
        info "Setting zsh as default shell..."
        if [[ "$DRY_RUN" != "true" ]]; then
            sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || chsh -s "$(command -v zsh)" 2>/dev/null || true
            success "zsh set as default shell (takes effect on next login)"
        fi
    fi
else
    warn "zsh is already the default shell"
fi

# snap
if ! installed snap; then
    info "Installing snapd..."
    case "$PKG_MANAGER" in
        apt) sudo apt-get install -y snapd 2>&1 | tee -a "$LOG_FILE" > /dev/null && success "snapd installed" ;;
        dnf) sudo dnf install -y snapd 2>&1 | tee -a "$LOG_FILE" > /dev/null && sudo systemctl enable --now snapd.socket 2>&1 | tee -a "$LOG_FILE" > /dev/null && success "snapd installed" ;;
        pacman)
            info "snapd on Arch requires AUR — skipping auto-install"
            info "  Install manually: yay -S snapd && sudo systemctl enable --now snapd.socket"
            ;;
    esac
    # Create symlink for classic snap support
    if [[ -d /var/lib/snapd/snap ]] && [[ ! -d /snap ]]; then
        sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
    fi
else
    warn "snapd already installed"
fi

# flatpak
if ! installed flatpak; then
    pkg_install "flatpak" "flatpak" "flatpak" "flatpak"
fi
# Add flathub
if installed flatpak; then
    if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
        info "Adding Flathub repository..."
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOG_FILE" 2>&1
        success "Flathub added"
    else
        warn "Flathub already configured"
    fi
fi

# Homebrew for Linux (Linuxbrew) — fallback for tools not in repos
if ! installed brew; then
    info "Installing Homebrew for Linux (Linuxbrew)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download Homebrew installer"
            rm -f "$installer"
        else
            NONINTERACTIVE=1 /bin/bash "$installer" >> "$LOG_FILE" 2>&1 || true
            rm -f "$installer"
        fi
        # Add to PATH
        if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
            eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
        fi
        if installed brew; then
            success "Linuxbrew installed"
        else
            warn "Linuxbrew installation failed — some tools will use cargo/pip fallback"
        fi
    fi
else
    warn "Linuxbrew already installed"
    brew update >> "$LOG_FILE" 2>&1 || true
fi

# Prevent brew from auto-updating on every install
export HOMEBREW_NO_AUTO_UPDATE=1

# =============================================================================
if should_run "core"; then
banner "Core Development"

# mise (universal version manager — replaces nvm, pyenv, rbenv in one tool)
if ! installed mise; then
    info "Installing mise (universal version manager)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL "https://mise.run" -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download mise installer"
            rm -f "$installer"
        else
            sh "$installer" >> "$LOG_FILE" 2>&1
            rm -f "$installer"
            success "mise installed"
        fi
    else
        info "[DRY RUN] Would install: mise"
    fi
else
    warn "mise already installed"
fi

# Activate mise for this script session
if installed mise; then
    eval "$(mise activate bash 2>/dev/null)" || true
fi

# Install Node.js LTS and Python via mise
if installed mise; then
    if ! mise ls node 2>/dev/null | grep -q "lts"; then
        info "Installing Node.js LTS via mise..."
        if [[ "$DRY_RUN" != "true" ]]; then
            mise install node@lts >> "$LOG_FILE" 2>&1
            mise use --global node@lts >> "$LOG_FILE" 2>&1
            success "Node.js LTS installed via mise"
        fi
    else
        warn "Node.js LTS already installed via mise"
    fi

    if ! mise ls python 2>/dev/null | grep -q "$PYTHON_VERSION"; then
        info "Installing Python $PYTHON_VERSION via mise..."
        if [[ "$DRY_RUN" != "true" ]]; then
            mise install "python@$PYTHON_VERSION" >> "$LOG_FILE" 2>&1
            mise use --global "python@$PYTHON_VERSION" >> "$LOG_FILE" 2>&1
            success "Python $PYTHON_VERSION installed via mise"
        fi
    else
        warn "Python $PYTHON_VERSION already installed via mise"
    fi

    # Ensure mise shims are in PATH for the rest of this script
    eval "$(mise env 2>/dev/null)" || true
fi

# Go
pkg_install "golang-go" "golang" "go" "Go (lang)"

# Python3
pkg_install "python3" "python3" "python3" "Python 3"
pkg_install "python3-pip" "python3-pip" "python-pip" "pip3"
pkg_install "python3-venv" "python3-virtualenv" "python-virtualenv" "Python venv"

# uv (fast Python package manager)
if ! installed uv; then
    info "Installing uv (fast Python package manager)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fLsSf https://astral.sh/uv/install.sh -o "$installer" 2>/dev/null
        if [[ ! -s "$installer" ]]; then
            error "Failed to download uv installer"
            rm -f "$installer"
            return 1
        fi
        sh "$installer" >> "$LOG_FILE" 2>&1
        rm -f "$installer"
        success "uv installed"
    fi
else
    warn "uv already installed"
fi

pkg_install "jq" "jq" "jq" "jq (JSON processor)"
pkg_install "direnv" "direnv" "direnv" "direnv (per-project env vars)"

# watchman — build from source or use brew
if ! installed watchman; then
    info "Installing watchman..."
    if installed brew; then
        if brew install watchman >> "$LOG_FILE" 2>&1; then success "watchman installed (brew)"; else warn "watchman install failed"; fi
    else
        warn "watchman — install manually or via Linuxbrew"
    fi
else
    warn "watchman already installed"
fi

pkg_install "cmake" "cmake" "cmake" "CMake"
pkg_install "pkg-config" "pkgconf" "pkgconf" "pkg-config"

# Rust (rustup manages the toolchain)
if ! installed rustup; then
    info "Installing Rust via rustup..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would install: Rust via rustup"
    else
        installer
        installer="$(mktemp)"
        curl --proto '=https' --tlsv1.2 -fsSL "https://sh.rustup.rs" -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download rustup installer"
            rm -f "$installer"
        else
            sh "$installer" -y --no-modify-path >> "$LOG_FILE" 2>&1
            rm -f "$installer"
        fi
        source "$HOME/.cargo/env" 2>/dev/null || true
        success "Rust installed via rustup"
    fi
else
    warn "Rust (rustup) already installed"
    source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Docker Engine (NOT Docker Desktop)
setup_docker_repo
case "$PKG_MANAGER" in
    apt)
        pkg_install "docker-ce" "docker-ce" "docker" "Docker Engine"
        pkg_install "docker-ce-cli" "docker-ce-cli" "-" "Docker CLI"
        pkg_install "containerd.io" "containerd.io" "-" "containerd"
        pkg_install "docker-buildx-plugin" "docker-buildx-plugin" "docker-buildx" "Docker Buildx"
        pkg_install "docker-compose-plugin" "docker-compose-plugin" "docker-compose" "Docker Compose"
        ;;
    dnf)
        pkg_install "-" "docker-ce" "-" "Docker Engine"
        pkg_install "-" "docker-ce-cli" "-" "Docker CLI"
        pkg_install "-" "containerd.io" "-" "containerd"
        pkg_install "-" "docker-buildx-plugin" "-" "Docker Buildx"
        pkg_install "-" "docker-compose-plugin" "-" "Docker Compose"
        ;;
    pacman)
        pkg_install "-" "-" "docker" "Docker Engine"
        pkg_install "-" "-" "docker-buildx" "Docker Buildx"
        pkg_install "-" "-" "docker-compose" "Docker Compose"
        ;;
esac

# Add user to docker group
if groups "$USER" 2>/dev/null | grep -q docker; then
    warn "User already in docker group"
else
    info "Adding $USER to docker group..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        success "Added $USER to docker group (re-login to take effect)"
    fi
fi

# Enable docker service
if [[ "$DRY_RUN" != "true" ]]; then
    sudo systemctl enable docker 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
    sudo systemctl start docker 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
fi

# bun
if ! installed bun; then
    info "Installing bun..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL "https://bun.sh/install" -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download bun installer"
            rm -f "$installer"
        else
            bash "$installer" >> "$LOG_FILE" 2>&1
            rm -f "$installer"
        fi
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        success "bun installed"
    fi
else
    warn "bun already installed"
fi

# pnpm
if ! installed pnpm; then
    info "Installing pnpm..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL https://get.pnpm.io/install.sh -o "$installer" 2>/dev/null
        if [[ ! -s "$installer" ]]; then
            error "Failed to download pnpm installer"
            rm -f "$installer"
            return 1
        fi
        sh "$installer" >> "$LOG_FILE" 2>&1
        rm -f "$installer"
        export PNPM_HOME="$HOME/.local/share/pnpm"
        export PATH="$PNPM_HOME:$PATH"
        success "pnpm installed"
    fi
else
    warn "pnpm already installed"
fi

# -- Verify all runtimes are in PATH for the rest of the script ----------------
info "Verifying runtime paths..."
# Go
if ! installed go && [[ -d "/usr/local/go/bin" ]]; then
    export PATH="/usr/local/go/bin:$PATH"
fi
# Rust/cargo
if ! installed cargo && [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env" 2>/dev/null || true
fi
# mise
if installed mise; then
    eval "$(mise env 2>/dev/null)" || true
fi
# pnpm
if ! installed pnpm && [[ -d "$HOME/.local/share/pnpm" ]]; then
    export PATH="$HOME/.local/share/pnpm:$PATH"
fi
# bun
if ! installed bun && [[ -d "$HOME/.bun/bin" ]]; then
    export PATH="$HOME/.bun/bin:$PATH"
fi
# VS Code 'code' CLI (snap puts it in /snap/bin, apt in /usr/bin)
if ! installed code; then
    for code_path in /snap/bin/code /usr/share/code/bin/code /usr/bin/code; do
        if [[ -f "$code_path" ]]; then
            code_dir
            code_dir="$(dirname "$code_path")"
            export PATH="$code_dir:$PATH"
            break
        fi
    done
fi
# Report what's available
for tool in node npm go cargo rustc bun pnpm uv code; do
    if installed "$tool"; then
        log "RUNTIME: $tool found at $(command -v "$tool")"
    else
        log "RUNTIME: $tool NOT found in PATH"
    fi
done

fi  # core

# =============================================================================
if should_run "git"; then
banner "Git & GitHub"

pkg_install "git" "git" "git" "Git"

# GitHub CLI
setup_github_cli_repo
pkg_install "gh" "gh" "github-cli" "GitHub CLI"

# delta
if ! installed delta; then
    info "Installing delta (better git diffs)..."
    case "$PKG_MANAGER" in
        apt)
            github_release_install "dandavison/delta" "delta" "https://github.com/dandavison/delta/releases/download/VERSION/git-delta_VVERSION_ARCH.deb" "delta (better git diffs)"
            ;;
        dnf)
            github_release_install "dandavison/delta" "delta" "https://github.com/dandavison/delta/releases/download/VERSION/git-delta-VVERSION-ARCH.rpm" "delta (better git diffs)"
            ;;
        pacman)
            pkg_install "-" "-" "git-delta" "delta (better git diffs)"
            ;;
    esac
else
    warn "delta already installed"
    progress
fi

# git-lfs
pkg_install "git-lfs" "git-lfs" "git-lfs" "Git LFS"

# gnupg
pkg_install "gnupg" "gnupg2" "gnupg" "GnuPG (commit signing)"

# pinentry
pkg_install "pinentry-curses" "pinentry" "pinentry" "pinentry (GPG passphrase)"

# lazygit
if ! installed lazygit; then
    info "Installing lazygit..."
    case "$PKG_MANAGER" in
        apt|dnf)
            github_release_install "jesseduffield/lazygit" "lazygit" "https://github.com/jesseduffield/lazygit/releases/download/VERSION/lazygit_VVERSION_Linux_ARCH.tar.gz" "lazygit (terminal UI for git)"
            ;;
        pacman)
            pkg_install "-" "-" "lazygit" "lazygit (terminal UI for git)"
            ;;
    esac
else
    warn "lazygit already installed"
    progress
fi

# git-absorb
cargo_install "git-absorb" "git-absorb (auto-fixup commits)"
cargo_install "git-cliff" "git-cliff (generate changelogs from conventional commits)"

# pre-commit
pip_install "pre-commit" "pre-commit (git hook framework)"

# Configure delta as default git pager
if [[ "$DRY_RUN" != "true" ]]; then
    if ! git config --global core.pager 2>/dev/null | grep -q delta 2>/dev/null; then
        info "Configuring delta as git pager..."
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.side-by-side true
        git config --global merge.conflictstyle diff3
        success "delta configured as git pager"
    fi
fi

fi  # git

# =============================================================================
if should_run "aws"; then
banner "AWS & CDK"

# AWS CLI v2
if ! installed aws; then
    info "Installing AWS CLI v2..."
    if [[ "$DRY_RUN" != "true" ]]; then
        tmp_dir=$(mktemp -d)
        arch=$(uname -m)
        {
            curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$tmp_dir/awscliv2.zip"
            unzip -o "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
        } >> "$LOG_FILE" 2>&1
        sudo "$tmp_dir/aws/install" --update 2>&1 | tee -a "$LOG_FILE" > /dev/null
        rm -rf "$tmp_dir"
        success "AWS CLI v2 installed"
    fi
else
    warn "AWS CLI already installed"
fi

# aws-sam-cli
pip_install "aws-sam-cli" "AWS SAM CLI"

# cfn-lint
pip_install "cfn-lint" "CloudFormation Linter"

# Session Manager Plugin
if ! installed session-manager-plugin; then
    info "Installing AWS SSM Session Manager Plugin..."
    if [[ "$DRY_RUN" != "true" ]]; then
        tmp_dir=$(mktemp -d)
        arch=$(uname -m)
        case "$arch" in
            x86_64) arch="64bit" ;;
            aarch64) arch="arm64" ;;
        esac
        case "$PKG_MANAGER" in
            apt)
                curl -sL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${arch}/session-manager-plugin.deb" -o "$tmp_dir/smp.deb" >> "$LOG_FILE" 2>&1
                sudo dpkg -i "$tmp_dir/smp.deb" 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
                ;;
            dnf)
                curl -sL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_${arch}/session-manager-plugin.rpm" -o "$tmp_dir/smp.rpm" >> "$LOG_FILE" 2>&1
                sudo dnf install -y "$tmp_dir/smp.rpm" 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
                ;;
            pacman)
                info "Session Manager Plugin on Arch — install from AUR: yay -S aws-session-manager-plugin"
                ;;
        esac
        rm -rf "$tmp_dir"
        if installed session-manager-plugin; then
            success "AWS SSM Session Manager Plugin installed"
        fi
    fi
else
    warn "Session Manager Plugin already installed"
fi

# Granted
if ! installed granted && ! installed assume; then
    info "Installing Granted (AWS SSO credential switching)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        if installed brew; then
            brew tap common-fate/granted >> "$LOG_FILE" 2>&1 || true
            if brew install granted >> "$LOG_FILE" 2>&1; then success "Granted installed"; else error "Failed to install Granted"; fi
        else
            # Download from GitHub releases
            arch=$(uname -m)
            case "$arch" in
                x86_64) arch="amd64" ;;
                aarch64) arch="arm64" ;;
            esac
            github_release_install "common-fate/granted" "assume" "https://releases.commonfate.io/granted/VERSION/granted_VVERSION_linux_ARCH.tar.gz" "Granted"
        fi
    fi
else
    warn "Granted already installed"
fi

# AWS CDK (via npm)
if installed npm; then
    npm_global_install "aws-cdk" "AWS CDK CLI"
    npm_global_install "cdk-nag" "cdk-nag"
fi

fi  # aws

# =============================================================================
if should_run "iac"; then
banner "Infrastructure as Code"

# OpenTofu (open-source Terraform)
if ! installed tofu; then
    case "$PKG_MANAGER" in
        apt)
            info "Adding OpenTofu apt repository..."
            if [[ "$DRY_RUN" != "true" ]]; then
                sudo install -m 0755 -d /etc/apt/keyrings 2>/dev/null || true
                curl -fsSL https://get.opentofu.org/opentofu.gpg | sudo tee /etc/apt/keyrings/opentofu.gpg >/dev/null 2>&1
                curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | sudo gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null 2>&1
                echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" | sudo tee /etc/apt/sources.list.d/opentofu.list > /dev/null 2>&1
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
                pkg_install "tofu" "-" "-" "OpenTofu (open-source Terraform)"
            fi
            ;;
        dnf)
            info "Adding OpenTofu dnf repository..."
            if [[ "$DRY_RUN" != "true" ]]; then
                cat <<'TOFU_REPO' | sudo tee /etc/yum.repos.d/opentofu.repo > /dev/null
[opentofu]
name=opentofu
baseurl=https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/$basearch
repo_gpgcheck=0
gpgcheck=1
enabled=1
gpgkey=https://get.opentofu.org/opentofu.gpg
       https://packages.opentofu.org/opentofu/tofu/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
TOFU_REPO
                pkg_install "-" "tofu" "-" "OpenTofu (open-source Terraform)"
            fi
            ;;
        pacman)
            info "OpenTofu on Arch — install from AUR: yay -S opentofu-bin, or use brew"
            if installed brew; then
                brew_install "opentofu" "OpenTofu (open-source Terraform)"
            fi
            ;;
    esac
else
    warn "OpenTofu already installed"
    progress
fi

# tflint
if ! installed tflint; then
    if installed brew; then
        brew_install "tflint" "tflint (Terraform linter)"
    else
        info "Installing tflint from GitHub releases..."
        if [[ "$DRY_RUN" != "true" ]]; then
            installer
            installer="$(mktemp)"
            curl -fsSL "https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh" -o "$installer"
            if [[ ! -s "$installer" ]]; then
                error "Failed to download tflint installer"
                rm -f "$installer"
            else
                if bash "$installer" >> "$LOG_FILE" 2>&1; then
                    success "tflint installed"
                else
                    error "Failed to install tflint"
                fi
                rm -f "$installer"
            fi
        fi
    fi
else
    warn "tflint already installed"
    progress
fi

# infracost
if ! installed infracost; then
    if installed brew; then
        brew_install "infracost" "infracost (cost estimation for Terraform changes)"
    else
        info "Installing infracost from GitHub releases..."
        if [[ "$DRY_RUN" != "true" ]]; then
            installer
            installer="$(mktemp)"
            curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh -o "$installer" 2>/dev/null
            if [[ ! -s "$installer" ]]; then
                error "Failed to download infracost installer"
                rm -f "$installer"
                return 1
            fi
            if sh "$installer" >> "$LOG_FILE" 2>&1; then
                success "infracost installed"
            else
                error "Failed to install infracost"
            fi
            rm -f "$installer"
        fi
    fi
else
    warn "infracost already installed"
    progress
fi

fi  # iac

# =============================================================================
if should_run "security"; then
banner "Security & Secrets"

# detect-secrets
pip_install "detect-secrets" "detect-secrets (Yelp pre-commit secret detection)"

# gitleaks
if ! installed gitleaks; then
    github_release_install "gitleaks/gitleaks" "gitleaks" "https://github.com/gitleaks/gitleaks/releases/download/VERSION/gitleaks_VVERSION_linux_ARCH.tar.gz" "gitleaks (fast git secret scanning)"
else
    warn "gitleaks already installed"
    progress
fi

# age
pkg_install "age" "age" "age" "age (modern file encryption)"

# sops
if ! installed sops; then
    github_release_install "getsops/sops" "sops" "https://github.com/getsops/sops/releases/download/VERSION/sops-VERSION.linux.ARCH" "sops (encrypt secrets in YAML/JSON)"
else
    warn "sops already installed"
    progress
fi

# trivy
setup_trivy_repo
pkg_install "trivy" "trivy" "-" "trivy (container & IaC vulnerability scanning)"
if [[ "$PKG_MANAGER" == "pacman" ]] && ! installed trivy; then
    info "trivy on Arch — install from AUR: yay -S trivy-bin"
fi

# semgrep
pip_install "semgrep" "semgrep (static analysis)"

# cosign
if ! installed cosign; then
    github_release_install "sigstore/cosign" "cosign" "https://github.com/sigstore/cosign/releases/download/VERSION/cosign-linux-ARCH" "cosign (sign & verify container images)"
else
    warn "cosign already installed"
    progress
fi

# snyk CLI
if ! installed snyk; then
    if installed npm; then
        npm_global_install "snyk" "Snyk CLI"
    fi
else
    warn "Snyk CLI already installed"
fi

# mkcert
if ! installed mkcert; then
    github_release_install "FiloSottile/mkcert" "mkcert" "https://github.com/FiloSottile/mkcert/releases/download/VERSION/mkcert-VERSION-linux-ARCH" "mkcert (local HTTPS certs for dev)"
else
    warn "mkcert already installed"
    progress
fi

# wireshark
pkg_install "wireshark" "wireshark" "wireshark-qt" "Wireshark (network packet analysis)"

# ssh-audit
pip_install "ssh-audit" "ssh-audit (audit SSH server/client config)"

# ClamAV
pkg_install "clamav" "clamav" "clamav" "ClamAV (open-source antivirus)"

# Firewall note
info "Linux firewall: ufw (apt) / firewalld (dnf) — configure manually"
echo "  -> Enable ufw: sudo ufw enable"
echo "  -> LUKS: full disk encryption — set up during OS install"

# Install local CA for mkcert
if installed mkcert; then
    info "Installing local CA for mkcert..."
    mkcert -install 2>/dev/null || true
    success "mkcert local CA installed"
fi

fi  # security

# =============================================================================
if should_run "replacements"; then
banner "Modern Tool Replacements"
echo "  (upgrades for standard Unix utilities)"
echo ""

# eza (replaces ls)
if ! installed eza; then
    case "$PKG_MANAGER" in
        apt)
            # eza has its own repo for Debian/Ubuntu
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null 2>&1
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            pkg_install "eza" "-" "-" "eza (replaces ls)"
            ;;
        dnf)
            pkg_install "-" "eza" "-" "eza (replaces ls)"
            if ! installed eza; then cargo_install "eza" "eza (replaces ls)"; fi
            ;;
        pacman)
            pkg_install "-" "-" "eza" "eza (replaces ls)"
            ;;
    esac
else
    warn "eza already installed"
    progress
fi

# bat (replaces cat)
pkg_install "bat" "bat" "bat" "bat (replaces cat — syntax highlighting)"
# Symlink batcat -> bat on Debian/Ubuntu
if [[ "$PKG_MANAGER" == "apt" ]] && installed batcat && ! installed bat; then
    sudo ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true
    info "Created symlink: batcat -> bat"
fi

# fd (replaces find)
pkg_install "fd-find" "fd-find" "fd" "fd (replaces find — faster, simpler syntax)"
# Symlink fdfind -> fd on Debian/Ubuntu
if [[ "$PKG_MANAGER" == "apt" ]] && installed fdfind && ! installed fd; then
    sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
    info "Created symlink: fdfind -> fd"
fi

# ripgrep
pkg_install "ripgrep" "ripgrep" "ripgrep" "ripgrep (replaces grep — 10x faster)"

# zoxide (replaces cd)
if ! installed zoxide; then
    case "$PKG_MANAGER" in
        apt|dnf)
            # zoxide not always in repos — use installer
            installer
            installer="$(mktemp)"
            curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o "$installer" 2>/dev/null
            if [[ ! -s "$installer" ]]; then
                error "Failed to download zoxide installer"
                rm -f "$installer"
                cargo_install "zoxide" "zoxide (replaces cd)"
            else
                if bash "$installer" >> "$LOG_FILE" 2>&1; then success "zoxide installed"; else cargo_install "zoxide" "zoxide (replaces cd)"; fi
                rm -f "$installer"
            fi
            ;;
        pacman)
            pkg_install "-" "-" "zoxide" "zoxide (replaces cd)"
            ;;
    esac
else
    warn "zoxide already installed"
    progress
fi

# delta already installed in Git section
info "delta (replaces diff — already installed in Git section)"

# tldr
if installed npm; then
    npm_global_install "tldr" "tldr (replaces man — simplified with examples)"
fi

# btop
pkg_install "btop" "btop" "btop" "btop (replaces top/htop — graphs, mouse support)"

# sd
if ! installed sd; then
    cargo_install "sd" "sd (replaces sed — intuitive find & replace)"
else
    warn "sd already installed"
    progress
fi

# choose
cargo_install "choose" "choose (replaces cut/awk — simpler column selection)"

# dust
if ! installed dust; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "dust" "dust (replaces du)" ;;
        *) cargo_install "du-dust" "dust (replaces du — visual disk usage tree)" ;;
    esac
else
    warn "dust already installed"
    progress
fi

# duf
if ! installed duf; then
    case "$PKG_MANAGER" in
        apt) github_release_install "muesli/duf" "duf" "https://github.com/muesli/duf/releases/download/VERSION/duf_VVERSION_linux_ARCH.deb" "duf (replaces df)" ;;
        dnf) github_release_install "muesli/duf" "duf" "https://github.com/muesli/duf/releases/download/VERSION/duf_VVERSION_linux_ARCH.rpm" "duf (replaces df)" ;;
        pacman) pkg_install "-" "-" "duf" "duf (replaces df)" ;;
    esac
else
    warn "duf already installed"
    progress
fi

# procs
if ! installed procs; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "procs" "procs (replaces ps)" ;;
        *) cargo_install "procs" "procs (replaces ps — sortable, tree view)" ;;
    esac
else
    warn "procs already installed"
    progress
fi

# gping
if ! installed gping; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "gping" "gping (replaces ping)" ;;
        *) cargo_install "gping" "gping (replaces ping — real-time latency graph)" ;;
    esac
else
    warn "gping already installed"
    progress
fi

# xh
if ! installed xh; then
    cargo_install "xh" "xh (replaces curl — colorized, JSON-friendly)"
else
    warn "xh already installed"
    progress
fi

# curlie (curl with httpie-like output)
cargo_install "curlie" "curlie (curl with httpie-like output)"

# doggo (DNS)
if ! installed doggo; then
    github_release_install "mr-karan/doggo" "doggo" "https://github.com/mr-karan/doggo/releases/download/VERSION/doggo_VVERSION_linux_ARCH.tar.gz" "doggo (replaces dig — colorized DNS)"
else
    warn "doggo already installed"
    progress
fi

# tokei
if ! installed tokei; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "tokei" "tokei (lines of code by language)" ;;
        *) cargo_install "tokei" "tokei (replaces wc for code — LOC by language)" ;;
    esac
else
    warn "tokei already installed"
    progress
fi

# tree
pkg_install "tree" "tree" "tree" "tree (directory listing)"

# viddy
if ! installed viddy; then
    github_release_install "sachaos/viddy" "viddy" "https://github.com/sachaos/viddy/releases/download/VERSION/viddy_Linux_ARCH.tar.gz" "viddy (replaces watch)"
else
    warn "viddy already installed"
    progress
fi

# rsync
pkg_install "rsync" "rsync" "rsync" "rsync (better cp/mv for large transfers)"

# hexyl
if ! installed hexyl; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "hexyl" "hexyl (replaces hexdump)" ;;
        *) cargo_install "hexyl" "hexyl (replaces hexdump — colorized hex viewer)" ;;
    esac
else
    warn "hexyl already installed"
    progress
fi

# aria2
pkg_install "aria2" "aria2" "aria2" "aria2 (multi-connection downloads)"

# trash-cli (replaces rm)
pip_install "trash-cli" "trash-cli (replaces rm — moves to Trash, recoverable)"

# difftastic
if ! installed difft; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "difftastic" "difftastic (syntax-aware diffs)" ;;
        *) cargo_install "difftastic" "difftastic (replaces diff — syntax-aware structural diffs)" ;;
    esac
else
    warn "difftastic already installed"
    progress
fi

# vivid (LS_COLORS generator — colorize file listings by type)
if ! installed vivid; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "vivid" "vivid (LS_COLORS generator)" ;;
        *) cargo_install "vivid" "vivid (LS_COLORS generator — colorize file listings by type)" ;;
    esac
else
    warn "vivid already installed"
    progress
fi

# just
if ! installed just; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "just" "just (replaces make)" ;;
        *) cargo_install "just" "just (replaces make — simpler task runner)" ;;
    esac
else
    warn "just already installed"
    progress
fi

# yazi
if ! installed yazi; then
    case "$PKG_MANAGER" in
        pacman) pkg_install "-" "-" "yazi" "yazi (terminal file manager)" ;;
        *) cargo_install "yazi-fm" "yazi (terminal file manager — image preview, vim keys)" ;;
    esac
else
    warn "yazi already installed"
    progress
fi

# fx
if ! installed fx; then
    github_release_install "antonmedv/fx" "fx" "https://github.com/antonmedv/fx/releases/download/VERSION/fx_linux_ARCH" "fx (interactive JSON viewer)"
else
    warn "fx already installed"
    progress
fi

# jnv (interactive JSON navigator with jq filtering)
cargo_install "jnv" "jnv (interactive JSON navigator with jq filtering)"

fi  # replacements

# =============================================================================
if should_run "data-processing"; then
banner "Data & File Processing"

pkg_install "yq" "yq" "yq" "yq (jq for YAML)"
if ! installed yq; then
    snap_install "yq" "yq (jq for YAML)"
fi

pkg_install "miller" "miller" "miller" "miller (awk/sed/jq for CSV, JSON)"
if ! installed mlr; then
    # miller may not be in all repos
    if installed brew; then brew_install "miller" "miller"; fi
fi

pip_install "csvkit" "csvkit (CSV tools)"

pkg_install "pandoc" "pandoc" "pandoc" "pandoc (universal document converter)"
pkg_install "imagemagick" "ImageMagick" "imagemagick" "ImageMagick (image resize, convert)"
pkg_install "ffmpeg" "ffmpeg" "ffmpeg" "ffmpeg (video/audio processing)"

# yt-dlp
if ! installed yt-dlp; then
    pip_install "yt-dlp" "yt-dlp (video/audio downloader)"
fi

fi  # data-processing

# =============================================================================
if should_run "code-quality"; then
banner "Code Quality"

pkg_install "shellcheck" "ShellCheck" "shellcheck" "shellcheck (shell script linter)"

# shfmt
if ! installed shfmt; then
    if installed brew; then
        brew_install "shfmt" "shfmt (shell script formatter)"
    else
        github_release_install "mvdan/sh" "shfmt" "https://github.com/mvdan/sh/releases/download/VERSION/shfmt_VERSION_linux_ARCH" "shfmt (shell script formatter)"
    fi
else
    warn "shfmt already installed"
    progress
fi

# act
if ! installed act; then
    if installed brew; then
        brew_install "act" "act (run GitHub Actions locally)"
    else
        github_release_install "nektos/act" "act" "https://github.com/nektos/act/releases/download/VERSION/act_Linux_ARCH.tar.gz" "act (run GitHub Actions locally)"
    fi
else
    warn "act already installed"
    progress
fi

# act3 (glance at last 3 GitHub Actions runs)
if ! installed act3; then
    if installed brew; then
        brew tap dhth/tap >> "$LOG_FILE" 2>&1 || true
        brew_install "act3" "act3 (glance at last 3 GitHub Actions runs)"
    else
        github_release_install "dhth/act3" "act3" "https://github.com/dhth/act3/releases/download/VERSION/act3_VERSION_linux_ARCH.tar.gz" "act3 (glance at last 3 GitHub Actions runs)"
    fi
else
    warn "act3 already installed"
    progress
fi

# hadolint (Dockerfile linter)
if ! installed hadolint; then
    if installed brew; then
        brew_install "hadolint" "hadolint (Dockerfile linter)"
    else
        info "Installing hadolint from GitHub releases..."
        if [[ "$DRY_RUN" != "true" ]]; then
            arch=$(uname -m)
            case "$arch" in
                x86_64) arch="x86_64" ;;
                aarch64) arch="arm64" ;;
            esac
            curl -sL "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-${arch}" -o /tmp/hadolint >> "$LOG_FILE" 2>&1
            if sudo install /tmp/hadolint /usr/local/bin/hadolint 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                success "hadolint installed"
            else
                error "Failed to install hadolint"
            fi
            rm -f /tmp/hadolint
        fi
    fi
else
    warn "hadolint already installed"
    progress
fi

# ruff (fast Python linter+formatter)
if ! installed ruff; then
    if installed brew; then
        brew_install "ruff" "ruff (fast Python linter+formatter)"
    elif installed pip3; then
        pip_install "ruff" "ruff (fast Python linter+formatter)"
    elif installed cargo; then
        cargo_install "ruff" "ruff (fast Python linter+formatter)"
    else
        info "Installing ruff via standalone installer..."
        if [[ "$DRY_RUN" != "true" ]]; then
            installer
            installer="$(mktemp)"
            curl -LsSf https://astral.sh/ruff/install.sh -o "$installer"
            if [[ ! -s "$installer" ]]; then
                error "Failed to download ruff installer"
                rm -f "$installer"
                return 1
            fi
            if sh "$installer" >> "$LOG_FILE" 2>&1; then
                success "ruff installed"
            else
                error "Failed to install ruff"
            fi
            rm -f "$installer"
        fi
    fi
else
    warn "ruff already installed"
    progress
fi

# typos (source code spell checker)
cargo_install "typos-cli" "typos (source code spell checker — fast, low false positives)"

# ast-grep (structural code search/replace)
cargo_install "ast-grep" "ast-grep (structural code search/replace using AST)"

# JS/TS workflow npm globals
if installed npm; then
    npm_global_install "npkill" "npkill (find and nuke node_modules folders)"
    npm_global_install "commitizen" "commitizen (interactive conventional commits)"
    npm_global_install "@commitlint/cli" "commitlint (enforce conventional commit format)"
    npm_global_install "@antfu/ni" "ni (universal package runner — auto-detects npm/yarn/pnpm/bun)"
fi

fi  # code-quality

# =============================================================================
if should_run "perf-testing"; then
banner "Performance & Load Testing"

if ! installed hyperfine; then
    case "$PKG_MANAGER" in
        apt)
            github_release_install "sharkdp/hyperfine" "hyperfine" "https://github.com/sharkdp/hyperfine/releases/download/VERSION/hyperfine_VVERSION_ARCH.deb" "hyperfine (command benchmarking)"
            ;;
        dnf)
            github_release_install "sharkdp/hyperfine" "hyperfine" "https://github.com/sharkdp/hyperfine/releases/download/VERSION/hyperfine-VVERSION-ARCH-unknown-linux-gnu.tar.gz" "hyperfine (command benchmarking)"
            ;;
        pacman) pkg_install "-" "-" "hyperfine" "hyperfine (command benchmarking)" ;;
    esac
else
    warn "hyperfine already installed"
    progress
fi

cargo_install "oha" "oha (HTTP load testing, Rust-based)"
cargo_install "hurl" "hurl (HTTP requests from plain text files — curl + test runner)"

fi  # perf-testing

# =============================================================================
if should_run "dev-servers"; then
banner "Dev Servers & Tunnels"

snap_install "ngrok" "ngrok (expose localhost)" ""

cargo_install "miniserve" "miniserve (instant file server)"

# caddy
if ! installed caddy; then
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null 2>&1
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null
            pkg_install "caddy" "-" "-" "caddy (modern web server)"
            ;;
        dnf)
            sudo dnf copr enable @caddy/caddy -y 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            pkg_install "-" "caddy" "-" "caddy (modern web server)"
            ;;
        pacman)
            pkg_install "-" "-" "caddy" "caddy (modern web server)"
            ;;
    esac
else
    warn "caddy already installed"
    progress
fi

fi  # dev-servers

# =============================================================================
if should_run "terminal-productivity"; then
banner "Terminal Productivity"

# glow
if ! installed glow; then
    if installed brew; then
        brew_install "glow" "glow (render Markdown in terminal)"
    else
        github_release_install "charmbracelet/glow" "glow" "https://github.com/charmbracelet/glow/releases/download/VERSION/glow_VVERSION_Linux_ARCH.tar.gz" "glow (render Markdown in terminal)"
    fi
else
    warn "glow already installed"
    progress
fi

cargo_install "watchexec-cli" "watchexec (run commands on file changes — better entr)"
pkg_install "pv" "pv" "pv" "pv (pipe viewer — progress bars)"
pkg_install "parallel" "parallel" "parallel" "parallel (GNU parallel)"

# asciinema
pip_install "asciinema" "asciinema (record & share terminal sessions)"

# gum (shell script UI toolkit)
github_release_install "charmbracelet/gum" "gum" "https://github.com/charmbracelet/gum/releases/download/VERSION/gum_VVERSION_Linux_ARCH.tar.gz" "gum (shell script UI toolkit — prompts, spinners)"

# nushell (structured data shell)
cargo_install "nu" "nushell (structured data shell — pipelines output tables)"

# newsboat (terminal RSS reader)
pkg_install "newsboat" "newsboat" "newsboat" "newsboat (terminal RSS/Atom reader)"

# topgrade
if ! installed topgrade; then
    cargo_install "topgrade" "topgrade (update everything)"
else
    warn "topgrade already installed"
    progress
fi

# fastfetch
if ! installed fastfetch; then
    case "$PKG_MANAGER" in
        apt)
            # Not always in default repos
            sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            pkg_install "fastfetch" "-" "-" "fastfetch (system info display)"
            ;;
        dnf) pkg_install "-" "fastfetch" "-" "fastfetch (system info display)" ;;
        pacman) pkg_install "-" "-" "fastfetch" "fastfetch (system info display)" ;;
    esac
else
    warn "fastfetch already installed"
    progress
fi

pkg_install "nano" "nano" "nano" "nano (latest)"

# lnav (advanced log file viewer)
if ! installed lnav; then
    case "$PKG_MANAGER" in
        apt) pkg_install "lnav" "-" "-" "lnav (advanced log file viewer)" ;;
        dnf) pkg_install "-" "lnav" "-" "lnav (advanced log file viewer)" ;;
        pacman) pkg_install "-" "-" "lnav" "lnav (advanced log file viewer)" ;;
    esac
    if ! installed lnav && installed brew; then
        brew_install "lnav" "lnav (advanced log file viewer)"
    fi
else
    warn "lnav already installed"
    progress
fi

# nnn (tiny, fast terminal file manager)
pkg_install "nnn" "nnn" "nnn" "nnn (tiny, fast terminal file manager)"

# progress (coreutils progress viewer)
pkg_install "progress" "progress" "progress" "progress (coreutils progress viewer — cp, mv, dd, tar)"

fi  # terminal-productivity

# =============================================================================
if should_run "k8s-github"; then
banner "Kubernetes & GitHub Extras"

# stern
if ! installed stern; then
    if installed brew; then
        brew_install "stern" "stern (multi-pod log tailing)"
    else
        github_release_install "stern/stern" "stern" "https://github.com/stern/stern/releases/download/VERSION/stern_VVERSION_linux_ARCH.tar.gz" "stern (multi-pod log tailing)"
    fi
else
    warn "stern already installed"
    progress
fi

# gh-dash
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-dash"; then
        warn "gh-dash already installed"
    else
        info "Installing gh-dash (GitHub dashboard)..."
        gh extension install dlvhdr/gh-dash 2>/dev/null || true
        success "gh-dash installed"
    fi
fi

fi  # k8s-github

# =============================================================================
if should_run "database"; then
banner "Database & Data"

pip_install "pgcli" "pgcli (auto-completing Postgres CLI)"
pip_install "mycli" "mycli (auto-completing MySQL CLI)"
cargo_install "lazysql" "lazysql (TUI for databases — interactive SQL in terminal)"

# usql
if installed go; then
    if ! installed usql; then
        info "Installing usql (universal SQL CLI)..."
        go install github.com/xo/usql@latest >> "$LOG_FILE" 2>&1 || error "Failed to install usql"
    else
        warn "usql already installed"
    fi
fi

# sq
if ! installed sq; then
    if installed brew; then
        brew_install "neilotoole/sq/sq" "sq (jq for databases)"
    else
        github_release_install "neilotoole/sq" "sq" "https://github.com/neilotoole/sq/releases/download/VERSION/sq-VERSION-linux-ARCH.tar.gz" "sq (jq for databases)"
    fi
else
    warn "sq already installed"
    progress
fi

# dbmate
if ! installed dbmate; then
    if installed brew; then
        brew_install "dbmate" "dbmate (lightweight DB migrations)"
    else
        github_release_install "amacneil/dbmate" "dbmate" "https://github.com/amacneil/dbmate/releases/download/VERSION/dbmate-linux-ARCH" "dbmate (lightweight DB migrations)"
    fi
else
    warn "dbmate already installed"
    progress
fi

# DBeaver
snap_install "dbeaver-community" "DBeaver Community (advanced SQL, 100+ DB support)" ""

fi  # database

# =============================================================================
if should_run "containers"; then
banner "Containers & Orchestration"

# lazydocker
if ! installed lazydocker; then
    if installed brew; then
        brew_install "lazydocker" "lazydocker (terminal UI for Docker)"
    else
        github_release_install "jesseduffield/lazydocker" "lazydocker" "https://github.com/jesseduffield/lazydocker/releases/download/VERSION/lazydocker_VVERSION_Linux_ARCH.tar.gz" "lazydocker (terminal UI for Docker)"
    fi
else
    warn "lazydocker already installed"
    progress
fi

# dive
if ! installed dive; then
    if installed brew; then
        brew_install "dive" "dive (explore Docker image layers)"
    else
        github_release_install "wagoodman/dive" "dive" "https://github.com/wagoodman/dive/releases/download/VERSION/dive_VVERSION_linux_ARCH.tar.gz" "dive (explore Docker image layers)"
    fi
else
    warn "dive already installed"
    progress
fi

# kubectl
if ! installed kubectl; then
    info "Installing kubectl..."
    if [[ "$DRY_RUN" != "true" ]]; then
        arch=$(uname -m)
        case "$arch" in
            x86_64) arch="amd64" ;;
            aarch64) arch="arm64" ;;
        esac
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${arch}/kubectl" >> "$LOG_FILE" 2>&1
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl 2>&1 | tee -a "$LOG_FILE" > /dev/null
        rm -f kubectl
        success "kubectl installed"
    fi
else
    warn "kubectl already installed"
fi

# k9s
if ! installed k9s; then
    if installed brew; then
        brew_install "k9s" "k9s (terminal UI for Kubernetes)"
    else
        github_release_install "derailed/k9s" "k9s" "https://github.com/derailed/k9s/releases/download/VERSION/k9s_Linux_ARCH.tar.gz" "k9s (terminal UI for Kubernetes)"
    fi
else
    warn "k9s already installed"
    progress
fi

fi  # containers

# =============================================================================
if should_run "api"; then
banner "API Development"

# Postman
snap_install "postman" "Postman (industry-standard API client)" ""
if ! installed postman && ! snap list postman &>/dev/null; then
    flatpak_install "com.getpostman.Postman" "Postman (industry-standard API client)"
fi

# grpcurl
if ! installed grpcurl; then
    if installed brew; then
        brew_install "grpcurl" "grpcurl (curl for gRPC)"
    else
        github_release_install "fullstorydev/grpcurl" "grpcurl" "https://github.com/fullstorydev/grpcurl/releases/download/VERSION/grpcurl_VVERSION_linux_ARCH.tar.gz" "grpcurl (curl for gRPC)"
    fi
else
    warn "grpcurl already installed"
    progress
fi

fi  # api

# =============================================================================
if should_run "networking"; then
banner "Networking & Debugging"

pkg_install "mtr" "mtr" "mtr" "mtr (combines ping + traceroute)"
cargo_install "bandwhich" "bandwhich (real-time bandwidth by process)"
pkg_install "nmap" "nmap" "nmap" "nmap (network scanning)"
cargo_install "trippy" "trippy (modern traceroute TUI with charts)"

# sshclick (SSH config manager)
pip_install "sshclick" "sshclick (SSH config manager — organize ~/.ssh/config)"

fi  # networking

# =============================================================================
if should_run "dx"; then
banner "Developer Experience"

# fzf
pkg_install "fzf" "fzf" "fzf" "fzf (fuzzy finder)"

# starship
if ! installed starship; then
    info "Installing Starship prompt..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL https://starship.rs/install.sh -o "$installer" 2>/dev/null
        if [[ ! -s "$installer" ]]; then
            error "Failed to download Starship installer"
            rm -f "$installer"
            return 1
        fi
        sh "$installer" -y >> "$LOG_FILE" 2>&1
        rm -f "$installer"
        success "Starship prompt installed"
    fi
else
    warn "Starship already installed"
fi

# zsh plugins
case "$PKG_MANAGER" in
    apt)
        pkg_install "zsh-autosuggestions" "-" "-" "zsh-autosuggestions"
        pkg_install "zsh-syntax-highlighting" "-" "-" "zsh-syntax-highlighting"
        ;;
    dnf)
        pkg_install "-" "zsh-autosuggestions" "-" "zsh-autosuggestions"
        pkg_install "-" "zsh-syntax-highlighting" "-" "zsh-syntax-highlighting"
        ;;
    pacman)
        pkg_install "-" "-" "zsh-autosuggestions" "zsh-autosuggestions"
        pkg_install "-" "-" "zsh-syntax-highlighting" "zsh-syntax-highlighting"
        ;;
esac

# atuin
if ! installed atuin; then
    info "Installing atuin (shell history)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl --proto '=https' --tlsv1.2 -fLsSf https://setup.atuin.sh -o "$installer" 2>/dev/null
        if [[ ! -s "$installer" ]]; then
            error "Failed to download atuin installer"
            rm -f "$installer"
            cargo_install "atuin" "atuin (shell history)"
        else
            sh "$installer" >> "$LOG_FILE" 2>&1 || \
            cargo_install "atuin" "atuin (shell history)"
            rm -f "$installer"
        fi
        success "atuin installed"
    fi
else
    warn "atuin already installed"
fi

# VS Code
setup_vscode_repo
pkg_install "code" "code" "code" "VS Code"
if ! installed code && [[ "$PKG_MANAGER" == "pacman" ]]; then
    snap_install "code" "VS Code" "classic"
fi

# Cursor removed (paid) — use VS Code

# Alacritty
pkg_install "alacritty" "alacritty" "alacritty" "Alacritty (GPU-accelerated terminal)"

# kitty
pkg_install "kitty" "kitty" "kitty" "kitty (GPU-accelerated terminal)"

# tmux
pkg_install "tmux" "tmux" "tmux" "tmux (terminal multiplexer)"
cargo_install "zellij" "zellij (modern terminal multiplexer — discoverable UI, layouts)"

# ulauncher (Raycast alternative)
if ! installed ulauncher; then
    case "$PKG_MANAGER" in
        apt)
            sudo add-apt-repository ppa:agornostal/ulauncher -y 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
            pkg_install "ulauncher" "-" "-" "ulauncher (application launcher — Raycast alternative)"
            ;;
        dnf)
            pkg_install "-" "ulauncher" "-" "ulauncher (application launcher)"
            ;;
        pacman)
            pkg_install "-" "-" "ulauncher" "ulauncher (application launcher)"
            ;;
    esac
else
    warn "ulauncher already installed"
    progress
fi

# Claude Code
if installed npm; then
    npm_global_install "@anthropic-ai/claude-code" "Claude Code (AI-assisted coding in terminal)"
fi

# GitHub Copilot CLI
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-copilot"; then
        warn "GitHub Copilot CLI already installed"
    else
        info "Installing GitHub Copilot CLI..."
        gh extension install github/gh-copilot 2>/dev/null || true
        success "GitHub Copilot CLI installed"
    fi
fi

# chezmoi
if ! installed chezmoi; then
    info "Installing chezmoi..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sh -c "$(curl -fsSL get.chezmoi.io)" >> "$LOG_FILE" 2>&1 || true
        if installed chezmoi; then
            success "chezmoi installed"
        elif installed brew; then
            brew_install "chezmoi" "chezmoi (dotfile manager)"
        fi
    fi
else
    warn "chezmoi already installed"
fi

# mitmproxy (replaces Proxyman)
pip_install "mitmproxy" "mitmproxy (HTTP debugging proxy — Proxyman alternative)"

# Node/JS tooling
if installed npm; then
    npm_global_install "typescript" "TypeScript"
    npm_global_install "tsx" "tsx (TS execute)"
    npm_global_install "turbo" "Turborepo"
fi

# fzf key bindings
if installed fzf; then
    FZF_KEYBINDINGS=""
    for path in /usr/share/doc/fzf/examples/key-bindings.zsh \
                /usr/share/fzf/key-bindings.zsh \
                /usr/share/fzf/shell/key-bindings.zsh \
                /etc/profile.d/fzf.zsh; do
        [[ -f "$path" ]] && FZF_KEYBINDINGS="$path" && break
    done
    if [[ -n "$FZF_KEYBINDINGS" ]]; then
        info "fzf key bindings found at $FZF_KEYBINDINGS"
    fi
fi

fi  # dx

# =============================================================================
if should_run "ui"; then
banner "UI Development"

# Chrome
setup_chrome_repo
pkg_install "google-chrome-stable" "google-chrome-stable" "-" "Google Chrome"
if [[ "$PKG_MANAGER" == "pacman" ]] && ! installed google-chrome-stable; then
    info "Chrome on Arch — install from AUR: yay -S google-chrome"
fi

fi  # ui

# =============================================================================
if should_run "ux"; then
banner "UX & Design"

if installed npm; then
    npm_global_install "lighthouse" "Lighthouse CLI"
fi

fi  # ux

# =============================================================================
if should_run "docs"; then
banner "Documentation & Diagrams"

# d2
if ! installed d2; then
    if installed brew; then
        brew_install "d2" "d2 (code-to-diagram)"
    else
        installer
        installer="$(mktemp)"
        curl -fsSL "https://d2lang.com/install.sh" -o "$installer" 2>/dev/null
        if [[ ! -s "$installer" ]]; then
            error "Failed to download d2 installer"
            rm -f "$installer"
        else
            if sh "$installer" >> "$LOG_FILE" 2>&1; then success "d2 installed"; else error "Failed to install d2"; fi
            rm -f "$installer"
        fi
    fi
else
    warn "d2 already installed"
    progress
fi

if installed npm; then
    npm_global_install "@mermaid-js/mermaid-cli" "Mermaid CLI"
fi

fi  # docs

# =============================================================================
if should_run "linux-system"; then
banner "Linux Apps — System & Utilities"

# p7zip (replaces Keka/Unarchiver)
pkg_install "p7zip-full" "p7zip" "p7zip" "p7zip (archive utility)"

# gnome-sushi (Quick Look for Linux)
pkg_install "gnome-sushi" "-" "sushi" "gnome-sushi (file previewer — Quick Look equivalent)"

# caffeine (prevent sleep)
pkg_install "caffeine" "caffeine" "-" "caffeine (prevent sleep — Amphetamine equivalent)"


# Mullvad VPN
pkg_install "mullvad-vpn" "mullvad-vpn" "-" "Mullvad VPN (privacy-focused, no account email required)"

fi  # linux-system

# =============================================================================
if should_run "linux-productivity"; then
banner "Linux Apps — Productivity"

# Flameshot (replaces Shottr)
pkg_install "flameshot" "flameshot" "flameshot" "Flameshot (screenshots — Shottr equivalent)"

# Espanso
if ! installed espanso; then
    snap_install "espanso" "Espanso (text expander)" "classic"
fi

# evince (PDF reader — usually pre-installed)
pkg_install "evince" "evince" "evince" "Evince (PDF reader)"

# Notion
snap_install "notion-snap-reborn" "Notion" ""

# Filezilla (replaces Transmit)
pkg_install "filezilla" "filezilla" "filezilla" "FileZilla (SFTP client — Transmit equivalent)"

fi  # linux-productivity

# =============================================================================
if should_run "linux-communication"; then
banner "Linux Apps — Communication"

snap_install "slack" "Slack" "classic"
snap_install "telegram-desktop" "Telegram" ""

fi  # linux-communication

# =============================================================================
if should_run "linux-browsers"; then
banner "Linux Apps — Browsers"

# Firefox (usually pre-installed)
pkg_install "firefox" "firefox" "firefox" "Firefox"

# Brave
setup_brave_repo
pkg_install "brave-browser" "brave-browser" "-" "Brave Browser"
if [[ "$PKG_MANAGER" == "pacman" ]] && ! installed brave; then
    info "Brave on Arch — install from AUR: yay -S brave-bin"
fi

# Chrome (already handled in UI section, just ensure it's here too)
if ! installed google-chrome-stable; then
    setup_chrome_repo
    pkg_install "google-chrome-stable" "google-chrome-stable" "-" "Google Chrome"
fi

npm_global_install "carbonyl" "Carbonyl (Chromium-based browser for the terminal)"

# w3m (text-based terminal browser)
pkg_install "w3m" "w3m" "w3m" "w3m (text-based terminal browser and pager)"

# monolith (save complete web pages as a single HTML file)
if ! installed monolith; then
    case "$PKG_MANAGER" in
        apt) pkg_install "monolith" "-" "-" "monolith (save web pages as single HTML)" ;;
        dnf) pkg_install "-" "monolith" "-" "monolith (save web pages as single HTML)" ;;
        pacman) pkg_install "-" "-" "monolith" "monolith (save web pages as single HTML)" ;;
    esac
    if ! installed monolith; then
        cargo_install "monolith" "monolith (save web pages as single HTML)"
    fi
else
    warn "monolith already installed"
    progress
fi

fi  # linux-browsers

# =============================================================================
if should_run "linux-media"; then
banner "Linux Apps — Media"

# mpv (replaces IINA)
pkg_install "mpv" "mpv" "mpv" "mpv (video player — IINA equivalent)"

# Image compression (CLI)
cargo_install "oxipng" "oxipng (lossless PNG compression)"
pkg_install "jpegoptim" "jpegoptim" "jpegoptim" "jpegoptim (lossless JPEG compression)"

# LibreOffice (usually pre-installed)
pkg_install "libreoffice" "libreoffice" "libreoffice-fresh" "LibreOffice"

# cmus (ncurses terminal music player)
pkg_install "cmus" "cmus" "cmus" "cmus (ncurses terminal music player)"

fi  # linux-media

# =============================================================================
if should_run "linux-cloud"; then
banner "Linux Apps — Cloud"

# rclone (Google Drive mount)
if ! installed rclone; then
    info "Installing rclone (Google Drive / cloud storage mount)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        installer
        installer="$(mktemp)"
        curl -fsSL "https://rclone.org/install.sh" -o "$installer"
        if [[ ! -s "$installer" ]]; then
            error "Failed to download rclone installer"
            rm -f "$installer"
        else
            sudo bash "$installer" 2>&1 | tee -a "$LOG_FILE" > /dev/null
            rm -f "$installer"
            success "rclone installed (configure: rclone config)"
        fi
    fi
else
    warn "rclone already installed"
fi

# Syncthing (real-time file sync between devices)
if ! installed syncthing; then
    case "$PKG_MANAGER" in
        apt)
            info "Adding Syncthing apt repository..."
            if [[ "$DRY_RUN" != "true" ]]; then
                sudo mkdir -p /etc/apt/keyrings 2>/dev/null || true
                curl -fsSL https://syncthing.net/release-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/syncthing-archive-keyring.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null 2>&1
                sudo apt-get update 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
                pkg_install "syncthing" "-" "-" "Syncthing (real-time file sync)"
            fi
            ;;
        dnf) pkg_install "-" "syncthing" "-" "Syncthing (real-time file sync)" ;;
        pacman) pkg_install "-" "-" "syncthing" "Syncthing (real-time file sync)" ;;
    esac
else
    warn "syncthing already installed"
    progress
fi

# borgbackup (deduplicated encrypted backups)
if ! installed borg; then
    case "$PKG_MANAGER" in
        apt) pkg_install "borgbackup" "-" "-" "borgbackup (deduplicated encrypted backups)" ;;
        dnf) pkg_install "-" "borgbackup" "-" "borgbackup (deduplicated encrypted backups)" ;;
        pacman) pkg_install "-" "-" "borg" "borgbackup (deduplicated encrypted backups)" ;;
    esac
else
    warn "borgbackup already installed"
    progress
fi

# borgmatic (automated borg backup scheduling)
pip_install "borgmatic" "borgmatic (automated borg backup scheduling)"

fi  # linux-cloud

# =============================================================================
if should_run "linux-focus"; then
banner "Linux Apps — Focus & Learning"

# NewsFlash (replaces Reeder)
flatpak_install "io.gitlab.news_flash.NewsFlash" "NewsFlash (RSS reader — Reeder equivalent)"

fi  # linux-focus

# =============================================================================
if should_run "linux-disk"; then
banner "Linux Apps — Disk"

pkg_install "ncdu" "ncdu" "ncdu" "ncdu (interactive disk usage analyzer)"

fi  # linux-disk

# =============================================================================
if should_run "dracula"; then
banner "Dracula Theme"

# VS Code - Dracula theme
if installed code; then
    if code --list-extensions 2>/dev/null | grep -qi "dracula-theme.theme-dracula"; then
        warn "VS Code Dracula theme already installed"
    else
        info "Installing Dracula theme for VS Code..."
        code --install-extension dracula-theme.theme-dracula >> "$LOG_FILE" 2>&1
        success "VS Code Dracula theme installed"
    fi
fi

# bat (Dracula is built-in)
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    if [[ -n "$BAT_CONFIG_DIR" ]]; then
        mkdir -p "$BAT_CONFIG_DIR"
        if [[ -f "$BAT_CONFIG_DIR/config" ]] && grep -q 'Dracula' "$BAT_CONFIG_DIR/config" 2>/dev/null; then
            warn "bat Dracula theme already configured"
        else
            echo '--theme="Dracula"' >> "$BAT_CONFIG_DIR/config"
            success "bat Dracula theme configured"
        fi
    fi
fi

# delta (git diffs)
if git config --global delta.syntax-theme &>/dev/null; then
    warn "delta syntax theme already set"
else
    info "Setting delta to Dracula theme..."
    git config --global delta.syntax-theme Dracula
    success "delta Dracula theme configured"
fi

# Alacritty Dracula config
ALACRITTY_CONFIG_DIR="$HOME/.config/alacritty"
ALACRITTY_CONFIG="$ALACRITTY_CONFIG_DIR/alacritty.toml"
if [[ -f "$ALACRITTY_CONFIG" ]]; then
    warn "Alacritty config already exists"
else
    info "Creating Alacritty Dracula configuration..."
    mkdir -p "$ALACRITTY_CONFIG_DIR"
    cat > "$ALACRITTY_CONFIG" <<'ALACRITTY_CONF'
# Alacritty configuration with Dracula theme

[font]
size = 14.0

[font.normal]
family = "JetBrains Mono"
style = "Regular"

[font.bold]
family = "JetBrains Mono"
style = "Bold"

[font.italic]
family = "JetBrains Mono"
style = "Italic"

[window]
padding = { x = 8, y = 4 }
decorations = "full"
opacity = 0.95

[scrolling]
history = 50000

# Dracula theme colors
[colors.primary]
background = "#282a36"
foreground = "#f8f8f2"

[colors.cursor]
text = "#44475a"
cursor = "#f8f8f2"

[colors.selection]
text = "#f8f8f2"
background = "#44475a"

[colors.normal]
black   = "#21222c"
red     = "#ff5555"
green   = "#50fa7b"
yellow  = "#f1fa8c"
blue    = "#bd93f9"
magenta = "#ff79c6"
cyan    = "#8be9fd"
white   = "#f8f8f2"

[colors.bright]
black   = "#6272a4"
red     = "#ff6e6e"
green   = "#69ff94"
yellow  = "#ffffa5"
blue    = "#d6acff"
magenta = "#ff92df"
cyan    = "#a4ffff"
white   = "#ffffff"
ALACRITTY_CONF
    success "Alacritty Dracula theme configured"
fi

# kitty Dracula config
KITTY_CONFIG_DIR="$HOME/.config/kitty"
KITTY_CONFIG="$KITTY_CONFIG_DIR/kitty.conf"
if [[ -f "$KITTY_CONFIG" ]]; then
    warn "kitty config already exists"
else
    info "Creating kitty Dracula configuration..."
    mkdir -p "$KITTY_CONFIG_DIR"
    cat > "$KITTY_CONFIG" <<'KITTY_CONF'
# kitty configuration with Dracula theme

font_family      JetBrains Mono
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        14.0

window_padding_width 4
confirm_os_window_close 0
scrollback_lines 50000
copy_on_select   clipboard

# Dracula theme
foreground            #f8f8f2
background            #282a36
selection_foreground  #f8f8f2
selection_background  #44475a

url_color #8be9fd

# black
color0  #21222c
color8  #6272a4

# red
color1  #ff5555
color9  #ff6e6e

# green
color2  #50fa7b
color10 #69ff94

# yellow
color3  #f1fa8c
color11 #ffffa5

# blue
color4  #bd93f9
color12 #d6acff

# magenta
color5  #ff79c6
color13 #ff92df

# cyan
color6  #8be9fd
color14 #a4ffff

# white
color7  #f8f8f2
color15 #ffffff

cursor            #f8f8f2
cursor_text_color #282a36

active_tab_foreground   #282a36
active_tab_background   #bd93f9
inactive_tab_foreground #f8f8f2
inactive_tab_background #44475a
KITTY_CONF
    success "kitty Dracula theme configured"
fi

# Starship prompt (rich config with Dracula palette)
STARSHIP_CONFIG="$HOME/.config/starship.toml"
if [[ -f "$STARSHIP_CONFIG" ]] && grep -q "dracula" "$STARSHIP_CONFIG" 2>/dev/null; then
    warn "Starship config already configured"
else
    info "Creating rich Starship prompt config..."
    mkdir -p "$(dirname "$STARSHIP_CONFIG")"
    cat > "$STARSHIP_CONFIG" <<'STARSHIP_CONF'
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
"Documents" = "󰈙 "
"Downloads" = " "
"Code" = " "
"Creative" = "🎨"
"Media" = "🎵"

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
fi

# GTK dark theme
if [[ "$DRY_RUN" != "true" ]] && command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
    info "GTK dark theme set (Adwaita-dark)"
fi

fi  # dracula

# =============================================================================
if should_run "configs"; then
banner "Tool Configurations"

# ---- tmux ----
TMUX_CONF="$HOME/.tmux.conf"
if [[ -f "$TMUX_CONF" ]]; then
    warn "tmux config already exists at $TMUX_CONF"
else
    info "Creating tmux configuration..."
    cat > "$TMUX_CONF" <<'TMUX_CONFIG'
# =============================================================================
# tmux configuration
# =============================================================================

# -- Prefix: Ctrl-a instead of Ctrl-b (easier to reach) ----------------------
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# -- General ------------------------------------------------------------------
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
set -g history-limit 50000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g set-clipboard on
set -sg escape-time 0
set -g focus-events on
set -g display-time 3000
set -g status-interval 5

# -- Keybindings --------------------------------------------------------------
# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Split panes with | and -
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# New window in current path
bind c new-window -c "#{pane_current_path}"

# Navigate panes with vim keys
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Resize panes with vim keys
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Vi mode for copy — use xclip on Linux
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "xclip -selection clipboard"

# Quick pane switching with Alt+arrow (no prefix)
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# -- Dracula Colors -----------------------------------------------------------
# Status bar
set -g status-style "bg=#44475a,fg=#f8f8f2"
set -g status-left "#[bg=#bd93f9,fg=#282a36,bold] #S #[bg=#44475a] "
set -g status-right "#[fg=#6272a4]%Y-%m-%d #[fg=#f8f8f2]%H:%M #[bg=#bd93f9,fg=#282a36,bold] #h "
set -g status-left-length 30
set -g status-right-length 50

# Window tabs
setw -g window-status-format "#[fg=#6272a4] #I:#W "
setw -g window-status-current-format "#[bg=#282a36,fg=#50fa7b,bold] #I:#W "

# Pane borders
set -g pane-border-style "fg=#6272a4"
set -g pane-active-border-style "fg=#bd93f9"

# Message style
set -g message-style "bg=#44475a,fg=#f8f8f2"

# Clock
setw -g clock-mode-colour "#bd93f9"

# -- Plugins (via TPM) -------------------------------------------------------
# Install TPM: git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
# Then press prefix + I (capital i) to install plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'    # Save/restore sessions (prefix + Ctrl-s / Ctrl-r)
set -g @plugin 'tmux-plugins/tmux-continuum'     # Auto-save sessions every 15 min
set -g @continuum-restore 'on'                   # Auto-restore on tmux start

# Initialize TPM (must be last line)
run '~/.tmux/plugins/tpm/tpm'
TMUX_CONFIG
    success "tmux configured at $TMUX_CONF"
fi

# ---- tmux plugin manager (TPM) ----
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -d "$TPM_DIR" ]]; then
    warn "tmux plugin manager (TPM) already installed"
else
    info "Installing tmux plugin manager (TPM)..."
    if [[ "$DRY_RUN" != "true" ]]; then
        git clone https://github.com/tmux-plugins/tpm "$TPM_DIR" 2>/dev/null || true
        success "TPM installed (press prefix + I in tmux to install plugins)"
    else
        info "[DRY RUN] Would install TPM"
    fi
fi

# ---- git global config ----
if [[ "$DRY_RUN" != "true" ]]; then
info "Configuring git global settings..."

git config --global init.defaultBranch main 2>/dev/null
git config --global pull.rebase true
git config --global rebase.autoStash true
git config --global diff.algorithm histogram
git config --global commit.verbose true
git config --global help.autocorrect 5
git config --global column.ui auto
git config --global branch.sort -committerdate
git config --global rerere.enabled true

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

success "git global settings configured"
fi  # DRY_RUN check for git global config

# ---- GPG + pinentry ----
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
if [[ -f "$GPG_AGENT_CONF" ]] && grep -q "pinentry" "$GPG_AGENT_CONF" 2>/dev/null; then
    warn "GPG pinentry already configured"
else
    info "Configuring GPG pinentry..."
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    # Find pinentry
    PINENTRY_PATH=$(command -v pinentry-curses 2>/dev/null || command -v pinentry-gnome3 2>/dev/null || command -v pinentry 2>/dev/null || echo "/usr/bin/pinentry")
    cat > "$GPG_AGENT_CONF" <<GPG_CONFIG
# GPG agent config
pinentry-program $PINENTRY_PATH

# Cache passphrase for 8 hours
default-cache-ttl 28800
max-cache-ttl 28800
GPG_CONFIG
    gpgconf --kill gpg-agent 2>/dev/null || true
    success "GPG pinentry configured (passphrases cached 8 hours)"
fi

# ---- aria2 ----
ARIA2_CONFIG_DIR="$HOME/.aria2"
ARIA2_CONFIG="$ARIA2_CONFIG_DIR/aria2.conf"
if [[ -f "$ARIA2_CONFIG" ]]; then
    warn "aria2 config already exists"
else
    info "Creating aria2 configuration..."
    mkdir -p "$ARIA2_CONFIG_DIR"
    cat > "$ARIA2_CONFIG" <<ARIA2_CONF
## aria2 configuration

# Max concurrent downloads
max-concurrent-downloads=5

# Max connections per server
max-connection-per-server=16

# Split file into pieces
split=16

# Min split size
min-split-size=1M

# Retry
max-tries=5
retry-wait=10

# Resume
continue=true

# Download directory
dir=$HOME/Downloads

# File allocation
file-allocation=none

# Auto-rename
auto-file-renaming=true

# Console
summary-interval=0
human-readable=true
enable-color=true

# HTTP
content-disposition-default-utf8=true
http-accept-gzip=true
user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36

# BitTorrent
enable-dht=true
enable-dht6=true
listen-port=6881-6999
seed-ratio=1.0
max-overall-upload-limit=256K

# Disk cache
disk-cache=64M
ARIA2_CONF
    success "aria2 configured (16 connections, auto-resume, BitTorrent)"
fi

# ---- atuin ----
ATUIN_CONFIG_DIR="$HOME/.config/atuin"
ATUIN_CONFIG="$ATUIN_CONFIG_DIR/config.toml"
if [[ -f "$ATUIN_CONFIG" ]]; then
    warn "atuin config already exists"
else
    info "Creating atuin configuration..."
    mkdir -p "$ATUIN_CONFIG_DIR"
    cat > "$ATUIN_CONFIG" <<'ATUIN_CONF'
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
fi

# ---- lazygit Dracula theme ----
LAZYGIT_CONFIG_DIR="$HOME/.config/lazygit"
LAZYGIT_CONFIG="$LAZYGIT_CONFIG_DIR/config.yml"
if [[ -f "$LAZYGIT_CONFIG" ]] && grep -q "activeBorderColor" "$LAZYGIT_CONFIG" 2>/dev/null; then
    warn "lazygit theme already configured"
else
    info "Creating lazygit Dracula config..."
    mkdir -p "$LAZYGIT_CONFIG_DIR"
    cat > "$LAZYGIT_CONFIG" <<'LAZYGIT_CONF'
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
  editPreset: "vscode"
  open: "xdg-open {{filename}}"
  openLink: "xdg-open {{link}}"
notARepository: skip
promptToReturnFromSubprocess: false
LAZYGIT_CONF
    success "lazygit configured (Dracula theme, delta pager, auto-fetch, VS Code editor)"
fi

# ---- k9s Dracula skin ----
K9S_SKINS_DIR="$HOME/.config/k9s/skins"
K9S_CONFIG_DIR="$HOME/.config/k9s"
K9S_SKIN="$K9S_SKINS_DIR/dracula.yaml"
if [[ -f "$K9S_SKIN" ]]; then
    warn "k9s Dracula skin already exists"
else
    info "Creating k9s Dracula skin..."
    mkdir -p "$K9S_SKINS_DIR"
    cat > "$K9S_SKIN" <<'K9S_DRACULA'
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

    K9S_MAIN_CONFIG="$K9S_CONFIG_DIR/config.yaml"
    if [[ -f "$K9S_MAIN_CONFIG" ]]; then
        if ! grep -q "skin:" "$K9S_MAIN_CONFIG" 2>/dev/null; then
            echo "  skin: dracula" >> "$K9S_MAIN_CONFIG"
        fi
    else
        cat > "$K9S_MAIN_CONFIG" <<'K9S_CFG'
k9s:
  ui:
    skin: dracula
K9S_CFG
    fi
    success "k9s Dracula skin configured"
fi

# ---- VS Code settings ----
VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
VSCODE_SETTINGS="$VSCODE_SETTINGS_DIR/settings.json"
if [[ -f "$VSCODE_SETTINGS" ]]; then
    warn "VS Code settings.json already exists — not overwriting"
    info "  To use Dracula, add: \"workbench.colorTheme\": \"Dracula\""
else
    info "Creating VS Code settings..."
    mkdir -p "$VSCODE_SETTINGS_DIR"
    cat > "$VSCODE_SETTINGS" <<'VSCODE_CONF'
{
    "workbench.colorTheme": "Dracula",
    "workbench.iconTheme": "vs-seti",
    "workbench.startupEditor": "none",
    "workbench.tree.indent": 16,

    "editor.fontFamily": "'JetBrains Mono', 'Fira Code', 'Droid Sans Mono', monospace",
    "editor.fontSize": 14,
    "editor.lineHeight": 1.6,
    "editor.fontLigatures": true,
    "editor.minimap.enabled": false,
    "editor.renderWhitespace": "boundary",
    "editor.smoothScrolling": true,
    "editor.cursorBlinking": "smooth",
    "editor.cursorSmoothCaretAnimation": "on",
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.tabSize": 2,
    "editor.wordWrap": "on",
    "editor.linkedEditing": true,
    "editor.stickyScroll.enabled": true,
    "editor.stickyScroll.maxLineCount": 3,
    "editor.inlayHints.enabled": "onUnlessPressed",
    "editor.suggest.preview": true,
    "editor.suggest.showStatusBar": true,

    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": "active",
    "workbench.colorCustomizations": {
        "editorBracketHighlight.foreground1": "#bd93f9",
        "editorBracketHighlight.foreground2": "#50fa7b",
        "editorBracketHighlight.foreground3": "#ffb86c",
        "editorBracketHighlight.foreground4": "#ff79c6",
        "editorBracketHighlight.foreground5": "#8be9fd",
        "editorBracketHighlight.foreground6": "#f1fa8c"
    },

    "files.autoSave": "onFocusChange",
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,

    "explorer.fileNesting.enabled": true,
    "explorer.fileNesting.expand": false,
    "explorer.fileNesting.patterns": {
        "*.ts": "${capture}.js, ${capture}.d.ts, ${capture}.js.map, ${capture}.test.ts, ${capture}.spec.ts",
        "*.tsx": "${capture}.test.tsx, ${capture}.spec.tsx, ${capture}.stories.tsx",
        "*.js": "${capture}.js.map, ${capture}.test.js, ${capture}.spec.js",
        "package.json": "package-lock.json, pnpm-lock.yaml, yarn.lock, .npmrc, .nvmrc, .node-version, .eslintrc*, .prettierrc*, tsconfig*.json, vite.config.*, vitest.config.*, jest.config.*, tailwind.config.*, postcss.config.*",
        "README.md": "LICENSE, CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md",
        ".env": ".env.*, .env.local, .env.development, .env.production, .env.test",
        "Dockerfile": "docker-compose*.yml, .dockerignore",
        "Cargo.toml": "Cargo.lock, rust-toolchain.toml",
        "go.mod": "go.sum"
    },
    "explorer.confirmDragAndDrop": false,
    "explorer.confirmDelete": false,

    "terminal.integrated.fontFamily": "'JetBrains Mono NF', 'MesloLGS NF', monospace",
    "terminal.integrated.fontSize": 13,
    "terminal.integrated.cursorStyle": "line",
    "terminal.integrated.cursorBlinking": true,
    "terminal.integrated.defaultProfile.linux": "zsh",

    "breadcrumbs.enabled": true,
    "telemetry.telemetryLevel": "off",

    "todo-tree.general.tags": ["TODO", "FIXME", "HACK", "BUG", "XXX"],
    "todo-tree.highlights.defaultHighlight": {
        "foreground": "#282a36",
        "background": "#ffb86c",
        "iconColour": "#ffb86c"
    },

    "errorLens.gutterIconsEnabled": true,
    "errorLens.messageMaxChars": 80,

    "[python]": {
        "editor.defaultFormatter": "charliermarsh.ruff",
        "editor.tabSize": 4
    },
    "[go]": {
        "editor.defaultFormatter": "golang.go",
        "editor.tabSize": 4,
        "editor.insertSpaces": false
    },
    "[rust]": {
        "editor.defaultFormatter": "rust-lang.rust-analyzer",
        "editor.tabSize": 4
    },
    "[markdown]": {
        "editor.wordWrap": "on",
        "editor.quickSuggestions": {
            "comments": "off",
            "strings": "off",
            "other": "off"
        }
    }
}
VSCODE_CONF
    success "VS Code settings configured with Dracula theme"
fi

# ---- VS Code essential extensions ----
if installed code; then
    info "Installing VS Code extensions..."
    VSCODE_EXTENSIONS=(
        # Theme
        "dracula-theme.theme-dracula"
        # Formatting & linting
        "esbenp.prettier-vscode"
        "dbaeumer.vscode-eslint"
        # Language support
        "bradlc.vscode-tailwindcss"
        "ms-python.python"
        "golang.go"
        "rust-lang.rust-analyzer"
        # Editor enhancements
        "formulahendry.auto-rename-tag"
        "christian-kohler.path-intellisense"
        "usernamehw.errorlens"
        "aaron-bond.better-comments"
        "streetsidesoftware.code-spell-checker"
        "christian-kohler.npm-intellisense"
        "naumovs.color-highlight"
        "mechatroner.rainbow-csv"
        # Git
        "eamodio.gitlens"
        "mhutchie.git-graph"
        # AI
        "github.copilot"
        # Productivity
        "gruntfuggly.todo-tree"
        "wix.vscode-import-cost"
        "ms-azuretools.vscode-docker"
        "mikestead.dotenv"
        "yzhang.markdown-all-in-one"
        "redhat.vscode-yaml"
        "tamasfe.even-better-toml"
    )
    for ext in "${VSCODE_EXTENSIONS[@]}"; do
        if code --list-extensions 2>/dev/null | grep -qi "$ext"; then
            warn "VS Code extension $ext already installed"
        else
            code --install-extension "$ext" 2>/dev/null || true
        fi
    done
    success "VS Code extensions installed"
fi

# ---- Fonts ----
info "Installing development fonts..."
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

install_nerd_font() {
    local font_name="$1"
    local display_name="$2"

    progress
    is_done "font:$font_name" && { warn "$display_name already completed (resume)"; return 0; }

    if ls "$FONT_DIR"/*"${font_name}"* &>/dev/null; then
        warn "$display_name already installed"
        mark_done "font:$font_name"
        return 0
    fi

    info "Installing $display_name..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font_name}.tar.xz" -o "$tmp_dir/${font_name}.tar.xz" >> "$LOG_FILE" 2>&1 || \
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font_name}.zip" -o "$tmp_dir/${font_name}.zip" >> "$LOG_FILE" 2>&1

        if [[ -f "$tmp_dir/${font_name}.tar.xz" ]]; then
            tar xJf "$tmp_dir/${font_name}.tar.xz" -C "$FONT_DIR" >> "$LOG_FILE" 2>&1
        elif [[ -f "$tmp_dir/${font_name}.zip" ]]; then
            unzip -o "$tmp_dir/${font_name}.zip" -d "$FONT_DIR" >> "$LOG_FILE" 2>&1
        fi
        rm -rf "$tmp_dir"
        success "$display_name installed"
        mark_done "font:$font_name"
    fi
}

install_nerd_font "JetBrainsMono" "JetBrains Mono Nerd Font"
install_nerd_font "Meslo" "MesloLGS Nerd Font"
install_nerd_font "FiraCode" "Fira Code Nerd Font"
install_nerd_font "Hack" "Hack Nerd Font"

# Inter font
if ! ls "$FONT_DIR"/*Inter* &>/dev/null; then
    info "Installing Inter font..."
    if [[ "$DRY_RUN" != "true" ]]; then
        tmp_dir=$(mktemp -d)
        curl -sL "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip" -o "$tmp_dir/inter.zip" >> "$LOG_FILE" 2>&1 || true
        if [[ -f "$tmp_dir/inter.zip" ]]; then
            unzip -o "$tmp_dir/inter.zip" -d "$tmp_dir/inter" >> "$LOG_FILE" 2>&1
            find "$tmp_dir/inter" \( -name "*.ttf" -o -name "*.otf" \) -print0 | xargs -0 -I{} cp {} "$FONT_DIR/" 2>/dev/null || true
        fi
        rm -rf "$tmp_dir"
    fi
else
    warn "Inter font already installed"
fi

# Rebuild font cache
if [[ "$DRY_RUN" != "true" ]]; then
    fc-cache -fv >> "$LOG_FILE" 2>&1 || true
    success "Font cache rebuilt"
fi
success "Development fonts installed"

# ---- shellcheck config ----
SHELLCHECK_RC="$HOME/.shellcheckrc"
if [[ -f "$SHELLCHECK_RC" ]]; then
    warn "shellcheck config already exists"
else
    info "Creating shellcheck configuration..."
    cat > "$SHELLCHECK_RC" <<'SHELLCHECK_CONF'
# Follow sourced files
external-sources=true

# Disable common false positives
disable=SC1091,SC2034
SHELLCHECK_CONF
    success "shellcheck configured"
fi

# ---- glow config ----
GLOW_CONFIG_DIR="$HOME/.config/glow"
GLOW_CONFIG="$GLOW_CONFIG_DIR/glow.yml"
if [[ -f "$GLOW_CONFIG" ]]; then
    warn "glow config already exists"
else
    info "Creating glow configuration..."
    mkdir -p "$GLOW_CONFIG_DIR"
    cat > "$GLOW_CONFIG" <<'GLOW_CONF'
# glow configuration
style: "dracula"
local: false
mouse: true
pager: true
width: 120
GLOW_CONF
    success "glow configured (Dracula style)"
fi

# ---- ngrok config ----
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
if [[ ! -d "$NGROK_CONFIG_DIR" ]]; then
    info "Creating ngrok config directory..."
    mkdir -p "$NGROK_CONFIG_DIR"
    cat > "$NGROK_CONFIG_DIR/ngrok.yml" <<'NGROK_CONF'
version: "3"
agent:
  metadata: "dev-machine"
NGROK_CONF
    success "ngrok config created"
else
    warn "ngrok config directory already exists"
fi

# ---- yt-dlp config ----
YT_DLP_CONFIG_DIR="$HOME/.config/yt-dlp"
YT_DLP_CONFIG="$YT_DLP_CONFIG_DIR/config"
if [[ -f "$YT_DLP_CONFIG" ]]; then
    warn "yt-dlp config already exists"
else
    info "Creating yt-dlp configuration..."
    mkdir -p "$YT_DLP_CONFIG_DIR"
    cat > "$YT_DLP_CONFIG" <<'YTDLP_CONF'
-f bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best
-o ~/Downloads/%(uploader)s/%(title)s.%(ext)s
--embed-metadata
--embed-thumbnail
--write-auto-subs
--sub-lang en
--downloader aria2c
--downloader-args aria2c:"-x 16 -s 16 -k 1M"
--no-overwrites
--restrict-filenames
YTDLP_CONF
    success "yt-dlp configured"
fi

# ---- difftastic config ----
# (difftastic git aliases are now set in the main git config section above)

# ---- caddy config ----
CADDY_CONFIG_DIR="$HOME/.config/caddy"
if [[ ! -d "$CADDY_CONFIG_DIR" ]]; then
    info "Creating Caddy config template..."
    mkdir -p "$CADDY_CONFIG_DIR"
    cat > "$CADDY_CONFIG_DIR/Caddyfile" <<'CADDY_CONF'
# Caddy development server template
# Usage: caddy run --config ~/.config/caddy/Caddyfile
CADDY_CONF
    success "Caddy config template created"
else
    warn "Caddy config directory already exists"
fi

# ---- act config ----
ACT_CONFIG="$HOME/.actrc"
if [[ -f "$ACT_CONFIG" ]]; then
    warn "act config already exists"
else
    info "Creating act configuration..."
    cat > "$ACT_CONFIG" <<'ACT_CONF'
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=catthehacker/ubuntu:act-20.04
--reuse
ACT_CONF
    success "act configured"
fi

# ---- miller config ----
MLR_CONFIG="$HOME/.mlrrc"
if [[ -f "$MLR_CONFIG" ]]; then
    warn "miller config already exists"
else
    info "Creating miller configuration..."
    cat > "$MLR_CONFIG" <<'MLR_CONF'
--opprint
--icsv
--skip-trivial-records
MLR_CONF
    success "miller configured"
fi

# ---- cmus config ----
CMUS_CONFIG_DIR="$HOME/.config/cmus"
CMUS_CONFIG="$CMUS_CONFIG_DIR/rc"
if [[ -f "$CMUS_CONFIG" ]]; then
    warn "cmus config already exists"
else
    info "Creating cmus config (Dracula-inspired colors)..."
    mkdir -p "$CMUS_CONFIG_DIR"
    cat > "$CMUS_CONFIG" <<'CMUS_CONF'
# cmus configuration — Dracula-inspired colors
# Apply inside cmus with:  :source ~/.config/cmus/rc

set replaygain=track
set replaygain_limit=true

set format_current= %a — %t
set format_playlist= %-20%a %t (%l)
set format_trackwin= %-20%a %t (%l)

# Dracula palette (256-color)
set color_bg=-1
set color_cmdline_bg=-1
set color_cmdline_fg=253
set color_info=141
set color_error=203
set color_separator=61
set color_statusline_bg=61
set color_statusline_fg=253
set color_titleline_bg=61
set color_titleline_fg=253
set color_win_bg=-1
set color_win_cur=141
set color_win_cur_sel_bg=61
set color_win_cur_sel_fg=253
set color_win_dir=117
set color_win_fg=253
set color_win_inactive_cur_sel_bg=61
set color_win_inactive_cur_sel_fg=253
set color_win_inactive_sel_bg=-1
set color_win_inactive_sel_fg=141
set color_win_sel_bg=61
set color_win_sel_fg=253
set color_win_title_bg=61
set color_win_title_fg=253
CMUS_CONF
    success "cmus configured (Dracula colors, replaygain)"
fi

# ---- w3m config ----
W3M_CONFIG_DIR="$HOME/.w3m"
W3M_CONFIG="$W3M_CONFIG_DIR/config"
if [[ -f "$W3M_CONFIG" ]]; then
    warn "w3m config already exists"
else
    info "Creating w3m config (UTF-8, cookies off, colors)..."
    mkdir -p "$W3M_CONFIG_DIR"
    cat > "$W3M_CONFIG" <<'W3M_CONF'
# w3m configuration — sensible privacy + display defaults
display_charset UTF-8
document_charset UTF-8
system_charset UTF-8
auto_detect 2

display_image 0
use_mouse 1
tabstop 8
show_lnum 0

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

follow_redirection 5
use_proxy 1

bookmark bookmark.html
keep_cache_in_memory 0
W3M_CONF
    success "w3m configured (UTF-8, cookies off)"
fi

# ---- asciinema config ----
ASCIINEMA_CONFIG_DIR="$HOME/.config/asciinema"
ASCIINEMA_CONFIG="$ASCIINEMA_CONFIG_DIR/config"
if [[ -f "$ASCIINEMA_CONFIG" ]]; then
    warn "asciinema config already exists"
else
    info "Creating asciinema configuration..."
    mkdir -p "$ASCIINEMA_CONFIG_DIR"
    cat > "$ASCIINEMA_CONFIG" <<'ASCIINEMA_CONF'
[record]
idle_time_limit = 2
stdin = no
command = /bin/zsh -l
overwrite = yes
ASCIINEMA_CONF
    success "asciinema configured"
fi

# ---- gh-dash config ----
GH_DASH_CONFIG_DIR="$HOME/.config/gh-dash"
GH_DASH_CONFIG="$GH_DASH_CONFIG_DIR/config.yml"
if [[ -f "$GH_DASH_CONFIG" ]]; then
    warn "gh-dash config already exists"
else
    if installed gh && gh extension list 2>/dev/null | grep -q "gh-dash"; then
        info "Creating gh-dash configuration..."
        mkdir -p "$GH_DASH_CONFIG_DIR"
        cat > "$GH_DASH_CONFIG" <<'GHDASH_CONF'
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
        success "gh-dash configured"
    fi
fi

# ---- stern config ----
STERN_CONFIG="$HOME/.config/stern/config.yaml"
if [[ -f "$STERN_CONFIG" ]]; then
    warn "stern config already exists"
else
    info "Creating stern configuration..."
    mkdir -p "$(dirname "$STERN_CONFIG")"
    cat > "$STERN_CONFIG" <<'STERN_CONF'
template: '{{color .PodColor .PodName}} {{color .ContainerColor .ContainerName}} {{.Message}}{{"\n"}}'
tail: 50
timestamps: short
since: 5m
STERN_CONF
    success "stern configured"
fi

# ---- SSH config ----
SSH_CONFIG="$HOME/.ssh/config"
if [[ -f "$SSH_CONFIG" ]]; then
    warn "SSH config already exists"
else
    info "Creating SSH configuration..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cat > "$SSH_CONFIG" <<'SSH_CONF'
# =============================================================================
# SSH Configuration
# =============================================================================

Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600

    ServerAliveInterval 60
    ServerAliveCountMax 3

    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519

    Compression yes

    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    PubkeyAcceptedAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
SSH_CONF
    mkdir -p "$HOME/.ssh/sockets"
    chmod 600 "$SSH_CONFIG"
    success "SSH configured (multiplexing, keep-alive, strong algorithms)"
fi

# Generate SSH key if none exists
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    info "No SSH key found. To generate one, run:"
    echo "  ssh-keygen -t ed25519 -C \"your_email@example.com\""
else
    warn "SSH key already exists at ~/.ssh/id_ed25519"
fi

# ---- Global .gitignore ----
GLOBAL_GITIGNORE="$HOME/.gitignore_global"
if [[ -f "$GLOBAL_GITIGNORE" ]]; then
    warn "Global .gitignore already exists"
else
    info "Creating global .gitignore..."
    cat > "$GLOBAL_GITIGNORE" <<'GITIGNORE_GLOBAL'
# =============================================================================
# Global .gitignore
# =============================================================================

# Linux
*~
.fuse_hidden*
.Trash-*
.nfs*

# macOS
.DS_Store
._*

# Editors
.vscode/settings.json
.vscode/launch.json
*.code-workspace
.idea/
*.iml
*.swp
*.swo
*~

# Environment & Secrets
.env
.env.local
.env.*.local
*.pem
*.key
credentials.json
secrets.yaml

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
.pnpm-debug.log*

# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/

# Build
dist/
build/
*.o
*.so
coverage/

# System
Thumbs.db
Desktop.ini
GITIGNORE_GLOBAL
    git config --global core.excludesfile "$GLOBAL_GITIGNORE"
    success "Global .gitignore created and registered"
fi

# ---- .npmrc ----
NPMRC="$HOME/.npmrc"
if [[ -f "$NPMRC" ]]; then
    warn ".npmrc already exists"
else
    info "Creating .npmrc..."
    cat > "$NPMRC" <<'NPMRC_CONF'
save-exact=true
init-author-name=
init-license=MIT
init-version=0.1.0
update-notifier=false
fund=false
audit-level=moderate
prefer-offline=true
engine-strict=true
NPMRC_CONF
    success ".npmrc configured"
fi

# ---- .editorconfig ----
EDITORCONFIG="$HOME/.editorconfig"
if [[ -f "$EDITORCONFIG" ]]; then
    warn ".editorconfig already exists"
else
    info "Creating global .editorconfig..."
    cat > "$EDITORCONFIG" <<'EDITORCONFIG_CONF'
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
    success ".editorconfig created"
fi

# ---- .prettierrc ----
PRETTIERRC="$HOME/.prettierrc"
if [[ -f "$PRETTIERRC" ]]; then
    warn ".prettierrc already exists"
else
    info "Creating global .prettierrc..."
    cat > "$PRETTIERRC" <<'PRETTIER_CONF'
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
    success ".prettierrc created"
fi

# ---- .curlrc ----
# NOTE: This is created late in the script to avoid affecting earlier curl calls.
# If moving this section, ensure CURL_HOME="" is exported before any script curls.
CURLRC="$HOME/.curlrc"
if [[ -f "$CURLRC" ]]; then
    warn ".curlrc already exists"
else
    info "Creating .curlrc..."
    cat > "$CURLRC" <<'CURLRC_CONF'
--location
--show-error
--fail
--max-time 30
--connect-timeout 10
--retry 3
--retry-delay 2
--compressed
--user-agent "curl/dev"
CURLRC_CONF
    success ".curlrc configured"
fi

# ---- Docker daemon config ----
DOCKER_CONFIG_DIR="/etc/docker"
DOCKER_DAEMON="$DOCKER_CONFIG_DIR/daemon.json"
if [[ -f "$DOCKER_DAEMON" ]]; then
    warn "Docker daemon.json already exists"
else
    info "Creating Docker daemon configuration..."
    sudo mkdir -p "$DOCKER_CONFIG_DIR"
    sudo tee "$DOCKER_DAEMON" > /dev/null <<'DOCKER_CONF'
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
    success "Docker configured (BuildKit, log rotation)"
fi

# ---- Docker buildx as default builder ----
if installed docker; then
    if docker buildx version &>/dev/null; then
        info "Setting Docker buildx as default builder..."
        docker buildx install 2>/dev/null || true
        success "Docker buildx set as default builder (multi-platform builds enabled)"
    fi
fi

# ---- ~/.hushlogin ----
if [[ -f "$HOME/.hushlogin" ]]; then
    warn "\$HOME/.hushlogin already exists"
else
    touch "$HOME/.hushlogin"
    success "\$HOME/.hushlogin created"
fi

# ---- ~/.zprofile ----
ZPROFILE="$HOME/.zprofile"
if [[ -f "$ZPROFILE" ]]; then
    warn "\$HOME/.zprofile already exists"
else
    info "Creating \$HOME/.zprofile..."
    cat > "$ZPROFILE" <<'ZPROFILE_CONF'
# =============================================================================
# ~/.zprofile — login shell configuration
# =============================================================================
# This runs ONCE on login (not on every subshell like .zshrc).
# Put PATH modifications and env vars here that only need to be set once.

# Homebrew on Linux (Linuxbrew)
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi

# Default editor
export EDITOR="code --wait"
export VISUAL="code --wait"

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
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Personal scripts
export PATH="$HOME/Scripts/bin:$PATH"

# ripgrep config
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# GPG tty (required for commit signing)
export GPG_TTY=$(tty 2>/dev/null || echo /dev/null)

# mise (version manager — Node, Python, Go, etc.)
# Activated here (not just .zshrc) so non-interactive login shells
# (e.g. Claude Code, IDE terminals) also get managed tool shims.
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# direnv
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Deduplicate PATH
typeset -U PATH path
ZPROFILE_CONF
    success "\$HOME/.zprofile created (editor, pager, XDG, Go, Rust, bun, pnpm, mise, direnv)"
fi

# ---- ~/.zshenv (every zsh invocation — interactive or not) ----
ZSHENV="$HOME/.zshenv"
if [[ -f "$ZSHENV" ]]; then
    warn "$HOME/.zshenv already exists"
else
    info "Creating ~/.zshenv..."
    cat > "$ZSHENV" <<'ZSHENV_CONF'
# mise (version manager) — sourced by every zsh invocation (interactive,
# non-interactive, login or not). This ensures tools like node/npx are
# available in Claude Code, IDE terminals, and scripted shells.
command -v mise &>/dev/null && eval "$(mise activate zsh)"
ZSHENV_CONF
    success "$HOME/.zshenv created (mise activation for all shell types)"
fi

# ---- ~/.vimrc ----
VIMRC="$HOME/.vimrc"
if [[ -f "$VIMRC" ]]; then
    warn "\$HOME/.vimrc already exists"
else
    info "Creating basic \$HOME/.vimrc..."
    cat > "$VIMRC" <<'VIM_CONF'
set nocompatible
syntax on
filetype plugin indent on
set number relativenumber ruler showcmd showmode cursorline
set scrolloff=8 sidescrolloff=8 signcolumn=yes colorcolumn=100
set laststatus=2 wildmenu wildmode=longest:full,full
set tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent smartindent
set incsearch hlsearch ignorecase smartcase
set backspace=indent,eol,start clipboard=unnamedplus mouse=a
set hidden autoread encoding=utf-8 noerrorbells novisualbell
set nobackup nowritebackup noswapfile undofile undodir=~/.vim/undodir
let mapleader = " "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>h :nohlsearch<CR>
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
set termguicolors background=dark
highlight Normal       guifg=#f8f8f2 guibg=#282a36
highlight CursorLine   guibg=#44475a
highlight LineNr       guifg=#6272a4
highlight Comment      guifg=#6272a4
highlight Visual       guibg=#44475a
highlight Search       guifg=#282a36 guibg=#f1fa8c
if !isdirectory($HOME . "/.vim/undodir")
    call mkdir($HOME . "/.vim/undodir", "p")
endif
VIM_CONF
    mkdir -p "$HOME/.vim/undodir"
    success "\$HOME/.vimrc created"
fi

# ---- ~/.nanorc ----
NANORC="$HOME/.nanorc"
if [[ -f "$NANORC" ]]; then
    warn "\$HOME/.nanorc already exists"
else
    info "Creating \$HOME/.nanorc..."
    cat > "$NANORC" <<'NANO_CONF'
set linenumbers
set constantshow
set smooth
set autoindent
set tabsize 2
set tabstospaces
set mouse
set nowrap
set matchbrackets "(<[{)>]}"
set smarthome
set softwrap
set suspend
include "/usr/share/nano/*.nanorc"
NANO_CONF
    success "\$HOME/.nanorc created"
fi

# ---- bat extended config ----
if installed bat; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null)"
    BAT_CONFIG="$BAT_CONFIG_DIR/config"
    if [[ -n "$BAT_CONFIG_DIR" ]] && [[ -f "$BAT_CONFIG" ]]; then
        if ! grep -q "map-syntax" "$BAT_CONFIG" 2>/dev/null; then
            info "Adding bat file type mappings..."
            cat >> "$BAT_CONFIG" <<'BAT_MAPPINGS'

--map-syntax "*.env:dotenv"
--map-syntax "*.env.*:dotenv"
--map-syntax "*.Dockerfile:Dockerfile"
--map-syntax "Dockerfile.*:Dockerfile"
--map-syntax "docker-compose*.yml:YAML"
--map-syntax "*.conf:INI"
--map-syntax "Brewfile:Ruby"
--map-syntax "*.mdx:Markdown"
--map-syntax ".prettierrc:JSON"
--map-syntax ".eslintrc:JSON"
--map-syntax "tsconfig*.json:JSON"

--style="numbers,changes,header,grid"
--italic-text=always
BAT_MAPPINGS
            success "bat file type mappings added"
        else
            warn "bat file type mappings already configured"
        fi
    fi
fi

# ---- ripgrep config ----
RIPGREPRC="$HOME/.ripgreprc"
if [[ -f "$RIPGREPRC" ]]; then
    warn "\$HOME/.ripgreprc already exists"
else
    info "Creating ripgrep configuration..."
    cat > "$RIPGREPRC" <<'RG_CONF'
--smart-case
--hidden
--follow
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
--max-columns=200
--max-columns-preview
--type-add=web:*.{html,css,scss,js,jsx,ts,tsx,vue,svelte}
--type-add=config:*.{json,yaml,yml,toml,ini,conf}
--type-add=doc:*.{md,mdx,txt,rst}
--type-add=style:*.{css,scss,sass,less}
RG_CONF
    success "\$HOME/.ripgreprc configured"
fi

# ---- fd ignore ----
FDIGNORE="$HOME/.fdignore"
if [[ -f "$FDIGNORE" ]]; then
    warn "\$HOME/.fdignore already exists"
else
    info "Creating fd ignore patterns..."
    cat > "$FDIGNORE" <<'FD_CONF'
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
.Trash/
FD_CONF
    success "\$HOME/.fdignore created"
fi

# ---- btop Dracula ----
BTOP_CONFIG_DIR="$HOME/.config/btop"
BTOP_CONFIG="$BTOP_CONFIG_DIR/btop.conf"
if [[ -f "$BTOP_CONFIG" ]]; then
    warn "btop config already exists"
else
    info "Creating btop configuration..."
    mkdir -p "$BTOP_CONFIG_DIR/themes"
    cat > "$BTOP_CONFIG" <<'BTOP_CONF'
color_theme = "dracula"
update_ms = 1000
proc_sorting = "cpu lazy"
shown_boxes = "cpu mem net proc"
proc_tree = true
mem_graphs = true
truecolor = true
rounded_corners = true
BTOP_CONF
    cat > "$BTOP_CONFIG_DIR/themes/dracula.theme" <<'BTOP_DRACULA'
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
fi

# ---- lazydocker config ----
LAZYDOCKER_CONFIG_DIR="$HOME/.config/lazydocker"
LAZYDOCKER_CONFIG="$LAZYDOCKER_CONFIG_DIR/config.yml"
if [[ -f "$LAZYDOCKER_CONFIG" ]]; then
    warn "lazydocker config already exists"
else
    info "Creating lazydocker configuration..."
    mkdir -p "$LAZYDOCKER_CONFIG_DIR"
    cat > "$LAZYDOCKER_CONFIG" <<'LAZYDOCKER_CONF'
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
fi

# ---- Git commit template ----
GIT_COMMIT_TEMPLATE="$HOME/.gitmessage"
if [[ -f "$GIT_COMMIT_TEMPLATE" ]]; then
    warn "Git commit template already exists"
else
    info "Creating git commit template..."
    cat > "$GIT_COMMIT_TEMPLATE" <<'GIT_TEMPLATE'
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
    success "Git commit template created"
fi

# ---- Global git hooks ----
GIT_HOOKS_DIR="$HOME/.config/git/hooks"
if [[ -d "$GIT_HOOKS_DIR" ]]; then
    warn "Global git hooks directory already exists"
else
    info "Creating global git hooks..."
    mkdir -p "$GIT_HOOKS_DIR"
    cat > "$GIT_HOOKS_DIR/pre-commit" <<'HOOK_PRECOMMIT'
#!/usr/bin/env bash
# Global pre-commit hook

# Check for debug statements
if git diff --cached --name-only | xargs grep -l 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null; then
    echo "WARNING: Debug statements found in staged files"
    git diff --cached --name-only | xargs grep -n 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null
    echo "Remove them or commit with --no-verify to bypass."
    exit 1
fi

# Check for large files (> 5MB)
large_files=$(git diff --cached --name-only --diff-filter=d | while read f; do
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    if [[ "$size" -gt 5242880 ]]; then
        echo "  $f ($(( size / 1048576 ))MB)"
    fi
done)
if [[ -n "$large_files" ]]; then
    echo "WARNING: Large files detected (>5MB):"
    echo "$large_files"
    exit 1
fi

# Check for merge conflict markers
if git diff --cached --name-only | xargs grep -l '<<<<<<<\|=======\|>>>>>>>' 2>/dev/null; then
    echo "ERROR: Merge conflict markers found."
    exit 1
fi

exit 0
HOOK_PRECOMMIT
    chmod +x "$GIT_HOOKS_DIR/pre-commit"
    git config --global core.hooksPath "$GIT_HOOKS_DIR"
    success "Global git hooks created"
fi

# ---- AWS config ----
AWS_CONFIG="$HOME/.aws/config"
if [[ -f "$AWS_CONFIG" ]]; then
    warn "AWS config already exists"
else
    info "Creating AWS CLI configuration..."
    mkdir -p "$HOME/.aws"
    chmod 700 "$HOME/.aws"
    cat > "$AWS_CONFIG" <<'AWS_CONF'
[default]
region = us-east-1
output = json
cli_pager = bat --style=plain
cli_auto_prompt = on-partial
retry_mode = adaptive
max_attempts = 3
AWS_CONF
    chmod 600 "$AWS_CONFIG"
    success "AWS CLI configured"
fi

# ---- GitHub CLI config ----
GH_CONFIG_DIR="$HOME/.config/gh"
GH_CONFIG="$GH_CONFIG_DIR/config.yml"
if [[ -f "$GH_CONFIG" ]]; then
    warn "GitHub CLI config already exists"
else
    info "Creating GitHub CLI configuration..."
    mkdir -p "$GH_CONFIG_DIR"
    cat > "$GH_CONFIG" <<'GH_CONF'
git_protocol: ssh
editor: code --wait
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
    success "GitHub CLI configured"
fi

# ---- pip config ----
PIP_CONFIG_DIR="$HOME/.config/pip"
PIP_CONFIG="$PIP_CONFIG_DIR/pip.conf"
if [[ -f "$PIP_CONFIG" ]]; then
    warn "pip config already exists"
else
    info "Creating pip configuration..."
    mkdir -p "$PIP_CONFIG_DIR"
    cat > "$PIP_CONFIG" <<'PIP_CONF'
[global]
require-virtualenv = true
disable-pip-version-check = true
no-input = true
timeout = 30

[install]
compile = true
PIP_CONF
    success "pip configured"
fi

# ---- gemrc ----
GEMRC="$HOME/.gemrc"
if [[ -f "$GEMRC" ]]; then
    warn "\$HOME/.gemrc already exists"
else
    echo "gem: --no-document" > "$GEMRC"
    success "\$HOME/.gemrc created"
fi

# ---- pgcli config ----
PGCLI_CONFIG_DIR="$HOME/.config/pgcli"
PGCLI_CONFIG="$PGCLI_CONFIG_DIR/config"
if [[ -f "$PGCLI_CONFIG" ]]; then
    warn "pgcli config already exists"
else
    info "Creating pgcli configuration..."
    mkdir -p "$PGCLI_CONFIG_DIR"
    cat > "$PGCLI_CONFIG" <<'PGCLI_CONF'
[main]
multi_line = True
auto_expand = True
expand = False
pager = bat --style=plain --paging=always
prompt = '\u@\h:\d> '
log_file = ~/.config/pgcli/log
history_file = ~/.config/pgcli/history
destructive_warning = all
syntax_style = monokai
keyword_casing = upper
smart_completion = True
PGCLI_CONF
    success "pgcli configured"
fi

# ---- mycli config ----
MYCLIRC="$HOME/.myclirc"
if [[ -f "$MYCLIRC" ]]; then
    warn "\$HOME/.myclirc already exists"
else
    info "Creating mycli configuration..."
    cat > "$MYCLIRC" <<'MYCLI_CONF'
[main]
multi_line = True
auto_expand = True
pager = bat --style=plain --paging=always
prompt = '\u@\h:\d> '
syntax_style = monokai
keyword_casing = upper
smart_completion = True
destructive_warning = True
wider_completion_menu = True
MYCLI_CONF
    success "\$HOME/.myclirc configured"
fi

# ---- yazi config ----
YAZI_CONFIG_DIR="$HOME/.config/yazi"
YAZI_CONFIG="$YAZI_CONFIG_DIR/yazi.toml"
if [[ -f "$YAZI_CONFIG" ]]; then
    warn "yazi config already exists"
else
    info "Creating yazi configuration..."
    mkdir -p "$YAZI_CONFIG_DIR"
    cat > "$YAZI_CONFIG" <<'YAZI_CONF'
[manager]
show_hidden = true
sort_dir_first = true
linemode = "size"

[preview]
max_width = 1000
max_height = 1000

[opener]
edit = [
    { run = 'code "$@"', desc = "Open in VS Code", block = true, for = "unix" },
]
YAZI_CONF

    cat > "$YAZI_CONFIG_DIR/theme.toml" <<'YAZI_THEME'
[manager]
cwd = { fg = "#bd93f9" }

[status]
separator_open = ""
separator_close = ""
separator_style = { fg = "#44475a", bg = "#44475a" }

[filetype]
rules = [
    { mime = "image/*", fg = "#ff79c6" },
    { mime = "video/*", fg = "#ffb86c" },
    { mime = "audio/*", fg = "#8be9fd" },
    { name = "*.md", fg = "#50fa7b" },
    { name = "*.json", fg = "#f1fa8c" },
    { name = "*.ts", fg = "#8be9fd" },
    { name = "*.tsx", fg = "#8be9fd" },
    { name = "*.js", fg = "#f1fa8c" },
    { name = "*.py", fg = "#50fa7b" },
    { name = "*.rs", fg = "#ffb86c" },
    { name = "*.go", fg = "#8be9fd" },
]
YAZI_THEME
    success "yazi configured"
fi

# ---- just global justfile ----
JUSTFILE_GLOBAL="$HOME/.justfile"
if [[ -f "$JUSTFILE_GLOBAL" ]]; then
    warn "Global justfile already exists"
else
    info "Creating global justfile..."
    cat > "$JUSTFILE_GLOBAL" <<'JUSTFILE_CONF'
# =============================================================================
# Global Justfile — available from any directory via: just --justfile ~/.justfile
# =============================================================================
# Tip: alias gj="just --justfile ~/.justfile --working-directory ."

# List all recipes
default:
    @just --justfile {{justfile()}} --list

# ── System ───────────────────────────────────────────────────────────────────

# Update everything (apt/dnf, npm, pip, etc.)
update:
    topgrade

# Show system info
info:
    fastfetch

# Flush DNS cache
flush-dns:
    sudo systemd-resolve --flush-caches 2>/dev/null || sudo resolvectl flush-caches 2>/dev/null
    @echo "DNS cache flushed"

# Show listening ports
ports:
    ss -tlnp | tail -n +2 | sort -t: -k2 -n

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
    @cat /proc/sys/kernel/random/uuid

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
    @hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"

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
fi

# ---- mise config ----
MISE_CONFIG="$HOME/.config/mise/config.toml"
if [[ -f "$MISE_CONFIG" ]]; then
    warn "mise global config already exists"
else
    info "Creating mise configuration..."
    mkdir -p "$HOME/.config/mise"
    cat > "$MISE_CONFIG" <<'MISE_CONF'
# mise global tool versions
# Docs: https://mise.jdx.dev/
# These are defaults — per-project .mise.toml takes precedence

[tools]
node = "lts"
python = "3.12"
# go = "latest"      # installed via pkg manager
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
fi

# ---- topgrade config ----
TOPGRADE_CONFIG="$HOME/.config/topgrade.toml"
if [[ -f "$TOPGRADE_CONFIG" ]]; then
    warn "topgrade config already exists"
else
    info "Creating topgrade configuration..."
    mkdir -p "$HOME/.config"
    cat > "$TOPGRADE_CONFIG" <<'TOPGRADE_CONF'
cleanup = true

[linux]
yay_arguments = "--nodiffmenu"
TOPGRADE_CONF
    success "topgrade configured"
fi

# ---- fastfetch config ----
FASTFETCH_CONFIG="$HOME/.config/fastfetch/config.jsonc"
if [[ -f "$FASTFETCH_CONFIG" ]]; then
    warn "fastfetch config already exists"
else
    info "Creating fastfetch configuration..."
    mkdir -p "$HOME/.config/fastfetch"
    cat > "$FASTFETCH_CONFIG" <<'FASTFETCH_CONF'
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
            "charElapsed": "█",
            "charTotal": "░",
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
fi

# ---- direnv config ----
DIRENV_CONFIG_DIR="$HOME/.config/direnv"
DIRENV_CONFIG="$DIRENV_CONFIG_DIR/direnv.toml"
if [[ -f "$DIRENV_CONFIG" ]]; then
    warn "direnv config already exists"
else
    info "Creating direnv configuration..."
    mkdir -p "$DIRENV_CONFIG_DIR"
    cat > "$DIRENV_CONFIG" <<'DIRENV_CONF'
[global]
hide_env_diff = true
warn_timeout = "10s"
load_dotenv = true

[whitelist]
prefix = [ "~/Code" ]
DIRENV_CONF
    success "direnv configured"
fi

# ---- VS Code keybindings (Linux uses ctrl instead of cmd) ----
VSCODE_KEYBINDINGS="$HOME/.config/Code/User/keybindings.json"
if [[ -f "$VSCODE_KEYBINDINGS" ]]; then
    warn "VS Code keybindings already exist"
else
    info "Creating VS Code keybindings..."
    mkdir -p "$HOME/.config/Code/User"
    cat > "$VSCODE_KEYBINDINGS" <<'VSCODE_KEYS'
[
    { "key": "ctrl+`", "command": "workbench.action.terminal.toggleTerminal" },
    { "key": "ctrl+shift+`", "command": "workbench.action.terminal.new" },
    { "key": "ctrl+\\", "command": "workbench.action.splitEditor" },
    { "key": "ctrl+1", "command": "workbench.action.focusFirstEditorGroup" },
    { "key": "ctrl+2", "command": "workbench.action.focusSecondEditorGroup" },
    { "key": "ctrl+3", "command": "workbench.action.focusThirdEditorGroup" },
    { "key": "ctrl+p", "command": "workbench.action.quickOpen" },
    { "key": "ctrl+shift+o", "command": "workbench.action.gotoSymbol" },
    { "key": "ctrl+t", "command": "workbench.action.showAllSymbols" },
    { "key": "ctrl+b", "command": "workbench.action.toggleSidebarVisibility" },
    { "key": "ctrl+shift+m", "command": "editor.action.toggleMinimap" },
    { "key": "ctrl+shift+[", "command": "editor.fold" },
    { "key": "ctrl+shift+]", "command": "editor.unfold" },
    { "key": "alt+up", "command": "editor.action.moveLinesUpAction" },
    { "key": "alt+down", "command": "editor.action.moveLinesDownAction" },
    { "key": "ctrl+shift+d", "command": "editor.action.copyLinesDownAction" },
    { "key": "ctrl+shift+k", "command": "editor.action.deleteLines" },
    { "key": "ctrl+d", "command": "editor.action.addSelectionToNextFindMatch" },
    { "key": "ctrl+shift+l", "command": "editor.action.selectHighlights" },
    { "key": "ctrl+shift+f", "command": "editor.action.formatDocument" },
    { "key": "f2", "command": "editor.action.rename" },
    { "key": "ctrl+.", "command": "editor.action.quickFix" },
    { "key": "ctrl+w", "command": "workbench.action.closeActiveEditor" },
    { "key": "ctrl+shift+t", "command": "workbench.action.reopenClosedEditor" }
]
VSCODE_KEYS
    success "VS Code keybindings created"
fi

# ---- Espanso config ----
ESPANSO_CONFIG_DIR="$HOME/.config/espanso/match"
ESPANSO_CONFIG="$ESPANSO_CONFIG_DIR/base.yml"
if [[ -f "$ESPANSO_CONFIG" ]]; then
    warn "Espanso config already exists"
else
    info "Creating Espanso configuration..."
    mkdir -p "$ESPANSO_CONFIG_DIR"
    cat > "$ESPANSO_CONFIG" <<'ESPANSO_CONF'
# Espanso text expansion config
# Docs: https://espanso.org/docs/

matches:
  # -- Date & Time -------------------------------------------------------
  - trigger: ";date"
    replace: "{{today}}"
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  - trigger: ";time"
    replace: "{{now}}"
    vars:
      - name: now
        type: date
        params:
          format: "%H:%M"

  - trigger: ";datetime"
    replace: "{{dt}}"
    vars:
      - name: dt
        type: date
        params:
          format: "%Y-%m-%d %H:%M"

  - trigger: ";iso"
    replace: "{{iso}}"
    vars:
      - name: iso
        type: date
        params:
          format: "%Y-%m-%dT%H:%M:%S%z"

  # -- Dev Shortcuts -----------------------------------------------------
  - trigger: ";shrug"
    replace: "¯\\_(ツ)_/¯"

  - trigger: ";arrow"
    replace: "→"

  - trigger: ";check"
    replace: "✓"

  - trigger: ";cross"
    replace: "✗"

  - trigger: ";bullet"
    replace: "•"

  # -- Code Snippets -----------------------------------------------------
  - trigger: ";clog"
    replace: "console.log('$|$');"

  - trigger: ";todo"
    replace: "// TODO: "

  - trigger: ";fixme"
    replace: "// FIXME: "

  # -- Markdown ----------------------------------------------------------
  - trigger: ";cb"
    replace: "```\n$|$\n```"

  - trigger: ";cbt"
    replace: "```typescript\n$|$\n```"

  - trigger: ";cbp"
    replace: "```python\n$|$\n```"

  - trigger: ";cbb"
    replace: "```bash\n$|$\n```"

  - trigger: ";table"
    replace: "| Column 1 | Column 2 | Column 3 |\n|----------|----------|----------|\n| | | |"

  # -- Git ---------------------------------------------------------------
  - trigger: ";gcm"
    replace: "git commit -m \""

  - trigger: ";gca"
    replace: "git add -A && git commit -m \""

  - trigger: ";gpush"
    replace: "git push origin $(git branch --show-current)"

  # -- UUID & Random ----------------------------------------------------------
  - trigger: ";uuid"
    replace: "{{uuid}}"
    vars:
      - name: uuid
        type: shell
        params:
          cmd: "uuidgen | tr '[:upper:]' '[:lower:]'"

  - trigger: ";lorem"
    replace: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."

  - trigger: ";loremshort"
    replace: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

  # -- Common Regex Patterns --------------------------------------------------
  - trigger: ";rxemail"
    replace: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

  - trigger: ";rxurl"
    replace: "https?://[\\w\\-]+(\\.[\\w\\-]+)+[\\w\\-.,@?^=%&:/~+#]*"

  - trigger: ";rxip"
    replace: "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b"

  - trigger: ";rxphone"
    replace: "^\\+?[1-9]\\d{1,14}$"

  # -- Templates --------------------------------------------------------------
  - trigger: ";prdesc"
    replace: |
      ## Summary
      <!-- What does this PR do? -->

      ## Changes
      -

      ## Test plan
      - [ ] Unit tests pass
      - [ ] Manual testing done
      - [ ] No regressions

      ## Screenshots
      <!-- If applicable -->

  - trigger: ";meeting"
    replace: |
      ## Meeting Notes — {{today}}
      **Attendees:**
      **Agenda:**
      1.

      **Action Items:**
      - [ ]

      **Decisions:**
      -
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  - trigger: ";bug"
    replace: |
      ## Bug Report
      **Environment:**
      **Steps to Reproduce:**
      1.

      **Expected:**
      **Actual:**
      **Screenshots:**

  # -- Arrows & Symbols -------------------------------------------------------
  - trigger: ";rarr"
    replace: "→"

  - trigger: ";larr"
    replace: "←"

  - trigger: ";uarr"
    replace: "↑"

  - trigger: ";darr"
    replace: "↓"

  - trigger: ";mdash"
    replace: "—"

  - trigger: ";deg"
    replace: "°"

  - trigger: ";tm"
    replace: "™"

  - trigger: ";copy"
    replace: "©"
ESPANSO_CONF
    success "Espanso configured (dates, dev shortcuts, Markdown, git, templates, regex, symbols)"
fi

fi  # configs

# =============================================================================
# CLAUDE CODE CONFIGURATION
# =============================================================================
if should_run "configs"; then
banner "Claude Code Configuration"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    warn "Claude Code settings.json already exists"
else
    info "Creating Claude Code global settings..."
    mkdir -p "$HOME/.claude"
    cat > "$CLAUDE_SETTINGS" <<'CLAUDE_SETTINGS_CONF'
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(npm install *)",
      "Bash(npm test *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(pnpm *)",
      "Bash(bun *)",
      "Bash(node *)",
      "Bash(tsx *)",
      "Bash(ts-node *)",
      "Bash(git *)",
      "Bash(git-*)",
      "Bash(gh *)",
      "Bash(aws *)",
      "Bash(cdk *)",
      "Bash(sam *)",
      "Bash(docker *)",
      "Bash(docker-compose *)",
      "Bash(docker compose *)",
      "Bash(kubectl *)",
      "Bash(k9s *)",
      "Bash(stern *)",
      "Bash(python3 *)",
      "Bash(pip *)",
      "Bash(uv *)",
      "Bash(cargo *)",
      "Bash(go *)",
      "Bash(just *)",
      "Bash(make *)",
      "Bash(cat *)",
      "Bash(bat *)",
      "Bash(ls *)",
      "Bash(eza *)",
      "Bash(find *)",
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
      "Bash(awk *)",
      "Bash(sed *)",
      "Bash(sd *)",
      "Bash(jq *)",
      "Bash(yq *)",
      "Bash(fx *)",
      "Bash(mlr *)",
      "Bash(csvlook *)",
      "Bash(curl *)",
      "Bash(xh *)",
      "Bash(wget *)",
      "Bash(which *)",
      "Bash(type *)",
      "Bash(echo *)",
      "Bash(printf *)",
      "Bash(env *)",
      "Bash(export *)",
      "Bash(cd *)",
      "Bash(mkdir -p *)",
      "Bash(touch *)",
      "Bash(cp *)",
      "Bash(mv *)",
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
      "Bash(act *)",
      "Bash(tofu *)",
      "Bash(tflint *)",
      "Bash(infracost *)",
      "Bash(trivy *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)",
      "Bash(snyk *)",
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
      "Bash(dbmate *)",
      "Bash(commitizen *)",
      "Bash(commitlint *)",
      "Bash(typos *)",
      "Bash(ast-grep *)",
      "Bash(git-cliff *)",
      "Bash(hurl *)",
      "Bash(jnv *)",
      "Bash(watchexec *)",
      "Bash(curlie *)",
      "Bash(lazysql *)",
      "Bash(trippy *)",
      "Bash(nushell *)",
      "Bash(nu *)",
      "Bash(oxipng *)",
      "Bash(jpegoptim *)",
      "Bash(7z *)",
      "Bash(mpv *)",
      "Bash(newsboat *)",
      "Bash(zellij *)",
      "Bash(gum *)",
      "Read",
      "Edit",
      "Write",
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
  }
}
CLAUDE_SETTINGS_CONF
    success "Claude Code settings.json created"
fi

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    warn "Claude Code global CLAUDE.md already exists"
else
    info "Creating Claude Code global CLAUDE.md..."
    mkdir -p "$HOME/.claude"
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
- Editor: VS Code (Dracula theme, JetBrains Mono)
- Terminal: Ghostty (Dracula theme)
- Package managers: pnpm (preferred), npm, bun
- Python: uv for packages (not pip), ruff for linting (not flake8/black)
- JS/TS runtimes: Node (via mise), Bun, Deno
- Version manager: mise (Node, Python, Go, Ruby — all in one)
- Container runtime: OrbStack (macOS — provides docker + kubectl), Docker Engine (Linux)
- Task runner: just (prefer over make for project-level tasks)
- Shell note: `bat` is aliased to `cat`; use `/bin/cat` only inside heredoc subshells where bat breaks syntax
- Dotfiles: chezmoi
- Launcher: Raycast
- API client: Postman
- Database GUI: TablePlus
- Proxy/debugger: mitmproxy
- Tunneling: ngrok

## Available CLI Tools (use these instead of manual approaches)
- **Search**: `rg` (ripgrep) for content, `fd` for files, `fzf` for interactive
- **Data**: `jq` for JSON, `yq` for YAML, `mlr` for CSV, `fx`/`jnv` for interactive JSON, `csvkit` for CSV
- **Git**: `lazygit` for interactive UI, `delta` for diffs, `difft` for syntax-aware diffs, `git-cliff` for changelogs, `git-absorb` for auto fixup commits, `git-lfs` for large files
- **Docker**: `lazydocker` for UI, `dive` to inspect layers, `hadolint` for Dockerfile linting
- **Testing**: `hyperfine` to benchmark, `oha` for load testing, `hurl` for HTTP test files, `act` for local GitHub Actions
- **Code quality**: `typos` for spell checking, `ast-grep` for structural search/replace, `shellcheck`/`shfmt` for shell
- **Security**: `trivy` to scan containers/IaC, `gitleaks` for secrets, `semgrep` for static analysis, `snyk` for dependency scanning, `detect-secrets` for pre-commit secret detection, `sops` for secrets encryption
- **IaC**: `tofu` (Terraform), `tflint` for linting, `infracost` for cost estimation, `cfn-lint` for CloudFormation, `aws-sam-cli` for SAM
- **HTTP**: `xh` for colorized requests, `curlie` for curl with httpie output, `grpcurl` for gRPC
- **Network**: `trip` (trippy) for traceroute TUI, `sudo mtr` (requires root, lives in sbin), `bandwhich` for bandwidth, `nmap` for scanning, `mkcert` for local TLS certs
- **Docs**: `d2` for diagrams, `pandoc` for conversion, `glow` for Markdown preview
- **Database**: `pgcli`/`mycli` for auto-completing SQL, `lazysql` for TUI, `sq` for cross-database queries, `dbmate` for migrations
- **File management**: `yazi` for TUI file manager, `watchexec` for running commands on file changes, `rclone` for cloud storage sync
- **Kubernetes**: `k9s` for TUI, `stern` for log tailing (kubectl via OrbStack)
- **AWS**: `granted`/`assume` for role switching
- **Shell scripting**: `gum` for interactive prompts/spinners, `nushell` for structured data pipelines, `parallel` for parallel execution
- **Terminal**: `tmux` or `zellij` for multiplexing, `mpv` for video playback, `asciinema` for recording
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
- `snyk test` — dependency vulnerability scanning
- `detect-secrets scan` — pre-commit secret detection
CLAUDE_MD_CONF
    success "Claude Code global CLAUDE.md created"
fi

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
- Estimate costs with `infracost` before applying changes
- Use modules for reusable infrastructure patterns
- Tag all resources: project, environment, owner, managed-by
- Use workspaces or separate state files per environment
- Scan with `trivy config .` for misconfigurations
IAC_RULES

    success "Claude Code rules created (workflow, git, security, typescript, python, docker, iac)"
fi

CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
if [[ -d "$CLAUDE_HOOKS_DIR" ]]; then
    warn "Claude Code hooks directory already exists"
else
    info "Creating Claude Code hooks..."
    mkdir -p "$CLAUDE_HOOKS_DIR"
    cat > "$CLAUDE_HOOKS_DIR/format-on-edit.sh" <<'HOOK_FORMAT'
#!/usr/bin/env bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [[ -n "$FILE" ]] && [[ "$FILE" =~ \.(ts|tsx|js|jsx|css|scss|json|md)$ ]]; then
    if [[ -f "$FILE" ]] && command -v prettier &>/dev/null; then
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
    chmod +x "$CLAUDE_HOOKS_DIR/format-on-edit.sh"

    # Post-edit hook: auto-lint Python files with ruff
    cat > "$CLAUDE_HOOKS_DIR/lint-python.sh" <<'HOOK_RUFF'
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
    chmod +x "$CLAUDE_HOOKS_DIR/lint-python.sh"

    # Post-edit hook: lint Dockerfiles with hadolint
    cat > "$CLAUDE_HOOKS_DIR/lint-dockerfile.sh" <<'HOOK_HADOLINT'
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
    chmod +x "$CLAUDE_HOOKS_DIR/lint-dockerfile.sh"

    success "Claude Code hooks created (auto-format JS/TS, auto-lint Python, lint Dockerfiles)"
fi

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
2. Run `trivy config .` to scan for misconfigurations
3. Run `infracost breakdown --path .` to estimate costs (if infracost is configured)
4. Check for: missing tags, overly permissive IAM, unencrypted resources, missing backups
5. Check CDK code for L1 constructs that should be L2/L3

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
4. **Index**: Add to barrel export (`index.ts`) if the directory uses one

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

If no version range specified, generate from the last tag to HEAD.

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

fi  # configs (Claude Code configuration)

# =============================================================================
if should_run "filesystem"; then
banner "Filesystem Structure"

info "Setting up filesystem structure..."

DIRS=(
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

    # -- Documents (organized by life area) -----------------------------------
    "$HOME/Documents/finance/taxes"
    "$HOME/Documents/finance/invoices"
    "$HOME/Documents/finance/statements"
    "$HOME/Documents/health"
    "$HOME/Documents/legal"
    "$HOME/Documents/travel"
    "$HOME/Documents/insurance"
    "$HOME/Documents/contracts"
    "$HOME/Documents/receipts"
    "$HOME/Documents/design"

    # -- Reference (quick-access knowledge) -----------------------------------
    "$HOME/Reference/manuals"
    "$HOME/Reference/cheatsheets"
    "$HOME/Reference/bookmarks-export"

    # -- Creative -------------------------------------------------------------
    "$HOME/Creative/design"
    "$HOME/Creative/writing"
    "$HOME/Creative/video-editing"
    "$HOME/Creative/assets/icons"
    "$HOME/Creative/assets/fonts"
    "$HOME/Creative/assets/stock-photos"
    "$HOME/Creative/assets/templates"

    # -- Media ----------------------------------------------------------------
    "$HOME/Media/photos"
    "$HOME/Media/videos"
    "$HOME/Media/music"
    "$HOME/Media/wallpapers"

    # -- Projects (non-code personal projects) --------------------------------
    "$HOME/Projects/side-hustles"
    "$HOME/Projects/home"

    # -- Archive (cold storage for old stuff) ---------------------------------
    "$HOME/Archive/old-projects"
    "$HOME/Archive/old-docs"
)
for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
success "Directory structure created (~/Code, ~/Scripts, ~/Documents, ~/Reference, ~/Creative, ~/Media, ~/Projects, ~/Archive)"

# ---- GNOME Tracker / search-indexing exclusions ----
# Prevent Tracker (GNOME desktop search) from indexing dev directories
for exclude_dir in "$HOME/Code" "$HOME/.config"; do
    trackerignore="$exclude_dir/.trackerignore"
    if [[ ! -f "$trackerignore" ]]; then
        touch "$trackerignore"
        info "Created $trackerignore (excludes directory from GNOME Tracker indexing)"
    fi
done

# ---- Helper Scripts (adapted for Linux: open->xdg-open, pbcopy->xclip) ----
info "Creating helper scripts in ~/Scripts/bin..."

cat > "$HOME/Scripts/bin/clean-downloads" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DAYS="${1:-30}"
DIR="$HOME/Downloads"
echo "Finding files in $DIR older than $DAYS days..."
count=$(find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" | wc -l | tr -d ' ')
if [[ "$count" -eq 0 ]]; then echo "No files found."; exit 0; fi
echo "Found $count files to delete:"
find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" -exec basename {} \;
read -rp "Delete these $count files? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" -exec trash-put {} \;
    echo "Moved $count files to Trash."
else echo "Cancelled."; fi
SCRIPT

cat > "$HOME/Scripts/bin/new-project" <<'SCRIPT'
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

cat > "$HOME/Scripts/bin/clone-work" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then echo "Usage: clone-work <github-url-or-org/repo>"; exit 1; fi
if [[ "$INPUT" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then ORG="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"
elif [[ "$INPUT" =~ ^([^/]+)/([^/]+)$ ]]; then ORG="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"
else echo "Could not parse: $INPUT"; exit 1; fi
TARGET="$HOME/Code/work/$ORG"
mkdir -p "$TARGET"
if [[ -d "$TARGET/$REPO" ]]; then echo "Already exists: $TARGET/$REPO"; exit 1; fi
gh repo clone "$ORG/$REPO" "$TARGET/$REPO"
git -C "$TARGET/$REPO" maintenance start 2>/dev/null || true
echo "Cloned to: $TARGET/$REPO"
SCRIPT

cat > "$HOME/Scripts/bin/clone-personal" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then echo "Usage: clone-personal <repo>"; exit 1; fi
if [[ "$INPUT" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then REPO="${BASH_REMATCH[2]}"; CLONE_URL="$INPUT"
elif [[ "$INPUT" =~ / ]]; then REPO="${INPUT##*/}"; CLONE_URL="$INPUT"
else REPO="$INPUT"; CLONE_URL=""; fi
TARGET="$HOME/Code/personal/$REPO"
if [[ -d "$TARGET" ]]; then echo "Already exists: $TARGET"; exit 1; fi
if [[ -n "$CLONE_URL" ]]; then gh repo clone "$CLONE_URL" "$TARGET"; else gh repo clone "$REPO" "$TARGET"; fi
git -C "$TARGET" maintenance start 2>/dev/null || true
echo "Cloned to: $TARGET"
SCRIPT

cat > "$HOME/Scripts/bin/backup-dotfiles" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v chezmoi &>/dev/null; then echo "chezmoi not installed"; exit 1; fi

# Backup crontab
echo "Backing up crontab..."
crontab -l > "$(chezmoi source-path)/crontab.backup" 2>/dev/null || echo "  (no crontab)"

# Export package list
echo "Exporting package list..."
if command -v dpkg &>/dev/null; then
    dpkg --get-selections > "$(chezmoi source-path)/packages-apt.txt" 2>/dev/null || true
elif command -v dnf &>/dev/null; then
    dnf list installed > "$(chezmoi source-path)/packages-dnf.txt" 2>/dev/null || true
elif command -v pacman &>/dev/null; then
    pacman -Qqe > "$(chezmoi source-path)/packages-pacman.txt" 2>/dev/null || true
fi

# Re-add tracked files to pick up changes
echo "Updating tracked dotfiles..."
chezmoi re-add 2>/dev/null || true
cd "$(chezmoi source-path)"
if git diff --quiet && git diff --cached --quiet; then echo "No changes."; exit 0; fi
git status --short
read -rp "Commit and push? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git add -A && git commit -m "Update dotfiles — $(date +%Y-%m-%d)" && git push
    echo "Done."
else echo "Cancelled."; fi
SCRIPT

cat > "$HOME/Scripts/bin/project-stats" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
CODE_DIR="$HOME/Code"
echo "=== Project Stats ==="
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
    repo=$(dirname "$gitdir"); branch=$(git -C "$repo" branch --show-current 2>/dev/null)
    echo "  ${repo#$CODE_DIR/} ($branch)"
done
SCRIPT

# -- health-check: quick system overview --
cat > "$HOME/Scripts/bin/health-check" <<'SCRIPT'
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
free -h 2>/dev/null | awk '/^Mem:/ {printf "  Used: %s  Free: %s  Total: %s\n", $3, $4, $2}'

# Package manager outdated
if command -v apt &>/dev/null; then
    echo ""
    echo "-- APT --"
    OUTDATED=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
    echo "  Upgradable packages: $OUTDATED"
elif command -v dnf &>/dev/null; then
    echo ""
    echo "-- DNF --"
    OUTDATED=$(dnf check-update --quiet 2>/dev/null | grep -cE "^[a-zA-Z]" || echo "0")
    echo "  Upgradable packages: $OUTDATED"
elif command -v pacman &>/dev/null; then
    echo ""
    echo "-- Pacman --"
    OUTDATED=$(checkupdates 2>/dev/null | wc -l | tr -d ' ')
    echo "  Upgradable packages: $OUTDATED"
fi

# Brew outdated (if linuxbrew)
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
cat > "$HOME/Scripts/bin/setup-ssh" <<'SCRIPT'
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
read -rp "Add this key to GitHub? [y/N] " confirm
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

# -- export-brewfile: export package list snapshot --
cat > "$HOME/Scripts/bin/export-brewfile" <<'SCRIPT'
#!/usr/bin/env bash
# Export package list / Brewfile snapshot
# Usage: export-brewfile
set -euo pipefail

EXPORT_DIR="$HOME/.config/package-list"
mkdir -p "$EXPORT_DIR"

# Linuxbrew Brewfile
if command -v brew &>/dev/null; then
    BREWFILE="$EXPORT_DIR/Brewfile"
    echo "Exporting Brewfile to $BREWFILE..."
    brew bundle dump --file="$BREWFILE" --force --describe 2>/dev/null
    echo "Done. $(wc -l < "$BREWFILE" | tr -d ' ') brew packages recorded."
    echo ""
    echo "Restore on a new machine:"
    echo "  brew bundle install --file=$BREWFILE"
fi

# Native package manager export
if command -v dpkg &>/dev/null; then
    PKG_LIST="$EXPORT_DIR/apt-packages.txt"
    echo "Exporting apt package list to $PKG_LIST..."
    dpkg --get-selections > "$PKG_LIST" 2>/dev/null
    echo "Done. $(wc -l < "$PKG_LIST" | tr -d ' ') packages recorded."
elif command -v dnf &>/dev/null; then
    PKG_LIST="$EXPORT_DIR/dnf-packages.txt"
    echo "Exporting dnf package list to $PKG_LIST..."
    dnf list installed > "$PKG_LIST" 2>/dev/null
    echo "Done."
elif command -v pacman &>/dev/null; then
    PKG_LIST="$EXPORT_DIR/pacman-packages.txt"
    echo "Exporting pacman package list to $PKG_LIST..."
    pacman -Qqe > "$PKG_LIST" 2>/dev/null
    echo "Done. $(wc -l < "$PKG_LIST" | tr -d ' ') packages recorded."
fi
SCRIPT

chmod +x "$HOME/Scripts/bin/"*
success "Helper scripts created"

# ---- Per-directory Git Config ----
info "Setting up per-directory git config..."

GITCONFIG_WORK="$HOME/.gitconfig-work"
GITCONFIG_PERSONAL="$HOME/.gitconfig-personal"

if [[ ! -f "$GITCONFIG_WORK" ]]; then
    cat > "$GITCONFIG_WORK" <<'GIT_WORK'
[user]
    # name = Your Name
    # email = you@company.com
GIT_WORK
    success "\$HOME/.gitconfig-work created"
fi

if [[ ! -f "$GITCONFIG_PERSONAL" ]]; then
    cat > "$GITCONFIG_PERSONAL" <<'GIT_PERSONAL'
[user]
    # name = Your Name
    # email = you@personal.com
GIT_PERSONAL
    success "\$HOME/.gitconfig-personal created"
fi

if ! git config --global --get "includeIf.gitdir:~/Code/work/.path" &>/dev/null; then
    git config --global "includeIf.gitdir:~/Code/work/.path" "$GITCONFIG_WORK"
fi
if ! git config --global --get "includeIf.gitdir:~/Code/personal/.path" &>/dev/null; then
    git config --global "includeIf.gitdir:~/Code/personal/.path" "$GITCONFIG_PERSONAL"
fi
success "Per-directory git identity configured"

fi  # filesystem

# =============================================================================
if should_run "linux-defaults"; then
banner "Linux Desktop Defaults"

# GNOME settings (only if gsettings available)
if command -v gsettings &>/dev/null; then
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Configuring GNOME desktop settings..."

        # Fast keyboard repeat
        gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30 2>/dev/null || true
        gsettings set org.gnome.desktop.peripherals.keyboard delay 200 2>/dev/null || true

        # Show hidden files in file manager
        gsettings set org.gnome.nautilus.preferences show-hidden-files true 2>/dev/null || true

        # Reduce animations
        gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true

        # Dark theme
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true

        # Dock settings (if dash-to-dock present)
        gsettings set org.gnome.shell.extensions.dash-to-dock autohide true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40 2>/dev/null || true

        # Only clear dock favorites on fresh installs (no existing customization)
        current_favorites=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "")
        if [[ "$current_favorites" == "@as []" ]] || [[ -z "$current_favorites" ]]; then
            gsettings set org.gnome.shell favorite-apps "['org.gnome.Nautilus.desktop']" 2>/dev/null || true
        fi

        # Screenshots location
        mkdir -p "$HOME/Screenshots"
        gsettings set org.gnome.gnome-screenshot auto-save-directory "file://$HOME/Screenshots" 2>/dev/null || true

        success "GNOME desktop settings configured"
    else
        info "[DRY RUN] Would configure GNOME desktop settings"
    fi
else
    info "gsettings not available — skipping GNOME defaults (not running GNOME?)"
fi

# KDE Plasma: clear default taskbar pinned apps
if [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]] && [[ "$DRY_RUN" != "true" ]]; then
    info "Clearing default pinned apps from KDE taskbar..."
    PLASMA_TASKBAR="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "$PLASMA_TASKBAR" ]]; then
        # Remove launchers from the task manager applet
        sed -i 's/^launchers=.*/launchers=/' "$PLASMA_TASKBAR" 2>/dev/null || true
        success "KDE taskbar cleared — right-click apps to pin them"
    fi
fi

# ---- File Manager Sidebar Bookmarks ----
# GTK file managers (Nautilus, Thunar, Nemo, Caja) read ~/.config/gtk-3.0/bookmarks
# KDE Dolphin reads ~/.local/share/user-places.xbel (but also respects gtk bookmarks for portability)
info "Configuring file manager sidebar bookmarks..."
if [[ "$DRY_RUN" != "true" ]]; then
    BOOKMARKS_FILE="$HOME/.config/gtk-3.0/bookmarks"
    mkdir -p "$HOME/.config/gtk-3.0"

    # Build the bookmarks list
    BOOKMARK_DIRS=(
        "$HOME/Code|Code"
        "$HOME/Screenshots|Screenshots"
        "$HOME/Scripts|Scripts"
        "$HOME/Documents|Documents"
        "$HOME/Reference|Reference"
        "$HOME/Creative|Creative"
        "$HOME/Media|Media"
        "$HOME/Projects|Projects"
        "$HOME/Archive|Archive"
        "$HOME/Downloads|Downloads"
    )

    # Preserve any existing bookmarks not in our list, then append ours
    EXISTING_BOOKMARKS=""
    if [[ -f "$BOOKMARKS_FILE" ]]; then
        EXISTING_BOOKMARKS=$(cat "$BOOKMARKS_FILE")
    fi

    # Start fresh with our curated list
    : > "$BOOKMARKS_FILE"
    for entry in "${BOOKMARK_DIRS[@]}"; do
        dir="${entry%%|*}"
        name="${entry##*|}"
        if [[ -d "$dir" ]]; then
            echo "file://$dir $name" >> "$BOOKMARKS_FILE"
        fi
    done

    # Re-add any user bookmarks that aren't in our list (e.g., network shares, custom dirs)
    if [[ -n "$EXISTING_BOOKMARKS" ]]; then
        while IFS= read -r line; do
            # Skip if it's one of our managed dirs
            is_managed=false
            for entry in "${BOOKMARK_DIRS[@]}"; do
                dir="${entry%%|*}"
                if echo "$line" | grep -q "file://$dir"; then
                    is_managed=true
                    break
                fi
            done
            if [[ "$is_managed" == "false" ]] && [[ -n "$line" ]]; then
                echo "$line" >> "$BOOKMARKS_FILE"
            fi
        done <<< "$EXISTING_BOOKMARKS"
    fi

    success "File manager bookmarks updated (Code, Screenshots, Scripts, Documents, Reference, Creative, Media, Projects, Archive, Downloads)"
else
    info "[DRY RUN] Would update file manager sidebar bookmarks"
fi

# DNS (systemd-resolved)
if systemctl is-active systemd-resolved &>/dev/null; then
    info "Configuring DNS via systemd-resolved..."
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo mkdir -p /etc/systemd/resolved.conf.d
        cat <<'DNS_CONF' | sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null
[Resolve]
DNS=1.1.1.1 1.0.0.1 9.9.9.9 8.8.8.8
FallbackDNS=8.8.4.4
DNS_CONF
        sudo systemctl restart systemd-resolved 2>&1 | tee -a "$LOG_FILE" > /dev/null || true
        success "DNS set to Cloudflare + Quad9 + Google"
    fi
else
    info "systemd-resolved not active — configure DNS manually in /etc/resolv.conf"
fi

# -- Wallpaper --
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SRC="$SCRIPT_DIR/assets/wolf-wallpaper.jpg"
WALLPAPER_DEST="$HOME/Media/wallpapers/wolf-wallpaper.jpg"
if [[ -f "$WALLPAPER_SRC" ]]; then
    mkdir -p "$HOME/Media/wallpapers"
    cp -f "$WALLPAPER_SRC" "$WALLPAPER_DEST"
    if [[ "$DRY_RUN" != "true" ]]; then
        # GNOME
        if command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_DEST" 2>/dev/null || true
            gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DEST" 2>/dev/null || true
            gsettings set org.gnome.desktop.background picture-options "zoom" 2>/dev/null || true
        fi
        # KDE Plasma (via dbus)
        if command -v qdbus &>/dev/null; then
            qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
                var allDesktops = desktops();
                for (var i = 0; i < allDesktops.length; i++) {
                    allDesktops[i].wallpaperPlugin = 'org.kde.image';
                    allDesktops[i].currentConfigGroup = ['Wallpaper','org.kde.image','General'];
                    allDesktops[i].writeConfig('Image','file://$WALLPAPER_DEST');
                }
            " 2>/dev/null || true
        fi
        # feh fallback (i3, sway, bspwm, etc.)
        if command -v feh &>/dev/null && [[ -z "$XDG_CURRENT_DESKTOP" || "$XDG_CURRENT_DESKTOP" =~ ^(i3|sway|bspwm|dwm|openbox)$ ]]; then
            feh --bg-fill "$WALLPAPER_DEST" 2>/dev/null || true
        fi
        success "Wallpaper set to wolf-wallpaper.jpg"
    else
        info "[DRY RUN] Would set wallpaper to wolf-wallpaper.jpg"
    fi
else
    warn "Wallpaper not found at $WALLPAPER_SRC — skipping"
fi

# ---- Auto-set timezone ----
# Timezone — uncomment and set your timezone if desired
# sudo timedatectl set-timezone "America/Chicago" 2>/dev/null || true
if [[ "$DRY_RUN" != "true" ]]; then
    sudo timedatectl set-ntp true 2>/dev/null || true
    success "NTP enabled"
fi

# ---- Software update: auto-check (Ubuntu) ----
if [[ "$DRY_RUN" != "true" ]] && [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
fi

# ---- Login items / autostart ----
mkdir -p "$HOME/.config/autostart"
# Create autostart entries for flameshot, etc.
if installed flameshot; then
    if [[ ! -f "$HOME/.config/autostart/flameshot.desktop" ]]; then
        cat > "$HOME/.config/autostart/flameshot.desktop" <<'AUTOSTART_FLAMESHOT'
[Desktop Entry]
Name=Flameshot
Exec=flameshot
Type=Application
X-GNOME-Autostart-enabled=true
AUTOSTART_FLAMESHOT
        success "Flameshot added to autostart"
    fi
fi

# ---- GNOME additional settings ----
if command -v gsettings &>/dev/null; then
    # Disable automatic screen lock timeout during work (15 min)
    gsettings set org.gnome.desktop.session idle-delay 900 2>/dev/null || true

    # Show battery percentage
    gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null || true

    # Touchpad tap-to-click
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true 2>/dev/null || true

    # Natural scrolling
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true 2>/dev/null || true

    success "GNOME additional settings applied (idle-delay, battery, touchpad)"
fi

fi  # linux-defaults

# =============================================================================
if should_run "shell"; then
banner "Shell Configuration"

ZSHRC="$HOME/.zshrc"
ZSHRC_BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
ZSHRC_MANAGED_MARKER="# >>> dev-setup managed block >>>"
ZSHRC_MANAGED_END="# <<< dev-setup managed block <<<"

# Determine zsh plugin paths
ZSH_AUTOSUGGEST_PATH=""
for p in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
         /usr/share/zsh-autosuggestions.zsh; do
    [[ -f "$p" ]] && ZSH_AUTOSUGGEST_PATH="$p" && break
done

ZSH_SYNTAX_HL_PATH=""
for p in /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
         /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
         /usr/share/zsh-syntax-highlighting.zsh; do
    [[ -f "$p" ]] && ZSH_SYNTAX_HL_PATH="$p" && break
done

# Determine fzf paths
FZF_KEYBINDINGS_PATH=""
for p in /usr/share/doc/fzf/examples/key-bindings.zsh \
         /usr/share/fzf/key-bindings.zsh \
         /usr/share/fzf/shell/key-bindings.zsh; do
    [[ -f "$p" ]] && FZF_KEYBINDINGS_PATH="$p" && break
done

FZF_COMPLETION_PATH=""
for p in /usr/share/doc/fzf/examples/completion.zsh \
         /usr/share/fzf/completion.zsh \
         /usr/share/fzf/shell/completion.zsh; do
    [[ -f "$p" ]] && FZF_COMPLETION_PATH="$p" && break
done

MANAGED_BLOCK="# >>> dev-setup managed block >>>
# This block is managed by setup-dev-tools-linux.sh — edits may be overwritten.
# Add personal customizations OUTSIDE this block.

# -- PATH additions -----------------------------------------------------------
typeset -U PATH path
export PATH=\"\$HOME/Scripts/bin:\$HOME/.local/bin:\$PATH\"

# -- Environment Variables ----------------------------------------------------
export RIPGREP_CONFIG_PATH=\"\$HOME/.ripgreprc\"
export GPG_TTY=\$(tty)

# Raise file descriptor limit for Node.js / bundlers
ulimit -n 65536 2>/dev/null || true

# LS_COLORS via vivid (Dracula theme — colorize file listings by type)
if command -v vivid &>/dev/null; then
    export LS_COLORS=\"\$(vivid generate dracula)\"
fi

# -- Tool Initialization ------------------------------------------------------

# Linuxbrew
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"
elif [[ -f \"\$HOME/.linuxbrew/bin/brew\" ]]; then
    eval \"\$(\"\$HOME/.linuxbrew/bin/brew\" shellenv)\"
fi

# mise (universal version manager — Node, Python, Go, Ruby, etc.)
eval \"\$(mise activate zsh)\"

# direnv
command -v direnv &>/dev/null && eval \"\$(direnv hook zsh)\"

# zoxide
command -v zoxide &>/dev/null && eval \"\$(zoxide init zsh)\"

# starship prompt
command -v starship &>/dev/null && eval \"\$(starship init zsh)\"

# atuin
command -v atuin &>/dev/null && eval \"\$(atuin init zsh)\"

# fzf"

# Add fzf keybindings/completion
if [[ -n "$FZF_KEYBINDINGS_PATH" ]]; then
    MANAGED_BLOCK="$MANAGED_BLOCK
[ -f \"$FZF_KEYBINDINGS_PATH\" ] && source \"$FZF_KEYBINDINGS_PATH\""
fi
if [[ -n "$FZF_COMPLETION_PATH" ]]; then
    MANAGED_BLOCK="$MANAGED_BLOCK
[ -f \"$FZF_COMPLETION_PATH\" ] && source \"$FZF_COMPLETION_PATH\""
fi

MANAGED_BLOCK="$MANAGED_BLOCK

# fzf — Dracula colors + fd for file finding + bat for preview
export FZF_DEFAULT_OPTS=\" \\
  --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 \\
  --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 \\
  --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 \\
  --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4 \\
  --color=border:#6272a4 \\
  --height=60% --layout=reverse --border=rounded \\
  --prompt='❯ ' --pointer='▶' --marker='✓' \\
  --bind='ctrl-/:toggle-preview' \\
  --bind='ctrl-d:half-page-down,ctrl-u:half-page-up' \\
  --bind='ctrl-y:execute-silent(echo -n {+} | xclip -selection clipboard)+abort' \\
  --preview-window='right:50%:wrap:hidden' \\
  --info=inline\"

# Use fd instead of find (respects .gitignore, faster)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'

# CTRL-T: paste file path (with bat preview)
export FZF_CTRL_T_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS=\"--preview 'bat --color=always --style=numbers --line-range=:300 {}' --preview-window='right:50%:wrap'\"

# ALT-C: cd into directory (with eza tree preview)
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS=\"--preview 'eza --tree --icons --level=2 --color=always {}' --preview-window='right:50%:wrap'\"

# -- nnn (terminal file manager) ----------------------------------------------
export NNN_OPTS=\"deH\"
export NNN_COLORS=\"2136\"
export NNN_FCOLORS=\"c1e2272e006033f7c6d6abc4\"
export NNN_PLUG=\"f:fzcd;o:fzopen;p:preview-tui\"

# zsh plugins"

if [[ -n "$ZSH_AUTOSUGGEST_PATH" ]]; then
    MANAGED_BLOCK="$MANAGED_BLOCK
[ -f \"$ZSH_AUTOSUGGEST_PATH\" ] && source \"$ZSH_AUTOSUGGEST_PATH\""
fi
if [[ -n "$ZSH_SYNTAX_HL_PATH" ]]; then
    MANAGED_BLOCK="$MANAGED_BLOCK
[ -f \"$ZSH_SYNTAX_HL_PATH\" ] && source \"$ZSH_SYNTAX_HL_PATH\""
fi

MANAGED_BLOCK="$MANAGED_BLOCK

# -- Completions ---------------------------------------------------------------
autoload -Uz compinit && compinit -C
[[ -x \"\$(command -v kubectl)\" ]] && source <(kubectl completion zsh)
[[ -x \"\$(command -v gh)\" ]] && source <(gh completion -s zsh)
[[ -x \"\$(command -v aws_completer)\" ]] && complete -C \"\$(command -v aws_completer)\" aws

# -- Modern Tool Aliases ------------------------------------------------------
alias ls=\"eza --icons\"
alias ll=\"eza -la --icons --git\"
alias la=\"eza -a --icons\"
alias lt=\"eza --tree --icons --level=3\"
alias cat=\"bat --paging=never\"
alias top=\"btop\"
alias du=\"dust\"
alias df=\"duf\"
alias ps=\"procs\"
alias ping=\"gping\"
alias dig=\"doggo\"
alias watch=\"viddy\"
alias hexdump=\"hexyl\"
alias rm=\"trash-put\"
alias make=\"just\"

# Short aliases
alias rg=\"rg\"
alias f=\"fd\"
alias sd=\"sd\"
alias dft=\"difft\"
alias y=\"yazi\"
alias jx=\"fx\"

# Download
alias dl=\"aria2c\"

# Git & GitHub
alias lg=\"lazygit\"
alias ghd=\"gh dash\"
alias gdft=\"git dft\"
alias gha=\"act\"
alias gha3=\"act3\"

# Containers & K8s
alias lzd=\"lazydocker\"
alias k=\"kubectl\"
alias klog=\"stern\"

# File Tools
alias md=\"glow\"
alias serve=\"miniserve --color-scheme-dark dracula -qr .\"
alias csvp=\"csvlook\"

# Media
alias ytdl=\"yt-dlp\"
alias ytmp3=\"yt-dlp -x --audio-format mp3\"
alias resize=\"magick mogrify -resize\"
alias ffq=\"ffmpeg -hide_banner -loglevel warning\"
alias md2pdf=\"pandoc -f markdown -t pdf\"
alias md2html=\"pandoc -f markdown -t html -s\"
alias md2docx=\"pandoc -f markdown -t docx\"

# Python (uv)
alias pip=\"uv pip\"
alias venv=\"uv venv\"
alias pyrun=\"uv run\"

# Global Justfile
alias gj=\"just --justfile ~/.justfile --working-directory .\"

# Dev & Testing
alias watchrun=\"watchexec --exts ts,tsx --restart\"
alias bench=\"hyperfine\"
alias loadtest=\"oha\"
alias par=\"parallel\"
alias lint-sh=\"shellcheck\"
alias fmt-sh=\"shfmt -w -i 4\"

# Terminal apps
alias n=\"nnn -de\"
alias prog=\"progress -m\"
alias sshc=\"sshclick\"

# Directory Shortcuts
alias cw=\"z ~/Code/work\"
alias cper=\"z ~/Code/personal\"
alias coss=\"z ~/Code/oss\"
alias clearn=\"z ~/Code/learning\"
alias cscratch=\"z ~/Code/work/scratch\"
alias cscripts=\"z ~/Scripts\"

# Helper Script Shortcuts
alias nproj=\"new-project\"
alias cwork=\"clone-work\"
alias cpers=\"clone-personal\"
alias dotback=\"backup-dotfiles\"
alias pstats=\"project-stats\"
alias cleandl=\"clean-downloads\"
alias hc=\"health-check\"
alias sshsetup=\"setup-ssh\"
alias brewsnap=\"export-brewfile\"

# System
alias update=\"topgrade\"
alias sysinfo=\"fastfetch\"
alias open=\"xdg-open\"
alias pbcopy=\"xclip -selection clipboard\"
alias pbpaste=\"xclip -selection clipboard -o\"

# -- Terminal Welcome Screen --------------------------------------------------
# Colorful greeting on new terminal sessions (not in VS Code integrated terminal)
if [[ \"\$TERM_PROGRAM\" != \"vscode\" ]] && [[ -z \"\$INSIDE_EMACS\" ]]; then
    if command -v fastfetch &>/dev/null; then
        fastfetch --logo small 2>/dev/null
    fi
    echo \"\"
    printf \"\\033[0;35m  %s\\033[0m  \" \"\$(date '+%A, %B %d %Y  •  %H:%M')\"
    TIPS=(
        \"💡 git stash -u  — stash untracked files too\"
        \"💡 fd -e ts -x wc -l  — count lines in every .ts file\"
        \"💡 rg TODO --glob '!node_modules'  — search TODOs\"
        \"💡 just --list  — see all task runner recipes\"
        \"💡 gh pr create --web  — open PR in browser\"
        \"💡 btop  — beautiful system monitor\"
        \"💡 yazi  — terminal file manager with preview\"
        \"💡 oha -n 500 http://localhost:3000  — quick load test\"
        \"💡 sd 'old' 'new' file.ts  — fast find & replace\"
        \"💡 dust ~/Code  — visual disk usage of your projects\"
        \"💡 doggo example.com AAAA  — colorized DNS lookup\"
        \"💡 hyperfine 'cmd1' 'cmd2'  — benchmark two commands\"
        \"💡 fx data.json  — interactive JSON explorer\"
        \"💡 gj ports  — list all listening ports\"
        \"💡 hc  — quick system health check\"
    )
    echo \"\${TIPS[\$((RANDOM % \${#TIPS[@]}))]}\"\
    echo \"\"
fi

# <<< dev-setup managed block <<<"

if [[ -f "$ZSHRC" ]]; then
    if grep -q "$ZSHRC_MANAGED_MARKER" "$ZSHRC" 2>/dev/null; then
        info "Updating managed block in existing ~/.zshrc..."
        cp "$ZSHRC" "$ZSHRC_BACKUP"
        awk -v marker="$ZSHRC_MANAGED_MARKER" -v end_marker="$ZSHRC_MANAGED_END" '
            $0 == marker { skip=1; next }
            $0 == end_marker { skip=0; next }
            !skip { print }
        ' "$ZSHRC_BACKUP" > "$ZSHRC"
        echo "" >> "$ZSHRC"
        echo "$MANAGED_BLOCK" >> "$ZSHRC"
        success "\$HOME/.zshrc managed block updated (backup: $ZSHRC_BACKUP)"
    else
        info "Appending managed block to existing \$HOME/.zshrc..."
        cp "$ZSHRC" "$ZSHRC_BACKUP"
        echo "" >> "$ZSHRC"
        echo "$MANAGED_BLOCK" >> "$ZSHRC"
        success "\$HOME/.zshrc updated (backup: $ZSHRC_BACKUP)"
    fi
else
    info "Creating \$HOME/.zshrc..."
    cat > "$ZSHRC" <<'ZSHRC_HEADER'
# =============================================================================
# ~/.zshrc — generated by setup-dev-tools-linux.sh
# =============================================================================
# Add personal customizations OUTSIDE the managed block below.

ZSHRC_HEADER
    echo "$MANAGED_BLOCK" >> "$ZSHRC"
    success "\$HOME/.zshrc created"
fi

fi  # shell

# =============================================================================
# FIRST-RUN SETUP (interactive — only runs if not already configured)
# =============================================================================
if [[ "$DRY_RUN" == "false" ]]; then
banner "First-Run Setup"

# ---- SSH Key Generation ----
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    echo ""
    read -rp "Generate an SSH key? [Y/n] " ssh_confirm
    if [[ ! "$ssh_confirm" =~ ^[Nn]$ ]]; then
        read -rp "Email for SSH key: " ssh_email
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
        read -rp "Authenticate with GitHub? [Y/n] " gh_confirm
        if [[ ! "$gh_confirm" =~ ^[Nn]$ ]]; then
            info "Opening GitHub authentication..."
            gh auth login
            # Add SSH key to GitHub if it was just generated
            if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
                read -rp "Add SSH key to GitHub? [Y/n] " ssh_gh_confirm
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
    read -rp "Set up your work git identity? [Y/n] " work_confirm
    if [[ ! "$work_confirm" =~ ^[Nn]$ ]]; then
        read -rp "Work name: " work_name
        read -rp "Work email: " work_email
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
    read -rp "Set up your personal git identity? [Y/n] " personal_confirm
    if [[ ! "$personal_confirm" =~ ^[Nn]$ ]]; then
        read -rp "Personal name: " personal_name
        read -rp "Personal email: " personal_email
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

fi  # DRY_RUN (first-run setup)

# =============================================================================
# POST-INSTALL VERIFICATION
# =============================================================================
banner "Post-install Verification"

if [[ "$DRY_RUN" == "false" ]]; then
    info "Verifying critical tools..."

    VERIFY_TOOLS=(
        "git:git --version"
        "node:node --version"
        "python3:python3 --version"
        "go:go version"
        "rustc:rustc --version"
        "bun:bun --version"
        "uv:uv --version"
        "code:code --version"
        "docker:docker --version"
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
        if version=$($cmd 2>/dev/null | head -1); then
            echo -e "  ${GREEN}✓${NC} $tool: $version"
            ((VERIFY_PASS++))
        else
            echo -e "  ${RED}✗${NC} $tool: not found or not working"
            ((VERIFY_FAIL++))
        fi
    done
    echo ""
    success "Verification: $VERIFY_PASS passed, $VERIFY_FAIL failed"
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
echo ""

if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
    echo -e "${RED}${BOLD}Failed items:${NC}"
    for item in "${FAILED_ITEMS[@]}"; do
        echo -e "  ${RED}•${NC} $item"
    done
    echo ""
    echo -e "  Check the log for details: ${DIM}cat $LOG_FILE | grep ERROR${NC}"
    echo ""
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}${BOLD}  This was a dry run — no changes were made.${NC}"
    echo -e "${YELLOW}  Run without --dry-run to install everything.${NC}"
    echo ""
fi

echo ""
info "What was configured:"
echo "  [~/.zshrc]              Shell config with managed block"
echo "  [~/.ssh/config]         SSH multiplexing, keep-alive"
echo "  [~/.gitignore_global]   Global gitignore"
echo "  [~/.gitconfig]          Git aliases, rebase, delta, difftastic"
echo "  [~/.gnupg/]             GPG with pinentry"
echo "  [~/.tmux.conf]          tmux with Dracula theme"
echo "  [~/.npmrc]              save-exact, no telemetry"
echo "  [~/.editorconfig]       Cross-editor consistency"
echo "  [~/.prettierrc]         Global Prettier defaults"
echo "  [~/.curlrc]             Follow redirects, retry, compression"
echo "  [~/.docker/daemon.json] BuildKit, log rotation"
echo "  [~/.config/starship]    Dracula prompt"
echo "  [~/.config/atuin]       Fuzzy search, local-only"
echo "  [~/.config/alacritty]   Dracula terminal theme"
echo "  [~/.config/kitty]       Dracula terminal theme"
echo "  [~/.config/yazi]        File manager with Dracula theme"
echo "  [~/.justfile]           Global task runner recipes"
echo "  [VS Code]               Dracula theme, extensions"
echo "  [lazygit]               Dracula theme"
echo "  [k9s]                   Dracula skin"
echo "  [Claude Code]           Custom commands, rules, hooks"
echo ""
info "Next steps:"
echo "  1. Log out and back in (for docker group + zsh default shell)"
echo "  2. Open a new terminal or run: source ~/.zshrc"
echo "  3. Generate SSH key: ssh-keygen -t ed25519 -C \"your_email@example.com\""
echo "  4. Add SSH key to GitHub: gh ssh-key add ~/.ssh/id_ed25519.pub"
echo "  5. Set up ngrok: ngrok config add-authtoken <TOKEN>"
echo "  6. Set up chezmoi: chezmoi init && chezmoi add ~/.zshrc"
echo ""
echo -e "${GREEN}${BOLD}  Restart your terminal to activate everything.${NC}"
echo ""
