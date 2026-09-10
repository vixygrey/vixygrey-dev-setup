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
| `y` | Yazi shell wrapper | Open Yazi and keep its directory after `q` |
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

### e1s and lazysql

*Source: upstream READMEs.*

Both ship an in-app keymap that is the authoritative reference, and both are best read there:

| Tool | Help key |
|------|----------|
| `e1s` (ECS browser) | `?` |
| `lazysql` | `?` — upstream states "For a list of keyboard shortcuts press `?`" |

---

### micro

*Source: upstream [`runtime/help/defaultkeys.md`](https://github.com/zyedidia/micro/blob/master/runtime/help/defaultkeys.md).*

`micro` is the `EDITOR` for git, `gh`, and lazygit commit messages. It is non-modal, so these
work immediately with no mode to enter first.

| Key | Action |
|-----|--------|
| `Ctrl-s` | Save |
| `Ctrl-q` | Close file (quits micro if it is the last one) |
| `Ctrl-g` | Open help |
| `Ctrl-e` | Command prompt (`> help commands` lists them) |
| `Ctrl-o` | Open a file |
| `Ctrl-f` | Find |
| `Ctrl-n` / `Ctrl-p` | Next / previous search result |
| `Ctrl-z` / `Ctrl-y` | Undo / redo |
| `Ctrl-c` / `Ctrl-x` / `Ctrl-v` | Copy / cut / paste |
| `Ctrl-k` | Cut current line |
| `Ctrl-d` | Duplicate current line |
| `Ctrl-a` | Select all |
| `Ctrl-l` | Jump to line |
| `Ctrl-t` | New tab |
| `Ctrl-w` | Cycle splits (`> vsplit`, `> hsplit` create them) |
| `Ctrl-r` | Toggle line-number ruler |
| `Ctrl-u` | Toggle macro recording |
| `Ctrl-j` | Run last recorded macro |
| `Ctrl-b` | Run a shell command |

On macOS, word-wise movement is `Alt`+arrows and line-start/end is `Ctrl`+arrows — the
opposite of Linux, which the upstream doc calls out explicitly.

---

### lnav

*Source: [docs.lnav.org hotkeys reference](https://docs.lnav.org/en/latest/hotkeys.html).*

The richest keymap of any tool here. `man lnav` lists only `?` and `q`; everything below
comes from the online reference.

**Navigation**

| Key | Action |
|-----|--------|
| `j` / `k` or arrows | Down / up a line |
| `Space` / `PgDn`, `b` / `PgUp` | Down / up a page |
| `Ctrl-d` / `Ctrl-u` | Down / up half a page |
| `h` / `l` | Left / right half a page |
| `g` / `G` or `Home` / `End` | Top / bottom |
| `e` / `Shift-e` | Next / previous **error** |
| `w` / `Shift-w` | Next / previous **warning** |
| `n` / `Shift-n` | Next / previous search result |
| `f` / `Shift-f` | Next / previous file |
| `u` / `Shift-u` | Next / previous bookmark |
| `{` / `}` | Previous / next section |

**Time travel**

| Key | Action |
|-----|--------|
| `d` / `Shift-d` | Forward / back 24 hours |
| `1`–`6` | Next ten-minute interval (`Shift` for previous) |
| `7` / `8` | Previous / next minute |
| `0` / `Shift-0` | Next / previous day |
| `r` / `Shift-r` | Forward / back by the last relative time used |

**Bookmarks**

| Key | Action |
|-----|--------|
| `m` | Mark / unmark line |
| `Shift-m` | Mark range back to the last mark |
| `c` | Copy marked lines to clipboard |
| `Shift-c` | Clear marks |

**Display and views**

| Key | Action |
|-----|--------|
| `?` or `F1` | Help |
| `q` | Back a view, or quit |
| `t` | Text view |
| `i` / `Shift-i` | Histogram view |
| `v` / `Shift-v` | SQL results view |
| `z` / `Shift-z` | Zoom in / out on time |
| `Shift-p` | Toggle pretty-print |
| `Ctrl-w` | Toggle word wrap |
| `Ctrl-f` | Toggle all filters |
| `x` | Toggle field hiding |
| `=` | Pause / resume file loading |

**Prompts**

| Key | Opens |
|-----|-------|
| `/` | Regex search |
| `;` | SQLite query prompt |
| `:` | Internal command |
| `\|` | Run an lnav script |
| `Ctrl-]` | Abort the prompt |

---

### stu

*Source: [lusingander.github.io/stu keybindings](https://lusingander.github.io/stu/keybindings/).*

| Key | Action |
|-----|--------|
| `j` / `k` | Select / scroll |
| `Enter` | Open selected item |
| `Backspace` | Back |
| `?` | Help (per-view detail) |
| `Esc` | Hide help |
| `Ctrl-c` | Quit |

### Yazi

*Source: [Yazi Quick Start](https://yazi-rs.github.io/docs/quick-start/).*

| Key | Action |
|-----|--------|
| `h` / `j` / `k` / `l` | Parent / down / up / enter directory |
| `Enter` | Open selected files |
| `Space` | Toggle selection |
| `y` / `x` / `p` | Copy / cut / paste |
| `a` / `r` | Create / rename |
| `d` | Move selected files to Trash |
| `.` | Toggle hidden files |
| `F1` or `~` | Open help |
| `q` / `Q` | Quit and change directory / quit without changing |

---


### Tools whose keymap you configure, not memorise

These tools have no fixed default table because users can change their bindings.
Use each tool's own interface to inspect its current keymap:
| Tool | How bindings are set | Verified via |
|------|----------------------|--------------|
| `trip` (trippy) | `--tui-key-bindings command=key,…` | `trip --help` |
| `harlequin` | `--keymap-name <name>`, and keymaps are composable | `harlequin --help` |
| `clipse` | a `keyBindings` map in its config file | upstream README |

If you want a stable muscle-memory keymap for any of them, set it in this repo's generated
config rather than learning the upstream default.

---

### Tools where the in-app help is the documentation

For these, the help key genuinely **is** the reference. Each was checked against its man
page, its `--help`, and its upstream README or docs site; none publishes a keymap table.
Listing a plausible one here would be a guess, which is exactly how the retired Kiro
section survived for years.

| Tool | Help key | What was checked |
|------|----------|------------------|
| `lazysql` | `?` | upstream README: "For a list of keyboard shortcuts press `?`" |
| `e1s` | `?` | upstream README key-bindings section |
| `btop` | in-app | 1,593-line README, no keymap; `--help` has none |
| `atuin` | in-app | docs keybinds page 404s; `--help` "key" hits are about encryption keys |
| `fx` | in-app | README defers to fx.wtf, which publishes no keybindings page |
| `gh-dash`, `atac` | in-app | READMEs and `man atac` carry no keymap |
| `viddy`, `mprocs` | in-app | no man page; upstream repo renamed, docs not reachable |
| `pgcli`, `mycli` | in-app | no man page; both use standard readline editing |
| `w3m`, `bandwhich` | in-app | man pages carry no keybindings section |

`kondo` is deliberately absent from every table: it is a CLI with a confirmation prompt, not
a TUI, so it has no keymap at all.

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

## Hot Corners

| Corner | Action |
|--------|--------|
| **Top-left** | Disabled |
| **Top-right** | Disabled |
| **Bottom-left** | Disabled |
| **Bottom-right** | Disabled |

---

## macOS App Shortcuts

| App | Shortcut | Action |
|-----|----------|--------|
| Spotlight | `Cmd+Space` | Search applications, files, and the web |
| Finder | `Cmd+Option+Space` | Open a Finder search window |

Kitty uses its standard macOS bindings. The setup does not register a global
terminal shortcut or a background launcher.
