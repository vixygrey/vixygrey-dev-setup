# macOS User Guide

Everything installed by `scripts/setup-dev-tools-mac.sh` -- tools, apps, workflows, aliases, and system configuration. Read top to bottom or jump to a section.

---

## Quick Start

After running the setup script, open a new terminal and try these:

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
update              # topgrade: brew, npm, pip, system updates

# System info
sysinfo             # fastfetch: quick hardware/software summary
```

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

# Delete safely (trash replaces rm)
rm file.txt         # moves to macOS Trash (recoverable)
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
| `rm` | `trash` | Moves to macOS Trash (recoverable) |
| `make` | `just` | Simpler task runner, no tab issues |
| `f` | `fd` | Fast file finder, simple syntax |
| `dft` | `difft` | Syntax-aware structural diff |
| `y` | `yazi` | Terminal file manager |
| `jx` | `fx` | Interactive JSON viewer |
| `md` | `glow` | Render Markdown in terminal |
| `wget` / `dl` | `aria2c` | Multi-connection downloader |

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

## Docker & Kubernetes

### OrbStack (Docker runtime)

OrbStack is a faster, lighter alternative to Docker Desktop on macOS (2-5x less memory). Both are installed by the setup script -- pick your preference.

1. **First launch:** Open OrbStack, it will set up Docker automatically
2. **Resource limits:** OrbStack > Settings > Resources > set memory limit (e.g. 8GB)
3. **Default builder:** OrbStack > Settings > Docker > Enable BuildKit (already the default)

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

### LuLu Firewall

macOS application firewall for monitoring and blocking outbound connections.

1. **First launch:** Grant Full Disk Access when prompted
2. **Rules:** Allow known apps (browsers, dev tools), block suspicious outbound connections
3. **Mode:** Block and alert mode (default) is recommended

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
fd -e png -x oxipng -o 4 {}  # compress all PNGs in project

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
| `Alt+←/→/↑/↓` | Navigate panes |
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

## GUI Apps

### Raycast

1. **Set as Spotlight replacement:** System Settings > Keyboard > Shortcuts > Spotlight > disable both. Then set Raycast hotkey to `Cmd+Space`
2. **Install extensions:** Raycast Store > search for: Clipboard History, GitHub, AWS, Docker, Notion, Brew, Kill Process, Color Picker
3. **Enable Clipboard History:** Raycast Settings > Extensions > Clipboard History > enable
4. **Window management:** Raycast Settings > Extensions > Window Management > enable (replaces Rectangle)

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
1. **Sign in for Settings Sync:** Cmd+Shift+P > "Settings Sync: Turn On"
2. **GitHub Copilot:** Install extension, sign in with GitHub
3. **Keyboard shortcuts:** The script installs 21 keybindings (see SHORTCUTS.md)

### TablePlus

1. **Add connections:** Click "+" to add database connections
2. **Keyboard shortcuts:** Cmd+Enter to run query, Cmd+S to save
3. **Theme:** Preferences > Appearance > Dark mode
4. **Export:** Right-click table > Export (CSV, JSON, SQL)

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
2. **Keyboard shortcuts:** Cmd+K (quick switch), Cmd+Shift+M (mentions)
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
2. **Output folder:** Preferences > Share > set default save location to `~/Screenshots`
3. **Editor:** Configure annotation defaults (font, colors, arrow style)
4. **Video:** Enable system audio recording if needed

### UniFi Identity Endpoint

1. **First launch:** Sign in with your Ubiquiti account
2. **Connect to NAS:** Enter your UniFi OS Console address
3. **Device management:** Enroll your Mac for network management

### Quick Look Plugins

Preview files in Finder by pressing Space:

| Plugin | Description |
|--------|-------------|
| QLMarkdown | Preview Markdown files |
| QLStephen | Preview extensionless plain text files |

Installed automatically by the setup script via Homebrew Cask.

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
- `workflow.md` — Trunk-based development, PR-first approach
- `git.md` — Conventional commits, branch naming
- `security.md` — No hardcoded secrets, input validation
- `typescript.md` — Strict mode, no `any`, zod for validation
- `python.md` — uv for packages, ruff for linting, type hints
- `docker.md` — Multi-stage builds, non-root, hadolint
- `iac.md` — OpenTofu, tflint, infracost, resource tagging

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
| `rm` | `trash` | Files |
| `make` | `just` | Dev |
| `f` | `fd` | Search |
| `dft` | `difft` | Diff |
| `y` | `yazi` | Files |
| `jx` | `fx` | Data |
| `dl` | `aria2c` | Network |
| `wget` | `aria2c` | Network |
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

### macOS-Specific Aliases

| Alias | Command | Notes |
|-------|---------|-------|
| `rm` | `trash` | Moves to macOS Trash (recoverable) |
| `open` | (native) | Opens files/URLs with default app |
| `pbcopy` | (native) | Copy to clipboard from pipe |
| `pbpaste` | (native) | Paste clipboard contents |

Use `/bin/rm` for permanent deletion.

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
| `cleandl` | Delete old files from ~/Downloads |
| `hc` | System health overview |
| `sshsetup` | Generate SSH key + add to GitHub |
| `brewsnap` | Export Brewfile snapshot |

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
| `gj ds-clean` | Remove .DS_Store files |
| `gj cheat curl` | Show tldr cheatsheet |
| `gj uuid` | Generate UUID |
| `gj loc` | Count lines of code |
| `gj serve 8080` | Serve current directory |
| `gj b64-encode "text"` | Base64 encode |
| `gj b64-decode "..."` | Base64 decode |

---

## System Configuration

The setup script configures these macOS defaults automatically via `defaults write`.

### Dock

- Small icon size (36px), no recent apps shown
- Scale minimize effect (faster than genie)
- Minimize windows into application icon
- Clears all default pinned apps (add your own by dragging)
- Mission Control: fixed Spaces order, fast animations, grouped by app
- Hot corners: all disabled to prevent accidental triggers

### Screenshots

- Save as PNG to `~/Screenshots` (not Desktop)
- No shadow on window captures
- No floating thumbnail after capture

### Finder

- Show all file extensions
- Show path bar and status bar
- Default to list view
- Search scoped to current folder
- Folders sorted first
- Hidden files visible
- `~/Library` folder unhidden
- No `.DS_Store` files on network or USB volumes
- Expanded save and print panels by default

### Keyboard & Input

- Fast key repeat (rate: 2, delay: 15)
- Press-and-hold for accents disabled (essential for Vim key repeat)
- Full keyboard access for all UI controls
- Disable auto-correct, auto-capitalization, smart quotes, smart dashes, period substitution
- Faster trackpad tracking speed (2.0)

### Screensaver & Display

- Screensaver at 45 minutes
- Display sleep at 2 hours (charger) / 1 hour 15 minutes (battery)

### Security

- Firewall: script checks status and prompts you to enable if not active
- FileVault: script checks status and prompts you to enable full-disk encryption
- Siri disabled for privacy

### DNS

- Configured to use 1.1.1.1 / 1.0.0.1 (Cloudflare), 9.9.9.9 (Quad9), 8.8.8.8 (Google)
- Previous DNS settings backed up to `~/.local/share/dev-setup/`
- DNS cache flushed after changes

### Spotlight

- Dev directories excluded from indexing (`~/Code`, `~/.config`, `node_modules`, caches)

### Software Update

- Automatic check and download enabled
- Automatic install of macOS updates disabled (manual control)
