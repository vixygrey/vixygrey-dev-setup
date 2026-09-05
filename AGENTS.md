# AGENTS.md — vixygrey-dev-setup

Guidance for AI agents working in this repo. Read this before editing.

This file is **public and tracked**: it describes the repo, not the maintainer. Personal
preferences and private notes belong in `CLAUDE.md`, which is gitignored here and machine-wide.
Nothing in a private `CLAUDE.md` binds a contribution you are helping someone else write.

## What this repo is

A single idempotent Bash script, [`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh) (~10k lines), that provisions a macOS developer machine: installs CLI/GUI tools via Homebrew, writes dotfiles/config, and **generates the user's Claude Code environment** — `~/.claude/CLAUDE.md`, `~/.claude/rules/*`, agents, commands, skills, MCP servers — plus Desktop docs (`POST_SETUP_CHECKLIST.md`, `TOOL_REFERENCE.md`, `KEYBOARD_SHORTCUTS.md`, `TOOLKIT_SUMMARY.md`). Almost all work happens in that one script.

## The golden rule: edit the generator, never the output

Config files, the user's `~/.claude/CLAUDE.md`, the pre-commit hook, and the Desktop docs are all **generated** by the script — usually inside a quoted heredoc. To change any of them, edit the heredoc **in the script**, not the produced file (which gets overwritten on the next run). Generated files carry a managed-block marker: `# >>> dev-setup managed block (do not edit between the markers) >>>`.

## Two delivery paths — a fix that only lands on fresh installs is half a fix

Most breakage found in this repo has the same shape: **the generator is correct, but the machine never receives the correction.** Before calling anything done, ask *how does this reach a machine that was already provisioned?*

- **Files written with `write_managed`/`write_managed_script`** refresh on every run. Nothing more to do — but only the region **between** the markers refreshes. Content *outside* them is never rewritten, which is deliberate (`~/.ssh/config` Host entries, `~/.aws/config` profiles, `~/.zshrc` edits all live out there) and was also how 19 configs stayed frozen carrying a duplicate copy of their own block, left by the pre-#130 version that appended instead of replacing. `write_managed` now deletes an outside region when it exactly matches the block being written *or* the block already on disk — both are provably ours. **Do not loosen that test**: anything short of an exact match to our own output eats real user config, which is why the "replace the file wholesale" repair proposed in #259 was not the fix (#261). Leftover outside-marker content is reported once at the end of a run.
- **`~/.claude/settings.json` is different** — the `configs` block only writes the full heredoc when the file is *absent*. Existing machines take the `jq` **merge branch**, which must be taught about the change explicitly. #206 fixed schema-invalid hooks in the heredoc; without the matching merge-branch migration, every already-provisioned machine would have kept the broken hooks forever.
- **The Claude `settings.json` allowlist is two lists, and they are not the same list.** The fresh-machine heredoc (`CLAUDE_SETTINGS_CONF`) is the actual grant set — read *that* to see what is auto-approved, and it already uses binary names (`Bash(trip *)`, not `Bash(trippy *)`). The merge branch's `CLAUDE_DENY_ALLOW` / `CLAUDE_STALE_ALLOW` variables are **removal** lists that *strip* dangerous or dead auto-approvals from already-provisioned machines. So a package-named entry like `Bash(dynein *)` sitting in those variables is a removal target, **not** a live dead grant — don't "fix" it. Extract the heredoc and run it through `jq` before flagging anything in the allowlist; a finding built on the strip lists was retracted mid-audit (the #209 pattern).
- **Anything guarded by `if [[ -f … ]]` / `if [[ -d … ]]` is create-once** and silently freezes. That is exactly how the global `CLAUDE.md` and `rules/` drifted 33 lines and eight tool names behind the generator (#226). Prefer `write_managed`.
- **Retiring a tool is not the same as cleaning up after it.** `--cleanup` uninstalls the package; its config dir, its tap, and its orphaned dependencies each needed separate handling (#210, #214, #224).

## Categories install; `configs` configures

`should_run "<category>"` gates only the **install** sections. Every generated config
file is written in one ordered `configs` segment further down the script — with three
exceptions: starship is in `dracula`, `~/Scripts/*` in `filesystem`, `~/.zshrc` in
`shell`. So `--only git` installs git tooling, refreshes **no** git configuration
(the global pre-commit hook included), and still reports `Failed: 0` (#258).

When you add a config block, it goes in the `configs` segment with everything else —
and if it belongs to a category a user would plausibly try to refresh on its own, add
that category to **`CONFIG_LIVES_IN_CONFIGS`** so `--only <cat>` names what it is not
refreshing. The keys of that table are validated against `ALL_CATEGORIES` at startup,
so a typo fails loudly instead of producing a notice that can never fire.

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

## A config can be valid and still be read by nobody

The section above is about the right **keys**. This one is about the right **address**, and
it is the defect this repo has shipped most often. A generated file can be perfectly
well-formed and sit somewhere its tool never looks. Nothing errors — the tool starts, falls
back to its defaults, and carries on.

| Tool | We wrote | The tool reads |
| --- | --- | --- |
| asciinema (#329) | `~/.config/asciinema/config`, 2.x INI | `config.toml`, TOML |
| ngrok (#332) | `~/.config/ngrok/ngrok.yml` | `~/Library/Application Support/ngrok/ngrok.yml` |
| k9s, lazygit, nushell (#333) | `~/Library/Application Support/<tool>/` | `~/.config/<tool>/` |

Why it survives so well:

- **No check in the repo can see it.** The CI `generated-config` job proves each heredoc
  *parses*, which is necessary and caught #291. A file that parses perfectly and is read by
  nobody passes it every time.
- **A warning is not enough.** Two of the five *did* announce themselves — asciinema and
  nushell printed a banner on every invocation, across releases. Both survived anyway, because
  a banner naming a config file reads as advisory noise rather than "your settings are off".
- **The tool usually keeps working.** ngrok was never broken: `add-authtoken` writes to the
  file ngrok actually reads, so only the stranded seed template was dead. Nothing pointed at it.
- **The cause can be ours.** #333's three came from the generated `~/.zshrc` exporting
  `XDG_CONFIG_HOME="$HOME/.config"`, which relocated the config of every XDG-aware tool on
  the machine while those config blocks kept their hardcoded macOS paths.

**Ask the tool; do not hardcode.** Where a tool will tell you, derive the path from it —
`lazygit --print-config-dir`, `k9s info`, `nu -c '$nu.env-path'`, `bat --config-dir` — so a
tool that moves again is self-correcting. Pin `XDG_CONFIG_HOME` to the value our own
`.zshrc` exports when you query, because the question is not where the tool looks in
whatever shell is running setup — possibly a bare bash on a fresh box that has never sourced
the generated zshrc — but where it will look once setup is done. Without that pin, a first
run on a fresh machine resolves to the old paths and bakes in the bug.

**The rule is per-tool, never per-directory.** A blanket "move everything to XDG" sweep
would have broken two: **VS Code** is genuinely Library-based on macOS, and **ngrok** ignores
`XDG_CONFIG_HOME` entirely (verified with `HOME` and `XDG_CONFIG_HOME` both pointed at temp
dirs). #334 deliberately moved ngrok *into* Library in the same release #337 moved three
others out of it.

**Finish the move.** A path change is the two-delivery-paths problem in its purest form:
writing the new file fixes fresh installs, while every provisioned machine keeps the old one
and goes on paying for it. `remove_superseded_managed <file> <explanation> [ref]` is the
canonical way — it deletes only when the file carries our markers **and** holds nothing
outside them, the same test `write_managed` applies before removing an outside region
(#259). It is deliberately conservative: a `k9s/config.yaml` written by a pre-`write_managed`
version has our content but no markers, so ownership cannot be proven and it stays with a
warning. A harmless stale file beats deleting something we cannot prove is ours.

`--verify` (step 5 below) is the check for all of this, and the only one that can answer
"does anything read this". Read a `FAIL` as *the file is fine, the tool is ignoring it*.

## Generated shell config is inherited by agents and scripts

`~/.zshrc` is sourced by non-interactive shells, so anything defined there reaches Claude Code and any script. Aliases are an interactive convenience and **must be gated** — every modern replacement rejects the original's flags (`du -sh` prints dust's help, `rm -rf` is rejected by trash), and the quiet ones are worse (`ps aux`, `dig +short` silently ignore the argument). Gate the whole section on `[[ -o interactive && -z "$CLAUDECODE" && -z "$AI_AGENT" ]]` rather than enumerating hazards — the enumerate approach already failed once, letting `wget` through (#218, #220).

## Shell startup order decides which tool wins, and `~/.zshenv` loses

zsh reads **`~/.zshenv` -> `~/.zprofile` -> `~/.zshrc`**. Anything activated in `.zshenv` is therefore activated *first*, which for a version manager is exactly backwards: every later `export PATH="X:$PATH"` — `brew shellenv` in `.zprofile`, the gnubin loop, `~/.local/bin`, `~/Scripts/bin`, `$PNPM_HOME` — prepends itself in front of it.

`mise activate` sat in `.zshenv` alone, for the good reason that `.zshenv` is the only file every shell type reads (agents and scripts included). The cost was that mise ended up at PATH position **24** while Homebrew sat at **10**, and the machine disagreed with itself:

- **login/interactive shell** (`.zprofile` runs `brew shellenv`) -> Homebrew's `node` 26.8.1 and Homebrew's `npm`
- **non-login shell** (only `.zshenv` runs, Homebrew's shellenv never does) -> mise's `node` 24.18.1 and mise's `npm`

`mise current node` reported the pinned 24.18.1 the whole time. Nothing errored. The visible damage was two global `node_modules` trees with 18 packages in both, `npm install -g` writing to whichever one the invoking shell resolved, and `_npm_has` truthfully answering "installed" about a tree `PATH` never reached (#343).

Rules that follow:

- **Activate in `.zshenv` for coverage, and again at the end of `.zshrc` for precedence.** Both, not either. `mise activate` registers its hook with `add-zsh-hook`, which is idempotent per function name, so the second call does not double-fire it — verified by counting `$precmd_functions`.
- **`command -v foo` is not an answer unless you say which shell you asked.** Check both: `zsh -c 'command -v foo'` and `zsh -l -i -c 'command -v foo'`. A tool that resolves differently in the two is a bug, not a quirk — and `--verify` results inherit the same split (see [[verify-generated-config-before-flagging]] territory: k9s and nushell "fail" from a non-login shell purely because `XDG_CONFIG_HOME` is unset there).
- **`mise activate` is for interactive shells; `mise` SHIMS are for everything else.** Activation only happens where a shell rc runs — zsh, here. Git hooks run under `sh`, and launchd and GUI-launched apps run under neither, so none of them see an activated tool. `~/.local/share/mise/shims` resolves the active version with no activation at all, which is exactly what those callers need: `sh -c '~/.local/share/mise/shims/node --version'` works from a completely bare environment. Because that directory cannot go on a system-wide `PATH` without `sudo`, the script links the shims into `~/.local/bin`, which is already on `PATH` there (#345).

  Two constraints when linking a shim, both found by testing rather than reading: **the link name must match the shim name** — mise dispatches on `argv[0]`, so a link called `nodetest` pointing at the `node` shim dies with `nodetest is not a valid shim` — and **link the shim, not the versioned `installs/node/<ver>/bin` path**, which silently rots at the next `mise use node@…`.

- **Removing a tool from `$HOMEBREW_PREFIX/bin` removes it from nearly every `PATH` on the machine.** That directory is on the `PATH` of `sh`, git hooks, and most GUI-launched processes; a mise-managed tool is not. #344 removed Homebrew's node for good reasons and, in doing so, took `node`/`npm`/`npx` away from every non-zsh caller — which surfaced as a prettier pre-commit hook failing with `npx not found` in an unrelated repo (#345). Before relocating a tool out of Homebrew, ask which non-interactive callers were relying on it being there, and check with `sh -c 'command -v <tool>'` rather than from your own shell.

- **A brew formula can install a whole second runtime as a dependency.** `brew install prettier` pulls in `node`. Before adding a formula that has a language runtime beneath it, check `brew deps <formula>` — and prefer the package manager that runtime already has. Check afterwards too: `brew uses --installed node` names everything keeping it alive.

## pi extensions are unsandboxed, and a wrong event field fails silently

pi extensions are TypeScript running **in-process with the user's full permissions**. pi's own security doc is explicit: *"It is not a sandbox."* Project trust gates only `.pi/` resources — a **global** extension in `~/.pi/agent/extensions/` loads with no prompt whatsoever. `pi install npm:<anything>` is therefore the same decision as `npm i -g`, and `~/.pi/agent/auth.json` (a live OAuth token) is readable by anything that loads. Prefer the examples bundled inside the installed package; they are first-party and add no supply-chain surface.

When generating one, **copy the upstream example's API exactly and then verify behaviour, not loading.** The `tool_call` event field is `event.toolName`; a first draft here used `event.tool`, which matches nothing. It type-checked, loaded without complaint, and reported success while blocking nothing — the same silent-no-op family as everything else in this file. The test that catches it is functional: ask pi to write a protected path and confirm no file appears.

## Uninstall before install when both own the same bin path

Migrating a tool from Homebrew to npm is not "install the new one, remove the old one" — that order fails. Homebrew's prettier owns `$HOMEBREW_PREFIX/bin/prettier`; `npm install -g prettier` wants to write its shim to the same path and dies with `EEXIST: file already exists`. The install fails, the uninstall that follows removes the Homebrew copy anyway, and the machine is left with **no prettier at all** — a worse state than before the "fix", produced by a script reporting only a single failed step.

Uninstall first, install second, and prove it by running the migration on a machine that actually has the old package. A dry run cannot catch this: it reports both steps as intended and never discovers they collide.

## Removing user data needs two guards

`--cleanup` deletes things people may still want. Every removal must:

1. **Verify the owner is actually gone** — check the `.app` is absent or `command -v <tool>` fails, so a manual reinstall is never gutted.
2. **Prefer `trash` over `rm -rf`** so a mistake is recoverable from Finder.

And beware paths that *look* orphaned but aren't: `~/.docker` reads as Docker Desktop residue, but OrbStack took it over (`currentContext: orbstack`, registry `auths`). Removing it would break the docker CLI and destroy credentials — it is excluded with a comment saying why (#214).

## A data-driven dispatch needs one vocabulary and a loud default

`--cleanup` reads `DEPRECATED_TOOLS` — rows like `type:name:display:replacement:appname` — and dispatches on `type` through a `case`. For releases the array mixed **two type words for the same thing**: `formula:` *and* `brew:`, both meaning a Homebrew formula, but the `case` only had a `formula)` branch. All 12 `brew:` rows matched nothing, so they were **never uninstalled and never even counted** — the run cheerfully reported `0 removed, 104 not found (already clean)` while a dozen retired tools sat installed. It stayed invisible because a `case` with no `*)` default is a silent no-op on an unrecognized key (#241/#242).

Two rules whenever you add or edit a table that is dispatched on a string field:

- **One canonical vocabulary.** Don't let two spellings mean the same branch. If you add a row, its type must be a value the `case` actually matches — grep the branches, don't assume.
- **Every dispatch gets a `*)` default that fails loudly** (`warn` + count as skipped), so the next typo'd or unhandled type is a visible warning, not a tool that quietly never gets touched. The same smell applies to any lookup keyed on data — a missing key should never be silently correct.

## Conventions that are easy to get wrong

- **Idempotency is mandatory.** Every run must be safe to repeat. Use the existing guards: `mark_done`/`is_done "<key>"`, and the `brew_install` / `brew_cask_install` / `npm_global_install` / `go_install` / `uv_tool_install` helpers (they snapshot installed state and skip work already done). Don't call `brew install` directly.
- **Honor `--dry-run`.** Any block with side effects must do nothing when `$DRY_RUN == "true"` (print an `info "[DRY RUN] Would …"` line instead). `write_managed`/`write_managed_script` already handle this; raw `git`/`curl`/`cp`/`ln`/`mkdir` blocks you add must guard themselves.
- **Write files with the managed helpers**, not ad-hoc redirection:
  - `write_managed <file> [comment-prefix]` — wraps stdin in a managed block (refreshes in place on re-run; backs up+replaces an unmarked pre-existing file).
  - `write_managed_script <file>` — same, for executables; keeps the shebang on line 1 and `chmod +x`.
  - `remove_superseded_managed <file> <explanation> [ref]` — for the *other* half of a path
    change: clears a copy we wrote at an address the tool no longer reads, and only when it
    is provably ours. See "A config can be valid and still be read by nobody".
- **Logging/UX helpers:** `info`, `success`, `warn`, `error`, `banner`, `progress`. Everything verbose goes to `$LOG_FILE` via `log`.
- **Guard on tool presence** with `installed <cmd>` before using an optional tool.
- **Heredoc quoting:** use `<<'MARKER'` (quoted) for literal content — this is the default, and it keeps `$` and backticks literal (most generated files rely on this). Only use an unquoted heredoc when you deliberately want the script's variables expanded.

## Testing / verification loop (do this before every commit)

1. `bash -n scripts/setup-dev-tools-mac.sh` — syntax.
2. `shellcheck -x -S warning scripts/setup-dev-tools-mac.sh` — **this is what CI runs**
   (`.github/workflows/lint.yml`), `-x` included. Keep it clean — and note a green local run
   is not proof CI is green: 0.11.0 passed a dead `NUSHELL_CONFIG_DIR` that the runner's older
   build flagged as SC2034. When CI disagrees with your shellcheck, CI is the gate.
3. `./scripts/setup-dev-tools-mac.sh --dry-run` (or `--only <category>`) — preview without mutating the machine.
4. When you change a generated file, extract and exercise it in a throwaway dir rather than trusting the heredoc by eye (e.g. the pre-commit hook was tested against sample staged files in a temp `git init`).
5. `./scripts/setup-dev-tools-mac.sh --verify` — asks each installed tool whether it
   actually reads what we generate. Steps 1-3 and CI all check the file is *well-formed*;
   none of them can tell you it is at an address the tool looks at. Run this after touching
   any config path, and read a `FAIL` as "the file is fine, the tool is ignoring it".

Useful flags: `--dry-run`, `--list`, `--list-categories`, `--only <cats>`, `--skip <cats>`, `--interactive/-i`, `--resume`, `--cleanup`, `--verify`, `--uninstall`, `--version`.

## The global hooks directory is shared, and `--git-path` lies inside it

`core.hooksPath` makes git read **only** `~/.config/git/hooks`; per-repo `.git/hooks` is never
consulted, for any type. So the script writes a **delegator for every hook type**, each sourcing
`dev-setup-chain.sh`, which runs the repo's own hook and then anything in `<type>.d/`.

Two traps to respect when touching this (#260):

- **Never resolve the per-repo hook with `git rev-parse --git-path hooks/<type>`.** That call is
  itself `core.hooksPath` aware, so it returns the *delegator's own path* — the hook then runs
  itself forever and every `git commit` on the machine hangs. Use `--git-common-dir` (common, not
  absolute: a linked worktree shares the main repo's `hooks/`), and keep the guard that refuses to
  re-enter the global directory.
- **This directory is not ours alone.** Third-party tools install hooks here, so the chain must
  run `<type>.d/` too, and `preserve_foreign_hook` must move a foreign hook aside before a
  delegator takes its name. It re-runs on every setup, because tools re-create their hooks.
- **git-lfs is the one tool deliberately NOT chained (#311).** It is `core.hooksPath` aware and
  installs `pre-push`/`post-checkout`/`post-merge`/`post-commit` here from any repo, which made
  `git lfs pre-push` run on every push on the machine — including repos with no LFS object in
  them. Against a GitHub wiki remote its lock verification cannot succeed (an account with push
  access still gets `You must have push access to verify locks`), the hook exits non-zero, and the
  chain aborts: every wiki push blocked by an error naming authentication rather than LFS. So
  `preserve_foreign_hook` *discards* git-lfs hooks instead of preserving them, and purges copies
  left in `<type>.d/` by earlier versions. Per-repo opt-in is `git-lfs-enable-repo`, which writes
  the hooks to `.git/hooks` where the chain runs them as link 1.
  - Note `git lfs install --local` **cannot** be used for that: `--local` governs the config, not
    the hooks, so with `core.hooksPath` set it writes the hooks globally anyway. Verified against
    git-lfs 3.7.1.
  - git-lfs refuses to overwrite a foreign hook (`Hook already exists`, exit 2), so the delegators
    hold their names once installed — this arrangement is self-maintaining, not a race.
  - **That tradeoff is guarded, not just documented (#313).** A repo that uses LFS and never
    runs `git-lfs-enable-repo` would push pointer files without their objects, and the push would
    *succeed* — so the `pre-push` chain refuses it instead. The check is `git ls-files
    ':(attr:filter=lfs)'` (one git call, ~20ms, no `git-lfs` fork) plus a grep for an LFS
    `pre-push` hook. It **aborts** rather than warns, deliberately: a warning would not stop the
    bad push, which is the whole point. Unlike #311's wiki case it cannot misfire on a healthy
    repo — LFS-tracked paths with no LFS hook is always wrong. Escapes are `--no-verify` and
    `git config dev-setup.lfsguard false`.

Hooks fed data on stdin (`pre-push`, `post-rewrite`, `push-to-checkout`) need it buffered and
replayed per link — the first reader would otherwise consume it and the rest would see nothing.

## The generated pre-commit hook

The script installs a **global** hook (`git config --global core.hooksPath ~/.config/git/hooks`) that runs on all repos. It checks for debug statements (language-scoped: JS/TS `console.log`/`debugger`, Python pdb/`breakpoint()`, Ruby `binding.pry`), files >5 MB, and merge-conflict markers. Two things to know:

- A change to the hook only takes effect **after the script is re-run** to regenerate it. So editing the hook's heredoc will not stop the *currently installed* (old) hook from firing on your very next commit — that commit may still need `--no-verify`.
- To whitelist an intentional debug token on a line, add a trailing **`debug-ok`** comment. Prefer that over `--no-verify`.

## Commits, PRs, CHANGELOG

- **Open a GitHub issue FIRST — before creating a branch or writing a single line of code.** `gh issue create` with a clear title and a `bug`/`feature`/`chore`/`documentation`/`tech-debt`/`security` label (run `gh label list` if unsure — there is no `docs` label; it's `documentation`), then branch, implement, and reference it from the PR body (`Closes #N`) and a comment. This is not optional bookkeeping: the issue is where the problem and its root cause get recorded before the fix shapes your thinking. The only carve-outs are a pure `chore(release)` version bump and a trivial one-liner the user explicitly asked you to just do.
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
- **A second agent, `pi`**, installed from `@earendil-works/pi-coding-agent` — *not* `@mariozechner/pi-coding-agent`, which is the namespace every write-up links and which stopped at 0.73.1 in May 2026. Its config lives in **`~/.pi/agent/`**, which ignores `XDG_CONFIG_HOME`; `~/.config/pi` would be this repo's "valid config, wrong address" bug again, so `--verify` covers it (`pi --list-models` knows the `ollama` provider only because our `models.json` defines it).
  - pi shares **five** skills with Claude Code via per-skill symlinks in `~/.agents/skills/` — not the whole of `~/.claude/skills/`. pi injects every discovered skill's name and description into its system prompt at startup, and that prompt is under 1k tokens by design; all 29 skills would roughly double it, mostly with Google Workspace recipes. Per-skill links also matter because the `gws` skills are re-copied from upstream each run, so their frontmatter cannot carry `disable-model-invocation`.
  - Do **not** add `enabledModels` to the generated `settings.json`. Scoping it to `["anthropic/*"]` makes pi print `Warning: No models match pattern "anthropic/*"` on every run of a fresh machine, because the Anthropic catalog is empty until the first `/login` — the #327 shape.
  - The local model must emit *structured* tool calls under Ollama. `qwen3:8b` does; `qwen2.5-coder:7b` does not, despite advertising `tools` in `ollama show`. Verify with a direct `curl` to `/v1/chat/completions` carrying a `tools` array before changing the model.
