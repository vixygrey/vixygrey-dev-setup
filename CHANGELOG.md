# Changelog

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
