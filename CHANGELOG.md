# Changelog

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
