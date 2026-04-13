# =============================================================================
# Development Environment Setup Script (Windows)
# =============================================================================
# Version:  2.0.0
# Updated:  2026-04-06
# Platform: Windows 10/11 (x64)
# Run:      Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#           .\setup-dev-tools-windows.ps1
# Flags:    --dry-run, --skip <categories>, --only <categories>, --cleanup, --help
# =============================================================================

$SCRIPT_VERSION = "2.0.0"
$SCRIPT_START = Get-Date

# Don't abort on errors — we count failures instead
$ErrorActionPreference = "Continue"

# -- Colors & Formatting ------------------------------------------------------
function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host $Text -ForegroundColor $Color -NoNewline
}

# -- Logging ------------------------------------------------------------------
$LOG_DIR = Join-Path $HOME ".local\share\dev-setup"
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }
$LOG_FILE = Join-Path $LOG_DIR "setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Log rotation — remove logs older than 30 days
Get-ChildItem "$HOME\.local\share\dev-setup\setup-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

function Write-Log { param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Add-Content -Path $LOG_FILE -Value "[$ts] $Message"
}

function Write-Info { param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
    Write-Log "INFO: $Message"
}

function Write-Success { param([string]$Message)
    Write-Host "[  OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    Write-Log "OK: $Message"
    $script:INSTALL_SUCCESS++
}

function Write-Warn { param([string]$Message)
    Write-Host "[SKIP] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    Write-Log "SKIP: $Message"
    $script:INSTALL_SKIPPED++
}

function Write-Err { param([string]$Message)
    Write-Host "[ ERR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    Write-Log "ERROR: $Message"
    $script:INSTALL_FAILED++
    $script:FAILED_ITEMS += $Message
}

function Write-Banner { param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 74) -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor Magenta
    Write-Host ("=" * 74) -ForegroundColor Magenta
    Write-Host ""
    Write-Log "=== $Title ==="
}

# -- Counters -----------------------------------------------------------------
$script:INSTALL_SUCCESS = 0
$script:INSTALL_SKIPPED = 0
$script:INSTALL_FAILED = 0
$script:INSTALL_CURRENT = 0
$script:FAILED_ITEMS = @()

# Approximate count — dynamically counted from Show-Progress calls in this script
$script:INSTALL_TOTAL = (Select-String -Path $PSCommandPath -Pattern 'Show-Progress' -SimpleMatch).Count
if ($script:INSTALL_TOTAL -eq 0) { $script:INSTALL_TOTAL = 175 }

function Show-Progress {
    $script:INSTALL_CURRENT++
    if ($script:INSTALL_TOTAL -le 0) { $script:INSTALL_TOTAL = 1 }
    $pct = [math]::Min(100, [math]::Floor($script:INSTALL_CURRENT * 100 / $script:INSTALL_TOTAL))
    $barLen = [math]::Floor($pct / 2)
    $bar = [string]::new([char]0x2588, $barLen)
    $spaces = [string]::new(' ', (50 - $barLen))
    Write-Host "`r" -NoNewline
    Write-Host "[" -ForegroundColor DarkGray -NoNewline
    Write-Host $bar -ForegroundColor Cyan -NoNewline
    Write-Host $spaces -ForegroundColor DarkGray -NoNewline
    Write-Host "] ${pct}% ($($script:INSTALL_CURRENT)/$($script:INSTALL_TOTAL))" -ForegroundColor DarkGray
}

# -- State flags --------------------------------------------------------------
$DRY_RUN = $false
$RESUME = $false
$UNINSTALL = $false
$CLEANUP = $false
$SKIP_CATEGORIES = @()
$ONLY_CATEGORIES = @()

# -- State file for --resume --------------------------------------------------
$STATE_DIR = Join-Path $HOME ".local\share\dev-setup"
$STATE_FILE = Join-Path $STATE_DIR "completed-items.txt"

function Mark-Done { param([string]$Item)
    if ($DRY_RUN) { return }
    Add-Content -Path $STATE_FILE -Value $Item
}

function Test-Done { param([string]$Item)
    if (-not $RESUME) { return $false }
    if (-not (Test-Path $STATE_FILE)) { return $false }
    return (Get-Content $STATE_FILE -ErrorAction SilentlyContinue) -contains $Item
}

# -- Lockfile (prevent concurrent runs) ---------------------------------------
$LOCKFILE = Join-Path $STATE_DIR "setup.lock"

function Get-Lock {
    if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }
    if (Test-Path $LOCKFILE) {
        $oldPid = Get-Content $LOCKFILE -ErrorAction SilentlyContinue
        if ($oldPid) {
            $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
            if ($proc -and ($proc.ProcessName -eq "pwsh" -or $proc.ProcessName -eq "powershell")) {
                Write-Err "Another instance is running (PID: $oldPid)"
                exit 1
            }
            Write-Warning "Removing stale lock (PID: $oldPid)"
            Remove-Item $LOCKFILE -Force -ErrorAction SilentlyContinue
        }
    }
    $PID | Out-File $LOCKFILE -Force
}

function Release-Lock {
    Remove-Item $LOCKFILE -Force -ErrorAction SilentlyContinue
}

# Register cleanup
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Release-Lock } -ErrorAction SilentlyContinue

$ALL_CATEGORIES = @(
    "prerequisites"
    "core"
    "git"
    "aws"
    "iac"
    "security"
    "replacements"
    "data-processing"
    "code-quality"
    "perf-testing"
    "dev-servers"
    "terminal-productivity"
    "k8s-github"
    "database"
    "containers"
    "api"
    "networking"
    "dx"
    "ui"
    "ux"
    "docs"
    "win-system"
    "win-productivity"
    "win-communication"
    "win-browsers"
    "win-media"
    "win-cloud"
    "win-focus"
    "win-disk"
    "win-bloat"
    "dracula"
    "configs"
    "filesystem"
    "windows-defaults"
    "shell"
)

# -- CLI argument parsing -----------------------------------------------------
function Show-Help {
    Write-Host ""
    Write-Host "Windows Development Environment Setup v$SCRIPT_VERSION" -ForegroundColor White
    Write-Host ""
    Write-Host "Usage: .\setup-dev-tools-windows.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --help              Show this help message"
    Write-Host "  --dry-run           Preview what would be installed (no changes)"
    Write-Host "  --resume            Skip items that succeeded in a previous run"
    Write-Host "  --uninstall         Show commands to remove everything (no changes made)"
    Write-Host "  --cleanup           Remove tools from previous versions no longer in this script"
    Write-Host "  --skip <cats>       Skip categories (comma-separated)"
    Write-Host "  --only <cats>       Only run these categories (comma-separated)"
    Write-Host "  --list-categories   List all available categories"
    Write-Host "  --version           Show script version"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup-dev-tools-windows.ps1                          # Install everything"
    Write-Host "  .\setup-dev-tools-windows.ps1 --dry-run                # Preview only"
    Write-Host "  .\setup-dev-tools-windows.ps1 --resume                 # Continue after a failure"
    Write-Host "  .\setup-dev-tools-windows.ps1 --uninstall              # Show removal commands"
    Write-Host "  .\setup-dev-tools-windows.ps1 --cleanup                # Remove dropped tools from previous versions"
    Write-Host "  .\setup-dev-tools-windows.ps1 --skip win-media,win-cloud"
    Write-Host "  .\setup-dev-tools-windows.ps1 --only core,git,aws,dx"
    Write-Host ""
}

function Show-Categories {
    Write-Host ""
    Write-Host "Available categories:" -ForegroundColor White
    Write-Host ""
    $cats = @(
        @("prerequisites",          "Scoop, Scoop buckets, Visual Studio Build Tools")
        @("core",                   "mise (Node, Python), Go, Rust, Docker, bun, uv, pnpm")
        @("git",                    "Git, GitHub CLI, delta, lazygit, pre-commit")
        @("aws",                    "AWS CLI, CDK, SAM, Granted, cfn-lint")
        @("iac",                   "OpenTofu, tflint, infracost (Infrastructure as Code)")
        @("security",              "detect-secrets, gitleaks, trivy, semgrep, simplewall, Wireshark")
        @("replacements",          "eza, bat, fd, ripgrep, zoxide, btop, sd, dust, just, yazi, fx, etc.")
        @("data-processing",       "yq, miller, csvkit, pandoc, ffmpeg, ImageMagick")
        @("code-quality",          "shellcheck, shfmt, act, hadolint, ruff, npkill, commitizen")
        @("perf-testing",          "hyperfine, oha")
        @("dev-servers",           "ngrok, miniserve, caddy")
        @("terminal-productivity", "glow, watchexec, pv, parallel, topgrade, fastfetch, lnav")
        @("k8s-github",            "stern, gh-dash")
        @("database",              "pgcli, mycli, usql, sq, DBeaver")
        @("containers",            "lazydocker, dive, kubectl, k9s")
        @("api",                   "Bruno, grpcurl")
        @("networking",            "mtr/WinMTR, bandwhich, nmap")
        @("dx",                    "fzf, starship, atuin, VS Code, Zed, Alacritty, PowerToys")
        @("ui",                    "Storybook, Playwright, Chrome")
        @("ux",                    "Lighthouse")
        @("docs",                  "d2, Mermaid CLI")
        @("win-system",            "BCUninstaller, 7zip, simplewall, QuickLook, PowerToys, Mullvad VPN")
        @("win-productivity",      "Notion, ShareX, Espanso, SumatraPDF")
        @("win-communication",     "Slack, Telegram, Signal")
        @("win-browsers",          "Firefox, Arc, Brave, Carbonyl")
        @("win-media",             "mpv, oxipng, jpegoptim, LibreOffice")
        @("win-cloud",             "Google Drive, rclone, Syncthing")
        @("win-focus",             "Reeder alternative")
        @("win-disk",              "dust, duf")
        @("win-bloat",             "Remove pre-installed Windows apps (Clipchamp, Xbox, etc.)")
        @("dracula",               "Dracula theme for all tools")
        @("configs",               "All dotfiles and tool configurations")
        @("filesystem",            "Directory structure, helper scripts, git identity")
        @("windows-defaults",      "Registry edits: keyboard, Explorer, DNS, taskbar, animations")
        @("shell",                 "PowerShell profile, aliases, environment")
    )
    foreach ($c in $cats) {
        Write-Host ("  {0,-25} {1}" -f $c[0], $c[1])
    }
    Write-Host ""
}

# Parse arguments
$argList = $args
$i = 0
while ($i -lt $argList.Count) {
    switch ($argList[$i]) {
        "--help"   { Show-Help; exit 0 }
        "-h"       { Show-Help; exit 0 }
        "--version" { Write-Host "setup-dev-tools-windows.ps1 v$SCRIPT_VERSION"; exit 0 }
        "-v"       { Write-Host "setup-dev-tools-windows.ps1 v$SCRIPT_VERSION"; exit 0 }
        "--dry-run" { $DRY_RUN = $true }
        "--resume"  { $RESUME = $true }
        "--uninstall" { $UNINSTALL = $true }
        "--cleanup" { $CLEANUP = $true }
        "--skip" {
            $i++
            if ($i -lt $argList.Count) { $SKIP_CATEGORIES = $argList[$i] -split "," }
        }
        "--only" {
            $i++
            if ($i -lt $argList.Count) { $ONLY_CATEGORIES = $argList[$i] -split "," }
        }
        "--list-categories" { Show-Categories; exit 0 }
        default {
            Write-Host "Unknown option: $($argList[$i])" -ForegroundColor Red
            Show-Help
            exit 1
        }
    }
    $i++
}

# Validate --skip/--only category names
foreach ($cat in $SKIP_CATEGORIES + $ONLY_CATEGORIES) {
    if ($cat -and $cat -notin $ALL_CATEGORIES) {
        Write-Err "Unknown category: '$cat'. Valid categories: $($ALL_CATEGORIES -join ', ')"
        exit 1
    }
}

# -- Category filtering -------------------------------------------------------
function Test-ShouldRun { param([string]$Category)
    if ($ONLY_CATEGORIES.Count -gt 0) {
        return $ONLY_CATEGORIES -contains $Category
    }
    if ($SKIP_CATEGORIES -contains $Category) { return $false }
    return $true
}

# -- Utility functions --------------------------------------------------------
function Test-Command { param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# -- Installer functions ------------------------------------------------------
function Install-ScoopPackage {
    param([string]$Package, [string]$DisplayName)
    if (-not $DisplayName) { $DisplayName = $Package }
    Show-Progress
    if (Test-Done "scoop:$Package") { Write-Warn "$DisplayName already completed (resume)"; return }
    if ($DRY_RUN) {
        $installed = scoop list 2>$null | Select-String -Pattern "^\s*$([regex]::Escape($Package))\s" -Quiet
        if ($installed) { Write-Warn "[DRY RUN] $DisplayName -- already installed" }
        else { Write-Info "[DRY RUN] Would install: $DisplayName" }
        return
    }
    $installed = scoop list 2>$null | Select-String -Pattern "^\s*$([regex]::Escape($Package))\s" -Quiet
    if ($installed) {
        Write-Warn "$DisplayName already installed"
        Mark-Done "scoop:$Package"
    } else {
        Write-Info "Installing $DisplayName..."
        $output = scoop install $Package 2>&1
        $output | Out-File $LOG_FILE -Append
        if ($LASTEXITCODE -eq 0 -or ($output -match "installed successfully")) {
            Write-Success "$DisplayName installed"
            Mark-Done "scoop:$Package"
        } else {
            Write-Err "Failed to install $DisplayName"
        }
    }
}

function Install-WingetPackage {
    param([string]$PackageId, [string]$DisplayName)
    if (-not $DisplayName) { $DisplayName = $PackageId }
    Show-Progress
    if (Test-Done "winget:$PackageId") { Write-Warn "$DisplayName already completed (resume)"; return }
    if ($DRY_RUN) {
        $check = winget list --id $PackageId --exact --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0 -and $check -match [regex]::Escape($PackageId)) { Write-Warn "[DRY RUN] $DisplayName -- already installed" }
        else { Write-Info "[DRY RUN] Would install: $DisplayName" }
        return
    }
    $check = winget list --id $PackageId --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $check -match [regex]::Escape($PackageId)) {
        Write-Warn "$DisplayName already installed"
        Mark-Done "winget:$PackageId"
    } else {
        Write-Info "Installing $DisplayName..."
        $output = winget install --id $PackageId --accept-source-agreements --accept-package-agreements --silent 2>&1
        $output | Out-File $LOG_FILE -Append
        if ($LASTEXITCODE -eq 0 -or ($output -match "Successfully installed")) {
            Write-Success "$DisplayName installed"
            Mark-Done "winget:$PackageId"
        } else {
            Write-Err "Failed to install $DisplayName"
        }
    }
}

function Install-NpmGlobal {
    param([string]$Package, [string]$DisplayName)
    if (-not $DisplayName) { $DisplayName = $Package }
    Show-Progress
    if (Test-Done "npm:$Package") { Write-Warn "$DisplayName already completed (resume)"; return }
    if ($DRY_RUN) {
        $check = npm list -g $Package 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Warn "[DRY RUN] $DisplayName -- already installed" }
        else { Write-Info "[DRY RUN] Would install: $DisplayName" }
        return
    }
    $check = npm list -g $Package 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Warn "$DisplayName already installed globally"
        Mark-Done "npm:$Package"
    } else {
        Write-Info "Installing $DisplayName globally..."
        $output = npm install -g $Package 2>&1
        $output | Out-File $LOG_FILE -Append
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$DisplayName installed"
            Mark-Done "npm:$Package"
        } else {
            Write-Err "Failed to install $DisplayName"
        }
    }
}

# -- Pre-flight checks --------------------------------------------------------
function Invoke-Preflight {
    Write-Banner "Pre-flight Checks"

    # Windows version
    $winVer = [System.Environment]::OSVersion.Version
    if ($winVer.Build -lt 19041) {
        Write-Err "Windows 10 version 2004 or later required. Build: $($winVer.Build)"
        $confirm = Read-Host "Continue anyway? [y/N]"
        if ($confirm -ne "y" -and $confirm -ne "Y") { exit 1 }
    } else {
        Write-Success "Windows $($winVer.Major).$($winVer.Minor) Build $($winVer.Build) detected"
    }

    # Architecture
    $arch = $env:PROCESSOR_ARCHITECTURE
    Write-Success "Architecture: $arch"

    # Internet connectivity
    try {
        $null = Invoke-WebRequest -Uri "https://raw.githubusercontent.com" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Success "Internet connection OK"
    } catch {
        Write-Err "No internet connection detected"
        Write-Host "  This script requires internet to download packages."
        exit 1
    }

    # Disk space (require at least 15GB free)
    $drive = (Get-PSDrive -Name ($HOME.Substring(0,1)))
    $freeGB = [math]::Floor($drive.Free / 1GB)
    if ($freeGB -lt 15) {
        Write-Err "Low disk space: ${freeGB}GB free (15GB+ recommended)"
        $confirm = Read-Host "Continue anyway? [y/N]"
        if ($confirm -ne "y" -and $confirm -ne "Y") { exit 1 }
    } else {
        Write-Success "Disk space: ${freeGB}GB free"
    }

    # Admin check
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Success "Running as Administrator"
    } else {
        Write-Info "Some steps require Administrator privileges. Registry edits may be skipped."
    }

    Write-Success "Log file: $LOG_FILE"

    if ($DRY_RUN) {
        Write-Host ""
        Write-Host "  DRY RUN MODE -- no changes will be made" -ForegroundColor Yellow
        Write-Host ""
    }

    if ($RESUME) {
        if (Test-Path $STATE_FILE) {
            $completedCount = (Get-Content $STATE_FILE -ErrorAction SilentlyContinue).Count
            Write-Host ""
            Write-Host "  RESUME MODE -- skipping $completedCount previously completed items" -ForegroundColor Cyan
            Write-Host ""
        } else {
            Write-Info "Resume mode enabled but no previous state found -- running from scratch"
        }
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Magenta
Write-Host "  |         Windows Dev Environment Setup v$SCRIPT_VERSION               |" -ForegroundColor Magenta
Write-Host "  |                                                                |" -ForegroundColor Magenta
Write-Host "  |  200+ tools - 50+ configs - Dracula theme - Windows defaults   |" -ForegroundColor Magenta
Write-Host "  +================================================================+" -ForegroundColor Magenta
Write-Host ""

# -- Handle --uninstall early (just prints commands, no changes) --------------
if ($UNINSTALL) {
    Write-Host ""
    Write-Host "Uninstall Guide" -ForegroundColor Yellow
    Write-Host "Run these commands to remove everything installed by this script." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "# Remove all Scoop packages:"
    Write-Host "  scoop uninstall --all"
    Write-Host ""
    Write-Host "# Remove config files:"
    Write-Host "  Remove-Item -Force ~\.shellcheckrc, ~\.editorconfig, ~\.prettierrc"
    Write-Host "  Remove-Item -Force ~\.curlrc, ~\.npmrc, ~\.ripgreprc, ~\.fdignore, ~\.vimrc"
    Write-Host "  Remove-Item -Force ~\.hushlogin, ~\.gitmessage, ~\.myclirc, ~\.gemrc, ~\.actrc, ~\.mlrrc"
    Write-Host "  Remove-Item -Recurse -Force ~\.aria2, ~\.config\atuin, ~\.config\glow, ~\.config\ngrok"
    Write-Host "  Remove-Item -Recurse -Force ~\.config\yt-dlp, ~\.config\gh-dash, ~\.config\stern"
    Write-Host "  Remove-Item -Recurse -Force ~\.config\btop, ~\.config\lazydocker, ~\.config\mise"
    Write-Host "  Remove-Item -Recurse -Force ~\.config\topgrade.toml, ~\.config\fastfetch, ~\.config\pgcli"
    Write-Host "  Remove-Item -Recurse -Force ~\.config\direnv, ~\.config\caddy, ~\.config\yazi"
    Write-Host "  Remove-Item -Force ~\.justfile"
    Write-Host ""
    Write-Host "# Remove Rust (installed via rustup):"
    Write-Host "  rustup self uninstall"
    Write-Host ""
    Write-Host "# Remove Claude Code config (CAREFUL -- contains your custom rules):"
    Write-Host "  Remove-Item -Recurse -Force ~\.claude\settings.json, ~\.claude\CLAUDE.md, ~\.claude\rules, ~\.claude\hooks, ~\.claude\commands"
    Write-Host ""
    Write-Host "# Remove VS Code settings:"
    Write-Host "  Remove-Item -Force `"$env:APPDATA\Code\User\settings.json`""
    Write-Host "  Remove-Item -Force `"$env:APPDATA\Code\User\keybindings.json`""
    Write-Host ""
    Write-Host "# Remove helper scripts:"
    Write-Host "  Remove-Item -Recurse -Force ~\Scripts\bin"
    Write-Host ""
    Write-Host "# Remove the managed block from `$PROFILE (edit manually)"
    Write-Host "# Remove git global config overrides:"
    Write-Host "  git config --global --unset core.pager"
    Write-Host "  git config --global --unset core.hooksPath"
    Write-Host "  git config --global --unset core.excludesfile"
    Write-Host "  git config --global --unset commit.template"
    Write-Host ""
    Write-Host "# Remove state files:"
    Write-Host "  Remove-Item -Recurse -Force ~\.local\share\dev-setup"
    Write-Host ""
    Write-Host "Review each command before running. This does NOT auto-execute." -ForegroundColor Yellow
    exit 0
}

# -- Handle --cleanup (remove tools from previous versions no longer in script)
if ($CLEANUP) {
    Write-Host ""
    Write-Host "Cleanup: Removing tools from previous versions" -ForegroundColor Cyan
    Write-Host ""

    # Tools removed in current version (were in previous versions, now replaced or dropped)
    $deprecatedTools = @(
        @{ Type="scoop"; Id="warp"; Name="Warp terminal"; Replacement="Windows Terminal + Alacritty" }
        @{ Type="winget"; Id="CursorAI.Cursor"; Name="Cursor (AI editor)"; Replacement="VS Code + Claude Code" }
        @{ Type="winget"; Id="Telerik.Fiddler.Classic"; Name="Fiddler"; Replacement="mitmproxy" }
        @{ Type="scoop"; Id="dog"; Name="dog (DNS tool)"; Replacement="doggo" }
        @{ Type="winget"; Id="Tailscale.Tailscale"; Name="Tailscale"; Replacement="removed" }
        @{ Type="winget"; Id="Figma.Figma"; Name="Figma"; Replacement="removed (use figma.com)" }
        @{ Type="winget"; Id="Discord.Discord"; Name="Discord"; Replacement="removed" }
        @{ Type="winget"; Id="GIMP.GIMP"; Name="GIMP"; Replacement="removed" }
        @{ Type="winget"; Id="Anki.Anki"; Name="Anki"; Replacement="removed" }
        @{ Type="scoop"; Id="nvm"; Name="nvm"; Replacement="mise" }
        @{ Type="scoop"; Id="pyenv"; Name="pyenv-win"; Replacement="mise" }
        @{ Type="scoop"; Id="httpie"; Name="HTTPie"; Replacement="xh" }
        @{ Type="scoop"; Id="git-secrets"; Name="git-secrets"; Replacement="gitleaks + detect-secrets" }
        @{ Type="scoop"; Id="trufflehog"; Name="trufflehog"; Replacement="gitleaks + detect-secrets" }
        @{ Type="winget"; Id="Cyberduck.Cyberduck"; Name="Cyberduck"; Replacement="WinSCP" }
    )

    $cleanupCount = 0
    $cleanupSkipped = 0

    foreach ($tool in $deprecatedTools) {
        $installed = $false

        switch ($tool.Type) {
            "winget" {
                $result = winget list --id $tool.Id 2>$null
                if ($LASTEXITCODE -eq 0 -and $result -match $tool.Id) { $installed = $true }
            }
            "scoop" {
                if (scoop list $tool.Id 2>$null | Select-String $tool.Id) { $installed = $true }
            }
        }

        if ($installed) {
            if ($DRY_RUN) {
                Write-Info "[DRY RUN] Would remove: $($tool.Name) (replaced by $($tool.Replacement))"
            } else {
                Write-Info "Removing $($tool.Name) (replaced by $($tool.Replacement))..."
                switch ($tool.Type) {
                    "winget" {
                        winget uninstall --id $tool.Id --silent 2>$null >> $LOG_FILE
                        if ($?) { Write-Success "$($tool.Name) removed" } else { Write-Err "$($tool.Name) — failed to remove" }
                    }
                    "scoop" {
                        scoop uninstall $tool.Id 2>$null >> $LOG_FILE
                        if ($?) { Write-Success "$($tool.Name) removed" } else { Write-Err "$($tool.Name) — failed to remove" }
                    }
                }
                $cleanupCount++
            }
        } else {
            $cleanupSkipped++
        }
    }

    Write-Host ""
    if (-not $DRY_RUN) {
        Write-Success "Cleanup complete: $cleanupCount removed, $cleanupSkipped not found (already clean)"
    }
    exit 0
}

Invoke-Preflight
Get-Lock

try {

# =============================================================================
# PREREQUISITES (always runs -- required for everything else)
# =============================================================================
Write-Banner "Prerequisites"

# Scoop bootstrap
if (-not (Test-Command "scoop")) {
    Write-Info "Installing Scoop..."
    if (-not $DRY_RUN) {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            $scoopInstaller = Join-Path $env:TEMP "scoop-install.ps1"
            Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstaller -UseBasicParsing
            if (-not (Test-Path $scoopInstaller) -or (Get-Item $scoopInstaller).Length -eq 0) {
                Write-Err "Failed to download Scoop installer"
                return
            }
            & $scoopInstaller
            Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
            Write-Success "Scoop installed"
        } catch {
            Write-Err "Failed to install Scoop: $_"
        }
    } else {
        Write-Info "[DRY RUN] Would install: Scoop"
    }
} else {
    Write-Warn "Scoop already installed"
    if (-not $DRY_RUN) {
        Write-Info "Updating Scoop..."
        scoop update 2>&1 | Out-File $LOG_FILE -Append
    }
}

# Scoop buckets
if (Test-Command "scoop") {
    $existingBuckets = scoop bucket list 2>$null
    foreach ($bucket in @("extras", "nerd-fonts", "versions")) {
        if ($existingBuckets -match $bucket) {
            Write-Warn "Scoop bucket '$bucket' already added"
        } else {
            if (-not $DRY_RUN) {
                Write-Info "Adding Scoop bucket: $bucket..."
                scoop bucket add $bucket 2>&1 | Out-File $LOG_FILE -Append
                Write-Success "Scoop bucket '$bucket' added"
            } else {
                Write-Info "[DRY RUN] Would add Scoop bucket: $bucket"
            }
        }
    }
}

# Visual Studio Build Tools
Install-WingetPackage "Microsoft.VisualStudio.2022.BuildTools" "Visual Studio 2022 Build Tools"

# Git (early install -- needed for scoop buckets and other tooling)
Install-ScoopPackage "git" "Git"

# =============================================================================
if (Test-ShouldRun "core") {
Write-Banner "Core Development"

Install-ScoopPackage "mise" "mise (universal version manager -- Node, Python, Go, Ruby, etc.)"

# Activate mise for this script session and install Node/Python
if (Test-Command "mise") {
    if (-not $DRY_RUN) {
        $miseActivation = mise activate powershell 2>&1
        if ($LASTEXITCODE -eq 0 -and $miseActivation) {
            $miseActivation | Invoke-Expression
        } else {
            Write-Warn "mise activation failed — Node/Python via mise may be unavailable"
        }

        # Install Node.js LTS via mise
        $miseNode = mise ls node 2>$null
        if (-not ($miseNode -match "lts")) {
            Write-Info "Installing Node.js LTS via mise..."
            mise install node@lts 2>&1 | Out-File $LOG_FILE -Append
            mise use --global node@lts 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "Node.js LTS installed via mise"
        } else {
            Write-Warn "Node.js LTS already installed via mise"
        }

        # Install Python 3.12 via mise
        $misePython = mise ls python 2>$null
        if (-not ($misePython -match "3.12")) {
            Write-Info "Installing Python 3.12 via mise..."
            mise install python@3.12 2>&1 | Out-File $LOG_FILE -Append
            mise use --global python@3.12 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "Python 3.12 installed via mise"
        } else {
            Write-Warn "Python 3.12 already installed via mise"
        }

        # Ensure mise shims are in PATH for the rest of this script
        mise env 2>$null | Invoke-Expression
    }
}

Install-ScoopPackage "go" "Go (lang)"
Install-ScoopPackage "uv" "uv (fast Python package manager -- 10-100x faster than pip)"
Install-ScoopPackage "jq" "jq (JSON processor)"
Install-ScoopPackage "direnv" "direnv (per-project env vars)"
Install-ScoopPackage "cmake" "CMake"

# Rust (rustup manages the toolchain -- installs rustc, cargo, etc.)
if (-not (Test-Command "rustup")) {
    Show-Progress
    Write-Info "Installing Rust via rustup..."
    if (-not $DRY_RUN) {
        try {
            $arch = if ([Environment]::Is64BitOperatingSystem) {
                if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
            } else { "i686" }
            $rustupUrl = "https://win.rustup.rs/$arch"
            $rustupInit = Join-Path $env:TEMP "rustup-init.exe"
            Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupInit -UseBasicParsing
            if (-not (Test-Path $rustupInit) -or (Get-Item $rustupInit).Length -eq 0) {
                Write-Err "Failed to download Rust installer"
                return
            }
            & $rustupInit -y --no-modify-path 2>&1 | Out-File $LOG_FILE -Append
            $env:Path = "$HOME\.cargo\bin;$env:Path"
            Write-Success "Rust installed via rustup"
        } catch {
            Write-Err "Failed to install Rust: $_"
        }
    } else {
        Write-Info "[DRY RUN] Would install: Rust via rustup"
    }
} else {
    Show-Progress
    Write-Warn "Rust (rustup) already installed"
}

# Docker Desktop
Install-WingetPackage "Docker.DockerDesktop" "Docker Desktop"

# bun
Install-ScoopPackage "bun" "bun (fast JS runtime/bundler/test runner)"

# pnpm
Install-ScoopPackage "pnpm" "pnpm (fast, disk-efficient package manager)"

# -- Verify all runtimes are in PATH for the rest of the script ----------------
Write-Info "Verifying runtime paths..."
# Refresh PATH to pick up scoop/winget installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# mise - ensure mise shims are active
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise env 2>$null | Invoke-Expression
}

# Verify and log
foreach ($tool in @("node", "npm", "go", "rustc", "cargo", "bun", "pnpm", "uv", "code")) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Add-Content $LOG_FILE "RUNTIME: $tool found at $((Get-Command $tool).Source)"
    } else {
        Add-Content $LOG_FILE "RUNTIME: $tool NOT found in PATH"
    }
}

} # core

# =============================================================================
if (Test-ShouldRun "git") {
Write-Banner "Git & GitHub"

# git already installed in prerequisites
Install-ScoopPackage "gh" "GitHub CLI"
Install-ScoopPackage "delta" "delta (better git diffs)"
Install-ScoopPackage "git-lfs" "Git LFS"
Install-ScoopPackage "gpg" "GnuPG (commit signing)"
Install-ScoopPackage "lazygit" "lazygit (terminal UI for git)"

# git-absorb via cargo
if (Test-Command "cargo") {
    if (-not (Test-Command "git-absorb")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing git-absorb via cargo..."
            cargo install git-absorb 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "git-absorb installed"
        }
    } else {
        Write-Warn "git-absorb already installed"
    }

    # git-cliff
    if (-not (Test-Command "git-cliff")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing git-cliff via cargo..."
            cargo install git-cliff 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "git-cliff installed"
        }
    } else {
        Write-Warn "git-cliff already installed"
    }
}

# pre-commit via uv
if (Test-Command "uv") {
    if (-not (Test-Command "pre-commit")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing pre-commit via uv..."
            uv tool install pre-commit 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "pre-commit installed"
        }
    } else {
        Write-Warn "pre-commit already installed"
    }
}

# Configure delta as default git pager
if (-not $DRY_RUN) {
    $currentPager = git config --global core.pager 2>$null
    if ($currentPager -ne "delta") {
        Write-Info "Configuring delta as git pager..."
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.side-by-side true
        git config --global merge.conflictstyle diff3
        Write-Success "delta configured as git pager"
    }
}

} # git

# =============================================================================
if (Test-ShouldRun "aws") {
Write-Banner "AWS & CDK"

Install-WingetPackage "Amazon.AWSCLI2" "AWS CLI v2"
Install-WingetPackage "Amazon.SAM-CLI" "AWS SAM CLI"

# cfn-lint via uv
if (Test-Command "uv") {
    if (-not $DRY_RUN) {
        if (-not (Test-Command "cfn-lint")) {
            Write-Info "Installing cfn-lint via uv..."
            uv tool install cfn-lint 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "cfn-lint installed"
        } else {
            Write-Warn "cfn-lint already installed"
        }
    }
}

# Granted (multi-account credential switching)
Install-ScoopPackage "granted" "Granted (AWS SSO credential switching)"

# AWS CDK (via npm)
if (Test-Command "npm") {
    Install-NpmGlobal "aws-cdk" "AWS CDK CLI"
    Install-NpmGlobal "cdk-nag" "cdk-nag"
}

} # aws

# =============================================================================
if (Test-ShouldRun "iac") {
Write-Banner "Infrastructure as Code"

Install-ScoopPackage "opentofu" "OpenTofu (open-source Terraform)"
Install-ScoopPackage "tflint" "tflint (Terraform linter)"
Install-ScoopPackage "infracost" "infracost (cost estimation for Terraform)"

} # iac

# =============================================================================
if (Test-ShouldRun "security") {
Write-Banner "Security & Secrets"

Install-ScoopPackage "age" "age (modern file encryption)"
Install-ScoopPackage "sops" "sops (encrypt secrets in YAML/JSON, works with AWS KMS)"

Install-ScoopPackage "detect-secrets" "detect-secrets (pre-commit secret detection)"
Install-ScoopPackage "gitleaks" "gitleaks (fast git secret scanning)"
Install-ScoopPackage "trivy" "trivy (container & IaC vulnerability scanning)"
Install-ScoopPackage "semgrep" "semgrep (static analysis -- bugs & security issues)"
Install-ScoopPackage "cosign" "cosign (sign & verify container images)"
Install-ScoopPackage "mkcert" "mkcert (local HTTPS certs for dev)"
Install-ScoopPackage "ssh-audit" "ssh-audit (audit SSH server/client config)"
Install-WingetPackage "WiresharkFoundation.Wireshark" "Wireshark (network packet analysis)"
Install-ScoopPackage "simplewall" "simplewall (lightweight Windows firewall)"

# Skip Objective-See tools (macOS only)
Write-Info "Skipping Objective-See tools (macOS only)"

# Windows hardening notes
Write-Info "BitLocker: Enable via Settings > Privacy & Security > Device Encryption"
Write-Info "Windows Firewall: Ensure enabled via Settings > Privacy & Security > Windows Security"

# Install local CA for mkcert
if ((Test-Command "mkcert") -and -not $DRY_RUN) {
    Write-Info "Installing local CA for mkcert..."
    mkcert -install 2>$null
    Write-Success "mkcert local CA installed"
}

} # security

# =============================================================================
if (Test-ShouldRun "replacements") {
Write-Banner "Modern Tool Replacements"
Write-Host "  (upgrades for standard Windows/Unix utilities)" -ForegroundColor DarkGray
Write-Host ""

Install-ScoopPackage "eza" "eza (replaces ls/dir -- icons, git status, tree view)"
Install-ScoopPackage "bat" "bat (replaces cat/type -- syntax highlighting, line numbers)"
Install-ScoopPackage "fd" "fd (replaces find -- faster, simpler syntax)"
Install-ScoopPackage "ripgrep" "ripgrep (replaces grep/findstr -- 10x faster, .gitignore aware)"
Install-ScoopPackage "zoxide" "zoxide (replaces cd -- smart frecency-based jumping)"
Install-ScoopPackage "tldr" "tldr (replaces man -- simplified with examples)"
Install-ScoopPackage "btop" "btop (replaces Task Manager -- graphs, mouse support)"
Install-ScoopPackage "sd" "sd (replaces sed -- intuitive find & replace)"
Install-ScoopPackage "dust" "dust (replaces du -- visual disk usage tree)"
Install-ScoopPackage "duf" "duf (replaces df -- colorful disk usage table)"
Install-ScoopPackage "procs" "procs (replaces ps/tasklist -- sortable, tree view)"
Install-ScoopPackage "gping" "gping (replaces ping -- real-time latency graph)"
Install-ScoopPackage "xh" "xh (replaces curl -- colorized, JSON-friendly)"
Install-ScoopPackage "curlie" "curlie (curl with httpie-like output)"
Install-ScoopPackage "doggo" "doggo (replaces nslookup -- colorized DNS, DoH support)"
Install-ScoopPackage "tokei" "tokei (replaces wc for code -- lines of code by language)"
Install-ScoopPackage "tree" "tree (directory listing)"
Install-ScoopPackage "viddy" "viddy (replaces watch -- diff highlighting, history)"
Install-ScoopPackage "hexyl" "hexyl (replaces hexdump -- colorized hex viewer)"
Install-ScoopPackage "aria2" "aria2 (replaces curl/wget for downloads -- multi-connection, BitTorrent)"
Install-ScoopPackage "difftastic" "difftastic (replaces diff for code -- syntax-aware structural diffs)"
Install-ScoopPackage "vivid" "vivid (LS_COLORS generator -- colorize file listings by type)"
Install-ScoopPackage "just" "just (replaces make -- simpler task runner, no tab issues)"
Install-ScoopPackage "yazi" "yazi (terminal file manager -- image preview, vim keys, bulk ops)"
Install-ScoopPackage "fx" "fx (interactive JSON viewer -- better than jq for exploring)"
Install-ScoopPackage "jnv" "jnv (interactive JSON navigator with jq filtering)"
Install-ScoopPackage "recycle-bin" "recycle-bin (replaces rm -- moves to Recycle Bin, recoverable)"
Install-ScoopPackage "watchexec" "watchexec (replaces entr -- run commands when files change)"

# choose via cargo
if (Test-Command "cargo") {
    if (-not (Test-Command "choose")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing choose via cargo..."
            cargo install choose 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "choose installed"
        }
    } else {
        Write-Warn "choose already installed"
    }
}

} # replacements

# =============================================================================
if (Test-ShouldRun "data-processing") {
Write-Banner "Data & File Processing"

Install-ScoopPackage "yq" "yq (jq for YAML -- essential for k8s/CDK work)"
Install-ScoopPackage "miller" "miller (awk/sed/jq for CSV, JSON, tabular data)"
Install-ScoopPackage "pandoc" "pandoc (universal document converter -- md, pdf, docx, html)"
Install-ScoopPackage "imagemagick" "ImageMagick (image resize, convert, composite)"
Install-ScoopPackage "ffmpeg" "ffmpeg (video/audio processing swiss army knife)"
Install-ScoopPackage "yt-dlp" "yt-dlp (video/audio downloader)"

# csvkit via uv
if (Test-Command "uv") {
    if (-not $DRY_RUN) {
        if (-not (Test-Command "csvlook")) {
            Write-Info "Installing csvkit via uv..."
            uv tool install csvkit 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "csvkit installed"
        } else {
            Write-Warn "csvkit already installed"
        }
    }
}

} # data-processing

# =============================================================================
if (Test-ShouldRun "code-quality") {
Write-Banner "Code Quality"

Install-ScoopPackage "shellcheck" "shellcheck (shell script linter)"
Install-ScoopPackage "shfmt" "shfmt (shell script formatter)"
Install-ScoopPackage "act" "act (run GitHub Actions locally)"
Install-ScoopPackage "hadolint" "hadolint (Dockerfile linter)"
Install-ScoopPackage "ruff" "ruff (fast Python linter+formatter)"
Install-ScoopPackage "typos" "typos (source code spell checker -- fast, low false positives)"
Install-ScoopPackage "ast-grep" "ast-grep (structural code search/replace using AST)"

# npm code-quality globals
if (Test-Command "npm") {
    Install-NpmGlobal "npkill" "npkill (find & remove node_modules)"
    Install-NpmGlobal "commitizen" "commitizen (conventional commit prompts)"
    Install-NpmGlobal "@commitlint/cli" "@commitlint/cli (lint commit messages)"
    Install-NpmGlobal "@antfu/ni" "@antfu/ni (auto-detect package manager)"
}

} # code-quality

# =============================================================================
if (Test-ShouldRun "perf-testing") {
Write-Banner "Performance & Load Testing"

Install-ScoopPackage "hyperfine" "hyperfine (command benchmarking)"
Install-ScoopPackage "oha" "oha (HTTP load testing, Rust-based)"
Install-ScoopPackage "hurl" "hurl (HTTP requests from plain text files -- curl + test runner)"

} # perf-testing

# =============================================================================
if (Test-ShouldRun "dev-servers") {
Write-Banner "Dev Servers & Tunnels"

Install-WingetPackage "Ngrok.Ngrok" "ngrok (expose localhost to the internet)"
Install-ScoopPackage "miniserve" "miniserve (instant file server from any directory)"
Install-ScoopPackage "caddy" "caddy (modern web server with automatic HTTPS)"

} # dev-servers

# =============================================================================
if (Test-ShouldRun "terminal-productivity") {
Write-Banner "Terminal Productivity"

Install-ScoopPackage "glow" "glow (render Markdown in terminal)"
# watchexec already installed in replacements section — skipping duplicate
Install-ScoopPackage "pv" "pv (pipe viewer -- progress bars for pipes)"
Install-ScoopPackage "parallel" "parallel (GNU parallel -- run commands in parallel)"
Install-ScoopPackage "asciinema" "asciinema (record & share terminal sessions)"
Install-ScoopPackage "gum" "gum (shell script UI toolkit -- prompts, spinners, confirmations)"
Install-ScoopPackage "nushell" "nushell (structured data shell -- pipelines output tables)"
Install-ScoopPackage "newsboat" "newsboat (terminal RSS/Atom reader)"
Install-ScoopPackage "topgrade" "topgrade (update everything -- scoop, npm, pip, all at once)"
Install-ScoopPackage "fastfetch" "fastfetch (quick system info display -- faster neofetch)"
Install-ScoopPackage "lnav" "lnav (advanced log viewer)"

} # terminal-productivity

# =============================================================================
if (Test-ShouldRun "k8s-github") {
Write-Banner "Kubernetes & GitHub Extras"

Install-ScoopPackage "stern" "stern (multi-pod log tailing for k8s)"

# gh-dash (GitHub dashboard extension)
if (Test-Command "gh") {
    $ghExtList = gh extension list 2>$null
    if ($ghExtList -match "gh-dash") {
        Write-Warn "gh-dash already installed"
    } else {
        if (-not $DRY_RUN) {
            Write-Info "Installing gh-dash (GitHub dashboard)..."
            gh extension install dlvhdr/gh-dash 2>$null
            Write-Success "gh-dash installed (run: gh dash)"
        }
    }
}

} # k8s-github

# =============================================================================
if (Test-ShouldRun "database") {
Write-Banner "Database & Data"

Install-ScoopPackage "pgcli" "pgcli (auto-completing Postgres CLI)"
Install-ScoopPackage "mycli" "mycli (auto-completing MySQL CLI)"
Install-ScoopPackage "lazysql" "lazysql (TUI for databases -- interactive SQL in terminal)"

# usql via go install
if (Test-Command "go") {
    if (-not (Test-Command "usql")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing usql (universal SQL CLI)..."
            go install github.com/xo/usql@latest 2>&1 | Out-File $LOG_FILE -Append
        }
    } else {
        Write-Warn "usql already installed"
    }
}

Install-ScoopPackage "dbmate" "dbmate (lightweight DB migrations)"
Install-WingetPackage "dbeaver.dbeaver" "DBeaver Community (advanced SQL, 100+ DB support)"

# sq -- jq for databases
Install-ScoopPackage "sq" "sq (jq for databases -- query SQLite, Postgres, CSV from one tool)"

# TablePlus
Write-Info "TablePlus: Download manually from https://tableplus.com/windows (no winget package)"

} # database

# =============================================================================
if (Test-ShouldRun "containers") {
Write-Banner "Containers & Orchestration"

Install-ScoopPackage "lazydocker" "lazydocker (terminal UI for Docker)"
Install-ScoopPackage "dive" "dive (explore Docker image layers)"
Install-ScoopPackage "kubectl" "kubectl (Kubernetes CLI)"
Install-ScoopPackage "k9s" "k9s (terminal UI for Kubernetes)"

} # containers

# =============================================================================
if (Test-ShouldRun "api") {
Write-Banner "API Development"

Install-WingetPackage "Bruno.Bruno" "Bruno (open-source API client, git-friendly)"
Install-ScoopPackage "grpcurl" "grpcurl (curl for gRPC)"

} # api

# =============================================================================
if (Test-ShouldRun "networking") {
Write-Banner "Networking & Debugging"

Install-ScoopPackage "winmtr" "WinMTR (combines ping + traceroute)"
Install-ScoopPackage "bandwhich" "bandwhich (real-time bandwidth by process)"
Install-ScoopPackage "nmap" "nmap (network scanning)"
Install-ScoopPackage "trippy" "trippy (modern traceroute TUI with charts)"

} # networking

# =============================================================================
if (Test-ShouldRun "dx") {
Write-Banner "Developer Experience"

# Terminal tools
Install-ScoopPackage "fzf" "fzf (fuzzy finder)"
Install-ScoopPackage "starship" "Starship (shell prompt)"
Install-ScoopPackage "atuin" "atuin (replaces shell history -- SQLite-backed, searchable)"
Install-ScoopPackage "chezmoi" "chezmoi (dotfile manager -- backup/restore configs across machines)"

# Editors & terminals
Install-WingetPackage "Microsoft.VisualStudioCode" "VS Code"
Install-ScoopPackage "alacritty" "Alacritty (fast GPU-accelerated terminal)"

# Zed
Write-Info "Zed: Check availability at https://zed.dev for Windows"

# Windows Terminal is built-in on Windows 11 / available via winget
Install-WingetPackage "Microsoft.WindowsTerminal" "Windows Terminal"

# PowerToys (replaces Raycast + Rectangle on macOS)
Install-WingetPackage "Microsoft.PowerToys" "PowerToys (replaces Raycast + Rectangle -- window management, launcher, etc.)"

# AI tools
if (Test-Command "npm") {
    Install-NpmGlobal "@anthropic-ai/claude-code" "Claude Code (AI-assisted coding in terminal)"
}

# GitHub Copilot CLI
if (Test-Command "gh") {
    $ghExtList = gh extension list 2>$null
    if ($ghExtList -match "gh-copilot") {
        Write-Warn "GitHub Copilot CLI already installed"
    } else {
        if (-not $DRY_RUN) {
            Write-Info "Installing GitHub Copilot CLI..."
            gh extension install github/gh-copilot 2>$null
            Write-Success "GitHub Copilot CLI installed (run: gh copilot suggest)"
        }
    }
}

# HTTP debugging
# mitmproxy (replaces Proxyman / Fiddler)
if (Test-Command "uv") {
    if (-not (Test-Command "mitmproxy")) {
        if (-not $DRY_RUN) {
            Write-Info "Installing mitmproxy via uv..."
            uv tool install mitmproxy 2>&1 | Out-File $LOG_FILE -Append
            Write-Success "mitmproxy installed"
        }
    } else {
        Write-Warn "mitmproxy already installed"
    }
}

# Node/JS tooling (via npm)
if (Test-Command "npm") {
    Install-NpmGlobal "typescript" "TypeScript"
    Install-NpmGlobal "tsx" "tsx (TS execute)"
    Install-NpmGlobal "turbo" "Turborepo"
}

# tmux: not native on Windows, but zellij works via WSL or natively
Write-Info "tmux: Not available on Windows. Use Windows Terminal tabs/panes (Ctrl+Shift+T, Alt+Shift+D)"
Install-ScoopPackage "zellij" "zellij (modern terminal multiplexer -- discoverable UI, layouts)"

} # dx

# =============================================================================
if (Test-ShouldRun "ui") {
Write-Banner "UI Development"

Install-WingetPackage "Google.Chrome" "Google Chrome"

} # ui

# =============================================================================
if (Test-ShouldRun "ux") {
Write-Banner "UX & Design"

if (Test-Command "npm") {
    Install-NpmGlobal "lighthouse" "Lighthouse CLI"
}

} # ux

# =============================================================================
if (Test-ShouldRun "docs") {
Write-Banner "Documentation & Diagrams"

Install-ScoopPackage "d2" "d2 (code-to-diagram scripting language)"

if (Test-Command "npm") {
    Install-NpmGlobal "@mermaid-js/mermaid-cli" "Mermaid CLI (render diagrams from CLI)"
}

} # docs

# =============================================================================
if (Test-ShouldRun "win-system") {
Write-Banner "Windows Apps -- System & Utilities"

Install-ScoopPackage "bulk-cask-remover" "BCUninstaller (bulk uninstaller)"
Install-ScoopPackage "7zip" "7-Zip (archive manager)"
Install-ScoopPackage "simplewall" "simplewall (lightweight firewall)"
Install-WingetPackage "QL-Win.QuickLook" "QuickLook (preview files with spacebar)"

# PowerToys already installed in dx section
Write-Info "PowerToys Awake: Included in PowerToys (keeps screen awake)"

# Mullvad VPN
Install-WingetPackage "MullvadVPN.MullvadVPN" "Mullvad VPN (privacy-focused, no account email required)"

Write-Info "Windows built-in: Clipboard History (Win+V), Taskbar management, Alt-Tab, Clock/Calendar"

} # win-system

# =============================================================================
if (Test-ShouldRun "win-productivity") {
Write-Banner "Windows Apps -- Productivity"

Install-WingetPackage "Notion.Notion" "Notion (docs, wikis, project tracking)"
Install-WingetPackage "Notion.NotionCalendar" "Notion Calendar"
Install-ScoopPackage "sharex" "ShareX (replaces Shottr -- screenshots & recording)"
Install-ScoopPackage "espanso" "Espanso (open-source text expander -- snippets, templates)"
Install-ScoopPackage "sumatrapdf" "SumatraPDF (lightweight PDF reader -- replaces Skim)"

# File transfer
Install-WingetPackage "WinSCP.WinSCP" "WinSCP (SFTP/SCP client -- replaces Transmit)"

} # win-productivity

# =============================================================================
if (Test-ShouldRun "win-communication") {
Write-Banner "Windows Apps -- Communication"

Install-WingetPackage "SlackTechnologies.Slack" "Slack"
Install-WingetPackage "Telegram.TelegramDesktop" "Telegram"
Install-WingetPackage "OpenWhisperSystems.Signal" "Signal (end-to-end encrypted messaging)"

} # win-communication

# =============================================================================
if (Test-ShouldRun "win-browsers") {
Write-Banner "Windows Apps -- Browsers"

Install-WingetPackage "Mozilla.Firefox" "Firefox"
Install-WingetPackage "TheBrowserCompany.Arc" "Arc (modern Chromium browser)"
Install-WingetPackage "BraveSoftware.BraveBrowser" "Brave Browser (privacy-focused Chromium)"

Install-NpmGlobal "carbonyl" "Carbonyl (Chromium-based browser for the terminal)"

} # win-browsers

# =============================================================================
if (Test-ShouldRun "win-media") {
Write-Banner "Windows Apps -- Media"

Install-ScoopPackage "mpv" "mpv (modern video player -- replaces IINA)"
Install-ScoopPackage "oxipng" "oxipng (lossless PNG compression)"
Install-ScoopPackage "jpegoptim" "jpegoptim (lossless JPEG compression)"
Install-WingetPackage "TheDocumentFoundation.LibreOffice" "LibreOffice (free office suite)"

} # win-media

# =============================================================================
if (Test-ShouldRun "win-cloud") {
Write-Banner "Windows Apps -- Cloud Storage"

Install-WingetPackage "Google.GoogleDrive" "Google Drive (cloud storage with Docs/Sheets)"
Install-ScoopPackage "rclone" "rclone (sync to any cloud)"
Install-WingetPackage "Syncthing.Syncthing" "Syncthing (real-time device sync)"

} # win-cloud

# =============================================================================
if (Test-ShouldRun "win-focus") {
Write-Banner "Windows Apps -- Focus & Learning"

Write-Info "Reeder: macOS-only RSS reader. Alternatives: Fluent Reader (winget: nicehash.fluentreader)"

} # win-focus

# =============================================================================
if (Test-ShouldRun "win-disk") {
Write-Banner "Windows Apps -- Disk & File Utilities"

# DaisyDisk equivalent removed -- dust and duf (installed in modern-replacements) cover disk analysis

} # win-disk

# =============================================================================
if (Test-ShouldRun "win-bloat") {
Write-Banner "Remove Pre-installed Windows Apps"

$BLOAT_APPS = @(
    @{ Id = "Clipchamp.Clipchamp";                       Name = "Clipchamp" }
    @{ Id = "Microsoft.XboxGameOverlay";                  Name = "Xbox Game Overlay" }
    @{ Id = "Microsoft.XboxGamingOverlay";                Name = "Xbox Gaming Overlay" }
    @{ Id = "Microsoft.Xbox.TCUI";                        Name = "Xbox TCUI" }
    @{ Id = "Microsoft.BingNews";                         Name = "Bing News" }
    @{ Id = "Microsoft.GetHelp";                          Name = "Get Help" }
    @{ Id = "Microsoft.Getstarted";                       Name = "Tips" }
    @{ Id = "microsoft.windowscommunicationsapps";        Name = "Mail and Calendar" }
    @{ Id = "Microsoft.BingWeather";                      Name = "Bing Weather" }
    @{ Id = "Microsoft.WindowsMaps";                      Name = "Windows Maps" }
    @{ Id = "Microsoft.People";                           Name = "People" }
    @{ Id = "Microsoft.MicrosoftSolitaireCollection";     Name = "Solitaire Collection" }
    @{ Id = "Microsoft.MixedReality.Portal";              Name = "Mixed Reality Portal" }
    @{ Id = "Microsoft.549981C3F5F10";                    Name = "Cortana" }
    @{ Id = "Microsoft.WindowsFeedbackHub";               Name = "Feedback Hub" }
    @{ Id = "Microsoft.PowerAutomateDesktop";             Name = "Power Automate Desktop" }
    @{ Id = "MicrosoftTeams";                             Name = "Microsoft Teams (free)" }
    @{ Id = "Microsoft.Todos";                            Name = "Microsoft To Do" }
    # @{ Id = "Microsoft.OneDrive"; Name = "OneDrive" }  # Optional -- uncomment to remove
)

$bloatRemoved = 0
$bloatSkipped = 0
$bloatFailed = 0

foreach ($app in $BLOAT_APPS) {
    if ($DRY_RUN) {
        Write-Info "[DRY RUN] Would remove: $($app.Name) ($($app.Id))"
        continue
    }

    # Check if installed via winget
    $check = winget list --id $app.Id --accept-source-agreements 2>$null
    if ($check -match [regex]::Escape($app.Id)) {
        Write-Info "Removing $($app.Name)..."
        $output = winget uninstall --id $app.Id --accept-source-agreements --silent 2>&1
        $output | Out-File $LOG_FILE -Append
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$($app.Name) removed"
            $bloatRemoved++
        } else {
            Write-Err "Failed to remove $($app.Name)"
            $bloatFailed++
        }
    } else {
        Write-Warn "$($app.Name) -- not found (already removed or not installed)"
        $bloatSkipped++
    }
}

if (-not $DRY_RUN) {
    Write-Host ""
    Write-Info "Bloat removal: $bloatRemoved removed, $bloatSkipped skipped, $bloatFailed failed"
}

} # win-bloat

# =============================================================================
if (Test-ShouldRun "dracula") {
Write-Banner "Dracula Theme"

# VS Code - Dracula theme
if (Test-Command "code") {
    $vsCodeExt = code --list-extensions 2>$null
    if ($vsCodeExt -match "dracula-theme.theme-dracula") {
        Write-Warn "VS Code Dracula theme already installed"
    } else {
        if (-not $DRY_RUN) {
            Write-Info "Installing Dracula theme for VS Code..."
            code --install-extension dracula-theme.theme-dracula
            Write-Success "VS Code Dracula theme installed"
        }
    }
}

# bat (Dracula is built-in, just needs to be set)
if (Test-Command "bat") {
    $batConfigDir = & bat --config-dir 2>$null
    if ($batConfigDir) {
        if (-not (Test-Path $batConfigDir)) { New-Item -ItemType Directory -Path $batConfigDir -Force | Out-Null }
        $batConfig = Join-Path $batConfigDir "config"
        if ((Test-Path $batConfig) -and (Select-String -Path $batConfig -Pattern "Dracula" -Quiet -ErrorAction SilentlyContinue)) {
            Write-Warn "bat Dracula theme already configured"
        } else {
            if (-not $DRY_RUN) {
                Add-Content -Path $batConfig -Value '--theme="Dracula"'
                Write-Success "bat Dracula theme configured"
            }
        }
    }
}

# delta (git diffs) - Dracula colors
if (-not $DRY_RUN) {
    $deltaSyntax = git config --global delta.syntax-theme 2>$null
    if (-not $deltaSyntax) {
        Write-Info "Setting delta to Dracula theme..."
        git config --global delta.syntax-theme Dracula
        Write-Success "delta Dracula theme configured"
    } else {
        Write-Warn "delta syntax theme already set"
    }
}

# fzf Dracula colors (will be set in shell profile)
Write-Info "fzf Dracula colors will be set in PowerShell profile"

# Starship rich prompt config (Dracula themed)
$starshipConfig = Join-Path $HOME ".config\starship.toml"
if ((Test-Path $starshipConfig) -and (Select-String -Path $starshipConfig -Pattern "dracula" -Quiet -ErrorAction SilentlyContinue)) {
    Write-Warn "Starship config already configured"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating rich Starship prompt config..."
        $starshipDir = Split-Path $starshipConfig
        if (-not (Test-Path $starshipDir)) { New-Item -ItemType Directory -Path $starshipDir -Force | Out-Null }
        $starshipToml = @"
# =============================================================================
# Starship Prompt — Dracula themed, info-rich
# =============================================================================

# Use Dracula colors everywhere
palette = "dracula"

# Prompt format: directory, git, languages, duration, newline, character
format = """
[┌──](comment)\
`$os\
`$username\
`$hostname\
`$directory\
`$git_branch\
`$git_status\
`$git_state\
`$nodejs\
`$python\
`$rust\
`$go\
`$docker_context\
`$aws\
`$terraform\
`$cmd_duration\
`$jobs\
`$fill\
`$battery\
`$time
[└─](comment)`$character"""

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
format = "[`$symbol ](`$style)"

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
format = "[`$user](`$style) "

# -- Hostname (only show if SSH) ----------------------------------------------
[hostname]
ssh_only = true
style = "fg:pink"
format = "[@`$hostname](`$style) "

# -- Directory ----------------------------------------------------------------
[directory]
style = "bold cyan"
format = "[`$path](`$style)[`$read_only](`$read_only_style) "
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
format = "[`$symbol`$branch(:`$remote_branch)](`$style) "
truncation_length = 24

# -- Git status ---------------------------------------------------------------
[git_status]
style = "fg:red"
format = '([`$all_status`$ahead_behind](`$style) )'
conflicted = "⚡`${count} "
ahead = "⇡`${count} "
behind = "⇣`${count} "
diverged = "⇕⇡`${ahead_count}⇣`${behind_count} "
untracked = "?`${count} "
stashed = "📦`${count} "
modified = "!`${count} "
staged = "+`${count} "
renamed = "»`${count} "
deleted = "✘`${count} "

# -- Git state (rebase, merge, etc.) ------------------------------------------
[git_state]
style = "bold fg:orange"
format = "[`$state( `$progress_current/`$progress_total)](`$style) "
rebase = "REBASING"
merge = "MERGING"
revert = "REVERTING"
cherry_pick = "CHERRY-PICKING"
bisect = "BISECTING"

# -- Node.js ------------------------------------------------------------------
[nodejs]
symbol = " "
style = "fg:green"
format = "[`$symbol`$version](`$style) "
detect_files = ["package.json", ".nvmrc"]
detect_extensions = []

# -- Python -------------------------------------------------------------------
[python]
symbol = " "
style = "fg:yellow"
format = '[`$symbol`$version( \(`$virtualenv\))](`$style) '
detect_extensions = ["py"]

# -- Rust ---------------------------------------------------------------------
[rust]
symbol = "🦀 "
style = "fg:orange"
format = "[`$symbol`$version](`$style) "

# -- Go ----------------------------------------------------------------------
[golang]
symbol = " "
style = "fg:cyan"
format = "[`$symbol`$version](`$style) "

# -- Docker context -----------------------------------------------------------
[docker_context]
symbol = " "
style = "fg:cyan"
format = "[`$symbol`$context](`$style) "
only_with_files = true

# -- AWS profile --------------------------------------------------------------
[aws]
symbol = "☁️ "
style = "bold fg:orange"
format = "[`$symbol`$profile(\\(`$region\\))](`$style) "

# -- Terraform ----------------------------------------------------------------
[terraform]
symbol = "💠 "
style = "fg:purple"
format = "[`$symbol`$workspace](`$style) "

# -- Command duration (show if > 3 seconds) -----------------------------------
[cmd_duration]
min_time = 3_000
style = "fg:yellow"
format = "[⏱ `$duration](`$style) "
show_milliseconds = false

# -- Background jobs ----------------------------------------------------------
[jobs]
symbol = "✦"
style = "bold fg:cyan"
number_threshold = 1
format = "[`$symbol`$number](`$style) "

# -- Battery (show if < 30%) --------------------------------------------------
[battery]
format = "[`$symbol`$percentage](`$style) "

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
format = "[`$time](`$style)"
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
"@
        Set-Content -Path $starshipConfig -Value $starshipToml
        Write-Success "Starship prompt configured (rich two-line prompt, Dracula theme)"
    }
}

# lazygit Dracula theme
$lazygitConfigDir = Join-Path $env:APPDATA "lazygit"
$lazygitConfig = Join-Path $lazygitConfigDir "config.yml"
if ((Test-Path $lazygitConfig) -and (Select-String -Path $lazygitConfig -Pattern "activeBorderColor" -Quiet -ErrorAction SilentlyContinue)) {
    Write-Warn "lazygit theme already configured"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating lazygit Dracula config..."
        if (-not (Test-Path $lazygitConfigDir)) { New-Item -ItemType Directory -Path $lazygitConfigDir -Force | Out-Null }
        $lazygitTheme = @"
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
  open: "start {{filename}}"
  openLink: "start {{link}}"
notARepository: skip
promptToReturnFromSubprocess: false
"@
        Set-Content -Path $lazygitConfig -Value $lazygitTheme
        Write-Success "lazygit configured (Dracula theme, delta pager, auto-fetch, VS Code editor)"
    }
}

# k9s Dracula skin
$k9sConfigDir = Join-Path $env:LOCALAPPDATA "k9s"
$k9sSkinsDir = Join-Path $k9sConfigDir "skins"
$k9sSkin = Join-Path $k9sSkinsDir "dracula.yaml"
if (Test-Path $k9sSkin) {
    Write-Warn "k9s Dracula skin already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating k9s Dracula skin..."
        if (-not (Test-Path $k9sSkinsDir)) { New-Item -ItemType Directory -Path $k9sSkinsDir -Force | Out-Null }
        $k9sDracula = @"
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
"@
        Set-Content -Path $k9sSkin -Value $k9sDracula

        # Set dracula as active skin
        $k9sMainConfig = Join-Path $k9sConfigDir "config.yaml"
        if (-not (Test-Path $k9sMainConfig)) {
            Set-Content -Path $k9sMainConfig -Value @"
k9s:
  ui:
    skin: dracula
"@
        }
        Write-Success "k9s Dracula skin configured"
    }
}

# Windows Terminal Dracula color scheme
if (-not $DRY_RUN) {
    $wtSettingsPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wtSettingsPath) {
        Write-Info "Adding Dracula color scheme to Windows Terminal..."
        try {
            # Check if Dracula already present before parsing (preserves JSONC comments)
            $wtRawContent = Get-Content $wtSettingsPath -Raw -ErrorAction SilentlyContinue
            if ($wtRawContent -and $wtRawContent -match "Dracula") {
                Write-Warn "Windows Terminal Dracula scheme already exists"
            } else {
                # Warning: ConvertFrom-Json strips JSONC comments — backup created
                Write-Warn "Adding Dracula theme requires modifying settings.json — backup created"
                Copy-Item $wtSettingsPath "$wtSettingsPath.bak" -Force
            }
            $wtSettings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
            $draculaScheme = @{
                name        = "Dracula"
                background  = "#282A36"
                black       = "#21222C"
                blue        = "#BD93F9"
                brightBlack = "#6272A4"
                brightBlue  = "#D6ACFF"
                brightCyan  = "#A4FFFF"
                brightGreen = "#69FF94"
                brightPurple = "#FF92DF"
                brightRed   = "#FF6E6E"
                brightWhite = "#FFFFFF"
                brightYellow = "#FFFFA5"
                cursorColor = "#F8F8F2"
                cyan        = "#8BE9FD"
                foreground  = "#F8F8F2"
                green       = "#50FA7B"
                purple      = "#FF79C6"
                red         = "#FF5555"
                selectionBackground = "#44475A"
                white       = "#F8F8F2"
                yellow      = "#F1FA8C"
            }
            # Ensure schemes array exists
            if (-not $wtSettings.schemes) {
                $wtSettings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @()
            }
            $existingScheme = $wtSettings.schemes | Where-Object { $_.name -eq "Dracula" }
            if (-not $existingScheme) {
                $wtSettings.schemes += $draculaScheme
                $wtSettings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath
                Write-Success "Windows Terminal Dracula color scheme added"
            } else {
                Write-Warn "Windows Terminal Dracula scheme already exists"
            }
        } catch {
            Write-Err "Could not update Windows Terminal settings: $_"
        }
    } else {
        Write-Info "Windows Terminal settings not found (install Windows Terminal first)"
    }
}

# Alacritty Dracula config
$alacrittyConfigDir = Join-Path $env:APPDATA "alacritty"
$alacrittyConfig = Join-Path $alacrittyConfigDir "alacritty.toml"
if (Test-Path $alacrittyConfig) {
    Write-Warn "Alacritty config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Alacritty Dracula config..."
        if (-not (Test-Path $alacrittyConfigDir)) { New-Item -ItemType Directory -Path $alacrittyConfigDir -Force | Out-Null }
        $alacrittyDracula = @"
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
decorations = "Full"
opacity = 0.97

# Dracula color scheme
[colors.primary]
background = "#282a36"
foreground = "#f8f8f2"

[colors.cursor]
text = "#282a36"
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
"@
        Set-Content -Path $alacrittyConfig -Value $alacrittyDracula
        Write-Success "Alacritty configured (JetBrains Mono, Dracula theme)"
    }
}

} # dracula

# =============================================================================
if (Test-ShouldRun "configs") {
Write-Banner "Tool Configurations"

# ---- git global config ----
if (-not $DRY_RUN) {
    Write-Info "Configuring git global settings..."
    git config --global init.defaultBranch main 2>$null
    git config --global pull.rebase true
    git config --global rebase.autoStash true
    git config --global diff.algorithm histogram
    git config --global commit.verbose true
    git config --global help.autocorrect 5
    git config --global column.ui auto
    git config --global branch.sort -committerdate
    # Remember merge conflict resolutions and auto-apply next time
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
    git config --global alias.standup "!git log --oneline --since='yesterday' --author=`"`$(git config user.name)`""

    # Branch management
    git config --global alias.recent "branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)' -n 15"
    git config --global alias.cleanup "!git branch --merged main | grep -v '\\*\\|main\\|master' | xargs -n 1 git branch -d"
    git config --global alias.gone "!git fetch -p && git branch -vv | grep ': gone]' | awk '{print `$1}' | xargs -r git branch -d"

    # Diff
    git config --global alias.dft "!git -c diff.external=difft diff"
    git config --global alias.dfl "!git -c diff.external=difft log -p --ext-diff"
    git config --global alias.diff-names "diff --name-only"
    git config --global alias.diff-stat "diff --stat"

    # Worktree shortcuts
    git config --global alias.wt "worktree"
    git config --global alias.wta "worktree add"
    git config --global alias.wtl "worktree list"

    Write-Success "git global settings configured"
}

# ---- GPG ----
$gpgAgentConf = Join-Path $HOME ".gnupg\gpg-agent.conf"
if ((Test-Path $gpgAgentConf) -and (Select-String -Path $gpgAgentConf -Pattern "default-cache-ttl" -Quiet -ErrorAction SilentlyContinue)) {
    Write-Warn "GPG agent already configured"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Configuring GPG agent..."
        $gpgDir = Join-Path $HOME ".gnupg"
        if (-not (Test-Path $gpgDir)) { New-Item -ItemType Directory -Path $gpgDir -Force | Out-Null }
        Set-Content -Path $gpgAgentConf -Value @"
# Cache passphrase for 8 hours
default-cache-ttl 28800
max-cache-ttl 28800
"@
        Write-Success "GPG agent configured (passphrases cached 8 hours)"
    }
}

# ---- aria2 ----
$aria2ConfigDir = Join-Path $HOME ".aria2"
$aria2Config = Join-Path $aria2ConfigDir "aria2.conf"
if (Test-Path $aria2Config) {
    Write-Warn "aria2 config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating aria2 configuration..."
        if (-not (Test-Path $aria2ConfigDir)) { New-Item -ItemType Directory -Path $aria2ConfigDir -Force | Out-Null }
        $aria2Content = @"
## aria2 configuration

# -- Connections & Speed
max-concurrent-downloads=5
max-connection-per-server=16
split=16
min-split-size=1M

# -- Retry & Resume
max-tries=5
retry-wait=10
continue=true

# -- File Management
dir=$(Join-Path $HOME 'Downloads')
file-allocation=none
auto-file-renaming=true

# -- Console Output
summary-interval=0
human-readable=true
enable-color=true

# -- HTTP/HTTPS
content-disposition-default-utf8=true
http-accept-gzip=true
user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36

# -- BitTorrent
enable-dht=true
enable-dht6=true
listen-port=6881-6999
seed-ratio=1.0
max-overall-upload-limit=256K

# -- Disk Cache
disk-cache=64M
"@
        Set-Content -Path $aria2Config -Value $aria2Content
        Write-Success "aria2 configured (16 connections, auto-resume, BitTorrent)"
    }
}

# ---- atuin ----
$atuinConfigDir = Join-Path $HOME ".config\atuin"
$atuinConfig = Join-Path $atuinConfigDir "config.toml"
if (Test-Path $atuinConfig) {
    Write-Warn "atuin config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating atuin configuration..."
        if (-not (Test-Path $atuinConfigDir)) { New-Item -ItemType Directory -Path $atuinConfigDir -Force | Out-Null }
        Set-Content -Path $atuinConfig -Value @"
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
    "^ls`$",
    "^ll`$",
    "^la`$",
    "^cd ",
    "^clear`$",
    "^exit`$",
    "^pwd`$",
    "^\\.",
    "^cat ",
    "^echo ",
    "^export ",
]

# Secrets: don't record commands containing these patterns
secrets_filter = true

# -- Stats --------------------------------------------------------------------
# Show stats in search footer (e.g., "3,402 commands")
stats.show_in_footer = true
"@
        Write-Success "atuin configured (fuzzy search, local-only, history filter, enter=paste)"
    }
}

# ---- VS Code settings ----
$vscodeSettingsDir = Join-Path $env:APPDATA "Code\User"
$vscodeSettings = Join-Path $vscodeSettingsDir "settings.json"
if (Test-Path $vscodeSettings) {
    Write-Warn "VS Code settings.json already exists -- not overwriting"
    Write-Info "  To use Dracula, add: `"workbench.colorTheme`": `"Dracula`""
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating VS Code settings..."
        if (-not (Test-Path $vscodeSettingsDir)) { New-Item -ItemType Directory -Path $vscodeSettingsDir -Force | Out-Null }
        Set-Content -Path $vscodeSettings -Value @"
{
    "workbench.colorTheme": "Dracula",
    "workbench.iconTheme": "vs-seti",
    "workbench.startupEditor": "none",
    "workbench.tree.indent": 16,

    "editor.fontFamily": "'JetBrains Mono', 'Fira Code', Consolas, monospace",
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
        "*.ts": "`${capture}.js, `${capture}.d.ts, `${capture}.js.map, `${capture}.test.ts, `${capture}.spec.ts",
        "*.tsx": "`${capture}.test.tsx, `${capture}.spec.tsx, `${capture}.stories.tsx",
        "*.js": "`${capture}.js.map, `${capture}.test.js, `${capture}.spec.js",
        "package.json": "package-lock.json, pnpm-lock.yaml, yarn.lock, .npmrc, .nvmrc, .node-version, .eslintrc*, .prettierrc*, tsconfig*.json, vite.config.*, vitest.config.*, jest.config.*, tailwind.config.*, postcss.config.*",
        "README.md": "LICENSE, CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md",
        ".env": ".env.*, .env.local, .env.development, .env.production, .env.test",
        "Dockerfile": "docker-compose*.yml, .dockerignore",
        "Cargo.toml": "Cargo.lock, rust-toolchain.toml",
        "go.mod": "go.sum"
    },
    "explorer.confirmDragAndDrop": false,
    "explorer.confirmDelete": true,

    "terminal.integrated.fontFamily": "'JetBrains Mono NF', 'MesloLGS NF', Consolas",
    "terminal.integrated.fontSize": 13,
    "terminal.integrated.cursorStyle": "line",
    "terminal.integrated.cursorBlinking": true,
    "terminal.integrated.defaultProfile.windows": "PowerShell",

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
"@
        Write-Success "VS Code settings configured with Dracula theme"
    }
}

# ---- VS Code essential extensions ----
if ((Test-Command "code") -and -not $DRY_RUN) {
    Write-Info "Installing VS Code extensions..."
    $vscodeExtensions = @(
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
    $installedExts = code --list-extensions 2>$null
    foreach ($ext in $vscodeExtensions) {
        if ($installedExts -match $ext) {
            Write-Warn "VS Code extension $ext already installed"
        } else {
            code --install-extension $ext 2>$null
        }
    }
    Write-Success "VS Code extensions installed"
}

# ---- VS Code keybindings ----
$vscodeKeybindings = Join-Path $vscodeSettingsDir "keybindings.json"
if (Test-Path $vscodeKeybindings) {
    Write-Warn "VS Code keybindings already exist"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating VS Code keybindings..."
        if (-not (Test-Path $vscodeSettingsDir)) { New-Item -ItemType Directory -Path $vscodeSettingsDir -Force | Out-Null }
        Set-Content -Path $vscodeKeybindings -Value @"
[
    { "key": "ctrl+``", "command": "workbench.action.terminal.toggleTerminal" },
    { "key": "ctrl+shift+``", "command": "workbench.action.terminal.new" },
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
"@
        Write-Success "VS Code keybindings created"
    }
}

# ---- Fonts ----
Write-Info "Installing development fonts..."
Install-ScoopPackage "JetBrains-Mono" "JetBrains Mono (primary dev font)"
Install-ScoopPackage "JetBrainsMono-NF" "JetBrains Mono Nerd Font (with icons)"
Install-ScoopPackage "Meslo-NF" "MesloLGS Nerd Font (terminal icons)"
Install-ScoopPackage "FiraCode" "Fira Code (ligature font)"
Install-ScoopPackage "FiraCode-NF" "Fira Code Nerd Font (with icons)"
Install-ScoopPackage "Inter" "Inter (best UI font for web/design)"
Install-ScoopPackage "Hack-NF" "Hack Nerd Font (classic terminal font)"
Write-Success "Development fonts installed"

# ---- shellcheck config ----
$shellcheckRc = Join-Path $HOME ".shellcheckrc"
if (Test-Path $shellcheckRc) {
    Write-Warn "shellcheck config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating shellcheck configuration..."
        Set-Content -Path $shellcheckRc -Value @"
# Follow sourced files
external-sources=true

# Disable common false positives
# SC1091: Not following sourced file (not input)
# SC2034: Variable appears unused (often used in sourced files)
disable=SC1091,SC2034
"@
        Write-Success "shellcheck configured"
    }
}

# ---- glow config (Dracula) ----
$glowConfigDir = Join-Path $HOME ".config\glow"
$glowConfig = Join-Path $glowConfigDir "glow.yml"
if (Test-Path $glowConfig) {
    Write-Warn "glow config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating glow configuration..."
        if (-not (Test-Path $glowConfigDir)) { New-Item -ItemType Directory -Path $glowConfigDir -Force | Out-Null }
        Set-Content -Path $glowConfig -Value @"
# glow configuration
style: "dracula"
local: false
mouse: true
pager: true
width: 120
"@
        Write-Success "glow configured (Dracula style, mouse, pager)"
    }
}

# ---- ngrok config ----
$ngrokConfigDir = Join-Path $HOME ".config\ngrok"
if (-not (Test-Path $ngrokConfigDir)) {
    if (-not $DRY_RUN) {
        Write-Info "Creating ngrok config directory..."
        New-Item -ItemType Directory -Path $ngrokConfigDir -Force | Out-Null
        Set-Content -Path (Join-Path $ngrokConfigDir "ngrok.yml") -Value @"
# ngrok configuration
# Add your authtoken: ngrok config add-authtoken <TOKEN>
version: "3"
agent:
  metadata: "dev-machine"
"@
        Write-Success "ngrok config created"
    }
} else {
    Write-Warn "ngrok config directory already exists"
}

# ---- yt-dlp config ----
$ytdlpConfigDir = Join-Path $HOME ".config\yt-dlp"
$ytdlpConfig = Join-Path $ytdlpConfigDir "config"
if (Test-Path $ytdlpConfig) {
    Write-Warn "yt-dlp config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating yt-dlp configuration..."
        if (-not (Test-Path $ytdlpConfigDir)) { New-Item -ItemType Directory -Path $ytdlpConfigDir -Force | Out-Null }
        Set-Content -Path $ytdlpConfig -Value @"
# yt-dlp configuration
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
"@
        Write-Success "yt-dlp configured (best quality, aria2c downloader, metadata)"
    }
}

# ---- caddy config ----
$caddyConfigDir = Join-Path $HOME ".config\caddy"
if (-not (Test-Path $caddyConfigDir)) {
    if (-not $DRY_RUN) {
        Write-Info "Creating Caddy config template..."
        New-Item -ItemType Directory -Path $caddyConfigDir -Force | Out-Null
        Set-Content -Path (Join-Path $caddyConfigDir "Caddyfile") -Value @"
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
"@
        Write-Success "Caddy config template created"
    }
} else {
    Write-Warn "Caddy config directory already exists"
}

# ---- act config ----
$actConfig = Join-Path $HOME ".actrc"
if (Test-Path $actConfig) {
    Write-Warn "act config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating act configuration..."
        Set-Content -Path $actConfig -Value @"
# act configuration (run GitHub Actions locally)
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=catthehacker/ubuntu:act-20.04
--reuse
"@
        Write-Success "act configured (medium Ubuntu images, container reuse)"
    }
}

# ---- miller config ----
$mlrConfig = Join-Path $HOME ".mlrrc"
if (Test-Path $mlrConfig) {
    Write-Warn "miller config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating miller configuration..."
        Set-Content -Path $mlrConfig -Value @"
# miller (mlr) configuration
--opprint
--icsv
--skip-trivial-records
"@
        Write-Success "miller configured (CSV input, pretty table output)"
    }
}

# ---- asciinema config ----
$asciinemaConfigDir = Join-Path $HOME ".config\asciinema"
$asciinemaConfig = Join-Path $asciinemaConfigDir "config"
if (Test-Path $asciinemaConfig) {
    Write-Warn "asciinema config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating asciinema configuration..."
        if (-not (Test-Path $asciinemaConfigDir)) { New-Item -ItemType Directory -Path $asciinemaConfigDir -Force | Out-Null }
        Set-Content -Path $asciinemaConfig -Value @"
[record]
idle_time_limit = 2
stdin = no
command = pwsh
overwrite = yes
"@
        Write-Success "asciinema configured (2s idle limit, no keystroke recording)"
    }
}

# ---- gh-dash config ----
$ghDashConfigDir = Join-Path $HOME ".config\gh-dash"
$ghDashConfig = Join-Path $ghDashConfigDir "config.yml"
if (Test-Path $ghDashConfig) {
    Write-Warn "gh-dash config already exists"
} else {
    if ((Test-Command "gh") -and -not $DRY_RUN) {
        $ghExtList = gh extension list 2>$null
        if ($ghExtList -match "gh-dash") {
            Write-Info "Creating gh-dash configuration..."
            if (-not (Test-Path $ghDashConfigDir)) { New-Item -ItemType Directory -Path $ghDashConfigDir -Force | Out-Null }
            Set-Content -Path $ghDashConfig -Value @"
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
"@
            Write-Success "gh-dash configured (Dracula theme, PR/issue sections)"
        }
    }
}

# ---- stern config ----
$sternConfig = Join-Path $HOME ".config\stern\config.yaml"
if (Test-Path $sternConfig) {
    Write-Warn "stern config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating stern configuration..."
        $sternDir = Split-Path $sternConfig
        if (-not (Test-Path $sternDir)) { New-Item -ItemType Directory -Path $sternDir -Force | Out-Null }
        Set-Content -Path $sternConfig -Value @"
# stern configuration (multi-pod log tailing)
template: '{{color .PodColor .PodName}} {{color .ContainerColor .ContainerName}} {{.Message}}{{"\n"}}'
tail: 50
timestamps: short
since: 5m
"@
        Write-Success "stern configured (50 tail lines, 5m lookback, timestamps)"
    }
}

# ---- SSH config ----
$sshConfig = Join-Path $HOME ".ssh\config"
if (Test-Path $sshConfig) {
    Write-Warn "SSH config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating SSH configuration..."
        $sshDir = Join-Path $HOME ".ssh"
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        $socketsDir = Join-Path $sshDir "sockets"
        if (-not (Test-Path $socketsDir)) { New-Item -ItemType Directory -Path $socketsDir -Force | Out-Null }
        Set-Content -Path $sshConfig -Value @"
# =============================================================================
# SSH Configuration
# =============================================================================

# -- Global Defaults ----------------------------------------------------------
Host *
    # Keep connections alive (prevents timeouts)
    ServerAliveInterval 60
    ServerAliveCountMax 3

    # Use ssh-agent
    AddKeysToAgent yes
    IdentityFile $($HOME)\.ssh\id_ed25519

    # Faster connections
    Compression yes

    # Security: only use strong algorithms
    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    PubkeyAcceptedAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256

# -- GitHub -------------------------------------------------------------------
Host github.com
    HostName github.com
    User git
    IdentityFile $($HOME)\.ssh\id_ed25519

# -- Example: shortcut for a server ------------------------------------------
# Host myserver
#     HostName 192.168.1.100
#     User deploy
#     Port 22
#     IdentityFile $($HOME)\.ssh\id_ed25519
"@
        Write-Success "SSH configured (keep-alive, strong algorithms)"
    }
}

# Generate SSH key if none exists
if (-not (Test-Path (Join-Path $HOME ".ssh\id_ed25519"))) {
    Write-Info "No SSH key found. To generate one, run:"
    Write-Host '  ssh-keygen -t ed25519 -C "your_email@example.com"'
} else {
    Write-Warn "SSH key already exists at ~/.ssh/id_ed25519"
}

# ---- Global .gitignore ----
$globalGitignore = Join-Path $HOME ".gitignore_global"
if (Test-Path $globalGitignore) {
    Write-Warn "Global .gitignore already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating global .gitignore..."
        Set-Content -Path $globalGitignore -Value @"
# =============================================================================
# Global .gitignore -- applied to ALL repositories
# =============================================================================

# -- Windows ------------------------------------------------------------------
Thumbs.db
ehthumbs.db
Desktop.ini
`$RECYCLE.BIN/

# -- macOS (for cross-platform compat) ---------------------------------------
.DS_Store
.DS_Store?
._*

# -- Editors ------------------------------------------------------------------
.vscode/settings.json
.vscode/launch.json
*.code-workspace
.idea/
*.iml
*.swp
*.swo
*~
.netrwhist
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
*.dll
coverage/
.nyc_output/
"@
        git config --global core.excludesfile $globalGitignore
        Write-Success "Global .gitignore created and registered with git"
    }
}

# ---- .npmrc ----
$npmrc = Join-Path $HOME ".npmrc"
if (Test-Path $npmrc) {
    Write-Warn ".npmrc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating .npmrc..."
        Set-Content -Path $npmrc -Value @"
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

# Engine strict
engine-strict=true
"@
        Write-Success ".npmrc configured (save-exact, no telemetry, prefer-offline)"
    }
}

# ---- .editorconfig ----
$editorconfig = Join-Path $HOME ".editorconfig"
if (Test-Path $editorconfig) {
    Write-Warn ".editorconfig already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating global .editorconfig..."
        Set-Content -Path $editorconfig -Value @"
# EditorConfig -- cross-editor consistency
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

[*.ps1]
indent_size = 4
"@
        Write-Success ".editorconfig created (utf-8, lf, 2-space indent, trim whitespace)"
    }
}

# ---- .prettierrc ----
$prettierrc = Join-Path $HOME ".prettierrc"
if (Test-Path $prettierrc) {
    Write-Warn ".prettierrc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating global .prettierrc..."
        Set-Content -Path $prettierrc -Value @"
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
"@
        Write-Success ".prettierrc created (single quotes, trailing commas, 100 width)"
    }
}

# ---- .curlrc ----
$curlrc = Join-Path $HOME ".curlrc"
if (Test-Path $curlrc) {
    Write-Warn ".curlrc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating .curlrc..."
        Set-Content -Path $curlrc -Value @"
--location
--show-error
--fail
--max-time 30
--connect-timeout 10
--retry 3
--retry-delay 2
--compressed
--user-agent "curl/dev"
"@
        Write-Success ".curlrc configured (follow redirects, retry, compression, timeouts)"
    }
}

# ---- Docker daemon config ----
$dockerConfigDir = Join-Path $HOME ".docker"
$dockerDaemon = Join-Path $dockerConfigDir "daemon.json"
if (Test-Path $dockerDaemon) {
    Write-Warn "Docker daemon.json already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Docker daemon configuration..."
        if (-not (Test-Path $dockerConfigDir)) { New-Item -ItemType Directory -Path $dockerConfigDir -Force | Out-Null }
        Set-Content -Path $dockerDaemon -Value @"
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
"@
        Write-Success "Docker configured (BuildKit, log rotation 10m x 3, garbage collection)"
    }
}

# ---- Docker buildx ----
if (-not $DRY_RUN) {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker buildx install 2>$null
    }
}

# ---- .hushlogin ----
# Skipped — .hushlogin has no effect on Windows

# ---- ripgrep config ----
$ripgreprc = Join-Path $HOME ".ripgreprc"
if (Test-Path $ripgreprc) {
    Write-Warn "~/.ripgreprc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating ripgrep configuration..."
        Set-Content -Path $ripgreprc -Value @"
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

# Custom type definitions
--type-add=web:*.{html,css,scss,js,jsx,ts,tsx,vue,svelte}
--type-add=config:*.{json,yaml,yml,toml,ini,conf}
--type-add=doc:*.{md,mdx,txt,rst}
--type-add=style:*.{css,scss,sass,less}
"@
        Write-Success "~/.ripgreprc configured (smart-case, hidden files, custom types)"
    }
}

# ---- fd ignore ----
$fdignore = Join-Path $HOME ".fdignore"
if (Test-Path $fdignore) {
    Write-Warn "~/.fdignore already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating fd ignore patterns..."
        Set-Content -Path $fdignore -Value @"
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
Thumbs.db
`$RECYCLE.BIN/
"@
        Write-Success "~/.fdignore created"
    }
}

# ---- btop Dracula theme ----
$btopConfigDir = Join-Path $HOME ".config\btop"
$btopConfig = Join-Path $btopConfigDir "btop.conf"
if (Test-Path $btopConfig) {
    Write-Warn "btop config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating btop configuration..."
        $btopThemesDir = Join-Path $btopConfigDir "themes"
        if (-not (Test-Path $btopThemesDir)) { New-Item -ItemType Directory -Path $btopThemesDir -Force | Out-Null }
        Set-Content -Path $btopConfig -Value @"
#? Config file for btop
color_theme = "dracula"
update_ms = 1000
proc_sorting = "cpu lazy"
shown_boxes = "cpu mem net proc"
proc_tree = true
mem_graphs = true
truecolor = true
rounded_corners = true
"@
        Set-Content -Path (Join-Path $btopThemesDir "dracula.theme") -Value @"
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
"@
        Write-Success "btop configured with Dracula theme"
    }
}

# ---- lazydocker Dracula config ----
$lazydockerConfigDir = Join-Path $HOME ".config\lazydocker"
$lazydockerConfig = Join-Path $lazydockerConfigDir "config.yml"
if (Test-Path $lazydockerConfig) {
    Write-Warn "lazydocker config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating lazydocker configuration..."
        if (-not (Test-Path $lazydockerConfigDir)) { New-Item -ItemType Directory -Path $lazydockerConfigDir -Force | Out-Null }
        Set-Content -Path $lazydockerConfig -Value @"
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
"@
        Write-Success "lazydocker configured with Dracula theme"
    }
}

# ---- Git commit template ----
$gitCommitTemplate = Join-Path $HOME ".gitmessage"
if (Test-Path $gitCommitTemplate) {
    Write-Warn "Git commit template already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating git commit template..."
        Set-Content -Path $gitCommitTemplate -Value @"
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
"@
        git config --global commit.template $gitCommitTemplate
        Write-Success "Git commit template created and registered"
    }
}

# ---- Global git hooks directory ----
$gitHooksDir = Join-Path $HOME ".config\git\hooks"
if (Test-Path $gitHooksDir) {
    Write-Warn "Global git hooks directory already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating global git hooks..."
        New-Item -ItemType Directory -Path $gitHooksDir -Force | Out-Null
        # Pre-commit hook using bash (Git for Windows includes bash)
        Set-Content -Path (Join-Path $gitHooksDir "pre-commit") -Value @"
#!/usr/bin/env bash
# Global pre-commit hook -- runs on ALL repos

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
large_files=`$(git diff --cached --name-only --diff-filter=d | while read f; do
    size=`$(wc -c < "`$f" 2>/dev/null | tr -d ' ')
    if [[ "`$size" -gt 5242880 ]]; then
        echo "  `$f (`$(( size / 1048576 ))MB)"
    fi
done)
if [[ -n "`$large_files" ]]; then
    echo ""
    echo "WARNING: Large files detected (>5MB):"
    echo "`$large_files"
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
"@
        git config --global core.hooksPath $gitHooksDir
        Write-Success "Global git hooks created (debug check, large file check, conflict markers)"
    }
}

# ---- AWS config ----
$awsConfig = Join-Path $HOME ".aws\config"
if (Test-Path $awsConfig) {
    Write-Warn "AWS config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating AWS CLI configuration..."
        $awsDir = Join-Path $HOME ".aws"
        if (-not (Test-Path $awsDir)) { New-Item -ItemType Directory -Path $awsDir -Force | Out-Null }
        Set-Content -Path $awsConfig -Value @"
# AWS CLI configuration
[default]
region = us-east-1
output = json
cli_pager = bat --style=plain
cli_auto_prompt = on-partial
retry_mode = adaptive
max_attempts = 3

# SSO profile template:
# [profile my-dev]
# sso_start_url = https://myorg.awsapps.com/start
# sso_region = us-east-1
# sso_account_id = 123456789012
# sso_role_name = DeveloperAccess
# region = us-east-1
# output = json
"@
        Write-Success "AWS CLI configured (us-east-1, json, bat pager, auto-prompt)"
    }
}

# ---- GitHub CLI config ----
$ghConfigDir = Join-Path $env:APPDATA "GitHub CLI"
$ghConfig = Join-Path $ghConfigDir "config.yml"
if (Test-Path $ghConfig) {
    Write-Warn "GitHub CLI config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating GitHub CLI configuration..."
        if (-not (Test-Path $ghConfigDir)) { New-Item -ItemType Directory -Path $ghConfigDir -Force | Out-Null }
        Set-Content -Path $ghConfig -Value @"
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
    rerun: run rerun --failed
    pm: pr merge --squash --delete-branch
    rel: release create --generate-notes
"@
        Write-Success "GitHub CLI configured (SSH protocol, VS Code editor, delta pager, aliases)"
    }
}

# ---- pip config (Windows path: APPDATA\pip\pip.ini) ----
$pipConfigDir = Join-Path $env:APPDATA "pip"
$pipConfig = Join-Path $pipConfigDir "pip.ini"
if (Test-Path $pipConfig) {
    Write-Warn "pip config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating pip configuration..."
        if (-not (Test-Path $pipConfigDir)) { New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null }
        Set-Content -Path $pipConfig -Value @"
[global]
require-virtualenv = true
disable-pip-version-check = true
no-input = true
timeout = 30

[install]
compile = true
"@
        Write-Success "pip configured (require virtualenv, no telemetry)"
    }
}

# ---- .gemrc ----
$gemrc = Join-Path $HOME ".gemrc"
if (Test-Path $gemrc) {
    Write-Warn "~/.gemrc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating gemrc..."
        Set-Content -Path $gemrc -Value "gem: --no-document"
        Write-Success "~/.gemrc created (no docs on gem install)"
    }
}

# ---- pgcli config ----
$pgcliConfigDir = Join-Path $HOME ".config\pgcli"
$pgcliConfig = Join-Path $pgcliConfigDir "config"
if (Test-Path $pgcliConfig) {
    Write-Warn "pgcli config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating pgcli configuration..."
        if (-not (Test-Path $pgcliConfigDir)) { New-Item -ItemType Directory -Path $pgcliConfigDir -Force | Out-Null }
        Set-Content -Path $pgcliConfig -Value @"
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
"@
        Write-Success "pgcli configured (multi-line, auto-expand, destructive warnings)"
    }
}

# ---- mycli config ----
$myclirc = Join-Path $HOME ".myclirc"
if (Test-Path $myclirc) {
    Write-Warn "~/.myclirc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating mycli configuration..."
        Set-Content -Path $myclirc -Value @"
[main]
multi_line = True
auto_expand = True
pager = bat --style=plain --paging=always
prompt = '\u@\h:\d> '
syntax_style = monokai
keyword_casing = upper
smart_completion = True
destructive_warning = True
log_file = ~/.mycli.log
history_file = ~/.mycli-history
wider_completion_menu = True
"@
        Write-Success "~/.myclirc configured (multi-line, auto-expand, destructive warnings)"
    }
}

# ---- yazi config ----
$yaziConfigDir = Join-Path $HOME ".config\yazi"
$yaziConfig = Join-Path $yaziConfigDir "yazi.toml"
if (Test-Path $yaziConfig) {
    Write-Warn "yazi config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating yazi configuration..."
        if (-not (Test-Path $yaziConfigDir)) { New-Item -ItemType Directory -Path $yaziConfigDir -Force | Out-Null }
        Set-Content -Path $yaziConfig -Value @"
# yazi configuration
[manager]
show_hidden = true
sort_dir_first = true
linemode = "size"

[preview]
max_width = 1000
max_height = 1000

[opener]
edit = [
    { run = 'code "%@"', desc = "Open in VS Code", block = true, for = "windows" },
]
"@
        Set-Content -Path (Join-Path $yaziConfigDir "theme.toml") -Value @"
# Dracula color palette for yazi
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
    { name = "*.toml", fg = "#f1fa8c" },
    { name = "*.yaml", fg = "#f1fa8c" },
    { name = "*.yml", fg = "#f1fa8c" },
    { name = "*.ts", fg = "#8be9fd" },
    { name = "*.tsx", fg = "#8be9fd" },
    { name = "*.js", fg = "#f1fa8c" },
    { name = "*.jsx", fg = "#f1fa8c" },
    { name = "*.py", fg = "#50fa7b" },
    { name = "*.rs", fg = "#ffb86c" },
    { name = "*.go", fg = "#8be9fd" },
]
"@
        Write-Success "yazi configured (hidden files, VS Code opener, Dracula theme)"
    }
}

# ---- just global justfile ----
$justfileGlobal = Join-Path $HOME ".justfile"
if (Test-Path $justfileGlobal) {
    Write-Warn "Global justfile already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating global justfile with common recipes..."
        Set-Content -Path $justfileGlobal -Value @"
# =============================================================================
# Global Justfile -- available from any directory via: just --justfile ~/.justfile
# =============================================================================
# Tip: Set-Alias gj { just --justfile ~/.justfile --working-directory . }

# List all recipes
default:
    @just --justfile {{justfile()}} --list

# -- System -------------------------------------------------------------------

# Update everything (topgrade)
update:
    topgrade

# Show system info
info:
    fastfetch

# Show listening ports
ports:
    netstat -ano | findstr LISTENING

# -- Git ----------------------------------------------------------------------

# Interactive rebase last N commits
rebase n="5":
    git rebase -i HEAD~{{n}}

# Undo last commit (keep changes staged)
undo:
    git reset --soft HEAD~1

# Show recent branches sorted by last commit
branches:
    git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:relative)\t%(refname:short)'

# -- Docker -------------------------------------------------------------------

# Clean Docker: unused images, containers, volumes
docker-clean:
    docker system prune -af --volumes

# Show Docker disk usage
docker-usage:
    docker system df

# -- Dev ----------------------------------------------------------------------

# Serve current directory on port 8080
serve port="8080":
    miniserve --color-scheme-dark dracula -qr . -p {{port}}

# Generate a UUID
uuid:
    @powershell -Command "[guid]::NewGuid().ToString()"

# Encode/decode base64
b64-encode text:
    @powershell -Command "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{{text}}'))"

b64-decode text:
    @powershell -Command "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{{text}}'))"

# -- Network ------------------------------------------------------------------

# Show public IP address
ip:
    @powershell -Command "(Invoke-WebRequest -Uri https://ifconfig.me -UseBasicParsing).Content"

# Show local IP address
local-ip:
    @powershell -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object {`$_.InterfaceAlias -ne 'Loopback Pseudo-Interface 1'} | Select-Object -First 1).IPAddress"

# Kill process on a specific port
kill-port port:
    @powershell -Command "`$p = (netstat -ano | Select-String ':{{port}}.*LISTENING' | ForEach-Object { (`$_ -split '\s+')[-1] } | Select-Object -First 1); if (`$p) { Stop-Process -Id `$p -Force; Write-Host 'Killed process on port {{port}}' } else { Write-Host 'No process on port {{port}}' }"

# Quick HTTP status check
status url:
    @powershell -Command "`$r = Invoke-WebRequest -Uri '{{url}}' -Method Head -UseBasicParsing; Write-Host ('HTTP ' + `$r.StatusCode)"

# -- Cleanup ------------------------------------------------------------------

# Remove all node_modules directories under ~/Code
node-clean:
    @echo "Finding node_modules under ~/Code..."
    @powershell -Command "Get-ChildItem -Path ~/Code -Recurse -Directory -Filter node_modules -Depth 4 | ForEach-Object { Write-Host (`$_.FullName + ' -> ' + ('{0:N2} MB' -f ((Get-ChildItem `$_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB))) }"
    @echo ""
    @echo "Run: Get-ChildItem -Path ~/Code -Recurse -Directory -Filter node_modules -Depth 4 | Remove-Item -Recurse -Force"

# Nuclear Docker cleanup (everything)
docker-nuke:
    docker system prune -af --volumes
    @echo "Docker wiped clean."

# -- Quick Info ---------------------------------------------------------------

# Show a cheatsheet for a command (via tldr)
cheat cmd:
    @tldr {{cmd}}

# Generate a timestamp
timestamp:
    @powershell -Command "Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'"

# Show weather (via wttr.in)
weather city="":
    @powershell -Command "(Invoke-WebRequest -Uri 'https://wttr.in/{{city}}?format=3' -UseBasicParsing).Content"

# Git standup -- what did I do yesterday?
standup:
    @git log --oneline --since='yesterday' --author="$(git config user.name)" 2>nul || echo "Not in a git repo"

# Count lines of code in current directory
loc:
    @tokei . 2>nul || powershell -Command "(Get-ChildItem -Recurse -Include *.ts,*.tsx,*.js,*.py,*.go,*.rs | Get-Content | Measure-Object -Line).Lines.ToString() + ' lines'"
"@
        Write-Success "Global justfile created (~/.justfile -- system, git, docker, network, cleanup, info recipes)"
    }
}

# ---- Zed editor config ----
$zedConfigDir = Join-Path $HOME ".config\zed"
$zedConfig = Join-Path $zedConfigDir "settings.json"
if (Test-Path $zedConfig) {
    Write-Warn "Zed config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Zed configuration..."
        if (-not (Test-Path $zedConfigDir)) { New-Item -ItemType Directory -Path $zedConfigDir -Force | Out-Null }
        Set-Content -Path $zedConfig -Value @"
{
    "theme": "Dracula",
    "ui_font_family": "Inter",
    "ui_font_size": 15,
    "buffer_font_family": "JetBrains Mono",
    "buffer_font_size": 14,
    "buffer_line_height": { "custom": 1.6 },
    "buffer_font_features": { "calt": true, "liga": true },
    "tab_size": 2,
    "format_on_save": "on",
    "autosave": "on_focus_change",
    "relative_line_numbers": true,
    "scrollbar": { "show": "auto" },
    "indent_guides": { "enabled": true, "coloring": "indent_aware" },
    "inlay_hints": { "enabled": true },
    "git": { "inline_blame": { "enabled": true } },
    "terminal": {
        "font_family": "JetBrains Mono NF",
        "font_size": 13,
        "blinking": "on"
    },
    "telemetry": { "diagnostics": false, "metrics": false }
}
"@
        Write-Success "Zed configured (Dracula theme, JetBrains Mono, format on save)"
    }
}

# ---- direnv config ----
$direnvConfigDir = Join-Path $HOME ".config\direnv"
$direnvConfig = Join-Path $direnvConfigDir "direnv.toml"
if (Test-Path $direnvConfig) {
    Write-Warn "direnv config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating direnv configuration..."
        if (-not (Test-Path $direnvConfigDir)) { New-Item -ItemType Directory -Path $direnvConfigDir -Force | Out-Null }
        Set-Content -Path $direnvConfig -Value @"
# direnv configuration
[global]
hide_env_diff = true
warn_timeout = "10s"
load_dotenv = true

[whitelist]
prefix = [
    "~/Code"
]
"@
        Write-Success "direnv configured (hidden env diff, auto-trust ~/Code)"
    }
}

# ---- mise global config ----
$miseConfig = Join-Path $HOME ".config\mise\config.toml"
if (Test-Path $miseConfig) {
    Write-Warn "mise global config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating mise global configuration..."
        $miseDir = Split-Path $miseConfig
        if (-not (Test-Path $miseDir)) { New-Item -ItemType Directory -Path $miseDir -Force | Out-Null }
        Set-Content -Path $miseConfig -Value @"
# mise global tool versions
# Docs: https://mise.jdx.dev/
# These are defaults -- per-project .mise.toml takes precedence

[tools]
node = "lts"
python = "3.12"
# go = "latest"      # installed via scoop
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
"@
        Write-Success "mise configured (auto-install, trust ~/Code)"
    }
}

# ---- topgrade config ----
$topgradeConfig = Join-Path $HOME ".config\topgrade.toml"
if (Test-Path $topgradeConfig) {
    Write-Warn "topgrade config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating topgrade configuration..."
        Set-Content -Path $topgradeConfig -Value @"
# topgrade configuration -- update everything with one command
cleanup = true

[windows]
accept_all_updates = true
open_remotes_in_new_terminal = true
"@
        Write-Success "topgrade configured (cleanup, auto-accept updates)"
    }
}

# ---- fastfetch config ----
$fastfetchConfig = Join-Path $HOME ".config\fastfetch\config.jsonc"
if (Test-Path $fastfetchConfig) {
    Write-Warn "fastfetch config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating fastfetch configuration..."
        $ffDir = Split-Path $fastfetchConfig
        if (-not (Test-Path $ffDir)) { New-Item -ItemType Directory -Path $ffDir -Force | Out-Null }
        Set-Content -Path $fastfetchConfig -Value @"
{
    "`$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
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
            "text": "node --version 2>nul | ForEach-Object { `$_ -replace 'v','' }"
        },
        {
            "type": "command",
            "key": "  Python",
            "text": "python3 --version 2>nul | ForEach-Object { (`$_ -split ' ')[1] }"
        },
        {
            "type": "command",
            "key": "  Go",
            "text": "go version 2>nul | ForEach-Object { (`$_ -split ' ')[2] -replace 'go','' }"
        },
        {
            "type": "command",
            "key": " 🦀 Rust",
            "text": "rustc --version 2>nul | ForEach-Object { (`$_ -split ' ')[1] }"
        },
        {
            "type": "command",
            "key": " 󰜫 Docker",
            "text": "docker --version 2>nul | ForEach-Object { ((`$_ -split ' ')[2]) -replace ',','' }"
        },
        { "type": "separator", "string": "─" },
        { "type": "colors", "symbol": "circle" }
    ]
}
"@
        Write-Success "fastfetch configured (themed layout, Nerd Font icons, dev tool versions)"
    }
}

# ---- bat extended config ----
if ((Test-Command "bat") -and -not $DRY_RUN) {
    $batConfigDir2 = & bat --config-dir 2>$null
    if ($batConfigDir2) {
        $batConfig2 = Join-Path $batConfigDir2 "config"
        if ((Test-Path $batConfig2) -and -not (Select-String -Path $batConfig2 -Pattern "map-syntax" -Quiet -ErrorAction SilentlyContinue)) {
            Write-Info "Adding bat file type mappings..."
            Add-Content -Path $batConfig2 -Value @"

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
--map-syntax "Caddyfile:Plain Text"
--map-syntax "*.mdx:Markdown"
--map-syntax ".prettierrc:JSON"
--map-syntax ".eslintrc:JSON"
--map-syntax ".babelrc:JSON"
--map-syntax "tsconfig*.json:JSON"

# Style
--style="numbers,changes,header,grid"
--italic-text=always
"@
            Write-Success "bat file type mappings added"
        }
    }
}

# ---- Espanso config ----
$espansoConfigDir = Join-Path $env:APPDATA "espanso\match"
$espansoConfig = Join-Path $espansoConfigDir "base.yml"
if (Test-Path $espansoConfig) {
    Write-Warn "Espanso config already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Espanso configuration..."
        if (-not (Test-Path $espansoConfigDir)) { New-Item -ItemType Directory -Path $espansoConfigDir -Force | Out-Null }
        Set-Content -Path $espansoConfig -Value @"
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
    replace: "¯\_(ツ)_/¯"

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
    replace: "console.log('`$|`$');"

  - trigger: ";todo"
    replace: "// TODO: "

  - trigger: ";fixme"
    replace: "// FIXME: "

  # -- Markdown ----------------------------------------------------------
  - trigger: ";cb"
    replace: "``````\n`$|`$\n``````"

  - trigger: ";cbt"
    replace: "``````typescript\n`$|`$\n``````"

  - trigger: ";cbp"
    replace: "``````python\n`$|`$\n``````"

  - trigger: ";cbb"
    replace: "``````bash\n`$|`$\n``````"

  - trigger: ";table"
    replace: "| Column 1 | Column 2 | Column 3 |\n|----------|----------|----------|\n| | | |"

  # -- Git ---------------------------------------------------------------
  - trigger: ";gcm"
    replace: 'git commit -m "'

  - trigger: ";gca"
    replace: 'git add -A && git commit -m "'

  - trigger: ";gpush"
    replace: "git push origin `$(git branch --show-current)"

  # -- UUID & Random ----------------------------------------------------------
  - trigger: ";uuid"
    replace: "{{uuid}}"
    vars:
      - name: uuid
        type: shell
        params:
          cmd: "powershell -Command \"[guid]::NewGuid().ToString()\""

  - trigger: ";lorem"
    replace: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."

  - trigger: ";loremshort"
    replace: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."

  # -- Common Regex Patterns --------------------------------------------------
  - trigger: ";rxemail"
    replace: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}`$"

  - trigger: ";rxurl"
    replace: "https?://[\\w\\-]+(\\.[\\w\\-]+)+[\\w\\-.,@?^=%&:/~+#]*"

  - trigger: ";rxip"
    replace: "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b"

  - trigger: ";rxphone"
    replace: "^\\+?[1-9]\\d{1,14}`$"

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
      ## Meeting Notes -- {{today}}
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
"@
        Write-Success "Espanso configured (dates, dev shortcuts, Markdown, git, templates, regex, symbols)"
    }
}

# ---- .vimrc ----
$vimrc = Join-Path $HOME ".vimrc"
if (Test-Path $vimrc) {
    Write-Warn "~/.vimrc already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating basic ~/.vimrc..."
        Set-Content -Path $vimrc -Value @"
" =============================================================================
" ~/.vimrc -- minimal but comfortable vim config
" =============================================================================

set nocompatible
syntax on
filetype plugin indent on
set number
set relativenumber
set ruler
set showcmd
set showmode
set cursorline
set scrolloff=8
set sidescrolloff=8
set signcolumn=yes
set colorcolumn=100
set laststatus=2
set wildmenu
set wildmode=longest:full,full
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set autoindent
set smartindent
set incsearch
set hlsearch
set ignorecase
set smartcase
set backspace=indent,eol,start
set clipboard=unnamed
set mouse=a
set hidden
set autoread
set encoding=utf-8
set noerrorbells
set novisualbell
set nobackup
set nowritebackup
set noswapfile
set undofile
set undodir=~/.vim/undodir

let mapleader = " "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>h :nohlsearch<CR>
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" Dracula-ish Colors
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

if !isdirectory(`$HOME . "/.vim/undodir")
    call mkdir(`$HOME . "/.vim/undodir", "p")
endif
"@
        $vimUndoDir = Join-Path $HOME ".vim\undodir"
        if (-not (Test-Path $vimUndoDir)) { New-Item -ItemType Directory -Path $vimUndoDir -Force | Out-Null }
        Write-Success "~/.vimrc created (line numbers, clipboard, mouse, Dracula colors)"
    }
}

} # configs

# =============================================================================
if (Test-ShouldRun "filesystem") {
Write-Banner "Filesystem Structure & Helper Scripts"

Write-Info "Setting up filesystem structure..."

$dirs = @(
    # -- Development ----------------------------------------------------------
    (Join-Path $HOME "Code\work")
    (Join-Path $HOME "Code\work\scratch")
    (Join-Path $HOME "Code\personal")
    (Join-Path $HOME "Code\personal\scratch")
    (Join-Path $HOME "Code\oss")
    (Join-Path $HOME "Code\learning\courses")
    (Join-Path $HOME "Code\learning\playground")

    # -- Scripts & Automation -------------------------------------------------
    (Join-Path $HOME "Scripts\bin")
    (Join-Path $HOME "Scripts\cron")

    # -- Screenshots ----------------------------------------------------------
    (Join-Path $HOME "Screenshots")

    # -- Documents (organized by life area) -----------------------------------
    (Join-Path $HOME "Documents\finance\taxes")
    (Join-Path $HOME "Documents\finance\invoices")
    (Join-Path $HOME "Documents\finance\statements")
    (Join-Path $HOME "Documents\health")
    (Join-Path $HOME "Documents\legal")
    (Join-Path $HOME "Documents\travel")
    (Join-Path $HOME "Documents\insurance")
    (Join-Path $HOME "Documents\contracts")
    (Join-Path $HOME "Documents\receipts")
    (Join-Path $HOME "Documents\design")

    # -- Reference (quick-access knowledge) -----------------------------------
    (Join-Path $HOME "Reference\manuals")
    (Join-Path $HOME "Reference\cheatsheets")
    (Join-Path $HOME "Reference\bookmarks-export")

    # -- Creative -------------------------------------------------------------
    (Join-Path $HOME "Creative\design")
    (Join-Path $HOME "Creative\writing")
    (Join-Path $HOME "Creative\video-editing")
    (Join-Path $HOME "Creative\assets\icons")
    (Join-Path $HOME "Creative\assets\fonts")
    (Join-Path $HOME "Creative\assets\stock-photos")
    (Join-Path $HOME "Creative\assets\templates")

    # -- Media ----------------------------------------------------------------
    (Join-Path $HOME "Media\photos")
    (Join-Path $HOME "Media\videos")
    (Join-Path $HOME "Media\music")
    (Join-Path $HOME "Media\wallpapers")

    # -- Projects (non-code personal projects) --------------------------------
    (Join-Path $HOME "Projects\side-hustles")
    (Join-Path $HOME "Projects\home")

    # -- Archive (cold storage for old stuff) ---------------------------------
    (Join-Path $HOME "Archive\old-projects")
    (Join-Path $HOME "Archive\old-docs")
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
Write-Success "Directory structure created (~/Code, ~/Scripts, ~/Documents, ~/Reference, ~/Creative, ~/Media, ~/Projects, ~/Archive)"

if (-not $DRY_RUN) {
    Write-Info "Creating helper scripts in ~/Scripts/bin..."

    # -- clean-downloads.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\clean-downloads.ps1") -Value @'
# Delete files in ~/Downloads older than 30 days
param([int]$Days = 30)
$dir = Join-Path $HOME "Downloads"
$cutoff = (Get-Date).AddDays(-$Days)
$files = Get-ChildItem $dir -File | Where-Object { $_.LastWriteTime -lt $cutoff }

if ($files.Count -eq 0) {
    Write-Host "No files older than $Days days found."
    return
}

Write-Host "Found $($files.Count) files to delete:"
$files | ForEach-Object { Write-Host "  $($_.Name)" }
$confirm = Read-Host "Delete these files? [y/N]"
if ($confirm -eq "y" -or $confirm -eq "Y") {
    $files | ForEach-Object {
        $shell = New-Object -ComObject Shell.Application
        $shell.Namespace(10).MoveHere($_.FullName)
    }
    Write-Host "Moved $($files.Count) files to Recycle Bin."
} else {
    Write-Host "Cancelled."
}
'@

    # -- new-project.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\new-project.ps1") -Value @'
# Scaffold a new project with git, .editorconfig, .gitignore
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Context = "personal"
)
$baseMap = @{
    "work"     = Join-Path $HOME "Code\work"
    "personal" = Join-Path $HOME "Code\personal"
    "oss"      = Join-Path $HOME "Code\oss"
    "learning" = Join-Path $HOME "Code\learning\playground"
}
if (-not $baseMap.ContainsKey($Context)) {
    Write-Host "Unknown context: $Context (use work, personal, oss, or learning)"
    return
}
$projectDir = Join-Path $baseMap[$Context] $Name
if (Test-Path $projectDir) { Write-Host "Project already exists: $projectDir"; return }
Write-Host "Creating project: $projectDir"
New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
Set-Location $projectDir
git init -b main
$editorconfig = Join-Path $HOME ".editorconfig"
if (Test-Path $editorconfig) { Copy-Item $editorconfig .editorconfig }
@"
node_modules/
dist/
build/
.next/
.env
.env.local
.env.*.local
.vscode/settings.json
.idea/
Thumbs.db
coverage/
*.log
"@ | Set-Content .gitignore
@"
# $Name

## Getting Started
``````
pnpm install
pnpm dev
``````
"@ | Set-Content README.md

# Create project-level CLAUDE.md for AI context
New-Item -ItemType Directory -Path ".claude" -Force | Out-Null
@"
# $Name

## Overview
<!-- Describe what this project does -->

## Tech Stack
<!-- Languages, frameworks, key libraries -->

## Development
- Install: ``pnpm install``
- Dev: ``pnpm dev``
- Test: ``pnpm test``
- Build: ``pnpm build``

## Conventions
<!-- Project-specific conventions not in the global CLAUDE.md -->
"@ | Set-Content "CLAUDE.md"

# Create GitHub PR template
New-Item -ItemType Directory -Path ".github" -Force | Out-Null
@"
## Summary
<!-- What does this PR do and why? -->

## Changes
-

## Test Plan
- [ ]

Closes #
"@ | Set-Content ".github\PULL_REQUEST_TEMPLATE.md"

git add -A
git commit -m "Initial project scaffold"
Write-Host "Project created at: $projectDir"
'@

    # -- clone-work.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\clone-work.ps1") -Value @'
# Clone a work repo into ~/Code/work/<org>/<repo>
param([Parameter(Mandatory)][string]$RepoUrl)
if ($RepoUrl -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    $org = $Matches[1]; $repo = $Matches[2]
} elseif ($RepoUrl -match '^([^/]+)/([^/]+)$') {
    $org = $Matches[1]; $repo = $Matches[2]
} else {
    Write-Host "Could not parse org/repo from: $RepoUrl"; return
}
$target = Join-Path $HOME "Code\work\$org"
New-Item -ItemType Directory -Path $target -Force | Out-Null
$repoDir = Join-Path $target $repo
if (Test-Path $repoDir) { Write-Host "Already exists: $repoDir"; return }
Write-Host "Cloning $org/$repo into $repoDir..."
gh repo clone "$org/$repo" $repoDir
git -C $repoDir maintenance start
Write-Host "Cloned to: $repoDir"
'@

    # -- clone-personal.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\clone-personal.ps1") -Value @'
# Clone a personal repo into ~/Code/personal/<repo>
param([Parameter(Mandatory)][string]$Input)
if ($Input -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    $repo = $Matches[2]; $cloneUrl = $Input
} elseif ($Input -match '/') {
    $repo = $Input.Split('/')[-1]; $cloneUrl = $Input
} else {
    $repo = $Input; $cloneUrl = ""
}
$target = Join-Path $HOME "Code\personal\$repo"
if (Test-Path $target) { Write-Host "Already exists: $target"; return }
Write-Host "Cloning $repo into $target..."
if ($cloneUrl) { gh repo clone $cloneUrl $target }
else { gh repo clone $repo $target }
git -C $target maintenance start
Write-Host "Cloned to: $target"
'@

    # -- backup-dotfiles.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\backup-dotfiles.ps1") -Value @'
# Backup dotfiles using chezmoi
if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    Write-Host "chezmoi not installed. Run: scoop install chezmoi"; return
}
# Export scoop package list for reproducibility
$scoopExportDir = Join-Path $HOME ".config\scoop-export"
if (-not (Test-Path $scoopExportDir)) { New-Item -ItemType Directory -Path $scoopExportDir -Force | Out-Null }
$scoopExportFile = Join-Path $scoopExportDir "scoop-export-latest.json"
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "Exporting scoop package list..."
    scoop export | Set-Content -Path $scoopExportFile
}
# Export scheduled tasks list (crontab equivalent)
$taskExportFile = Join-Path $scoopExportDir "scheduled-tasks.txt"
Get-ScheduledTask | Where-Object { $_.TaskPath -eq "\" } | Format-Table TaskName, State -AutoSize | Out-File $taskExportFile
chezmoi re-add 2>$null
$sourceDir = chezmoi source-path
Set-Location $sourceDir
$status = git status --porcelain
if (-not $status) { Write-Host "No dotfile changes to backup."; return }
Write-Host "Changes detected:"
git status --short
$confirm = Read-Host "Commit and push? [y/N]"
if ($confirm -eq "y" -or $confirm -eq "Y") {
    git add -A
    git commit -m "Update dotfiles -- $(Get-Date -Format 'yyyy-MM-dd')"
    git push
    Write-Host "Dotfiles backed up."
} else {
    Write-Host "Cancelled."
}
'@

    # -- project-stats.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\project-stats.ps1") -Value @'
# Show overview of all projects in ~/Code
$codeDir = Join-Path $HOME "Code"
Write-Host "=== Project Stats ==="
foreach ($context in @("work", "personal", "oss", "learning")) {
    $dir = Join-Path $codeDir $context
    if (Test-Path $dir) {
        $count = (Get-ChildItem $dir -Recurse -Directory -Filter ".git" -Depth 2 -ErrorAction SilentlyContinue).Count
        Write-Host "  ${context}: $count repos"
    }
}
Write-Host "`n=== Disk Usage ==="
Get-ChildItem $codeDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
    Write-Host ("  {0}: {1:N2} GB" -f $_.Name, $size)
}
'@

    # -- health-check.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\health-check.ps1") -Value @'
# Quick system health overview
# Usage: health-check.ps1
Write-Host "=== System Health Check ==="

Write-Host "`n--- Disk Space ---"
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | ForEach-Object {
    $usedGB = [math]::Round($_.Used / 1GB, 1)
    $freeGB = [math]::Round($_.Free / 1GB, 1)
    $totalGB = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
    $pct = [math]::Round($_.Used * 100 / ($_.Used + $_.Free))
    Write-Host ("  {0}: {1}GB / {2}GB ({3}% used, {4}GB free)" -f $_.Root, $usedGB, $totalGB, $pct, $freeGB)
}

Write-Host "`n--- Docker Disk Usage ---"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker system df 2>$null
} else {
    Write-Host "  Docker not installed"
}

Write-Host "`n--- Largest node_modules ---"
$codeDir = Join-Path $HOME "Code"
if (Test-Path $codeDir) {
    Get-ChildItem $codeDir -Recurse -Directory -Filter "node_modules" -Depth 4 -ErrorAction SilentlyContinue |
        ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{ Path = $_.FullName; SizeMB = [math]::Round($size / 1MB) }
        } | Sort-Object SizeMB -Descending | Select-Object -First 10 |
        ForEach-Object { Write-Host ("  {0}MB  {1}" -f $_.SizeMB, $_.Path) }
} else {
    Write-Host "  ~/Code not found"
}

Write-Host "`n--- Outdated Scoop Packages ---"
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    scoop status 2>$null
}

Write-Host "`n--- Outdated Winget Packages ---"
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget upgrade 2>$null | Select-Object -First 20
}

Write-Host "`n--- Uptime ---"
$os = Get-CimInstance Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
Write-Host ("  {0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
'@

    # -- setup-ssh.ps1 --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\setup-ssh.ps1") -Value @'
# Generate SSH key and optionally add to GitHub
# Usage: setup-ssh.ps1 <email>
param([Parameter(Mandatory)][string]$Email)

$keyPath = Join-Path $HOME ".ssh\id_ed25519"

if (Test-Path $keyPath) {
    Write-Host "SSH key already exists at $keyPath"
    Write-Host "Public key:"
    Get-Content "$keyPath.pub"
} else {
    Write-Host "Generating Ed25519 SSH key for $Email..."
    $sshDir = Join-Path $HOME ".ssh"
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
    ssh-keygen -t ed25519 -C $Email -f $keyPath -N ""
    Write-Host "SSH key generated."
}

# Start ssh-agent
Get-Service ssh-agent -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service ssh-agent -ErrorAction SilentlyContinue
ssh-add $keyPath 2>$null

# Optionally add to GitHub
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $confirm = Read-Host "Add this key to GitHub? [y/N]"
    if ($confirm -eq "y" -or $confirm -eq "Y") {
        gh ssh-key add "$keyPath.pub" --title "$(hostname) $(Get-Date -Format 'yyyy-MM-dd')"
        Write-Host "SSH key added to GitHub."
    }
} else {
    Write-Host "Install GitHub CLI (gh) to automatically add key to GitHub."
    Write-Host "Or add manually: https://github.com/settings/keys"
}
'@

    # -- export-brewfile.ps1 (scoop export equivalent) --
    Set-Content -Path (Join-Path $HOME "Scripts\bin\export-brewfile.ps1") -Value @'
# Export scoop package list for reproducibility
# Usage: export-brewfile.ps1
$exportDir = Join-Path $HOME ".config\scoop-export"
if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$exportFile = Join-Path $exportDir "scoop-export-$timestamp.json"
$latestFile = Join-Path $exportDir "scoop-export-latest.json"

Write-Host "Exporting scoop package list..."
scoop export | Set-Content -Path $exportFile
Copy-Item $exportFile $latestFile -Force

Write-Host "Exported to: $exportFile"
Write-Host "Latest link: $latestFile"
Write-Host ""
Write-Host "To restore on another machine:"
Write-Host "  scoop import $latestFile"
'@

    Write-Success "Helper scripts created (clean-downloads, new-project, clone-work, clone-personal, backup-dotfiles, project-stats, health-check, setup-ssh, export-brewfile)"

    # ---- Per-directory Git Config ----
    Write-Info "Setting up per-directory git config..."

    $gitconfigWork = Join-Path $HOME ".gitconfig-work"
    $gitconfigPersonal = Join-Path $HOME ".gitconfig-personal"

    if (-not (Test-Path $gitconfigWork)) {
        Set-Content -Path $gitconfigWork -Value @"
# Git config for work projects (~/Code/work/)
[user]
    # name = Your Name
    # email = you@company.com
    # signingkey = YOUR_GPG_KEY_ID
# [commit]
#     gpgsign = true
"@
        Write-Success "~/.gitconfig-work created (fill in your work email)"
    }

    if (-not (Test-Path $gitconfigPersonal)) {
        Set-Content -Path $gitconfigPersonal -Value @"
# Git config for personal projects (~/Code/personal/)
[user]
    # name = Your Name
    # email = you@personal.com
    # signingkey = YOUR_GPG_KEY_ID
# [commit]
#     gpgsign = true
"@
        Write-Success "~/.gitconfig-personal created (fill in your personal email)"
    }

    # Register includeIf directives
    $existingWorkInc = git config --global --get "includeIf.gitdir:~/Code/work/.path" 2>$null
    if (-not $existingWorkInc) {
        git config --global "includeIf.gitdir:~/Code/work/.path" $gitconfigWork
        Write-Success "git includeIf registered for ~/Code/work/"
    }
    $existingPersInc = git config --global --get "includeIf.gitdir:~/Code/personal/.path" 2>$null
    if (-not $existingPersInc) {
        git config --global "includeIf.gitdir:~/Code/personal/.path" $gitconfigPersonal
        Write-Success "git includeIf registered for ~/Code/personal/"
    }
}

} # filesystem

# =============================================================================
if (Test-ShouldRun "windows-defaults") {
Write-Banner "Windows Defaults (Registry Edits)"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Info "Some registry edits require Administrator privileges. Running what we can as current user..."
}

if (-not $DRY_RUN) {
    # Fast keyboard repeat
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name KeyboardSpeed -Value 31
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name KeyboardDelay -Value 0
        Write-Success "Keyboard configured (fast repeat rate)"
    } catch { Write-Err "Failed to set keyboard settings: $_" }

    # Show hidden files
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name Hidden -Value 1
        Write-Success "Explorer: Show hidden files enabled"
    } catch { Write-Err "Failed to set hidden files: $_" }

    # Show file extensions
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideFileExt -Value 0
        Write-Success "Explorer: Show file extensions enabled"
    } catch { Write-Err "Failed to set file extensions: $_" }

    # Disable web search in Start
    try {
        $explorerPoliciesPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $explorerPoliciesPath)) { New-Item -Path $explorerPoliciesPath -Force | Out-Null }
        Set-ItemProperty -Path $explorerPoliciesPath -Name DisableSearchBoxSuggestions -Value 1
        Write-Success "Start Menu: Web search disabled"
    } catch { Write-Err "Failed to disable web search: $_" }

    # Disable Copilot (requires admin for HKLM)
    if ($isAdmin) {
        try {
            $copilotPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
            if (-not (Test-Path $copilotPath)) { New-Item -Path $copilotPath -Force | Out-Null }
            Set-ItemProperty -Path $copilotPath -Name TurnOffWindowsCopilot -Value 1
            Write-Success "Windows Copilot disabled"
        } catch { Write-Err "Failed to disable Copilot: $_" }
    } else {
        Write-Info "Skipping Copilot disable (requires Administrator)"
    }

    # Reduce animations
    try {
        # Read current value and only modify animation-related bits
        $currentMask = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name UserPreferencesMask -ErrorAction SilentlyContinue).UserPreferencesMask
        if ($currentMask) {
            # Disable animations (bit 1 of byte 0)
            $currentMask[0] = $currentMask[0] -band 0xFE  # Clear animation bit
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name UserPreferencesMask -Value $currentMask
        } else {
            # Fallback to the full set if no current value exists
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name UserPreferencesMask -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00))
        }
        Write-Success "Animations reduced"
    } catch { Write-Err "Failed to reduce animations: $_" }

    # Small taskbar
    try {
        Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name TaskbarSi -Value 0
        Write-Success "Taskbar size: small"
    } catch { Write-Err "Failed to set taskbar size: $_" }

    # DNS (1.1.1.1 + 9.9.9.9 + 8.8.8.8) - requires admin
    if ($isAdmin) {
        try {
            $dnsServers = @("1.1.1.1","1.0.0.1","9.9.9.9","8.8.8.8")
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
            foreach ($adapter in $adapters) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsServers
            }
            Write-Success "DNS set to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) + Google (8.8.8.8)"
        } catch { Write-Err "Failed to set DNS: $_" }
    } else {
        Write-Info "Skipping DNS configuration (requires Administrator)"
    }

    # Disable autocorrect/autocomplete
    try {
        $tabletTipPath = "HKCU:\SOFTWARE\Microsoft\TabletTip\1.7"
        if (Test-Path $tabletTipPath) {
            Set-ItemProperty -Path $tabletTipPath -Name EnableAutocorrection -Value 0
            Set-ItemProperty -Path $tabletTipPath -Name EnableSpellchecking -Value 0
        }
        Write-Success "Autocorrect/spell-check disabled"
    } catch { Write-Err "Failed to disable autocorrect: $_" }

    # Disable Bing in Start Menu (same as web search above, ensuring both paths)
    try {
        $searchPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
        Set-ItemProperty -Path $searchPath -Name DisableSearchBoxSuggestions -Value 1
        Write-Success "Bing search in Start Menu disabled"
    } catch { Write-Err "Failed to disable Bing search: $_" }

    # -- Clear Taskbar (remove all default pinned apps so user can set their own) --
    if (-not $DRY_RUN) {
        Write-Info "Clearing default pinned apps from taskbar (pin your own via right-click)..."
        try {
            # Remove all pinned apps from taskbar (Windows 11)
            # Delete the TaskbarLayout XML and the pinned items cache
            $taskbarPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
            Remove-ItemProperty -Path $taskbarPath -Name "Favorites" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $taskbarPath -Name "FavoritesResolve" -ErrorAction SilentlyContinue

            # Unpin default taskbar items by clearing the layout
            $layoutPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell\LayoutModification.xml"
            if (Test-Path $layoutPath) { Remove-Item $layoutPath -Force -ErrorAction SilentlyContinue }

            # Disable default taskbar items: Task View, Widgets, Chat
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -ErrorAction SilentlyContinue  # Widgets
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0 -ErrorAction SilentlyContinue  # Chat

            Write-Success "Taskbar cleared — right-click apps to pin them"
        } catch {
            Write-Err "Failed to clear taskbar: $_"
        }
    } else {
        Write-Info "[DRY RUN] Would clear default pinned apps from taskbar"
    }

    # -- File Explorer Quick Access Favorites --
    Write-Info "Configuring File Explorer Quick Access favorites..."
    if (-not $DRY_RUN) {
        try {
            $shell = New-Object -ComObject Shell.Application

            # Remove default Quick Access pins that clutter
            # (Windows doesn't have a clean API to remove, so we just add ours)

            # Pin our organized folders to Quick Access
            $quickAccessPins = @(
                (Join-Path $HOME "Code")
                (Join-Path $HOME "Screenshots")
                (Join-Path $HOME "Scripts")
                (Join-Path $HOME "Documents")
                (Join-Path $HOME "Reference")
                (Join-Path $HOME "Creative")
                (Join-Path $HOME "Media")
                (Join-Path $HOME "Projects")
                (Join-Path $HOME "Archive")
                (Join-Path $HOME "Downloads")
            )

            foreach ($pin in $quickAccessPins) {
                if (Test-Path $pin) {
                    try {
                        $shell.Namespace($pin).Self.InvokeVerb("pintohome")
                    } catch {
                        # Fallback for older Windows versions
                        $o = $shell.Namespace("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}")
                        $o.Items() | ForEach-Object { } # access Quick Access
                        $shell.Namespace($pin).Self.InvokeVerb("pintohome") 2>$null
                    }
                }
            }

            Write-Success "File Explorer Quick Access updated (Code, Screenshots, Scripts, Documents, Reference, Creative, Media, Projects, Archive, Downloads)"
        } catch {
            Write-Err "Failed to update Quick Access: $_"
        }
    } else {
        Write-Info "[DRY RUN] Would update File Explorer Quick Access favorites"
    }

    Write-Info "Restart Explorer or log out/in for all changes to take effect."

    # -- Wallpaper --
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $wallpaperSrc = Join-Path $scriptDir "assets\wolf-wallpaper.jpg"
    $wallpaperDest = Join-Path $HOME "Media\wallpapers\wolf-wallpaper.jpg"
    if (Test-Path $wallpaperSrc) {
        New-Item -ItemType Directory -Path (Join-Path $HOME "Media\wallpapers") -Force | Out-Null
        Copy-Item -Path $wallpaperSrc -Destination $wallpaperDest -Force
        if (-not $DRY_RUN) {
            try {
                # Set wallpaper via SystemParametersInfo
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
                [Wallpaper]::SystemParametersInfo(0x0014, 0, $wallpaperDest, 0x0003) | Out-Null
                Write-Success "Wallpaper set to wolf-wallpaper.jpg"
            } catch {
                Write-Err "Failed to set wallpaper: $_"
            }
        } else {
            Write-Info "[DRY RUN] Would set wallpaper to wolf-wallpaper.jpg"
        }
    } else {
        Write-Warn "Wallpaper not found at $wallpaperSrc - skipping"
    }
}

    # ---- Auto-set timezone ----
    # Timezone — uncomment and set your timezone if desired
    # try {
    #     Set-TimeZone -Id "Central Standard Time" -ErrorAction SilentlyContinue
    #     Write-Success "Timezone set to Central Standard Time"
    # } catch { Write-Err "Failed to set timezone: $_" }

    # ---- Software Update: auto-check but don't auto-restart ----
    if (-not $DRY_RUN) {
        if ($isAdmin) {
            try {
                $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                New-Item -Path $wuPath -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $wuPath -Name NoAutoRebootWithLoggedOnUsers -Value 1 -ErrorAction SilentlyContinue
                Write-Success "Windows Update: disabled auto-reboot with logged-on users"
            } catch { Write-Err "Failed to set Windows Update policy: $_" }
        } else {
            Write-Warn "Skipping Windows Update policy (requires Administrator)"
        }
    }

    # ---- Show Bluetooth in system tray (already visible by default on Windows) ----
    Write-Info "Bluetooth is visible in system tray by default on Windows"

    # ---- Login items (start at login) ----
    $startupFolder = [Environment]::GetFolderPath("Startup")
    # Clipboard history: use Windows built-in (Win+V) — no CopyQ needed

} # windows-defaults

# =============================================================================
if (Test-ShouldRun "configs") {
# CLAUDE CODE CONFIGURATION
# =============================================================================
Write-Banner "Claude Code Configuration"

$claudeDir = Join-Path $HOME ".claude"
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

# ---- Claude Code global settings ----
$claudeSettings = Join-Path $claudeDir "settings.json"
if (Test-Path $claudeSettings) {
    Write-Warn "Claude Code settings.json already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Claude Code global settings..."
        Set-Content -Path $claudeSettings -Value @"
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
      "Bash(dir *)",
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
      "Bash(where *)",
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
      "Bash(del /f /s /q C:\\*)",
      "Bash(format *)",
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
        "command": "powershell -File ~/.claude/hooks/format-on-edit.ps1"
      },
      {
        "matcher": "Edit|Write",
        "command": "powershell -File ~/.claude/hooks/lint-python.ps1"
      },
      {
        "matcher": "Edit|Write",
        "command": "powershell -File ~/.claude/hooks/lint-dockerfile.ps1"
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
"@
        Write-Success "Claude Code settings.json created"
    }
}

# ---- Claude Code global CLAUDE.md ----
$claudeMd = Join-Path $claudeDir "CLAUDE.md"
if (Test-Path $claudeMd) {
    Write-Warn "Claude Code global CLAUDE.md already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Claude Code global CLAUDE.md..."
        Set-Content -Path $claudeMd -Value @"
# Global Development Standards

## Workflow Philosophy
- **Trunk-based development** -- short-lived feature branches off main, merge back fast
- **PRs over direct commits** -- every change goes through a pull request, no direct pushes to main
- **Issues for everything** -- create GitHub issues before starting work, reference in PRs
- **README-driven development** -- every project and significant module gets a README
- **Industry best practices** -- follow established patterns, OWASP, 12-factor, SOLID, DRY

## Environment
- Shell: PowerShell with Starship prompt
- Editor: VS Code / Zed (Dracula theme, JetBrains Mono)
- Terminal: Windows Terminal / Alacritty (Dracula theme)
- Package managers: pnpm (preferred), npm, bun
- Python: uv for packages (not pip), ruff for linting (not flake8/black)
- Version manager: mise (Node, Python, Go, Ruby — all in one)
- Container runtime: Docker Desktop
- Task runner: just (prefer over make for project-level tasks)

## Available CLI Tools (use these instead of manual approaches)
- **Search**: ``rg`` (ripgrep) for content, ``fd`` for files, ``fzf`` for interactive
- **Data**: ``jq`` for JSON, ``yq`` for YAML, ``mlr`` for CSV, ``fx``/``jnv`` for interactive JSON
- **Git**: ``lazygit`` for interactive UI, ``delta`` for diffs, ``difft`` for syntax-aware diffs, ``git-cliff`` for changelogs
- **Docker**: ``lazydocker`` for UI, ``dive`` to inspect layers, ``hadolint`` for Dockerfile linting
- **Testing**: ``hyperfine`` to benchmark, ``oha`` for load testing, ``hurl`` for HTTP test files, ``act`` for local GitHub Actions
- **Code quality**: ``typos`` for spell checking, ``ast-grep`` for structural search/replace, ``shellcheck``/``shfmt`` for shell
- **Security**: ``trivy`` to scan containers/IaC, ``gitleaks`` for secrets, ``semgrep`` for static analysis
- **IaC**: ``tofu`` (Terraform), ``tflint`` for linting, ``infracost`` for cost estimation
- **HTTP**: ``xh`` for colorized requests, ``curlie`` for curl with httpie output
- **Network**: ``trippy`` for traceroute TUI, ``bandwhich`` for bandwidth
- **Docs**: ``d2`` for diagrams, ``pandoc`` for conversion, ``glow`` for Markdown preview
- **Database**: ``pgcli``/``mycli`` for auto-completing SQL, ``lazysql`` for TUI, ``sq`` for cross-database queries
- **File watching**: ``watchexec`` for running commands on file changes
- **Shell scripting**: ``gum`` for interactive prompts/spinners, ``nushell`` for structured data pipelines
- **Terminal**: ``zellij`` for multiplexing, ``mpv`` for video playback

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
- Functional components only -- no class components
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
- Run ``trivy config .`` to scan IaC before deploying
- Use ``infracost`` to estimate costs before applying changes

## Git Workflow (Trunk-Based)
- **Never commit directly to main** -- always use a feature branch + PR
- Branch naming: feature/, fix/, chore/, docs/ (e.g., feature/add-auth)
- Branches should be short-lived (< 2 days ideally)
- Squash merge to main (use ``gh pm`` alias) -- keeps history clean
- Delete branch after merge (automatic with ``gh pm``)
- Keep PRs small and focused (< 400 lines)
- Include tests with feature PRs
- Reference GitHub issues in PR descriptions (Closes #123)
- Use ``git standup`` to see yesterday's work
- Use ``git cleanup`` to prune merged branches
- Use ``git recent`` to see branches by last commit date

## PR Workflow
When asked to implement a feature or fix:
1. Create a GitHub issue first: ``gh issue create --title "..." --body "..."``
2. Create a branch: ``git switch -c feature/short-description``
3. Implement with small, atomic commits (conventional commit format)
4. Push and create PR: ``gh pr create --title "..." --body "Closes #<issue>"``
5. PR body should include: Summary, Changes (bullet list), Test plan
6. After approval, merge with: ``gh pm`` (squash + delete branch)

## Issue Tracking
- Create issues for bugs, features, chores, and tech debt
- Use labels: bug, feature, chore, docs, tech-debt, security
- Reference issues in commits and PRs (Closes #N, Fixes #N)
- Use ``gh il`` to list issues, ``gh ic`` to create via browser

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
- Handle errors explicitly -- no silent catches
- Use async/await over .then() chains
- Use zod for runtime validation at API boundaries

## Error Handling Patterns
- **TypeScript**: Use Result types or discriminated unions for expected errors, throw for unexpected
- **Python**: Use specific exception types, never bare ``except:``, always log context
- **API routes**: Return structured error responses ``{ error: { code, message, details } }``
- **Async**: Always handle promise rejections, use try/catch with async/await
- **Never**: Swallow errors silently, use ``console.log`` for error handling, expose stack traces to users

## API Design Standards
- RESTful naming: plural nouns for collections (``/users``, ``/posts``)
- HTTP methods: GET (read), POST (create), PUT (replace), PATCH (update), DELETE (remove)
- Response format: ``{ data: T }`` for success, ``{ error: { code, message } }`` for errors
- Always paginate list endpoints: ``?page=1&limit=20`` or cursor-based
- Use proper HTTP status codes: 200, 201, 204, 400, 401, 403, 404, 409, 422, 500
- Version APIs: ``/api/v1/...`` or via headers
- Validate all inputs at the boundary (zod for TS, pydantic for Python)

## Database Conventions
- Table names: plural, snake_case (``user_accounts``, ``order_items``)
- Column names: snake_case (``created_at``, ``is_active``, ``user_id``)
- Always include: ``id`` (primary key), ``created_at``, ``updated_at``
- Use migrations (dbmate) -- never modify schema manually
- Foreign keys: ``<table_singular>_id`` (e.g., ``user_id``)
- Index foreign keys and columns used in WHERE/ORDER BY

## Testing Standards
- Write tests alongside code (colocated: ``foo.ts`` + ``foo.test.ts``)
- Test behavior, not implementation (test what it does, not how)
- Follow Arrange-Act-Assert (AAA) pattern
- Unit tests: fast, isolated, no external dependencies
- Integration tests: test real interactions (DB, API, services)
- E2E tests: critical user flows only (login, checkout, etc.)
- Minimum coverage: aim for 80% on business logic, don't test trivial code
- Name tests clearly: "should return 404 when user not found"

## Pre-Push Checklist (follow before every PR)
1. All tests pass (``npm test`` / ``pytest`` / ``cargo test``)
2. Linting passes (``eslint .`` / ``ruff check .``)
3. Formatting applied (``prettier --write .`` / ``ruff format .``)
4. No secrets committed (``gitleaks detect``)
5. Dependencies audited (``npm audit`` / ``uv pip audit``)
6. README updated (if behavior changed)
7. Types check (``tsc --noEmit`` for TypeScript)
8. Build succeeds (``npm run build``)

## Security Checks (run before PRs)
- ``gitleaks detect`` -- check for leaked secrets
- ``trivy fs .`` -- scan for vulnerabilities
- ``npm audit`` / ``uv pip audit`` -- dependency audit
- ``semgrep --config auto .`` -- static analysis
"@
        Write-Success "Claude Code global CLAUDE.md created"
    }
}

# ---- Claude Code rules directory ----
$claudeRulesDir = Join-Path $claudeDir "rules"
if (Test-Path $claudeRulesDir) {
    Write-Warn "Claude Code rules directory already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Claude Code rules..."
        New-Item -ItemType Directory -Path $claudeRulesDir -Force | Out-Null

        Set-Content -Path (Join-Path $claudeRulesDir "workflow.md") -Value @"
# Workflow Rules (Trunk-Based Development)

## PR-First Approach
- NEVER commit directly to main -- always create a feature branch and PR
- When implementing a feature or fix, follow this order:
  1. Create a GitHub issue (``gh issue create``) to track the work
  2. Create a short-lived branch (``git switch -c feature/description``)
  3. Implement with small, atomic conventional commits
  4. Create a PR referencing the issue (``gh pr create``, body includes "Closes #N")
  5. Merge via squash (``gh pm``)

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
- One concern per PR -- don't mix features with refactoring

## READMEs
- Every new project MUST have a README.md
- Update README when adding significant features or changing setup steps
- README should cover: purpose, setup, usage, architecture, environment variables
"@

        Set-Content -Path (Join-Path $claudeRulesDir "git.md") -Value @"
# Git Rules

- Never force-push to main or master
- Never commit directly to main -- use feature branches + PRs
- Never commit .env files, secrets, or credentials
- Use conventional commit format: type(scope): description
  - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
- Keep commits atomic -- one logical change per commit
- Run tests before committing
- Reference GitHub issues in commits: "feat(auth): add login page (closes #42)"
- Branch names: feature/, fix/, chore/, docs/ (e.g., feature/add-oauth)
- Delete branches after merging (automatic with ``gh pm``)
"@

        Set-Content -Path (Join-Path $claudeRulesDir "security.md") -Value @"
# Security Rules

- Never hardcode API keys, tokens, passwords, or secrets
- Use environment variables or AWS Secrets Manager for sensitive values
- Never log sensitive information (passwords, tokens, PII)
- Always validate and sanitize user input
- Use parameterized queries -- never string-concatenate SQL
- Check npm audit before adding new dependencies
"@

        Set-Content -Path (Join-Path $claudeRulesDir "typescript.md") -Value @"
# TypeScript Rules

- Enable strict mode in tsconfig.json
- No ``any`` types -- use ``unknown`` if type is truly unknown
- Use discriminated unions for complex state
- Prefer interfaces for object shapes, types for unions/intersections
- Use ``as const`` for literal types
- Export types alongside their implementations
- Use zod schemas that infer TypeScript types (z.infer<typeof schema>)
"@
        Set-Content -Path (Join-Path $claudeRulesDir "python.md") -Value @"
# Python Rules

- Use uv for package management (not pip directly)
- Use ruff for linting and formatting (not flake8, black, isort)
- Type hints on all public functions and method signatures
- Use pydantic for data validation, dataclasses for simple data structures
- Virtual environments via ``uv venv`` -- never install globally
- Use ``async def`` for I/O-bound operations
- Prefer pathlib over os.path
"@

        Set-Content -Path (Join-Path $claudeRulesDir "docker.md") -Value @"
# Docker Rules

- Multi-stage builds for production images (builder + runtime)
- Run as non-root user (add USER directive)
- Use specific base image tags (not :latest)
- Lint Dockerfiles with ``hadolint`` before building
- Use .dockerignore to exclude node_modules, .git, etc.
- Scan images with ``trivy image <name>`` before pushing
- Use ``dive <image>`` to inspect and minimize layer sizes
"@

        Set-Content -Path (Join-Path $claudeRulesDir "iac.md") -Value @"
# Infrastructure as Code Rules

- Use OpenTofu/Terraform with state stored remotely (S3 + DynamoDB)
- Lint with ``tflint`` before applying
- Estimate costs with ``infracost`` before applying changes
- Use modules for reusable infrastructure patterns
- Tag all resources: project, environment, owner, managed-by
- Use workspaces or separate state files per environment
- Scan with ``trivy config .`` for misconfigurations
"@

        Write-Success "Claude Code rules created (workflow, git, security, typescript, python, docker, iac)"
    }
}

# ---- Claude Code hooks ----
$claudeHooksDir = Join-Path $claudeDir "hooks"
if (Test-Path $claudeHooksDir) {
    Write-Warn "Claude Code hooks directory already exists"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Claude Code hooks..."
        New-Item -ItemType Directory -Path $claudeHooksDir -Force | Out-Null

        Set-Content -Path (Join-Path $claudeHooksDir "format-on-edit.sh") -Value @'
#!/usr/bin/env bash
# Auto-format TypeScript/JavaScript files after Claude edits them
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
'@
        Set-Content -Path (Join-Path $claudeHooksDir "lint-python.sh") -Value @'
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
'@

        # format-on-edit.ps1 (PowerShell equivalent of format-on-edit.sh)
        $formatOnEditPs1 = Join-Path $claudeHooksDir "format-on-edit.ps1"
        if (-not (Test-Path $formatOnEditPs1)) {
            @'
$rawInput = [Console]::In.ReadToEnd()
$input_data = $rawInput | ConvertFrom-Json

$filePath = $input_data.file_path

if ($filePath -match '\.py$') {
    if (Get-Command ruff -ErrorAction SilentlyContinue) {
        ruff format $filePath 2>$null
    }
}
elseif ($filePath -match '\.(js|ts|jsx|tsx|json|css|md|yaml|yml)$') {
    if (Get-Command prettier -ErrorAction SilentlyContinue) {
        prettier --write $filePath 2>$null
    }
}
elseif ($filePath -match '\.go$') {
    if (Get-Command gofmt -ErrorAction SilentlyContinue) {
        gofmt -w $filePath 2>$null
    }
}
'@ | Out-File -FilePath $formatOnEditPs1 -Encoding utf8 -Force
        }

        Set-Content -Path (Join-Path $claudeHooksDir "lint-python.ps1") -Value @'
# Auto-lint and fix Python files after Claude edits them (PowerShell version)
$rawInput = [Console]::In.ReadToEnd()
$input_data = $rawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
$file = $input_data.tool_input.file_path

if ($file -and $file -match '\.py$' -and (Test-Path $file)) {
    if (Get-Command ruff -ErrorAction SilentlyContinue) {
        ruff check --fix $file 2>$null
        ruff format $file 2>$null
    }
}
exit 0
'@

        Set-Content -Path (Join-Path $claudeHooksDir "lint-dockerfile.sh") -Value @'
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
'@

        Set-Content -Path (Join-Path $claudeHooksDir "lint-dockerfile.ps1") -Value @'
# Lint Dockerfiles after Claude edits them (PowerShell version)
$rawInput = [Console]::In.ReadToEnd()
$input_data = $rawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
$file = $input_data.tool_input.file_path

if ($file -and (Split-Path $file -Leaf) -match '^Dockerfile' -and (Test-Path $file)) {
    if (Get-Command hadolint -ErrorAction SilentlyContinue) {
        $issues = hadolint $file 2>$null
        if ($issues) { Write-Error $issues }
    }
}
exit 0
'@

        Write-Success "Claude Code hooks created (auto-format JS/TS, auto-lint Python, lint Dockerfiles)"
    }
}

# ---- Claude Code custom slash commands ----
$claudeCommandsDir = Join-Path $claudeDir "commands"
if ((Test-Path $claudeCommandsDir) -and (Get-ChildItem $claudeCommandsDir -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Warn "Claude Code commands directory already has commands"
} else {
    if (-not $DRY_RUN) {
        Write-Info "Creating Claude Code custom slash commands..."
        if (-not (Test-Path $claudeCommandsDir)) { New-Item -ItemType Directory -Path $claudeCommandsDir -Force | Out-Null }

        Set-Content -Path (Join-Path $claudeCommandsDir "pr-review.md") -Value @"
Review the changes on the current branch compared to main. For each file changed:
1. Summarize what changed and why
2. Flag any security issues, bugs, or performance concerns
3. Check for missing error handling or edge cases
4. Note any style inconsistencies

Use ``git diff main...HEAD`` to see all changes. Be concise -- focus on issues, not praise.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "test-plan.md") -Value @"
Look at the recent changes in this repo (use git diff or git log) and generate a test plan:
1. List what should be tested (unit, integration, e2e)
2. Identify edge cases and error scenarios
3. Suggest specific test cases with expected inputs/outputs
4. Note any areas that are hard to test and why

Output as a Markdown checklist.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "dep-audit.md") -Value @"
Audit the project dependencies:
1. Check for known vulnerabilities (run npm audit or pip audit)
2. Identify outdated packages (run npm outdated or pip list --outdated)
3. Flag any packages with no recent maintenance (>2 years)
4. Check for duplicate/redundant dependencies
5. Estimate total bundle size impact of each dependency if this is a frontend project

Summarize findings with severity (critical/high/medium/low) and recommended actions.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "quick-doc.md") -Value @"
Generate documentation for the file or function I specify: `$ARGUMENTS

Include:
1. A brief description of what it does
2. Parameters/props with types and descriptions
3. Return value
4. Usage example
5. Any gotchas or important notes

Format as JSDoc/docstring appropriate for the language.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "cleanup.md") -Value @"
Scan the project for cleanup opportunities:
1. Unused imports and variables
2. Dead code (unreachable functions, unused exports)
3. Console.log / debug statements left in
4. TODO/FIXME comments that should be addressed
5. Empty catch blocks or swallowed errors

List each finding with file path and line number. Don't fix anything -- just report.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "security-scan.md") -Value @"
Run a comprehensive security scan of this project using the available tools:

1. **Secrets**: Run ``gitleaks detect --source .`` to check for leaked credentials
2. **Dependencies**: Run ``npm audit`` (Node) or ``uv pip audit`` (Python) for known vulnerabilities
3. **Static analysis**: Run ``semgrep --config auto .`` for security anti-patterns
4. **Container scan**: If there's a Dockerfile, run ``trivy fs .`` to scan for vulnerabilities
5. **IaC scan**: If there are Terraform/CDK files, run ``trivy config .`` for misconfigurations

For each finding, report: severity, file, line, description, and recommended fix.
Prioritize: critical > high > medium > low. Skip informational findings.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "perf-check.md") -Value @"
Analyze the performance of this project: `$ARGUMENTS

1. If a command/script is given, benchmark it with ``hyperfine``
2. If a URL is given, load test with ``oha -n 500 -c 10 <url>``
3. If no argument, look at package.json scripts and suggest which to benchmark
4. Check for common performance anti-patterns in the code (N+1 queries, missing indexes, unbounded loops, sync I/O in async code)
5. Check bundle size if this is a frontend project (``npx @next/bundle-analyzer`` or similar)

Report findings with concrete numbers and suggested optimizations.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "docker-lint.md") -Value @"
Analyze the Docker setup in this project:

1. Lint all Dockerfiles with ``hadolint``
2. If images are built, analyze with ``dive`` for layer optimization opportunities
3. Check docker-compose.yml for best practices (health checks, resource limits, named volumes)
4. Verify .dockerignore exists and excludes node_modules, .git, etc.
5. Check for security issues: running as root, secrets in build args, latest tags

Fix any issues found and explain the changes.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "iac-review.md") -Value @"
Review the infrastructure-as-code in this project:

1. Run ``tflint`` on any Terraform/OpenTofu files
2. Run ``trivy config .`` to scan for misconfigurations
3. Run ``infracost breakdown --path .`` to estimate costs (if infracost is configured)
4. Check for: missing tags, overly permissive IAM, unencrypted resources, missing backups
5. Check CDK code for L1 constructs that should be L2/L3

Report findings with severity and recommended fixes.
"@

        Set-Content -Path (Join-Path $claudeCommandsDir "convert.md") -Value @"
Convert files between formats: `$ARGUMENTS

Use the available tools:
- ``pandoc`` for document conversion (md, html, pdf, docx, rst)
- ``d2`` for diagram generation from text
- ``mmdc`` (mermaid) for flowcharts, sequence diagrams, ERDs
- ``ffmpeg`` for audio/video conversion
- ``magick`` for image conversion and manipulation

Parse the user's intent from the arguments and run the appropriate conversion command.
Examples: "convert README.md to pdf", "resize logo.png to 200x200", "diagram from architecture.d2"
"@

        # /new-feature -- full trunk-based feature workflow
        Set-Content -Path (Join-Path $claudeCommandsDir "new-feature.md") -Value @"
Implement a new feature following trunk-based development: `$ARGUMENTS

Follow this workflow in order:
1. **Create issue**: Run ``gh issue create --title "<feature title>" --body "<description>" --label "feature"`` and note the issue number
2. **Create branch**: Run ``git switch -c feature/<short-kebab-name>``
3. **Implement**: Write the code with tests. Use conventional commits (feat, test, docs).
4. **Create/update README**: If this adds a new capability, update the project README
5. **Push and PR**: Run ``git push -u origin HEAD`` then ``gh pr create --title "feat: <title>" --body "## Summary\n<what and why>\n\n## Changes\n- <bullet list>\n\n## Test Plan\n- [ ] <test items>\n\nCloses #<issue-number>"``

Make each commit small and atomic. Write tests alongside the implementation, not after.
"@

        # /fix-bug -- full trunk-based bug fix workflow
        Set-Content -Path (Join-Path $claudeCommandsDir "fix-bug.md") -Value @"
Fix a bug following trunk-based development: `$ARGUMENTS

Follow this workflow in order:
1. **Create issue**: Run ``gh issue create --title "fix: <bug title>" --body "<description of bug, steps to reproduce, expected vs actual>" --label "bug"`` and note the issue number
2. **Create branch**: Run ``git switch -c fix/<short-kebab-name>``
3. **Write failing test first**: Write a test that reproduces the bug (should fail)
4. **Fix**: Implement the fix so the test passes
5. **Verify**: Run the full test suite to confirm no regressions
6. **Push and PR**: Run ``git push -u origin HEAD`` then ``gh pr create --title "fix: <title>" --body "## Bug\n<what was broken>\n\n## Root Cause\n<why it happened>\n\n## Fix\n<what changed>\n\n## Test Plan\n- [ ] Repro test passes\n- [ ] No regressions\n\nFixes #<issue-number>"``
"@

        # /create-readme -- generate a comprehensive README
        Set-Content -Path (Join-Path $claudeCommandsDir "create-readme.md") -Value @"
Generate a comprehensive README.md for this project.

Analyze the codebase to determine:
1. **Project name and description** -- from package.json, Cargo.toml, go.mod, or directory name
2. **Tech stack** -- languages, frameworks, key dependencies
3. **Prerequisites** -- runtime versions, required tools, env vars
4. **Getting started** -- install deps, run dev server, build, test
5. **Project structure** -- key directories and what they contain
6. **Available scripts/commands** -- from package.json scripts, Justfile, Makefile
7. **Environment variables** -- list all referenced env vars with descriptions (NOT values)
8. **Architecture** -- high-level overview if the project has multiple services/modules
9. **API documentation** -- if there are API routes, list endpoints with methods
10. **Deployment** -- if there are Docker/CI/CD files, document the process
11. **Contributing** -- branch naming, commit format, PR process

Use clean Markdown formatting. Be concise but complete. If information isn't available, leave a placeholder with a TODO comment.
"@

        # /init-project -- set up a new project with all best practices
        Set-Content -Path (Join-Path $claudeCommandsDir "init-project.md") -Value @"
Initialize a new project with industry best practices: `$ARGUMENTS

Set up the following in order:

## 1. Git
- Initialize repo with ``git init -b main``
- Create comprehensive .gitignore (language-appropriate)

## 2. README.md
- Project name, one-line description, tech stack
- Getting started (prerequisites, install, run, test)
- Available scripts/commands
- Project structure overview
- Environment variables (with descriptions, not values)

## 3. Project-Level CLAUDE.md
Create a ``.claude/CLAUDE.md`` with project-specific context:
``````markdown
# <Project Name>

## Overview
<One-paragraph description of what this project does>

## Tech Stack
<Languages, frameworks, key libraries>

## Architecture
<How the project is structured, key directories>

## Development
- Run dev: ``just dev`` or ``npm run dev``
- Run tests: ``just test`` or ``npm test``
- Build: ``just build`` or ``npm run build``

## Conventions
<Any project-specific conventions not in the global CLAUDE.md>
``````

## 4. Code Quality
- **EditorConfig**: Copy global defaults or create project-specific
- **Prettier**: Create .prettierrc if JS/TS project
- **Linting**: ESLint (TS/JS), ruff.toml (Python), clippy (Rust)

## 5. Testing
- Set up framework: vitest (preferred for TS), pytest (Python), cargo test (Rust)
- Create example test file

## 6. CI/CD
Create ``.github/workflows/ci.yml``:
``````yaml
on: [push, pull_request]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps: [checkout, setup-node/python/rust, install deps, lint, test, build]
``````

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
Create ``.github/PULL_REQUEST_TEMPLATE.md``:
``````markdown
## Summary
<!-- What does this PR do and why? -->

## Changes
-

## Test Plan
- [ ]

Closes #
``````

Create ``.github/ISSUE_TEMPLATE/feature.md``:
``````markdown
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
``````

Create ``.github/ISSUE_TEMPLATE/bug.md``:
``````markdown
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
``````

## 11. License
- Add MIT license (or ask which)

## 12. Initial commit and push
- ``git add -A && git commit -m "feat: initial project scaffold"``
- Create GitHub repo if not exists: ``gh repo create <name> --private --source=.``
- Push: ``git push -u origin main``
"@

        # /refactor -- refactor code with tests preserved
        Set-Content -Path (Join-Path $claudeCommandsDir "refactor.md") -Value @"
Refactor the specified code: `$ARGUMENTS

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
6. **Commit**: Use ``refactor(scope): description`` commit format.

If tests don't exist, write them FIRST before refactoring.
"@

        # /add-endpoint -- add an API endpoint with full stack
        Set-Content -Path (Join-Path $claudeCommandsDir "add-endpoint.md") -Value @"
Add a new API endpoint: `$ARGUMENTS

Implement the full vertical slice:
1. **Types**: Define request/response types (zod schema for TS, pydantic for Python)
2. **Route handler**: Implement the endpoint with proper HTTP method and status codes
3. **Validation**: Validate all inputs at the boundary
4. **Error handling**: Return structured errors with appropriate status codes
5. **Tests**: Write unit tests for the handler and integration tests for the route
6. **Documentation**: Add JSDoc/docstring, update API docs or README if they exist

Follow REST conventions:
- GET for retrieval (200), POST for creation (201), PUT/PATCH for updates (200), DELETE for removal (204)
- Response format: ``{ data: T }`` for success, ``{ error: { code, message } }`` for errors
- Always paginate list endpoints

Commit with: ``feat(api): add <METHOD> <path> endpoint``
"@

        # /add-component -- add a React component with tests and stories
        Set-Content -Path (Join-Path $claudeCommandsDir "add-component.md") -Value @"
Add a new React component: `$ARGUMENTS

Create the full component package:
1. **Component file**: ``ComponentName.tsx`` -- functional component with TypeScript props interface
2. **Tests**: ``ComponentName.test.tsx`` -- test rendering, user interactions, edge cases
3. **Types**: Export the props interface for consumers
4. **Index**: Add to barrel export (``index.ts``) if the directory uses one

Follow these patterns:
- Functional components only, use hooks for state/effects
- Props interface named ``ComponentNameProps``, exported
- Use ``forwardRef`` if the component wraps a native element
- Tailwind CSS for styling (or whatever the project uses)
- Handle loading, error, and empty states
- Accessibility: proper ARIA attributes, keyboard navigation, semantic HTML

Place in: ``src/components/ComponentName/`` (colocated structure)
Commit with: ``feat(ui): add <ComponentName> component``
"@

        # /ci-fix -- diagnose and fix CI failures
        Set-Content -Path (Join-Path $claudeCommandsDir "ci-fix.md") -Value @"
Diagnose and fix the CI/CD pipeline failure.

Steps:
1. **Check CI status**: Run ``gh run list --limit 5`` to see recent runs
2. **Get failure details**: Run ``gh run view <run-id> --log-failed`` to see the error
3. **Diagnose**: Identify the root cause (test failure, lint error, build error, dependency issue, flaky test)
4. **Fix**: Apply the fix
5. **Verify locally**: Run the same checks locally (``act`` for GitHub Actions, or the individual commands)
6. **Push**: Commit with ``ci: fix <description of what broke>``

Common CI issues to check:
- Node/Python version mismatch between local and CI
- Missing environment variables in CI
- Dependency resolution differences (lockfile out of date)
- Flaky tests (timing-dependent, order-dependent)
- ESLint/Prettier formatting differences
"@

        # /changelog -- generate changelog from git history
        Set-Content -Path (Join-Path $claudeCommandsDir "changelog.md") -Value @"
Generate a changelog from git history: `$ARGUMENTS

If no version range specified, generate from the last tag to HEAD.

1. Get commits: ``git log <range> --oneline --format="%h %s"``
2. Parse conventional commits and group by type:
   - **Features** (feat:) -- new functionality
   - **Bug Fixes** (fix:) -- bug fixes
   - **Performance** (perf:) -- performance improvements
   - **Documentation** (docs:) -- documentation changes
   - **Other** (chore:, refactor:, style:, test:, build:, ci:)
3. Format as Markdown with:
   - Version header with date
   - Grouped sections (only include sections that have entries)
   - Each entry: short description with commit hash link
   - Breaking changes highlighted at the top
4. If a CHANGELOG.md exists, prepend the new entry. Otherwise create it.

Format: Keep it concise -- one line per change, no fluff.
"@

        # /commit-msg -- generate commit message from staged changes
        Set-Content -Path (Join-Path $claudeCommandsDir "commit-msg.md") -Value @"
Generate a conventional commit message for the currently staged changes.

1. Run ``git diff --cached --stat`` to see what files changed
2. Run ``git diff --cached`` to see the actual changes
3. Analyze the changes and determine:
   - **Type**: feat, fix, docs, style, refactor, perf, test, build, ci, chore
   - **Scope**: the module or area affected (optional but preferred)
   - **Description**: concise summary in imperative mood
   - **Body**: explain WHAT changed and WHY (not HOW) -- only if non-obvious
   - **Footer**: reference issues if applicable (Closes #N)
4. Output the commit message in this format:
   ``````
   type(scope): short description

   Optional body explaining what and why.

   Closes #N
   ``````
5. Run the commit: ``git commit -m "<message>"``

Keep the first line under 72 characters. Use imperative mood ("add" not "added").
"@

        Write-Success "Claude Code commands created (20 commands: /pr-review, /test-plan, /dep-audit, /quick-doc, /cleanup, /security-scan, /perf-check, /docker-lint, /iac-review, /convert, /new-feature, /fix-bug, /create-readme, /init-project, /refactor, /add-endpoint, /add-component, /ci-fix, /changelog, /commit-msg)"
    }
}

} # configs

# =============================================================================
if (Test-ShouldRun "shell") {
Write-Banner "Shell Configuration (PowerShell Profile)"

$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

$MANAGED_MARKER = "# >>> dev-setup managed block >>>"
$MANAGED_END    = "# <<< dev-setup managed block <<<"

$managedBlock = @"
$MANAGED_MARKER
# This block is managed by setup-dev-tools-windows.ps1 -- edits may be overwritten on re-run.
# Add personal customizations OUTSIDE this block (above or below).

# -- PATH additions -----------------------------------------------------------
`$env:Path = "`$HOME\Scripts\bin;`$env:Path"

# -- Environment Variables ----------------------------------------------------
`$env:RIPGREP_CONFIG_PATH = "`$HOME\.ripgreprc"
`$env:EDITOR = "code --wait"
`$env:VISUAL = "code --wait"
`$env:PAGER = "bat --style=plain --paging=always"
`$env:LANG = "en_US.UTF-8"

# XDG Base Directories
`$env:XDG_CONFIG_HOME = "`$HOME\.config"
`$env:XDG_DATA_HOME = "`$HOME\.local\share"
`$env:XDG_CACHE_HOME = "`$HOME\.cache"
`$env:XDG_STATE_HOME = "`$HOME\.local\state"

# Go
if (Get-Command go -ErrorAction SilentlyContinue) {
    `$env:GOPATH = "`$HOME\.local\share\go"
    `$env:Path = "`$env:GOPATH\bin;`$env:Path"
}

# Rust
if (Test-Path "`$HOME\.cargo\env.ps1") { . "`$HOME\.cargo\env.ps1" }
elseif (Test-Path "`$HOME\.cargo\bin") { `$env:Path = "`$HOME\.cargo\bin;`$env:Path" }

# bun
if (Test-Path "`$HOME\.bun") {
    `$env:BUN_INSTALL = "`$HOME\.bun"
    `$env:Path = "`$env:BUN_INSTALL\bin;`$env:Path"
}

# -- Tool Initialization ------------------------------------------------------

# mise (universal version manager — Node, Python, Go, Ruby, etc.)
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate powershell | Invoke-Expression
}

# Starship prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Atuin (shell history)
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    Invoke-Expression (& atuin init powershell)
}

# Zoxide (smart cd)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& zoxide init powershell)
}

# Direnv
if (Get-Command direnv -ErrorAction SilentlyContinue) {
    Invoke-Expression "`$(direnv hook pwsh)"
}

# fzf -- Dracula colors + fd for file finding + bat for preview
`$env:FZF_DEFAULT_OPTS = @"
  --color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9
  --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9
  --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6
  --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4
  --color=border:#6272a4
  --height=60% --layout=reverse --border=rounded
  --prompt='> ' --pointer='>' --marker='v'
  --bind='ctrl-/:toggle-preview'
  --bind='ctrl-d:half-page-down,ctrl-u:half-page-up'
  --bind='ctrl-y:execute-silent(echo {+} | clip.exe)+abort'
  --preview-window='right:50%:wrap:hidden'
  --info=inline
"@

# Use fd instead of find (respects .gitignore, faster)
`$env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'

# CTRL-T: paste file path (with bat preview)
`$env:FZF_CTRL_T_COMMAND = 'fd --type f --hidden --follow --exclude .git'
`$env:FZF_CTRL_T_OPTS = "--preview 'bat --color=always --style=numbers --line-range=:300 {}' --preview-window='right:50%:wrap'"

# ALT-C: cd into directory (with eza tree preview)
`$env:FZF_ALT_C_COMMAND = 'fd --type d --hidden --follow --exclude .git'
`$env:FZF_ALT_C_OPTS = "--preview 'eza --tree --icons --level=2 --color=always {}' --preview-window='right:50%:wrap'"

# LS_COLORS via vivid (Dracula theme)
if (Get-Command vivid -ErrorAction SilentlyContinue) {
    `$env:LS_COLORS = (vivid generate dracula)
}

# -- PSReadLine (replaces zsh-autosuggestions + syntax-highlighting) -----------
if (Get-Module -ListAvailable PSReadLine) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# -- Modern Tool Aliases (replacements for built-in commands) -----------------
Set-Alias -Name cat -Value bat -Option AllScope -Force -ErrorAction SilentlyContinue
Set-Alias -Name top -Value btop -Force -ErrorAction SilentlyContinue
Set-Alias -Name lg -Value lazygit -Force -ErrorAction SilentlyContinue
Set-Alias -Name lzd -Value lazydocker -Force -ErrorAction SilentlyContinue
Set-Alias -Name k -Value kubectl -Force -ErrorAction SilentlyContinue
Set-Alias -Name md -Value glow -Force -ErrorAction SilentlyContinue
Set-Alias -Name y -Value yazi -Force -ErrorAction SilentlyContinue

# Parameterized aliases as functions
function ls { eza --icons @args }
function ll { eza -la --icons --git @args }
function la { eza -a --icons @args }
function lt { eza --tree --icons --level=3 @args }
function du { dust @args }
function df { duf @args }
function psg { procs @args }
function ping2 { gping @args }
function dig2 { doggo @args }
function watch2 { viddy @args }
function dl { aria2c @args }
function serve { miniserve --color-scheme-dark dracula -qr . @args }

# -- Git & GitHub -------------------------------------------------------------
function ghd { gh dash @args }
function gdft { git dft @args }
function gha { act @args }

# -- Media & Conversion -------------------------------------------------------
function ytdl { yt-dlp @args }
function ytmp3 { yt-dlp -x --audio-format mp3 @args }
function ffq { ffmpeg -hide_banner -loglevel warning @args }
function md2pdf { pandoc -f markdown -t pdf @args }
function md2html { pandoc -f markdown -t html -s @args }
function md2docx { pandoc -f markdown -t docx @args }

# -- Python (uv) -------------------------------------------------------------
function pip2 { uv pip @args }
function venv { uv venv @args }
function pyrun { uv run @args }

# -- Global Justfile ----------------------------------------------------------
function gj { just --justfile `$HOME\.justfile --working-directory . @args }

# -- Dev & Testing ------------------------------------------------------------
function bench { hyperfine @args }
function loadtest { oha @args }
function lint-sh { shellcheck @args }

# -- Directory Shortcuts ------------------------------------------------------
function cw { Set-Location "`$HOME\Code\work" }
function cper { Set-Location "`$HOME\Code\personal" }
function coss { Set-Location "`$HOME\Code\oss" }
function clearn { Set-Location "`$HOME\Code\learning" }
function cscratch { Set-Location "`$HOME\Code\work\scratch" }
function cscripts { Set-Location "`$HOME\Scripts" }

# -- Helper Script Shortcuts --------------------------------------------------
function nproj { & "`$HOME\Scripts\bin\new-project.ps1" @args }
function cwork { & "`$HOME\Scripts\bin\clone-work.ps1" @args }
function cpers { & "`$HOME\Scripts\bin\clone-personal.ps1" @args }
function dotback { & "`$HOME\Scripts\bin\backup-dotfiles.ps1" @args }
function pstats { & "`$HOME\Scripts\bin\project-stats.ps1" @args }
function cleandl { & "`$HOME\Scripts\bin\clean-downloads.ps1" @args }
function hc { & "`$HOME\Scripts\bin\health-check.ps1" @args }
function sshsetup { & "`$HOME\Scripts\bin\setup-ssh.ps1" @args }
function scoopsnap { & "`$HOME\Scripts\bin\export-brewfile.ps1" @args }

# -- Completions --------------------------------------------------------------
try { kubectl completion powershell 2>`$null | Out-String | Invoke-Expression } catch {}
try { gh completion -s powershell 2>`$null | Out-String | Invoke-Expression } catch {}

# -- System -------------------------------------------------------------------
function update { topgrade @args }
function sysinfo { fastfetch @args }

# -- Terminal Welcome Screen ---------------------------------------------------
# Colorful greeting on new terminal sessions (not in VS Code integrated terminal)
if (`$env:TERM_PROGRAM -ne "vscode") {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        fastfetch --logo small
    }
    Write-Host ""
    `$date = Get-Date -Format "dddd, MMMM dd yyyy  •  HH:mm"
    Write-Host "  `$date  " -ForegroundColor Magenta -NoNewline
    `$tips = @(
        "💡 git stash -u  — stash untracked files too",
        "💡 fd -e ts -x wc -l  — count lines in every .ts file",
        "💡 rg TODO --glob '!node_modules'  — search TODOs",
        "💡 just --list  — see all task runner recipes",
        "💡 gh pr create --web  — open PR in browser",
        "💡 btop  — beautiful system monitor",
        "💡 yazi  — terminal file manager with preview",
        "💡 oha -n 500 http://localhost:3000  — quick load test",
        "💡 sd 'old' 'new' file.ts  — fast find & replace",
        "💡 dust ~/Code  — visual disk usage of your projects",
        "💡 doggo example.com AAAA  — colorized DNS lookup",
        "💡 hyperfine 'cmd1' 'cmd2'  — benchmark two commands",
        "💡 fx data.json  — interactive JSON explorer",
        "💡 gj ports  — list all listening ports",
        "💡 hc  — quick system health check"
    )
    Write-Host `$tips[(Get-Random -Maximum `$tips.Count)]
    Write-Host ""
}

$MANAGED_END
"@

if (-not $DRY_RUN) {
    if (Test-Path $PROFILE) {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($profileContent -match [regex]::Escape($MANAGED_MARKER)) {
            Write-Info "Updating managed block in existing `$PROFILE..."
            $backup = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $PROFILE $backup
            # Remove old managed block
            $pattern = [regex]::Escape($MANAGED_MARKER) + "[\s\S]*?" + [regex]::Escape($MANAGED_END)
            $newContent = [regex]::Replace($profileContent, $pattern, "")
            $newContent = $newContent.TrimEnd() + "`n`n" + $managedBlock + "`n"
            Set-Content -Path $PROFILE -Value $newContent
            Write-Success "`$PROFILE managed block updated (backup: $backup)"
        } else {
            Write-Info "Appending managed block to existing `$PROFILE..."
            $backup = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item $PROFILE $backup
            Add-Content -Path $PROFILE -Value "`n$managedBlock"
            Write-Success "`$PROFILE updated (backup: $backup)"
        }
    } else {
        Write-Info "Creating `$PROFILE..."
        Set-Content -Path $PROFILE -Value @"
# =============================================================================
# PowerShell Profile -- generated by setup-dev-tools-windows.ps1
# =============================================================================
# Add personal customizations OUTSIDE the managed block below.

$managedBlock
"@
        Write-Success "`$PROFILE created"
    }
}

} # shell

# =============================================================================
# FIRST-RUN SETUP (interactive — only runs if not already configured)
# =============================================================================
if (-not $DRY_RUN) {
Write-Banner "First-Run Setup"

# ---- SSH Key Generation ----
$sshKeyPath = Join-Path $HOME ".ssh\id_ed25519"
if (-not (Test-Path $sshKeyPath)) {
    Write-Host ""
    $sshConfirm = Read-Host "Generate an SSH key? [Y/n]"
    if ($sshConfirm -notmatch '^[Nn]$') {
        $sshEmail = Read-Host "Email for SSH key"
        if ($sshEmail) {
            $sshDir = Join-Path $HOME ".ssh"
            if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
            & ssh-keygen.exe -t ed25519 -C $sshEmail -f $sshKeyPath
            try {
                Start-Service ssh-agent -ErrorAction SilentlyContinue
                & ssh-add.exe $sshKeyPath 2>$null
            } catch {
                Write-Warn "Could not start ssh-agent: $_"
            }
            Write-Success "SSH key generated at ~/.ssh/id_ed25519"
        }
    }
} else {
    Write-Warn "SSH key already exists at ~/.ssh/id_ed25519"
}

# ---- GitHub Authentication ----
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghAuth = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        $ghConfirm = Read-Host "Authenticate with GitHub? [Y/n]"
        if ($ghConfirm -notmatch '^[Nn]$') {
            Write-Info "Opening GitHub authentication..."
            & gh auth login
            # Add SSH key to GitHub if it was just generated
            $sshPubKey = Join-Path $HOME ".ssh\id_ed25519.pub"
            if (Test-Path $sshPubKey) {
                $sshGhConfirm = Read-Host "Add SSH key to GitHub? [Y/n]"
                if ($sshGhConfirm -notmatch '^[Nn]$') {
                    $keyTitle = "$env:COMPUTERNAME $(Get-Date -Format 'yyyy-MM-dd')"
                    & gh ssh-key add $sshPubKey --title $keyTitle
                    Write-Success "SSH key added to GitHub"
                }
            }
        }
    } else {
        Write-Warn "GitHub CLI already authenticated"
    }
}

# ---- Git Identity ----
$gitconfigWork = Join-Path $HOME ".gitconfig-work"
$gitconfigPersonal = Join-Path $HOME ".gitconfig-personal"

# Work identity
if ((Test-Path $gitconfigWork) -and (Select-String -Path $gitconfigWork -Pattern "^    # name = " -Quiet)) {
    Write-Host ""
    $workConfirm = Read-Host "Set up your work git identity? [Y/n]"
    if ($workConfirm -notmatch '^[Nn]$') {
        $workName = Read-Host "Work name"
        $workEmail = Read-Host "Work email"
        if ($workName -and $workEmail) {
            Set-Content -Path $gitconfigWork -Value @"
[user]
    name = $workName
    email = $workEmail
"@
            Write-Success "Work git identity set ($workEmail)"
        }
    }
}

# Personal identity
if ((Test-Path $gitconfigPersonal) -and (Select-String -Path $gitconfigPersonal -Pattern "^    # name = " -Quiet)) {
    Write-Host ""
    $personalConfirm = Read-Host "Set up your personal git identity? [Y/n]"
    if ($personalConfirm -notmatch '^[Nn]$') {
        $personalName = Read-Host "Personal name"
        $personalEmail = Read-Host "Personal email"
        if ($personalName -and $personalEmail) {
            Set-Content -Path $gitconfigPersonal -Value @"
[user]
    name = $personalName
    email = $personalEmail
"@
            Write-Success "Personal git identity set ($personalEmail)"
        }
    }
}

}  # DRY_RUN (first-run setup)

# =============================================================================
# POST-INSTALL VERIFICATION
# =============================================================================
Write-Banner "Post-install Verification"

if (-not $DRY_RUN) {
    Write-Info "Verifying critical tools..."

    $verifyTools = @(
        @{ Name = "git";      Cmd = "git --version" }
        @{ Name = "gh";       Cmd = "gh --version" }
        @{ Name = "node";     Cmd = "node --version" }
        @{ Name = "npm";      Cmd = "npm --version" }
        @{ Name = "python";   Cmd = "python --version" }
        @{ Name = "go";       Cmd = "go version" }
        @{ Name = "rustc";    Cmd = "rustc --version" }
        @{ Name = "bun";      Cmd = "bun --version" }
        @{ Name = "uv";       Cmd = "uv --version" }
        @{ Name = "code";     Cmd = "code --version" }
        @{ Name = "docker";   Cmd = "docker --version" }
        @{ Name = "starship"; Cmd = "starship --version" }
        @{ Name = "fzf";      Cmd = "fzf --version" }
        @{ Name = "eza";      Cmd = "eza --version" }
        @{ Name = "bat";      Cmd = "bat --version" }
        @{ Name = "rg";       Cmd = "rg --version" }
        @{ Name = "fd";       Cmd = "fd --version" }
        @{ Name = "zoxide";   Cmd = "zoxide --version" }
        @{ Name = "atuin";    Cmd = "atuin --version" }
        @{ Name = "lazygit";  Cmd = "lazygit --version" }
        @{ Name = "just";     Cmd = "just --version" }
        @{ Name = "delta";    Cmd = "delta --version" }
    )

    $verifyPass = 0
    $verifyFail = 0
    foreach ($tool in $verifyTools) {
        try {
            $version = Invoke-Expression $tool.Cmd 2>$null | Select-Object -First 1
            if ($version) {
                Write-Host "  + $($tool.Name): $version" -ForegroundColor Green
                $verifyPass++
            } else {
                Write-Host "  x $($tool.Name): not found or not working" -ForegroundColor Red
                $verifyFail++
            }
        } catch {
            Write-Host "  x $($tool.Name): not found or not working" -ForegroundColor Red
            $verifyFail++
        }
    }
    Write-Host ""
    Write-Success "Verification: $verifyPass passed, $verifyFail failed"

    # Scoop cleanup
    if (Test-Command "scoop") {
        Write-Info "Running scoop cleanup..."
        scoop cleanup --all 2>&1 | Out-File $LOG_FILE -Append
        Write-Success "Scoop cleanup complete"
    }
} else {
    Write-Info "[DRY RUN] Skipping verification"
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================

$SCRIPT_END = Get-Date
$DURATION = $SCRIPT_END - $SCRIPT_START
$minutes = [math]::Floor($DURATION.TotalMinutes)
$seconds = $DURATION.Seconds

Write-Host ""
Write-Host ("=" * 74) -ForegroundColor Magenta
Write-Host "  Setup Complete!" -ForegroundColor Magenta
Write-Host ("=" * 74) -ForegroundColor Magenta
Write-Host ""
Write-Host "  Installed:  $($script:INSTALL_SUCCESS)" -ForegroundColor Green
Write-Host "  Skipped:    $($script:INSTALL_SKIPPED) (already installed)" -ForegroundColor Yellow
Write-Host "  Failed:     $($script:INSTALL_FAILED)" -ForegroundColor Red
Write-Host "  Duration:   ${minutes}m ${seconds}s" -ForegroundColor Blue
Write-Host "  Log:        $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

if ($script:FAILED_ITEMS.Count -gt 0) {
    Write-Host "Failed items:" -ForegroundColor Red
    foreach ($item in $script:FAILED_ITEMS) {
        Write-Host "  - $item" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Check the log for details: Get-Content $LOG_FILE | Select-String ERROR" -ForegroundColor DarkGray
    Write-Host ""
}

if ($DRY_RUN) {
    Write-Host "  This was a dry run -- no changes were made." -ForegroundColor Yellow
    Write-Host "  Run without --dry-run to install everything." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host ""
Write-Info "What was configured:"
Write-Host "  [`$PROFILE]              PowerShell profile (managed block with aliases)"
Write-Host "  [~\.ssh\config]          SSH keep-alive, strong algorithms"
Write-Host "  [~\.gitignore_global]    Global gitignore (Thumbs.db, .env, node_modules)"
Write-Host "  [~\.gitconfig]           Git aliases, rebase, delta, difftastic"
Write-Host "  [~\.gnupg\]              GPG agent config"
Write-Host "  [~\.npmrc]               save-exact, no telemetry"
Write-Host "  [~\.editorconfig]        Cross-editor consistency"
Write-Host "  [~\.prettierrc]          Global Prettier defaults"
Write-Host "  [~\.curlrc]              Follow redirects, retry, compression"
Write-Host "  [~\.docker\daemon.json]  BuildKit, log rotation"
Write-Host "  [~\.aria2\aria2.conf]    16 connections, auto-resume"
Write-Host "  [~\.config\starship]     Dracula prompt"
Write-Host "  [~\.config\atuin]        Fuzzy search, local-only"
Write-Host "  [~\.config\glow]         Dracula Markdown renderer"
Write-Host "  [~\.config\yt-dlp]       Best quality, aria2c downloader"
Write-Host "  [~\.config\gh-dash]      GitHub dashboard, Dracula theme"
Write-Host "  [~\.config\stern]        K8s log tailing"
Write-Host "  [~\.config\yazi]         File manager with Dracula theme"
Write-Host "  [~\.justfile]            Global task runner recipes"
Write-Host "  [VS Code]                Dracula theme, extensions, JetBrains Mono"
Write-Host "  [Windows Terminal]       Dracula color scheme"
Write-Host "  [Alacritty]              Dracula theme, JetBrains Mono"
Write-Host "  [lazygit]                Dracula theme, delta pager"
Write-Host "  [k9s]                    Dracula skin"
Write-Host "  [Explorer]               Hidden files, file extensions"
Write-Host "  [Registry]               Keyboard, taskbar, animations, DNS"
Write-Host "  [Claude Code]            Custom commands (20), rules, hooks"
Write-Host ""
Write-Info "Optional Chrome extensions to install manually:"
Write-Host "  - axe DevTools (accessibility testing)"
Write-Host "  - React Developer Tools"
Write-Host "  - Lighthouse"
Write-Host "  - JSON Formatter"
Write-Host ""
Write-Info "Chezmoi quickstart (dotfile backup):"
Write-Host "  chezmoi init                          # Initialize"
Write-Host "  chezmoi add ~\.editorconfig ~\.npmrc   # Track dotfiles"
Write-Host "  chezmoi cd; git remote add origin <repo>  # Link to git repo"
Write-Host "  chezmoi update                        # Pull on new machine"
Write-Host ""
Write-Info "Next steps:"
Write-Host "  1. Restart your terminal or run: . `$PROFILE"
Write-Host '  2. Generate SSH key: ssh-keygen -t ed25519 -C "your_email@example.com"'
Write-Host "  3. Add SSH key to GitHub: gh ssh-key add ~\.ssh\id_ed25519.pub"
Write-Host "  4. Set up ngrok: ngrok config add-authtoken <TOKEN>"
Write-Host "  5. Set up chezmoi: chezmoi init && chezmoi add ~\.npmrc"
Write-Host "  6. Enable BitLocker: Settings > Privacy & Security > Device Encryption"
Write-Host "  7. Enable Windows Firewall: Settings > Privacy & Security > Windows Security"
Write-Host "  8. Enable Clipboard History: Settings > System > Clipboard > Clipboard History"
Write-Host ""
Write-Host "  Restart your terminal to activate everything." -ForegroundColor Green
Write-Host ""

} finally {
    # Cleanup — always release lock, even on Ctrl+C
    Release-Lock
}
