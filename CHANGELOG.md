# Changelog

## [4.1.0] - 2026-05-10

Minor release rolling up two follow-up PRs to v4.0.0: a tool-discoverability audit (#31) and the AWS MCP / toolkit fleet (#32). Fully backward-compatible.

### Added

- **kiro/mcp**: Add 11 AWS MCP servers backed by [awslabs/mcp](https://awslabs.github.io/mcp/). Five enabled by default (read-only or autoApprove-reads-only): `aws-pricing` (no AWS creds needed), `aws-iac` (CDK + Terraform + CloudFormation patterns, replaces the deprecated cdk-mcp-server), `aws-knowledge` (broader knowledge base), `cloudwatch` (Logs/Metrics queries, read ops only auto-approved), `iam` (read/simulate only auto-approved — every mutation still prompts). Six written disabled-by-default for opt-in per workspace: `aws-ccapi` (Cloud Control API CRUD), `aws-serverless` (SAM lifecycle), `aws-lambda-tool` (call deployed Lambdas as agent tools), `aws-eks`, `aws-ecs`, `aws-dynamodb`. All use `${AWS_REGION}` / `${AWS_PROFILE}` from the launching shell (#32)
- **kiro/extensions**: Add `amazonwebservices.aws-toolkit-vscode` (local Lambda debugging via SAM, CloudFormation/SAM YAML schemas, ECS exec terminal, AWS resource explorer, credential/SSO management) and `kddejong.vscode-cfn-lint` (template linter, pairs with the `cfn-lint` CLI). Both verified on OpenVSX (#32)
- **docs**: README documents the AWS credential setup chain (`aws configure`, AWS SSO via `granted`/`assume`, explicit env vars) and the Notion integration sharing model (#32)

### Fixed

- **path**: Add `~/.local/bin` to `.zprofile` and the managed `.zshrc` block. `uv tool install` (and `pipx`) put persistent binaries there — without this, `harlequin` and anything else the user installs via `uv tool install` was unreachable as a bare command (#31)
- **kiro/mcp**: Pre-expand `npx` and `uvx` to absolute paths in `~/.kiro/settings/mcp.json`. Kiro is a GUI app; when launched from Finder, Spotlight, or Raycast it inherits launchd's restricted PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), not the user's interactive shell PATH. Bare `"command": "npx"` silently failed to spawn MCP servers for any user who didn't launch Kiro from a terminal — the most common launch path. Same well-known issue as Claude Desktop. Resolution chain falls back to `/opt/homebrew/bin` then `/usr/local/bin` if `brew --prefix` fails (#31)
- **claude**: Refresh the Claude Code Bash permission allowlist with 36 entries covering v4.0.0 additions (`kiro`, `aider`, `llm`, `repomix`, `uvx`) plus 30+ tools installed by earlier versions that had never been allowlisted (`mas`, `dockutil`, `terminal-notifier`, `harlequin`, `granted`, `assume`, `topgrade`, `git-absorb`, `mkcert`, `mitmproxy`, `bandwhich`, `nmap`, `procs`, `btop`, `trash`, `yt-dlp`, `parallel`, `lnav`, `glow`, `fastfetch`, etc.). 169 allow entries total. `claude *` deliberately excluded as recursive (#31)

## [4.0.0] - 2026-05-10

**BREAKING:** VS Code is replaced with **Kiro** (AWS's agentic IDE — VS Code fork with built-in Claude agent, specs, steering, hooks, MCP). Re-running the script on a v3.x machine will leave VS Code in place but switch the toolchain (`EDITOR`, lazygit, yazi, `gh`) to point at `kiro`. Run `--cleanup` to also uninstall the now-deprecated `visual-studio-code` cask.

### Changed

- **editor**: Replace `visual-studio-code` cask with `kiro`. Settings move from `~/Library/Application Support/Code/User/` to `~/Library/Application Support/Kiro/User/`. CLI symlink installs into `$(brew --prefix)/bin/kiro` so it lands on PATH on both Apple Silicon and Intel. `EDITOR`/`VISUAL`, `gh editor`, lazygit edit/editAtLine, and yazi opener all switch from `code` to `kiro` (#24)
- **extensions**: Curate the auto-installed extension list for **OpenVSX** (Kiro's registry — Microsoft Marketplace closed-source extensions are unavailable). Drop `github.copilot` (Kiro ships its own Claude agent, redundant). Add `charliermarsh.ruff`, `astro-build.astro-vscode`, `svelte.svelte-vscode`, `editorconfig.editorconfig`, `davidanson.vscode-markdownlint`, `hashicorp.terraform` (#24)
- **keybindings**: Keep the 21 VS Code muscle-memory bindings; add three Kiro-specific ones — `⌘I` (open agent chat), `⌘⇧I` (inline edit with agent), `⌘⇧S` (create a spec from a one-line ask) (#24)
- **gitignore template**: Editor section now covers both `.vscode/` and `.kiro/` layouts; `.kiro/.cache`, `.kiro/.tmp`, `.kiro/local` are ignored while `.kiro/steering`, `.kiro/specs`, `.kiro/hooks`, and `.kiro/settings/mcp.json` stay version-controlled by default (#24)
- **terminal welcome**: Skip the fastfetch banner in both `TERM_PROGRAM=vscode` and `TERM_PROGRAM=kiro` integrated terminals (#24)
- **docs**: Replace VS Code sections in README, GUIDE, and SHORTCUTS with Kiro equivalents — covering OpenVSX, the four agent primitives (steering / specs / hooks / MCP), the Kiro + Claude Code workflow, and the new keybindings (#24)

### Added

- **kiro/mcp**: Auto-write a global MCP server config at `~/.kiro/settings/mcp.json` with sensible defaults — **filesystem, github, git, fetch, context7, aws-docs, notion** enabled and **playwright, postgres** written disabled (opt-in). Token references (`${GITHUB_TOKEN}`, `${NOTION_TOKEN}`) are kept literal so Kiro substitutes them at runtime; `$HOME` is pre-expanded at install time so the filesystem server gets a real path (#24)
- **dx**: Add agentic AI CLIs that pair with Claude Code + Kiro — `aider` (terminal AI pair programmer with git-aware edit loops), `llm` (Simon Willison's CLI for one-shot prompts, plugins, SQLite logging, embeddings), `repomix` (pack a repo into a single LLM-friendly file with token counts) (#26, #29)
- **iac**: Add `terraform-docs` (auto-generate module README sections from variables/outputs) and `checkov` (IaC static analysis — Terraform, CloudFormation, Kubernetes, Dockerfile). Note: `tfsec` is no longer installed standalone — its checks are folded into `trivy config`, which is already installed under `security`. Wired into the iac rules, the `/iac-review` slash command (now runs both trivy + checkov + terraform-docs), and the Claude Code Bash allowlist (#27, #29)

### Fixed

- **state**: Truncate `~/.local/share/dev-setup/completed-items.txt` on non-resume runs. `mark_done` always appends; `is_done` only checks the state file when `--resume` is passed. Without truncation, the file grew unbounded across repeated runs. `--resume` runs are preserved so previous successes can short-circuit (#28, #29)

## [3.2.0] - 2026-04-29

### Changed

- **Dock**: Stop pinning a curated app list (Finder, System Settings, VS Code, Ghostty, Raycast) on setup — Dock contents are personal preference. Enable Dock auto-hide by default (`com.apple.dock autohide = true`). `dockutil` is still installed for manual Dock management (#20)
- **ci**: Bump GitHub Actions runtimes to Node 24 (#18)

### Added

- **repo**: Version-controlled GitHub repository ruleset for `main` at `.github/rulesets/main.json` (PR-only, squash-merge, ShellCheck required, force pushes / branch deletion blocked, linear history, admin bypass) plus apply/update instructions in `.github/rulesets/README.md`. Already applied live (#22)

## [3.1.0] - 2026-04-23

### Added

- **tools**: Add `mas` (Mac App Store CLI), `dockutil` (Dock management), and `terminal-notifier` (macOS notifications) to the `mac-system` category (#15, #16)
- **script**: Emit a macOS notification at end of run — success notification with install/skip/fail counts and duration, or failure notification with error log path if any step errored (uses `terminal-notifier`, no-op if not installed)

### Changed

- **Dock**: Replace the `defaults write persistent-apps -array` clearing block with a `dockutil` sequence that removes all defaults then pins a curated set (Finder, System Settings, VS Code, Ghostty, Raycast). Any app not present on disk is skipped with a warning, so partial installs still succeed. Falls back to the previous clear-only behavior if `dockutil` isn't installed (#15, #16)

## [3.0.0] - 2026-04-23

**BREAKING:** Linux and Windows support removed. This is now a macOS-only project.

### Added

- **tools**: Add `ouch` (universal archive tool) and `harlequin` (terminal SQL IDE) to the macOS setup, with `hq` alias and Dracula-themed `~/.config/harlequin/config.toml` (#11)
- **repo**: Wire up `.pre-commit-config.yaml` (shellcheck via `shellcheck-py`, gitleaks, typos, file-hygiene hooks) and `.typos.toml` (#11)

### Removed

- **platforms**: Drop Linux and Windows support (#12, #13). Deleted `scripts/setup-dev-tools-linux.sh`, `scripts/setup-dev-tools-windows.ps1`, and their per-platform `docs/GUIDE-*` / `docs/SHORTCUTS-*` files. Remaining macOS docs renamed to `docs/GUIDE.md` and `docs/SHORTCUTS.md`. CI workflows simplified to ShellCheck-only; release workflow now produces a single macOS zip.

## [2.2.0] - 2026-04-23

### Changed

- **api**: Replace Bruno with Postman as the API client across mac (brew cask `postman`), linux (snap/flatpak `com.getpostman.Postman`), and windows (winget `Postman.Postman`) (#8)

### Removed

- **editors**: Remove Zed editor install and `~/.config/zed/settings.json` config block from all three setup scripts; VS Code is now the sole configured editor (#8)

## [2.1.0] - 2026-04-13

### Features

- **browsers**: Add Carbonyl (Chromium-based terminal browser) to mac/linux/windows browsers categories (#1)
- **tools**: Add seven terminal CLI tools across platforms (#3):
  - `w3m` and `monolith` in browsers
  - `cmus` in media
  - `nnn` and `progress` in terminal-productivity (mac + linux)
  - `act3` in code-quality
  - `sshclick` in networking (linux only)
- **aliases**: Add `gha3` → `act3` (all platforms); `n` → `nnn -de`, `prog` → `progress -m` (mac + linux); `sshc` → `sshclick` (linux) (#5)
- **configs**: Generate default `~/.config/cmus/rc` (Dracula palette, replaygain) and `~/.w3m/config` (UTF-8, cookies off) on mac + linux (#5)
- **configs**: Export `NNN_OPTS`, `NNN_COLORS`, `NNN_FCOLORS`, `NNN_PLUG` in managed zshrc block (#5)

### Documentation

- Document all new tools in `GUIDE-MACOS.md`, `GUIDE-LINUX.md`, `GUIDE-WINDOWS.md` with usage examples (#5)
- Update `SHORTCUTS-*.md` with new alias rows and a "Terminal Apps" section (#5)

## [Unreleased]

### Bug Fixes

- **ci**: Remove unused variables, exclude remaining PSScriptAnalyzer rules
- **ci**: Use system shellcheck, exclude false-positive PSScriptAnalyzer rules
- Local-outside-function error, firewall detection, and remove tmux
- Resolve install failures, Safari sandbox errors, and progress bar rendering
- Resolve 99 issues across all three setup scripts

### Documentation

- Update README to reflect mysides replacement with LSSharedFileList API
- Split documentation into per-platform self-contained guides

### Miscellaneous

- Pre-publication audit — shellcheck fixes, CI, configs sync
- Rename setup-dev-tools.sh to setup-dev-tools-mac.sh
- Reorganize project structure

### Refactoring

- Remove tmux (replaced by zellij), replace Proton suite with Mullvad VPN
