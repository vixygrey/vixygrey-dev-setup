# Windows User Guide

Everything installed and configured by `scripts/setup-dev-tools-windows.ps1`. This is the complete reference for Windows users -- no other guide needed.

> **Setup (PowerShell as Administrator):**
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> .\scripts\setup-dev-tools-windows.ps1
> ```

---

## Quick Start

After running the setup script, open a new PowerShell terminal and try these:

```powershell
# Your new shell -- aliases are already active
ls                  # eza with icons and colors
ll                  # long listing with git status
lt                  # tree view (3 levels)
cat $PROFILE        # syntax-highlighted file viewing (bat)
top                 # graphical system monitor (btop)

# Navigate with zoxide (learns your habits)
cd ~\Code\work      # first time: use cd as normal
cw                  # after that: directory shortcut function

# Search anything
rg "TODO" .         # ripgrep: fast text search
fd "*.ts"           # fd: fast file search
fzf                 # interactive fuzzy finder (Ctrl+T in shell)

# Update everything at once
update              # topgrade: Scoop, winget, npm, pip, system updates

# System info
sysinfo             # fastfetch: quick hardware/software summary
```

---

## Package Managers

| Manager | Purpose | Install Level |
|---------|---------|---------------|
| **Scoop** | CLI tools, developer utilities, Nerd Fonts | User-level (no admin needed) |
| **winget** | GUI apps, system tools (Docker Desktop, VS Code, browsers) | Windows Package Manager |

### Scoop Buckets

The script adds these Scoop buckets automatically:

- `extras` -- GUI apps and additional CLI tools
- `nerd-fonts` -- JetBrains Mono and other patched fonts
- `versions` -- alternate/older versions of packages

### How Tools Are Distributed

- **Scoop** handles most CLI tools (fd, ripgrep, bat, eza, fzf, jq, yq, etc.)
- **winget** handles GUI apps (Docker Desktop, VS Code, Windows Terminal, Brave Browser, etc.)
- **npm** handles global Node.js tools (installed after mise sets up Node)
- **cargo** handles Rust-based tools when not available via Scoop

---

## PowerShell Profile

The profile lives at `$PROFILE` (typically `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`).

The script inserts a **managed block** (delimited by `# >>> dev-setup managed block >>>` and `# <<< dev-setup managed block <<<`) that configures:

### PATH Additions

- `$HOME\Scripts\bin` added to PATH

### Environment Variables

| Variable | Value |
|----------|-------|
| `RIPGREP_CONFIG_PATH` | `$HOME\.ripgreprc` |
| `EDITOR` | `code --wait` |
| `VISUAL` | `code --wait` |
| `PAGER` | `bat --style=plain --paging=always` |
| `LANG` | `en_US.UTF-8` |
| `XDG_CONFIG_HOME` | `$HOME\.config` |
| `XDG_DATA_HOME` | `$HOME\.local\share` |
| `XDG_CACHE_HOME` | `$HOME\.cache` |
| `XDG_STATE_HOME` | `$HOME\.local\state` |

### Tool Initialization

The profile initializes these tools (if installed):

- **mise** -- universal version manager (Node, Python, Go, Ruby)
- **Starship** -- cross-shell prompt (Dracula theme)
- **Atuin** -- shell history with fuzzy search
- **Zoxide** -- smart `cd` replacement (`z` command)
- **Direnv** -- per-project environment variables
- **vivid** -- LS_COLORS with Dracula theme

### PSReadLine

Replaces zsh-autosuggestions and syntax-highlighting from Linux/macOS:

- Prediction source: `HistoryAndPlugin`
- Prediction view: `ListView`
- Edit mode: `Windows`
- Tab key: `MenuComplete`

### fzf Configuration

Dracula color scheme with the same keybindings as the Linux/macOS version, but uses `clip.exe` instead of `pbcopy`/`xclip` for the `Ctrl-Y` copy binding.

---

## Windows Terminal

The script installs Windows Terminal via winget (built-in on Windows 11) and adds the **Dracula color scheme** to the settings file at:

```
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

A backup of the existing settings is created before modification. The Dracula scheme includes matching colors for background (#282A36), foreground (#F8F8F2), cursor (#F8F8F2), and selection (#44475A).

To activate the scheme after install, open Windows Terminal Settings and select "Dracula" as the color scheme for your default profile.

---

## Daily Workflow

### File Navigation

```powershell
# List files (eza replaces ls)
ls                  # colorful listing with icons
ll                  # long listing with git status, permissions, size
la                  # include hidden files
lt                  # tree view, 3 levels deep

# Find files (fd replaces find)
fd "config"         # find files matching "config"
fd -e ts            # find all .ts files
fd -e test.ts       # find all test files
fd -H .env          # include hidden files

# Navigate (zoxide replaces cd)
z project           # jump to most-visited directory matching "project"
z code work         # jump to directory matching both "code" and "work"
zi                  # interactive selection with fzf

# File manager (yazi)
y                   # open terminal file manager
# j/k to navigate, l to enter, h to go back, q to quit
```

### Searching

```powershell
# Text search (ripgrep replaces grep)
rg "function"            # search current dir recursively
rg "TODO" --type ts      # search only TypeScript files
rg "error" -i            # case-insensitive
rg "api" -g "*.py"       # search only Python files
rg "class" -l            # list only filenames with matches
rg "import" -C 3         # show 3 lines of context

# Interactive fuzzy finder (fzf)
# Ctrl+T   -- search files, paste path
# Alt+C    -- search directories, cd into selection
# Ctrl+R   -- search shell history (handled by atuin)

# Atuin (replaces shell history)
atuin search "docker"    # search history for docker commands
# Up arrow -- browse recent commands
# Ctrl+R   -- interactive search (fuzzy, full-text)
```

### File Operations

```powershell
# View files (bat replaces cat)
cat file.ts         # syntax highlighting, line numbers
bat -p file.ts      # plain mode (no line numbers)
bat -l json data    # force language detection

# Edit quickly
nano file.txt       # enhanced nano (syntax highlighting, line numbers)

# Open files/folders (Windows equivalents of macOS `open`)
Start-Process file.txt       # open with default app
Invoke-Item file.txt         # same thing, shorter in scripts
start .                      # open current folder in Explorer (cmd-style shortcut)

# Disk usage
du                  # dust: visual disk usage tree
du ~\Code           # see what's using space
df                  # duf: colorful disk free table

# Process management (note: psg instead of ps to avoid PowerShell built-in conflict)
psg                 # procs: sortable process list
procs --tree        # process tree view
```

> **Note:** Windows does not override `rm` with `trash`. Use the Recycle Bin via Explorer, or install a trash CLI separately. To permanently delete from the command line, use `Remove-Item`.

---

## Modern CLI Replacements

Every standard tool has a faster, modern alternative:

| You type | Actually runs | What it does |
|----------|--------------|--------------|
| `ls` | `eza --icons` | Colorful listing with file type icons |
| `ll` | `eza -la --icons --git` | Long listing with git status |
| `lt` | `eza --tree --icons --level=3` | Tree view |
| `cat` | `bat --paging=never` | Syntax highlighting, line numbers |
| `top` | `btop` | Graphical system monitor with charts |
| `du` | `dust` | Visual disk usage tree |
| `df` | `duf` | Colorful disk space table |
| `psg` | `procs` | Sortable process list, Docker-aware |
| `ping2` | `gping` | Real-time latency graph |
| `dig2` | `doggo` | Colorized DNS lookup with DoH/DoT |
| `watch2` | `viddy` | Watch commands with diff highlighting |
| `make` | `just` | Simpler task runner, no tab issues |
| `f` / `fd` | `fd` | Fast file finder, simple syntax |
| `dft` | `difft` | Syntax-aware structural diff |
| `y` | `yazi` | Terminal file manager |
| `jx` | `fx` | Interactive JSON viewer |
| `md` | `glow` | Render Markdown in terminal |
| `dl` | `aria2c` | Multi-connection downloader |

> **Windows alias differences:** `ps`, `ping`, `dig`, and `watch` are PowerShell built-ins and cannot be overridden. Use `psg`, `ping2`, `dig2`, and `watch2` instead. Similarly, `pip` is aliased as `pip2` to avoid conflicts.

### Examples

```powershell
# fd vs find (Windows has no built-in find equivalent)
fd -e ts                                              # auto-ignores .gitignore entries

# ripgrep vs Select-String
Select-String -Pattern "TODO" -Path *.ts -Recurse     # old way
rg "TODO" --type ts                                    # new way (10x faster)

# dust vs native du
dust                                                   # visual disk usage tree

# sd (find & replace)
sd 'oldName' 'newName' file.ts                         # no escaping regex needed

# choose (extract columns)
echo "a:b:c" | choose -f ':' 1

# tldr vs man (quick help)
tldr tar                                               # simplified with examples
```

---

## Data & JSON

### jq (JSON processor)

```powershell
# Extract a field
cat data.json | jq '.name'

# Filter an array
cat data.json | jq '.users[] | select(.age > 30)'

# Transform
cat data.json | jq '{name: .name, email: .email}'

# Pretty-print API response
curl -s https://api.example.com/data | jq .
```

### jnv (interactive JSON navigator)

```powershell
# Explore a JSON file interactively with live jq filtering
jnv data.json
# Type jq expressions and see results in real-time
```

### fx (interactive JSON viewer)

```powershell
# Explore JSON interactively
jx data.json               # alias for fx
curl -s api.example.com | fx
# Use arrow keys to navigate, . to access fields
```

### yq (jq for YAML)

```powershell
# Read a value from YAML
yq '.metadata.name' deployment.yaml

# Modify in place
yq -i '.spec.replicas = 3' deployment.yaml

# Convert YAML to JSON
yq -o json config.yaml
```

### miller (CSV/JSON/tabular data)

```powershell
# Pretty-print CSV
mlr --csv --opprint cat data.csv

# Filter rows
mlr --csv filter '$age > 30' data.csv

# Sort by column
mlr --csv sort-by name data.csv

# Group by and aggregate
mlr --csv group-by department then stats1 -a mean -f salary data.csv
```

### csvkit (CSV tools)

```powershell
csvp data.csv               # alias: pretty-print CSV as table
csvcut -c name,email data.csv  # extract columns
csvgrep -c status -m "active" data.csv  # filter rows
csvstat data.csv             # summary statistics
```

### pandoc (document converter)

```powershell
md2pdf README.md             # alias: Markdown to PDF
md2html README.md            # alias: Markdown to HTML
md2docx README.md            # alias: Markdown to Word

# More conversions
pandoc input.docx -o output.md           # Word to Markdown
pandoc slides.md -t revealjs -o slides.html  # Markdown to slides
```

---

## Git & GitHub

### lazygit (terminal UI for git)

```powershell
lg                           # alias: open lazygit
# s -- stage/unstage files
# c -- commit
# p -- push
# P -- pull
# b -- branches
# Space -- toggle stage
# q -- quit
```

### GitHub CLI (gh)

```powershell
# PRs
gh co                        # alias: checkout PR locally
gh pc                        # alias: create PR in browser
gh pl                        # alias: list open PRs
gh pv                        # alias: view PR in browser
gh pm                        # alias: squash-merge + delete branch

# Issues
gh il                        # alias: list issues
gh ic                        # alias: create issue in browser
gh iv                        # alias: view issue in browser

# Actions
gh runs                      # alias: list workflow runs
gh watch                     # alias: watch running workflow
gh rerun                     # alias: re-run failed jobs

# Dashboard
ghd                          # alias: gh-dash (TUI dashboard)
```

### git-cliff (changelog generator)

```powershell
# Generate changelog from conventional commits
git-cliff                    # full changelog to stdout
git-cliff --unreleased       # only unreleased changes
git-cliff -o CHANGELOG.md    # write to file
git-cliff v1.0.0..HEAD       # specific range
```

### Git Aliases

```powershell
git st                       # status -sb (short status)
git lg                       # pretty graph log
git undo                     # undo last commit (keep changes)
git amend                    # amend last commit
git wip                      # stage all + commit "WIP"
git save                     # stage all + commit "chore: savepoint"
git standup                  # your commits since yesterday
git recent                   # 15 most recent branches
git cleanup                  # delete branches merged into main
git dft                      # difftastic (syntax-aware diff)
```

### pre-commit (git hooks)

```powershell
pre-commit install           # install hooks for current repo
pre-commit run --all-files   # run all hooks manually
pre-commit autoupdate        # update hook versions
```

---

## Docker & Kubernetes

Windows uses **Docker Desktop** (installed via winget) instead of Docker Engine or OrbStack. The daemon config lives at `~\.docker\daemon.json`:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  },
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["1.1.1.1", "8.8.8.8"]
}
```

Key settings: BuildKit enabled, log rotation (10 MB x 3 files), builder garbage collection (20 GB), and Cloudflare + Google DNS.

### lazydocker (Docker TUI)

```powershell
lzd                          # alias: open lazydocker
# Navigate containers, images, volumes, networks
# Enter -- view logs
# d -- remove
# s -- stop
# r -- restart
```

### dive (Docker image inspector)

```powershell
dive myapp:latest            # inspect image layers
# Tab -- switch between layers and file tree
# See exactly what each layer adds to the image
```

### k9s (Kubernetes TUI)

```powershell
k9s                          # open k9s
# : then type resource name (pods, deploy, svc)
# / -- filter
# d -- describe
# l -- logs
# s -- shell into pod
# Ctrl+D -- delete
```

### stern (multi-pod log tailing)

```powershell
klog                         # alias: stern
stern "api-*"                # tail all pods matching pattern
stern -n production api      # specific namespace
stern api --since 5m         # last 5 minutes
```

### kubectl shortcuts

```powershell
k get pods                   # alias: kubectl get pods
k get svc                    # list services
k apply -f deploy.yaml       # apply config
k logs -f pod-name           # follow logs
```

---

## Database

### pgcli / mycli (auto-completing SQL)

```powershell
pgcli -h localhost -U postgres mydb   # connect to PostgreSQL
mycli -h localhost -u root mydb       # connect to MySQL
# Tab -- autocomplete table names, columns, SQL keywords
# \dt -- list tables
# \d tablename -- describe table
# Ctrl+D -- quit
```

### lazysql (database TUI)

```powershell
lazysql                      # interactive database TUI
# Connect to Postgres, MySQL, SQLite
# Browse tables, run queries, view results in a table
```

### sq (jq for databases)

```powershell
sq inspect data.csv          # inspect a CSV file
sq '.data | .name, .email'   # query with jq-like syntax
sq @mydb '.users'            # query a database source
sq add mydb postgres://...   # add a database source
```

### dbmate (database migrations)

```powershell
dbmate new create_users      # create a new migration
dbmate up                    # run pending migrations
dbmate down                  # rollback last migration
dbmate status                # show migration status
```

---

## Security & Scanning

### typos (spell checker for code)

```powershell
typos .                      # check all files for typos
typos --diff                 # show what would be fixed
typos --write-changes        # auto-fix typos
typos src\                   # check specific directory
```

### ast-grep (structural code search)

```powershell
# Find all console.log statements
ast-grep --pattern 'console.log($$$)' --lang ts

# Find unused variables (structural, not text)
ast-grep --pattern 'const $VAR = $_' --lang ts

# Interactive mode
ast-grep scan
```

### gitleaks (secret scanning)

```powershell
gitleaks detect              # scan current repo for secrets
gitleaks detect --verbose    # show details
gitleaks protect             # pre-commit hook mode
```

### trivy (vulnerability scanning)

```powershell
trivy fs .                   # scan filesystem for vulnerabilities
trivy image myapp:latest     # scan Docker image
trivy config .               # scan IaC (Terraform, Docker, K8s)
```

### semgrep (static analysis)

```powershell
semgrep --config auto .      # auto-detect language, run rules
semgrep --config p/security-audit .  # security-focused rules
semgrep --config p/typescript .      # TypeScript-specific rules
```

---

## Testing & Benchmarking

### hyperfine (command benchmarking)

```powershell
bench 'fd -e ts' 'find . -name "*.ts"'   # alias: compare two commands
hyperfine 'npm run build' 'bun run build' # compare build tools
hyperfine --warmup 3 'curl -s localhost'  # warm up before measuring
```

### oha (HTTP load testing)

```powershell
loadtest http://localhost:3000           # alias: quick load test
oha -n 1000 -c 50 http://localhost:3000 # 1000 requests, 50 concurrent
oha -z 30s http://localhost:3000         # run for 30 seconds
```

### hurl (HTTP test files)

```powershell
# Create a test file (test.hurl):
# GET http://localhost:3000/api/health
# HTTP 200
# [Asserts]
# jsonpath "$.status" == "ok"

hurl test.hurl               # run the test
hurl --test test.hurl        # test mode (exit code)
hurl --very-verbose test.hurl # debug mode
```

### act (run GitHub Actions locally)

```powershell
gha                          # alias: run default workflow
act -l                       # list all workflows
act push                     # simulate push event
act -j test                  # run specific job
```

### act3 (glance at last 3 GitHub Actions runs)

```powershell
gha3                         # alias: view last 3 runs of every workflow
act3 -r owner/repo           # view runs for a specific repo
act3 -t html > status.html   # export HTML status page
# Requires a GitHub token: `gh auth login` or $env:GH_TOKEN
```

---

## Networking & Debugging

### mitmproxy (HTTP debugging proxy)

```powershell
mitmproxy                    # interactive TUI proxy
# Configure browser/app to use localhost:8080 as proxy
# See all HTTP/HTTPS requests in real-time
# Press Enter on a request to inspect headers/body
```

### trippy (modern traceroute TUI)

```powershell
trippy google.com            # traceroute with live charts
# Real-time hop-by-hop latency visualization
# Better than mtr for understanding network paths
```

### mtr (ping + traceroute combined)

```powershell
mtr google.com               # combined ping and traceroute
mtr --report google.com      # generate a report
```

### bandwhich (bandwidth monitor)

```powershell
# Run in an elevated (Administrator) PowerShell
bandwhich                    # see bandwidth by process
# Real-time view of which processes are using network
```

### nmap (network scanning)

```powershell
nmap -sn 192.168.1.0/24     # discover hosts on network
nmap -p 1-1000 target        # scan ports
nmap -sV target              # detect service versions
```

### xh / curlie (HTTP clients)

```powershell
xh httpbin.org/get           # GET request (colorized)
xh POST api.example.com/data name=John  # POST with JSON
xh -d api.example.com/file  # download file

curlie httpbin.org/get       # curl syntax, httpie output
curlie -X POST api.example.com -d '{"key":"val"}'
```

---

## Media & Files

### mpv (video player)

```powershell
mpv video.mp4                # play video
mpv --no-video music.mp3     # play audio only
mpv https://youtube.com/...  # play URL (with yt-dlp)
# Space -- pause, q -- quit, f -- fullscreen
# [ / ] -- slower / faster playback
```

### ffmpeg (video/audio processing)

```powershell
ffq -i input.mp4 -c:v libx264 output.mp4    # alias: convert video
ffq -i input.mp4 -ss 00:01:00 -t 30 clip.mp4 # extract 30s clip
ffq -i input.mp4 -vn -acodec mp3 audio.mp3   # extract audio
ffq -i input.mov -vf scale=1280:720 output.mp4 # resize
```

### Image tools

```powershell
# Compress images (lossless)
oxipng -o 4 image.png        # lossless PNG compression
jpegoptim --strip-all photo.jpg  # lossless JPEG compression

# Batch compress
fd -e png -x oxipng -o 4 {}  # compress all PNGs in project

# Resize / convert (ImageMagick)
magick input.png -resize 800x600 output.png   # resize image
magick input.png output.jpg                    # convert format
magick input.png -quality 85 output.jpg        # set quality
```

### yt-dlp (video downloader)

```powershell
ytdl https://youtube.com/watch?v=...     # alias: download video
ytmp3 https://youtube.com/watch?v=...    # alias: download as MP3
yt-dlp -f best URL                       # best quality
yt-dlp --list-formats URL                # show available formats
```

### Archives (7-Zip)

```powershell
7z a archive.7z files\       # create 7z archive
7z x archive.7z              # extract
7z l archive.zip             # list contents
7z a -tzip archive.zip files\ # create zip specifically
```

### cmus (terminal music player)

```powershell
cmus                         # launch the TUI
# Inside cmus:
#   1–7 — switch views (library, playlist, queue, browser, filters, settings)
#   a   — add directory to library    c — pause    x — play    v — stop
#   b / z — next / previous track     s / r — shuffle / repeat
#   / — search      q — quit
# On Windows, audio routing depends on the Scoop build; may require WASAPI setup.
```

### w3m (terminal web browser)

```powershell
w3m https://example.com      # open URL in terminal
w3m -dump https://example.com  # dump rendered text to stdout
# Inside w3m: Tab — next link, Enter — follow, B — back, U — enter URL, q — quit
```

### monolith (save pages as single HTML)

```powershell
monolith https://example.com -o page.html
monolith https://example.com -o page.html --no-js --no-audio
# Embeds CSS, JS, images, and fonts inline — single-file web archive.
```

---

## Terminal Multiplexing

Use **Windows Terminal tabs and panes** as the built-in terminal multiplexer:

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+T` | New tab |
| `Alt+Shift+D` | Split pane (auto direction) |
| `Alt+Shift+-` | Split pane horizontally |
| `Alt+Shift+=` | Split pane vertically |
| `Alt+Arrow` | Navigate between panes |
| `Ctrl+Shift+W` | Close pane |

### zellij

zellij is available on Windows and provides a richer multiplexer experience:

```powershell
zellij                       # start new session
zellij -s work               # named session
zellij attach work           # reattach
zellij ls                    # list sessions
```

Zellij shows keyboard hints at the bottom. No prefix key needed for common actions:

| Key | Action |
|-----|--------|
| `Alt+N` | New pane |
| `Alt+Arrow` | Navigate panes |
| `Alt+[/]` | Switch tabs |
| `Ctrl+T` | Tab mode |
| `Ctrl+P` | Pane mode |
| `Ctrl+Q` | Quit |

---

## Shell Scripting

### gum (interactive shell UI)

```powershell
# Ask a question
gum input --placeholder "What's the project name?"

# Choose from options
gum choose "Option 1" "Option 2" "Option 3"

# Confirm
gum confirm "Deploy to production?"

# Show a spinner
gum spin --title "Building..." -- npm run build

# Styled text
gum style --border rounded "Hello, World!"
```

### nushell (structured data shell)

```powershell
nu                           # start nushell

# Pipelines output tables, not strings
ls | where size > 1mb | sort-by modified
ps | where cpu > 5
open data.json | get users | where age > 30

# Built-in data operations
http get https://api.example.com | get data
```

### watchexec (file watcher)

```powershell
watchexec --exts ts -- npm test          # run tests on change
watchexec --exts py -- python main.py    # restart Python on change
watchexec -w src\ -- npm run build       # watch specific directory
```

### just (task runner)

```powershell
# Project justfile (like Makefile but simpler)
just                         # run default recipe
just test                    # run test recipe
just deploy prod             # run with arguments

# Global justfile recipes
gj update                    # update everything
gj info                      # system info
gj docker-clean              # prune Docker
gj kill-port 3000            # kill process on port
gj cheat curl                # show tldr cheatsheet
gj uuid                      # generate UUID
gj loc                       # count lines of code
```

### parallel (GNU parallel)

```powershell
# Process files in parallel
fd -e png | parallel oxipng -o 4 {}
# Run commands across servers
parallel ssh {} uptime ::: server1 server2 server3
```

---

## Infrastructure

### OpenTofu (Terraform alternative)

```powershell
tofu init                    # initialize providers
tofu plan                    # preview changes
tofu apply                   # apply changes
tofu destroy                 # tear down
```

### tflint (Terraform linter)

```powershell
tflint                       # lint current directory
tflint --init                # install plugins
tflint --recursive           # lint all modules
```

### infracost (cost estimation)

```powershell
infracost breakdown --path . # show cost breakdown
infracost diff --path .      # show cost difference vs current
```

### age + sops (secret management)

```powershell
# age: file encryption
age-keygen -o key.txt        # generate key
age -r age1... -o secret.enc secret.txt  # encrypt
age -d -i key.txt secret.enc # decrypt

# sops: encrypt secrets in config files
sops --encrypt --age age1... secrets.yaml  # encrypt YAML
sops secrets.yaml            # edit encrypted file in place
sops --decrypt secrets.yaml  # decrypt to stdout
```

---

## Windows System Settings (Registry Edits)

The script applies these registry tweaks. Settings marked "requires Admin" are skipped when running without elevation.

### Keyboard

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKCU:\Control Panel\Keyboard\KeyboardSpeed` | `31` | Maximum repeat rate |
| `HKCU:\Control Panel\Keyboard\KeyboardDelay` | `0` | Minimum repeat delay |

### File Explorer

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKCU:\...\Explorer\Advanced\Hidden` | `1` | Show hidden files |
| `HKCU:\...\Explorer\Advanced\HideFileExt` | `0` | Show file extensions |

### Start Menu and Search

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKCU:\...\Policies\...\Explorer\DisableSearchBoxSuggestions` | `1` | Disable web search in Start Menu / Bing suggestions |

### Copilot (requires Admin)

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKLM:\...\Policies\...\WindowsCopilot\TurnOffWindowsCopilot` | `1` | Disable Windows Copilot |

### Animations

The script modifies the `UserPreferencesMask` byte array in `HKCU:\Control Panel\Desktop` to clear the animation bit, reducing UI animations system-wide.

### Taskbar

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKCU:\...\Explorer\Advanced\TaskbarSi` | `0` | Small taskbar |
| `HKCU:\...\Explorer\Advanced\ShowTaskViewButton` | `0` | Hide Task View button |
| `HKCU:\...\Explorer\Advanced\TaskbarDa` | `0` | Hide Widgets |
| `HKCU:\...\Explorer\Advanced\TaskbarMn` | `0` | Hide Chat |

Default pinned apps are also cleared from the taskbar (Favorites and layout XML removed) so you can pin your own apps via right-click.

### Input

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKCU:\...\TabletTip\1.7\EnableAutocorrection` | `0` | Disable autocorrect |
| `HKCU:\...\TabletTip\1.7\EnableSpellchecking` | `0` | Disable spell-check |

### DNS (requires Admin)

Sets DNS servers on all active physical network adapters:

- Primary: `1.1.1.1` (Cloudflare), `1.0.0.1` (Cloudflare)
- Secondary: `9.9.9.9` (Quad9), `8.8.8.8` (Google)

### Windows Update (requires Admin)

| Registry Path | Value | Effect |
|---------------|-------|--------|
| `HKLM:\...\WindowsUpdate\AU\NoAutoRebootWithLoggedOnUsers` | `1` | Prevent auto-reboot while logged in |

---

## File Explorer Quick Access

The script pins these folders to Quick Access in File Explorer:

- Code, Screenshots, Scripts, Documents, Reference, Creative, Media, Projects, Archive, Downloads

---

## GUI App Recommended Settings

Settings the script cannot configure programmatically. Set these up manually after install.

### Brave Browser

1. **Import bookmarks:** Brave Settings > Bookmarks > Import
2. **Extensions:** uBlock Origin (pre-installed), React DevTools, axe DevTools, JSON Formatter, Lighthouse
3. **Privacy:** Settings > Shields > Aggressive mode for trackers
4. **Default search:** Settings > Search engine > DuckDuckGo or Brave Search

### Firefox

1. **Privacy:** Settings > Privacy & Security > Strict tracking protection
2. **Extensions:** uBlock Origin, React DevTools, axe DevTools
3. **Developer tools:** Settings > Developer Tools > enable browser console

### VS Code

Already configured by the script. Additional recommended steps:
1. **Sign in for Settings Sync:** Ctrl+Shift+P > "Settings Sync: Turn On"
2. **GitHub Copilot:** Install extension, sign in with GitHub
3. **Keyboard shortcuts:** The script installs 21 keybindings (see SHORTCUTS.md)

### Zed

Already configured by the script with Dracula theme. Additional:
1. **Sign in:** Zed > Sign In for collaboration features
2. **AI integration:** Settings > AI > configure Claude or Copilot
3. **Vim mode:** Already enabled by default in script config

### TablePlus

1. **Add connections:** Click "+" to add database connections
2. **Keyboard shortcuts:** Ctrl+Enter to run query, Ctrl+S to save
3. **Theme:** Preferences > Appearance > Dark mode
4. **Export:** Right-click table > Export (CSV, JSON, SQL)

### Bruno (API Client)

1. **Create a collection:** New Collection > choose a directory (git-friendly)
2. **Import from Postman:** Collection > Import > Postman Collection
3. **Environment variables:** Environments > add dev/staging/prod configs
4. **Tests:** Each request supports pre-request and post-response scripts

### Notion

1. **Workspace setup:** Create team workspace or personal workspace
2. **Templates:** Explore template gallery for project management, docs, wikis
3. **Integrations:** Settings > Integrations > connect Slack, GitHub
4. **Web clipper:** Install Notion Web Clipper browser extension

### Slack

1. **Workspaces:** Add all your team workspaces
2. **Keyboard shortcuts:** Ctrl+K (quick switch), Ctrl+Shift+M (mentions)
3. **Notifications:** Preferences > Notifications > customize per-channel
4. **Sidebar:** Organize channels with sections

### Mullvad VPN

1. **Account:** Create account at mullvad.net (no email required, anonymous payment accepted)
2. **Auto-connect:** Settings > VPN settings > Launch on startup, Auto-connect
3. **Kill switch:** Settings > VPN settings > Always require VPN
4. **DNS:** Settings > VPN settings > Use custom DNS if needed
5. **Server:** Choose server location close to you for best performance

### Snagit

1. **Capture hotkey:** Preferences > Capture > set to `Ctrl+Shift+4` (or your preference)
2. **Output folder:** Preferences > Share > set default save location to `~\Screenshots`
3. **Editor:** Configure annotation defaults (font, colors, arrow style)
4. **Video:** Enable system audio recording if needed

---

## Claude Code

### Custom Slash Commands

20 custom commands are installed to `~\.claude\commands\`:

| Command | What it does |
|---------|-------------|
| `/pr-review` | Review current branch changes vs main |
| `/test-plan` | Generate test plan for recent changes |
| `/dep-audit` | Audit dependencies for vulnerabilities and bloat |
| `/quick-doc` | Generate docs for a file or function |
| `/cleanup` | Find dead code, unused imports, debug statements |
| `/security-scan` | Run gitleaks, semgrep, trivy, and dependency audits |
| `/perf-check` | Benchmark with hyperfine, load test with oha |
| `/docker-lint` | Lint Dockerfiles with hadolint, analyze layers with dive |
| `/iac-review` | Review Terraform/CDK with tflint, trivy, infracost |
| `/convert` | Convert between formats using pandoc, ffmpeg, magick, d2 |
| `/new-feature` | Full trunk-based workflow: issue, branch, implement, tests, PR |
| `/fix-bug` | Full trunk-based workflow: issue, branch, test-first fix, PR |
| `/create-readme` | Analyze codebase and generate comprehensive README |
| `/init-project` | Scaffold project with git, README, CLAUDE.md, CI, Docker |
| `/refactor` | Refactor with tests preserved, SOLID principles |
| `/add-endpoint` | Add API endpoint: types, handler, validation, tests, docs |
| `/add-component` | Add React component: TSX, tests, accessibility |
| `/ci-fix` | Diagnose and fix CI failures via gh run view + act |
| `/changelog` | Generate changelog (uses git-cliff if available) |
| `/commit-msg` | Generate conventional commit message from staged changes |

### Hooks (automatic)

- **Format on edit:** Auto-runs Prettier on JS/TS/CSS/JSON/MD files after Claude edits them
- **Lint Python:** Auto-runs ruff check + format on .py files after edits
- **Lint Dockerfile:** Auto-runs hadolint on Dockerfiles after edits

### Rules

Language-specific rules are in `~\.claude\rules\`:
- `workflow.md` -- Trunk-based development, PR-first approach
- `git.md` -- Conventional commits, branch naming
- `security.md` -- No hardcoded secrets, input validation
- `typescript.md` -- Strict mode, no `any`, zod for validation
- `python.md` -- uv for packages, ruff for linting, type hints
- `docker.md` -- Multi-stage builds, non-root, hadolint
- `iac.md` -- OpenTofu, tflint, infracost, resource tagging

---

## Cheat Sheet

### All Shell Aliases and Functions

| Alias / Function | Runs | Category |
|------------------|------|----------|
| `ls` | `eza --icons` | Files |
| `ll` | `eza -la --icons --git` | Files |
| `la` | `eza -a --icons` | Files |
| `lt` | `eza --tree --icons --level=3` | Files |
| `cat` | `bat --paging=never` | Files |
| `top` | `btop` | System |
| `du` | `dust` | System |
| `df` | `duf` | System |
| `psg` | `procs` | System |
| `ping2` | `gping` | Network |
| `dig2` | `doggo` | Network |
| `watch2` | `viddy` | System |
| `make` | `just` | Dev |
| `dl` | `aria2c` | Network |
| `lg` | `lazygit` | Git |
| `ghd` | `gh dash` | Git |
| `gdft` | `git dft` | Git |
| `gha` | `act` | Git |
| `lzd` | `lazydocker` | Docker |
| `k` | `kubectl` | K8s |
| `klog` | `stern` | K8s |
| `md` | `glow` | Docs |
| `y` | `yazi` | Files |
| `jx` | `fx` | Data |
| `serve` | `miniserve --color-scheme-dark dracula -qr .` | Dev |
| `csvp` | `csvlook` | Data |
| `ytdl` | `yt-dlp` | Media |
| `ytmp3` | `yt-dlp -x --audio-format mp3` | Media |
| `ffq` | `ffmpeg -hide_banner -loglevel warning` | Media |
| `md2pdf` | `pandoc -f markdown -t pdf` | Docs |
| `md2html` | `pandoc -f markdown -t html -s` | Docs |
| `md2docx` | `pandoc -f markdown -t docx` | Docs |
| `pip2` | `uv pip` | Python |
| `venv` | `uv venv` | Python |
| `pyrun` | `uv run` | Python |
| `gj` | `just --justfile $HOME\.justfile --working-directory .` | Dev |
| `bench` | `hyperfine` | Testing |
| `loadtest` | `oha` | Testing |
| `lint-sh` | `shellcheck` | Quality |
| `update` | `topgrade` | System |
| `sysinfo` | `fastfetch` | System |

### Directory Shortcuts

| Function | Path |
|----------|------|
| `cw` | `$HOME\Code\work` |
| `cper` | `$HOME\Code\personal` |
| `coss` | `$HOME\Code\oss` |
| `clearn` | `$HOME\Code\learning` |
| `cscratch` | `$HOME\Code\work\scratch` |
| `cscripts` | `$HOME\Scripts` |

Directory shortcuts use `Set-Location` instead of `z` (zoxide) since PowerShell functions cannot alias `z` the same way.

### Helper Script Shortcuts

| Function | Script |
|----------|--------|
| `nproj` | `$HOME\Scripts\bin\new-project.ps1` |
| `cwork` | `$HOME\Scripts\bin\clone-work.ps1` |
| `cpers` | `$HOME\Scripts\bin\clone-personal.ps1` |
| `dotback` | `$HOME\Scripts\bin\backup-dotfiles.ps1` |
| `pstats` | `$HOME\Scripts\bin\project-stats.ps1` |
| `cleandl` | `$HOME\Scripts\bin\clean-downloads.ps1` |
| `hc` | `$HOME\Scripts\bin\health-check.ps1` |
| `sshsetup` | `$HOME\Scripts\bin\setup-ssh.ps1` |
| `scoopsnap` | `$HOME\Scripts\bin\export-brewfile.ps1` |

### Global Justfile Recipes (`gj <recipe>`)

| Recipe | What it does |
|--------|-------------|
| `gj update` | Update everything via topgrade |
| `gj info` | System info via fastfetch |
| `gj flush-dns` | Flush DNS cache |
| `gj ports` | Show all listening ports |
| `gj rebase N` | Interactive rebase last N commits |
| `gj undo` | Undo last commit (keep changes) |
| `gj branches` | Recent branches by last commit |
| `gj standup` | Your commits since yesterday |
| `gj docker-clean` | Prune unused Docker resources |
| `gj docker-usage` | Show Docker disk usage |
| `gj docker-nuke` | Remove ALL Docker data |
| `gj ip` | Show public IP |
| `gj local-ip` | Show local IP |
| `gj kill-port 3000` | Kill process on port |
| `gj node-clean` | Show node_modules disk usage |
| `gj cheat curl` | Show tldr cheatsheet |
| `gj uuid` | Generate UUID |
| `gj loc` | Count lines of code |
| `gj serve 8080` | Serve current directory |
| `gj b64-encode "text"` | Base64 encode |
| `gj b64-decode "..."` | Base64 decode |

---

## Platform Differences from Linux/macOS

| Area | Linux/macOS | Windows |
|------|------------|---------|
| Shell | zsh | PowerShell |
| Alias syntax | `alias name="cmd"` | `Set-Alias` or `function name { cmd @args }` |
| Clipboard | `pbcopy`/`xclip` | `clip.exe` (built-in) |
| Open files | `open`/`xdg-open` | `Start-Process` or `Invoke-Item` |
| Trash | `trash-put`/`trash` | No `rm` override (use Recycle Bin) |
| Container runtime | Docker Engine / OrbStack | Docker Desktop |
| Profile file | `~/.zshrc` | `$PROFILE` (PowerShell) |
| Path separator | `/` | `\` (but most tools accept `/`) |
| Config paths | `~/.config/` | `$HOME\.config\` or `%APPDATA%\` |
| Some alias names | `ps`, `ping`, `dig` | `psg`, `ping2`, `dig2` (avoid built-in conflicts) |
| Python alias | `pip` | `pip2` (avoid built-in conflict) |

---

## Configs Created

The setup script creates/configures:

| Config | Location |
|--------|----------|
| PowerShell profile | `$PROFILE` |
| SSH config | `~\.ssh\config` |
| Global gitignore | `~\.gitignore_global` |
| Git config | `~\.gitconfig` |
| GPG agent | `~\.gnupg\` |
| npm config | `~\.npmrc` |
| EditorConfig | `~\.editorconfig` |
| Prettier | `~\.prettierrc` |
| curl config | `~\.curlrc` |
| Docker daemon | `~\.docker\daemon.json` |
| aria2 config | `~\.aria2\aria2.conf` |
| Starship prompt | `~\.config\starship` |
| Atuin history | `~\.config\atuin` |
| Glow (Markdown) | `~\.config\glow` |
| yt-dlp | `~\.config\yt-dlp` |
| gh-dash | `~\.config\gh-dash` |
| stern (K8s logs) | `~\.config\stern` |
| yazi (file manager) | `~\.config\yazi` |
| Global Justfile | `~\.justfile` |
| VS Code | Dracula theme, extensions, JetBrains Mono |
| Windows Terminal | Dracula color scheme |
| Alacritty | Dracula theme, JetBrains Mono |
| lazygit | Dracula theme, delta pager |
| k9s | Dracula skin |
| Explorer | Hidden files, file extensions |
| Registry | Keyboard, taskbar, animations, DNS |
| Claude Code | Custom commands, rules, hooks |

---

## Post-Install Next Steps

After running the setup script:

1. **Restart your terminal** or run: `. $PROFILE`
2. Generate SSH key: `ssh-keygen -t ed25519 -C "your_email@example.com"`
3. Add SSH key to GitHub: `gh ssh-key add ~\.ssh\id_ed25519.pub`
4. Set up ngrok: `ngrok config add-authtoken <TOKEN>`
5. Set up chezmoi: `chezmoi init && chezmoi add ~\.npmrc`
6. Enable BitLocker: Settings > Privacy & Security > Device Encryption
7. Enable Windows Firewall: Settings > Privacy & Security > Windows Security
8. Enable Clipboard History: Settings > System > Clipboard > Clipboard History
