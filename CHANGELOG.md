# Changelog

> Release notes for 7.0.0–7.1.1 live in [GitHub Releases](https://github.com/vixygrey/vixygrey-dev-setup/releases) (auto-generated). This file resumes hand-written notes at 7.2.0.

## [Unreleased]

### Added

- **mac-productivity**: Install **`reminders-cli`** (`keith/formulae`, binary `reminders`) so Apple Reminders are reachable from the terminal — the one gap between the existing productivity tools, since `tiki` keeps tasks in git and `herald` owns mail and calendar events, but neither can create an alert that follows you to iPhone/Watch via iCloud. The generated `CLAUDE.md` now draws that three-way line explicitly and tells Claude that "remind me" means this tool, with reads free and mutations gated on explicit user intent. Only the read-only verb is auto-approved in `settings.json` (`Bash(reminders show*)`) — `add`/`complete`/`delete` still prompt. Ships a `TOOL_REFERENCE.md` entry and a checklist step for the one-time macOS Reminders consent prompt, which is granted to the terminal rather than to the binary and silently yields empty results until approved (#208)

### Changed

- **cleanup**: `--cleanup` now removes the **orphaned support trees left behind by the VS Code / Kiro / Cursor casks** it already uninstalls. Homebrew only ever owned the `.app`, so `~/.vscode`, `~/.kiro`, `~/.cursor` and their `~/Library/Application Support` counterparts survived every run — ~1.5 GB across 73 extension folders on the maintainer's machine, for three editors long since replaced by Helix + Claude Code. A tree is only touched when its `.app` is genuinely absent, so a manual reinstall is never gutted, and removal prefers `trash` over `rm -rf` so a mistake is recoverable (#210)

### Fixed

- **claude**: Correct five tool references in the generated `CLAUDE.md` that named the **Homebrew package instead of the binary**, so Claude was being told to run commands that do not exist — `csvkit` → `csvlook`/`in2csv`/`csvjson`, `aws-sam-cli` → `sam`, `dynein` → `dy`, `nushell` → `nu`, `imagemagick` → `magick`. Same class as the `Bash(trippy *)` rule fixed in #206 (the binary is `trip`) (#209)
- **code-quality**: Install **prettier**. The generated `CLAUDE.md` mandates it, the pre-push checklist runs it, and the script already writes a global `.prettierrc` — but it was never actually installed, so the Claude `format-on-edit` hook found nothing on PATH and silently no-opped. Installed from brew so it survives mise Node switches. The hook now prefers a project's **own** prettier over the global one, so a repo pinning 2.x is not reformatted by 3.x (#209)
- **script**: `--list-categories` now renders from `CATEGORY_DESC` instead of a second hardcoded copy. The two lists had drifted apart in **seven** categories — `act3`, `ni`, `Objective-See`, `monolith`, `terminal-notifier`, `fx`, and most of `terminal-productivity` (`nnn`, `cheznav`, `apw`, `has`, `starlit`) appeared in one but not the other — so the flag and the interactive picker described the same category differently. One source of truth means it cannot recur (#209)
- **typos**: `typos .` now passes repo-wide, so the pre-push spell-check step is actionable instead of always red. Allowlisted five project-specific identifiers the default dictionary misreads: `keyward` (SSH-key manager), `clearn` (the `~/Code/learning` alias), `PNGs`, `SLQ` (sq's query language, not a transposed SQL), and `wrk` (the load-testing tool) (#209)

- **claude**: Repair the generated `settings.json` **PostToolUse hooks**, which were schema-invalid and therefore **never ran on any machine this script has provisioned**. Entries were emitted as `{matcher, command}`, but the schema requires a nested `hooks` array (`{matcher, hooks:[{type,command}]}`) — Claude Code reported `Expected array, but received undefined` and silently skipped all three hooks (auto-format, ruff, hadolint). The three entries now collapse into a single `Edit|Write` entry (#206)
- **claude**: Drop the **`fileSuggestionSettings`** key from the generated settings — Claude Code does not implement it (0 occurrences in the shipped binary), so its 20 ignore patterns were inert. Build/dependency dirs were already excluded via each repo's `.gitignore` (`respectGitignore` defaults to true); the genuinely-unfiltered noise is the *committed* kind, so the script now writes a global **`~/.ignore`** covering lock files, minified bundles, and sourcemaps instead. Note this also applies to ripgrep searches under `$HOME` (#206)
- **claude**: Retarget the generated `permissions.deny` list from **Linux to macOS** — `> /dev/sda*` → `> /dev/disk*`, `mkfs *` → `diskutil erase*` / `diskutil partitionDisk*` / `newfs_*` — and add the `rm -fr` and `~/*` spellings the original literal-prefix rules missed. These remain fat-finger guardrails, not a security boundary (#206)
- **claude**: Make the `format-on-edit.sh` prettier hook actually fire. It gated on a global `prettier` that this script never installs, so it no-opped even once wired correctly; it now falls back to the project-local copy via `npx --no-install prettier` and recognises five more config filenames (`.prettierrc.yaml/.yml/.js/.mjs`, `prettier.config.mjs`) (#206)
- **claude**: **Migrate existing installs.** The `configs` block only writes the full settings heredoc when `~/.claude/settings.json` is absent, so already-provisioned machines took the jq merge path and would never have been repaired. That path now normalizes legacy `{matcher, command}` hook entries across every hook event, drops `fileSuggestionSettings`, migrates the deny list, and strips stale allow entries (`Bash(trippy *)` — the binary is `trip` — and `Bash(wc -l *)`, already covered by `Bash(wc *)`). The migration is idempotent and leaves user-added rules and custom keys untouched (#206)

## [7.5.0] - 2026-08-10

Deepens the Claude Code integration: a scoped set of Google Workspace (`gws`) skills, four first-party skills for installed tools (`office-docs`, `d2-diagrams`, `dbmate-migrations`, `api-testing`), and a project `CLAUDE.md`. Also fixes the global pre-commit hook's false positives and switches the terminal to a Nerd Font. No breaking changes.

### Added

- **claude**: Add three more first-party skills for installed tools — **`d2-diagrams`** (diagrams as code: d2 primary, mermaid fallback), **`dbmate-migrations`** (schema migrations following the global DB conventions), and **`api-testing`** (headless HTTP/gRPC via hurl/xh/curlie/grpcurl; atac as the TUI) (#203)
- **claude**: Add a first-party **`office-docs` skill** (`~/.claude/skills/office-docs/`) wrapping the local Office-file render→see→assert loop (`soffice` → `pdftoppm` → `pdftotext`/`doxx` → `office-py`), scoped to local files (authoring stays in Workspace; cloud files use `gws`). The generated `CLAUDE.md` now points at it and at Claude Code's bundled `docx`/`pptx`/`xlsx`/`pdf` skills (#199)
- **docs**: Add a root **`CLAUDE.md`** documenting repo conventions for AI agents — the script is a generator (edit heredocs, not output), the managed-block/idempotency/`--dry-run` patterns, the `bash -n` + ShellCheck + `--dry-run` verification loop, the global pre-commit hook's regenerate-on-re-run behavior and `debug-ok` whitelist, heredoc quoting, changelog-on-every-PR, and the `trash`/`bat` alias gotchas (#197)
- **script**: Install a scoped set of **24 `gws` Claude skills** — 10 service skills + 14 recipes covering **Drive/Docs/Slides/Sheets/Forms only** — into `~/.claude/skills/`, refreshed each run. Gmail/Calendar/Chat/Meet skills are deliberately excluded, and `recipe-create-feedback-form` is dropped because it depends on `gws-gmail`. The generated `CLAUDE.md` now lists exactly which skills/recipes Claude has and notes that skills are not an access boundary; the post-setup checklist gains an **OAuth-fence reminder** (authorize only the five services' scopes at `gws auth setup`) (#193)

### Changed

- **ghostty**: Set the terminal `font-family` to **`JetBrainsMono Nerd Font`** (was plain `JetBrains Mono`) so glyph icons — eza, starship, lazygit, Claude Code, etc. — render natively instead of relying on font fallback. The Nerd Font was already installed and is the same family SketchyBar uses (#201)

### Fixed

- **hooks**: The global pre-commit hook is now **language-aware** — the debug-statement check scans only the file types each token belongs to (JS/TS for `console.log`/`debugger`, Python for pdb/`breakpoint()`, Ruby for `binding.pry`), so shell scripts and markdown that merely *mention* those tokens are no longer rejected (this repo's own script previously required `--no-verify`); a trailing `debug-ok` comment whitelists an intentional line. The merge-conflict-marker check is anchored to line start and requires the trailing space real markers carry, so markdown setext headings (`=======`) no longer false-flag (#195)

## [7.4.0] - 2026-08-09

Adds comprehensive on-machine tool documentation, fills gaps in the post-setup checklist, and fixes the Google Workspace CLI install. No breaking changes.

### Added

- **docs**: New Desktop doc **TOOL_REFERENCE.md** — a categorized reference of every user-facing installed tool (~195 entries) with a plain-English description and worked usage examples, generated fresh on every run alongside the other Desktop docs (#190)
- **checklist**: The manual auth/first-run steps that were missing — `gh auth login` (the PR workflow assumed it), AWS auth (`aws configure sso` / `granted` / `assume`, plus `steampipe plugin install aws`), and optional `atuin` cross-machine history sync (#190)

### Changed

- **docs**: `TOOLKIT_SUMMARY.md` now points at `TOOL_REFERENCE.md` so its curation is intentional; clarify the window-management wording in the generated CLAUDE.md to `native macOS Spaces + built-in window tiling (no tiling WM)` now that AeroSpace is gone (#190, #186)

### Fixed

- **script**: Install the **`googleworkspace-cli`** formula for the `gws` command instead of Homebrew's core `gws` (which is *git-workspace*, an unrelated tool); the two share a `gws` binary and conflict, so the conflicting formula is removed first and existing machines self-correct on the next run (#188, #189)

## [7.3.0] - 2026-08-09

Captures the maintainer's macOS defaults, drops AeroSpace in favor of native Spaces + Zellij, and fixes several login/MCP papercuts. No breaking changes.

### Added

- **macos**: Capture this machine's Finder, trackpad, and appearance settings so fresh installs reproduce them — Finder view settings (Desktop + "Use as Defaults" for all windows), desktop drive visibility, new-window target, keep the empty-trash warning; trackpad tap-to-click/secondary-click/gesture prefs; and **Dark mode** (#180)

### Changed

- **wm**: Remove **AeroSpace** — window management moves to **Zellij** (terminal density) + **native macOS Spaces & tiling** (GUI). SketchyBar stays, minus the workspace pills; revert `spans-displays` so multi-monitor gets per-display Spaces back; keep `mru-spaces=false` (fixed Space order). AeroSpace added to `--cleanup` so existing machines uninstall it (#182)
- **filesystem**: Consolidate `~/Docs` into the default `~/Documents` (reverses the 6.0.0 rename) — one Documents folder, sidebar de-duplicated; life-admin buckets + tiki notes repo move under `~/Documents` (#178)
- **sketchybar**: Wifi pill is icon-only — drop the SSID label from the menu bar (#179)

### Fixed

- **mcp**: The github / cloudwatch / iam MCP servers now register — `claude mcp add`'s variadic `-e` flag was eating the server name; reordered to `<name> ... -e KEY=val --` (#177)
- **ghostty**: Auto-start launches Ghostty in the **background** (`open -g`) instead of hidden (`-gj`) so the global cmd+space quick-terminal hotkey registers after login (it never did from a hidden launch) (#183)
- **script**: Restore the executable bit on `setup-dev-tools-mac.sh` (#181); drop the stale "hot corners" line from the run summary and suppress the `universalaccess` write error (#176)

## [7.2.0] - 2026-08-09

Makes a batch of installed tools actually work out of the box, hardens macOS/login integration, and reconciles the README with the script. No breaking changes.

### Added

- **ghostty**: Auto-start Ghostty at login via a LaunchAgent so the global `cmd+space` quick-terminal hotkey survives logout/reboot (#145)
- **leaf**: Point leaf's `Ctrl+E` editor at Helix instead of nano — leaf ignores `$EDITOR`, so `~/.config/leaf/config.toml` now sets `editor = 'hx {$path}:{$line}'` (#147)
- **git**: Set the personal identity as the **global default** committer so commits outside `~/Code/{work,personal}` still work; the work `includeIf` still overrides it there (#172)
- **macos**: Auto-disable Spotlight's `cmd+space` (symbolichotkeys 64/65) so it no longer collides with Ghostty; register Quick Look generators with `qlmanage -r` so `.md`/plain-text previews activate immediately (#167)
- **backups**: Scaffold a commented `~/.config/borgmatic/config.yaml`; seed ClamAV's `freshclam.conf` and register a daily virus-DB updater LaunchAgent (#171)
- **theme**: Dracula theming for trippy (`theme-colors`), d2 (`$D2_THEME`), and claws (`--theme dracula`) (#172)

### Changed

- **llm**: Install `llm` via `uv tool ... --with llm-anthropic` instead of Homebrew (brew's externally-managed llm can't install the plugin) and default the model to `anthropic/claude-sonnet-4-5`, so the Helix `Alt+a` pipe reaches Claude (#166)
- **commitizen / tflint / act / pandoc**: Wire the `cz-conventional-changelog` adapter (`~/.czrc`); write `~/.tflint.hcl` with the AWS ruleset (`tflint --init`); add `--container-architecture linux/amd64` to `~/.actrc`; install `tectonic` so pandoc can render PDFs (#166)
- **macos**: Gate the Time Machine exclusions on a configured TM destination (skip when unused — backups run via borg/rclone/rsync); drop the hot-corner defaults (macOS default is already off), keeping only `mru-spaces=false` as a required AeroSpace prerequisite (#173)

### Fixed

- **shell**: Source fzf before atuin so atuin owns `Ctrl-R` (was shadowed by fzf); de-duplicate the direnv hook (`.zprofile` + `.zshrc` fired it twice); add `alias assume="source assume"` so granted can export AWS creds into the shell (#165)
- **docs**: Document the Shottr Screen Recording and SketchyBar Automation/Accessibility permissions in the post-setup checklist; flag the infracost API key (#167, #171)
- **readme**: Reconcile the README with the script — correct the Claude Code permission allowlist (read-only/scoped, not full write access) and its counts, the Apple-bloat table (GarageBand only, no SIP), removed wallpaper/hot-corner claims, and add missing tools, config files, aliases, and the herald MCP server (#173, #174)

## [6.0.0] - 2026-07-27

**BREAKING:** Removes the `mac-communication` category (both Slack and Telegram are dropped), so `--only mac-communication` / `--skip mac-communication` are no longer valid category names. Also restructures the `~/` filesystem layout (see Changed) — re-running on an existing machine creates the new folders alongside the old ones; it does not migrate or delete existing files. Curates the installed app set for a solo fractional CIO/CTO consulting workflow (Google Workspace); run `--cleanup` to uninstall the retired apps (#39).

### Added

- **editor**: Re-add `visual-studio-code`, installed alongside Kiro and sharing a single extension list (`EDITOR_EXTENSIONS`) via a new `install_editor_extensions` helper — Kiro resolves from OpenVSX, VS Code from the Microsoft Marketplace. Grants `Bash(code *)` in the Claude Code allowlist (#39)
- **apps**: Add `bruno` (local-first, git-friendly API client), `dbeaver-community` (universal DB GUI), `cyberduck` (SFTP/S3/cloud transfer), `shottr` (native screenshots with scrolling capture + OCR), and `drawio` (offline architecture/system diagrams) (#39)
- **filesystem**: Add an `~/Inbox` dump zone, pinned first (with `~/Downloads`) in the Finder sidebar, for a lower-friction, ADD-friendly layout. Starship gains `Inbox`/`Docs`/`Archive` directory icons (#39)
- **claude**: Expand the generated global `~/.claude/CLAUDE.md` — a fuller Environment section plus a new Working Context section (Google Workspace, open-source/CLI/privacy/minimal tooling philosophy, and the ADD-friendly home-folder layout) (#39)

### Changed

- **filesystem**: Restructure `~/` for fewer top-level roots and shallower nesting — `~/Documents` (10 nested subfolders) becomes a flat `~/Docs` (finance, health, admin, receipts, travel); `~/Reference`, `~/Projects`, and `~/Creative/assets/*` are collapsed; `~/Archive` becomes a single bucket. `~/Code` is intentionally unchanged (aliases, per-directory git identity, mise/direnv trust, and the MCP filesystem scope depend on it) (#39)
- **api**: Replace `postman` with `bruno`. **database**: replace `tableplus` with `dbeaver-community`. **file-transfer**: replace `transmit` with `cyberduck`. **screenshots**: replace `snagit` with `shottr`. Each retired tool's `--cleanup` entry now points at its replacement (#39)

### Removed

- **apps**: Drop `brave-browser`, `firefox`, `slack`, `telegram`, `notion-mail`, and `libreoffice` from install (all moved to the `--cleanup` deprecation list). `zed` added to `--cleanup` as well (it was never installed by the script) (#39)
- **mas**: Drop the `mas` (Mac App Store CLI) install entirely — nothing was being installed via the App Store anymore, which had left `mas` both installed and marked-for-removal. `--cleanup` still removes any leftover `mas` and old App Store apps via the `/Applications` fallback. Removes `Bash(mas *)` from the Claude Code allowlist (#39)
- **category**: Remove the now-empty `mac-communication` category (#39)

## [5.0.0] - 2026-06-18

### Added

- **script**: Interactive category picker — run with `--interactive` / `-i` to select which categories to install from a checkbox menu instead of passing `--only` / `--skip` (closes #35, #36)

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
