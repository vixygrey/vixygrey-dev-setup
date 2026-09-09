# VixyGrey's Development Environment Setup

[![Lint](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/lint.yml)
[![Release](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml/badge.svg)](https://github.com/vixygrey/vixygrey-dev-setup/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/vixygrey/vixygrey-dev-setup?display_name=tag&sort=semver)](https://github.com/vixygrey/vixygrey-dev-setup/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS](https://img.shields.io/badge/macOS-supported-brightgreen)
![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen)
![Tools](https://img.shields.io/badge/tools-220%2B-purple)
![Configs](https://img.shields.io/badge/configs-60%2B-purple)

A single setup script that installs and configures **220+ tools** with **60+ config files** for development, GitHub, AWS/CDK, IaC, DX, UI/UX, security, backup, and daily productivity on macOS. Safe to re-run -- it skips anything already installed.

| Script | Package Manager |
|--------|-----------------|
| `scripts/setup-dev-tools-mac.sh` | Homebrew |

## Documentation

- [Guide](docs/GUIDE.md) -- daily workflow, tool usage, and setup walkthrough
- [Shortcuts](docs/SHORTCUTS.md) -- keyboard shortcuts and shell aliases reference

## Project structure

Everything below the script is documentation about the script, or CI that guards it.

| Path | Holds |
|---|---|
| [`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh) | The whole product |
| [`AGENTS.md`](AGENTS.md) | Procedural rules: workflow, commands, verification loop |
| [`CONVENTIONS.md`](CONVENTIONS.md) | Normative rules: how the code must look and behave |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to open a change, for humans |
| [`specs/`](specs/) | Planning state, architecture decision records, tech stack |
| [`Justfile`](Justfile) | Every command. `just preflight` before any commit. |
| [`tests/`](tests/) | Helper unit tests (bats) and the Homebrew name check |

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
pi --list-models                        # local Pi model inventory
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
./scripts/setup-dev-tools-mac.sh --list              # List all tools that would be installed
./scripts/setup-dev-tools-mac.sh --resume            # Continue from where a previous run left off
./scripts/setup-dev-tools-mac.sh --uninstall         # Show commands to remove everything (no changes made)
./scripts/setup-dev-tools-mac.sh --cleanup           # Remove tools from previous versions no longer in script
./scripts/setup-dev-tools-mac.sh --verify            # Check every tool actually reads the config we generate
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
2. Installs all tools via Homebrew, Cask, npm, `go install`, and `uv tool` with **progress tracking**
3. Configures every tool with sensible defaults
4. Applies a cohesive **Dracula-Sakura** theme across the terminal, editor, and TUI surfaces
5. Sets macOS system defaults (Dock, keyboard, Finder, screenshots, screensaver, etc.)
6. Configures Finder sidebar with custom favorites via **LSSharedFileList** API
7. Sets the Dock to auto-hide and installs `dockutil` so you can curate pins yourself (no automatic pin list — see GUIDE.md for examples)
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
| **Verify** | Check with `--verify` that each tool reads the config we write, and accepts it. CI proves these files parse; only a machine with the tools installed can prove anything *reads* them. Exits 1 on a mismatch |
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
| **coreutils** | GNU core utilities -- drop-in replacements for macOS' BSD versions |
| **gnu-sed** | GNU sed -- GNU-flavored regex and flags |
| **gnu-tar** | GNU tar -- GNU-flavored flags |
| **gawk** | GNU awk -- full-featured awk replacement |
| **findutils** | GNU find and xargs |

---

## Core Development

| Tool | Description |
|------|-------------|
| **mise** | Universal version manager -- Node, Python, Go, Ruby all in one tool |
| **Node.js LTS** | JavaScript runtime (latest Long Term Support version, installed via mise) |
| **Go** | Go programming language |
| **Python 3.12** | Python runtime (installed via mise) |
| **uv** | Fast Python package manager -- 10-100x faster than pip |
| **PyYAML** (`yaml-py`) | Isolated helper Python with the `yaml` module preinstalled for local YAML scripts and one-liners |
| **Rust** | Rust toolchain via rustup (rustc, cargo, etc.) |
| **bun** | Fast JS runtime, bundler, and test runner |
| **pnpm** | Fast, disk-efficient npm alternative |
| **jq** | Lightweight command-line JSON processor |
| **direnv** | Per-directory environment variables (auto-loads `.envrc`) |
| **lazyenv** | TUI for `.env` files across projects -- diff/sync, secret masking, `.gitignore` checks (complements direnv) |
| **keyward** | TUI SSH-key manager + A–F security audit + encrypted backups (offline, single binary) |
| **bmm** | CLI/TUI bookmark manager -- local, fzf-friendly, imports HTML/JSON/TXT |
| **manly** | Explains the flags in a command from its man page (`manly tar -xzf`) |
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
| **glab** | GitLab CLI -- mirrors the gh conveniences (SSH, micro, same alias names → merge requests; `rc` becomes `rcl`, since glab already has an `rc` command) for client repos on GitLab. GitHub stays primary |
| **delta** | Beautiful git diffs with syntax highlighting and side-by-side view |
| **git-lfs** | Git Large File Storage for binary assets |
| **gpg** | GNU Privacy Guard for commit signing and encryption |
| **pinentry-mac** | macOS keychain integration for GPG passphrases |
| **lazygit** | Terminal UI for git -- visualize branches, stage hunks interactively |
| **git-absorb** | Auto-fixup commits -- automatically amends the right commit |
| **git-cliff** | Generate changelogs from conventional commits |
| **gk** | GitKraken CLI -- installed to serve the [GitKraken MCP server](#claude-code-mcp-servers) to Claude Code, not for interactive use. Replaced the copy the GitLens VS Code extension used to hide in its own storage |
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
| **e1s** | ECS TUI -- clusters/services/tasks, exec, logs, port-forward ("k9s for ECS") |
| **e2c** | EC2 TUI -- start/stop/reboot/terminate, metrics, SSH (young project; via `go install`) |
| **stu** | S3 TUI -- browse/preview/download buckets |
| **claws** | Broad all-AWS TUI (~70 services, k9s-style; young; cask from `clawscli/tap`) |
| **s5cmd** | Massively parallel S3 CLI -- 10-30x faster than `aws s3` for bulk |
| **steampipe** | Query live AWS with SQL (inventory & posture); `steampipe plugin install aws` |
| **dynein** | Ergonomic DynamoDB CLI (awslabs) -- shorthand ops, import/export |
| **iamlive** | Generate least-privilege IAM policies from observed API calls (tap) |

---

## Infrastructure as Code (IaC)

| Tool | Description |
|------|-------------|
| **OpenTofu** | Open-source Terraform alternative -- multi-cloud infrastructure as code |
| **tflint** | Terraform/OpenTofu linter -- catches errors before apply |
| **terraform-docs** | Auto-generate module README sections from variables and outputs |
| **checkov** | IaC static analysis -- Terraform, CloudFormation, Kubernetes, Dockerfile |
| **infracost** | Cost estimation for Terraform changes before apply |
| _tfsec_ | _Folded into `trivy config` -- not installed separately_ |

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
| `man` | **tldr** (tlrc) | Community-driven simplified man pages with examples |
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
| `wc` (code) | **scc** | Count lines of code by language + complexity + COCOMO cost estimate |
| `watch` | **viddy** | Modern watch with diff highlighting and history |
| `hexdump` | **hexyl** | Colorized hex viewer with ASCII sidebar |
| `curl`/`wget` | **aria2** | Multi-connection parallel downloads, 3-10x faster, BitTorrent |
| `tar`/`unzip`/`7z` | **ouch** | Universal archive tool -- auto-detects format from extension |
| `rm` | **trash** | Moves files to macOS Trash instead of permanent delete |
| `rsync` | **rsync** (latest) | Updated rsync with better progress and Apple metadata |
| `tree` | **tree** | Directory listing in tree format |
| `make` | **just** | Modern task runner -- simpler syntax, no tab weirdness |
| file manager | **rovr** | Mouse-first, VS Code-Explorer-style TUI file manager (Textual); `nnn` kept as a fast fallback |
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
| **jc** | Convert many classic CLI outputs into JSON so they pipe cleanly into `jq` and automation |
| **jqp** | Interactive jq playground / TUI -- explore JSON while iterating on jq filters |
| **pandoc** | Universal document converter -- Markdown to PDF, DOCX, HTML, etc. |
| **tectonic** | Self-contained LaTeX/PDF engine so pandoc can render PDFs (`pandoc in.md -o out.pdf --pdf-engine=tectonic`) -- a bare Mac has no PDF engine |
| **poppler** | PDF tools -- `pdftoppm` (PDF→PNG), `pdftotext`, `pdfinfo` |
| **imagemagick** | Image manipulation CLI -- resize, convert, composite, watermark |
| **ffmpeg** | Video/audio processing swiss army knife |
| **yt-dlp** | Video/audio downloader for YouTube and hundreds of other sites |
| **surge** | TUI download manager (MIT) -- a browser extension captures browser-started downloads and routes them to a background daemon (port 1700). Complements aria2 (aria2 = scriptable CLI; surge = interactive + browser capture) |

---

## Code Quality

| Tool | Description |
|------|-------------|
| **shellcheck** | Shell script linter -- catches bugs and bad practices |
| **shfmt** | Shell script formatter -- consistent style for bash/zsh scripts |
| **actionlint** | GitHub Actions workflow linter -- catches workflow/expression/job wiring mistakes plain YAML parsing misses |
| **act** | Run GitHub Actions locally before pushing (`.actrc` forces `linux/amd64` on Apple Silicon) |
| **act3** | Glance at the last 3 GitHub Actions runs (`gha3` alias) |
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
| **leaf** | Terminal Markdown previewer -- live watch, fuzzy picker, Mermaid/LaTeX, inline mode |
| **mprocs** | TUI for running multiple dev processes side by side -- frontend/backend/worker/watchers in one terminal surface |
| **broot** | Keyboard-driven directory tree and file navigation TUI with shell handoff |
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
| **qalc** | Powerful terminal calculator (units, currencies, variables) |
| **doxx** | Read/preview `.docx` files in the terminal |
| **vhs** | Script terminal recordings to GIF/MP4 (for demos/docs) |
| **wiper** | Interactive disk-usage cleanup (ncdu-like, Trash-safe) |
| **jolt** | Battery/power status at a glance |
| **has** | Check for the presence/version of CLIs on PATH |
| **lazyssh** | TUI SSH connection manager |
| **starlit** | Terminal weather (run `starlit --setup` for an API key) |
| **kondo** | Clean dependency/build cruft from software projects across many ecosystems |

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
| **duckdb** | Local analytical SQL database -- query CSV/JSON/Parquet and ad hoc datasets with SQL |
| **pgcli** | Auto-completing PostgreSQL CLI with syntax highlighting |
| **mycli** | Auto-completing MySQL CLI with syntax highlighting |
| **lazysql** | TUI for databases -- interactive SQL queries in terminal |
| **harlequin** | Terminal SQL IDE -- multi-tab, autocomplete, DuckDB/Postgres/MySQL/S3 |
| **usql** | Universal SQL CLI -- connects to Postgres, MySQL, SQLite, and more |
| **sq** | jq for databases -- query SQLite, Postgres, CSV from one tool |
| **dbmate** | Lightweight, framework-agnostic database migration tool |
| **harlequin / lazysql** | Terminal SQL IDE + DB TUI (replaced the DBeaver GUI); plus pgcli, mycli, usql, sq |

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
| **ATAC** | Terminal API client (TUI + scriptable CLI) -- Postman import, git-friendly JSON/YAML collections; replaced the Bruno GUI |
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
| **croft** | Primary editor -- VS Code-style terminal IDE (Rust; `cargo install --git`). Three-pane workspace, LSP/DAP, integrated terminal; `croft pair` runs an AI navigator (Anthropic/local). Installed from git `main`, with a managed Dracula-Sakura theme extension and config |
| **Visual Studio Code** | The GUI editor, secondary to croft -- for long multi-tab refactors, graphical diffs, and `.editorconfig` repos (croft has no EditorConfig support). Ships 26 extensions and a merged `settings.json` that mirrors the terminal's rules -- including basedpyright as the Python type server, matching croft |
| **micro** | The `$EDITOR` -- git/gh/lazygit commit messages, leaf's Ctrl+E, quick edits. Non-modal, on-screen key menu (`Ctrl+G` for help), Dracula theme |
| **Claude Code (`claude`)** | Agentic coding in the terminal; hosts the migrated MCP servers |
| **GitHub Copilot CLI** | `copilot` -- installed from `@github/copilot` (a standalone npm package now, not a `gh` extension). The VS Code side needs no install: current VS Code ships Copilot **built in**, and installing the marketplace extension fails against the newer bundled `copilot-chat`. Proprietary -- a deliberate exception to the open-source preference |
| **llm** | Simon Willison's CLI -- one-shot prompts, plugin ecosystem, SQLite logging, embeddings. Installed via `uv tool` with the Anthropic plugin; default model `anthropic/claude-sonnet-4-5` |
| **aichat** | All-in-one AI CLI chat / shell copilot -- lighter than a full coding agent, with local Ollama support and a configurable REPL |
| **pi** | A second, deliberately minimal coding agent -- four core tools, custom Dracula-Sakura theme, curated shared skills, and local Ollama models wired through `~/.pi/agent/` |
| **omp** | Oh My Pi -- the maximalist fork of pi, installed from the `can1357/tap` Homebrew tap. 32 tools, LSP, a DAP debugger, subagents, and nine model roles routed at Google Gemini through `~/.omp/agent/`. Shares pi's theme, preferences, and skill bridge. Needs `GEMINI_API_KEY` |
| **chezmoi** | Dotfile manager -- backup and restore configs across machines |
| **mitmproxy** | Free HTTP debugging proxy -- inspect and modify API calls from any app |
| **Ghostty** | Fast GPU-accelerated terminal -- daily driver, native macOS feel |
| **zellij** | Modern terminal multiplexer -- discoverable UI, layouts, Rust-based |
| **Ghostty quick terminal + `a`/`ff`/`rgf`/`s`** | Terminal launcher & search (global cmd+space dropdown) replacing Raycast/Spotlight; **clipse** for clipboard history; **SketchyBar** status bar |
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
| **d2 / Mermaid** | Diagrams as code in the terminal (replaced the draw.io GUI) |

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


---

## Mac Apps -- System & Utilities

| App | Description |
|-----|-------------|
| **Pearcleaner** | Open-source deep app uninstaller -- finds leftover files and preferences |
| **LuLu** | Free open-source outbound firewall -- see what phones home |
| **Mullvad VPN** | Privacy-focused VPN -- no account required, anonymous payment accepted |
| **dockutil** | Manage Dock pins programmatically (used by the setup script to curate the Dock) |
| **terminal-notifier** | Send macOS notifications from shell scripts (used by the setup script for run-complete/failure alerts) |

---

## Mac Apps -- Productivity

| App | Description |
|-----|-------------|
| **tiki** | Terminal Markdown workspace -- tasks, docs, kanban, wiki (git-backed); replaced the Notion GUI. Its official Claude Code skill is installed to `~/.claude/skills/tiki/`, so Claude manages notes/tasks via `tiki exec` (ruki) |
| **herald** | Terminal email **+** calendar in one app -- Gmail (work) + iCloud (personal), unified CalDAV, built-in AI triage/summaries + an MCP server for Claude; replaced aerc + khal + vdirsyncer + Notion Calendar. Theme-integrated with a local Dracula-Sakura theme asset and a narrow config merge |
| **gws** (google-workspace-cli) | One CLI for Drive/Gmail/Docs/Sheets/Calendar/Chat with structured JSON output -- Claude's read/query surface for Workspace (`gws auth login` first; instructed to confirm before any mutation). A **scoped set of gws Claude skills -- Drive/Docs/Slides/Sheets/Forms only** -- is installed to `~/.claude/skills/` (Gmail/Calendar/Chat/Meet excluded); the real access boundary is the OAuth scopes granted at `gws auth`, not the skills |
| **Shottr** | Fast native screenshots -- scrolling capture, OCR, annotations (local-only, no account) |
| **Claude** | AI assistant |
| **Skim** | Lightweight PDF reader with annotations -- faster than Preview |
| **LibreOffice** | Headless office suite -- `soffice --headless --convert-to` lets Claude validate/convert .pptx/.xlsx/.docx (authoring stays in Google Workspace) |
| **office-py** | uv venv (python-docx/openpyxl/python-pptx) exposed on PATH so Claude can assert on office-file *content*, not just render it |
| **rclone** | SFTP/S3/cloud file transfer from the terminal (replaced the Cyberduck GUI) |

---

## Mac Apps -- Browsers

| App | Description |
|-----|-------------|
| **Google Chrome** | Primary Chromium browser for development and DevTools |

---

## Mac Apps -- Media

| App | Description |
|-----|-------------|
| **mpv** | Terminal video player -- keyboard-driven, scriptable |
| **oxipng** | Lossless PNG compression -- CLI, scriptable, CI-friendly |
| **jpegoptim** | Lossless JPEG compression -- strip metadata, optimize |
| **p7zip** | Archive tool -- zip, 7z, rar, tar from the command line |

---

## Mac Apps -- Cloud Storage & Backup

| App | Description |
|-----|-------------|
| **rclone** | Sync files to any cloud -- Google Drive, S3, Dropbox, etc. (replaced the Google Drive desktop app) |
| **borg** | Deduplicated encrypted backups -- better than Time Machine for offsite |
| **borgmatic** | Automated borg backup scheduling and configuration |

---

## Mac Apps -- Focus & Learning

| App | Description |
|-----|-------------|
| **newsboat** | Terminal RSS/Atom reader -- vim-like keybindings, highly configurable |

---

---

## Dracula-Sakura Theme

Applied consistently across the machine, with built-in Dracula variants kept where a tool exposes only a named theme:

| Tool | How |
|------|-----|
| **micro** | Dracula (`dracula-tc`) set in `settings.json` |
| **VS Code** | Dracula Official as the base theme, with a Dracula-Sakura workbench/token/terminal overlay in merged `settings.json` |
| **bat** | Dracula syntax theme in config |
| **delta** | Dracula syntax theme for git diffs |
| **Ghostty** | Full 16-color Dracula-Sakura palette in config |
| **croft** | Custom Dracula-Sakura theme extension in `~/.config/croft/extensions/` |
| **jqp** | Dracula base theme with Dracula-Sakura override colors in `~/.jqp.yaml` |
| **fzf** | Dracula colors in `FZF_DEFAULT_OPTS` |
| **Starship** | Dracula-Sakura palette in `starship.toml` |
| **lazygit** | Dracula-Sakura color scheme in config |
| **k9s** | Dracula skin recolored to the Dracula-Sakura house palette |
| **leaf** | Terminal Markdown previewer (runs on defaults) |
| **gh-dash** | Dracula-Sakura border, text, and selection colors |
| **SketchyBar** | Dracula-Sakura status bar (palette in `colors.sh`) |
| **btop** | Full Dracula-Sakura theme with custom color palette |
| **lazydocker** | Dracula-Sakura borders and options colors |
| **broot** | Custom Dracula-Sakura skin in `~/.config/broot/skins/` |
| **harlequin** | Built-in Dracula theme set in `~/.harlequin.toml` |
| **trippy** | Dracula-Sakura `theme-colors` in `~/.config/trippy/trippy.toml` |
| **zellij** | Dracula-Sakura theme in the config |
| **newsboat** | Dracula-Sakura colors in the config |
| **aichat** | Dracula-Sakura dark TextMate theme plus rose/lilac prompt colors in config |
| **herald** | Local Dracula-Sakura YAML theme in `~/.herald/themes/` with `theme.name` merged safely into `conf.yaml` |
| **pi** | Full Dracula-Sakura custom theme in `~/.pi/agent/themes/dracula-sakura.json` |
| **omp** | Full Dracula-Sakura custom theme in `~/.omp/agent/themes/dracula-sakura.json`, selected through `theme.dark` in `config.yml` |
| **claws** | Built-in `dracula` theme via `claws --theme dracula` alias |
| **miniserve** | `--color-scheme-dark dracula` in the `serve` alias |
| **vivid** | Dracula-themed LS_COLORS for file type coloring |
| **vim** | Dracula-ish color scheme (no plugin needed) |
| **macOS** | System highlight color set to Dracula purple |

---

## Claude Code Configuration

The script sets up Claude Code with a comprehensive configuration for full-stack development.

### Files Created

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Global permissions, file ignore patterns, env vars |
| `~/.claude/CLAUDE.md` | Global memory -- coding standards, available CLI tools reference, React/Next.js/AWS/CDK/Python/IaC conventions, security checks runbook |
| `~/.claude/rules/workflow.md` | Trunk-based workflow rules (PR-first, issues, README-driven) |
| `~/.claude/rules/git.md` | Git rules (no force-push, conventional commits, branch naming) |
| `~/.claude/rules/security.md` | Security rules (no hardcoded secrets, parameterized SQL) |
| `~/.claude/rules/typescript.md` | TypeScript rules (strict mode, no any, zod schemas) |
| `~/.claude/rules/python.md` | Python rules (uv for packages, ruff for linting, type hints, pydantic) |
| `~/.claude/rules/docker.md` | Docker rules (multi-stage builds, non-root, hadolint, dive) |
| `~/.claude/rules/iac.md` | IaC rules (remote state, tflint, infracost, trivy config scan) |
| `~/.claude/rules/style.md` | Voice rules (calm and concise, Dracula-Sakura when there is stylistic latitude) |
| `~/.claude/rules/writing.md` | Writing rules -- the 53 rules of ASD-STE100 Simplified Technical English. Strict on commits, PRs, specs, and technical docs; mechanical subset only on issues, wikis, and chat. pi and omp get the identical text at the tail of `~/.pi/agent/AGENTS.md` and `~/.omp/agent/AGENTS.md` |
| `~/.claude/hooks/format-on-edit.sh` | Auto-format with Prettier after Claude edits JS/TS/CSS/JSON/MD files |
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
| `/init-project` | Scaffold new project with git, README, AGENTS.md, linting, CI, Docker, templates |
| `/refactor` | Refactor code with tests preserved, SOLID principles, verify tests pass |
| `/add-endpoint` | Add full API endpoint: types, handler, validation, tests, docs |
| `/add-component` | Add React component: TSX, tests, props interface, accessibility |
| `/ci-fix` | Diagnose CI failures with `gh run view`, fix, verify locally with `act` |
| `/changelog` | Generate changelog from conventional commits grouped by type |
| `/commit-msg` | Analyze staged changes and generate conventional commit message |
| `/probe-assumptions` | Pressure test a document or plan by surfacing hidden assumptions |
| `/probe-evidence` | Audit whether a document's claims are well supported |
| `/probe-implications` | Trace first and second order consequences of a proposal |

### Permissions Pre-approved

The allowlist is deliberately **read-heavy and scoped** -- Claude runs safe local inspection, linting, formatting, and a small set of low-risk helpers without asking, but package installs, remote fetches/model calls, trust-store changes, deploys, and broader state mutation still prompt:
- **Read-only git**: `git status/diff/log/show/branch`, `git remote -v`, `git stash list` (no writes; `gh` is *not* pre-approved)
- **npm**: `npm run/test` only (`npm install`, pnpm/bun/npx/uv/cargo/pip prompt)
- **Inspect & data**: cat, bat, ls, eza, grep, rg, fd, fzf, tree, head, tail, wc, sort, uniq, cut, jq, yq, fx, mlr, csvlook, jnv, mdfind, scc, dust, diff, difft, delta
- **Linters/formatters/tests**: shellcheck, shfmt, prettier, eslint, ruff, hadolint, typos, ast-grep, tsc, jest, vitest
- **IaC (read-only)**: tflint, terraform-docs, checkov, infracost (no `aws`/`cdk`/`sam`/`tofu`)
- **Security scanners**: trivy, semgrep, gitleaks, cosign
- **Read-only TUIs**: k9s, stern, lazygit, lazydocker, dive, btop, procs, lnav (no `docker`/`kubectl`/`docker-compose`)
- **Docs & media**: pandoc, d2, mmdc, ffmpeg, magick, manly, soffice, office-py, pdftoppm/pdftotext/pdfinfo, oxipng, jpegoptim, mpv
- **DB clients**: pgcli, mycli, sq, lazysql
- **Misc CLIs**: atac, hurl, trippy, bandwhich, gping, doggo, gum, leaf, qalc, has, doxx, harlequin/hq, git-cliff, git-absorb, act3, commitizen, commitlint, tiki exec, fastfetch, newsboat, zellij
- **Tool permissions**: `Read`, `Edit`

### Denied Commands

Destructive commands are always blocked:
- `rm -rf /`, `rm -rf /*`, `rm -rf ~`, `sudo rm *`, `chmod 777 *`, `> /dev/sda*`, `mkfs *`

---

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
| `git-lfs-enable-repo` | `lfsinit` | Enable Git LFS hooks for one repo (LFS is per-repo here, not global) |

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
| `~/.config/mprocs/mprocs.yaml` | mprocs | 5k scrollback, wider proc list, per-process logs under the config dir |
| `~/.config/croft/config.json` + theme extension | croft | Dracula-Sakura theme, terminal-first layout defaults, explorer/status bar preferences |
| `~/.config/starship.toml` | Starship | Rich two-line prompt with a Dracula-Sakura palette, OS icon, git status with counts, Node/Python/Rust/Go/Docker/AWS/Terraform versions, battery warning, time, Nerd Font icons |
| `~/.config/yt-dlp/config` | yt-dlp | Best quality mp4, aria2c downloader, metadata, subtitles |
| `~/.config/gh-dash/config.yml` | gh-dash | PR/issue sections, Dracula-Sakura theme |
| `~/.config/stern/config.yaml` | stern | 50 tail lines, 5m lookback, timestamps |
| `~/Library/Application Support/ngrok/ngrok.yml` | ngrok | Base config (add authtoken). ngrok's real macOS path — **not** `~/.config/ngrok`, which it never reads; a stranded copy there is removed on the next run |
| `~/.config/caddy/Caddyfile` | Caddy | Development server template |
| `~/.config/asciinema/config.toml` | asciinema | 2s idle limit, no keystroke recording. TOML, for asciinema 3.x — a 2.x `config` left beside it is removed on the next run |
| `~/.config/micro/settings.json` | micro | Dracula (`dracula-tc`), the $EDITOR for git/gh/lazygit and leaf's Ctrl+Ents, auto-format on save (ruff for Python, taplo/marksman/TS/CSS/bash/yaml servers, rust-analyzer, gopls) |
| `~/Library/.../Code/User/settings.json` | VS Code | Dracula Official + Dracula-Sakura accent layer, format-on-save, ruff + basedpyright (Python; Pylance disabled), prettier (web), shfmt (shell), tabs for Go, LF, telemetry off. **Merged, not overwritten** — your keys and Settings Sync win |
| `~/.config/sketchybar/` | SketchyBar | Dracula-Sakura bar: app, clock, battery, wifi, volume, cpu, mem, bluetooth, VPN |
| `~/Media/photos/dracula-sakura.jpg` | Wallpaper | Bundled Dracula-Sakura wallpaper asset copied onto every provisioned machine |
| _(cliamp)_ | cliamp | Music player — self-configured on first run (point at `~/Media/music`) |
| `~/.herald/themes/dracula-sakura.yaml` + `~/.herald/conf.yaml` | herald | Local Dracula-Sakura theme asset plus a narrow merge of `theme.name`; accounts/credentials remain user-owned |
| `~/.config/zellij/config.kdl` | zellij | Dracula-Sakura theme, compact layout, mouse, Ctrl-a prefix |
| `~/.config/mpv/mpv.conf` | mpv | Hardware accel, save position, screenshots to ~/Screenshots |
| `~/.config/git-cliff/cliff.toml` | git-cliff | Conventional commits changelog template |
| `~/.config/broot/conf.hjson` + skin | broot | Git-aware defaults plus a custom Dracula-Sakura skin |
| `~/.jqp.yaml` | jqp | Dracula base theme with Dracula-Sakura color overrides |
| `~/.config/aichat/config.yaml` + `dark.tmTheme` | aichat | Local Ollama defaults, prompt behavior, document loaders, Dracula-Sakura dark theme |
| `~/.pi/agent/settings.json` | pi | Dracula-Sakura theme, telemetry/analytics off, `micro` as external editor, local Ollama defaults (`qwen2.5-coder:14b`) |
| `~/.pi/agent/AGENTS.md` | pi | Global Pi instruction layer: Dracula-Sakura house voice, durable context rules, token discipline, anti-trope writing guidance |
| `~/.pi/agent/models.json` | pi | Registers four local Ollama chat/coding models; the embedding-only `nomic-embed-text-v2-moe` stays machine-local for herald/aichat and is intentionally not exposed as a Pi chat model |
| `~/.pi/agent/themes/dracula-sakura.json` | pi | Full Dracula-Sakura theme with all required Pi color tokens |
| `~/.pi/agent/extensions/searxng-web.ts` | pi | Local SearXNG-backed web tools: `searxng_search`, `searxng_fetch`, plus `/searxng-check` |
| `~/.pi/agent/skills/*` | pi | Pi-local skills: Tiki companions (`tiki-capture`, `tiki-review`, `tiki-groom`, `tiki-arc`, `tiki-journal`) plus `searxng-web` for local web research |
| `~/.pi/agent/settings.json` (`packages`) | pi | Pins the third-party `bigpowers` Pi package so its extension / skills / prompts load reproducibly |
| `~/.agents/skills/*` | pi, omp | Symlinks to the curated shared skills (`api-testing`, `d2-diagrams`, `dbmate-migrations`, `office-docs`, `tiki`). omp treats this directory as its own native skills location, so it needs no separate wiring |
| `~/.omp/agent/AGENTS.md` | omp | Global Oh My Pi instruction layer: the same house preferences and writing rules as pi, from the same generators. Outranks every other user-level context file, `~/.claude/CLAUDE.md` included |
| `~/.omp/agent/themes/dracula-sakura.json` | omp | Full Dracula-Sakura theme with all 66 required omp color tokens, including the thirteen status-line colors pi has no equivalent for |
| `~/.omp/agent/config.yml` | omp | Merged, not managed-block written, because `omp config set` and `/settings` write this file themselves. Carries `theme.dark` and nine Gemini model roles with a fallback chain |
| `~/.newsboat/config` | newsboat | Vim keys, Dracula-Sakura colors, auto-reload |
| `~/.newsboat/urls` | newsboat | Starter RSS feeds (Claude Code, Node, Rust, GitHub) |
| `~/.config/nushell/env.nu` | nushell | Starship prompt, Homebrew paths |
| `~/.config/ghostty/config` | Ghostty | JetBrainsMono Nerd Font, Dracula-Sakura palette, transparent titlebar |
| `~/.config/fastfetch/config.jsonc` | fastfetch | Nerd Font icons, package counts, Node/Python/Go/Rust/Docker versions, battery, disk, colored output |
| `~/.config/mise/config.toml` | mise | Auto-install, trust ~/Code |
| `~/.config/topgrade.toml` | topgrade | Cleanup, greedy cask updates |
| `~/.config/direnv/direnv.toml` | direnv | Hidden env diff, auto-trust ~/Code, load .env |
| `~/.config/btop/` | btop | Dracula-Sakura theme with full color palette |
| `~/.config/lazydocker/` | lazydocker | Dracula-Sakura theme, timestamps, compose support |
| `~/.config/pip/pip.conf` | pip | Require virtualenv, no telemetry |
| `~/.config/pgcli/config` | pgcli | Multi-line, auto-expand, destructive warnings, bat pager |
| `~/.harlequin.toml` | harlequin | Built-in Dracula theme, vscode keymap, file tree on |
| `~/.config/gh/config.yml` | GitHub CLI | SSH protocol, micro editor, delta pager, aliases (co, pv, pc, pl, il, pm, rel) |
| `~/.config/glab-cli/config.yml` | GitLab CLI | SSH, micro; same alias names as gh mapped to GitLab merge requests + CI |
| `~/.aws/config` | AWS CLI | Default region, json output, bat pager, auto-prompt, SSO template |
| `~/.config/git/hooks/` | git | Global pre-commit hooks (debug statements, large files >5MB, conflict markers) |
| `~/.config/brewfile/Brewfile` | Homebrew | Snapshot of all installed packages with descriptions |
| `~/.justfile` | just | 26 global task-runner recipes (system, git, Docker, network, cleanup, info) |
| `~/.shellcheckrc` | shellcheck | External sources, disabled false positives |
| `~/.config/k9s/config.yaml` + skin | k9s | Dracula skin recolored to the Dracula-Sakura house palette (edit-resource uses your `$EDITOR`) |
| `~/.config/leaf/config.toml` | leaf | Ctrl+E hands off to micro at the current line |
| `~/.config/trippy/trippy.toml` | trippy | Dracula-Sakura theme-colors |
| `~/.tflint.hcl` | tflint | Recommended preset + AWS ruleset (fetched via `tflint --init`) |
| `~/.czrc` | commitizen | Points `cz` at the cz-conventional-changelog adapter |
| `~/.actrc` | act | Ubuntu images, container reuse, `--container-architecture linux/amd64` |
| `~/.mlrrc` | miller | Pretty-print output, CSV I/O defaults |
| `~/.ripgreprc` | ripgrep | Smart-case, hidden files, custom type definitions |
| `~/.w3m/config` | w3m | UTF-8, cookies off, colors, proxy-from-env |
| `~/.zshenv` | Shell | mise activation for all shell types (login + non-login) — coverage. mise is activated **again** at the end of `~/.zshrc` for *precedence*: `.zshenv` runs first, so everything prepended afterwards (`brew shellenv`, gnubin, `~/.local/bin`, `$PNPM_HOME`) would otherwise outrank it |
| `~/.actrc` | act | Medium Ubuntu images, container reuse |
| `~/.mlrrc` | miller | CSV input, pretty table output |
| `~/.hushlogin` | Terminal | Suppresses "Last login" message |
| `~/.ripgreprc` | ripgrep | Smart case, hidden files, ignore patterns, custom types (web, config, doc, style) |
| `~/.fdignore` | fd | Global ignore patterns (node_modules, .git, dist, etc.) |
| `~/.vimrc` | vim | Line numbers, clipboard, mouse, Dracula colors, space leader, persistent undo |
| `~/.nanorc` | nano | Line numbers, auto-indent, mouse, syntax highlighting |
| `~/.myclirc` | mycli | Multi-line, auto-expand, destructive warnings |
| `~/.gemrc` | Ruby | No docs on gem install |
| `~/.claude.json` (mcpServers) | Claude Code MCP | User-scope MCP servers (migrated from Kiro via `claude mcp add`) — filesystem, github, git, fetch, context7, aws-docs, aws-pricing, aws-iac, aws-knowledge, cloudwatch, iam, herald, GitKraken. Opt-in per project: playwright, postgres, several AWS servers. (Notion server dropped.) |
| `~/.config/lazygit/config.yml` | lazygit | Dracula-Sakura theme, delta pager, nerd fonts, auto-fetch, micro editor (`hx`), rounded borders |
| `~/.config/k9s/skins/dracula.yaml` | k9s | Full Dracula-Sakura-colored skin |
| `~/.local/bin/*` (36 links) | mise | Symlinks to every mise shim except the Python family and `corepack`, so `claude`, `prettier`, `tsc`, `copilot` and the language servers are reachable from git hooks, launchd and GUI-launched editors — not only from zsh, where `mise activate` runs |

---

## macOS System Defaults

| Category | Changes |
|----------|---------|
| **Dock** | Auto-hide, small icons (40px), no recents, scale minimize, no delay, spacers, all default pins cleared |
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
| `make` | `just` | Task runner |
| `y` | `rovr` | File manager (`n` → nnn fallback) |
| `a` / `ff` / `rgf` / `s` | launcher / find / grep / mdfind | Terminal launcher & search (replaces Raycast/Spotlight) |
| `clip` | `clipse` | Clipboard-history TUI |
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
| `md` | `leaf` | Markdown viewer |
| `serve` | `miniserve ...` | Quick file server |
| `ghd` | `gh dash` | GitHub dashboard |
| `gdft` | `git dft` | Syntax-aware git diff |
| `gha` | `act` | Run GitHub Actions locally |
| `gha3` | `act3` | Glance at the last 3 Actions runs |
| `hq` | `harlequin` | SQL IDE TUI |
| `claws` | `claws --theme dracula` | All-AWS TUI (Dracula) |
| `prog` | `progress -m` | Monitor progress of running coreutils |
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
| `lfsinit` | `git-lfs-enable-repo` | Enable Git LFS hooks for this repo |

### Shell Extras

| Feature | Description |
|---------|-------------|
| **Zsh completions** | kubectl, gh, aws auto-completions loaded |
| **GPG_TTY** | Set in zshrc for commit signing to work |
| **ulimit increase** | `ulimit -n 65536` in zprofile for Node.js/webpack/vite |
| **vivid LS_COLORS** | Dracula-themed file type coloring via `vivid generate dracula` |
| **fzf config** | Dracula colors, fd for file finding, bat for preview, eza tree for directory preview, keybindings (ctrl-/ toggle preview, ctrl-y copy) |
| **Plugin guards** | Zsh plugin sources have defensive `[[ -f ]]` guards |
| **Terminal welcome** | fastfetch + date + random dev tip on new terminal sessions |

---

## Language Servers

The script installs language servers on `PATH` for **croft**, the primary editor, so it has
completion, diagnostics, go-to-definition and format-on-save out of the box. They are plain
LSP binaries, so any editor that speaks LSP picks them up:

| Language | Server | Install |
|----------|--------|---------|
| Python | ty (types) + basedpyright (fallback) + ruff (lint) | uv tool |
| TypeScript / JS | typescript-language-server | npm |
| HTML / CSS / JSON / ESLint | vscode-langservers-extracted | npm |
| YAML | yaml-language-server | npm |
| Bash | bash-language-server | npm |
| TOML | taplo | brew |
| Markdown | marksman | brew |
| Rust | rust-analyzer | rustup component |
| Go | gopls | go install |

Python runs three servers at once, which is croft's own built-in arrangement — `ty` (Astral's type
server) at priority 0, `basedpyright` as the fallback for what `ty` does not yet advertise, and
`ruff` for lint. Previously only `ruff` was installed, so Python had lint and formatting but no
type checking or go-to-definition.

### AI agent — Claude Code (+ croft integration)

Agentic coding is handled by **Claude Code** (`claude`) in the terminal, which reuses
the MCP servers below. (Kiro's agent/specs/steering/hooks are gone with Kiro; Claude
Code plus your `~/.claude/CLAUDE.md` rules cover the same ground.)

Claude is wired into the terminal tools in four tiers:

| Tier | How | Best for |
|------|-----|----------|
| **1. Side-pane** | `zellij --layout dev` — editor + a `claude` pane | Real, multi-file, agentic work (strongest) |
| **2. croft pair** | `croft pair` — AI navigator inside the primary IDE | In-editor pairing while you code |
| **3. `llm` pipe** | `llm` from the shell — pipe a file or selection | Quick one-shot edits |
| **4. herald** | Built-in AI triage/summaries + MCP server (email/calendar) | Reading + triaging mail/events |

Set `ANTHROPIC_API_KEY` (for `croft pair`) and run `llm keys set anthropic` (for the
`llm` pipe bind). The script installs `llm` via `uv tool` with the `llm-anthropic`
plugin and sets the default model to `anthropic/claude-sonnet-4-5`, so only the key is
left to add.

### Secondary agent — Pi

**Pi** (`pi`) is also installed as a deliberately smaller coding harness: four core tools,
a custom Dracula-Sakura theme under `~/.pi/agent/themes/`, a small Pi-local skill set
under `~/.pi/agent/` — Tiki companions in `skills/` (`tiki-capture`, `tiki-review`,
`tiki-groom`, `tiki-arc`, `tiki-journal`), a `searxng-web` research skill, and a local
SearXNG-backed web extension in `extensions/searxng-web.ts` that exposes
`searxng_search`, `searxng_fetch`, and `/searxng-check` — plus the pinned third-party
`bigpowers` package through Pi's `packages` setting, and a curated five-skill bridge via
`~/.agents/skills/` (`api-testing`, `d2-diagrams`, `dbmate-migrations`, `office-docs`,
`tiki`). Its config is written under `~/.pi/agent/`, not `~/.config`.

The default Pi path here is **local Ollama**, with `qwen2.5-coder:14b` as the startup
model and three other local chat/coding models registered alongside it. The embedding-only
`nomic-embed-text-v2-moe` model still exists on the machine for herald/aichat, but is
intentionally **not** exposed as a Pi chat model. If you want a remote provider instead,
run `pi` and then `/login`.

What Pi is **not** in this setup: not the MCP-capable agent, not the mail/calendar/AWS/GitHub
surface, and not the place for the broadest automation. That remains **Claude Code**.
Pi is the smaller loop for local model work and tight edit/bash sessions.

### Third agent — Oh My Pi

**Oh My Pi** (`omp`) is the maximalist fork of Pi by can1357, installed from the
`can1357/tap` Homebrew tap rather than npm: the package is a Bun program
(`engines.bun >= 1.3.14`), and the tap ships a prebuilt native binary into
`$HOMEBREW_PREFIX/bin`, where `sh`, git hooks, and launchd can all see it.

Where Pi keeps four tools and delegates the rest, omp brings 32 built-in tools, 13 LSP
operations, a real debugger over DAP, subagents, a curated memory, and nine model roles
that route by intent. This setup points all nine at **Google Gemini**:

| Roles | Model | Why |
| --- | --- | --- |
| `default`, `task`, `vision` | `gemini-3.8-flash` | Ordinary turns, 1M context |
| `slow`, `plan`, `advisor` | `gemini-3.1-pro-preview` | The three roles where depth pays for itself. `advisor` is the second model watching every turn, so it reviews rather than generates |
| `smol`, `tiny`, `commit` | `gemini-3.1-flash-lite` | Cheap subagent fan-out |

`gemini-3.1-pro-preview` is the only Gemini Pro on the API today and preview ids can be
retired without notice, so `retry.fallbackChains` pins an exact-model fallback to Flash.
An unknown model id surfaces as a config warning at startup rather than failing quietly.

It shares everything visual and behavioral with Pi: the same Dracula-Sakura theme, the
same `AGENTS.md` preferences and writing rules (both generated by one emitter, so they
cannot drift), and the same five shared skills. Nothing extra is generated for skills,
because `~/.agents/skills/` is omp's own canonical location rather than a foreign import.

Two things worth knowing. Its `~/.omp/agent/AGENTS.md` has the highest precedence of any
user-level context file, so it **shadows** `~/.claude/CLAUDE.md` in omp sessions instead
of stacking with it. And `~/.omp/agent/config.yml` is written by omp itself, so this
setup **merges** into it with `yq` rather than owning it with a managed block.

**Authentication is yours.** omp's `google` provider reads `GEMINI_API_KEY` from the
environment; the setup never writes, reads, or echoes a key. Export it from wherever you
keep secrets, then confirm with `omp config get modelRoles`.

> `modelRoles` is a **record**, so it reads as a whole and not by sub-key.
> `omp config get modelRoles.default` answers `Unknown setting`, which reports a
> schema shape rather than a missing value.

### Claude Code MCP Servers

The script registers user-scope MCP servers with `claude mcp add --scope user` (stored
in `~/.claude.json` — never hand-edited). Enabled everywhere:

| Server | Purpose | Notes |
|--------|---------|-------|
| **filesystem** | Read/list/search files in `~/Code` | `@modelcontextprotocol/server-filesystem` (npx) |
| **github** | Search repos, read files, list issues/PRs | needs `GITHUB_TOKEN` env var |
| **git** | `git status/diff/log/show` | `mcp-server-git` (uvx) |
| **fetch** | HTTP fetch with HTML->Markdown | `mcp-server-fetch` (uvx) |
| **context7** | Up-to-date library docs by package name | `@upstash/context7-mcp` (npx) |
| **herald** | Email + calendar (Gmail/iCloud) read/search tools | `herald mcp`; mutations require `herald serve` running |
| **aws-docs / aws-pricing / aws-iac** | AWS docs, cost estimation, IaC patterns | `awslabs.*` (uvx) |
| **aws-knowledge** | AWS knowledge base | **Remote HTTP** — `https://knowledge-mcp.global.api.aws`. No auth, no AWS account, rate-limited. The only non-stdio server here |
| **cloudwatch / iam** | CloudWatch logs + metrics; read IAM | `awslabs.*` (uvx); need AWS creds |
| **GitKraken** | 31 tools — `git_*` porcelain, PR/issue read + create, Launchpad | `gk mcp` (gitkraken-cli cask), `--no-telemetry` |

Opt-in per project with `claude mcp add --scope project <name> ...`: playwright,
postgres, aws-ccapi, aws-serverless, aws-lambda-tool, aws-eks, aws-ecs, aws-dynamodb.
(The Notion MCP server was dropped along with Notion.)

**AWS setup:** the AWS servers use the standard AWS credential chain — anything that works for `aws sts get-caller-identity` works here. Three common setups:

```bash
# 1) Long-lived access keys (least preferred)
aws configure                       # writes ~/.aws/credentials

# 2) AWS SSO via `granted` (installed under the `aws` module)
assume <profile>                    # exports AWS_PROFILE for the shell

# 3) Per-shell env vars (CI-style)
export AWS_REGION=us-east-1
export AWS_PROFILE=my-dev-account
```

Claude Code reads `${AWS_REGION}` and `${AWS_PROFILE}` from your shell environment. The AWS MCP servers are read-leaning, and Claude Code prompts before any tool call that mutates state (e.g. IAM `create_role`, `attach_role_policy`).

---

## Chrome Extensions (manual install)

| Extension | Purpose |
|-----------|---------|
| **axe DevTools** | Accessibility testing |
| **React Developer Tools** | React component inspection |
| **Lighthouse** | Performance and accessibility audits |
| **JSON Formatter** | Pretty-print JSON in the browser |

---

## Terminal Launcher & Window Management (replaces Raycast/Spotlight)

| Key / command | Action |
|---------------|--------|
| `cmd + space` | Ghostty quick terminal (global dropdown) — after disabling Spotlight's shortcut |
| `a` | Fuzzy-launch an app · `ff` find a file · `rgf <q>` search contents · `s <q>` mdfind |
| `clip` | Clipboard history (clipse) |
| `taproom` · `k9s` · `lazydocker` | Homebrew · Kubernetes · Docker TUIs |

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
