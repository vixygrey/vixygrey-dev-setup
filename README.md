# macOS Development Environment Setup

A single idempotent script that installs and configures **191 tools** for development, GitHub, AWS/CDK, DX, UI/UX, security, and daily productivity on macOS. Safe to re-run — skips anything already installed.

## Quick Start

```bash
chmod +x setup-dev-tools.sh
./setup-dev-tools.sh
```

## CLI Options

```bash
./setup-dev-tools.sh --help              # Show all options
./setup-dev-tools.sh --dry-run           # Preview changes without installing
./setup-dev-tools.sh --list-categories   # List all available categories
./setup-dev-tools.sh --skip mac-media,mac-cloud  # Skip specific categories
./setup-dev-tools.sh --only core,git,aws,dx      # Only install specific categories
./setup-dev-tools.sh --version           # Show script version
```

## What It Does

1. **Pre-flight checks** — verifies macOS version, disk space, internet, admin privileges
2. Installs all tools via Homebrew, Cask, and npm with **progress tracking**
3. Configures every tool with sensible defaults
4. Applies the **Dracula** theme everywhere
5. Sets macOS system defaults (Dock, keyboard, Finder, screenshots, etc.)
6. Auto-writes `~/.zshrc` with a managed block (preserves your customizations)
7. Exports a `Brewfile` snapshot for reproducibility
8. **Post-install verification** — verifies critical tools work
9. Runs `brew cleanup` and `brew doctor`
10. **Logs everything** to `~/.local/share/dev-setup/` for debugging
11. Reports final summary with install/skip/fail counts and duration

## Features

| Feature | Description |
|---------|-------------|
| **Idempotent** | Safe to re-run — skips anything already installed |
| **Dry run** | Preview all changes with `--dry-run` |
| **Category filtering** | Install only what you need with `--only` / `--skip` |
| **Progress bar** | Visual progress counter (47/193) |
| **Error resilient** | Continues on failure, reports all failures at the end |
| **Logging** | Full log file for debugging failed installs |
| **Verification** | Post-install check that critical tools actually work |
| **Timing** | Shows total duration at the end |

---

## Prerequisites (auto-installed)

| Tool | Description |
|------|-------------|
| **Xcode CLI Tools** | Compilers, git, headers — required before everything else |
| **Rosetta 2** | Apple Silicon compatibility layer for x86 binaries |
| **Homebrew** | macOS package manager |
| **mas** | Mac App Store CLI — install App Store apps from the terminal |
| **coreutils** | GNU core utilities — Linux-compatible versions of standard tools |
| **gnu-sed** | GNU sed — consistent behavior with Linux scripts |
| **gnu-tar** | GNU tar — consistent behavior with Linux scripts |
| **gawk** | GNU awk — full-featured awk replacement |
| **findutils** | GNU find and xargs — Linux-compatible |

---

## Core Development

| Tool | Description |
|------|-------------|
| **nvm** | Node.js version manager — run multiple Node versions side by side |
| **Node.js LTS** | JavaScript runtime (latest Long Term Support version) |
| **pyenv** | Python version manager |
| **Python 3.12** | Python runtime |
| **pnpm** | Fast, disk-efficient npm alternative |
| **jq** | Lightweight command-line JSON processor |
| **httpie** | Human-friendly HTTP client for API testing |
| **direnv** | Per-directory environment variables (auto-loads `.envrc`) |
| **watchman** | File watching service (used by React Native, Jest, etc.) |
| **cmake** | Cross-platform build system generator |
| **pkg-config** | Helper tool for compiling libraries |
| **Docker Desktop** | Container runtime with GUI for managing images and containers |
| **OrbStack** | Faster Docker Desktop alternative — 2-5x less memory, native macOS feel |

---

## Git & GitHub

| Tool | Description |
|------|-------------|
| **git** | Distributed version control |
| **gh** | GitHub CLI — PRs, issues, Actions from the terminal |
| **delta** | Beautiful git diffs with syntax highlighting and side-by-side view |
| **git-lfs** | Git Large File Storage for binary assets |
| **gpg** | GNU Privacy Guard for commit signing and encryption |
| **pinentry-mac** | macOS keychain integration for GPG passphrases |
| **lazygit** | Terminal UI for git — visualize branches, stage hunks interactively |
| **git-absorb** | Auto-fixup commits — automatically amends the right commit |
| **pre-commit** | Git hook framework — run linters/formatters before each commit |

---

## AWS & CDK

| Tool | Description |
|------|-------------|
| **aws-cli v2** | Official AWS command-line interface |
| **aws-cdk** | AWS Cloud Development Kit — infrastructure as TypeScript/Python code |
| **cdk-nag** | CDK rule packs for security and best-practice compliance |
| **aws-sam-cli** | AWS Serverless Application Model — local Lambda testing |
| **cfn-lint** | CloudFormation template linter |
| **session-manager-plugin** | SSH-less access to EC2 instances via AWS SSM |
| **granted** | Fast multi-account AWS SSO credential switching |

---

## Security & Secrets

| Tool | Description |
|------|-------------|
| **git-secrets** | Prevents committing AWS keys and secrets to git |
| **trufflehog** | Scans git repos for leaked credentials and API keys |
| **detect-secrets** | Yelp's pre-commit hook for catching secrets before they're committed |
| **age** | Modern, simple file encryption (replaces GPG for file encryption) |
| **sops** | Encrypt secrets in YAML/JSON files — integrates with AWS KMS |
| **trivy** | Vulnerability scanner for containers, filesystems, and IaC |
| **semgrep** | Static analysis tool — finds bugs and security issues in code |
| **cosign** | Sign and verify container images and artifacts |
| **snyk** | Dependency vulnerability scanning for npm, pip, Go, etc. |
| **mkcert** | Create locally-trusted HTTPS certificates for development |
| **wireshark** | Network protocol analyzer — deep packet inspection GUI |
| **ssh-audit** | Audit SSH server and client configuration for security |
| **clamav** | Open-source antivirus engine — on-demand malware scanning |
| **BlockBlock** | Alerts when software installs persistent components (launch daemons) |
| **OverSight** | Alerts when microphone or camera is activated |
| **KnockKnock** | Shows all persistently installed software — spot malware |
| **ReiKey** | Detects keyboard event taps — catches keyloggers |

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
| `dig` | **dog** | Colorized DNS lookup with DoH/DoT support |
| `wc` (code) | **tokei** | Count lines of code by language with statistics |
| `watch` | **viddy** | Modern watch with diff highlighting and history |
| `hexdump` | **hexyl** | Colorized hex viewer with ASCII sidebar |
| `curl`/`wget` | **aria2** | Multi-connection parallel downloads, 3-10x faster, BitTorrent |
| `rm` | **trash** | Moves files to macOS Trash instead of permanent delete |
| `rsync` | **rsync** (latest) | Updated rsync with better progress and Apple metadata |
| `tree` | **tree** | Directory listing in tree format |

---

## Data & File Processing

| Tool | Description |
|------|-------------|
| **yq** | jq for YAML — parse and manipulate YAML files (essential for k8s/CDK) |
| **miller (mlr)** | awk/sed/jq for CSV, JSON, and tabular data |
| **csvkit** | Suite of CSV tools — csvcut, csvgrep, csvstat, csvlook |
| **pandoc** | Universal document converter — Markdown to PDF, DOCX, HTML, etc. |
| **imagemagick** | Image manipulation CLI — resize, convert, composite, watermark |
| **ffmpeg** | Video/audio processing swiss army knife |
| **yt-dlp** | Video/audio downloader for YouTube and hundreds of other sites |

---

## Code Quality

| Tool | Description |
|------|-------------|
| **shellcheck** | Shell script linter — catches bugs and bad practices |
| **shfmt** | Shell script formatter — consistent style for bash/zsh scripts |
| **act** | Run GitHub Actions locally before pushing |

---

## Performance & Load Testing

| Tool | Description |
|------|-------------|
| **hyperfine** | Command-line benchmarking tool — compare execution times |
| **oha** | HTTP load testing tool written in Rust — fast and simple |

---

## Dev Servers & Tunnels

| Tool | Description |
|------|-------------|
| **ngrok** | Expose localhost to the internet for webhooks and demos |
| **miniserve** | Instant file server from any directory — one command |
| **caddy** | Modern web server with automatic HTTPS |

---

## Terminal Productivity

| Tool | Description |
|------|-------------|
| **glow** | Render Markdown beautifully in the terminal |
| **entr** | Run commands when files change — lightweight file watcher |
| **pv** | Pipe viewer — add progress bars to any piped command |
| **parallel** | GNU parallel — run commands in parallel across multiple cores |
| **asciinema** | Record and share terminal sessions as text (not video) |

---

## Kubernetes & GitHub Extras

| Tool | Description |
|------|-------------|
| **stern** | Multi-pod log tailing for Kubernetes |
| **gh-dash** | GitHub dashboard in the terminal — PRs, issues, notifications |

---

## Database & Data

| Tool | Description |
|------|-------------|
| **pgcli** | Auto-completing PostgreSQL CLI with syntax highlighting |
| **mycli** | Auto-completing MySQL CLI with syntax highlighting |
| **usql** | Universal SQL CLI — connects to Postgres, MySQL, SQLite, and more |
| **dbmate** | Lightweight, framework-agnostic database migration tool |
| **TablePlus** | Native macOS database GUI — fast, clean, supports 20+ databases |
| **DBeaver** | Advanced SQL editor with 100+ database support (community edition) |

---

## Containers & Orchestration

| Tool | Description |
|------|-------------|
| **lazydocker** | Terminal UI for Docker — manage containers, images, volumes |
| **dive** | Explore Docker image layers — find what's taking up space |
| **kubectl** | Kubernetes CLI for managing clusters |
| **k9s** | Terminal UI for Kubernetes — navigate clusters with keyboard |

---

## API Development

| Tool | Description |
|------|-------------|
| **Bruno** | Open-source API client — Postman alternative, stores in git |
| **grpcurl** | curl for gRPC services |

---

## Networking & Debugging

| Tool | Description |
|------|-------------|
| **mtr** | Combines ping and traceroute into a single diagnostic tool |
| **bandwhich** | Real-time bandwidth usage by process, connection, and host |
| **nmap** | Network scanner — discover hosts and services |

---

## Developer Experience

| Tool | Description |
|------|-------------|
| **fzf** | Fuzzy finder — search files, history, branches interactively |
| **starship** | Cross-shell prompt with git status, language versions, and more |
| **zsh-autosuggestions** | Fish-like inline suggestions as you type |
| **zsh-syntax-highlighting** | Command coloring in the terminal — red for errors |
| **atuin** | Replaces shell history with SQLite-backed, fuzzy-searchable database |
| **mise** | Universal version manager — replaces nvm + pyenv + rbenv in one tool |
| **VS Code** | Primary code editor and IDE |
| **Cursor** | AI-native code editor — VS Code fork with built-in AI pair programming |
| **Claude Code** | AI-assisted coding in the terminal |
| **GitHub Copilot CLI** | AI suggestions in the terminal (via `gh copilot suggest`) |
| **chezmoi** | Dotfile manager — backup and restore configs across machines |
| **Proxyman** | Native macOS HTTP debugging proxy — inspect API calls from any app |
| **Warp** | Modern GPU-accelerated terminal with AI and block-based output |
| **iTerm2** | Classic macOS terminal with deep customization and tmux integration |
| **tmux** | Terminal multiplexer — persistent sessions, panes, and windows |
| **Raycast** | Spotlight replacement with extensions, snippets, and workflows |
| **Rectangle** | Window management with keyboard shortcuts |
| **TypeScript** | Typed JavaScript — installed globally for scripts and tooling |
| **tsx** | Run TypeScript files directly without a build step |
| **Turborepo** | High-performance monorepo build system |

---

## UI Development

| Tool | Description |
|------|-------------|
| **Storybook** | Component development environment — build and test UI in isolation |
| **Playwright** | End-to-end browser testing framework |
| **Google Chrome** | Primary Chromium browser for development and DevTools |

---

## UX & Design

| Tool | Description |
|------|-------------|
| **Figma** | Collaborative design and prototyping tool |
| **Lighthouse** | Web performance, accessibility, and SEO auditing CLI |

---

## Documentation & Diagrams

| Tool | Description |
|------|-------------|
| **d2** | Code-to-diagram scripting language — declarative diagrams as code |
| **Mermaid CLI** | Render Mermaid diagrams (flowcharts, sequences, ERDs) from CLI |

---

## Fonts

| Font | Description |
|------|-------------|
| **JetBrains Mono** | Primary development font with ligatures |
| **JetBrains Mono Nerd Font** | JetBrains Mono with patched icons for terminal tools |
| **MesloLGS Nerd Font** | Classic terminal font with icons for starship/eza |
| **Fira Code** | Popular ligature font — alternative to JetBrains Mono |
| **Fira Code Nerd Font** | Fira Code with patched icons |
| **Inter** | Best UI font for web and design work |
| **Hack Nerd Font** | Clean monospace font with icons |

---

## Quick Look Plugins

Preview files in Finder by pressing spacebar.

| Plugin | Description |
|--------|-------------|
| **QLMarkdown** | Preview Markdown files with rendered formatting |
| **Syntax Highlight** | Preview source code files with syntax coloring |
| **QLStephen** | Preview plain text files that have no file extension |
| **QuickLookJSON** | Preview JSON files with formatted, colorized output |

---

## Mac Apps — System & Utilities

| App | Description |
|-----|-------------|
| **AppCleaner** | Fully uninstall apps — removes leftover files and preferences |
| **The Unarchiver** | Opens any archive format — RAR, 7z, tar, etc. |
| **Stats** | Free menubar system monitor — CPU, RAM, network, disk, battery |
| **Bartender** | Organize and hide menubar icons |
| **Amphetamine** | Prevent Mac from sleeping during presentations or long tasks |
| **AltTab** | Windows-style alt-tab with window previews |
| **Dato** | Menubar clock with calendar, timezones, and meeting countdown |
| **Maccy** | Lightweight clipboard manager with search |
| **LuLu** | Free open-source outbound firewall — see what phones home |
| **Proton VPN** | Privacy-focused VPN |
| **Proton Mail** | End-to-end encrypted email client |
| **Proton Pass** | Password manager with end-to-end encryption |

---

## Mac Apps — Productivity

| App | Description |
|-----|-------------|
| **Notion** | All-in-one workspace — docs, wikis, databases, project tracking |
| **Notion Calendar** | Calendar app with Notion integration |
| **Notion Mail** | Email client with Notion integration |
| **CleanShot X** | Screenshot and recording tool with annotation, scrolling capture |
| **Shottr** | Free screenshot tool with pixel measuring, OCR, and color picker |
| **Numi** | Natural language calculator in a notepad ("$120 + 15% tax") |
| **Soulver 3** | Smart calculator/spreadsheet hybrid for back-of-napkin math |
| **Espanso** | Open-source text expander — snippets, date macros, code templates |
| **Hazel** | Automated file organization rules — move, rename, tag, archive |
| **PopClip** | Text actions on select — copy, search, translate, format |
| **Yoink** | Drag and drop shelf — stage files between apps |
| **Raindrop.io** | Bookmark manager with collections, tags, and full-text search |
| **Transmit** | Premium SFTP/S3 file transfer client — fast, dual-pane |
| **Cyberduck** | Free SFTP/S3 client with Cryptomator encryption and `duck` CLI |

---

## Mac Apps — Communication

| App | Description |
|-----|-------------|
| **Slack** | Team messaging and collaboration |
| **Discord** | Community chat — voice, video, and text |
| **Telegram** | Encrypted messaging with channels and bots |
| **Signal** | End-to-end encrypted messaging — privacy focused |

---

## Mac Apps — Browsers

| App | Description |
|-----|-------------|
| **Firefox** | Privacy-focused browser for cross-browser testing |
| **Arc** | Modern Chromium browser with spaces, tabs management, and split view |
| **Brave** | Privacy-focused Chromium browser with built-in ad blocking |

---

## Mac Apps — Media

| App | Description |
|-----|-------------|
| **IINA** | Modern native macOS video player — replaces VLC |
| **ImageOptim** | Lossless image compression — shrink PNGs, JPGs, GIFs |
| **Gifski** | Convert video clips to high-quality animated GIFs |
| **Keka** | File archiver and compressor |
| **LibreOffice** | Free office suite — documents, spreadsheets, presentations |
| **Pocket Casts** | Podcast player with cross-device sync |
| **Hand Mirror** | Quick webcam check from menubar before meetings |

---

## Mac Apps — Cloud Storage

| App | Description |
|-----|-------------|
| **Google Drive** | Cloud storage with Docs, Sheets, and Slides integration |

---

## Mac Apps — Focus & Learning

| App | Description |
|-----|-------------|
| **Flow** | Pomodoro timer that lives in the menubar |
| **Anki** | Spaced repetition flashcards — great for learning new tech |
| **Reeder** | RSS reader — follow blogs, release notes, changelogs |

---

## Mac Apps — Disk & File Utilities

| App | Description |
|-----|-------------|
| **DaisyDisk** | Visual disk space analyzer — find what's eating storage |

---

## Dracula Theme

Applied consistently across all tools:

| Tool | How |
|------|-----|
| **VS Code** | Extension auto-installed, set as default theme |
| **bat** | Dracula syntax theme in config |
| **delta** | Dracula syntax theme for git diffs |
| **iTerm2** | Theme downloaded to `~/.dracula-iterm` |
| **Warp** | Built-in (manual: Settings > Appearance > Dracula) |
| **fzf** | Dracula colors in `FZF_DEFAULT_OPTS` |
| **Starship** | Dracula color palette in `starship.toml` |
| **lazygit** | Full Dracula color scheme in config |
| **k9s** | Dracula skin with all view colors |
| **tmux** | Dracula status bar, pane borders, and colors |
| **glow** | Dracula Markdown rendering style |
| **gh-dash** | Dracula border and highlight colors |
| **macOS** | System highlight color set to Dracula purple |

---

## Claude Code Configuration

The script sets up Claude Code with sensible defaults for full-stack development.

### Files Created

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Global permissions, file ignore patterns, env vars |
| `~/.claude/CLAUDE.md` | Global memory — coding standards, React/Next.js/AWS/CDK conventions |
| `~/.claude/settings.local.json` | Local settings — MCP servers (Notion) |
| `~/.claude/rules/git.md` | Git workflow rules (no force-push, conventional commits) |
| `~/.claude/rules/security.md` | Security rules (no hardcoded secrets, parameterized SQL) |
| `~/.claude/rules/typescript.md` | TypeScript rules (strict mode, no any, zod schemas) |
| `~/.claude/hooks/format-on-edit.sh` | Auto-format with Prettier after Claude edits files |

### Permissions Pre-approved

Common safe commands are pre-approved so Claude doesn't ask every time:
- **Package managers**: npm, pnpm, bun, npx
- **Git**: all git and gh commands
- **AWS**: aws, cdk, sam
- **Docker**: docker, docker-compose, kubectl
- **Build tools**: make, tsc, jest, vitest, playwright
- **File tools**: cat, ls, find, grep, rg, fd, jq, yq, curl
- **Linters**: eslint, prettier, shellcheck, shfmt

### Denied Commands

Destructive commands are blocked:
- `rm -rf /`, `rm -rf ~`, `sudo rm`, `chmod 777`, `mkfs`

---

## Filesystem Structure

The script creates an organized directory layout:

```
~/
├── Code/
│   ├── work/                   # Work projects
│   │   ├── <org-name>/         # Grouped by GitHub org
│   │   └── scratch/            # Throwaway experiments
│   ├── personal/               # Personal projects
│   │   └── scratch/
│   ├── oss/                    # Open source contributions
│   └── learning/
│       ├── courses/
│       └── playground/
├── Documents/
│   ├── notion-templates/
│   ├── design/
│   ├── contracts/
│   └── receipts/
├── Screenshots/                # macOS screenshots save here
└── Scripts/
    ├── bin/                    # Custom scripts (added to PATH)
    └── cron/                   # Cron job scripts
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

### Directory Shortcut Aliases

| Alias | Directory |
|-------|-----------|
| `cw` | `~/Code/work` |
| `cp_` | `~/Code/personal` |
| `co` | `~/Code/oss` |
| `cl` | `~/Code/learning` |
| `cs` | `~/Code/work/scratch` |
| `sc` | `~/Scripts` |

### Per-Directory Git Identity

Automatically uses different git identities for work vs personal:

```
~/Code/work/     → uses ~/.gitconfig-work     (work email)
~/Code/personal/ → uses ~/.gitconfig-personal  (personal email)
```

Edit these files after running the script to fill in your details.

---

## Configurations Created

The script generates config files with sensible defaults:

| File | Tool | Highlights |
|------|------|------------|
| `~/.zshrc` | Shell | Auto-written managed block with all init scripts and aliases |
| `~/.tmux.conf` | tmux | Ctrl-a prefix, mouse, vim keys, Dracula status bar |
| `~/.gitconfig` | git | Rebase pull, histogram diff, aliases (st, co, lg, wip), delta |
| `~/.gitignore_global` | git | .DS_Store, .env, node_modules, editor files, secrets |
| `~/.gnupg/gpg-agent.conf` | GPG | pinentry-mac, 8-hour passphrase cache |
| `~/.ssh/config` | SSH | Multiplexing, keychain, keep-alive, strong algorithms |
| `~/.npmrc` | npm | save-exact, no telemetry, prefer-offline |
| `~/.editorconfig` | EditorConfig | UTF-8, LF, 2-space indent, per-language overrides |
| `~/.prettierrc` | Prettier | Single quotes, trailing commas, 100 width |
| `~/.curlrc` | curl | Follow redirects, retry 3x, compression, timeouts |
| `~/.docker/daemon.json` | Docker | BuildKit enabled, log rotation 10m x 3, DNS |
| `~/.aria2/aria2.conf` | aria2 | 16 connections, auto-resume, BitTorrent, 64MB cache |
| `~/.config/atuin/config.toml` | atuin | Fuzzy search, local-only, compact style |
| `~/.config/starship.toml` | Starship | Dracula palette, purple/red prompt |
| `~/.config/glow/glow.yml` | glow | Dracula style, mouse, pager |
| `~/.config/yt-dlp/config` | yt-dlp | Best quality mp4, aria2c downloader, metadata |
| `~/.config/gh-dash/config.yml` | gh-dash | PR/issue sections, Dracula theme |
| `~/.config/stern/config.yaml` | stern | 50 tail lines, 5m lookback, timestamps |
| `~/.config/ngrok/ngrok.yml` | ngrok | Base config (add authtoken) |
| `~/.config/caddy/Caddyfile` | Caddy | Development server template |
| `~/.config/asciinema/config` | asciinema | 2s idle limit, no keystroke recording |
| `~/.config/brewfile/Brewfile` | Homebrew | Snapshot of all installed packages |
| `~/.shellcheckrc` | shellcheck | External sources, disabled false positives |
| `~/.actrc` | act | Medium Ubuntu images, container reuse |
| `~/.mlrrc` | miller | CSV input, pretty table output |
| `~/.hushlogin` | Terminal | Suppresses "Last login" message |
| `~/.ripgreprc` | ripgrep | Smart case, hidden files, ignore patterns, custom types |
| `~/.fdignore` | fd | Global ignore patterns (node_modules, .git, dist, etc.) |
| `~/.gitmessage` | git | Commit template with type/scope format |
| `~/.config/git/hooks/` | git | Global pre-commit hooks (debug, large files, conflicts) |
| `~/.aws/config` | AWS CLI | Default region, json output, bat pager, auto-prompt, SSO template |
| `~/.config/gh/config.yml` | GitHub CLI | SSH protocol, VS Code editor, delta pager, aliases |
| `~/.config/pip/pip.conf` | pip | Require virtualenv, no telemetry |
| `~/.gemrc` | Ruby | No docs on gem install |
| `~/.config/pgcli/config` | pgcli | Multi-line, auto-expand, destructive warnings, bat pager |
| `~/.myclirc` | mycli | Multi-line, auto-expand, destructive warnings |
| `~/.config/direnv/direnv.toml` | direnv | Hidden env diff, auto-trust ~/Code |
| `~/.config/btop/` | btop | Dracula theme with full color palette |
| `~/.config/lazydocker/` | lazydocker | Dracula theme, timestamps, compose support |
| `~/Library/.../Code/keybindings` | VS Code | Custom keyboard shortcuts |
| `~/Library/.../espanso` | Espanso | Date macros, dev shortcuts, Markdown, git snippets |
| `~/Library/.../lazygit` | lazygit | Dracula theme, delta pager, nerd fonts |
| `~/Library/.../k9s` | k9s | Full Dracula skin |
| `~/Library/.../Code/User` | VS Code | Dracula, JetBrains Mono, format on save, extensions |

---

## macOS System Defaults

| Category | Changes |
|----------|---------|
| **Dock** | Auto-hide, small icons, no recents, scale minimize, no delay |
| **Screenshots** | PNG format, saved to `~/Screenshots`, no shadow |
| **Keyboard** | Fast key repeat, no press-and-hold, no auto-correct/capitalize/smart quotes |
| **Trackpad** | Faster tracking speed |
| **Mission Control** | Fixed spaces (no auto-rearrange), fast animations, group by app |
| **Hot Corners** | Top-left: Mission Control, Top-right: Desktop |
| **Safari** | Developer menu enabled, full URL in address bar |
| **TextEdit** | Plain text default, UTF-8 encoding |
| **Finder** | Hidden files visible, path bar, status bar, list view, folders first, no .DS_Store on network |
| **Animations** | Reduced motion, fast window resize |
| **Misc** | No quarantine dialog, battery %, Dracula purple highlight, expanded save/print panels |
| **Touch ID** | Enabled for sudo — use fingerprint instead of password in terminal |
| **DNS** | Set to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) + Google (8.8.8.8) |
| **Spotlight** | Excluded node_modules, caches, Homebrew directories from indexing |
| **Time Machine** | Excluded node_modules, Docker, caches, Downloads from backups |
| **Siri** | Disabled and removed from menubar |
| **Rectangle** | Almost maximize (95%), 8px gaps between windows, snap on drag |

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
| `find` | `fd` | Fast file finder |
| `grep` | `rg` | Fast content search |
| `cd` | `z` | Smart directory jumping |
| `top` | `btop` | System monitor |
| `sed` | `sd` | Find and replace |
| `du` | `dust` | Disk usage |
| `df` | `duf` | Disk free |
| `ps` | `procs` | Process list |
| `ping` | `gping` | Latency graph |
| `dig` | `dog` | DNS lookup |
| `watch` | `viddy` | Watch command output |
| `hexdump` | `hexyl` | Hex viewer |
| `rm` | `trash` | Safe delete (Trash) |
| `diff` | `difft` | Syntax-aware diff |
| `dl` | `aria2c` | Fast download |
| `wget` | `aria2c` | Fast download |
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
| `watchrun` | `find ... \| entr -r` | Watch and rerun on changes |

---

## VS Code Extensions

Auto-installed by the script:

| Extension | Purpose |
|-----------|---------|
| **Dracula Official** | Color theme |
| **Prettier** | Code formatter |
| **ESLint** | JavaScript/TypeScript linter |
| **Tailwind CSS IntelliSense** | Tailwind class autocomplete |
| **Auto Rename Tag** | Rename paired HTML/JSX tags |
| **Path Intellisense** | Autocomplete file paths |
| **Error Lens** | Inline error/warning highlights |
| **GitLens** | Git blame, history, and annotations |
| **GitHub Copilot** | AI code completion |

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
./setup-dev-tools.sh

# Option 2: Restore from Brewfile (packages only, no configs)
brew bundle install --file=~/.config/brewfile/Brewfile

# Option 3: Restore dotfiles via chezmoi
chezmoi init <your-github-username> && chezmoi apply

# Option 4: Run only specific categories
./setup-dev-tools.sh --only core,git,dx,configs
```

---

## Updating

```bash
# Update everything at once (via topgrade)
topgrade

# Or update manually
brew update && brew upgrade && brew cleanup

# Re-run this script to pick up new tools/configs
./setup-dev-tools.sh
```

The script will:
- Skip already-installed tools
- Update the `~/.zshrc` managed block
- Export a fresh Brewfile
- Apply any new macOS defaults
- Report what changed

---

## Troubleshooting

```bash
# Check the install log
cat ~/.local/share/dev-setup/setup-*.log | grep ERROR

# Run brew doctor
brew doctor

# Verify critical tools
git --version && node --version && python3 --version

# Re-run just one category
./setup-dev-tools.sh --only security

# Preview without changes
./setup-dev-tools.sh --dry-run
```
