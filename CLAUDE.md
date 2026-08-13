# CLAUDE.md — vixygrey-dev-setup

Guidance for AI agents working in this repo. Read this before editing.

## What this repo is

A single idempotent Bash script, [`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh) (~10k lines), that provisions a macOS developer machine: installs CLI/GUI tools via Homebrew, writes dotfiles/config, and **generates the user's Claude Code environment** — `~/.claude/CLAUDE.md`, `~/.claude/rules/*`, agents, commands, skills, MCP servers — plus Desktop docs (`POST_SETUP_CHECKLIST.md`, `TOOL_REFERENCE.md`, `KEYBOARD_SHORTCUTS.md`, `TOOLKIT_SUMMARY.md`). Almost all work happens in that one script.

## The golden rule: edit the generator, never the output

Config files, the user's `~/.claude/CLAUDE.md`, the pre-commit hook, and the Desktop docs are all **generated** by the script — usually inside a quoted heredoc. To change any of them, edit the heredoc **in the script**, not the produced file (which gets overwritten on the next run). Generated files carry a managed-block marker: `# >>> dev-setup managed block (do not edit between the markers) >>>`.

## Two delivery paths — a fix that only lands on fresh installs is half a fix

Most breakage found in this repo has the same shape: **the generator is correct, but the machine never receives the correction.** Before calling anything done, ask *how does this reach a machine that was already provisioned?*

- **Files written with `write_managed`/`write_managed_script`** refresh on every run. Nothing more to do.
- **`~/.claude/settings.json` is different** — the `configs` block only writes the full heredoc when the file is *absent*. Existing machines take the `jq` **merge branch**, which must be taught about the change explicitly. #206 fixed schema-invalid hooks in the heredoc; without the matching merge-branch migration, every already-provisioned machine would have kept the broken hooks forever.
- **The Claude `settings.json` allowlist is two lists, and they are not the same list.** The fresh-machine heredoc (`CLAUDE_SETTINGS_CONF`) is the actual grant set — read *that* to see what is auto-approved, and it already uses binary names (`Bash(trip *)`, not `Bash(trippy *)`). The merge branch's `CLAUDE_DENY_ALLOW` / `CLAUDE_STALE_ALLOW` variables are **removal** lists that *strip* dangerous or dead auto-approvals from already-provisioned machines. So a package-named entry like `Bash(dynein *)` sitting in those variables is a removal target, **not** a live dead grant — don't "fix" it. Extract the heredoc and run it through `jq` before flagging anything in the allowlist; a finding built on the strip lists was retracted mid-audit (the #209 pattern).
- **Anything guarded by `if [[ -f … ]]` / `if [[ -d … ]]` is create-once** and silently freezes. That is exactly how the global `CLAUDE.md` and `rules/` drifted 33 lines and eight tool names behind the generator (#226). Prefer `write_managed`.
- **Retiring a tool is not the same as cleaning up after it.** `--cleanup` uninstalls the package; its config dir, its tap, and its orphaned dependencies each needed separate handling (#210, #214, #224).

## Audit the generator, not your own machine

The generated output on the machine you are working on may be **older than the script**, so a "bug" you find there may already be fixed. During #209 the local `CLAUDE.md` showed `kew`/`snyk`/`tmux` as stale references; all three had already been corrected upstream and the finding had to be retracted.

Extract the heredoc and inspect *that*:

```bash
awk "/<<'CLAUDE_MD_CONF'/{f=1;next} /^CLAUDE_MD_CONF\$/{f=0} f" scripts/setup-dev-tools-mac.sh > /tmp/gen.md
```

The same applies to validating generated JSON/TOML — extract and run it through `jq`/`zsh -n` rather than trusting the heredoc by eye.

## Generated config must match the consuming tool's real schema

Unknown keys are often **silently ignored**, so "no error" is not evidence a setting works. `fileSuggestionSettings` sat in the generated `settings.json` for releases doing nothing — Claude Code has no such key (#206). Verify against the tool's documented schema, or grep its binary, before shipping a config block.

Related: **name the binary, not the package.** `trippy`→`trip`, `nushell`→`nu`, `dynein`→`dy`, `imagemagick`→`magick`, `csvkit`→`csvlook`. A permission rule or doc line naming the package never matches (#206, #209).

Same for **generated docs**: a checklist step, `TOOL_REFERENCE` entry, or `CLAUDE.md` line can promise a tool, backend, default provider, or example command that the script never installs or that does not exist. The docs advertised a local **Ollama** backend for herald's AI and `croft pair --provider ollama` that nothing installed — a "local, no-key" path that was dead until the install was added (#237); and the `ni` entry documented an `nx` command that `@antfu/ni` does not ship — the package-binary runner is `nlx` (#238). Cross-check every tool / backend / default / example command a generated doc names against the install calls (`brew_install`/`go_install`/`npm_global_install`/…) and, for commands, the package's real `bin` keys.

## Generated shell config is inherited by agents and scripts

`~/.zshrc` is sourced by non-interactive shells, so anything defined there reaches Claude Code and any script. Aliases are an interactive convenience and **must be gated** — every modern replacement rejects the original's flags (`du -sh` prints dust's help, `rm -rf` is rejected by trash), and the quiet ones are worse (`ps aux`, `dig +short` silently ignore the argument). Gate the whole section on `[[ -o interactive && -z "$CLAUDECODE" && -z "$AI_AGENT" ]]` rather than enumerating hazards — the enumerate approach already failed once, letting `wget` through (#218, #220).

## Removing user data needs two guards

`--cleanup` deletes things people may still want. Every removal must:

1. **Verify the owner is actually gone** — check the `.app` is absent or `command -v <tool>` fails, so a manual reinstall is never gutted.
2. **Prefer `trash` over `rm -rf`** so a mistake is recoverable from Finder.

And beware paths that *look* orphaned but aren't: `~/.docker` reads as Docker Desktop residue, but OrbStack took it over (`currentContext: orbstack`, registry `auths`). Removing it would break the docker CLI and destroy credentials — it is excluded with a comment saying why (#214).

## Conventions that are easy to get wrong

- **Idempotency is mandatory.** Every run must be safe to repeat. Use the existing guards: `mark_done`/`is_done "<key>"`, and the `brew_install` / `brew_cask_install` / `npm_global_install` / `go_install` / `uv_tool_install` helpers (they snapshot installed state and skip work already done). Don't call `brew install` directly.
- **Honor `--dry-run`.** Any block with side effects must do nothing when `$DRY_RUN == "true"` (print an `info "[DRY RUN] Would …"` line instead). `write_managed`/`write_managed_script` already handle this; raw `git`/`curl`/`cp`/`ln`/`mkdir` blocks you add must guard themselves.
- **Write files with the managed helpers**, not ad-hoc redirection:
  - `write_managed <file> [comment-prefix]` — wraps stdin in a managed block (refreshes in place on re-run; backs up+replaces an unmarked pre-existing file).
  - `write_managed_script <file>` — same, for executables; keeps the shebang on line 1 and `chmod +x`.
- **Logging/UX helpers:** `info`, `success`, `warn`, `error`, `banner`, `progress`. Everything verbose goes to `$LOG_FILE` via `log`.
- **Guard on tool presence** with `installed <cmd>` before using an optional tool.
- **Heredoc quoting:** use `<<'MARKER'` (quoted) for literal content — this is the default, and it keeps `$` and backticks literal (most generated files rely on this). Only use an unquoted heredoc when you deliberately want the script's variables expanded.

## Testing / verification loop (do this before every commit)

1. `bash -n scripts/setup-dev-tools-mac.sh` — syntax.
2. `shellcheck -S warning scripts/setup-dev-tools-mac.sh` — **this is what CI runs** (`.github/workflows/lint.yml`). Keep it clean.
3. `./scripts/setup-dev-tools-mac.sh --dry-run` (or `--only <category>`) — preview without mutating the machine.
4. When you change a generated file, extract and exercise it in a throwaway dir rather than trusting the heredoc by eye (e.g. the pre-commit hook was tested against sample staged files in a temp `git init`).

Useful flags: `--dry-run`, `--list`, `--list-categories`, `--only <cats>`, `--skip <cats>`, `--interactive/-i`, `--resume`, `--cleanup`, `--uninstall`, `--version`.

## The generated pre-commit hook

The script installs a **global** hook (`git config --global core.hooksPath ~/.config/git/hooks`) that runs on all repos. It checks for debug statements (language-scoped: JS/TS `console.log`/`debugger`, Python pdb/`breakpoint()`, Ruby `binding.pry`), files >5 MB, and merge-conflict markers. Two things to know:

- A change to the hook only takes effect **after the script is re-run** to regenerate it. So editing the hook's heredoc will not stop the *currently installed* (old) hook from firing on your very next commit — that commit may still need `--no-verify`.
- To whitelist an intentional debug token on a line, add a trailing **`debug-ok`** comment. Prefer that over `--no-verify`.

## Commits, PRs, CHANGELOG

- Trunk-based: branch off `main` (`feature/`, `fix/`, `chore/`, `docs/`), open a PR, squash-merge. Conventional commit messages.
- **CHANGELOG.md** is hand-written from 7.2.0 onward. Add entries under `## [Unreleased]` (create it if absent) in `### Added` / `### Changed` / `### Fixed`, and reference the PR number, e.g. `(#193)`. Concurrent PRs both touching `[Unreleased]` will conflict — serialize merges or rebase.
- When building `gh pr create --body`/`gh issue create --body`, prefer `--body-file`; if you must use a heredoc subshell, call `/bin/cat` (the user's `cat` is aliased to `bat`).

## Cutting a release

Releases are hand-prepared in a PR, then **a tag push triggers the GitHub release automatically** — never run `gh release create` by hand.

1. Bump `SCRIPT_VERSION` in `scripts/setup-dev-tools-mac.sh` (semver: new features → minor, fixes-only → patch, breaking → major).
2. In `CHANGELOG.md`, rename the top `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and rewrite its summary line to cover the whole release. Keep the `### Added` / `### Changed` / `### Fixed` groups. Do not leave an empty `[Unreleased]` behind — it's re-added when the next change lands.
3. Commit as `chore(release): bump version to X.Y.Z`, open a PR, merge (squash) once CI is green.
4. On updated `main`, create an **annotated** tag and push it:
   ```bash
   git tag -a vX.Y.Z -m "Release X.Y.Z" && git push origin vX.Y.Z
   ```
5. `.github/workflows/release.yml` (trigger: `push` tags `v*`) builds `vixygrey-dev-setup-macos-vX.Y.Z.zip` (the script + `docs/GUIDE.md` + `docs/SHORTCUTS.md` + `README.md` + `LICENSE`) and publishes the GitHub Release with **auto-generated** notes (a PR list). The hand-written `CHANGELOG.md` is the canonical human changelog; the release-page notes are the auto PR summary.

## Environment gotchas

- `rm` is aliased to **`trash`** (rejects `-rf`); use `/bin/rm` in test scripts that clean up temp dirs.
- `bat` shadows `cat`; use `/bin/cat` in scripts/subshells that need raw output.
- These aliases are **interactive-only as of 7.6.0** (#218/#220), so an agent shell gets the real POSIX tools. The two notes above still apply to *your own* interactive terminal, and to any session on a machine that has not re-run the script yet.
- `sed` is **GNU sed** here (from the coreutils install), not BSD — `sed -i '' 's/…/…/' file` fails with "can't read". Use `sed -i 's/…/…/' file`.
- `du` is `dust` interactively: `du -sh` prints dust's help text rather than a size. Use `/usr/bin/du -sh`.
- Target platform is macOS + zsh; the script is bash and assumes Homebrew.

## What the script provisions for Claude (so you can reason about it)

- **Skills** installed to `~/.claude/skills/`: `tiki` (curl'd `SKILL.md`) and a **scoped set of Google Workspace (`gws`) skills** — Drive/Docs/Slides/Sheets/Forms only (sparse-cloned from `googleworkspace/cli`; Gmail/Calendar/Chat/Meet deliberately excluded). Skills are recipes, **not** an access boundary — `gws`'s reach is set by the OAuth scopes granted at `gws auth setup`.
- **MCP servers** registered via `claude mcp add` (not idempotent — the script guards): `filesystem, github, git, fetch, context7, aws-docs, aws-pricing, aws-iac, aws-knowledge, cloudwatch, iam, herald`.
