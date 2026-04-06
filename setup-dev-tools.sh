#!/usr/bin/env bash

# =============================================================================
# Development Environment Setup Script (macOS)
# =============================================================================
# Version:  2.0.0
# Updated:  2026-04-05
# Platform: macOS (Apple Silicon + Intel)
# Run:      chmod +x setup-dev-tools.sh && ./setup-dev-tools.sh
# Flags:    --dry-run, --skip <categories>, --only <categories>, --help
# =============================================================================

SCRIPT_VERSION="2.0.0"
SCRIPT_START=$(date +%s)

# -- Colors & Formatting ------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# -- Logging ------------------------------------------------------------------
LOG_DIR="$HOME/.local/share/dev-setup"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"

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
INSTALL_TOTAL=191
FAILED_ITEMS=()

progress() {
    ((INSTALL_CURRENT++)) || true
    local pct=$((INSTALL_CURRENT * 100 / INSTALL_TOTAL))
    local bar_len=$((pct / 2))
    local bar=$(printf '█%.0s' $(seq 1 $bar_len 2>/dev/null) 2>/dev/null || echo "")
    local spaces=$(printf ' %.0s' $(seq 1 $((50 - bar_len)) 2>/dev/null) 2>/dev/null || echo "")
    echo -ne "\r${DIM}[${CYAN}${bar}${DIM}${spaces}] ${pct}% (${INSTALL_CURRENT}/${INSTALL_TOTAL})${NC}  "
    echo ""
}

# -- State flags --------------------------------------------------------------
DRY_RUN=false
SKIP_CATEGORIES=()
ONLY_CATEGORIES=()

ALL_CATEGORIES=(
    prerequisites
    core
    git
    aws
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
    mac-system
    mac-productivity
    mac-communication
    mac-browsers
    mac-media
    mac-cloud
    mac-focus
    mac-disk
    dracula
    configs
    filesystem
    macos-defaults
    shell
)

# -- CLI argument parsing -----------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}macOS Development Environment Setup v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: ./setup-dev-tools.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --dry-run           Preview what would be installed (no changes)"
    echo "  --skip <cats>       Skip categories (comma-separated)"
    echo "  --only <cats>       Only run these categories (comma-separated)"
    echo "  --list-categories   List all available categories"
    echo "  --version           Show script version"
    echo ""
    echo "Examples:"
    echo "  ./setup-dev-tools.sh                          # Install everything"
    echo "  ./setup-dev-tools.sh --dry-run                # Preview only"
    echo "  ./setup-dev-tools.sh --skip mac-media,mac-cloud"
    echo "  ./setup-dev-tools.sh --only core,git,aws,dx"
    echo ""
}

list_categories() {
    echo ""
    echo -e "${BOLD}Available categories:${NC}"
    echo ""
    printf "  %-25s %s\n" "prerequisites"       "Xcode CLI Tools, Rosetta 2, Homebrew, GNU coreutils"
    printf "  %-25s %s\n" "core"                "Node, Python, Docker, OrbStack, pnpm"
    printf "  %-25s %s\n" "git"                 "Git, GitHub CLI, delta, lazygit, pre-commit"
    printf "  %-25s %s\n" "aws"                 "AWS CLI, CDK, SAM, Granted, cfn-lint"
    printf "  %-25s %s\n" "security"            "git-secrets, trivy, semgrep, Snyk, ClamAV, Objective-See"
    printf "  %-25s %s\n" "replacements"        "eza, bat, fd, ripgrep, zoxide, btop, sd, dust, etc."
    printf "  %-25s %s\n" "data-processing"     "yq, miller, csvkit, pandoc, ffmpeg, ImageMagick"
    printf "  %-25s %s\n" "code-quality"        "shellcheck, shfmt, act"
    printf "  %-25s %s\n" "perf-testing"        "hyperfine, oha"
    printf "  %-25s %s\n" "dev-servers"         "ngrok, miniserve, caddy"
    printf "  %-25s %s\n" "terminal-productivity" "glow, entr, pv, parallel, topgrade, fastfetch"
    printf "  %-25s %s\n" "k8s-github"          "stern, gh-dash"
    printf "  %-25s %s\n" "database"            "pgcli, mycli, usql, TablePlus, DBeaver"
    printf "  %-25s %s\n" "containers"          "lazydocker, dive, kubectl, k9s"
    printf "  %-25s %s\n" "api"                 "Bruno, grpcurl"
    printf "  %-25s %s\n" "networking"          "mtr, bandwhich, nmap"
    printf "  %-25s %s\n" "dx"                  "fzf, starship, atuin, VS Code, Cursor, tmux, Raycast"
    printf "  %-25s %s\n" "ui"                  "Storybook, Playwright, Chrome"
    printf "  %-25s %s\n" "ux"                  "Figma, Lighthouse"
    printf "  %-25s %s\n" "docs"                "d2, Mermaid CLI"
    printf "  %-25s %s\n" "mac-system"          "AppCleaner, Stats, Bartender, Quick Look plugins"
    printf "  %-25s %s\n" "mac-productivity"    "Notion, CleanShot, Espanso, Hazel, Transmit"
    printf "  %-25s %s\n" "mac-communication"   "Slack, Discord, Telegram, Signal"
    printf "  %-25s %s\n" "mac-browsers"        "Firefox, Arc, Brave"
    printf "  %-25s %s\n" "mac-media"           "IINA, ImageOptim, LibreOffice, Pocket Casts"
    printf "  %-25s %s\n" "mac-cloud"           "Google Drive"
    printf "  %-25s %s\n" "mac-focus"           "Flow, Anki, Reeder"
    printf "  %-25s %s\n" "mac-disk"            "DaisyDisk"
    printf "  %-25s %s\n" "dracula"             "Dracula theme for all tools"
    printf "  %-25s %s\n" "configs"             "All dotfiles and tool configurations"
    printf "  %-25s %s\n" "filesystem"          "Directory structure, helper scripts, git identity"
    printf "  %-25s %s\n" "macos-defaults"      "Dock, Finder, keyboard, screenshots, Touch ID, DNS"
    printf "  %-25s %s\n" "shell"               "~/.zshrc, Brewfile export"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "setup-dev-tools.sh v${SCRIPT_VERSION}"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
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

brew_install() {
    local formula="$1"
    local name="${2:-$1}"
    progress
    if [[ "$DRY_RUN" == "true" ]]; then
        if brew list "$formula" &>/dev/null 2>&1; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if brew list "$formula" &>/dev/null 2>&1; then
        warn "$name already installed"
    else
        info "Installing $name..."
        if brew install "$formula" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
        else
            error "Failed to install $name"
        fi
    fi
}

brew_cask_install() {
    local cask="$1"
    local name="${2:-$1}"
    progress
    if [[ "$DRY_RUN" == "true" ]]; then
        if brew list --cask "$cask" &>/dev/null 2>&1; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if brew list --cask "$cask" &>/dev/null 2>&1; then
        warn "$name already installed"
    else
        info "Installing $name..."
        if brew install --cask "$cask" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
        else
            error "Failed to install $name (cask may have been renamed)"
        fi
    fi
}

npm_global_install() {
    local pkg="$1"
    local name="${2:-$1}"
    progress
    if [[ "$DRY_RUN" == "true" ]]; then
        if npm list -g "$pkg" &>/dev/null 2>&1; then
            warn "[DRY RUN] $name — already installed"
        else
            info "[DRY RUN] Would install: $name"
        fi
        return 0
    fi
    if npm list -g "$pkg" &>/dev/null 2>&1; then
        warn "$name already installed globally"
    else
        info "Installing $name globally..."
        if npm install -g "$pkg" >> "$LOG_FILE" 2>&1; then
            success "$name installed"
        else
            error "Failed to install $name"
        fi
    fi
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
        read -p "Continue anyway? [y/N] " confirm
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
    local free_space
    free_space=$(df -g "$HOME" | tail -1 | awk '{print $4}')
    if [[ "$free_space" -lt 15 ]]; then
        error "Low disk space: ${free_space}GB free (15GB+ recommended)"
        read -p "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        success "Disk space: ${free_space}GB free"
    fi

    # Admin check (some steps need sudo)
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
}

# =============================================================================
# Main
# =============================================================================

echo ""
echo -e "${BOLD}${MAGENTA}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║           macOS Dev Environment Setup v${SCRIPT_VERSION}              ║"
echo "  ║                                                              ║"
echo "  ║  191 tools · 50+ configs · Dracula theme · macOS defaults   ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Don't exit on error — we count failures instead
set +e

preflight

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

# Rosetta 2 (Apple Silicon compatibility for x86 tools)
if [[ "$(uname -m)" == "arm64" ]]; then
    if /usr/bin/pgrep -q oahd; then
        warn "Rosetta 2 already installed"
    else
        info "Installing Rosetta 2 for Apple Silicon..."
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license
        success "Rosetta 2 installed"
    fi
else
    info "Intel Mac detected — Rosetta 2 not needed"
fi

# -----------------------------------------------------------------------------
# Homebrew
# -----------------------------------------------------------------------------
if ! installed brew; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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

# mas (Mac App Store CLI — install App Store apps from terminal)
brew_install "mas" "mas (Mac App Store CLI)"

# GNU coreutils (Linux-compatible sed, tar, awk, grep for script portability)
brew_install "coreutils" "coreutils (GNU core utilities)"
brew_install "gnu-sed" "gnu-sed (Linux-compatible sed)"
brew_install "gnu-tar" "gnu-tar (Linux-compatible tar)"
brew_install "gawk" "gawk (GNU awk)"
brew_install "findutils" "findutils (GNU find, xargs)"

# =============================================================================
if should_run "core"; then
banner "Core Development"

brew_install "nvm" "nvm (Node Version Manager)"

# Set up nvm and install latest LTS Node
export NVM_DIR="$HOME/.nvm"
if [[ -d "$(brew --prefix nvm)" ]]; then
    source "$(brew --prefix nvm)/nvm.sh" 2>/dev/null || true
fi
if installed nvm; then
    if ! nvm ls --no-colors 2>/dev/null | grep -q "lts"; then
        info "Installing latest Node.js LTS..."
        nvm install --lts
        nvm alias default lts/*
        success "Node.js LTS installed"
    else
        warn "Node.js LTS already installed"
    fi
fi

brew_install "pyenv" "pyenv (Python Version Manager)"
brew_install "python@3.12" "Python 3.12"
brew_install "jq" "jq (JSON processor)"
brew_install "httpie" "HTTPie (API client)"
brew_install "direnv" "direnv (per-project env vars)"
brew_install "watchman" "Watchman (file watcher)"
brew_install "cmake" "CMake"
brew_install "pkg-config" "pkg-config"

# Docker (OrbStack is faster alternative — both installed, pick your preference)
brew_cask_install "docker" "Docker Desktop"
brew_cask_install "orbstack" "OrbStack (faster Docker Desktop alternative — 2-5x less memory)"

# pnpm
if ! installed pnpm; then
    info "Installing pnpm..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    success "pnpm installed"
else
    warn "pnpm already installed"
fi

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

# Granted (multi-account credential switching)
if ! installed granted && ! installed assume; then
    info "Installing Granted (AWS SSO credential switching)..."
    brew tap common-fate/granted
    brew install granted
    success "Granted installed"
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
if should_run "security"; then
banner "Security & Secrets"

# Secret management
brew_install "git-secrets" "git-secrets (prevents committing AWS keys)"
brew_install "trufflehog" "trufflehog (scans repos for leaked credentials)"
brew_install "age" "age (modern file encryption)"
brew_install "sops" "sops (encrypt secrets in YAML/JSON, works with AWS KMS)"

# Initialize git-secrets for AWS patterns
if installed git-secrets; then
    info "Registering AWS patterns with git-secrets..."
    git secrets --register-aws --global 2>/dev/null || true
    success "git-secrets AWS patterns registered"
fi

# detect-secrets (Yelp's pre-commit secret detection)
# detect-secrets (Yelp) — pip package, not brew
if installed pip3; then
    if pip3 show detect-secrets &>/dev/null 2>&1; then
        warn "detect-secrets already installed"
    else
        info "Installing detect-secrets..."
        pip3 install detect-secrets >> "$LOG_FILE" 2>&1 || error "Failed to install detect-secrets"
    fi
fi

# Code & dependency security
brew_install "trivy" "trivy (container & IaC vulnerability scanning)"
brew_install "semgrep" "semgrep (static analysis — bugs & security issues)"
brew_install "cosign" "cosign (sign & verify container images)"

# snyk CLI
if ! installed snyk; then
    info "Installing Snyk CLI..."
    brew tap snyk/tap 2>/dev/null || true
    brew install snyk 2>/dev/null || true
    success "Snyk CLI installed"
else
    warn "Snyk CLI already installed"
fi

# Network security
brew_install "mkcert" "mkcert (local HTTPS certs for dev)"
brew_cask_install "wireshark" "Wireshark (network packet analysis)"
brew_install "ssh-audit" "ssh-audit (audit SSH server/client config)"

# Endpoint & system security (Objective-See tools)
brew_cask_install "blockblock" "BlockBlock (alerts on persistent installs)"
brew_cask_install "oversight" "OverSight (mic/camera activation alerts)"
brew_cask_install "knockknock" "KnockKnock (shows persistently installed software)"
brew_cask_install "reikey" "ReiKey (detects keyboard event taps / keyloggers)"

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
if defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null | grep -q "[12]"; then
    warn "macOS Firewall is already enabled"
else
    info "macOS Firewall is NOT enabled"
    echo "  -> Enable it: System Settings > Network > Firewall > Turn On"
fi

# Install local CA for mkcert
if installed mkcert; then
    info "Installing local CA for mkcert (enables trusted localhost HTTPS)..."
    mkcert -install 2>/dev/null || true
    success "mkcert local CA installed"
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
info "delta (replaces diff — already installed in Git section)"

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

# dig -> dog: colorized DNS, supports DoH/DoT
brew_install "dog" "dog (replaces dig — colorized DNS, DoH support)"

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

# rm -> trash: moves to macOS Trash instead of permanent delete
brew_install "trash" "trash (replaces rm — moves to macOS Trash, recoverable)"

# diff (code-aware) -> difftastic: structural diff that understands syntax
brew_install "difftastic" "difftastic (replaces diff for code — syntax-aware structural diffs)"

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

fi  # code-quality

# =============================================================================
if should_run "perf-testing"; then
banner "Performance & Load Testing"

brew_install "hyperfine" "hyperfine (command benchmarking)"
brew_install "oha" "oha (HTTP load testing, Rust-based)"

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

brew_install "glow" "glow (render Markdown in terminal)"
brew_install "entr" "entr (run commands when files change)"
brew_install "pv" "pv (pipe viewer — progress bars for pipes)"
brew_install "parallel" "parallel (GNU parallel — run commands in parallel)"
brew_install "asciinema" "asciinema (record & share terminal sessions)"
brew_install "topgrade" "topgrade (update everything — brew, npm, pip, macOS, all at once)"
brew_install "fastfetch" "fastfetch (quick system info display — faster neofetch)"
brew_install "nano" "nano (latest — better than macOS built-in)"

fi  # terminal-productivity

# =============================================================================
if should_run "k8s-github"; then
banner "Kubernetes & GitHub Extras"

brew_install "stern" "stern (multi-pod log tailing for k8s)"

# gh-dash (GitHub dashboard extension)
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-dash"; then
        warn "gh-dash already installed"
    else
        info "Installing gh-dash (GitHub dashboard)..."
        gh extension install dlvhdr/gh-dash 2>/dev/null || true
        success "gh-dash installed (run: gh dash)"
    fi
fi

fi  # k8s-github

# =============================================================================
if should_run "database"; then
banner "Database & Data"

brew_install "pgcli" "pgcli (auto-completing Postgres CLI)"
brew_install "mycli" "mycli (auto-completing MySQL CLI)"
brew_install "usql" "usql (universal SQL CLI)"
brew_install "dbmate" "dbmate (lightweight DB migrations)"
brew_cask_install "tableplus" "TablePlus (native DB GUI — daily driver)"
brew_cask_install "dbeaver-community" "DBeaver Community (advanced SQL, 100+ DB support)"

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

brew_cask_install "bruno" "Bruno (open-source API client, git-friendly)"
brew_install "grpcurl" "grpcurl (curl for gRPC)"

fi  # api

# =============================================================================
if should_run "networking"; then
banner "Networking & Debugging"

brew_install "mtr" "mtr (combines ping + traceroute)"
brew_install "bandwhich" "bandwhich (real-time bandwidth by process)"
brew_install "nmap" "nmap (network scanning)"

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
brew_install "mise" "mise (universal version manager — nvm + pyenv + rbenv in one)"

# Editors & terminals
brew_cask_install "visual-studio-code" "VS Code"
brew_cask_install "cursor" "Cursor (AI-native code editor — VS Code fork with built-in AI)"
brew_cask_install "warp" "Warp terminal"
brew_cask_install "iterm2" "iTerm2 (classic terminal, tmux integration)"
brew_install "tmux" "tmux (terminal multiplexer)"

# AI tools
# Claude Code (installed via npm, not brew)
if installed npm; then
    npm_global_install "@anthropic-ai/claude-code" "Claude Code (AI-assisted coding in terminal)"
fi
# GitHub Copilot CLI (installed as gh extension)
if installed gh; then
    if gh extension list 2>/dev/null | grep -q "gh-copilot"; then
        warn "GitHub Copilot CLI already installed"
    else
        info "Installing GitHub Copilot CLI..."
        gh extension install github/gh-copilot 2>/dev/null || true
        success "GitHub Copilot CLI installed (run: gh copilot suggest)"
    fi
fi

# Productivity apps
brew_cask_install "raycast" "Raycast (Spotlight replacement with extensions)"
brew_cask_install "rectangle" "Rectangle (window management keyboard shortcuts)"

# Dotfile management
brew_install "chezmoi" "chezmoi (dotfile manager — backup/restore configs across machines)"

# HTTP debugging
brew_cask_install "proxyman" "Proxyman (native macOS HTTP debugging proxy)"

# Node/JS tooling (via npm)
if installed npm; then
    npm_global_install "typescript" "TypeScript"
    npm_global_install "tsx" "tsx (TS execute)"
    npm_global_install "turbo" "Turborepo"
fi

# fzf key bindings
if [[ ! -f "$HOME/.fzf.zsh" ]] && installed fzf; then
    info "Setting up fzf key bindings..."
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
    success "fzf key bindings configured"
fi

fi  # dx

# =============================================================================
if should_run "ui"; then
banner "UI Development"

if installed npm; then
    npm_global_install "storybook" "Storybook CLI"
    npm_global_install "playwright" "Playwright"
fi

# Chrome
brew_cask_install "google-chrome" "Google Chrome"

fi  # ui

# =============================================================================
if should_run "ux"; then
banner "UX & Design"

brew_cask_install "figma" "Figma"

# Lighthouse (via npm)
if installed npm; then
    npm_global_install "lighthouse" "Lighthouse CLI"
fi

fi  # ux

# =============================================================================
if should_run "docs"; then
banner "Documentation & Diagrams"

brew_install "d2" "d2 (code-to-diagram scripting language)"

if installed npm; then
    npm_global_install "@mermaid-js/mermaid-cli" "Mermaid CLI (render diagrams from CLI)"
fi

fi  # docs

# =============================================================================
if should_run "mac-system"; then
banner "Mac Apps — System & Utilities"

brew_cask_install "appcleaner" "AppCleaner (full app uninstaller)"
brew_cask_install "the-unarchiver" "The Unarchiver (any archive format)"
brew_cask_install "stats" "Stats (menubar system monitor)"
brew_cask_install "bartender" "Bartender (menubar icon manager)"
# Amphetamine is Mac App Store only — install via mas
if installed mas; then
    if mas list 2>/dev/null | grep -q "937984704"; then
        warn "Amphetamine already installed"
    else
        info "Installing Amphetamine from Mac App Store..."
        mas install 937984704 >> "$LOG_FILE" 2>&1 || error "Failed to install Amphetamine (sign into App Store first)"
    fi
fi
brew_cask_install "alt-tab" "AltTab (Windows-style window switcher)"
brew_cask_install "dato" "Dato (menubar clock with calendar/timezones)"
brew_cask_install "maccy" "Maccy (clipboard manager)"
brew_cask_install "lulu" "LuLu (outbound firewall)"
brew_cask_install "protonvpn" "Proton VPN"
brew_cask_install "proton-mail" "Proton Mail"
brew_cask_install "proton-pass" "Proton Pass (password manager)"
brew_cask_install "proton-drive" "Proton Drive (encrypted cloud storage)"

# Quick Look plugins (preview files in Finder with spacebar)
brew_cask_install "qlmarkdown" "QLMarkdown (preview Markdown in Finder)"
brew_cask_install "syntax-highlight" "Syntax Highlight (preview code files in Finder)"
brew_cask_install "qlstephen" "QLStephen (preview plain text files without extension)"
brew_cask_install "quicklook-json" "QuickLookJSON (preview JSON in Finder)"

fi  # mac-system

# =============================================================================
if should_run "mac-productivity"; then
banner "Mac Apps — Productivity"

brew_cask_install "notion" "Notion (docs, wikis, project tracking)"
brew_cask_install "notion-calendar" "Notion Calendar"
brew_cask_install "notion-mail" "Notion Mail"
brew_cask_install "cleanshot-x" "CleanShot X (screenshots & recording)"
brew_cask_install "shottr" "Shottr (free screenshot tool, pixel measuring, OCR)"
brew_cask_install "numi" "Numi (natural language calculator notepad)"
brew_cask_install "soulver" "Soulver 3 (smart calculator/spreadsheet hybrid)"
brew_cask_install "espanso" "Espanso (open-source text expander — snippets, templates)"
brew_cask_install "hazel" "Hazel (automated file organization rules)"
brew_cask_install "popclip" "PopClip (text actions on select — copy, search, format)"
brew_cask_install "yoink" "Yoink (drag and drop shelf — stage files between apps)"
brew_cask_install "raindropio" "Raindrop.io (bookmark manager — collections, tags, search)"

# File transfer
brew_cask_install "transmit" "Transmit (fast SFTP/S3 client, dual-pane)"
brew_cask_install "cyberduck" "Cyberduck (free SFTP/S3 client, Cryptomator, CLI)"

fi  # mac-productivity

# =============================================================================
if should_run "mac-communication"; then
banner "Mac Apps — Communication"

brew_cask_install "slack" "Slack"
brew_cask_install "discord" "Discord"
brew_cask_install "telegram" "Telegram"
brew_cask_install "signal" "Signal (end-to-end encrypted messaging)"

fi  # mac-communication

# =============================================================================
if should_run "mac-browsers"; then
banner "Mac Apps — Browsers"

brew_cask_install "firefox" "Firefox"
brew_cask_install "arc" "Arc (modern Chromium browser)"
brew_cask_install "brave-browser" "Brave Browser (privacy-focused Chromium)"

fi  # mac-browsers

# =============================================================================
if should_run "mac-media"; then
banner "Mac Apps — Media"

brew_cask_install "iina" "IINA (modern video player)"
brew_cask_install "imageoptim" "ImageOptim (lossless image compression)"
brew_cask_install "gifski" "Gifski (video to high-quality GIF)"
brew_cask_install "keka" "Keka (file archiver/compressor)"
brew_cask_install "libreoffice" "LibreOffice (free office suite)"
brew_cask_install "pocket-casts" "Pocket Casts (podcast player)"
brew_cask_install "hand-mirror" "Hand Mirror (quick webcam check from menubar)"

fi  # mac-media

# =============================================================================
if should_run "mac-cloud"; then
banner "Mac Apps — Cloud Storage"

brew_cask_install "google-drive" "Google Drive (cloud storage with Docs/Sheets)"

fi  # mac-cloud

# =============================================================================
if should_run "mac-focus"; then
banner "Mac Apps — Focus & Learning"

brew_cask_install "flow" "Flow (Pomodoro timer in menubar)"
brew_cask_install "anki" "Anki (spaced repetition flashcards)"
brew_cask_install "reeder" "Reeder (RSS reader — blogs, releases, changelogs)"

fi  # mac-focus

# =============================================================================
if should_run "mac-disk"; then
banner "Mac Apps — Disk & File Utilities"

brew_cask_install "daisydisk" "DaisyDisk (visual disk space analyzer)"

fi  # mac-disk

# =============================================================================
if should_run "dracula"; then
banner "Dracula Theme"

# VS Code - Dracula theme
if installed code; then
    if code --list-extensions 2>/dev/null | grep -qi "dracula-theme.theme-dracula"; then
        warn "VS Code Dracula theme already installed"
    else
        info "Installing Dracula theme for VS Code..."
        code --install-extension dracula-theme.theme-dracula
        success "VS Code Dracula theme installed"
    fi
fi

# bat (Dracula is built-in, just needs to be set)
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

# delta (git diffs) - Dracula colors
if git config --global delta.syntax-theme &>/dev/null; then
    warn "delta syntax theme already set"
else
    info "Setting delta to Dracula theme..."
    git config --global delta.syntax-theme Dracula
    success "delta Dracula theme configured"
fi

# iTerm2 Dracula theme
DRACULA_ITERM_DIR="$HOME/.dracula-iterm"
if [[ -d "$DRACULA_ITERM_DIR" ]]; then
    warn "iTerm2 Dracula theme already downloaded"
else
    info "Downloading Dracula theme for iTerm2..."
    git clone https://github.com/dracula/iterm.git "$DRACULA_ITERM_DIR" 2>/dev/null || true
    success "iTerm2 Dracula theme downloaded to $DRACULA_ITERM_DIR"
    echo "  -> Open iTerm2 > Preferences > Profiles > Colors > Import from $DRACULA_ITERM_DIR"
fi

# Warp Dracula theme (built-in, just print instructions)
if brew list --cask warp &>/dev/null 2>&1; then
    info "Warp has Dracula built-in: Settings > Appearance > Theme > Dracula"
fi

# fzf Dracula colors
FZF_DRACULA='export FZF_DEFAULT_OPTS="--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"'

# Starship Dracula palette
STARSHIP_CONFIG="$HOME/.config/starship.toml"
if [[ -f "$STARSHIP_CONFIG" ]] && grep -q "dracula" "$STARSHIP_CONFIG" 2>/dev/null; then
    warn "Starship Dracula palette already configured"
else
    info "Adding Dracula palette to Starship config..."
    mkdir -p "$(dirname "$STARSHIP_CONFIG")"
    cat >> "$STARSHIP_CONFIG" <<'STARSHIP_DRACULA'

# Dracula color palette
palette = "dracula"

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

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
STARSHIP_DRACULA
    success "Starship Dracula palette configured"
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

# Vi mode for copy
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "pbcopy"

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
TMUX_CONFIG
    success "tmux configured at $TMUX_CONF"
fi

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

# Useful aliases
git config --global alias.st "status -sb"
git config --global alias.co "checkout"
git config --global alias.br "branch"
git config --global alias.ci "commit"
git config --global alias.unstage "reset HEAD --"
git config --global alias.last "log -1 HEAD"
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.amend "commit --amend --no-edit"
git config --global alias.wip "!git add -A && git commit -m 'WIP'"

success "git global settings configured"

# ---- GPG + pinentry-mac ----
GPG_AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"
if [[ -f "$GPG_AGENT_CONF" ]] && grep -q "pinentry-mac" "$GPG_AGENT_CONF" 2>/dev/null; then
    warn "GPG pinentry-mac already configured"
else
    info "Configuring GPG to use pinentry-mac..."
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    PINENTRY_PATH="$(brew --prefix)/bin/pinentry-mac"
    cat > "$GPG_AGENT_CONF" <<GPG_CONFIG
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
if [[ -f "$ARIA2_CONFIG" ]]; then
    warn "aria2 config already exists"
else
    info "Creating aria2 configuration..."
    mkdir -p "$ARIA2_CONFIG_DIR"
    cat > "$ARIA2_CONFIG" <<'ARIA2_CONF'
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
user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36

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
    sed -i '' "s|PLACEHOLDER_HOME|$HOME|g" "$ARIA2_CONFIG"
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

# Search mode: prefix, fulltext, fuzzy, skim
search_mode = "fuzzy"

# Filter mode when pressing up arrow
filter_mode = "host"

# Inline search height (number of results)
inline_height = 20

# Show preview of full command
show_preview = true

# Timestamp format
style = "compact"

# Don't sync to atuin server (local only)
auto_sync = false

# Store in plaintext locally (faster)
# Set to true and configure sync_address if you want cross-machine sync
daemon.enabled = false
ATUIN_CONF
    success "atuin configured (fuzzy search, local-only)"
fi

# ---- lazygit Dracula theme ----
LAZYGIT_CONFIG_DIR="$HOME/Library/Application Support/lazygit"
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
LAZYGIT_CONF
    success "lazygit Dracula theme configured"
fi

# ---- k9s Dracula skin ----
K9S_SKINS_DIR="$HOME/Library/Application Support/k9s/skins"
K9S_CONFIG_DIR="$HOME/Library/Application Support/k9s"
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

    # Set dracula as active skin in k9s config
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
VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
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
    "editor.fontFamily": "'JetBrains Mono', 'Fira Code', Menlo, monospace",
    "editor.fontSize": 14,
    "editor.lineHeight": 1.6,
    "editor.fontLigatures": true,
    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": "active",
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
    "files.autoSave": "onFocusChange",
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "terminal.integrated.fontFamily": "'JetBrains Mono', 'MesloLGS NF', monospace",
    "terminal.integrated.fontSize": 13,
    "explorer.confirmDragAndDrop": false,
    "explorer.confirmDelete": false,
    "breadcrumbs.enabled": true,
    "telemetry.telemetryLevel": "off"
}
VSCODE_CONF
    success "VS Code settings configured with Dracula theme"
fi

# ---- VS Code essential extensions ----
if installed code; then
    info "Installing VS Code extensions..."
    VSCODE_EXTENSIONS=(
        "esbenp.prettier-vscode"
        "dbaeumer.vscode-eslint"
        "bradlc.vscode-tailwindcss"
        "formulahendry.auto-rename-tag"
        "christian-kohler.path-intellisense"
        "usernamehw.errorlens"
        "eamodio.gitlens"
        "github.copilot"
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
if [[ -f "$SHELLCHECK_RC" ]]; then
    warn "shellcheck config already exists"
else
    info "Creating shellcheck configuration..."
    cat > "$SHELLCHECK_RC" <<'SHELLCHECK_CONF'
# Follow sourced files
external-sources=true

# Disable common false positives
# SC1091: Not following sourced file (not input)
# SC2034: Variable appears unused (often used in sourced files)
disable=SC1091,SC2034
SHELLCHECK_CONF
    success "shellcheck configured"
fi

# ---- glow config (Dracula) ----
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
    success "glow configured (Dracula style, mouse, pager)"
fi

# ---- ngrok config ----
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
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
    success "ngrok config created (add authtoken: ngrok config add-authtoken <TOKEN>)"
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
fi

# ---- difftastic config (via git aliases, not global — delta stays as default) ----
info "Configuring difftastic git aliases..."
# Don't set diff.external globally — that would override delta as the default pager.
# Instead, provide aliases to opt-in to difftastic when needed.
git config --global alias.dft "!git -c diff.external=difft diff"
git config --global alias.dfl "!git -c diff.external=difft log -p --ext-diff"
success "difftastic aliases configured (use 'git dft' for syntax-aware diff, 'git dfl' for log)"

# ---- caddy config ----
CADDY_CONFIG_DIR="$HOME/.config/caddy"
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

# ---- act config (GitHub Actions local runner) ----
ACT_CONFIG="$HOME/.actrc"
if [[ -f "$ACT_CONFIG" ]]; then
    warn "act config already exists"
else
    info "Creating act configuration..."
    cat > "$ACT_CONFIG" <<'ACT_CONF'
# act configuration (run GitHub Actions locally)

# Use medium-sized Ubuntu image (good balance of speed vs compatibility)
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=catthehacker/ubuntu:act-20.04

# Reuse containers between runs (faster)
--reuse
ACT_CONF
    success "act configured (medium Ubuntu images, container reuse)"
fi

# ---- miller config ----
MLR_CONFIG="$HOME/.mlrrc"
if [[ -f "$MLR_CONFIG" ]]; then
    warn "miller config already exists"
else
    info "Creating miller configuration..."
    cat > "$MLR_CONFIG" <<'MLR_CONF'
# miller (mlr) configuration
# Default output format: pretty-printed table
--opprint
# Use CSV for input by default
--icsv
# Allow comments in data files
--skip-trivial-records
MLR_CONF
    success "miller configured (CSV input, pretty table output)"
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
fi

# ---- stern config ----
STERN_CONFIG="$HOME/.config/stern/config.yaml"
if [[ -f "$STERN_CONFIG" ]]; then
    warn "stern config already exists"
else
    info "Creating stern configuration..."
    mkdir -p "$(dirname "$STERN_CONFIG")"
    cat > "$STERN_CONFIG" <<'STERN_CONF'
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
fi

# ---- hyperfine (no config file, but add shell function) ----
info "hyperfine: no config needed (usage: hyperfine 'command1' 'command2')"

# ---- oha (no config file) ----
info "oha: no config needed (usage: oha -n 1000 -c 50 http://localhost:3000)"

# ---- entr (no config file) ----
info "entr: no config needed (usage: find . -name '*.ts' | entr -r npm test)"

# ---- pv (no config file) ----
info "pv: no config needed (usage: pv largefile.tar.gz | tar xz)"

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
    # Create sockets directory for multiplexing
    mkdir -p "$HOME/.ssh/sockets"
    chmod 600 "$SSH_CONFIG"
    success "SSH configured (multiplexing, keychain, keep-alive, strong algorithms)"
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
# VS Code
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
    git config --global core.excludesfile "$GLOBAL_GITIGNORE"
    success "Global .gitignore created and registered with git"
fi

# ---- .npmrc ----
NPMRC="$HOME/.npmrc"
if [[ -f "$NPMRC" ]]; then
    warn ".npmrc already exists"
else
    info "Creating .npmrc..."
    cat > "$NPMRC" <<'NPMRC_CONF'
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
fi

# ---- .editorconfig ----
EDITORCONFIG="$HOME/.editorconfig"
if [[ -f "$EDITORCONFIG" ]]; then
    warn ".editorconfig already exists"
else
    info "Creating global .editorconfig..."
    cat > "$EDITORCONFIG" <<'EDITORCONFIG_CONF'
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
    success ".prettierrc created (single quotes, trailing commas, 100 width)"
fi

# ---- .curlrc ----
CURLRC="$HOME/.curlrc"
if [[ -f "$CURLRC" ]]; then
    warn ".curlrc already exists"
else
    info "Creating .curlrc..."
    cat > "$CURLRC" <<'CURLRC_CONF'
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
fi

# ---- Docker daemon config ----
DOCKER_CONFIG_DIR="$HOME/.docker"
DOCKER_DAEMON="$DOCKER_CONFIG_DIR/daemon.json"
if [[ -f "$DOCKER_DAEMON" ]]; then
    warn "Docker daemon.json already exists"
else
    info "Creating Docker daemon configuration..."
    mkdir -p "$DOCKER_CONFIG_DIR"
    cat > "$DOCKER_DAEMON" <<'DOCKER_CONF'
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
    success "Docker configured (BuildKit, log rotation 10m x 3, garbage collection)"
fi

# ---- macOS System Defaults ----
info "Configuring macOS system defaults..."

# -- Dock --
# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true
# Remove auto-hide delay
defaults write com.apple.dock autohide-delay -float 0
# Faster auto-hide animation
defaults write com.apple.dock autohide-time-modifier -float 0.3
# Smaller Dock icon size
defaults write com.apple.dock tilesize -integer 40
# Don't show recent applications
defaults write com.apple.dock show-recents -bool false
# Minimize windows using scale effect (faster than genie)
defaults write com.apple.dock mineffect -string "scale"
# Minimize windows into their application icon
defaults write com.apple.dock minimize-to-application -bool true
success "Dock configured (auto-hide, small icons, no recents, scale effect)"

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

# -- Hot Corners --
# Top-left: Mission Control (value 2)
defaults write com.apple.dock wvous-tl-corner -int 2
defaults write com.apple.dock wvous-tl-modifier -int 0
# Top-right: Desktop (value 4)
defaults write com.apple.dock wvous-tr-corner -int 4
defaults write com.apple.dock wvous-tr-modifier -int 0
# Bottom-left: disabled (value 1)
defaults write com.apple.dock wvous-bl-corner -int 1
defaults write com.apple.dock wvous-bl-modifier -int 0
# Bottom-right: disabled (value 1)
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-br-modifier -int 0
success "Hot corners configured (TL: Mission Control, TR: Desktop)"

# -- Safari --
# Enable Developer menu
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true
# Show full URL in address bar
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
success "Safari configured (developer menu, full URL)"

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

# -- Misc --
# Disable the "Are you sure you want to open this application?" dialog
defaults write com.apple.LaunchServices LSQuarantine -bool false
# Disable Notification Center and remove from menu bar (restart required)
# Expand save panel by default (already set in Finder section but ensuring global)
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
# Show battery percentage in menu bar
defaults write com.apple.menuextra.battery ShowPercent -string "YES" 2>/dev/null || true
# Set highlight color to Dracula purple
defaults write NSGlobalDomain AppleHighlightColor -string "0.741176 0.576471 0.976471 Purple"
success "Misc macOS defaults configured"

# Restart Dock to apply all Dock/Hot Corner/Mission Control changes
killall Dock 2>/dev/null || true

# ---- ~/.hushlogin (suppress "Last login" message) ----
if [[ -f "$HOME/.hushlogin" ]]; then
    warn "~/.hushlogin already exists"
else
    touch "$HOME/.hushlogin"
    success "~/.hushlogin created (suppresses 'Last login' in terminal)"
fi

# ---- ~/.zprofile (login shell — PATH set once, not on every subshell) ----
ZPROFILE="$HOME/.zprofile"
if [[ -f "$ZPROFILE" ]]; then
    warn "~/.zprofile already exists"
else
    info "Creating ~/.zprofile..."
    cat > "$ZPROFILE" <<'ZPROFILE_CONF'
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

# Go
export GOPATH="$HOME/.local/share/go"
export PATH="$GOPATH/bin:$PATH"

# Rust
if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi
ZPROFILE_CONF
    success "~/.zprofile created (editor, pager, LESS, XDG, language)"
fi

# ---- ~/.vimrc (basic vim config for server editing) ----
VIMRC="$HOME/.vimrc"
if [[ -f "$VIMRC" ]]; then
    warn "~/.vimrc already exists"
else
    info "Creating basic ~/.vimrc..."
    cat > "$VIMRC" <<'VIM_CONF'
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
    mkdir -p "$HOME/.vim/undodir"
    success "~/.vimrc created (line numbers, clipboard, mouse, Dracula colors, space leader)"
fi

# ---- ~/.nanorc (better nano for quick edits) ----
NANORC="$HOME/.nanorc"
if [[ -f "$NANORC" ]]; then
    warn "~/.nanorc already exists"
else
    info "Creating ~/.nanorc..."
    cat > "$NANORC" <<'NANO_CONF'
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
    sed -i '' "s|PLACEHOLDER_BREW_PREFIX|$(brew --prefix)|g" "$NANORC"
    success "~/.nanorc created (line numbers, auto-indent, mouse, syntax highlighting)"
fi

# ---- bat extended config (file type mappings) ----
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

# ---- mise global config (default tool versions) ----
MISE_CONFIG="$HOME/.config/mise/config.toml"
if [[ -f "$MISE_CONFIG" ]]; then
    warn "mise global config already exists"
else
    info "Creating mise global configuration..."
    mkdir -p "$HOME/.config/mise"
    cat > "$MISE_CONFIG" <<'MISE_CONF'
# mise global tool versions
# Docs: https://mise.jdx.dev/
# These are defaults — per-project .mise.toml takes precedence

[tools]
# Uncomment and set versions as needed:
# node = "lts"
# python = "3.12"
# go = "latest"
# rust = "latest"
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

# Disabled steps (uncomment to skip)
#[disable]
#system = ["mas"]
#system = ["firmware"]
TOPGRADE_CONF
    success "topgrade configured (cleanup, greedy cask updates)"
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
        "type": "builtin",
        "color": {
            "1": "magenta",
            "2": "cyan"
        }
    },
    "display": {
        "separator": "  ",
        "color": {
            "keys": "magenta"
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "shell",
        "terminal",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "battery",
        "separator",
        {
            "type": "command",
            "key": "Node",
            "text": "node --version 2>/dev/null || echo 'not installed'"
        },
        {
            "type": "command",
            "key": "Python",
            "text": "python3 --version 2>/dev/null | cut -d' ' -f2 || echo 'not installed'"
        },
        {
            "type": "command",
            "key": "Docker",
            "text": "docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'not running'"
        },
        "separator",
        "colors"
    ]
}
FASTFETCH_CONF
    success "fastfetch configured (system info + dev tool versions)"
fi

# ---- ripgrep config ----
RIPGREPRC="$HOME/.ripgreprc"
if [[ -f "$RIPGREPRC" ]]; then
    warn "~/.ripgreprc already exists"
else
    info "Creating ripgrep configuration..."
    cat > "$RIPGREPRC" <<'RG_CONF'
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
    success "~/.ripgreprc configured (smart-case, hidden files, custom types)"
fi

# ---- fd ignore ----
FDIGNORE="$HOME/.fdignore"
if [[ -f "$FDIGNORE" ]]; then
    warn "~/.fdignore already exists"
else
    info "Creating fd ignore patterns..."
    cat > "$FDIGNORE" <<'FD_CONF'
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
    success "~/.fdignore created"
fi

# ---- btop Dracula theme ----
BTOP_CONFIG_DIR="$HOME/.config/btop"
BTOP_CONFIG="$BTOP_CONFIG_DIR/btop.conf"
if [[ -f "$BTOP_CONFIG" ]]; then
    warn "btop config already exists"
else
    info "Creating btop configuration..."
    mkdir -p "$BTOP_CONFIG_DIR/themes"
    cat > "$BTOP_CONFIG" <<'BTOP_CONF'
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
    cat > "$BTOP_CONFIG_DIR/themes/dracula.theme" <<'BTOP_DRACULA'
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
fi

# ---- lazydocker Dracula config ----
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
    success "Git commit template created and registered"
fi

# ---- Global git hooks directory ----
GIT_HOOKS_DIR="$HOME/.config/git/hooks"
if [[ -d "$GIT_HOOKS_DIR" ]]; then
    warn "Global git hooks directory already exists"
else
    info "Creating global git hooks..."
    mkdir -p "$GIT_HOOKS_DIR"

    # Pre-commit hook: check for common issues
    cat > "$GIT_HOOKS_DIR/pre-commit" <<'HOOK_PRECOMMIT'
#!/usr/bin/env bash
# Global pre-commit hook — runs on ALL repos
# Per-repo .git/hooks/pre-commit takes precedence if it exists

# Check for debug statements
if git diff --cached --name-only | xargs grep -l 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null; then
    echo ""
    echo "WARNING: Debug statements found in staged files:"
    git diff --cached --name-only | xargs grep -n 'console\.log\|debugger\|binding\.pry\|import pdb' 2>/dev/null
    echo ""
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
    echo ""
    echo "WARNING: Large files detected (>5MB):"
    echo "$large_files"
    echo ""
    echo "Consider using git-lfs or commit with --no-verify to bypass."
    exit 1
fi

# Check for merge conflict markers
if git diff --cached --name-only | xargs grep -l '<<<<<<<\|=======\|>>>>>>>' 2>/dev/null; then
    echo ""
    echo "ERROR: Merge conflict markers found in staged files."
    exit 1
fi

exit 0
HOOK_PRECOMMIT
    chmod +x "$GIT_HOOKS_DIR/pre-commit"

    # Register global hooks directory
    git config --global core.hooksPath "$GIT_HOOKS_DIR"

    success "Global git hooks created (debug check, large file check, conflict markers)"
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
# GitHub CLI configuration
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
GH_CONF
    success "GitHub CLI configured (SSH protocol, VS Code editor, delta pager, aliases)"
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
fi

# ---- gemrc (Ruby) ----
GEMRC="$HOME/.gemrc"
if [[ -f "$GEMRC" ]]; then
    warn "~/.gemrc already exists"
else
    info "Creating gemrc..."
    cat > "$GEMRC" <<'GEM_CONF'
# Skip documentation when installing gems (saves time and disk)
gem: --no-document
GEM_CONF
    success "~/.gemrc created (no docs on gem install)"
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
fi

# ---- mycli config ----
MYCLIRC="$HOME/.myclirc"
if [[ -f "$MYCLIRC" ]]; then
    warn "~/.myclirc already exists"
else
    info "Creating mycli configuration..."
    cat > "$MYCLIRC" <<'MYCLI_CONF'
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
    success "~/.myclirc configured (multi-line, auto-expand, destructive warnings)"
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
fi

# ---- VS Code keybindings ----
VSCODE_KEYBINDINGS_DIR="$HOME/Library/Application Support/Code/User"
VSCODE_KEYBINDINGS="$VSCODE_KEYBINDINGS_DIR/keybindings.json"
if [[ -f "$VSCODE_KEYBINDINGS" ]]; then
    warn "VS Code keybindings already exist"
else
    info "Creating VS Code keybindings..."
    mkdir -p "$VSCODE_KEYBINDINGS_DIR"
    cat > "$VSCODE_KEYBINDINGS" <<'VSCODE_KEYS'
[
    // Toggle terminal
    {
        "key": "cmd+`",
        "command": "workbench.action.terminal.toggleTerminal"
    },
    // New terminal
    {
        "key": "cmd+shift+`",
        "command": "workbench.action.terminal.new"
    },
    // Split editor
    {
        "key": "cmd+\\",
        "command": "workbench.action.splitEditor"
    },
    // Navigate between editor groups
    {
        "key": "cmd+1",
        "command": "workbench.action.focusFirstEditorGroup"
    },
    {
        "key": "cmd+2",
        "command": "workbench.action.focusSecondEditorGroup"
    },
    {
        "key": "cmd+3",
        "command": "workbench.action.focusThirdEditorGroup"
    },
    // Go to file (quick open)
    {
        "key": "cmd+p",
        "command": "workbench.action.quickOpen"
    },
    // Go to symbol in file
    {
        "key": "cmd+shift+o",
        "command": "workbench.action.gotoSymbol"
    },
    // Go to symbol in workspace
    {
        "key": "cmd+t",
        "command": "workbench.action.showAllSymbols"
    },
    // Toggle sidebar
    {
        "key": "cmd+b",
        "command": "workbench.action.toggleSidebarVisibility"
    },
    // Toggle minimap
    {
        "key": "cmd+shift+m",
        "command": "editor.action.toggleMinimap"
    },
    // Fold/unfold code
    {
        "key": "cmd+shift+[",
        "command": "editor.fold"
    },
    {
        "key": "cmd+shift+]",
        "command": "editor.unfold"
    },
    // Move line up/down
    {
        "key": "alt+up",
        "command": "editor.action.moveLinesUpAction"
    },
    {
        "key": "alt+down",
        "command": "editor.action.moveLinesDownAction"
    },
    // Duplicate line
    {
        "key": "cmd+shift+d",
        "command": "editor.action.copyLinesDownAction"
    },
    // Delete line
    {
        "key": "cmd+shift+k",
        "command": "editor.action.deleteLines"
    },
    // Multi-cursor
    {
        "key": "cmd+d",
        "command": "editor.action.addSelectionToNextFindMatch"
    },
    // Select all occurrences
    {
        "key": "cmd+shift+l",
        "command": "editor.action.selectHighlights"
    },
    // Format document
    {
        "key": "cmd+shift+f",
        "command": "editor.action.formatDocument"
    },
    // Rename symbol
    {
        "key": "f2",
        "command": "editor.action.rename"
    },
    // Quick fix
    {
        "key": "cmd+.",
        "command": "editor.action.quickFix"
    },
    // Close tab
    {
        "key": "cmd+w",
        "command": "workbench.action.closeActiveEditor"
    },
    // Reopen closed tab
    {
        "key": "cmd+shift+t",
        "command": "workbench.action.reopenClosedEditor"
    }
]
VSCODE_KEYS
    success "VS Code keybindings created"
fi

# ---- Rectangle preferences ----
info "Configuring Rectangle..."
# Enable "almost maximize" (leaves small gap)
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float 0.95 2>/dev/null || true
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float 0.95 2>/dev/null || true
# Enable gaps between windows (8px)
defaults write com.knollsoft.Rectangle gapSize -float 8 2>/dev/null || true
# Enable snap on drag
defaults write com.knollsoft.Rectangle windowSnapping -int 2 2>/dev/null || true
success "Rectangle configured (almost maximize, 8px gaps, snap on drag)"

# Set RIPGREP_CONFIG_PATH in zshrc (needed for ripgrep to read config)
# This will be in the managed block below

# ---- Espanso config (text expander) ----
ESPANSO_CONFIG_DIR="$HOME/Library/Application Support/espanso/match"
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
ESPANSO_CONF
    success "Espanso configured (dates, dev shortcuts, Markdown, git snippets)"
fi

# ---- Hazel config note ----
if brew list --cask hazel &>/dev/null 2>&1; then
    info "Hazel tip: Set up rules for ~/Downloads (auto-sort by file type, clean old files)"
    echo "  Suggested rules:"
    echo "    - Move .dmg/.pkg to ~/Downloads/Installers after 1 day"
    echo "    - Move .pdf to ~/Documents after 1 day"
    echo "    - Move screenshots to ~/Screenshots"
    echo "    - Trash files older than 30 days"
fi

# ---- Filesystem Structure ----
info "Setting up filesystem structure..."

# Code directories
DIRS=(
    "$HOME/Code/work"
    "$HOME/Code/work/scratch"
    "$HOME/Code/personal"
    "$HOME/Code/personal/scratch"
    "$HOME/Code/oss"
    "$HOME/Code/learning/courses"
    "$HOME/Code/learning/playground"
    "$HOME/Documents/design"
    "$HOME/Documents/contracts"
    "$HOME/Documents/receipts"
    "$HOME/Screenshots"
    "$HOME/Scripts/bin"
    "$HOME/Scripts/cron"
)
for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done
success "Directory structure created (~/Code, ~/Scripts, ~/Screenshots, ~/Documents)"

# ---- Helper Scripts ----
info "Creating helper scripts in ~/Scripts/bin..."

# -- clean-downloads: delete files older than 30 days --
cat > "$HOME/Scripts/bin/clean-downloads" <<'SCRIPT'
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

read -p "Delete these $count files? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    find "$DIR" -maxdepth 1 -type f -mtime +"$DAYS" -exec trash {} \;
    echo "Moved $count files to Trash."
else
    echo "Cancelled."
fi
SCRIPT

# -- new-project: scaffold a new project --
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

# Initial commit
git add -A
git commit -m "Initial project scaffold"

echo ""
echo "Project created at: $PROJECT_DIR"
echo "  cd $PROJECT_DIR"
SCRIPT

# -- clone-work: clone a work repo into the right directory --
cat > "$HOME/Scripts/bin/clone-work" <<'SCRIPT'
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

echo ""
echo "Cloned to: $TARGET/$REPO"
echo "  cd $TARGET/$REPO"
SCRIPT

# -- clone-personal: clone a personal repo --
cat > "$HOME/Scripts/bin/clone-personal" <<'SCRIPT'
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

echo ""
echo "Cloned to: $TARGET"
echo "  cd $TARGET"
SCRIPT

# -- backup-dotfiles: push dotfiles to git via chezmoi --
cat > "$HOME/Scripts/bin/backup-dotfiles" <<'SCRIPT'
#!/usr/bin/env bash
# Backup dotfiles using chezmoi
# Usage: backup-dotfiles
set -euo pipefail

if ! command -v chezmoi &>/dev/null; then
    echo "chezmoi not installed. Run: brew install chezmoi"
    exit 1
fi

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
read -p "Commit and push? [y/N] " confirm
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
cat > "$HOME/Scripts/bin/project-stats" <<'SCRIPT'
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

# Make all scripts executable
chmod +x "$HOME/Scripts/bin/"*
success "Helper scripts created (clean-downloads, new-project, clone-work, clone-personal, backup-dotfiles, project-stats)"

# ---- Per-directory Git Config (work vs personal identity) ----
info "Setting up per-directory git config..."

GITCONFIG_WORK="$HOME/.gitconfig-work"
GITCONFIG_PERSONAL="$HOME/.gitconfig-personal"

if [[ -f "$GITCONFIG_WORK" ]]; then
    warn "~/.gitconfig-work already exists"
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
    success "~/.gitconfig-work created (fill in your work email)"
fi

if [[ -f "$GITCONFIG_PERSONAL" ]]; then
    warn "~/.gitconfig-personal already exists"
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
    success "~/.gitconfig-personal created (fill in your personal email)"
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

# ---- Empty Desktop Policy ----
# Create a .localized file to keep Desktop clean in Finder sidebar
info "Tip: Keep ~/Desktop empty — use Raycast/Spotlight to find files"

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
# Also tell mdutil to disable indexing for common dev paths
sudo mdutil -i off /usr/local 2>/dev/null || true
sudo mdutil -i off /opt/homebrew 2>/dev/null || true
success "Spotlight exclusions set (node_modules, caches, Homebrew)"

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
        sudo tmutil addexclusion "$dir" 2>/dev/null || true
    fi
done
# Also exclude common project-level directories via fixed-path exclusion
sudo tmutil addexclusion -p "$HOME/.docker" 2>/dev/null || true
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

# ---- macOS defaults for installed apps ----
info "Setting macOS defaults for apps..."

# Maccy: paste on select, launch at login, history size
defaults write org.p0deje.Maccy pasteByDefault true 2>/dev/null || true
defaults write org.p0deje.Maccy historySize 200 2>/dev/null || true
defaults write org.p0deje.Maccy launchAtLogin true 2>/dev/null || true
success "Maccy configured (paste on select, 200 history, launch at login)"

# AltTab: show windows from current space only
defaults write com.lwouis.alt-tab-macos spacesToShow 1 2>/dev/null || true
# Show minimized windows
defaults write com.lwouis.alt-tab-macos showMinimizedWindows 1 2>/dev/null || true
success "AltTab configured (current space only)"

# Rectangle: launch at login
defaults write com.knollsoft.Rectangle launchOnLogin true 2>/dev/null || true
success "Rectangle configured (launch at login)"

# iTerm2: don't display the annoying prompt when quitting
defaults write com.googlecode.iterm2 PromptOnQuit -bool false 2>/dev/null || true
success "iTerm2 configured (suppress quit prompt)"

fi  # configs

# =============================================================================
# CLAUDE CODE CONFIGURATION
# =============================================================================
banner "Claude Code Configuration"

# ---- Claude Code global settings ----
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    warn "Claude Code settings.json already exists"
else
    info "Creating Claude Code global settings..."
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
      "Bash(python3 *)",
      "Bash(pip *)",
      "Bash(cargo *)",
      "Bash(go *)",
      "Bash(make *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(rg *)",
      "Bash(fd *)",
      "Bash(tree *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(sort *)",
      "Bash(uniq *)",
      "Bash(cut *)",
      "Bash(awk *)",
      "Bash(sed *)",
      "Bash(jq *)",
      "Bash(yq *)",
      "Bash(curl *)",
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
      "Bash(wc -l *)",
      "Bash(du -sh *)",
      "Bash(date *)",
      "Bash(pwd)",
      "Bash(shellcheck *)",
      "Bash(shfmt *)",
      "Bash(prettier *)",
      "Bash(eslint *)",
      "Bash(tsc *)",
      "Bash(jest *)",
      "Bash(vitest *)",
      "Bash(playwright *)",
      "Bash(act *)",
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
      "*.min.js",
      "*.min.css",
      "package-lock.json",
      "pnpm-lock.yaml",
      "yarn.lock"
    ]
  }
}
CLAUDE_SETTINGS_CONF
    success "Claude Code settings.json created (permissions, file ignore patterns)"
fi

# ---- Claude Code global CLAUDE.md (memory/instructions) ----
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
    warn "Claude Code global CLAUDE.md already exists"
else
    info "Creating Claude Code global CLAUDE.md..."
    cat > "$CLAUDE_MD" <<'CLAUDE_MD_CONF'
# Global Development Standards

## Environment
- macOS with Homebrew
- Shell: zsh with starship prompt
- Editor: VS Code / Cursor
- Terminal: Warp / iTerm2
- Package managers: pnpm (preferred), npm
- Version managers: nvm (Node), pyenv (Python), mise (universal)
- Container runtime: Docker Desktop or OrbStack

## Code Standards
- Use TypeScript strict mode for all TS projects
- Use ESLint + Prettier for formatting (2-space indent, single quotes, trailing commas)
- Write tests alongside code (colocated, not in separate test dirs)
- Use conventional commit messages: type(scope): description
- Prefer named exports over default exports
- Use path aliases (@/ for src/) in TypeScript projects

## React / Next.js
- Functional components only — no class components
- React hooks for state and effects
- Next.js App Router (not Pages Router) for new projects
- Use server components by default, 'use client' only when needed
- Tailwind CSS + shadcn/ui for styling

## AWS / CDK
- CDK stacks in infrastructure/ directory
- Use L2/L3 constructs when available
- Always tag resources with project, environment, owner
- Use environment-specific config (dev/staging/prod)
- Follow least-privilege IAM principles

## Git Workflow
- Branch naming: feature/, fix/, chore/, docs/
- Squash merge to main
- Keep PRs small and focused (< 400 lines)
- Include tests with feature PRs

## File Organization
- Components: src/components/[Feature]/
- Utilities: src/lib/ or src/utils/
- Types: src/types/
- API routes: src/app/api/ (Next.js) or src/api/
- Tests: colocated with source (*.test.ts)
- CDK: infrastructure/lib/

## When Writing Code
- Prefer early returns over nested conditions
- Use descriptive variable names (no single letters except loop counters)
- Add JSDoc comments for public APIs and complex functions
- Handle errors explicitly — no silent catches
- Use async/await over .then() chains
- Use zod for runtime validation at API boundaries
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

    # Git rules
    cat > "$CLAUDE_RULES_DIR/git.md" <<'GIT_RULES'
# Git Rules

- Never force-push to main or master
- Never commit .env files, secrets, or credentials
- Always create a new branch for changes (never commit directly to main)
- Use conventional commit format: type(scope): description
- Keep commits atomic — one logical change per commit
- Run tests before committing
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

    success "Claude Code rules created (git, security, typescript)"
fi

# ---- Claude Code hooks ----
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
if [[ -d "$CLAUDE_HOOKS_DIR" ]]; then
    warn "Claude Code hooks directory already exists"
else
    info "Creating Claude Code hooks..."
    mkdir -p "$CLAUDE_HOOKS_DIR"

    # Post-edit hook: auto-format with prettier
    cat > "$CLAUDE_HOOKS_DIR/format-on-edit.sh" <<'HOOK_FORMAT'
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
    chmod +x "$CLAUDE_HOOKS_DIR/format-on-edit.sh"

    success "Claude Code hooks created (auto-format on edit)"
fi

# =============================================================================
if should_run "shell"; then
banner "Shell Configuration"

ZSHRC="$HOME/.zshrc"
ZSHRC_BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
ZSHRC_MANAGED_MARKER="# >>> dev-setup managed block >>>"
ZSHRC_MANAGED_END="# <<< dev-setup managed block <<<"

# Define the managed block content
MANAGED_BLOCK=$(cat <<'MANAGED_ZSHRC'
# >>> dev-setup managed block >>>
# This block is managed by setup-dev-tools.sh — edits may be overwritten on re-run.
# Add personal customizations OUTSIDE this block (above or below).

# -- PATH additions -----------------------------------------------------------

# Personal scripts
export PATH="$HOME/Scripts/bin:$PATH"

# -- Environment Variables ----------------------------------------------------

# ripgrep config path
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# -- Tool Initialization ------------------------------------------------------

# GNU coreutils (use Linux-compatible versions by default)
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
export PATH="$(brew --prefix gnu-sed)/libexec/gnubin:$PATH"
export PATH="$(brew --prefix gnu-tar)/libexec/gnubin:$PATH"
export PATH="$(brew --prefix gawk)/libexec/gnubin:$PATH"
export PATH="$(brew --prefix findutils)/libexec/gnubin:$PATH"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix nvm)/nvm.sh" ] && \. "$(brew --prefix nvm)/nvm.sh"
[ -s "$(brew --prefix nvm)/etc/bash_completion.d/nvm" ] && \. "$(brew --prefix nvm)/etc/bash_completion.d/nvm"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# mise (universal version manager — alternative to nvm/pyenv)
# Uncomment to use mise INSTEAD of nvm/pyenv above:
# eval "$(mise activate zsh)"

# direnv
eval "$(direnv hook zsh)"

# zoxide
eval "$(zoxide init zsh)"

# starship prompt
eval "$(starship init zsh)"

# atuin (replaces ctrl-r shell history)
eval "$(atuin init zsh)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# fzf Dracula colors
export FZF_DEFAULT_OPTS="--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"

# zsh plugins
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

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
alias dig="dog"
alias watch="viddy"
alias hexdump="hexyl"
alias rm="trash"

# Short aliases for modern tools (don't override builtins)
alias rg="rg"          # ripgrep (already the command name)
alias f="fd"           # fd (fast find)
alias sd="sd"          # sd (fast sed)
alias dft="difft"      # difftastic

# -- Download & Transfer ------------------------------------------------------
alias dl="aria2c"
alias wget="aria2c"

# -- Git & GitHub -------------------------------------------------------------
alias lg="lazygit"
alias ghd="gh dash"
alias gdft="git dft"
alias gha="act"

# -- Containers & Kubernetes --------------------------------------------------
alias lzd="lazydocker"
alias k="kubectl"
alias klog="stern"

# -- File Tools ---------------------------------------------------------------
alias md="glow"
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

# -- Dev & Testing ------------------------------------------------------------
alias watchrun="find . -name '*.ts' -o -name '*.tsx' | entr -r"
alias bench="hyperfine"
alias loadtest="oha"
alias par="parallel"
alias lint-sh="shellcheck"
alias fmt-sh="shfmt -w -i 4"

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

# -- System -------------------------------------------------------------------
alias update="topgrade"
alias sysinfo="fastfetch"

# <<< dev-setup managed block <<<
MANAGED_ZSHRC
)

if [[ -f "$ZSHRC" ]]; then
    if grep -q "$ZSHRC_MANAGED_MARKER" "$ZSHRC" 2>/dev/null; then
        info "Updating managed block in existing ~/.zshrc..."
        # Back up first
        cp "$ZSHRC" "$ZSHRC_BACKUP"
        # Remove old managed block and insert new one
        # Use awk to remove everything between markers and append new block
        awk -v marker="$ZSHRC_MANAGED_MARKER" -v end_marker="$ZSHRC_MANAGED_END" '
            $0 == marker { skip=1; next }
            $0 == end_marker { skip=0; next }
            !skip { print }
        ' "$ZSHRC_BACKUP" > "$ZSHRC"
        echo "" >> "$ZSHRC"
        echo "$MANAGED_BLOCK" >> "$ZSHRC"
        success "~/.zshrc managed block updated (backup: $ZSHRC_BACKUP)"
    else
        info "Appending managed block to existing ~/.zshrc..."
        cp "$ZSHRC" "$ZSHRC_BACKUP"
        echo "" >> "$ZSHRC"
        echo "$MANAGED_BLOCK" >> "$ZSHRC"
        success "~/.zshrc updated (backup: $ZSHRC_BACKUP)"
    fi
else
    info "Creating ~/.zshrc..."
    cat > "$ZSHRC" <<'ZSHRC_HEADER'
# =============================================================================
# ~/.zshrc — generated by setup-dev-tools.sh
# =============================================================================
# Add personal customizations OUTSIDE the managed block below.

ZSHRC_HEADER
    echo "$MANAGED_BLOCK" >> "$ZSHRC"
    success "~/.zshrc created"
fi

fi  # shell

# =============================================================================
banner "Export Brewfile"

BREWFILE_DIR="$HOME/.config/brewfile"
mkdir -p "$BREWFILE_DIR"
BREWFILE="$BREWFILE_DIR/Brewfile"

info "Exporting Brewfile snapshot..."
brew bundle dump --file="$BREWFILE" --force 2>/dev/null || true
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
echo "  [~/.tmux.conf]          tmux with Dracula theme"
echo "  [~/.npmrc]              save-exact, no telemetry"
echo "  [~/.editorconfig]       Cross-editor consistency"
echo "  [~/.prettierrc]         Global Prettier defaults"
echo "  [~/.curlrc]             Follow redirects, retry, compression"
echo "  [~/.docker/daemon.json] BuildKit, log rotation"
echo "  [~/.aria2/aria2.conf]   16 connections, auto-resume"
echo "  [~/.config/starship]    Dracula prompt"
echo "  [~/.config/atuin]       Fuzzy search, local-only"
echo "  [~/.config/glow]        Dracula Markdown renderer"
echo "  [~/.config/yt-dlp]      Best quality, aria2c downloader"
echo "  [~/.config/gh-dash]     GitHub dashboard, Dracula theme"
echo "  [~/.config/stern]       K8s log tailing"
echo "  [~/.config/brewfile]    Brewfile snapshot for reproducibility"
echo "  [VS Code]               Dracula theme, extensions, JetBrains Mono"
echo "  [lazygit]               Dracula theme, delta pager"
echo "  [k9s]                   Dracula skin"
echo "  [Finder]                Hidden files, path bar, list view"
echo "  [macOS]                 Dock, keyboard, screenshots, hot corners"
echo ""
info "Optional Chrome extensions to install manually:"
echo "  - axe DevTools (accessibility testing)"
echo "  - React Developer Tools"
echo "  - Lighthouse"
echo "  - JSON Formatter"
echo ""
info "Recommended Raycast extensions (install via Raycast Store):"
echo "  - Clipboard History (built-in)"
echo "  - GitHub (search repos, PRs, issues)"
echo "  - AWS (quick access to console services)"
echo "  - Docker (manage containers)"
echo "  - Notion (search Notion pages)"
echo "  - Brew (search & install packages)"
echo "  - Kill Process (fast process killer)"
echo "  - Color Picker (system-wide color picker)"
echo ""
info "Chezmoi quickstart (dotfile backup):"
echo "  chezmoi init                          # Initialize"
echo "  chezmoi add ~/.zshrc ~/.tmux.conf     # Track dotfiles"
echo "  chezmoi cd && git remote add origin <repo>  # Link to git repo"
echo "  chezmoi update                        # Pull on new machine"
echo ""
info "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Generate SSH key: ssh-keygen -t ed25519 -C \"your_email@example.com\""
echo "  3. Add SSH key to GitHub: gh ssh-key add ~/.ssh/id_ed25519.pub"
echo "  4. Set up ngrok: ngrok config add-authtoken <TOKEN>"
echo "  5. Set up chezmoi: chezmoi init && chezmoi add ~/.zshrc"
echo "  6. Enable FileVault: System Settings > Privacy & Security > FileVault"
echo "  7. Enable macOS Firewall: System Settings > Network > Firewall"
echo "  8. Set OrbStack or Docker Desktop as default: open one and set as default"

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
        "brew:brew --version"
        "code:code --version"
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

echo -e "${GREEN}${BOLD}  Restart your terminal to activate everything.${NC}"
echo ""
