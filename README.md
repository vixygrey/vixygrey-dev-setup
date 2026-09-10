# VixyGrey's Development Environment Setup

[![Lint](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml)
[![Release](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/vixygrey/vixygrey-dev-setup?display_name=tag&sort=semver)](https://github.com/vixygrey/vixygrey-dev-setup/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-supported-brightgreen)

A single setup script that installs and configures a curated macOS development environment. It covers development, GitHub, AWS/CDK, infrastructure, security, backup, and daily productivity.

Homebrew is the primary package manager. npm, Cargo, Go, uv, the OMP plugin manager, upstream installers, and pinned source builds cover packages outside Homebrew.

## Documentation

- [Shortcuts](docs/SHORTCUTS.md) -- keyboard shortcuts and shell aliases reference

## Project structure

The script is the product. The other tracked files define its assets, generated outputs, documentation, tests, workflows, and planning state.

| Path | Holds |
|---|---|
| [`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh) | The generator and installer |
| [`assets/`](assets/) | Files copied onto provisioned machines |
| [`config/generated-outputs.tsv`](config/generated-outputs.tsv) | Generated-output policy and verification inventory |
| [`docs/`](docs/) | User reference documents |
| [`AGENTS.md`](AGENTS.md) | Procedural rules: workflow, commands, verification loop |
| [`CONVENTIONS.md`](CONVENTIONS.md) | Normative rules: how the code must look and behave |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to open a change, for humans |
| [`specs/`](specs/) | Planning state, architecture decision records, tech stack |
| [`.github/`](.github/) | CI, issue templates, pull request template, and branch rules |
| [`Justfile`](Justfile) | Local commands. Run `just preflight` before any commit. |
| [`tests/`](tests/) | Helper unit tests and the Homebrew name check |

## Quick Start

> **Before you start:** macOS ships `bash` 3.2, but this script needs **bash 4+**.
> If `bash --version` shows 3.2, install Homebrew if needed, then run
> `brew install bash` before starting setup.

```bash
chmod +x scripts/setup-dev-tools-mac.sh
./scripts/setup-dev-tools-mac.sh
```

A few good first commands after setup:

```bash
actionlint                              # lint GitHub Actions workflows
duckdb                                  # local SQL shell for CSV/JSON/Parquet
ps aux | jc --ps | jq '.[0]'            # classic command output -> JSON
yaml-py -c 'import yaml; print(yaml.safe_load("a: 1"))'
omp config get modelRoles               # which model each OMP role uses
```

## Bootstrap trust model

This repo is a bootstrapper, so a few first-run install paths intentionally trust
upstream installer scripts rather than shipping vendored payloads here. Today that
includes:

- **Homebrew** — fetched from Homebrew's official install script
- **rustup** — fetched from `sh.rustup.rs`
- **pnpm** — fetched from `get.pnpm.io/install.sh`

Those installer payloads are **not checksum-pinned by this repo today**. That is a
practical trade for a one-command setup script, not a claim that the risk is zero.
If you want to inspect first, run `--dry-run`, read `scripts/setup-dev-tools-mac.sh`,
and prefer tagged release artifacts with the published SHA256 checksum.

## CLI Options

```bash
./scripts/setup-dev-tools-mac.sh --help              # Show all options
./scripts/setup-dev-tools-mac.sh --dry-run           # Preview changes without installing
./scripts/setup-dev-tools-mac.sh --no-prompt         # Disable interactive prompts
./scripts/setup-dev-tools-mac.sh --interactive       # Choose categories interactively
./scripts/setup-dev-tools-mac.sh --list              # List declared Homebrew and npm packages
./scripts/setup-dev-tools-mac.sh --resume            # Continue from where a previous run left off
./scripts/setup-dev-tools-mac.sh --uninstall         # Show commands to remove everything (no changes made)
./scripts/setup-dev-tools-mac.sh --cleanup           # Remove tools from previous versions no longer in script
./scripts/setup-dev-tools-mac.sh --verify            # Check supported generated configs with installed consumers
./scripts/setup-dev-tools-mac.sh --list-categories   # List all available categories
./scripts/setup-dev-tools-mac.sh --skip mac-media,mac-cloud  # Skip specific categories
./scripts/setup-dev-tools-mac.sh --only core,git,aws,dx      # Only install specific categories
./scripts/setup-dev-tools-mac.sh --version           # Show script version
```

> macOS-only categories use the `mac-*` prefix (e.g., `--skip mac-media`).

> **A category installs its tools; it does not configure them.** Every generated
> config file is written in the `configs` category (plus starship in `dracula`,
> `~/Scripts` in `filesystem`, `~/.zshrc` in `shell`) — so `--only git` installs git
> tooling but refreshes none of its configuration, including the global pre-commit
> hook. Pair them: `--only git,configs`. The run prints a reminder when `--only`
> would skip the configuration for what you selected.

## What It Does

1. **Pre-flight checks** -- verifies macOS version, disk space, internet, admin privileges
2. Installs tools through idempotent Homebrew, npm, Cargo, Go, uv, OMP plugin, and upstream installer paths, plus pinned source builds
3. Writes managed defaults for supported tools and preserves user-owned settings
4. Applies a cohesive **Dracula-Sakura** theme across the terminal, editor, and TUI surfaces
5. Sets macOS system defaults (Dock, keyboard, Finder, screenshots, screensaver, etc.)
6. Configures Finder sidebar with custom favorites via **LSSharedFileList** API
7. Configures Dock size, recent-app visibility, and minimize behavior while keeping auto-hide and pins unchanged
8. Auto-writes `~/.zshrc` with a managed block (preserves your customizations)
9. Exports a `Brewfile` snapshot (with descriptions) for reproducibility
10. **Post-install verification** -- verifies critical tools work
11. Runs `brew cleanup` and `brew doctor`
12. **Logs everything** to `~/.local/share/dev-setup/` for debugging
13. Reports final summary with install/skip/fail counts and duration

## Features

| Feature | Description |
|---------|-------------|
| **Idempotent** | Safe to re-run -- skips anything already installed |
| **Dry run** | Preview all changes with `--dry-run` |
| **Resume** | Continue after a failure with `--resume` -- skips previously completed items |
| **Uninstall guide** | Show removal commands with `--uninstall` (no destructive actions taken) |
| **Cleanup** | Remove tools from previous versions with `--cleanup` (auto-detects deprecated tools) |
| **Verify** | Check supported generated configs with installed consumers. The report names unchecked inventory rows and exits 1 on a verified mismatch |
| **Lockfile** | Prevents concurrent runs via atomic directory-based lock |
| **Category filtering** | Install only what you need with `--only` / `--skip` (validates category names) |
| **List packages** | List declared Homebrew formulae, casks, and npm packages with `--list` |
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
| **coreutils** | GNU core utilities -- drop-in replacements for macOS' BSD versions |
| **gnu-sed** | GNU sed -- GNU-flavored regex and flags |
| **gnu-tar** | GNU tar -- GNU-flavored flags |
| **gawk** | GNU awk -- full-featured awk replacement |
| **findutils** | GNU find and xargs |

---

## Core Development

| Tool | Description |
|------|-------------|
| **mise** | Runtime manager used here for Node and Python |
| **Node.js LTS** | JavaScript runtime (latest Long Term Support version, installed via mise) |
| **Go** | Go programming language |
| **Python 3.12** | Python runtime (installed via mise) |
| **uv** | Fast Python package manager -- 10-100x faster than pip |
| **PyYAML** (`yaml-py`) | Isolated helper Python with the `yaml` module preinstalled for local YAML scripts and one-liners |
| **Rust** | Rust toolchain via rustup (rustc, cargo, etc.) |
| **pnpm** | Fast, disk-efficient npm alternative |
| **jq** | Lightweight command-line JSON processor |
| **direnv** | Per-directory environment variables (auto-loads `.envrc`) |
| **cmake** | Cross-platform build system generator |
| **pkg-config** | Helper tool for compiling libraries |

---

## Git & GitHub

| Tool | Description |
|------|-------------|
| **git** | Distributed version control |
| **gh** | GitHub CLI -- PRs, issues, Actions from the terminal |
| **delta** | Beautiful git diffs with syntax highlighting and side-by-side view |
| **gpg** | GNU Privacy Guard for commit signing and encryption |
| **pinentry-mac** | macOS keychain integration for GPG passphrases |
| **lazygit** | Terminal UI for git -- visualize branches, stage hunks interactively |
| **git-absorb** | Auto-fixup commits -- automatically amends the right commit |
| **pre-commit** | Git hook framework -- run linters/formatters before each commit |

---

## AWS & CDK

| Tool | Description |
|------|-------------|
| **aws-cli v2** | Official AWS command-line interface |
| **aws-cdk** | AWS Cloud Development Kit -- infrastructure as TypeScript/Python code |
| **aws-sam-cli** | AWS Serverless Application Model -- local Lambda testing |
| **cfn-lint** | CloudFormation template linter |
| **session-manager-plugin** | SSH-less access to EC2 instances via AWS SSM |
| **granted** | Fast multi-account AWS SSO credential switching |
| **e1s** | ECS TUI -- clusters, services, tasks, exec, logs, and port forwarding |
| **e2c** | EC2 TUI -- start/stop/reboot/terminate, metrics, SSH (young project; via `go install`) |
| **stu** | S3 TUI -- browse/preview/download buckets |
| **claws** | Broad all-AWS TUI with a managed palette and a read-only shell default |
| **s5cmd** | Massively parallel S3 CLI -- 10-30x faster than `aws s3` for bulk |
| **steampipe** | Query live AWS with SQL (inventory & posture); `steampipe plugin install aws` |
| **dynein** | Ergonomic DynamoDB CLI (awslabs) -- shorthand ops, import/export |
| **iamlive** | Generate least-privilege IAM policies from observed API calls (tap) |

---

## Infrastructure as Code (IaC)

| Tool | Description |
|------|-------------|
| **terraform-docs** | Auto-generate module README sections from variables and outputs |
| **checkov** | IaC static analysis -- Terraform, CloudFormation, Kubernetes, Dockerfile |
| _tfsec_ | _Folded into `trivy config` -- not installed separately_ |

---

## Security & Secrets

| Tool | Description |
|------|-------------|
| **gitleaks** | Fast git secret scanning -- great for CI and pre-commit hooks |
| **age** | Modern, simple file encryption (replaces GPG for file encryption) |
| **trivy** | Vulnerability scanner for containers, filesystems, and IaC |
| **semgrep** | Static analysis tool -- finds bugs and security issues in code |
| **cosign** | Sign and verify container images and artifacts |
| **mkcert** | Create locally-trusted HTTPS certificates for development |
| **ssh-audit** | Audit SSH server and client configuration for security |
| **Bitwarden** | Encrypted password manager for native and browser workflows |
| **chamber** | Local encrypted secrets vault with a terminal interface |

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
| `man` | **tldr** (tlrc) | Community-driven simplified man pages with examples |
| `top` | **btop** | Modern resource monitor with graphs and mouse support |
| `sed` | **sd** | Intuitive find and replace with simpler regex syntax |
| `cut`/`awk` | **choose** | Simple column selection with negative indexing |
| `du` | **dust** | Visual disk usage tree with bar charts |
| `df` | **duf** | Colorful disk usage table with smart formatting |
| `ps` | **procs** | Sortable process list with tree view, Docker-aware |
| `ping` | **gping** | Real-time latency graph for multiple hosts |
| `curl` | **xh** | Colorized HTTP client with JSON shortcuts |
| `dig` | **doggo** | Colorized DNS lookup with DoH/DoT support |
| `wc` (code) | **scc** | Count lines of code by language + complexity + COCOMO cost estimate |
| `watch` | **viddy** | Modern watch with diff highlighting and history |
| `hexdump` | **hexyl** | Colorized hex viewer with ASCII sidebar |
| `curl`/`wget` | **aria2** | Multi-connection parallel downloads, 3-10x faster, BitTorrent |
| `tar`/`unzip`/`7z` | **ouch** | Universal archive tool -- auto-detects format from extension |
| `rm` | **trash** | Moves files to macOS Trash instead of permanent delete |
| `rsync` | **rsync** (latest) | Updated rsync with better progress and Apple metadata |
| `make` | **just** | Modern task runner -- simpler syntax, no tab weirdness |
| file manager | **Yazi** | Fast terminal file manager with previews, fuzzy search, and bulk operations |
| `jq` (interactive) | **fx** | Interactive JSON viewer/processor for exploring large JSON |
| `jq` (interactive) | **jnv** | Interactive JSON navigator with jq filtering |
| `LS_COLORS` | **vivid** | LS_COLORS generator -- colorize file listings by type (Dracula themed) |

---

## Data & File Processing

| Tool | Description |
|------|-------------|
| **yq** | jq for YAML -- parse and manipulate YAML files (essential for k8s/CDK) |
| **csvkit** | Suite of CSV tools -- csvcut, csvgrep, csvstat, csvlook |
| **jc** | Convert many classic CLI outputs into JSON so they pipe cleanly into `jq` and automation |
| **jqp** | Interactive jq playground / TUI -- explore JSON while iterating on jq filters |
| **pandoc** | Universal document converter -- Markdown to PDF, DOCX, HTML, etc. |
| **tectonic** | Self-contained LaTeX/PDF engine so pandoc can render PDFs (`pandoc in.md -o out.pdf --pdf-engine=tectonic`) -- a bare Mac has no PDF engine |
| **poppler** | PDF tools -- `pdftoppm` (PDF→PNG), `pdftotext`, `pdfinfo` |
| **imagemagick** | Image manipulation CLI -- resize, convert, composite, watermark |
| **yt-dlp** | Video/audio downloader for YouTube and hundreds of other sites |

---

## Code Quality

| Tool | Description |
|------|-------------|
| **shellcheck** | Shell script linter -- catches bugs and bad practices |
| **shfmt** | Shell script formatter -- consistent style for bash/zsh scripts |
| **actionlint** | GitHub Actions workflow linter -- catches workflow/expression/job wiring mistakes plain YAML parsing misses |
| **act** | Run GitHub Actions locally before pushing (`.actrc` forces `linux/amd64` on Apple Silicon) |
| **hadolint** | Dockerfile linter -- catches bad practices and security issues |
| **typos** | Source code spell checker -- fast, low false positives |
| **ast-grep** | Structural code search/replace using AST -- like semgrep but interactive |
| **ruff** | Extremely fast Python linter and formatter -- replaces flake8+black+isort |

## Language Servers for OMP

OMP discovers each server from project markers and its command on `PATH`.

| Languages | Command | Installation |
|---|---|---|
| TypeScript and JavaScript | `typescript-language-server` | npm |
| HTML | `vscode-html-language-server` | npm |
| CSS, SCSS, Sass, and Less | `vscode-css-language-server` | npm |
| JSON and JSONC | `vscode-json-language-server` | npm |
| ESLint | `vscode-eslint-language-server` | npm |
| YAML | `yaml-language-server` | npm |
| Bash and Zsh | `bash-language-server` | npm |
| Python types | `pyright-langserver` | npm |
| Python lint and format | `ruff server` | Homebrew |
| C, C++, and Objective-C | `clangd` | Homebrew LLVM |
| Rust | `rust-analyzer` | Homebrew |
| C# | `omnisharp` | Verified official release and .NET SDK |
| Lua | `lua-language-server` | Homebrew |
| Dockerfile | `docker-language-server start --stdio` | Homebrew |
| Markdown | `marksman` | Homebrew |
| TypeScript, JavaScript, JSON, and CSS lint | `biome lsp-proxy` | npm |

The generated OMP policy selects Pyright for Python type intelligence and Ruff for lint and format operations.

---


## Performance & Load Testing

| Tool | Description |
|------|-------------|
| **hurl** | Run HTTP requests from plain text files -- curl meets test runner |

---

## Dev Servers & Tunnels

| Tool | Description |
|------|-------------|
| **ngrok** | Expose localhost to the internet for webhooks and demos |
| **miniserve** | Instant file server from any directory -- one command |

---

## Terminal Productivity

| Tool | Description |
|------|-------------|
| **Caligula** | Disk imaging TUI with verification and compressed-image support |
| **Nerdlog** | Multi-host log viewer with live filtering, histograms, and OpenSSH transport |
| **Emeraldian** | Obsidian vault TUI with live preview, backlinks, graph views, and an optional assistant |
| **Watchtower** | Global news, markets, weather, and optional model-generated intelligence briefs |
| **leaf** | Terminal Markdown previewer -- live watch, fuzzy picker, Mermaid/LaTeX, inline mode |
| **mprocs** | TUI for running multiple dev processes side by side -- frontend/backend/worker/watchers in one terminal surface |
| **broot** | Directory tree and file-navigation TUI with the shell-integrated `br` launcher |
| **watchexec** | Run commands on file changes -- supports globs, debouncing, process groups |
| **pv** | Pipe viewer -- add progress bars to any piped command |
| **gum** | Shell script UI toolkit -- pretty prompts, spinners, confirmations |
| **topgrade** | Update supported package managers and system components from one command |
| **fastfetch** | Quick system info display -- faster neofetch replacement |
| **nano** | macOS fallback editor, configured with syntax highlighting |
| **lnav** | Advanced log file viewer -- auto-format, SQL queries on logs |
| **qalc** | Powerful terminal calculator (units, currencies, variables) |
| **lazyssh** | TUI SSH connection manager |
| **eilmeldung** | Fast RSS reader with vim-style navigation and a Dracula-Sakura palette |
| **concord** | Discord terminal client with Keychain tokens and opt-in microphone transmission |
| **cfait** | Offline-first task manager with optional CalDAV synchronization |

---

## GitHub Extras

| Tool | Description |
|------|-------------|
| **gh-dash** | GitHub dashboard in the terminal -- PRs, issues, notifications |

---

## Database & Data

| Tool | Description |
|------|-------------|
| **duckdb** | Local analytical SQL database -- query CSV/JSON/Parquet and ad hoc datasets with SQL |
| **harlequin** | Terminal SQL IDE -- multi-tab, autocomplete, DuckDB/Postgres/MySQL/S3; replaced the DBeaver GUI |
| **usql** | Universal SQL CLI -- connects to Postgres, MySQL, SQLite, and more |
| **dbmate** | Lightweight, framework-agnostic database migration tool |

---

## Containers

| Tool | Description |
|------|-------------|
| **Docker Desktop** | Docker engine, Compose, Buildx, and the macOS virtual machine runtime |
| **lazydocker** | Terminal UI for Docker -- manage containers, images, volumes |
| **dive** | Explore Docker image layers -- find what's taking up space |

---

## API Development

| Tool | Description |
|------|-------------|
| **Posting** | Terminal HTTP client with a compact layout, secret redaction, and git-friendly YAML collections |

---

## Networking & Debugging

| Tool | Description |
|------|-------------|
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
| **mise** | Manages Node and Python here while replacing separate per-language version managers |
| **Bun** | Package manager used by OMP to install and update plugin packages |
| **micro** | The `$EDITOR` -- git/gh/lazygit commit messages, leaf's Ctrl+E, quick edits. Non-modal, on-screen key menu (`Ctrl+G` for help), Dracula theme |
| **Croft** | VS Code-style terminal IDE with LSP, debugging, source control, PDF previews, and a Dracula-Sakura theme |
| **Zed** | Fast native editor with a named Dracula-Sakura theme and OMP in the Agent Panel through ACP |
| **omp** | Oh My Pi coding agent with LSP, DAP, subagents, and role-based routing across Codex, Gemini, Claude Sonnet, and local llama.cpp |
| **Bigpowers** | OMP plugin with workflow skills, slash commands, and git safety guards |
| **chezmoi** | Dotfile manager -- backup and restore configs across machines |
| **Kitty** | Fast GPU-accelerated terminal with native macOS support |
| **zellij** | Modern terminal multiplexer -- discoverable UI, layouts, Rust-based |
| **Spotlight + `ff`/`rgf`/`s`** | Global application search plus terminal file and content search. Clipse provides clipboard history |
| **TypeScript** | Typed JavaScript -- installed globally for scripts and tooling |
| **tsx** | Run TypeScript files directly without a build step |

---


## Documentation & Diagrams

| Tool | Description |
|------|-------------|
| **d2** | Diagrams as code in the terminal for reproducible, reviewable architecture diagrams |

---

## Fonts

| Font | Description |
|------|-------------|
| **JetBrains Mono** | Primary development font with ligatures |
| **JetBrains Mono Nerd Font** | JetBrains Mono with patched icons for terminal tools |
| **Inter** | Best UI font for web and design work |

---


## Mac Apps -- System & Utilities

| App | Description |
|-----|-------------|
| **LuLu** | Free open-source outbound firewall -- see what phones home |
| **Mullvad VPN** | Privacy-focused VPN app with the bundled `mullvad` CLI and source-built `mullvad-tui` |
| **Bitwarden** | End-to-end encrypted password manager with browser and native application support |

---

## Mac Apps -- Productivity

| App | Description |
|-----|-------------|
| **LibreOffice** | Headless office suite for validation and conversion of `.pptx`, `.xlsx`, and `.docx` files |
| **Draw.io** | Desktop diagram editor with local file support and a command-line launcher |
| **Herald** | Terminal email and calendar client with a local Dracula-Sakura theme |
| **Obsidian** | Local Markdown knowledge base with a managed Dracula-Sakura theme in each registered vault |
| **rclone** | SFTP/S3/cloud file transfer from the terminal (replaced the Cyberduck GUI) |

---

## Mac Apps -- Browsers

| App | Description |
|-----|-------------|
| **Google Chrome** | Primary Chromium browser for development and DevTools |
| **Firefox** | Privacy-focused browser with a separate engine for cross-browser development |
| **Chawan** | Terminal web browser and pager with private defaults, CSS, JavaScript, and Kitty images |

---

## Mac Apps -- Media

| App | Description |
|-----|-------------|
| **mpv** | Terminal video player -- keyboard-driven, scriptable |
| **oxipng** | Lossless PNG compression -- CLI, scriptable, CI-friendly |
| **jpegoptim** | Lossless JPEG compression -- strip metadata, optimize |
| **spotatui** | Multi-source terminal music player with a seeded Dracula-Sakura theme |

---

## Mac Apps -- Cloud Storage & Backup

| App | Description |
|-----|-------------|
| **rclone** | Sync files to any cloud -- Google Drive, S3, Dropbox, etc. (replaced the Google Drive desktop app) |
| **borg** | Deduplicated encrypted backups -- better than Time Machine for offsite |
| **borgmatic** | Automated borg backup scheduling and configuration |

---


## Dracula-Sakura Theme

Applied consistently across the machine, with built-in Dracula variants kept where a tool exposes only a named theme:

| Tool | How |
|------|-----|
| **micro** | Dracula (`dracula-tc`) set in `settings.json` |
| **bat** | Dracula syntax theme in config |
| **delta** | Dracula syntax theme for git diffs |
| **Kitty** | Full 16-color Dracula-Sakura palette in `kitty.conf` |
| **Yazi** | Dracula-Sakura manager, status, dialog, mode, and file-type colors in `theme.toml` |
| **broot** | Full Dracula-Sakura skin in `~/.config/broot/skins/dracula-sakura.hjson` |
| **Herald** | Full role-based Dracula-Sakura theme in `~/.herald/themes/dracula-sakura.yaml` |
| **Zed** | Named interface, syntax, and terminal theme in `~/.config/zed/themes/dracula-sakura.json` |
| **Croft** | Native extension manifest with full interface, syntax, terminal, and tab palettes |
| **Emeraldian** | Native custom theme for the interface, Markdown, syntax, and graph views |
| **Caligula** | Uses named terminal colors, which Kitty maps to the Dracula-Sakura palette |
| **Nerdlog** | Uses named terminal colors, which Kitty maps to the Dracula-Sakura palette |
| **Chawan** | True-color display defaults in `~/.config/chawan/config.toml` |
| **Posting** | Native custom theme in `~/.local/share/posting/themes/dracula-sakura.yaml` |
| **Obsidian** | Full per-vault CSS theme with dark plum surfaces and Sakura accent colors |
| **jqp** | Dracula base theme with Dracula-Sakura override colors in `~/.jqp.yaml` |
| **fzf** | Dracula colors in `FZF_DEFAULT_OPTS` |
| **Starship** | Dracula-Sakura palette in `starship.toml` |
| **lazygit** | Dracula-Sakura color scheme in config |
| **leaf** | Terminal Markdown previewer (runs on defaults) |
| **gh-dash** | Dracula-Sakura border, text, and selection colors |
| **btop** | Full Dracula-Sakura theme with custom color palette |
| **lazydocker** | Dracula-Sakura borders and options colors |
| **harlequin** | Built-in Dracula theme set in `~/.harlequin.toml` |
| **trippy** | Dracula-Sakura `theme-colors` in `~/.config/trippy/trippy.toml` |
| **zellij** | Dracula-Sakura theme in the config |
| **omp** | Full Dracula-Sakura custom theme in `~/.omp/agent/themes/dracula-sakura.json`, selected through `theme.dark` in `config.yml` |
| **eilmeldung** | Full RGB Dracula-Sakura palette in `~/.config/eilmeldung/config.toml` |
| **concord** | Dracula-Sakura Highlight Groups and rounded borders in `~/.config/concord/theme.toml` |
| **spotatui** | Seeded Dracula preset with Sakura rose accents in `~/.config/spotatui/config.yml` |
| **cfait** | Built-in Dracula theme in its local-first seed configuration |
| **lnav** | Full Dracula-Sakura `theme-def` (151 values) as a config fragment in `~/.config/lnav/configs/dev-setup/`, selected with lnav's own `:config` |
| **atuin** | 15-token theme in `~/.config/atuin/themes/dracula-sakura.toml` |
| **stu** | 19 `ui.theme.*` keys in `~/.stu/config.toml` (hex, via Ratatouille's colour serde) |
| **e1s** | 11 hex colour overrides in `~/.config/e1s/config.yml` |
| **claws** | Dracula preset with Sakura primary, danger, and success overrides |
| **miniserve** | `--color-scheme-dark dracula` in the `serve` alias |
| **vivid** | Dracula-themed LS_COLORS for file type coloring |
| **vim** | Dracula-ish color scheme (no plugin needed) |
| **macOS** | System highlight color set to Dracula purple |

Watchtower hardcodes its palette and exposes no theme setting. The setup leaves its upstream colors unchanged.

---

### Tools that cannot take the house theme

Checked and recorded so they are not re-investigated each release. Every check
used a control: a deliberately invalid value had to be **rejected** before
acceptance of a valid one meant anything.

| Tool | Why not |
|------|---------|
| `duf` | preset flags only (`dark\|light\|ansi`) with no custom palette |
| `fx` | numbered built-in themes via `FX_THEME="0"`; no custom theme definition |
| `procs` | indexed color only (`Color256`), so the palette can only use nearest terminal indices |
| `viddy`, `cheznav`, `lazynpm`, `lazyrsync`, `lazyssh` | no theming found in their help or configuration schemas |
| `mullvad-tui`, Mullvad VPN | Both clients use fixed application colors and expose no theme configuration |
| `chamber` | Its current configuration schema exposes no theme settings |
| Firefox, Bitwarden, Docker Desktop | Appearance belongs to application or profile state, which the generator does not overwrite |

`stu` and `e1s` are themed but carry **no `--verify` row**. Both are TUIs with no
validate mode, and without a TTY they panic inside crossterm before config parsing
is reached — a correct config and a deliberately broken one produce the identical
panic, so a row built on that would prove nothing.

## Filesystem Structure

The scripts create a deliberately **ADD-friendly** directory layout: few top-level
roots, shallow nesting, no overlapping categories, and an `~/Inbox` dump zone so
nothing has to be filed in the moment. When in doubt, drop it in `Inbox` (or use
Spotlight to find things) rather than agonizing over where it "should" go.

```
~/
|-- Inbox/                       # Dump zone — drop ANYTHING here, sort later or never
|
|-- Code/                        # -- Development (unchanged) --
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
|-- Documents/                   # -- Life Admin (a few flat buckets) --
|   |-- finance/                 # Statements, taxes, invoices
|   |-- health/                  # Medical records, insurance cards
|   |-- admin/                   # Legal, insurance, contracts
|   |-- receipts/                # Purchase receipts, warranties
|   +-- travel/                  # Itineraries, bookings
|
|-- Creative/                    # -- Creative Work (flat) --
|   |-- writing/                 # Blog posts, drafts, notes
|   |-- design/                  # Graphic/design projects, mockups, assets
|   +-- video/                   # Video projects, raw footage
|
|-- Media/                       # -- Personal Media --
|   |-- photos/                  # Includes the bundled Dracula-Sakura wallpaper asset
|   |-- videos/
|   +-- music/
|
+-- Archive/                     # Cold storage — one bucket for old/done stuff
```

### Helper Scripts (~/Scripts/bin/)

| Script | Alias | Description |
|--------|-------|-------------|
| `new-project` | `nproj` | Scaffold a new project with a Bigpowers-aligned repo template: AGENTS.md, CONVENTIONS.md, specs/ cockpit, LF-safe .editorconfig and .gitattributes. Add `--justfile` for an optional minimal starter Justfile |
| `clone-work` | `cwork` | Clone a work repo into `~/Code/work/<org>/<repo>` |
| `clone-personal` | `cpers` | Clone a personal repo into `~/Code/personal/<repo>` |
| `clean-downloads` | `cleandl` | Delete files in ~/Downloads older than 30 days (interactive) |
| `backup-dotfiles` | `dotback` | Push dotfile changes via chezmoi |
| `project-stats` | `pstats` | Show repo counts, disk usage, recently modified projects |
| `health-check` | `hc` | Quick system health overview (disk, memory, battery, brew, Docker, node_modules) |
| `setup-ssh` | `sshsetup` | Generate an Ed25519 SSH key and optionally add it to GitHub via gh CLI |
| `export-brewfile` | `brewsnap` | Export a Brewfile snapshot with descriptions for reproducibility |

### Global Justfile (~/.justfile)

26 task-runner recipes available from any directory via `gj`:

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
| `gj loc` | Count lines of code in current directory (via scc) |

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

The **personal** identity is also set as the **global default**, so commits outside those two trees (`~/Code/oss`, `~/Inbox`, `/tmp`, …) still have a committer -- the `~/Code/work` include still overrides it there. The script prompts for your name/email interactively; you can also edit `~/.gitconfig-work` / `~/.gitconfig-personal` afterward.

---

## Configurations Created

The script generates config files with sensible defaults:

| File | Tool | Highlights |
|------|------|------------|
| `~/.zshrc` | Shell | Auto-written managed block with all init scripts, aliases, welcome screen |
| `~/.zprofile` | Shell | Login shell PATH, editor, pager, LESS, XDG dirs, ulimit increase for Node.js |
| `~/.gitconfig` | git | Rebase pull, histogram diff, delta, rerere, auto-stash, and workflow aliases |
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
| `~/.config/mprocs/mprocs.yaml` | mprocs | 5k scrollback, wider proc list, per-process logs under the config dir |
| `~/.config/broot/conf.hjson` | broot | Dracula-Sakura skin import and git-aware defaults |
| `~/.config/broot/skins/dracula-sakura.hjson` | broot | Full terminal palette for browser, preview, status, git, and diff surfaces |
| `~/.config/starship.toml` | Starship | Rich two-line prompt with a Dracula-Sakura palette, OS icon, git status with counts, Node/Python/Rust/Go/Docker/AWS/Terraform versions, battery warning, time, Nerd Font icons |
| `~/.config/yt-dlp/config` | yt-dlp | Best quality mp4, aria2c downloader, metadata, subtitles |
| `~/.config/gh-dash/config.yml` | gh-dash | PR/issue sections, Dracula-Sakura theme |
| `~/Library/Application Support/ngrok/ngrok.yml` | ngrok | Base config (add authtoken). ngrok's real macOS path — **not** `~/.config/ngrok`, which it never reads; a stranded copy there is removed on the next run |
| `~/.config/micro/settings.json` | micro | Dracula (`dracula-tc`), whitespace cleanup, soft wrap, mouse support, and the shared `$EDITOR` role |
| `~/.config/zed/settings.json` | Zed | House fonts, Dracula-Sakura overrides, editor defaults, and an `omp acp` external agent |
| `~/Library/Application Support/emeraldian/config.toml` | Emeraldian | Reading-first defaults, images, and an offline read-only assistant |
| `~/Library/Application Support/emeraldian/themes/dracula-sakura.toml` | Emeraldian | Native Dracula-Sakura interface, Markdown, syntax, and graph theme |
| `~/.config/croft/config.json` | Croft | Format on save, selection whitespace, copy on select, 20k terminal scrollback, and whole-project diagnostics |
| `~/.config/croft/extensions/dracula-sakura/extension.toml` | Croft | Native Dracula-Sakura interface, syntax, terminal, and tab theme |
| `~/.herald/conf.yaml` | Herald | User-owned account config with `theme.name` merged to select Dracula-Sakura |
| `~/.herald/themes/dracula-sakura.yaml` | Herald | Managed Dracula-Sakura role palette |
| `~/.config/eilmeldung/config.toml` | eilmeldung | Managed Dracula-Sakura palette, rounded borders, Nerd Font icons, and the macOS URL opener |
| `~/.config/concord/config.toml` | concord | Keychain token storage, Kitty images, selected-only animation, and opt-in microphone transmission |
| `~/.config/concord/theme.toml` | concord | Managed Dracula-Sakura Highlight Groups, semantic colors, and rounded borders |
| `~/.config/spotatui/config.yml` | spotatui | User-owned seed with Dracula-Sakura colors and optional network presence disabled |
| `~/.config/cfait/config.toml` | cfait | User-owned local-first seed with Dracula, privacy blur, reminders, and the micro editor |
| `~/Media/photos/dracula-sakura.jpg` | Wallpaper | Bundled Dracula-Sakura wallpaper asset copied onto every provisioned machine |
| _(cliamp)_ | cliamp | Music player — self-configured on first run (point at `~/Media/music`) |
| `~/.config/zellij/config.kdl` | zellij | Dracula-Sakura theme, compact layout, mouse support, and stock modal keybindings |
| `~/.config/mpv/mpv.conf` | mpv | Hardware accel, save position, screenshots to ~/Screenshots |
| `~/.jqp.yaml` | jqp | Dracula base theme with Dracula-Sakura color overrides |
| `~/.agents/skills/*` | omp | Four scoped shared skills: `api-testing`, `d2-diagrams`, `inspect-machine`, and `office-layout-check` |
| `~/.omp/agent/extensions/protected-paths.ts` | omp | Blocks native file mutations to credentials, dependency trees, and repository metadata. Bash and Eval remain under native approval policies |
| `~/.omp/agent/AGENTS.md` | omp | Global Oh My Pi instruction layer with house preferences and writing rules |
| `~/.omp/agent/themes/dracula-sakura.json` | omp | Full Dracula-Sakura theme, including OMP status-line colors |
| `~/.omp/agent/config.yml` | omp | Merged because OMP also writes this file. Uses automatic reasoning, workload routing, usage-aware fallback, provider caching, disabled MiniMax, disabled macOS word completion hints, and local Qwen last |
| `~/.omp/agent/.env` | omp | User-owned seed with blank `ANTHROPIC_API_KEY` and `GEMINI_API_KEY` entries. Later runs leave it unchanged |
| `~/.omp/plugins/node_modules/bigpowers` | omp | Enabled Bigpowers plugin package with workflow skills, slash commands, and the `bigpowers_skill` tool |
| `~/Library/LaunchAgents/dev.vixygrey.llama-cpp.plist` | llama.cpp | Runs Qwen2.5 Coder 14B on port 8081 with the Vulkan backend |
| `~/.config/kitty/kitty.conf` | Kitty | JetBrainsMono Nerd Font, Dracula-Sakura palette, compact padding, integrated titlebar |
| `~/.config/yazi/yazi.toml` | Yazi | Natural sorting, hidden files, symlink targets, previews |
| `~/.config/yazi/theme.toml` | Yazi | Dracula-Sakura interface and file-type palette |
| `~/.config/fastfetch/config.jsonc` | fastfetch | Nerd Font icons, package counts, Node/Python/Go/Rust/Docker versions, battery, disk, colored output |
| `~/.config/mise/config.toml` | mise | Auto-install, trust ~/Code |
| `~/.config/topgrade.toml` | topgrade | Cleanup, greedy cask updates |
| `~/.config/direnv/direnv.toml` | direnv | Hidden env diff, auto-trust ~/Code, load .env |
| `~/.config/btop/` | btop | Dracula-Sakura theme with full color palette |
| `~/.config/lazydocker/` | lazydocker | Dracula-Sakura theme, timestamps, compose support |
| `~/.config/pip/pip.conf` | pip | Require virtualenv, no telemetry |
| `~/.harlequin.toml` | harlequin | Built-in Dracula theme, vscode keymap, file tree on |
| `~/.config/gh/config.yml` | GitHub CLI | SSH protocol, micro editor, delta pager, aliases (co, pv, pc, pl, il, pm, rel) |
| `~/.aws/config` | AWS CLI | Default region, json output, bat pager, auto-prompt, SSO template |
| `~/.config/git/hooks/` | git | Global pre-commit hooks (debug statements, large files >5MB, conflict markers) |
| `~/.config/brewfile/Brewfile` | Homebrew | Snapshot of all installed packages with descriptions |
| `~/.justfile` | just | Global recipes for system, git, Docker, network, cleanup, and project information |
| `~/.shellcheckrc` | shellcheck | External sources, disabled false positives |
| `~/.config/leaf/config.toml` | leaf | Ctrl+E hands off to micro at the current line |
| `~/.config/trippy/trippy.toml` | trippy | Dracula-Sakura theme-colors |
| `~/.actrc` | act | Ubuntu images, container reuse, `--container-architecture linux/amd64` |
| `~/.ripgreprc` | ripgrep | Smart-case, hidden files, custom type definitions |
| `~/.config/claws/config.yaml` | Claws | Dracula-Sakura palette, dashboard startup, no automatic config rewrites |
| `~/.config/chawan/config.toml` | Chawan | Private browser defaults, Kitty images, true-color Dracula-Sakura display |
| `~/.config/posting/config.yaml` | Posting | Compact layout, secret redaction, isolated request environment |
| `~/.local/share/posting/themes/dracula-sakura.yaml` | Posting | Full application, syntax, URL, variable, and HTTP-method palette |
| `~/.zshenv` | Shell | mise activation for all shell types (login + non-login) — coverage. mise is activated **again** at the end of `~/.zshrc` for *precedence*: `.zshenv` runs first, so everything prepended afterwards (`brew shellenv`, gnubin, `~/.local/bin`, `$PNPM_HOME`) would otherwise outrank it |
| `~/.hushlogin` | Terminal | Suppresses "Last login" message |
| `~/.fdignore` | fd | Global ignore patterns (node_modules, .git, dist, etc.) |
| `~/.vimrc` | vim | Line numbers, clipboard, mouse, Dracula colors, space leader, persistent undo |
| `~/.nanorc` | nano | Line numbers, auto-indent, mouse, syntax highlighting |
| `~/.gemrc` | Ruby | No docs on gem install |
| `~/.config/lazygit/config.yml` | lazygit | Dracula-Sakura theme, delta pager, Nerd Fonts, auto-fetch, micro editor, and rounded borders |
| `~/.local/bin/*` | mise | Links non-Python mise shims for git hooks, launchd jobs, editors, and non-zsh shells |

---

## macOS System Defaults

| Category | Changes |
|----------|---------|
| **Dock** | Small icons, no recent applications, scale minimization into app icons, and unchanged auto-hide and pins |
| **Screensaver** | 45min idle, display sleep at 2hr (charger) / 1h15m (battery) |
| **Screenshots** | PNG format, saved to `~/Screenshots`, no shadow, no thumbnail |
| **Keyboard** | Fast key repeat (2/15), no press-and-hold, no auto-correct/capitalize/smart quotes/dashes/periods |
| **Trackpad** | Faster tracking speed (2.0) |
| **Mission Control** | Fixed spaces — auto-rearrange disabled (predictable Space order) |
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
| `y` | `yazi` | File manager with directory changes preserved after exit |
| `ff` / `rgf` / `s` | find / grep / mdfind | Terminal file and content search |
| `clip` | `clipse` | Clipboard-history TUI |
| `jx` | `fx` | Interactive JSON viewer |
| `f` | `fd` | Fast find |
| `dft` | `difft` | Syntax-aware diff |
| `dl` | `aria2c` | Fast download |
| `venv` | `uv venv` | Fast virtualenv creation |
| `pyrun` | `uv run` | Run Python with uv |
| `gj` | `just --justfile ~/.justfile` | Global justfile recipes |
| `lg` | `lazygit` | Git UI |
| `lzd` | `lazydocker` | Docker UI |
| `md` | `leaf` | Markdown viewer |
| `serve` | `miniserve ...` | Quick file server |
| `ghd` | `gh dash` | GitHub dashboard |
| `gdft` | `git dft` | Syntax-aware git diff |
| `gha` | `act` | Run GitHub Actions locally |
| `hq` | `harlequin` | SQL IDE TUI |
| `claws` | `claws --read-only` | All-AWS TUI with writes disabled by default |
| `nerdlog` | `nerdlog --set transport=ssh-bin` | Multi-host logs through the generated OpenSSH config |
| `prog` | `progress -m` | Monitor progress of running coreutils |
| `ytdl` | `yt-dlp` | Download video |
| `ytmp3` | `yt-dlp -x --audio-format mp3` | Download audio |
| `md2pdf` | `pandoc -f markdown -t pdf` | Markdown to PDF |
| `md2html` | `pandoc -f markdown -t html -s` | Markdown to HTML |
| `md2docx` | `pandoc -f markdown -t docx` | Markdown to Word |
| `resize` | `magick mogrify -resize` | Resize images |
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
| **Zsh completions** | gh and aws auto-completions loaded |
| **GPG_TTY** | Set in zshrc for commit signing to work |
| **ulimit increase** | `ulimit -n 65536` in zprofile for Node.js/webpack/vite |
| **vivid LS_COLORS** | Dracula-themed file type coloring via `vivid generate dracula` |
| **fzf config** | Dracula colors, fd for file finding, bat for preview, eza tree for directory preview, keybindings (ctrl-/ toggle preview, ctrl-y copy) |
| **Plugin guards** | Zsh plugin sources have defensive `[[ -f ]]` guards |
| **Terminal welcome** | Dracula-Sakura fastfetch system dashboard, with a themed identity and workspace fallback |

---

## AI and editors

### AI agents

**Oh My Pi** (`omp`) is the primary coding agent.

The setup also builds llama.cpp from source with Vulkan enabled and Metal disabled.
The login service exposes Qwen2.5 Coder 14B at `http://127.0.0.1:8081`.

```bash
omp
omp config get modelRoles
curl -s http://127.0.0.1:8081/v1/models | jq
```

OMP installs from the `can1357/tap` Homebrew tap as a prebuilt binary.
The OMP runtime remains available to shells, git hooks, and launchd jobs.
Bun handles package installation for the OMP plugin manager.

OMP includes native tools, LSP operations, a DAP debugger, subagents, memory, and nine model roles.
Automatic reasoning handles ordinary turns.
Usage-aware fallback preserves 10 percent of coding-plan quotas.
MiniMax Code is disabled. Provider prompt-cache retention stays on automatic defaults.
The roles use Codex, Gemini, Claude Sonnet, and local Qwen 2.5 Coder.

The local model is the final fallback for each hosted role.
The `LLAMA_CPP_BASE_URL` variable points OMP to the Vulkan service on port 8081.

OMP also carries the Dracula-Sakura theme and the generated `AGENTS.md`.
The shared skill directory is `~/.agents/skills/`.
It contains `api-testing`, `d2-diagrams`, `inspect-machine`, and `office-layout-check`.
The enabled Bigpowers plugin adds its workflow skills, slash commands, git safety guards, and `bigpowers_skill` tool.

**Web search is built in.** `web_search` exposes selectable provider backends. This setup configures
`http://127.0.0.1:8080` as the preferred SearXNG endpoint but does not install or manage
that service. Keyless backends remain available when the local endpoint is unavailable.

The `~/.omp/agent/AGENTS.md` file has the highest precedence among user context files.
OMP owns `~/.omp/agent/config.yml`, so this setup merges managed values into that file.

The `protected-paths.ts` extension blocks native file mutations to credential stores,
dependency trees, and repository metadata. It checks resolved paths to catch symlink
escapes. It does not claim to sandbox Bash or Eval, which remain under omp approval
policies.

**Authentication is yours.** The setup seeds blank `ANTHROPIC_API_KEY` and `GEMINI_API_KEY` entries in `~/.omp/agent/.env` once.
It never reads or overwrites an existing file.
Paste each key after the matching equals sign. OMP loads this file directly.

> `modelRoles` is a **record**, so it reads as a whole and not by sub-key.
> `omp config get modelRoles.default` answers `Unknown setting`, which reports a
> schema shape rather than a missing value.


---

## Chrome Extensions (manual install)

| Extension | Purpose |
|-----------|---------|
| **axe DevTools** | Accessibility testing |
| **React Developer Tools** | React component inspection |
| **JSON Formatter** | Pretty-print JSON in the browser |

---

## Terminal and Search

| Key / command | Action |
|---------------|--------|
| `cmd + space` | Open Spotlight for application, file, and web search |
| `ff` | Find a file and open it |
| `rgf <q>` / `s <q>` | Search file content or the Spotlight index |
| `clip` | Clipboard history (clipse) |
| `lazydocker` | Docker TUI |

See `~/Desktop/KEYBOARD_SHORTCUTS.md` (generated on setup) for the full list.

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

## Troubleshooting

```bash
# Inspect the failure log
cat ~/.local/share/dev-setup/setup-*.log | grep ERROR

# Check Homebrew health
brew doctor

# Resume after a failure (skips already-completed steps)
./scripts/setup-dev-tools-mac.sh --resume

# Preview without changes
./scripts/setup-dev-tools-mac.sh --dry-run

# Run only specific categories (add `configs` to refresh their config too)
./scripts/setup-dev-tools-mac.sh --only core,git,dx,configs

# Show removal commands
./scripts/setup-dev-tools-mac.sh --uninstall
```

---

## License

MIT — see [LICENSE](LICENSE)
