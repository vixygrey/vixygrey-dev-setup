# Keyboard Shortcuts & Aliases Reference

Quick reference for all **219+ shortcuts** configured by the setup scripts.

---

## Shell Aliases

### Modern Tool Replacements

| Alias | Runs | What it does |
|-------|------|-------------|
| `ls` | `eza --icons` | Colorful file listing with icons |
| `ll` | `eza -la --icons --git` | Long listing with git status |
| `la` | `eza -a --icons` | List all including hidden |
| `lt` | `eza --tree --icons --level=3` | Tree view (3 levels deep) |
| `cat` | `bat --paging=never` | Syntax-highlighted file viewer |
| `top` | `btop` | Graphical system monitor |
| `du` | `dust` | Visual disk usage tree |
| `df` | `duf` | Colorful disk usage table |
| `ps` | `procs` | Sortable process list (Docker-aware) |
| `ping` | `gping` | Real-time latency graph |
| `dig` | `doggo` | Colorized DNS lookup (DoH/DoT) |
| `watch` | `viddy` | Watch with diff highlighting |
| `hexdump` | `hexyl` | Colorized hex viewer |
| `rm` | `trash` | Move to Trash (recoverable) |
| `make` | `just` | Simpler task runner |
| `f` | `fd` | Fast file finder |
| `dft` | `difft` | Syntax-aware structural diff |
| `y` | `yazi` | Terminal file manager |
| `jx` | `fx` | Interactive JSON viewer |

### Downloads & Network

| Alias | Runs | What it does |
|-------|------|-------------|
| `dl` | `aria2c` | Multi-connection downloader |
| `wget` | `aria2c` | Download with 16 connections |

### Git & GitHub

| Alias | Runs | What it does |
|-------|------|-------------|
| `lg` | `lazygit` | Interactive git terminal UI |
| `ghd` | `gh dash` | GitHub dashboard (PRs, issues) |
| `gdft` | `git dft` | Syntax-aware git diff |
| `gha` | `act` | Run GitHub Actions locally |

### Containers & Kubernetes

| Alias | Runs | What it does |
|-------|------|-------------|
| `lzd` | `lazydocker` | Interactive Docker UI |
| `k` | `kubectl` | Kubernetes CLI |
| `klog` | `stern` | Multi-pod log tailing |

### Python (via uv)

| Alias | Runs | What it does |
|-------|------|-------------|
| `pip` | `uv pip` | Fast pip (10-100x faster) |
| `venv` | `uv venv` | Fast virtualenv creation |
| `pyrun` | `uv run` | Run Python scripts with uv |

### Media & Conversion

| Alias | Runs | What it does |
|-------|------|-------------|
| `md` | `glow` | Render Markdown in terminal |
| `serve` | `miniserve --color-scheme-dark dracula -qr .` | Quick file server |
| `csvp` | `csvlook` | Pretty-print CSV as table |
| `ytdl` | `yt-dlp` | Download video |
| `ytmp3` | `yt-dlp -x --audio-format mp3` | Download audio as MP3 |
| `resize` | `magick mogrify -resize` | Resize images |
| `ffq` | `ffmpeg -hide_banner -loglevel warning` | Quiet ffmpeg |
| `md2pdf` | `pandoc -f markdown -t pdf` | Markdown to PDF |
| `md2html` | `pandoc -f markdown -t html -s` | Markdown to HTML |
| `md2docx` | `pandoc -f markdown -t docx` | Markdown to Word |

### Dev & Testing

| Alias | Runs | What it does |
|-------|------|-------------|
| `gj` | `just --justfile ~/.justfile --working-directory .` | Global justfile recipes |
| `watchrun` | `find . -name '*.ts' -o -name '*.tsx' \| entr -r` | Watch & rerun on changes |
| `bench` | `hyperfine` | Benchmark commands |
| `loadtest` | `oha` | HTTP load testing |
| `par` | `parallel` | GNU parallel |
| `lint-sh` | `shellcheck` | Lint shell scripts |
| `fmt-sh` | `shfmt -w -i 4` | Format shell scripts |

### Directory Shortcuts (via zoxide)

| Alias | Jumps to | What it does |
|-------|----------|-------------|
| `cw` | `~/Code/work` | Work projects |
| `cper` | `~/Code/personal` | Personal projects |
| `coss` | `~/Code/oss` | Open source |
| `clearn` | `~/Code/learning` | Learning/courses |
| `cscratch` | `~/Code/work/scratch` | Scratch experiments |
| `cscripts` | `~/Scripts` | Custom scripts |

### Helper Scripts

| Alias | Script | What it does |
|-------|--------|-------------|
| `nproj` | `new-project` | Scaffold project with git + .editorconfig |
| `cwork` | `clone-work` | Clone work repo into `~/Code/work/<org>/<repo>` |
| `cpers` | `clone-personal` | Clone personal repo into `~/Code/personal/<repo>` |
| `dotback` | `backup-dotfiles` | Push dotfiles via chezmoi |
| `pstats` | `project-stats` | Show repo counts, disk usage |
| `cleandl` | `clean-downloads` | Delete old files from ~/Downloads |
| `hc` | `health-check` | System health overview |
| `sshsetup` | `setup-ssh` | Generate SSH key + add to GitHub |
| `brewsnap` | `export-brewfile` | Export Brewfile snapshot |

### System

| Alias | Runs | What it does |
|-------|------|-------------|
| `update` | `topgrade` | Update everything (brew, npm, pip, OS) |
| `sysinfo` | `fastfetch` | Quick system info display |

---

## VS Code Keybindings

| Key | Action |
|-----|--------|
| `Cmd+`` ` | Toggle terminal |
| `Cmd+Shift+`` ` | New terminal |
| `Cmd+\` | Split editor |
| `Cmd+1` / `2` / `3` | Focus editor group 1/2/3 |
| `Cmd+P` | Quick open file |
| `Cmd+Shift+O` | Go to symbol in file |
| `Cmd+T` | Go to symbol in workspace |
| `Cmd+B` | Toggle sidebar |
| `Cmd+Shift+M` | Toggle minimap |
| `Cmd+Shift+[` | Fold code block |
| `Cmd+Shift+]` | Unfold code block |
| `Alt+Up/Down` | Move line up/down |
| `Cmd+Shift+D` | Duplicate line |
| `Cmd+Shift+K` | Delete line |
| `Cmd+D` | Multi-select next match |
| `Cmd+Shift+L` | Select all occurrences |
| `Cmd+Shift+F` | Format document |
| `F2` | Rename symbol |
| `Cmd+.` | Quick fix |
| `Cmd+W` | Close editor tab |
| `Cmd+Shift+T` | Reopen closed editor |

> Windows/Linux: Replace `Cmd` with `Ctrl`.

---

## tmux Keybindings

**Prefix:** `Ctrl+A` (changed from default `Ctrl+B`)

| Key (after prefix) | Action |
|---------------------|--------|
| `r` | Reload config |
| `\|` | Split pane horizontally |
| `-` | Split pane vertically |
| `c` | New window (in current path) |
| `h` / `j` / `k` / `l` | Navigate panes (vim-style) |
| `H` / `J` / `K` / `L` | Resize panes (vim-style, repeatable) |
| `v` (copy mode) | Begin selection |
| `y` (copy mode) | Copy to clipboard |

| Key (no prefix) | Action |
|------------------|--------|
| `Alt+Left/Right/Up/Down` | Navigate panes directly |

**Plugins (via TPM):**
| Key | Action |
|-----|--------|
| `prefix + I` | Install plugins |
| `prefix + Ctrl+S` | Save session (tmux-resurrect) |
| `prefix + Ctrl+R` | Restore session (tmux-resurrect) |

---

## Vim Keybindings

**Leader key:** `Space`

| Key | Mode | Action |
|-----|------|--------|
| `Space+W` | Normal | Save file |
| `Space+Q` | Normal | Quit |
| `Space+H` | Normal | Clear search highlights |
| `Ctrl+H/J/K/L` | Normal | Navigate splits (vim-style) |
| `Ctrl+D` | Normal | Half-page down (centered) |
| `Ctrl+U` | Normal | Half-page up (centered) |
| `J` | Visual | Move selection down |
| `K` | Visual | Move selection up |

---

## fzf Keybindings

### Shell Integration

| Key | Action |
|-----|--------|
| `Ctrl+T` | Search files and paste path (uses fd + bat preview) |
| `Alt+C` | Search directories and cd into it (uses fd + eza tree preview) |
| `Ctrl+R` | Search shell history (handled by atuin) |

### Inside fzf

| Key | Action |
|-----|--------|
| `Ctrl+/` | Toggle preview window |
| `Ctrl+D` | Page down in results |
| `Ctrl+U` | Page up in results |
| `Ctrl+Y` | Copy selection to clipboard |

**Visual config:** Prompt: `>`, Pointer: `>`, Marker: checkmark. Dracula color scheme. Height 60%, reverse layout, rounded border.

---

## Git Aliases

Use as `git <alias>`, e.g., `git st`, `git lg`, `git undo`.

### Basics

| Alias | Command | What it does |
|-------|---------|-------------|
| `st` | `status -sb` | Short status with branch |
| `co` | `checkout` | Checkout |
| `br` | `branch` | List branches |
| `ci` | `commit` | Commit |
| `sw` | `switch` | Switch branch |

### Undo & Reset

| Alias | What it does |
|-------|-------------|
| `unstage` | Unstage files (keep changes) |
| `undo` | Undo last commit (keep changes staged) |
| `discard` | Discard all working directory changes |
| `amend` | Amend last commit (same message) |

### Quick Commits

| Alias | What it does |
|-------|-------------|
| `wip` | Stage all + commit "WIP" |
| `save` | Stage all + commit "chore: savepoint" |

### Stash

| Alias | What it does |
|-------|-------------|
| `stash-all` | Stash including untracked files |
| `stash-peek` | Preview stash contents |

### Log & History

| Alias | What it does |
|-------|-------------|
| `last` | Last commit with file stats |
| `lg` | Pretty graph log (all branches) |
| `log-stats` | Commits with file change stats |
| `log-since` | Commits from the last week |
| `contributors` | Contributors ranked by commits |
| `standup` | Your commits since yesterday |

### Branch Management

| Alias | What it does |
|-------|-------------|
| `recent` | 15 most recent branches by commit date |
| `cleanup` | Delete branches merged into main |
| `gone` | Delete branches whose remote is gone |

### Diff

| Alias | What it does |
|-------|-------------|
| `dft` | Syntax-aware diff (via difftastic) |
| `dfl` | Syntax-aware log diff |
| `diff-names` | Show only changed filenames |
| `diff-stat` | Show diff statistics |

### Worktree

| Alias | What it does |
|-------|-------------|
| `wt` | Worktree command |
| `wta` | Add a new worktree |
| `wtl` | List worktrees |

---

## GitHub CLI Aliases

Use as `gh <alias>`, e.g., `gh co`, `gh pm`.

| Alias | Command | What it does |
|-------|---------|-------------|
| `co` | `pr checkout` | Checkout a PR locally |
| `pv` | `pr view --web` | View PR in browser |
| `pc` | `pr create --web` | Create PR in browser |
| `pl` | `pr list` | List open PRs |
| `il` | `issue list` | List open issues |
| `iv` | `issue view --web` | View issue in browser |
| `ic` | `issue create --web` | Create issue in browser |
| `rv` | `repo view --web` | View repo in browser |
| `rc` | `repo clone` | Clone a repo |
| `rl` | `repo list` | List your repos |
| `runs` | `run list` | List workflow runs |
| `watch` | `run watch` | Watch a running workflow |
| `rerun` | `run rerun --failed` | Re-run failed jobs |
| `pm` | `pr merge --squash --delete-branch` | Squash-merge PR + delete branch |
| `rel` | `release create --generate-notes` | Create release with auto notes |

---

## Global Justfile Recipes

Run from anywhere with `gj <recipe>` (or `just --justfile ~/.justfile <recipe>`).

### System

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `update` | `gj update` | Update everything via topgrade |
| `info` | `gj info` | System info via fastfetch |
| `flush-dns` | `gj flush-dns` | Flush DNS cache |
| `ports` | `gj ports` | Show all listening ports |

### Git

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `rebase` | `gj rebase 5` | Interactive rebase last N commits |
| `undo` | `gj undo` | Undo last commit (keep changes) |
| `branches` | `gj branches` | Recent branches by last commit |
| `standup` | `gj standup` | Your commits since yesterday |

### Docker

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `docker-clean` | `gj docker-clean` | Prune unused Docker resources |
| `docker-usage` | `gj docker-usage` | Show Docker disk usage |
| `docker-nuke` | `gj docker-nuke` | Remove ALL Docker data |

### Network

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `ip` | `gj ip` | Show public IP |
| `local-ip` | `gj local-ip` | Show local IP |
| `kill-port` | `gj kill-port 3000` | Kill process on port |
| `status` | `gj status https://...` | HTTP status check |

### Cleanup

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `node-clean` | `gj node-clean` | Show node_modules disk usage |
| `ds-clean` | `gj ds-clean` | Remove .DS_Store files |

### Quick Info

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `cheat` | `gj cheat curl` | Show tldr cheatsheet |
| `timestamp` | `gj timestamp` | Generate ISO timestamp |
| `weather` | `gj weather London` | Show weather |
| `loc` | `gj loc` | Count lines of code |

### Dev

| Recipe | Usage | What it does |
|--------|-------|-------------|
| `serve` | `gj serve 8080` | Serve current directory |
| `uuid` | `gj uuid` | Generate a UUID |
| `b64-encode` | `gj b64-encode "text"` | Base64 encode |
| `b64-decode` | `gj b64-decode "dGV4dA=="` | Base64 decode |

---

## macOS Hot Corners

| Corner | Action |
|--------|--------|
| **Top-left** | Mission Control |
| **Top-right** | Show Desktop |
| **Bottom-left** | Disabled |
| **Bottom-right** | Disabled |

---

## macOS Rectangle (Window Management)

Default Rectangle shortcuts (installed by the script):

| Key | Action |
|-----|--------|
| `Ctrl+Alt+Left` | Left half |
| `Ctrl+Alt+Right` | Right half |
| `Ctrl+Alt+Up` | Top half |
| `Ctrl+Alt+Down` | Bottom half |
| `Ctrl+Alt+Enter` | Maximize |
| `Ctrl+Alt+Backspace` | Restore |
| `Ctrl+Alt+U` | Top-left quarter |
| `Ctrl+Alt+I` | Top-right quarter |
| `Ctrl+Alt+J` | Bottom-left quarter |
| `Ctrl+Alt+K` | Bottom-right quarter |

Script sets: Almost maximize (95%), 8px gaps, snap on drag.

---

## Claude Code Custom Commands

| Command | What it does |
|---------|-------------|
| `/pr-review` | Review current branch changes vs main |
| `/test-plan` | Generate test plan for recent changes |
| `/dep-audit` | Audit dependencies for vulnerabilities and bloat |
| `/quick-doc` | Generate docs for a file or function |
| `/cleanup` | Find dead code, unused imports, debug statements |
| `/security-scan` | Run gitleaks, semgrep, trivy, and dependency audits |
| `/perf-check` | Benchmark with hyperfine, load test with oha, find anti-patterns |
| `/docker-lint` | Lint Dockerfiles with hadolint, analyze layers with dive |
| `/iac-review` | Review Terraform/CDK with tflint, trivy, and infracost |
| `/convert` | Convert between formats using pandoc, ffmpeg, magick, d2, mermaid |
| `/new-feature` | Full trunk-based workflow: issue, branch, implement, tests, PR |
| `/fix-bug` | Full trunk-based workflow: issue, branch, test-first fix, PR |
| `/create-readme` | Analyze codebase and generate comprehensive README |
| `/init-project` | Scaffold project with git, README, CLAUDE.md, CI, Docker, templates |
| `/refactor` | Refactor with tests preserved, SOLID principles |
| `/add-endpoint` | Add API endpoint: types, handler, validation, tests, docs |
| `/add-component` | Add React component: TSX, tests, stories, accessibility |
| `/ci-fix` | Diagnose and fix CI failures via `gh run view` + `act` |
| `/changelog` | Generate changelog from conventional commits |
| `/commit-msg` | Generate conventional commit message from staged changes |

---

## Summary

| Category | Count |
|----------|-------|
| Shell aliases | 65 |
| VS Code keybindings | 21 |
| tmux keybindings | 12 |
| Vim keybindings | 8 |
| fzf keybindings | 7 |
| Git aliases | 30 |
| GitHub CLI aliases | 15 |
| Global justfile recipes | 27 |
| macOS hot corners | 4 |
| Rectangle window shortcuts | 10 |
| Claude Code commands | 20 |
| **Total** | **219** |
