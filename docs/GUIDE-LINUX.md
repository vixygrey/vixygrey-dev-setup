# Linux User Guide

Everything installed by `scripts/setup-dev-tools-linux.sh` -- tools, aliases, workflows, and system settings -- in one place.

> **Supports:** Ubuntu/Debian (apt), Fedora/RHEL (dnf), Arch/Manjaro (pacman)

---

## Quick Start

After running the setup script, **log out and back in** (for Docker group membership and zsh as default shell), then open a new terminal:

```bash
# Your new shell — aliases are already active
ls                  # eza with icons and colors
ll                  # long listing with git status
lt                  # tree view (3 levels)
cat ~/.zshrc        # syntax-highlighted file viewing (bat)
top                 # graphical system monitor (btop)

# Navigate with zoxide (learns your habits)
cd ~/Code/work      # first time: use cd as normal
cw                  # after that: zoxide remembers (alias)

# Search anything
rg "TODO" .         # ripgrep: fast text search
f "*.ts"            # fd: fast file search
fzf                 # interactive fuzzy finder (Ctrl+T in shell)

# Update everything at once
update              # topgrade: apt/dnf/pacman, npm, pip, system updates

# System info
sysinfo             # fastfetch: quick hardware/software summary
```

---

## Package Managers

The script auto-detects your distro and uses the appropriate package manager:

| Distro | Primary | Supplemental |
|--------|---------|-------------|
| Ubuntu/Debian | apt | snap, flatpak |
| Fedora/RHEL | dnf | snap, flatpak |
| Arch/Manjaro | pacman | snap, flatpak |

Additional package managers installed: Homebrew (Linuxbrew), npm, cargo, pip (via uv).

External repositories are added automatically for Docker, GitHub CLI, and Brave Browser on apt and dnf systems. Arch uses its official repos (plus AUR via yay for extras).

---

## Daily Workflow

### File Navigation

```bash
# List files (eza replaces ls)
ls                  # colorful listing with icons
ll                  # long listing with git status, permissions, size
la                  # include hidden files
lt                  # tree view, 3 levels deep

# Find files (fd replaces find)
f "config"          # find files matching "config"
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

# Alternative file manager (nnn — minimal, fast, keyboard-driven)
n                   # alias: nnn -de (detail view, open text in pager)
# Inside nnn: arrows to navigate, Enter to open, ! to spawn shell,
#             ^G cd-quit to parent shell, q to quit, ? for help
# Env vars: NNN_OPTS, NNN_COLORS, NNN_PLUG are pre-configured
```

### Searching

```bash
# Text search (ripgrep replaces grep)
rg "function"            # search current dir recursively
rg "TODO" --type ts      # search only TypeScript files
rg "error" -i            # case-insensitive
rg "api" -g "*.py"       # search only Python files
rg "class" -l            # list only filenames with matches
rg "import" -C 3         # show 3 lines of context

# Interactive fuzzy finder (fzf)
# Ctrl+T   — search files, paste path
# Alt+C    — search directories, cd into selection
# Ctrl+R   — search shell history (handled by atuin)

# Atuin (replaces shell history)
atuin search "docker"    # search history for docker commands
# Up arrow — browse recent commands
# Ctrl+R   — interactive search (fuzzy, full-text)
```

### File Operations

```bash
# View files (bat replaces cat)
cat file.ts         # syntax highlighting, line numbers
bat -p file.ts      # plain mode (no line numbers)
bat -l json data    # force language detection

# Edit quickly
nano file.txt       # enhanced nano (syntax highlighting, line numbers)

# Open files/URLs with default app
xdg-open file.pdf   # opens with default handler
open file.pdf       # alias: same thing (aliased to xdg-open)

# Clipboard (xclip aliases)
echo "text" | pbcopy    # alias: copy to clipboard (xclip -selection clipboard)
pbpaste                 # alias: paste from clipboard (xclip -selection clipboard -o)

# Delete safely (trash-put replaces rm)
rm file.txt         # moves to Trash (aliased to trash-put)
# To permanently delete: /bin/rm file.txt

# Disk usage
du                  # dust: visual disk usage tree
du ~/Code           # see what's using space
df                  # duf: colorful disk free table

# Process management
ps                  # procs: sortable process list
ps --tree           # process tree view

# Monitor ongoing cp/mv/dd/tar (progress)
prog                # alias: progress -m — live % for running coreutils
progress -w         # one-shot snapshot for all copy/move/dd ops
# Useful when you started a big `cp` in another pane and want live ETA.
```

---

## Modern CLI Replacements

Every standard Unix tool has a faster, modern alternative:

| You type | Actually runs | What it does |
|----------|--------------|--------------|
| `ls` | `eza --icons` | Colorful listing with file type icons |
| `ll` | `eza -la --icons --git` | Long listing with git status |
| `lt` | `eza --tree --icons --level=3` | Tree view |
| `cat` | `bat --paging=never` | Syntax highlighting, line numbers |
| `top` | `btop` | Graphical system monitor with charts |
| `du` | `dust` | Visual disk usage tree |
| `df` | `duf` | Colorful disk space table |
| `ps` | `procs` | Sortable process list, Docker-aware |
| `ping` | `gping` | Real-time latency graph |
| `dig` | `doggo` | Colorized DNS lookup with DoH/DoT |
| `watch` | `viddy` | Watch commands with diff highlighting |
| `hexdump` | `hexyl` | Colorized hex viewer |
| `rm` | `trash-put` | Moves to Trash safely |
| `make` | `just` | Simpler task runner, no tab issues |
| `f` | `fd` | Fast file finder, simple syntax |
| `dft` | `difft` | Syntax-aware structural diff |
| `y` | `yazi` | Terminal file manager |
| `jx` | `fx` | Interactive JSON viewer |
| `md` | `glow` | Render Markdown in terminal |
| `wget` / `dl` | `aria2c` | Multi-connection downloader |
| `tar` / `unzip` / `7z` | `ouch` | Universal archive tool -- auto-detects format |
| `open` | `xdg-open` | Open files/URLs with default app |
| `pbcopy` | `xclip -selection clipboard` | Copy to clipboard |
| `pbpaste` | `xclip -selection clipboard -o` | Paste from clipboard |

### Examples

```bash
# fd vs find
find . -name "*.ts" -not -path "*/node_modules/*"   # old way
fd -e ts                                              # new way (auto-ignores .gitignore)

# ripgrep vs grep
grep -r "TODO" --include="*.ts" .                    # old way
rg "TODO" --type ts                                  # new way (10x faster)

# dust vs du
du -sh */ | sort -rh                                 # old way
dust                                                 # new way (visual tree)

# sd vs sed (find & replace)
sed -i 's/oldName/newName/g' file.ts                 # old way
sd 'oldName' 'newName' file.ts                       # new way (no escaping regex)

# choose vs cut/awk (extract columns)
echo "a:b:c" | cut -d: -f2                           # old way
echo "a:b:c" | choose -f ':' 1                       # new way

# tldr vs man (quick help)
man tar                                              # dense, hard to read
tldr tar                                             # simplified with examples
```

---

## Data & JSON

### jq (JSON processor)

```bash
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

```bash
# Explore a JSON file interactively with live jq filtering
jnv data.json
# Type jq expressions and see results in real-time
```

### fx (interactive JSON viewer)

```bash
# Explore JSON interactively
jx data.json               # alias for fx
curl -s api.example.com | fx
# Use arrow keys to navigate, . to access fields
```

### yq (jq for YAML)

```bash
# Read a value from YAML
yq '.metadata.name' deployment.yaml

# Modify in place
yq -i '.spec.replicas = 3' deployment.yaml

# Convert YAML to JSON
yq -o json config.yaml
```

### miller (CSV/JSON/tabular data)

```bash
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

```bash
csvp data.csv               # alias: pretty-print CSV as table
csvcut -c name,email data.csv  # extract columns
csvgrep -c status -m "active" data.csv  # filter rows
csvstat data.csv             # summary statistics
```

### pandoc (document converter)

```bash
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

```bash
lg                           # alias: open lazygit
# s — stage/unstage files
# c — commit
# p — push
# P — pull
# b — branches
# Space — toggle stage
# q — quit
```

### GitHub CLI (gh)

```bash
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

```bash
# Generate changelog from conventional commits
git-cliff                    # full changelog to stdout
git-cliff --unreleased       # only unreleased changes
git-cliff -o CHANGELOG.md    # write to file
git-cliff v1.0.0..HEAD       # specific range
```

### Git Aliases

```bash
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

```bash
pre-commit install           # install hooks for current repo
pre-commit run --all-files   # run all hooks manually
pre-commit autoupdate        # update hook versions
```

---

## Docker

The setup installs **Docker Engine** (not Docker Desktop) via the official Docker repositories.

### Packages Installed

| Distro | Packages |
|--------|----------|
| Ubuntu/Debian | `docker-ce`, `docker-ce-cli`, `docker-buildx-plugin`, `docker-compose-plugin` |
| Fedora/RHEL | `docker-ce`, `docker-ce-cli`, `docker-buildx-plugin`, `docker-compose-plugin` |
| Arch/Manjaro | `docker`, `docker-buildx`, `docker-compose` |

Post-install steps handled by the script:

1. Adds current user to the `docker` group (re-login required to take effect)
2. Enables and starts the Docker service via `systemctl`

### Daemon Configuration

The daemon config lives at `/etc/docker/daemon.json`:

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

Key settings:

- **BuildKit** enabled by default for faster, cache-efficient builds
- **Log rotation**: 10 MB max per file, 3 files max (prevents disk fill from chatty containers)
- **Builder GC**: automatic garbage collection, keeps up to 20 GB of build cache
- **DNS**: Cloudflare + Google (avoids corporate DNS issues inside containers)

### lazydocker (Docker TUI)

```bash
lzd                          # alias: open lazydocker
# Navigate containers, images, volumes, networks
# Enter — view logs
# d — remove
# s — stop
# r — restart
```

### dive (Docker image inspector)

```bash
dive myapp:latest            # inspect image layers
# Tab — switch between layers and file tree
# See exactly what each layer adds to the image
```

---

## Kubernetes

### k9s (Kubernetes TUI)

```bash
k9s                          # open k9s
# : then type resource name (pods, deploy, svc)
# / — filter
# d — describe
# l — logs
# s — shell into pod
# Ctrl+D — delete
```

### stern (multi-pod log tailing)

```bash
klog                         # alias: stern
stern "api-*"                # tail all pods matching pattern
stern -n production api      # specific namespace
stern api --since 5m         # last 5 minutes
```

### kubectl shortcuts

```bash
k get pods                   # alias: kubectl get pods
k get svc                    # list services
k apply -f deploy.yaml       # apply config
k logs -f pod-name           # follow logs
```

---

## Database

### pgcli / mycli (auto-completing SQL)

```bash
pgcli -h localhost -U postgres mydb   # connect to PostgreSQL
mycli -h localhost -u root mydb       # connect to MySQL
# Tab — autocomplete table names, columns, SQL keywords
# \dt — list tables
# \d tablename — describe table
# Ctrl+D — quit
```

### lazysql (database TUI)

```bash
lazysql                      # interactive database TUI
# Connect to Postgres, MySQL, SQLite
# Browse tables, run queries, view results in a table
```

### harlequin (terminal SQL IDE)

Multi-tab SQL IDE with autocomplete, query history, and a results grid. Configured with the Dracula theme and vscode keymap at `~/.config/harlequin/config.toml`.

```bash
hq                           # alias for harlequin (opens last DB or DuckDB in-memory)
harlequin                    # explicit
harlequin file.duckdb        # open a DuckDB file
harlequin -P 5432 -u postgres mydb     # connect to Postgres
harlequin --adapter mysql -h localhost mydb   # connect to MySQL
```

Adapters bundled by the setup script: DuckDB (default), Postgres, MySQL, S3.

### sq (jq for databases)

```bash
sq inspect data.csv          # inspect a CSV file
sq '.data | .name, .email'   # query with jq-like syntax
sq @mydb '.users'            # query a database source
sq add mydb postgres://...   # add a database source
```

### dbmate (database migrations)

```bash
dbmate new create_users      # create a new migration
dbmate up                    # run pending migrations
dbmate down                  # rollback last migration
dbmate status                # show migration status
```

---

## Security & Scanning

### typos (spell checker for code)

```bash
typos .                      # check all files for typos
typos --diff                 # show what would be fixed
typos --write-changes        # auto-fix typos
typos src/                   # check specific directory
```

### ast-grep (structural code search)

```bash
# Find all console.log statements
ast-grep --pattern 'console.log($$$)' --lang ts

# Find unused variables (structural, not text)
ast-grep --pattern 'const $VAR = $_' --lang ts

# Interactive mode
ast-grep scan
```

### gitleaks (secret scanning)

```bash
gitleaks detect              # scan current repo for secrets
gitleaks detect --verbose    # show details
gitleaks protect             # pre-commit hook mode
```

### trivy (vulnerability scanning)

```bash
trivy fs .                   # scan filesystem for vulnerabilities
trivy image myapp:latest     # scan Docker image
trivy config .               # scan IaC (Terraform, Docker, K8s)
```

### semgrep (static analysis)

```bash
semgrep --config auto .      # auto-detect language, run rules
semgrep --config p/security-audit .  # security-focused rules
semgrep --config p/typescript .      # TypeScript-specific rules
```

---

## Testing & Benchmarking

### hyperfine (command benchmarking)

```bash
bench 'fd -e ts' 'find . -name "*.ts"'   # alias: compare two commands
hyperfine 'npm run build' 'bun run build' # compare build tools
hyperfine --warmup 3 'curl -s localhost'  # warm up before measuring
```

### oha (HTTP load testing)

```bash
loadtest http://localhost:3000           # alias: quick load test
oha -n 1000 -c 50 http://localhost:3000 # 1000 requests, 50 concurrent
oha -z 30s http://localhost:3000         # run for 30 seconds
```

### hurl (HTTP test files)

```bash
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

```bash
gha                          # alias: run default workflow
act -l                       # list all workflows
act push                     # simulate push event
act -j test                  # run specific job
```

### act3 (glance at last 3 GitHub Actions runs)

```bash
gha3                         # alias: view last 3 runs of every workflow
act3 -r owner/repo           # view runs for a specific repo
act3 -t html > status.html   # export HTML status page
# Requires a GitHub token: `gh auth login` or $GH_TOKEN
```

---

## Networking & Debugging

### mitmproxy (HTTP debugging proxy)

```bash
mitmproxy                    # interactive TUI proxy
# Configure browser/app to use localhost:8080 as proxy
# See all HTTP/HTTPS requests in real-time
# Press Enter on a request to inspect headers/body
```

### trippy (modern traceroute TUI)

```bash
trippy google.com            # traceroute with live charts
# Real-time hop-by-hop latency visualization
# Better than mtr for understanding network paths
```

### mtr (ping + traceroute combined)

```bash
mtr google.com               # combined ping and traceroute
mtr --report google.com      # generate a report
```

### bandwhich (bandwidth monitor)

```bash
sudo bandwhich               # see bandwidth by process
# Real-time view of which processes are using network
```

### nmap (network scanning)

```bash
nmap -sn 192.168.1.0/24     # discover hosts on network
nmap -p 1-1000 target        # scan ports
nmap -sV target              # detect service versions
```

### xh / curlie (HTTP clients)

```bash
xh httpbin.org/get           # GET request (colorized)
xh POST api.example.com/data name=John  # POST with JSON
xh -d api.example.com/file  # download file

curlie httpbin.org/get       # curl syntax, httpie output
curlie -X POST api.example.com -d '{"key":"val"}'
```

### sshclick (SSH config manager)

```bash
sshc host list                              # alias: list hosts in ~/.ssh/config
sshclick host add prod --hostname prod.example.com --user deploy
sshclick host show prod                     # show merged config for a host
sshclick group list                         # view host groups
# Organizes ~/.ssh/config with groups, comments, and safe edits.
```

---

## Media & Files

### mpv (video player)

```bash
mpv video.mp4                # play video
mpv --no-video music.mp3     # play audio only
mpv https://youtube.com/...  # play URL (with yt-dlp)
# Space — pause, q — quit, f — fullscreen
# [ / ] — slower / faster playback
```

### ffmpeg (video/audio processing)

```bash
ffq -i input.mp4 -c:v libx264 output.mp4    # alias: convert video
ffq -i input.mp4 -ss 00:01:00 -t 30 clip.mp4 # extract 30s clip
ffq -i input.mp4 -vn -acodec mp3 audio.mp3   # extract audio
ffq -i input.mov -vf scale=1280:720 output.mp4 # resize
```

### Image tools

```bash
# Compress images (lossless)
oxipng -o 4 image.png        # lossless PNG compression
jpegoptim --strip-all photo.jpg  # lossless JPEG compression

# Batch compress
fd -e png -x oxipng -o 4 {}  # compress all ONGs in project

# Resize / convert (ImageMagick)
resize 800x600 image.png     # alias: resize image
magick input.png output.jpg  # convert format
magick input.png -quality 85 output.jpg  # set quality
```

### yt-dlp (video downloader)

```bash
ytdl https://youtube.com/watch?v=...     # alias: download video
ytmp3 https://youtube.com/watch?v=...    # alias: download as MP3
yt-dlp -f best URL                       # best quality
yt-dlp --list-formats URL                # show available formats
```

### Archives (p7zip)

```bash
7z a archive.7z files/       # create 7z archive
7z x archive.7z              # extract
7z l archive.zip             # list contents
7z a -tzip archive.zip files/ # create zip specifically
```

### cmus (terminal music player)

```bash
cmus                         # launch the TUI
# Inside cmus:
#   1–7 — switch views (library, playlist, queue, browser, filters, settings)
#   a   — add directory to library
#   c   — toggle pause     x — play     v — stop
#   b / z — next / previous track
#   s / r — toggle shuffle / repeat
#   /   — search current view    q — quit
# Config: ~/.config/cmus/rc (Dracula colors pre-configured)
```

### w3m (terminal web browser)

```bash
w3m https://example.com      # open URL in terminal
w3m -dump https://example.com  # dump rendered text to stdout
w3m -T text/html local.html  # render a local HTML file
# Inside w3m:
#   Tab — next link    Enter — follow link
#   B   — back         U — enter URL     a — add bookmark
#   q   — quit         h — help
# Config: ~/.w3m/config (UTF-8, cookies off by default)
```

### monolith (save pages as single HTML)

```bash
monolith https://example.com -o page.html
monolith https://example.com -o page.html --no-js --no-audio
monolith -o bundle.html /tmp/local.html     # bundle a local file with deps
# Embeds CSS, JS, images, and fonts inline — single-file web archive.
```

---

## Terminal Multiplexing

### zellij

```bash
zellij                       # start new session
zellij -s work               # named session
zellij attach work           # reattach
zellij ls                    # list sessions
```

Zellij shows keyboard hints at the bottom. No prefix key needed for common actions:

| Key | Action |
|-----|--------|
| `Alt+N` | New pane |
| `Alt+left/right/up/down` | Navigate panes |
| `Alt+[/]` | Switch tabs |
| `Ctrl+T` | Tab mode |
| `Ctrl+P` | Pane mode |
| `Ctrl+Q` | Quit |

---

## Shell Scripting

### gum (interactive shell UI)

```bash
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

```bash
nu                           # start nushell

# Pipelines output tables, not strings
ls | where size > 1mb | sort-by modified
ps | where cpu > 5
open data.json | get users | where age > 30

# Built-in data operations
http get https://api.example.com | get data
```

### watchexec (file watcher)

```bash
watchrun                     # alias: watch .ts/.tsx files and restart
watchexec --exts ts -- npm test          # run tests on change
watchexec --exts py -- python main.py    # restart Python on change
watchexec -w src/ -- npm run build       # watch specific directory
```

### just (task runner)

```bash
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

```bash
par                          # alias: parallel
# Process files in parallel
fd -e png | parallel oxipng -o 4 {}
# Run commands across servers
parallel ssh {} uptime ::: server1 server2 server3
```

---

## Infrastructure

### OpenTofu (Terraform alternative)

```bash
tofu init                    # initialize providers
tofu plan                    # preview changes
tofu apply                   # apply changes
tofu destroy                 # tear down
```

### tflint (Terraform linter)

```bash
tflint                       # lint current directory
tflint --init                # install plugins
tflint --recursive           # lint all modules
```

### infracost (cost estimation)

```bash
infracost breakdown --path . # show cost breakdown
infracost diff --path .      # show cost difference vs current
```

### age + sops (secret management)

```bash
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

## GNOME Desktop Settings

The setup script configures GNOME with these defaults (skipped automatically if `gsettings` is not available):

| Setting | Value | Description |
|---------|-------|-------------|
| `peripherals.keyboard repeat-interval` | `30` | Fast keyboard repeat rate |
| `peripherals.keyboard delay` | `200` | Short key repeat delay |
| `nautilus.preferences show-hidden-files` | `true` | Show dotfiles in Nautilus |
| `interface enable-animations` | `false` | Disable UI animations |
| `interface color-scheme` | `prefer-dark` | System-wide dark mode |
| `interface gtk-theme` | `Adwaita-dark` | Dark GTK theme |
| `dash-to-dock autohide` | `true` | Auto-hide the dock |
| `dash-to-dock dash-max-icon-size` | `40` | Smaller dock icons |
| `gnome-screenshot auto-save-directory` | `~/Screenshots` | Screenshot save location |
| `session idle-delay` | `900` | Screen lock after 15 min idle |
| `interface show-battery-percentage` | `true` | Show battery % in top bar |
| `peripherals.touchpad tap-to-click` | `true` | Tap to click enabled |
| `peripherals.touchpad natural-scroll` | `true` | Natural (reverse) scrolling |

On a fresh install (no existing favorites), the dock favorites are reset to just Nautilus. The script also sets the wallpaper via `gsettings set org.gnome.desktop.background`.

### KDE Plasma Support

If KDE Plasma is detected (`$XDG_CURRENT_DESKTOP` contains `KDE`), the script clears default pinned apps from the taskbar by removing launchers from `~/.config/plasma-org.kde.plasma.desktop-appletsrc`. Wallpaper is set via `qdbus` on KDE, and `feh` is used as a fallback for tiling window managers (i3, sway, bspwm, etc.).

---

## GNOME Tracker Indexing

The setup creates `.trackerignore` files in directories that should be excluded from GNOME Tracker (desktop search indexing):

- `~/Code/.trackerignore`
- `~/.config/.trackerignore`

This prevents Tracker from indexing `node_modules`, build artifacts, and other dev files that would slow down search and waste resources.

---

## File Manager Sidebar Bookmarks

The script writes `~/.config/gtk-3.0/bookmarks` with these sidebar entries (works with Nautilus, Thunar, Nemo, Caja):

- Code, Screenshots, Scripts, Documents, Reference, Creative, Media, Projects, Archive, Downloads

Any existing user bookmarks not in the curated list are preserved.

---

## DNS Configuration

On systems running `systemd-resolved`, the script creates `/etc/systemd/resolved.conf.d/dns.conf`:

```ini
[Resolve]
DNS=1.1.1.1 1.0.0.1 9.9.9.9 8.8.8.8
FallbackDNS=8.8.4.4
```

If `systemd-resolved` is not active, DNS must be configured manually in `/etc/resolv.conf`.

---

## NTP (Time Sync)

The script enables NTP via:

```bash
sudo timedatectl set-ntp true
```

Timezone is left at the system default. Uncomment and edit the `timedatectl set-timezone` line in the script to set a specific timezone.

---

## Software Updates

On Ubuntu/Debian (`apt`), the script runs `dpkg-reconfigure -plow unattended-upgrades` to configure automatic security updates.

---

## Autostart Applications

The script creates `.desktop` entries in `~/.config/autostart/` for:

- **Flameshot** (screenshot tool) -- starts at login if installed

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

### Ghostty (Terminal)

Already configured by the script with Dracula theme and JetBrains Mono font. Optional tweaks:
1. **Font size:** Edit `~/.config/ghostty/config`, change `font-size`
2. **Opacity:** Add `background-opacity = 0.95` for slight transparency
3. **Shell integration:** Automatic (zsh integration built-in)

### VS Code

Already configured by the script. Additional recommended steps:
1. **Sign in for Settings Sync:** Ctrl+Shift+P > "Settings Sync: Turn On"
2. **GitHub Copilot:** Install extension, sign in with GitHub
3. **Keyboard shortcuts:** The script installs 21 keybindings (see SHORTCUTS.md)

### Postman (API Client)

1. **Sign in:** Sign in with your Postman account to sync collections across devices
2. **Create a collection:** New > Collection > organize requests by service or feature
3. **Environments:** Environments tab > add dev/staging/prod with variables
4. **Tests:** Each request supports pre-request and test scripts (Tests tab)
5. **Import:** File > Import supports OpenAPI, cURL, and other Postman exports

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

---

## Claude Code

### Custom Slash Commands

20 custom commands are installed to `~/.claude/commands/`:

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

Language-specific rules are in `~/.claude/rules/`:
- `workflow.md` -- Trunk-based development, PR-first approach
- `git.md` -- Conventional commits, branch naming
- `security.md` -- No hardcoded secrets, input validation
- `typescript.md` -- Strict mode, no `any`, zod for validation
- `python.md` -- uv for packages, ruff for linting, type hints
- `docker.md` -- Multi-stage builds, non-root, hadolint
- `iac.md` -- OpenTofu, tflint, infracost, resource tagging

---

## Cheat Sheet

### All Shell Aliases

| Alias | Runs | Category |
|-------|------|----------|
| `ls` | `eza --icons` | Files |
| `ll` | `eza -la --icons --git` | Files |
| `la` | `eza -a --icons` | Files |
| `lt` | `eza --tree --icons --level=3` | Files |
| `cat` | `bat --paging=never` | Files |
| `top` | `btop` | System |
| `du` | `dust` | System |
| `df` | `duf` | System |
| `ps` | `procs` | System |
| `ping` | `gping` | Network |
| `dig` | `doggo` | Network |
| `watch` | `viddy` | System |
| `hexdump` | `hexyl` | Files |
| `rm` | `trash-put` | Files |
| `make` | `just` | Dev |
| `f` | `fd` | Search |
| `dft` | `difft` | Diff |
| `y` | `yazi` | Files |
| `jx` | `fx` | Data |
| `dl` | `aria2c` | Network |
| `wget` | `aria2c` | Network |
| `open` | `xdg-open` | System |
| `pbcopy` | `xclip -selection clipboard` | System |
| `pbpaste` | `xclip -selection clipboard -o` | System |
| `lg` | `lazygit` | Git |
| `ghd` | `gh dash` | Git |
| `gdft` | `git dft` | Git |
| `gha` | `act` | Git |
| `lzd` | `lazydocker` | Docker |
| `k` | `kubectl` | K8s |
| `klog` | `stern` | K8s |
| `md` | `glow` | Docs |
| `serve` | `miniserve --color-scheme-dark dracula -qr .` | Dev |
| `csvp` | `csvlook` | Data |
| `ytdl` | `yt-dlp` | Media |
| `ytmp3` | `yt-dlp -x --audio-format mp3` | Media |
| `resize` | `magick mogrify -resize` | Media |
| `ffq` | `ffmpeg -hide_banner -loglevel warning` | Media |
| `md2pdf` | `pandoc -f markdown -t pdf` | Docs |
| `md2html` | `pandoc -f markdown -t html -s` | Docs |
| `md2docx` | `pandoc -f markdown -t docx` | Docs |
| `pip` | `uv pip` | Python |
| `venv` | `uv venv` | Python |
| `pyrun` | `uv run` | Python |
| `gj` | `just --justfile ~/.justfile` | Dev |
| `watchrun` | `watchexec --exts ts,tsx --restart` | Dev |
| `bench` | `hyperfine` | Testing |
| `loadtest` | `oha` | Testing |
| `par` | `parallel` | Dev |
| `lint-sh` | `shellcheck` | Quality |
| `fmt-sh` | `shfmt -w -i 4` | Quality |
| `update` | `topgrade` | System |
| `sysinfo` | `fastfetch` | System |
| `hq` | `harlequin` | Database |

### Directory Shortcuts

| Alias | Jumps to |
|-------|----------|
| `cw` | `~/Code/work` |
| `cper` | `~/Code/personal` |
| `coss` | `~/Code/oss` |
| `clearn` | `~/Code/learning` |
| `cscratch` | `~/Code/work/scratch` |
| `cscripts` | `~/Scripts` |

### Helper Scripts

| Alias | What it does |
|-------|-------------|
| `nproj` | Scaffold new project with git + .editorconfig |
| `cwork` | Clone work repo into `~/Code/work/<org>/<repo>` |
| `cpers` | Clone personal repo into `~/Code/personal/<repo>` |
| `dotback` | Push dotfiles via chezmoi |
| `pstats` | Show repo counts, disk usage |
| `cleandl` | Delete old files from ~/Downloads (uses `trash-put`) |
| `hc` | System health overview |
| `sshsetup` | Generate SSH key + add to GitHub |

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

## Post-Install Next Steps

After running the setup script:

1. **Log out and back in** (for Docker group membership and zsh as default shell)
2. Open a new terminal or run: `source ~/.zshrc`
3. Generate SSH key: `ssh-keygen -t ed25519 -C "your_email@example.com"`
4. Add SSH key to GitHub: `gh ssh-key add ~/.ssh/id_ed25519.pub`
5. Set up ngrok: `ngrok config add-authtoken <TOKEN>`
6. Set up chezmoi: `chezmoi init && chezmoi add ~/.zshrc`
