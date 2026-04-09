# Development Environment Setup

[![Lint](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml)
[![Release](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/vixygrey/vixygrey-dev-setup?display_name=tag&sort=semver)](https://github.com/vixygrey/vixygrey-dev-setup/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-supported-brightgreen)
![Linux](https://img.shields.io/badge/Linux-supported-brightgreen)
![Windows](https://img.shields.io/badge/Windows-supported-brightgreen)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)
![Tools](https://img.shields.io/badge/tools-220%2B-purple)
![Configs](https://img.shields.io/badge/configs-60%2B-purple)

Three platform-specific scripts that install and configure **220+ tools** with **60+ config files** for development, GitHub, AWS/CDK, IaC, DX, UI/UX, security, backup, and daily productivity. Safe to re-run -- each skips anything already installed.

| Platform | Script | Package Managers |
|----------|--------|-----------------|
| **macOS** | `scripts/setup-dev-tools-mac.sh` | Homebrew |
| **Windows** | `scripts/setup-dev-tools-windows.ps1` | winget + Scoop |
| **Linux** | `scripts/setup-dev-tools-linux.sh` | apt / dnf / pacman + snap + flatpak |

## Documentation

Each platform has a self-contained guide and shortcuts reference:

| Platform | Guide | Shortcuts |
|----------|-------|-----------|
| **macOS** | [Guide](docs/GUIDE-MACOS.md) | [Shortcuts](docs/SHORTCUTS-MACOS.md) |
| **Linux** | [Guide](docs/GUIDE-LINUX.md) | [Shortcuts](docs/SHORTCUTS-LINUX.md) |
| **Windows** | [Guide](docs/GUIDE-WINDOWS.md) | [Shortcuts](docs/SHORTCUTS-WINDOWS.md) |

## Quick Start

### macOS
```bash
chmod +x scripts/setup-dev-tools-mac.sh
./scripts/setup-dev-tools-mac.sh
```

### Windows (PowerShell as Administrator)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\scripts\setup-dev-tools-windows.ps1
```

### Linux (Ubuntu/Debian, Fedora/RHEL, or Arch)
```bash
chmod +x scripts/setup-dev-tools-linux.sh
./scripts/setup-dev-tools-linux.sh
```

## CLI Options (all three scripts)

All scripts share the same flags:

```bash
./scripts/setup-dev-tools-mac.sh --help              # Show all options
./scripts/setup-dev-tools-mac.sh --dry-run           # Preview changes without installing
./scripts/setup-dev-tools-mac.sh --list              # List all tools that would be installed
./scripts/setup-dev-tools-mac.sh --resume            # Continue from where a previous run left off
./scripts/setup-dev-tools-mac.sh --uninstall         # Show commands to remove everything (no changes made)
./scripts/setup-dev-tools-mac.sh --cleanup           # Remove tools from previous versions no longer in script
./scripts/setup-dev-tools-mac.sh --list-categories   # List all available categories
./scripts/setup-dev-tools-mac.sh --skip mac-media,mac-cloud  # Skip specific categories
./scripts/setup-dev-tools-mac.sh --only core,git,aws,dx      # Only install specific categories
./scripts/setup-dev-tools-mac.sh --version           # Show script version
```

> Platform-specific categories use prefixes: `mac-*`, `win-*`, `linux-*` (e.g., `--skip win-bloat`)

## What It Does

1. **Pre-flight checks** -- verifies macOS version, disk space, internet, admin privileges
2. Installs all tools via Homebrew, Cask, npm, and Mac App Store with **progress tracking**
3. Configures every tool with sensible defaults
4. Applies the **Dracula** theme everywhere
5. Sets macOS system defaults (Dock, keyboard, Finder, screenshots, wallpaper, screensaver, etc.)
6. Configures Finder sidebar with custom favorites via **LSSharedFileList** API
7. Clears Dock of default pins (start fresh, drag your own)
8. Optionally **removes pre-installed Apple bloat** (GarageBand, News, Stocks, etc.)
9. Auto-writes `~/.zshrc` with a managed block (preserves your customizations)
10. Exports a `Brewfile` snapshot (with descriptions) for reproducibility
11. **Post-install verification** -- verifies critical tools work
12. Runs `brew cleanup` and `brew doctor`
13. **Logs everything** to `~/.local/share/dev-setup/` for debugging
14. Reports final summary with install/skip/fail counts and duration

## Features

| Feature | Description |
|---------|-------------|
| **Idempotent** | Safe to re-run -- skips anything already installed |
| **Dry run** | Preview all changes with `--dry-run` |
| **Resume** | Continue after a failure with `--resume` -- skips previously completed items |
| **Uninstall guide** | Show removal commands with `--uninstall` (no destructive actions taken) |
| **Cleanup** | Remove tools from previous versions with `--cleanup` (auto-detects deprecated tools) |
| **Lockfile** | Prevents concurrent runs via atomic directory-based lock |
| **Category filtering** | Install only what you need with `--only` / `--skip` (validates category names) |
| **List tools** | See everything that would be installed with `--list` |
| **Progress bar** | Visual progress counter with dynamic total (capped at 100%) |
| **Fast installs** | `HOMEBREW_NO_AUTO_UPDATE` set after initial update for faster installs |
| **Error resilient** | Continues on failure, reports all failures at the end with separate error log |
| **Pre-flight checks** | Validates internet, disk space, Homebrew health, and admin privileges upfront |
| **Logging** | Full log file for debugging failed installs |
| **Verification** | Post-install check that critical tools actually work |
| **Timing** | Shows total duration at the end |

---

## Prerequisites (auto-installed)

| Tool | Description |
|------|-------------|
| **Xcode CLI Tools** | Compilers, git, headers -- required before everything else |
| **Homebrew** | macOS package manager |
| **coreutils** | GNU core utilities -- Linux-compatible versions of standard tools |
| **gnu-sed** | GNU sed -- consistent behavior with Linux scripts |
| **gnu-tar** | GNU tar -- consistent behavior with Linux scripts |
| **gawk** | GNU awk -- full-featured awk replacement |
| **findutils** | GNU find and xargs -- Linux-compatible |

---

## Core Development

| Tool | Description |
|------|-------------|
| **mise** | Universal version manager -- Node, Python, Go, Ruby all in one tool |
| **Node.js LTS** | JavaScript runtime (latest Long Term Support version, installed via mise) |
| **Go** | Go programming language |
| **Python 3.12** | Python runtime (installed via mise) |
| **uv** | Fast Python package manager -- 10-100x faster than pip |
| **Rust** | Rust toolchain via rustup (rustc, cargo, etc.) |
| **bun** | Fast JS runtime, bundler, and test runner |
| **pnpm** | Fast, disk-efficient npm alternative |
| **jq** | Lightweight command-line JSON processor |
| **direnv** | Per-directory environment variables (auto-loads `.envrc`) |
| **watchman** | File watching service (used by React Native, Jest, etc.) |
| **cmake** | Cross-platform build system generator |
| **pkg-config** | Helper tool for compiling libraries |
| **OrbStack** | Fast container runtime -- 2-5x less memory than Docker Desktop, native macOS feel |

---

## Git & GitHub

| Tool | Description |
|------|-------------|
| **git** | Distributed version control |
| **gh** | GitHub CLI -- PRs, issues, Actions from the terminal |
| **delta** | Beautiful git diffs with syntax highlighting and side-by-side view |
| **git-lfs** | Git Large File Storage for binary assets |
| **gpg** | GNU Privacy Guard for commit signing and encryption |
| **pinentry-mac** | macOS keychain integration for GPG passphrases |
| **lazygit** | Terminal UI for git -- visualize branches, stage hunks interactively |
| **git-absorb** | Auto-fixup commits -- automatically amends the right commit |
| **git-cliff** | Generate changelogs from conventional commits |
| **pre-commit** | Git hook framework -- run linters/formatters before each commit |

---

## AWS & CDK

| Tool | Description |
|------|-------------|
| **aws-cli v2** | Official AWS command-line interface |
| **aws-cdk** | AWS Cloud Development Kit -- infrastructure as TypeScript/Python code |
| **cdk-nag** | CDK rule packs for security and best-practice compliance |
| **aws-sam-cli** | AWS Serverless Application Model -- local Lambda testing |
| **cfn-lint** | CloudFormation template linter |
| **session-manager-plugin** | SSH-less access to EC2 instances via AWS SSM |
| **granted** | Fast multi-account AWS SSO credential switching |

---

## Infrastructure as Code (IaC)

| Tool | Description |
|------|-------------|
| **OpenTofu** | Open-source Terraform alternative -- multi-cloud infrastructure as code |
| **tflint** | Terraform/OpenTofu linter -- catches errors before apply |
| **infracost** | Cost estimation for Terraform changes before apply |

---

## Security & Secrets

| Tool | Description |
|------|-------------|
| **detect-secrets** | Yelp's pre-commit hook for catching secrets before they're committed |
| **gitleaks** | Fast git secret scanning -- great for CI and pre-commit hooks |
| **age** | Modern, simple file encryption (replaces GPG for file encryption) |
| **sops** | Encrypt secrets in YAML/JSON files -- integrates with AWS KMS |
| **trivy** | Vulnerability scanner for containers, filesystems, and IaC |
| **semgrep** | Static analysis tool -- finds bugs and security issues in code |
| **cosign** | Sign and verify container images and artifacts |
| **snyk** | Dependency vulnerability scanning for npm, pip, Go, etc. |
| **mkcert** | Create locally-trusted HTTPS certificates for development |
| **ssh-audit** | Audit SSH server and client configuration for security |
| **clamav** | Open-source antivirus engine -- on-demand malware scanning |

---

## Modern Tool Replacements

Faster, prettier, smarter replacements for standard Unix utilities.

| Replaces | Tool | Description |
|----------|------|-------------|
| `ls` | **eza** | File listing with icons, git status, tree view, colors |
| `cat` | **bat** | Syntax highlighting, line numbers, git integration |
| `find` | **fd** | Simpler syntax, faster, respects `.gitignore` |
| `grep` | **ripgrep** | 10x faster search, `.gitignore`-aware, Unicode support |
| `cd` | **zoxide** | Learns your most-used directories, fuzzy jump |
| `diff` | **delta** | Syntax-highlighted diffs with side-by-side view |
| `diff` (code) | **difftastic** | Structural diff that understands code syntax |
| `man` | **tldr** | Community-driven simplified man pages with examples |
| `top` | **btop** | Modern resource monitor with graphs and mouse support |
| `sed` | **sd** | Intuitive find and replace with simpler regex syntax |
| `cut`/`awk` | **choose** | Simple column selection with negative indexing |
| `du` | **dust** | Visual disk usage tree with bar charts |
| `df` | **duf** | Colorful disk usage table with smart formatting |
| `ps` | **procs** | Sortable process list with tree view, Docker-aware |
| `ping` | **gping** | Real-time latency graph for multiple hosts |
| `curl` | **xh** | Colorized HTTP client with JSON shortcuts |
| `curl` | **curlie** | curl with httpie-like output formatting |
| `dig` | **doggo** | Colorized DNS lookup with DoH/DoT support |
| `wc` (code) | **tokei** | Count lines of code by language with statistics |
| `watch` | **viddy** | Modern watch with diff highlighting and history |
| `hexdump` | **hexyl** | Colorized hex viewer with ASCII sidebar |
| `curl`/`wget` | **aria2** | Multi-connection parallel downloads, 3-10x faster, BitTorrent |
| `rm` | **trash** | Moves files to macOS Trash instead of permanent delete |
| `rsync` | **rsync** (latest) | Updated rsync with better progress and Apple metadata |
| `tree` | **tree** | Directory listing in tree format |
| `make` | **just** | Modern task runner -- simpler syntax, no tab weirdness |
| file manager | **yazi** | Terminal file manager with image preview, vim keys, bulk ops |
| `jq` (interactive) | **fx** | Interactive JSON viewer/processor for exploring large JSON |
| `jq` (interactive) | **jnv** | Interactive JSON navigator with jq filtering |
| `LS_COLORS` | **vivid** | LS_COLORS generator -- colorize file listings by type (Dracula themed) |

---

## Data & File Processing

| Tool | Description |
|------|-------------|
| **yq** | jq for YAML -- parse and manipulate YAML files (essential for k8s/CDK) |
| **miller (mlr)** | awk/sed/jq for CSV, JSON, and tabular data |
| **csvkit** | Suite of CSV tools -- csvcut, csvgrep, csvstat, csvlook |
| **pandoc** | Universal document converter -- Markdown to PDF, DOCX, HTML, etc. |
| **imagemagick** | Image manipulation CLI -- resize, convert, composite, watermark |
| **ffmpeg** | Video/audio processing swiss army knife |
| **yt-dlp** | Video/audio downloader for YouTube and hundreds of other sites |

---

## Code Quality

| Tool | Description |
|------|-------------|
| **shellcheck** | Shell script linter -- catches bugs and bad practices |
| **shfmt** | Shell script formatter -- consistent style for bash/zsh scripts |
| **act** | Run GitHub Actions locally before pushing |
| **hadolint** | Dockerfile linter -- catches bad practices and security issues |
| **typos** | Source code spell checker -- fast, low false positives |
| **ast-grep** | Structural code search/replace using AST -- like semgrep but interactive |
| **ruff** | Extremely fast Python linter and formatter -- replaces flake8+black+isort |
| **npkill** | Find and delete node_modules folders to reclaim disk space |
| **commitizen** | Interactive conventional commit message generator |
| **commitlint** | Enforce conventional commit message format |
| **ni** | Universal package runner -- auto-detects npm/yarn/pnpm/bun |

---

## Performance & Load Testing

| Tool | Description |
|------|-------------|
| **hyperfine** | Command-line benchmarking tool -- compare execution times |
| **oha** | HTTP load testing tool written in Rust -- fast and simple |
| **hurl** | Run HTTP requests from plain text files -- curl meets test runner |

---

## Dev Servers & Tunnels

| Tool | Description |
|------|-------------|
| **ngrok** | Expose localhost to the internet for webhooks and demos |
| **miniserve** | Instant file server from any directory -- one command |
| **caddy** | Modern web server with automatic HTTPS |

---

## Terminal Productivity

| Tool | Description |
|------|-------------|
| **glow** | Render Markdown beautifully in the terminal |
| **watchexec** | Run commands on file changes -- supports globs, debouncing, process groups |
| **pv** | Pipe viewer -- add progress bars to any piped command |
| **parallel** | GNU parallel -- run commands in parallel across multiple cores |
| **asciinema** | Record and share terminal sessions as text (not video) |
| **gum** | Shell script UI toolkit -- pretty prompts, spinners, confirmations |
| **nushell** | Structured data shell -- pipelines output tables, not strings |
| **topgrade** | Update everything at once -- brew, npm, pip, macOS, all in one command |
| **fastfetch** | Quick system info display -- faster neofetch replacement |
| **nano** (latest) | Upgraded nano with syntax highlighting |
| **lnav** | Advanced log file viewer -- auto-format, SQL queries on logs |

---

## Kubernetes & GitHub Extras

| Tool | Description |
|------|-------------|
| **stern** | Multi-pod log tailing for Kubernetes |
| **gh-dash** | GitHub dashboard in the terminal -- PRs, issues, notifications |

---

## Database & Data

| Tool | Description |
|------|-------------|
| **pgcli** | Auto-completing PostgreSQL CLI with syntax highlighting |
| **mycli** | Auto-completing MySQL CLI with syntax highlighting |
| **lazysql** | TUI for databases -- interactive SQL queries in terminal |
| **usql** | Universal SQL CLI -- connects to Postgres, MySQL, SQLite, and more |
| **sq** | jq for databases -- query SQLite, Postgres, CSV from one tool |
| **dbmate** | Lightweight, framework-agnostic database migration tool |
| **TablePlus** | Native macOS database GUI -- fast, clean, supports 20+ databases |

---

## Containers & Orchestration

| Tool | Description |
|------|-------------|
| **lazydocker** | Terminal UI for Docker -- manage containers, images, volumes |
| **dive** | Explore Docker image layers -- find what's taking up space |
| **kubectl** | Kubernetes CLI for managing clusters |
| **k9s** | Terminal UI for Kubernetes -- navigate clusters with keyboard |

---

## API Development

| Tool | Description |
|------|-------------|
| **Bruno** | Open-source API client -- Postman alternative, stores in git |
| **grpcurl** | curl for gRPC services |

---

## Networking & Debugging

| Tool | Description |
|------|-------------|
| **mtr** | Combines ping and traceroute into a single diagnostic tool |
| **bandwhich** | Real-time bandwidth usage by process, connection, and host |
| **nmap** | Network scanner -- discover hosts and services |
| **trippy** | Modern traceroute TUI with real-time charts and hop statistics |

---

## Developer Experience

| Tool | Description |
|------|-------------|
| **fzf** | Fuzzy finder -- search files, history, branches interactively |
| **starship** | Cross-shell prompt with git status, language versions, and more |
| **zsh-autosuggestions** | Fish-like inline suggestions as you type |
| **zsh-syntax-highlighting** | Command coloring in the terminal -- red for errors |
| **atuin** | Replaces shell history with SQLite-backed, fuzzy-searchable database |
| **mise** | Universal version manager -- Node, Python, Go, Ruby all in one (replaces nvm + pyenv + rbenv) |
| **VS Code** | Primary code editor and IDE |
| **Zed** | Fast native editor from ex-Atom team -- GPU-rendered |
| **Claude Code** | AI-assisted coding in the terminal |
| **GitHub Copilot CLI** | AI suggestions in the terminal (via `gh copilot suggest`) |
| **chezmoi** | Dotfile manager -- backup and restore configs across machines |
| **mitmproxy** | Free HTTP debugging proxy -- inspect and modify API calls from any app |
| **Ghostty** | Fast GPU-accelerated terminal -- daily driver, native macOS feel |
| **zellij** | Modern terminal multiplexer -- discoverable UI, layouts, Rust-based |
| **Raycast** | Spotlight replacement with extensions, snippets, and workflows |
| **TypeScript** | Typed JavaScript -- installed globally for scripts and tooling |
| **tsx** | Run TypeScript files directly without a build step |
| **Turborepo** | High-performance monorepo build system |

---

## UX & Design

| Tool | Description |
|------|-------------|
| **Lighthouse** | Web performance, accessibility, and SEO auditing CLI |

---

## Documentation & Diagrams

| Tool | Description |
|------|-------------|
| **d2** | Code-to-diagram scripting language -- declarative diagrams as code |
| **Mermaid CLI** | Render Mermaid diagrams (flowcharts, sequences, ERDs) from CLI |

---

## Fonts

| Font | Description |
|------|-------------|
| **JetBrains Mono** | Primary development font with ligatures |
| **JetBrains Mono Nerd Font** | JetBrains Mono with patched icons for terminal tools |
| **MesloLGS Nerd Font** | Classic terminal font with icons for starship/eza |
| **Fira Code** | Popular ligature font -- alternative to JetBrains Mono |
| **Fira Code Nerd Font** | Fira Code with patched icons |
| **Inter** | Best UI font for web and design work |
| **Hack Nerd Font** | Clean monospace font with icons |

---

## Quick Look Plugins

Preview files in Finder by pressing spacebar.

| Plugin | Description |
|--------|-------------|
| **QLMarkdown** | Preview Markdown files with rendered formatting |
| **QLStephen** | Preview plain text files that have no file extension |

---

## Mac Apps -- System & Utilities

| App | Description |
|-----|-------------|
| **Pearcleaner** | Open-source deep app uninstaller -- finds leftover files and preferences |
| **UniFi Identity Endpoint** | Wi-Fi, VPN, and device management for UniFi NAS |
| **LuLu** | Free open-source outbound firewall -- see what phones home |
| **Mullvad VPN** | Privacy-focused VPN -- no account required, anonymous payment accepted |

---

## Mac Apps -- Productivity

| App | Description |
|-----|-------------|
| **Notion** | All-in-one workspace -- docs, wikis, databases, project tracking |
| **Notion Calendar** | Calendar app with Notion integration |
| **Notion Mail** | Email client with Notion integration |
| **Snagit** | Screenshots, scrolling capture, annotations, and video recording |
| **Claude** | AI assistant |
| **Skim** | Lightweight PDF reader with annotations -- faster than Preview |
| **Transmit** | Premium SFTP/S3 file transfer client -- fast, dual-pane |

---

## Mac Apps -- Communication

| App | Description |
|-----|-------------|
| **Slack** | Team messaging and collaboration |
| **Telegram** | Encrypted messaging with channels and bots |

---

## Mac Apps -- Browsers

| App | Description |
|-----|-------------|
| **Google Chrome** | Primary Chromium browser for development and DevTools |
| **Firefox** | Privacy-focused browser for cross-browser testing |
| **Brave** | Privacy-focused Chromium browser with built-in ad blocking |

---

## Mac Apps -- Media

| App | Description |
|-----|-------------|
| **mpv** | Terminal video player -- keyboard-driven, scriptable |
| **oxipng** | Lossless PNG compression -- CLI, scriptable, CI-friendly |
| **jpegoptim** | Lossless JPEG compression -- strip metadata, optimize |
| **p7zip** | Archive tool -- zip, 7z, rar, tar from the command line |
| **LibreOffice** | Free office suite -- documents, spreadsheets, presentations |

---

## Mac Apps -- Cloud Storage & Backup

| App | Description |
|-----|-------------|
| **Google Drive** | Cloud storage with Docs, Sheets, and Slides integration |
| **rclone** | Sync files to any cloud -- Google Drive, S3, Dropbox, etc. |
| **borg** | Deduplicated encrypted backups -- better than Time Machine for offsite |
| **borgmatic** | Automated borg backup scheduling and configuration |

---

## Mac Apps -- Focus & Learning

| App | Description |
|-----|-------------|
| **newsboat** | Terminal RSS/Atom reader -- vim-like keybindings, highly configurable |

---

---

## Remove Pre-installed Apple Bloat

The `mac-bloat` category removes unused Apple apps (requires sudo, some need SIP disabled):

| App | Location |
|-----|----------|
| **GarageBand** | `/Applications/GarageBand.app` |
| **News** | `/System/Applications/News.app` |
| **Journal** | `/System/Applications/Journal.app` |
| **Chess** | `/System/Applications/Chess.app` |
| **Games** | `/System/Applications/Games.app` |
| **Stocks** | `/System/Applications/Stocks.app` |
| **Tips** | `/System/Applications/Tips.app` |
| **Voice Memos** | `/System/Applications/VoiceMemos.app` |

```bash
# Remove bloat only
./scripts/setup-dev-tools-mac.sh --only mac-bloat

# Skip bloat removal in a full run
./scripts/setup-dev-tools-mac.sh --skip mac-bloat
```

> **Note:** `/System/Applications` apps require SIP disabled on macOS Sonoma+. Boot into Recovery (Cmd+R) > Terminal > `csrutil disable` > reboot. Re-enable after: `csrutil enable`.

---

## Dracula Theme

Applied consistently across all tools:

| Tool | How |
|------|-----|
| **VS Code** | Extension auto-installed, set as default theme |
| **Zed** | Dracula theme set in settings.json |
| **bat** | Dracula syntax theme in config |
| **delta** | Dracula syntax theme for git diffs |
| **Ghostty** | Full 16-color Dracula palette in config |
| **fzf** | Dracula colors in `FZF_DEFAULT_OPTS` |
| **Starship** | Dracula color palette in `starship.toml` |
| **lazygit** | Full Dracula color scheme in config |
| **k9s** | Dracula skin with all view colors |
| **glow** | Dracula Markdown rendering style |
| **gh-dash** | Dracula border and highlight colors |
| **yazi** | Dracula file type colors and borders |
| **btop** | Full Dracula theme with custom color palette |
| **lazydocker** | Dracula borders and options colors |
| **vivid** | Dracula-themed LS_COLORS for file type coloring |
| **vim** | Dracula-ish color scheme (no plugin needed) |
| **VS Code brackets** | Dracula-colored bracket pair colorization |
| **macOS** | System highlight color set to Dracula purple |

---

## Claude Code Configuration

The script sets up Claude Code with a comprehensive configuration for full-stack development.

### Files Created

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Global permissions (110 entries), file ignore patterns, env vars |
| `~/.claude/CLAUDE.md` | Global memory -- coding standards, available CLI tools reference, React/Next.js/AWS/CDK/Python/IaC conventions, security checks runbook |
| `~/.claude/rules/workflow.md` | Trunk-based workflow rules (PR-first, issues, README-driven) |
| `~/.claude/rules/git.md` | Git rules (no force-push, conventional commits, branch naming) |
| `~/.claude/rules/security.md` | Security rules (no hardcoded secrets, parameterized SQL) |
| `~/.claude/rules/typescript.md` | TypeScript rules (strict mode, no any, zod schemas) |
| `~/.claude/rules/python.md` | Python rules (uv for packages, ruff for linting, type hints, pydantic) |
| `~/.claude/rules/docker.md` | Docker rules (multi-stage builds, non-root, hadolint, dive) |
| `~/.claude/rules/iac.md` | IaC rules (remote state, tflint, infracost, trivy config scan) |
| `~/.claude/hooks/format-on-edit.sh` | Auto-format with Prettier after Claude edits JS/TS/CSS/JSON/MD files |
| `~/.claude/hooks/format-on-edit.ps1` | Auto-format hook (PowerShell version for Windows) |
| `~/.claude/hooks/lint-python.sh` | Auto-lint and fix Python files with ruff after Claude edits them |
| `~/.claude/hooks/lint-dockerfile.sh` | Lint Dockerfiles with hadolint after Claude edits them |

### Custom Slash Commands

| Command | Purpose |
|---------|---------|
| `/pr-review` | Review current branch changes vs main -- flags security, bugs, edge cases |
| `/test-plan` | Generate a test plan with unit/integration/e2e cases for recent changes |
| `/dep-audit` | Audit dependencies for vulnerabilities, outdated packages, bundle size |
| `/quick-doc` | Generate JSDoc/docstring documentation for a file or function |
| `/cleanup` | Find dead code, unused imports, debug statements, empty catches |
| `/security-scan` | Run all security tools (gitleaks, npm audit, semgrep, trivy) and report findings |
| `/perf-check` | Benchmark with hyperfine, load test with oha, check for performance anti-patterns |
| `/docker-lint` | Lint Dockerfiles with hadolint, analyze layers with dive, check docker-compose best practices |
| `/iac-review` | Run tflint, trivy config scan, infracost estimate, check for IaC best practices |
| `/convert` | Convert between formats using pandoc, d2, mermaid, ffmpeg, or imagemagick |
| `/new-feature` | Full trunk-based workflow: create issue, branch, implement with tests, PR |
| `/fix-bug` | Full trunk-based workflow: create issue, branch, test-first fix, PR |
| `/create-readme` | Analyze codebase and generate comprehensive README.md |
| `/init-project` | Scaffold new project with git, README, CLAUDE.md, linting, CI, Docker, templates |
| `/refactor` | Refactor code with tests preserved, SOLID principles, verify tests pass |
| `/add-endpoint` | Add full API endpoint: types, handler, validation, tests, docs |
| `/add-component` | Add React component: TSX, tests, props interface, accessibility |
| `/ci-fix` | Diagnose CI failures with `gh run view`, fix, verify locally with `act` |
| `/changelog` | Generate changelog from conventional commits grouped by type |
| `/commit-msg` | Analyze staged changes and generate conventional commit message |

### Permissions Pre-approved

Common safe commands are pre-approved so Claude doesn't ask every time:
- **Package managers**: npm, pnpm, bun, npx, uv, cargo, pip
- **Git**: all git and gh commands
- **AWS & IaC**: aws, cdk, sam, tofu, tflint, infracost
- **Docker & K8s**: docker, docker-compose, kubectl, k9s, stern
- **Build tools**: make, just, tsc, jest, vitest
- **File tools**: cat, bat, ls, eza, find, grep, rg, fd, fzf, tree, jq, yq, fx, mlr, csvlook
- **Linters**: eslint, prettier, shellcheck, shfmt, ruff, hadolint, typos, ast-grep, commitizen, commitlint
- **Security**: trivy, semgrep, gitleaks, snyk, cosign
- **Media & docs**: pandoc, d2, mmdc, ffmpeg, magick
- **Database**: pgcli, mycli, lazysql, sq, dbmate
- **Other**: lazygit, lazydocker, dive, hyperfine, oha, tokei, dust, difft, delta

### Denied Commands

Destructive commands are blocked:
- `rm -rf /`, `rm -rf ~`, `sudo rm`, `chmod 777`, `mkfs`, `> /dev/sda*`

---

## Filesystem Structure

The scripts create an organized directory layout for both development and personal use:

```
~/
|-- Code/                        # -- Development --
|   |-- work/                    # Work projects
|   |   |-- <org-name>/          # Grouped by GitHub org
|   |   +-- scratch/             # Throwaway experiments
|   |-- personal/                # Personal projects
|   |   +-- scratch/
|   |-- oss/                     # Open source contributions
|   +-- learning/
|       |-- courses/
|       +-- playground/
|
|-- Scripts/                     # -- Automation --
|   |-- bin/                     # Custom scripts (added to PATH)
|   +-- cron/                    # Cron job scripts
|
|-- Screenshots/                 # Screenshots save here
|
|-- Documents/                   # -- Life Admin --
|   |-- finance/
|   |   |-- taxes/               # Tax returns, W-2s, 1099s
|   |   |-- invoices/            # Sent/received invoices
|   |   +-- statements/          # Bank/credit card statements
|   |-- health/                  # Medical records, insurance cards
|   |-- legal/                   # Contracts, agreements, legal docs
|   |-- travel/                  # Itineraries, bookings, visa docs
|   |-- insurance/               # Policies, claims
|   |-- contracts/               # Work/freelance contracts
|   |-- receipts/                # Purchase receipts, warranties
|   +-- design/                  # Design files, mockups
|
|-- Reference/                   # -- Quick-Access Knowledge --
|   |-- manuals/                 # Product/software manuals
|   |-- cheatsheets/             # CLI, language, tool cheatsheets
|   +-- bookmarks-export/        # Exported browser bookmarks
|
|-- Creative/                    # -- Creative Work --
|   |-- design/                  # Graphic design projects
|   |-- writing/                 # Blog posts, drafts, notes
|   |-- video-editing/           # Video projects, raw footage
|   +-- assets/
|       |-- icons/               # Icon collections
|       |-- fonts/               # Custom/downloaded fonts
|       |-- stock-photos/        # Stock imagery
|       +-- templates/           # Document/design templates
|
|-- Media/                       # -- Personal Media --
|   |-- photos/                  # Personal photos
|   |-- videos/                  # Personal videos
|   |-- music/                   # Music files
|   +-- wallpapers/              # Desktop/phone wallpapers
|
|-- Projects/                    # -- Non-Code Projects --
|   |-- side-hustles/            # Business/freelance projects
|   +-- home/                    # Home improvement, DIY
|
+-- Archive/                     # -- Cold Storage --
    |-- old-projects/            # Completed/abandoned projects
    +-- old-docs/                # Old documents for reference
```

### Helper Scripts (~/Scripts/bin/)

| Script | Alias | Description |
|--------|-------|-------------|
| `new-project` | `nproj` | Scaffold a new project with git, .editorconfig, .gitignore |
| `clone-work` | `cwork` | Clone a work repo into `~/Code/work/<org>/<repo>` |
| `clone-personal` | `cpers` | Clone a personal repo into `~/Code/personal/<repo>` |
| `clean-downloads` | `cleandl` | Delete files in ~/Downloads older than 30 days (interactive) |
| `backup-dotfiles` | `dotback` | Push dotfile changes via chezmoi |
| `project-stats` | `pstats` | Show repo counts, disk usage, recently modified projects |
| `health-check` | `hc` | Quick system health overview (disk, memory, battery, brew, Docker, node_modules) |
| `setup-ssh` | `sshsetup` | Generate an Ed25519 SSH key and optionally add it to GitHub via gh CLI |
| `export-brewfile` | `brewsnap` | Export a Brewfile snapshot with descriptions for reproducibility |

### Global Justfile (~/.justfile)

27 task-runner recipes available from any directory via `gj`:

| Recipe | Description |
|--------|-------------|
| `gj default` | List all available recipes |
| `gj update` | Update everything via topgrade |
| `gj info` | Show system info via fastfetch |
| `gj flush-dns` | Flush DNS cache |
| `gj ports` | Show listening ports |
| `gj rebase` | Interactive rebase last N commits |
| `gj undo` | Undo last commit (keep changes staged) |
| `gj branches` | Show recent branches by last commit |
| `gj docker-clean` | Clean unused Docker images, containers, volumes |
| `gj docker-usage` | Show Docker disk usage |
| `gj serve` | Serve current directory on a port |
| `gj uuid` | Generate a UUID |
| `gj b64-encode` | Encode text to base64 |
| `gj b64-decode` | Decode base64 text |
| `gj ip` | Show public IP address |
| `gj local-ip` | Show local IP address |
| `gj kill-port` | Kill process on a specific port |
| `gj status` | Quick HTTP status check for a URL |
| `gj node-clean` | Find all node_modules under ~/Code with sizes |
| `gj docker-nuke` | Nuclear Docker cleanup (remove everything) |
| `gj ds-clean` | Remove .DS_Store files recursively |
| `gj cheat` | Show a cheatsheet for a command (via tldr) |
| `gj timestamp` | Generate an ISO timestamp |
| `gj weather` | Show weather for a city (via wttr.in) |
| `gj standup` | Git standup -- what did I do yesterday? |
| `gj loc` | Count lines of code in current directory (via tokei) |

### Directory Shortcut Aliases

| Alias | Directory |
|-------|-----------|
| `cw` | `~/Code/work` |
| `cper` | `~/Code/personal` |
| `coss` | `~/Code/oss` |
| `clearn` | `~/Code/learning` |
| `cscratch` | `~/Code/work/scratch` |
| `cscripts` | `~/Scripts` |

### Per-Directory Git Identity

Automatically uses different git identities for work vs personal:

```
~/Code/work/     -> uses ~/.gitconfig-work     (work email)
~/Code/personal/ -> uses ~/.gitconfig-personal  (personal email)
```

Edit these files after running the script to fill in your details.

---

## Configurations Created

The script generates config files with sensible defaults:

| File | Tool | Highlights |
|------|------|------------|
| `~/.zshrc` | Shell | Auto-written managed block with all init scripts, aliases, welcome screen |
| `~/.zprofile` | Shell | Login shell PATH, editor, pager, LESS, XDG dirs, ulimit increase for Node.js |
| `~/.gitconfig` | git | Rebase pull, histogram diff, 30 aliases (st, co, lg, wip, cleanup, gone, standup, recent, worktree, stash-all, etc.), delta, rerere, auto-stash |
| `~/.gitignore_global` | git | .DS_Store, .env, node_modules, editor files, secrets |
| `~/.gitmessage` | git | Commit template with type/scope format |
| `~/.gnupg/gpg-agent.conf` | GPG | pinentry-mac, 8-hour passphrase cache |
| `~/.ssh/config` | SSH | Multiplexing, keychain, keep-alive, strong algorithms |
| `~/.npmrc` | npm | save-exact, no telemetry, prefer-offline, engine-strict |
| `~/.editorconfig` | EditorConfig | UTF-8, LF, 2-space indent, per-language overrides (Python 4-space, Go tabs) |
| `~/.prettierrc` | Prettier | Single quotes, trailing commas, 100 width |
| `~/.curlrc` | curl | Follow redirects, retry 3x, compression, timeouts |
| `~/.docker/daemon.json` | Docker | BuildKit enabled, log rotation 10m x 3, DNS, garbage collection |
| `~/.aria2/aria2.conf` | aria2 | 16 connections, auto-resume, BitTorrent, 64MB cache |
| `~/.config/atuin/config.toml` | atuin | Fuzzy search, local-only, compact style, enter=paste (not execute), history filter (ls/cd/clear/exit), secrets filter |
| `~/.config/starship.toml` | Starship | Rich two-line prompt with Dracula palette, OS icon, git status with counts, Node/Python/Rust/Go/Docker/AWS/Terraform versions, battery warning, time, Nerd Font icons |
| `~/.config/glow/glow.yml` | glow | Dracula style, mouse, pager |
| `~/.config/yt-dlp/config` | yt-dlp | Best quality mp4, aria2c downloader, metadata, subtitles |
| `~/.config/gh-dash/config.yml` | gh-dash | PR/issue sections, Dracula theme |
| `~/.config/stern/config.yaml` | stern | 50 tail lines, 5m lookback, timestamps |
| `~/.config/ngrok/ngrok.yml` | ngrok | Base config (add authtoken) |
| `~/.config/caddy/Caddyfile` | Caddy | Development server template |
| `~/.config/asciinema/config` | asciinema | 2s idle limit, no keystroke recording |
| `~/.config/yazi/yazi.toml` | yazi | Hidden files, VS Code opener, Dracula theme |
| `~/.config/zellij/config.kdl` | zellij | Dracula theme, compact layout, mouse, Ctrl-a prefix |
| `~/.config/mpv/mpv.conf` | mpv | Hardware accel, save position, screenshots to ~/Screenshots |
| `~/.config/git-cliff/cliff.toml` | git-cliff | Conventional commits changelog template |
| `~/.newsboat/config` | newsboat | Vim keys, Dracula colors, auto-reload |
| `~/.newsboat/urls` | newsboat | Starter RSS feeds (Claude Code, Node, Rust, GitHub) |
| `~/Library/Application Support/nushell/env.nu` | nushell | Starship prompt, Homebrew paths |
| `~/.config/ghostty/config` | Ghostty | JetBrains Mono, Dracula palette, transparent titlebar |
| `~/.config/zed/settings.json` | Zed | Dracula theme, JetBrains Mono, format on save, relative line numbers, inline blame, no telemetry |
| `~/.config/fastfetch/config.jsonc` | fastfetch | Nerd Font icons, package counts, Node/Python/Go/Rust/Docker versions, battery, disk, colored output |
| `~/.config/mise/config.toml` | mise | Auto-install, trust ~/Code |
| `~/.config/topgrade.toml` | topgrade | Cleanup, greedy cask updates |
| `~/.config/direnv/direnv.toml` | direnv | Hidden env diff, auto-trust ~/Code, load .env |
| `~/.config/btop/` | btop | Dracula theme with full color palette |
| `~/.config/lazydocker/` | lazydocker | Dracula theme, timestamps, compose support |
| `~/.config/pip/pip.conf` | pip | Require virtualenv, no telemetry |
| `~/.config/pgcli/config` | pgcli | Multi-line, auto-expand, destructive warnings, bat pager |
| `~/.config/gh/config.yml` | GitHub CLI | SSH protocol, VS Code editor, delta pager, aliases (co, pv, pc, pl, il, pm, rel) |
| `~/.aws/config` | AWS CLI | Default region, json output, bat pager, auto-prompt, SSO template |
| `~/.config/git/hooks/` | git | Global pre-commit hooks (debug statements, large files >5MB, conflict markers) |
| `~/.config/brewfile/Brewfile` | Homebrew | Snapshot of all installed packages with descriptions |
| `~/.justfile` | just | 27 global task-runner recipes (system, git, Docker, network, cleanup, info) |
| `~/.shellcheckrc` | shellcheck | External sources, disabled false positives |
| `~/.actrc` | act | Medium Ubuntu images, container reuse |
| `~/.mlrrc` | miller | CSV input, pretty table output |
| `~/.hushlogin` | Terminal | Suppresses "Last login" message |
| `~/.ripgreprc` | ripgrep | Smart case, hidden files, ignore patterns, custom types (web, config, doc, style) |
| `~/.fdignore` | fd | Global ignore patterns (node_modules, .git, dist, etc.) |
| `~/.vimrc` | vim | Line numbers, clipboard, mouse, Dracula colors, space leader, persistent undo |
| `~/.nanorc` | nano | Line numbers, auto-indent, mouse, syntax highlighting |
| `~/.myclirc` | mycli | Multi-line, auto-expand, destructive warnings |
| `~/.gemrc` | Ruby | No docs on gem install |
| `~/Library/.../Code/User/settings.json` | VS Code | Dracula, JetBrains Mono, format on save, 27 extensions, file nesting, bracket pair colorization, per-language formatters (ruff for Python, go for Go, rust-analyzer for Rust) |
| `~/Library/.../Code/User/keybindings.json` | VS Code | Custom keyboard shortcuts |
| `~/Library/.../lazygit/config.yml` | lazygit | Dracula theme, delta pager, nerd fonts, auto-fetch, VS Code editor, rounded borders |
| `~/Library/.../k9s/skins/dracula.yaml` | k9s | Full Dracula skin |

---

## macOS System Defaults

| Category | Changes |
|----------|---------|
| **Dock** | Auto-hide, small icons (40px), no recents, scale minimize, no delay, spacers, all default pins cleared |
| **Wallpaper** | Auto-set from `assets/wolf-wallpaper.jpg` to all desktops |
| **Screensaver** | 45min idle, display sleep at 2hr (charger) / 1h15m (battery) |
| **Screenshots** | PNG format, saved to `~/Screenshots`, no shadow, no thumbnail |
| **Keyboard** | Fast key repeat (2/15), no press-and-hold, no auto-correct/capitalize/smart quotes/dashes/periods |
| **Trackpad** | Faster tracking speed (2.0) |
| **Mission Control** | Fixed spaces (no auto-rearrange), fast animations, group by app |
| **Hot Corners** | Top-left: Mission Control, Top-right: Desktop |
| **Stage Manager** | Disabled (prevents accidental activation) |
| **Safari** | Developer menu enabled, full URL in address bar |
| **TextEdit** | Plain text default, UTF-8 encoding |
| **Finder** | Hidden files visible, path bar, status bar, list view, folders first, no .DS_Store on network/USB, full POSIX path in title bar |
| **Finder sidebar** | Configured via LSSharedFileList API (Code, Screenshots, Scripts, Documents, Reference, Creative, Media, Projects, Archive, Downloads) |
| **Animations** | Reduced motion, fast window resize |
| **Misc** | No quarantine dialog, battery %, Dracula purple highlight, expanded save/print panels |
| **Touch ID** | Enabled for sudo -- use fingerprint instead of password in terminal |
| **DNS** | Set to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) + Google (8.8.8.8) |
| **Spotlight** | Excluded ~/Code, ~/.config, node_modules, caches, Homebrew directories from indexing |
| **Time Machine** | Excluded node_modules, Docker, caches, Downloads from backups |
| **Siri** | Disabled and removed from menubar |

---

## Shell Aliases

All aliases are auto-written to `~/.zshrc`:

| Alias | Command | Purpose |
|-------|---------|---------|
| `ls` | `eza --icons` | File listing with icons |
| `ll` | `eza -la --icons --git` | Long list with git status |
| `la` | `eza -a --icons` | List all including hidden |
| `lt` | `eza --tree --icons --level=3` | Tree view |
| `cat` | `bat --paging=never` | Syntax-highlighted file viewer |
| `top` | `btop` | System monitor |
| `du` | `dust` | Disk usage |
| `df` | `duf` | Disk free |
| `ps` | `procs` | Process list |
| `ping` | `gping` | Latency graph |
| `dig` | `doggo` | DNS lookup |
| `watch` | `viddy` | Watch command output |
| `hexdump` | `hexyl` | Hex viewer |
| `rm` | `trash` | Safe delete (Trash) |
| `make` | `just` | Task runner |
| `y` | `yazi` | File manager |
| `jx` | `fx` | Interactive JSON viewer |
| `f` | `fd` | Fast find |
| `dft` | `difft` | Syntax-aware diff |
| `dl` | `aria2c` | Fast download |
| `wget` | `aria2c` | Fast download |
| `pip` | `uv pip` | Fast Python packages |
| `venv` | `uv venv` | Fast virtualenv creation |
| `pyrun` | `uv run` | Run Python with uv |
| `gj` | `just --justfile ~/.justfile` | Global justfile recipes |
| `lg` | `lazygit` | Git UI |
| `lzd` | `lazydocker` | Docker UI |
| `k` | `kubectl` | Kubernetes |
| `klog` | `stern` | K8s pod logs |
| `md` | `glow` | Markdown viewer |
| `serve` | `miniserve ...` | Quick file server |
| `ghd` | `gh dash` | GitHub dashboard |
| `gdft` | `git dft` | Syntax-aware git diff |
| `gha` | `act` | Run GitHub Actions locally |
| `ytdl` | `yt-dlp` | Download video |
| `ytmp3` | `yt-dlp -x --audio-format mp3` | Download audio |
| `bench` | `hyperfine` | Benchmark commands |
| `loadtest` | `oha` | HTTP load test |
| `md2pdf` | `pandoc -f markdown -t pdf` | Markdown to PDF |
| `md2html` | `pandoc -f markdown -t html -s` | Markdown to HTML |
| `md2docx` | `pandoc -f markdown -t docx` | Markdown to Word |
| `resize` | `magick mogrify -resize` | Resize images |
| `ffq` | `ffmpeg -hide_banner ...` | Quiet ffmpeg |
| `par` | `parallel` | Run in parallel |
| `lint-sh` | `shellcheck` | Lint shell scripts |
| `fmt-sh` | `shfmt -w -i 4` | Format shell scripts |
| `csvp` | `csvlook` | Pretty-print CSV |
| `watchrun` | `watchexec` | Watch and rerun on changes |
| `update` | `topgrade` | Update everything |
| `sysinfo` | `fastfetch` | Quick system info |
| `nproj` | `new-project` | Scaffold new project |
| `cwork` | `clone-work` | Clone work repo |
| `cpers` | `clone-personal` | Clone personal repo |
| `dotback` | `backup-dotfiles` | Backup dotfiles via chezmoi |
| `pstats` | `project-stats` | Show project stats |
| `cleandl` | `clean-downloads` | Clean old downloads |
| `hc` | `health-check` | System health overview |
| `sshsetup` | `setup-ssh` | Generate SSH key + add to GitHub |
| `brewsnap` | `export-brewfile` | Export Brewfile snapshot |

### Shell Extras

| Feature | Description |
|---------|-------------|
| **Zsh completions** | kubectl, gh, aws auto-completions loaded |
| **GPG_TTY** | Set in zshrc for commit signing to work |
| **ulimit increase** | `ulimit -n 65536` in zprofile for Node.js/webpack/vite |
| **vivid LS_COLORS** | Dracula-themed file type coloring via `vivid generate dracula` |
| **fzf config** | Dracula colors, fd for file finding, bat for preview, eza tree for directory preview, keybindings (ctrl-/ toggle preview, ctrl-y copy) |
| **Plugin guards** | Zsh plugin sources have defensive `[[ -f ]]` guards |
| **Terminal welcome** | fastfetch + date + random dev tip on new terminal sessions (not in VS Code) |

---

## VS Code Extensions

27 extensions auto-installed by the script:

| Extension | Purpose |
|-----------|---------|
| **Dracula Official** | Color theme |
| **Prettier** | Code formatter (default for JS/TS/CSS/JSON/MD) |
| **ESLint** | JavaScript/TypeScript linter |
| **Tailwind CSS IntelliSense** | Tailwind class autocomplete |
| **Python** | Python language support |
| **Go** | Go language support (also used as formatter for Go files) |
| **rust-analyzer** | Rust language support (also used as formatter for Rust files) |
| **Auto Rename Tag** | Rename paired HTML/JSX tags |
| **Path Intellisense** | Autocomplete file paths |
| **Error Lens** | Inline error/warning highlights |
| **Better Comments** | Colorized comment annotations (TODO, FIXME, etc.) |
| **Code Spell Checker** | Spell checking for code and comments |
| **npm Intellisense** | Autocomplete npm module imports |
| **Color Highlight** | Highlight color codes in the editor |
| **Rainbow CSV** | Colorize CSV columns for readability |
| **GitLens** | Git blame, history, and annotations |
| **Git Graph** | Visual git history graph |
| **GitHub Copilot** | AI code completion |
| **Todo Tree** | Find and highlight TODO/FIXME comments across the project |
| **Import Cost** | Show size of imported JS/TS packages inline |
| **Docker** | Dockerfile and docker-compose support |
| **DotENV** | .env file syntax highlighting |
| **Markdown All in One** | Markdown shortcuts, preview, table of contents |
| **YAML** | YAML language support with validation |
| **Even Better TOML** | TOML language support |
| **Ruff** | Python linter/formatter (set as default formatter for Python files) |

### VS Code Settings Highlights

- File nesting enabled (test files, lockfiles, config files grouped under parent)
- Bracket pair colorization with Dracula colors
- Per-language formatters: Ruff for Python, Go extension for Go, rust-analyzer for Rust
- Sticky scroll (3 lines max)
- Inlay hints on unless pressed
- Terminal uses JetBrains Mono NF

---

## Chrome Extensions (manual install)

| Extension | Purpose |
|-----------|---------|
| **axe DevTools** | Accessibility testing |
| **React Developer Tools** | React component inspection |
| **Lighthouse** | Performance and accessibility audits |
| **JSON Formatter** | Pretty-print JSON in the browser |

---

## Raycast Extensions (manual install via Raycast Store)

| Extension | Purpose |
|-----------|---------|
| **Clipboard History** | Built-in clipboard manager with search |
| **GitHub** | Search repos, PRs, and issues from Raycast |
| **AWS** | Quick access to AWS console services |
| **Docker** | Manage containers from Raycast |
| **Notion** | Search Notion pages and databases |
| **Brew** | Search and install Homebrew packages |
| **Kill Process** | Fast process killer |
| **Color Picker** | System-wide color picker |

---

## Restoring on a New Machine

```bash
# Option 1: Run the full script
./scripts/setup-dev-tools-mac.sh

# Option 2: Resume after a failure
./scripts/setup-dev-tools-mac.sh --resume

# Option 3: Restore from Brewfile (packages only, no configs)
brew bundle install --file=~/.config/brewfile/Brewfile

# Option 4: Restore dotfiles via chezmoi
chezmoi init <your-github-username> && chezmoi apply

# Option 5: Run only specific categories
./scripts/setup-dev-tools-mac.sh --only core,git,dx,configs
```

---

## Updating

```bash
# Update everything at once (via topgrade)
topgrade

# Or update manually
brew update && brew upgrade && brew cleanup

# Re-run this script to pick up new tools/configs
./scripts/setup-dev-tools-mac.sh
```

The script will:
- Skip already-installed tools
- Update the `~/.zshrc` managed block
- Export a fresh Brewfile
- Apply any new macOS defaults
- Report what changed

---

## Uninstalling

```bash
# Show removal commands (no changes made)
./scripts/setup-dev-tools-mac.sh --uninstall
```

This prints a full guide for removing all installed tools, configs, and settings. Review each command before running.

---

---

# Windows Script (`setup-dev-tools-windows.ps1`)

## Overview

4,200+ lines of PowerShell. Uses **winget** for GUI/desktop apps and **Scoop** for CLI dev tools. Run as Administrator for registry edits.

## Platform-Specific Substitutions

| macOS App | Windows Equivalent |
|-----------|--------------------|
| Raycast | **PowerToys** (Run, Color Picker) |
| Ghostty | **Windows Terminal** (built-in) + **Alacritty** |
| mitmproxy | **mitmproxy** (same tool, cross-platform) |
| Skim | **SumatraPDF** |
| Pearcleaner | **BCUninstaller** |
| Transmit | **WinSCP** |
| LuLu (firewall) | **simplewall** |
| Quick Look plugins | **QuickLook** (winget) |
| watchexec (file watcher) | **watchexec** (same tool, cross-platform) |

All Claude Code changes apply to Windows: 110 permissions, 7 rules (workflow, git, security, typescript, python, docker, iac), 3 hooks (format-on-edit, lint-python, lint-dockerfile), 20 commands.

## Windows System Tweaks

Registry edits applied by the `windows-defaults` category:
- Fast keyboard repeat, no autocorrect
- Show hidden files and file extensions
- Small taskbar, disable web search in Start
- Disable Copilot, reduce animations
- DNS set to Cloudflare + Quad9 + Google

## Windows Bloat Removal (`win-bloat`)

Removes pre-installed Windows apps via `winget uninstall`:
Clipchamp, Xbox Game Bar, Bing News, Get Help, Tips, Mail, Weather, Maps, People, Solitaire, Mixed Reality Portal, Cortana, Feedback Hub, Power Automate, Teams (free)

## Shell: PowerShell Profile

Managed block in `$PROFILE` with:
- Starship, Atuin, Zoxide initialization
- PSReadLine (prediction, ListView, tab completion -- replaces zsh-autosuggestions)
- All aliases translated to PowerShell (`Set-Alias` + wrapper functions)
- Dracula fzf colors, environment variables

## Windows Terminal

Dracula color scheme and JetBrains Mono NF font auto-configured in Windows Terminal settings.

---

# Linux Script (`setup-dev-tools-linux.sh`)

## Overview

5,300+ lines of Bash. Auto-detects distro at runtime and supports:

| Distro Family | Package Manager | Examples |
|---------------|----------------|----------|
| **Debian/Ubuntu** | apt | Ubuntu, Debian, Pop!_OS, Linux Mint, Elementary |
| **Fedora/RHEL** | dnf | Fedora, RHEL, CentOS, Rocky, Alma |
| **Arch** | pacman | Arch, Manjaro, EndeavourOS |

Also uses **snap**, **flatpak**, **cargo**, and **Linuxbrew** as fallbacks.

## Platform-Specific Substitutions

| macOS App | Linux Equivalent |
|-----------|-----------------|
| Raycast | **ulauncher** |
| Ghostty | **Alacritty** + **kitty** |
| mitmproxy | **mitmproxy** (same tool, cross-platform) |
| dust/duf (disk analysis) | **ncdu** |
| Skim | **Evince** (usually pre-installed) |
| Transmit | **FileZilla** |
| Quick Look plugins | **GNOME Sushi** |
| newsboat (RSS) | **newsboat** (same tool, cross-platform) |
| OrbStack | **Docker Engine** (native, no VM overhead) |
| watchexec | **watchexec** (same tool, cross-platform) |

GUI apps installed via snap/flatpak where native packages are unavailable.

All Claude Code changes apply to Linux: 110 permissions, 7 rules, 3 hooks, 20 commands.

## External Repos Auto-Added

The script adds official repositories for tools not in default repos:
- Docker Engine (docker.com)
- GitHub CLI (cli.github.com)
- Brave Browser (brave.com)
- Google Chrome (google.com)
- VS Code (microsoft.com)
- Trivy (aquasecurity)

## Ubuntu/Debian Notes

Some tools have different binary names on Debian-based systems. The script creates symlinks automatically:
- `batcat` -> `bat`
- `fdfind` -> `fd`

Many Rust CLI tools not in apt are installed via `cargo install` as fallback (eza, zoxide, sd, procs, gping, xh, etc.).

## Linux System Tweaks (`linux-defaults`)

GNOME settings applied via `gsettings` (skipped if not GNOME):
- Fast keyboard repeat, reduced animations
- Show hidden files in Nautilus
- Dark theme (Adwaita-dark)
- Dock auto-hide and small icons
- Screenshots to `~/Screenshots`
- DNS via systemd-resolved (Cloudflare + Quad9 + Google)
- GTK bookmarks configured for file manager sidebar (Code, Scripts, Documents, etc.)

## Shell: zsh

Installs zsh and sets it as default shell. Managed block in `~/.zshrc` with:
- Same aliases as macOS (eza, bat, fd, etc.)
- Tool initialization (starship, atuin, zoxide, direnv, mise)
- Plugin paths auto-detected across distros
- `xclip` for clipboard operations (replaces `pbcopy`)

## Fonts

Downloaded from GitHub to `~/.local/share/fonts/` and cached with `fc-cache -fv`:
JetBrains Mono, JetBrains Mono NF, MesloLGS NF, Fira Code, Fira Code NF, Inter, Hack NF

---

# Cross-Platform Tool Coverage

## Identical Across All Three Scripts

These 150+ CLI tools and configs are installed on every platform:

**Dev tools:** git, gh, mise, node, python, go, rust, bun, uv, pnpm, jq, direnv, cmake, docker, mitmproxy

**Modern replacements:** eza, bat, fd, ripgrep, zoxide, btop, sd, dust, duf, procs, gping, xh, curlie, doggo, tokei, viddy, hexyl, aria2, difftastic, vivid, just, yazi, fx, jnv, tldr, trash

**Git:** delta, lazygit, git-absorb, git-cliff, git-lfs, pre-commit, gnupg

**AWS:** aws-cli, sam-cli, cdk, cfn-lint, granted

**IaC:** opentofu, tflint, infracost

**Security:** detect-secrets, gitleaks, trivy, semgrep, cosign, snyk, mkcert, ssh-audit, clamav, age, sops

**Data:** yq, miller, csvkit, pandoc, imagemagick, ffmpeg, yt-dlp

**Code quality:** shellcheck, shfmt, act, hadolint, ruff, typos, ast-grep, npkill, commitizen, commitlint, ni, hyperfine, oha, hurl

**Servers:** ngrok, miniserve, caddy

**Productivity:** glow, watchexec, pv, parallel, asciinema, gum, nushell, topgrade, fastfetch, lnav, starship, atuin, fzf, chezmoi

**K8s:** stern, kubectl, k9s, lazydocker, dive

**Database:** pgcli, mycli, lazysql, usql, sq, dbmate

**Editors:** VS Code, Zed

**JS tooling:** TypeScript, tsx, Turborepo, Lighthouse, Mermaid CLI

**Backup:** rclone, borg, borgmatic

## 60+ Shared Config Files

Identical content across all platforms (paths adjusted per OS):
starship, atuin, glow, btop, lazygit, lazydocker, k9s, yazi, gh-dash, stern, mise, fastfetch, direnv, caddy, ngrok, yt-dlp, asciinema, pgcli, zed, ghostty, .editorconfig, .prettierrc, .shellcheckrc, .curlrc, .npmrc, .ripgreprc, .fdignore, .vimrc, .nanorc, .gitignore_global, .gitmessage, .myclirc, .gemrc, .actrc, .mlrrc, .justfile, VS Code settings/keybindings/extensions, Docker, AWS CLI, GitHub CLI, pip, git global config, SSH config, Claude Code config (settings, CLAUDE.md, 6 rules, 3 hooks, 10 commands)

---

## Troubleshooting

### macOS
```bash
cat ~/.local/share/dev-setup/setup-*.log | grep ERROR
brew doctor
./scripts/setup-dev-tools-mac.sh --resume
```

### Windows (PowerShell)
```powershell
Get-Content $HOME\.local\share\dev-setup\setup-*.log | Select-String ERROR
scoop checkup
.\setup-dev-tools-windows.ps1 --resume
```

### Linux
```bash
cat ~/.local/share/dev-setup/setup-*.log | grep ERROR
./setup-dev-tools-linux.sh --resume
```

### All Platforms
```bash
# Preview without changes
./scripts/setup-dev-tools-mac.sh --dry-run

# Run only specific categories
./scripts/setup-dev-tools-mac.sh --only core,git,dx

# Show removal commands
./scripts/setup-dev-tools-mac.sh --uninstall
```

---

## License

MIT — see [LICENSE](LICENSE)
