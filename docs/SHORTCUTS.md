# macOS Keyboard Shortcuts & Aliases

Quick reference for all **209+ shortcuts** configured by the setup scripts.

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
| `y` | `rovr` | Terminal file manager (mouse-first TUI; `n` = nnn, the minimal fallback) |
| `jx` | `fx` | Interactive JSON viewer |

### Downloads & Network

| Alias | Runs | What it does |
|-------|------|-------------|
| `dl` | `aria2c` | Multi-connection downloader |
| `wget` | `aria2c` | Download with 16 connections |

### Database

| Alias | Runs | What it does |
|-------|------|-------------|
| `hq` | `harlequin` | Terminal SQL IDE (DuckDB/Postgres/MySQL) |

### Git & GitHub

| Alias | Runs | What it does |
|-------|------|-------------|
| `lg` | `lazygit` | Interactive git terminal UI |
| `ghd` | `gh dash` | GitHub dashboard (PRs, issues) |
| `gdft` | `git dft` | Syntax-aware git diff |
| `gha` | `act` | Run GitHub Actions locally |
| `gha3` | `act3` | Glance at last 3 GitHub Actions runs |

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
| `md` | `leaf` | Render Markdown in the terminal |
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
| `watchrun` | `watchexec --exts ts,tsx --restart` | Watch & rerun on changes |
| `bench` | `hyperfine` | Benchmark commands |
| `loadtest` | `oha` | HTTP load testing |
| `par` | `parallel` | GNU parallel |
| `lint-sh` | `shellcheck` | Lint shell scripts |
| `fmt-sh` | `shfmt -w -i 4` | Format shell scripts |

### Terminal Apps

| Alias | Runs | What it does |
|-------|------|-------------|
| `n` | `nnn -de` | File manager (detail view, text in pager) |
| `prog` | `progress -m` | Live progress bars for running cp/mv/dd/tar |

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
| `lfsinit` | `git-lfs-enable-repo` | Enable Git LFS hooks for this repo |

### System

| Alias | Runs | What it does |
|-------|------|-------------|
| `update` | `topgrade` | Update everything (brew, npm, pip, OS) |
| `sysinfo` | `fastfetch` | Quick system info display |

---

## Terminal App Keybindings

> **How these were verified.** Every binding below was read from the tool on this machine
> or from its official documentation. None were written from memory. Each section names its
> source, so a wrong row is traceable rather than mysterious. Where a tool has no
> machine-readable keymap and no published table, this file lists its in-app help key and
> says so, instead of printing a plausible guess.
>
> Bindings marked **(house)** are set by this repo's generated config, so they differ from
> the tool's upstream defaults. Everything else is the upstream default.

### zellij

*Source: `zellij setup --dump-config` on this machine.*

Zellij is **modal**. You press a mode key, then act. The status bar shows the current mode's
keys, which is why `default_layout` is `"default"` and not `"compact"` — the compact layout
omits the plugin that draws them.

| Key | Enters mode |
|-----|-------------|
| `Ctrl+p` | Pane |
| `Ctrl+t` | Tab |
| `Ctrl+n` | Resize |
| `Ctrl+s` | Scroll |
| `Ctrl+o` | Session |
| `Ctrl+h` | Move |
| `Ctrl+g` | Locked (toggles — the pass-through escape hatch) |
| `Ctrl+b` | Tmux compatibility |

**Pane mode** (`Ctrl+p`, then):

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` / arrows | Move focus left/down/up/right |
| `n` | New pane |
| `d` | New pane below |
| `r` | New pane right |
| `s` | New stacked pane |
| `x` | Close focused pane |
| `p` | Switch focus |
| `;` | Focus last pane |

**Tab mode** (`Ctrl+t`, then):

| Key | Action |
|-----|--------|
| `n` | New tab |
| `x` | Close tab |
| `r` | Rename tab |
| `h` / `k` / arrows | Previous tab |
| `l` / `j` / arrows | Next tab |
| `1`…`9` | Go to tab N |
| `s` | Toggle sync across panes in tab |
| `b` | Break pane into its own tab |
| `[` / `]` | Break pane left / right |

**Resize mode** (`Ctrl+n`, then):

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Increase left/down/up/right |
| `H` `J` `K` `L` | Decrease left/down/up/right |
| `=` or `+` | Increase |
| `-` | Decrease |

**Scroll mode** (`Ctrl+s`, then):

| Key | Action |
|-----|--------|
| `j` / `k` | Scroll down / up |
| `d` / `u` | Half page down / up |
| `Ctrl+f` / `Ctrl+b` | Page down / up |
| `[` / `]` | Previous / next prompt |
| `s` | Search |
| `e` | Edit scrollback in `$EDITOR` |
| `Ctrl+c` | Jump to bottom and leave |

**Session mode** (`Ctrl+o`, then):

| Key | Action |
|-----|--------|
| `d` | Detach |
| `f` | Toggle host fullscreen |
| `[` / `]` | Focus guest / host session |

---

### lazygit

*Source: `lazygit --config`, which dumps the full default `keybinding:` tree (178 entries).*

**Universal**

| Key | Action |
|-----|--------|
| `q` | Quit |
| `Q` | Quit without changing directory |
| `Esc` | Return / cancel |
| `Tab` | Toggle panel |
| `j` / `k` or arrows | Next / previous item |
| `,` / `.` | Previous / next page |
| `<` / `>` | Go to top / bottom |
| `H` / `L` | Scroll left / right |
| `v` | Toggle range select |
| `Ctrl+z` | Suspend |

**Files panel**

| Key | Action |
|-----|--------|
| `c` | Commit changes |
| `w` | Commit without pre-commit hook |
| `C` | Commit using your editor |
| `A` | Amend last commit |
| `s` | Stash all changes |
| `S` | Stash options |
| `x` | Discard (confirm) |
| `i` | Add to `.gitignore` |
| `r` | Refresh files |
| `Ctrl+f` | Find base commit for fixup |

**Branches panel**

| Key | Action |
|-----|--------|
| `c` | Checkout branch by name |
| `F` | Force checkout |
| `-` | Checkout previous branch |
| `r` | Rebase branch |
| `o` | Create pull request |
| `O` | Pull request options |
| `G` | Open pull request in browser |
| `Ctrl+y` | Copy pull request URL |

---

### k9s

*Source: [k9scli.io command reference](https://k9scli.io/topics/commands/).*

| Key | Action |
|-----|--------|
| `?` | Show active keyboard mnemonics and help |
| `Ctrl+a` | Show all available resource aliases |
| `:q` or `Ctrl+c` | Quit |
| `Esc` | Leave view / command / filter mode |
| `d` | Describe |
| `v` | View |
| `e` | Edit |
| `l` | View logs |
| `Ctrl+d` | Delete a resource (Tab and Enter to confirm) |
| `Ctrl+k` | Kill a resource, no confirmation |

**Command mode** (`:` then):

| Command | Action |
|---------|--------|
| `:pod` | View a resource by singular, plural, or short name |
| `:pod ns-x` | View a resource in a given namespace |
| `:ctx` | View and switch Kubernetes context |
| `:ns` | View and switch namespace |
| `:xray RESOURCE [NS]` | Launch XRay view |
| `:pulses` or `:pu` | Pulses view |

**Filtering**

| Filter | Effect |
|--------|--------|
| `/text` | Regex filter on name |
| `/! text` | Keep everything that does *not* match |
| `/-l label-selector` | Filter by label |
| `/-f text` | Fuzzy find |

---

### lazydocker

*Source: upstream [`Keybindings_en.md`](https://github.com/jesseduffield/lazydocker/blob/master/docs/keybindings/Keybindings_en.md).*

**Global**

| Key | Action |
|-----|--------|
| `1` … `6` | Focus projects / services / containers / images / volumes / networks |
| `+` / `_` | Next / previous screen mode (normal, half, fullscreen) |
| `[` / `]` | Previous / next tab |
| `/` | Filter list |
| `Enter` | Focus main panel |
| `Esc` | Return (from main panel) |

**Containers**

| Key | Action |
|-----|--------|
| `d` | Remove |
| `s` | Stop |
| `r` | Restart |
| `p` | Pause |
| `a` | Attach |
| `E` | Exec shell |
| `m` | View logs |
| `e` | Hide/show stopped containers |
| `w` | Open in browser (first http port) |
| `b` | Bulk commands |
| `c` | Predefined custom command |

**Services** adds `u` up service, `U` up project, `D` down project, `S` start, `R` restart options.
**Images / Volumes / Networks** share `d` remove, `b` bulk commands, `c` custom command.

---

### broot

*Source: [dystroy.org/broot](https://dystroy.org/broot/).*

| Key | Action |
|-----|--------|
| *type letters* | Fuzzy search files and directories |
| `Enter` | Focus directory, or open file in default app |
| `Enter` on root line | Go to parent |
| `Alt+Enter` | Leave broot and `cd` to selection |
| `Esc` | Clear search / previous state |
| `Tab` | Cycle matches |
| `↑` / `↓` | Move selection |
| `Ctrl+→` / `Ctrl+←` | Open preview panel / move between panels |
| `Alt+h` | Toggle hidden files |
| `Alt+i` | Toggle ignored files |
| `:q` or `Ctrl+q` | Quit |
| `:e` | Open in `$EDITOR` |
| `:gf` / `:gs` | Git file statuses / only git-changed files |
| `:fs` | Filesystem usage |

Launch it with the shell function `br`, not `broot`, so `Alt+Enter` can change your shell's directory.

---

### jqp

*Source: upstream [README keybindings table](https://github.com/noahgorstein/jqp).*

| Key | Action |
|-----|--------|
| `Tab` / `Shift+Tab` | Cycle sections forward / back |
| `Enter` | Execute query |
| `↑` / `↓` | Cycle query history |
| `Ctrl+y` | Copy query to clipboard |
| `Ctrl+s` | Save output to file |
| `Ctrl+t` | Toggle input panel |
| `Ctrl+c` | Quit, or kill a long-running query |

---

### jnv

*Source: upstream [README keymap](https://github.com/ynqa/jnv).*

| Key | Action |
|-----|--------|
| `Ctrl+c` | Exit |
| `Ctrl+q` | Copy jq filter to clipboard |
| `Ctrl+o` | Copy JSON to clipboard |
| `Shift+↑` / `Shift+↓` | Switch mode |
| `Tab` | Enter suggestion |
| `Ctrl+a` / `Ctrl+e` | Line start / end |
| `Ctrl+u` | Clear line |
| `Alt+b` / `Alt+f` | Jump to previous / next jq token |

---

### mpv

*Source: `man mpv`, INTERACTIVE CONTROL section.*

| Key | Action |
|-----|--------|
| `q` | Stop and quit |
| `Q` | Quit, storing playback position |
| `Enter` | Next in playlist |
| `.` / `,` | Step forward / backward one frame |
| `m` | Mute |
| `f` | Toggle fullscreen |
| `_` | Cycle video tracks |
| `#` | Cycle audio tracks |
| `E` | Cycle editions |

---

### newsboat

*Source: this repo's generated `~/.config/newsboat/config` — these are **house** bindings, not upstream defaults.*

| Key | Action |
|-----|--------|
| `j` / `k` | Down / up **(house)** |
| `J` / `K` | Next / previous feed **(house)** |
| `g` / `G` | Home / end **(house)** |
| `l` | Open **(house)** |
| `h` | Quit **(house)** |

Upstream newsboat uses arrow keys and `q`; the generated config adds this vim layer on top.

---

### wiper

*Source: upstream [README keybindings](https://github.com/ikebastuz/wiper).*

| Key | Action |
|-----|--------|
| `j` / `k` or `↓` / `↑` | Navigate |
| `l` / `→` / `Enter` | Into folder |
| `h` / `←` / `Backspace` | To parent |
| `d` | Delete — first press selects, second confirms |
| `s` | Toggle sort (title / size) |
| `c` | Toggle size-gradient colouring |
| `t` | Toggle Trash (removed content goes to Trash) |
| `q` | Quit |

---

### e1s and lazysql

*Source: upstream READMEs.*

Both ship an in-app keymap that is the authoritative reference, and both are best read there:

| Tool | Help key |
|------|----------|
| `e1s` (ECS browser) | `?` |
| `lazysql` | `?` — upstream states "For a list of keyboard shortcuts press `?`" |

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
| `/init-project` | Scaffold project with git, README, AGENTS.md, CI, Docker, templates |
| `/refactor` | Refactor with tests preserved, SOLID principles |
| `/add-endpoint` | Add API endpoint: types, handler, validation, tests, docs |
| `/add-component` | Add React component: TSX, tests, accessibility |
| `/ci-fix` | Diagnose and fix CI failures via `gh run view` + `act` |
| `/changelog` | Generate changelog from conventional commits |
| `/commit-msg` | Generate conventional commit message from staged changes |
| `/probe-assumptions` | Pressure-test the assumptions behind a document or plan |
| `/probe-evidence` | Pressure-test the evidence behind a document or plan |
| `/probe-implications` | Pressure-test the implications of a document or plan |

---

## Hot Corners

| Corner | Action |
|--------|--------|
| **Top-left** | Mission Control |
| **Top-right** | Show Desktop |
| **Bottom-left** | Disabled |
| **Bottom-right** | Disabled |

---

## macOS App Shortcuts

*Source: this repo's generated Ghostty config, cross-checked against the copy on disk.*

Only Ghostty gets custom bindings from this setup. They are **global** hotkeys, so they work
from any application:

| App | Shortcut | Action |
|-----|----------|--------|
| Ghostty | `Cmd+Space` | Toggle the quick terminal (the drop-down shelf) **(house)** |
| Ghostty | `Cmd+Alt+T` | New window **(house)** |

`Cmd+Space` is deliberately taken from Spotlight, which the setup disables for that
combination. Spotlight-style search moves to the shell functions `a`, `ff`, `rgf`, and `s`.

**Visual Studio Code** uses stock shortcuts. The setup generates its `settings.json` but no
`keybindings.json`, so there is nothing house-specific to document; use VS Code's own
`Cmd+K Cmd+S` keyboard-shortcuts editor.

> Earlier revisions of this file listed shortcuts for **Slack**, **TablePlus**, **Snagit**,
> and **Raycast**. None of the four are installed — all sit in `DEPRECATED_TOOLS` and are
> actively uninstalled by `--cleanup`. Their replacements are Google Chat, the TUI database
> tools (`lazysql`, `harlequin`, `pgcli`), Shottr, and the Ghostty quick terminal.

---

## Summary

Counts are taken from this file's own tables, so they stay honest as it grows.

| Category | Count |
|----------|-------|
| Shell aliases | 70 |
| Terminal app keybindings | 156 |
| fzf keybindings | 7 |
| Git aliases | 29 |
| GitHub CLI aliases | 15 |
| Global justfile recipes | 25 |
| Claude Code commands | 23 |
| Ghostty global hotkeys | 2 |
| **Total** | **327** |

### Coverage

Documented in depth, each from a named source: **zellij, lazygit, k9s, lazydocker, broot,
jqp, jnv, mpv, newsboat, wiper, fzf**, plus the in-app help key for **e1s** and **lazysql**.

Not yet covered: `micro`, `nnn`, `lnav`, `btop`, `atuin`, `trip`, `viddy`, `harlequin`,
`atac`, `fx`, `mprocs`, `clipse`, `stu`, `bmm`, `rovr`, `pgcli`, `mycli`, `aichat`, `w3m`,
`bandwhich`, `croft`, `gh-dash`, `herald`, and `tiki`. These are pending verification
against their upstream documentation rather than omitted by choice.

`kondo` is deliberately absent: it is a CLI with a confirmation prompt, not a TUI, so it has
no keymap to document.
