# CONVENTIONS.md

> **Normative rules for how the code in this repo looks and behaves.**
>
> For the procedural rules AI coding agents must follow when working in this
> repo (issue-first workflow, verification loop, generator-vs-output doctrine,
> release prep), see [`AGENTS.md`](AGENTS.md). The two documents are
> complementary: this file describes the code, AGENTS.md describes the
> workflow. When they conflict, follow AGENTS.md's process and this file's
> substance.

This file is **public and tracked**. It describes the repo, not the
maintainer. Personal preferences and private notes do not belong here.

---

## 1. What this repo is

A single idempotent Bash script,
[`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh), that
provisions a macOS developer machine: installs CLI/GUI tools via Homebrew,
writes dotfiles and config, and generates OMP settings, plugins, and shared
skills under `~/.omp/` and `~/.agents/skills/`. Almost all work happens in
that one file.

Generated output lives on the user's machine; tracked config (this file,
`AGENTS.md`, `tests/`, `.github/`, `.pre-commit-config.yaml`, `docs/`,
`scripts/`) describes how the generator works and how to work in the repo.

---

## 2. The golden rule: edit the generator, never the output

Config files, the user's OMP environment, the pre-commit hook, and the
Desktop docs are all **generated** by the script — usually inside a quoted
heredoc. To change any of them, edit the heredoc **in the script**, not the
produced file (which gets overwritten on the next run).

Generated files carry a managed-block marker:

```text
# >>> dev-setup managed block (do not edit between the markers) >>>
…
# <<< dev-setup managed block <<<
```

Content *between* the markers refreshes on every run. Content *outside* the
markers is preserved by default because that region holds user content
(`~/.ssh/config` Host entries, `~/.aws/config` profiles, `~/.zshrc` hand
edits). The exact-match repair below removes only duplicate regions proved
to be generator output.

### The exact-match deletion test

`write_managed` deletes an outside region only when it **exactly matches**
the block being written *or* the block already on disk — both are provably
ours. Anything short of an exact match to our own output would eat real user
config. This is enforced by the script and verified by
[`tests/helpers.bats`](tests/helpers.bats) (`write_managed: scrubs a
duplicate block when the outside region exactly equals ours`, `write_managed:
does not eat an outside region that does NOT match our block`).

---

## 3. Delivery policies — a fix that only lands on fresh installs is half a fix

Most breakage found in this repo has the same shape: the generator is
correct, but the machine never receives the correction. Before calling
anything done, ask *how does this reach a machine that was already
provisioned?*

Generated outputs have distinct delivery paths:

1. **Files written with `write_managed` / `write_managed_script`** refresh
   on every run. Nothing more to do — but only the region between the
   markers refreshes.
2. **Files written with `write_generated`** refresh as complete generated
   files. The helper backs up replaced content.
3. **Merged files** preserve user values except for explicitly owned keys.
4. **Files written with `write_seed_once`** write only when absent and then
   remain user-owned.

Choosing the wrong policy can make a fix reach new machines but not existing
machines. Prefer a refreshing policy unless the user must own later changes.

Retiring a tool is not the same as cleaning up after it. `--cleanup`
uninstalls the package; the config dir, the tap, and orphaned dependencies
each need separate handling.

---

## 4. Categories install. `configs` configures

`should_run "<category>"` gates only the **install** sections. Generated
config files are written in three ordered `configs` segments further down
the script — with three named exceptions: starship is in `dracula`,
`~/Scripts/*` in `filesystem`, `~/.zshrc` in `shell`.

So `--only git` installs git tooling, refreshes **no** git configuration
(the global pre-commit hook included), and still reports `Failed: 0`.

When you add a config block, put it in the `configs` category with everything
else — and if it belongs to a category a user would plausibly try to refresh
on its own, add that category to **`CONFIG_LIVES_IN_CONFIGS`** so
`--only <cat>` names what it is *not* refreshing. The keys of that table are
validated against `ALL_CATEGORIES` at startup, so a typo fails loudly
instead of producing a notice that can never fire.

`ALL_CATEGORIES` and `CATEGORY_DESC` are the canonical category lists. Add a
new category in **both** places, in the same order. Add it to
`CONFIG_LIVES_IN_CONFIGS` only when the category has generated config in the
`configs` category.

---

## 5. Generated config must match the consuming tool's real schema

Unknown keys are often silently ignored, so "no error" is not evidence a
setting works. Verify against the tool's documented schema, or grep its
binary, before shipping a config block.

Related rules the codebase has learned by breakage:

- **Name the binary, not the package.** `trippy`→`trip`, `nushell`→`nu`,
  `dynein`→`dy`, `imagemagick`→`magick`, `csvkit`→`csvlook`. A permission
  rule or doc line naming the package never matches.
- **Generated docs must reflect what the script installs.** A checklist
  step, `TOOL_REFERENCE` entry, or agent instruction can promise a tool,
  backend, default provider, or example command that the script never
  installs. Cross-check every tool / backend / default / example command a
  generated doc names against the install calls
  (`brew_install` / `go_install` / `npm_global_install` / …) and, for
  commands, the package's real `bin` keys.

---

## 6. A config can be valid and still be read by nobody

This is the defect the repo has shipped most often. A generated file can be
perfectly well-formed and sit somewhere its tool never looks. Nothing errors
— the tool starts, falls back to its defaults, and carries on.

The rule is per-tool, never per-directory. A blanket "move everything to
XDG" sweep would have broken at least one tool that ignores `XDG_CONFIG_HOME`
entirely (verified). Some tools are genuinely Library-based on macOS even
when XDG-aware tools aren't. When in doubt, **ask the tool**:

```sh
lazygit --print-config-dir
k9s info
nu -c '$nu.env-path'
bat --config-dir
```

…then derive the path from that output so a tool that moves its config
again is self-correcting. Pin `XDG_CONFIG_HOME` to the value our own
`.zshrc` exports when you query, because the question is not where the tool
looks in whatever shell is running setup — possibly a bare bash on a fresh
box that has never sourced the generated zshrc — but where it will look
once setup is done.

`remove_superseded_managed <file> <explanation> [ref]` is the canonical way
to clear a copy we wrote at an address the tool no longer reads. It deletes
only when the file carries our markers **and** holds nothing outside them
— the same test `write_managed` applies before removing an outside region.
It is deliberately conservative: a file we wrote before the
managed-block discipline exists carries our content but no markers, so
ownership cannot be proven and it stays with a warning. A harmless stale
file beats deleting something we cannot prove is ours.

`./scripts/setup-dev-tools-mac.sh --verify` is the only check that can prove
path usage for supported tools. Read a `FAIL` as *the file is fine, the tool
is ignoring it.*

---

## 7. Generated shell config is inherited by agents and scripts

`~/.zshrc` is sourced by non-interactive shells, so its content reaches
automation agents and scripts. Aliases are an interactive convenience
and **must be gated** — every modern replacement rejects the original's
flags (`du -sh` prints dust's help, `rm -rf` is rejected by trash), and the
quiet ones are worse (`ps aux`, `dig +short` silently ignore the argument).
Gate the whole section on
`[[ -o interactive && -z "$AI_AGENT" ]]` rather than enumerating hazards —
the enumerate approach has failed before, letting `wget` through.

### Shell startup order decides which tool wins

zsh reads **`~/.zshenv` → `~/.zprofile` → `~/.zshrc`**. Anything activated
in `.zshenv` is therefore activated *first*, which for a version manager is
exactly backwards: every later `export PATH="X:$PATH"` —
`brew shellenv` in `.zprofile`, the gnubin loop, `~/.local/bin`,
`~/Scripts/bin`, `$PNPM_HOME` — prepends itself in front of it.

Conventions:

- **Activate in `.zshenv` for coverage, and again at the end of `.zshrc`
  for precedence.** Both, not either.
- **`command -v foo` is not an answer unless you say which shell you
  asked.** Check both: `zsh -c 'command -v foo'` and
  `zsh -l -i -c 'command -v foo'`. A tool that resolves differently in the
  two is a bug, not a quirk.
- **`mise activate` is for interactive shells; `mise` SHIMS are for
  everything else.** Activation only happens where a shell rc runs. Git
  hooks run under `sh`, and launchd and GUI-launched apps run under
  neither, so none of them see an activated tool.
  `~/.local/share/mise/shims` resolves the active version with no
  activation at all. The script links the shims into `~/.local/bin`,
  which is already on `PATH` in those callers.

When linking a shim, **the link name must match the shim name** — mise
dispatches on `argv[0]`. **Link the shim, not the versioned
`installs/node/<ver>/bin` path**, which silently rots at the next
`mise use node@…`.

`~/.local/bin` outranks Homebrew. Anything linked there wins in **every**
context — git hooks, launchd, GUI-launched editors — not only where
`mise activate` has run. That is the point when the tool is one mise owns
(`prettier`, `tsc`, `copilot`). It is a hazard when something
else already depends on the Homebrew copy. Prefer linking by **exclusion**
over an allowlist — a tool added to mise later is then picked up
automatically. Pair it with a prune scoped to symlinks pointing into the
shims directory, so hand-placed files survive.

Removing a tool from `$HOMEBREW_PREFIX/bin` removes it from nearly every
`PATH` on the machine — that directory is on the `PATH` of `sh`, git hooks,
and most GUI-launched processes. Before relocating a tool out of Homebrew,
ask which non-interactive callers were relying on it being there, and
check with `sh -c 'command -v <tool>'` rather than from your own shell.

A brew formula can install a whole second runtime as a dependency. Before
adding a formula that has a language runtime beneath it, check
`brew deps <formula>`, and prefer the package manager that runtime
already has.

---

## 8. Order matters, and self-healing is the hardest kind of bug to see

A bug that fixes itself on the next run is the hardest to spot, because the
usual "check after" passes. Two rules from past incidents:

- **Order-dependent work needs a test that spans one run, not a check
  afterwards.** Remove the thing entirely, run once, assert the end state.
- **Two jobs with opposite timing requirements cannot share a block.**
  Putting mise's node on the run's own `PATH` must be early; linking shims
  must be late. When a block serves two schedules, split it before the
  schedules diverge.

Related: prefer no category guard for work that must reflect the **final**
state of a run.

---

## 9. The helper layer

The script provides a small, named helper layer. New code uses the helpers
rather than calling `brew install`, `git config`, `tee`, `cat >`, etc.
directly. The helpers exist to make the next call site safe by default —
guard once, benefit forever.

| Helper | Purpose |
|---|---|
| `info`, `success`, `warn`, `error`, `banner`, `progress` | User-facing output. Use these, not `echo`. |
| `log` | Verbose detail to `$LOG_FILE`. |
| `mark_done <key>`, `is_done <key>` | Resume state. No-op under `--dry-run`. |
| `installed <cmd>` | `command -v <cmd>` test. |
| `brew_install`, `brew_cask_install`, `npm_global_install`, `omp_plugin_install`, `go_install`, `uv_tool_install`, `cargo_install` | Inspect installed state and skip completed work. Don't call package managers directly. |
| `write_managed <file> [comment-prefix]`, `write_managed_script <file>` | Wrap stdin in a managed block. Refresh in place on re-run. Back up + replace an unmarked pre-existing file. The `write_managed_script` form keeps the shebang on line 1 and `chmod +x`. |
| `remove_superseded_managed <file> <explanation> [ref]` | For the *other* half of a path change: clears a copy we wrote at an address the tool no longer reads, and only when it is provably ours. |
| `git_global` | A `git config --global` WRITE that honors `--dry-run` in one place. **Writes only** — reads stay as raw `git config`. |

Adding a new helper is fine; adding a new raw `brew install` call is not.
If you find yourself reaching for a raw side-effecting command, the
question is "should this be a helper?".

---

## 10. Idempotency is mandatory

Every run must be safe to repeat. Use the existing guards: `mark_done` /
`is_done "<key>"`, and the `brew_install` / `brew_cask_install` /
`npm_global_install` / `omp_plugin_install` / `go_install` /
`uv_tool_install` / `cargo_install` helpers. They inspect installed state and skip completed
work. Don't call package managers directly.

Honor `--dry-run`. Any block with side effects must do nothing when
`$DRY_RUN == "true"` (print an `info "[DRY RUN] Would …"` line instead).
`write_managed` / `write_managed_script` already handle this; raw `git`
/ `curl` / `cp` / `ln` / `mkdir` blocks you add must guard themselves.

Write files with the managed helpers, not ad-hoc redirection. The helpers
are what makes `--dry-run` honest.

---

## 11. Logging, UX, and observability

- **Logging helpers:** `info`, `success`, `warn`, `error`, `banner`,
  `progress`. Everything verbose goes to `$LOG_FILE` via `log`.
- **Guard on tool presence** with `installed <cmd>` before using an
  optional tool.
- **Heredoc quoting:** use `<<'MARKER'` (quoted) for literal content — this
  is the default, and it keeps `$` and backticks literal (most generated
  files rely on this). Only use an unquoted heredoc when you deliberately
  want the script's variables expanded.

---

## 12. The global hooks directory is shared

`core.hooksPath` makes git read **only** `~/.config/git/hooks`; per-repo
`.git/hooks` is never consulted, for any hook type. So the script writes a
**delegator for every hook type**, each sourcing `dev-setup-chain.sh`,
which runs the repo's own hook and then anything in `<type>.d/`.

Two traps:

- **Never resolve the per-repo hook with `git rev-parse --git-path
  hooks/<type>`.** That call is itself `core.hooksPath` aware, so it
  returns the *delegator's own path* — the hook then runs itself forever
  and every `git commit` on the machine hangs. Use `--git-common-dir`.
- **This directory is not ours alone.** Third-party tools install hooks
  here, so the chain must run `<type>.d/` too, and `preserve_foreign_hook`
  must move a foreign hook aside before a delegator takes its name. It
  re-runs on every setup, because tools re-create their hooks.

Hooks fed data on stdin (`pre-push`, `post-rewrite`, `push-to-checkout`)
need it buffered and replayed per link — the first reader would otherwise
consume it and the rest would see nothing.

---

## 13. The generated pre-commit hook

The script installs a **global** hook (`git config --global core.hooksPath
~/.config/git/hooks`) that runs on all repos. It checks for debug
statements (language-scoped: JS/TS `console.log` / `debugger`, Python
`pdb` / `breakpoint()`, Ruby `binding.pry`), files > 5 MB, and
merge-conflict markers.

- A change to the hook only takes effect **after the script is re-run** to
  regenerate it. Editing the hook's heredoc will not stop the *currently
  installed* (old) hook from firing on your very next commit — that commit
  may still need `--no-verify`.
- To whitelist an intentional debug token on a line, add a trailing
  **`debug-ok`** comment. Prefer that over `--no-verify`.

---

## 14. Data-driven dispatch needs one vocabulary and a loud default

`--cleanup` reads `DEPRECATED_TOOLS` — rows like
`type:name:display:replacement:appname` — and dispatches on `type` through
a `case`. The case must have:

- **One canonical vocabulary.** Don't let two spellings mean the same
  branch. If you add a row, its `type` must be a value the case actually
  matches.
- **A `*)` default that fails loudly** (`warn` + count as skipped), so
  the next typo'd or unhandled type is a visible warning, not a tool that
  quietly never gets touched.

The same smell applies to any lookup keyed on data — a missing key should
never be silently correct.

---

## 15. Removing user data needs two guards

`--cleanup` deletes things people may still want. Every removal must:

1. **Verify the owner is actually gone** — check the `.app` is absent or
   `command -v <tool>` fails, so a manual reinstall is never gutted.
2. **Prefer `trash` over `rm -rf`** so a mistake is recoverable from
   Finder.

Beware paths that *look* orphaned but aren't: `~/.docker` reads as Docker
Desktop residue, but a successor tool may have taken it over. Removing it
would break the docker CLI and destroy credentials. Such paths are
explicitly excluded with a comment in the script.

---

## 16. Conventions that are easy to get wrong

A short list of rules that have each caused a regression at least once:

- The generated pre-commit hook **checks against staged changes**, not
  working-tree changes — `git add` first.
- A `brew_install` call must list the formula by its **canonical name**,
  not its display name. The CI `brew-names` job (`tests/ci/check-brew-names.sh`)
  enforces this.
- `~/.config/git/hooks` is **not** symlinked from `.git/hooks`; it is the
  value of `core.hooksPath`. Adding a hook file there with the wrong
  permissions (`chmod -x`) silently disables it.
- `nvm`, `nodenv`, `asdf`, `pyenv`, and similar version managers **must
  not** be installed alongside mise. Pick one; the script picks mise.
- `mise use node@<ver>` at a project level writes a per-project
  `.mise.toml` (or `.tool-versions`); do not commit those files by
  accident.
- Aliases in `~/.zshrc` are interactive-only. Anything that affects
  non-interactive shells (PATH additions, env vars) goes in `~/.zshenv`.
- The script targets macOS + Homebrew + bash. Linux is not a target; the
  sister repo [`vixygrey-setup-linux`](https://github.com/vixygrey/vixygrey-setup-linux)
  exists for that.

---

## 17. Future considerations

These are conventions the codebase **knows about** but does not yet
enforce, or where the existing enforcement is partial. Treat them as
"good ideas, awaiting formalization" — and as a section that needs its
own periodic review (see "drift" below).

- **`--verify` coverage gap, honestly reported.** The CI `generated-config`
  job proves each heredoc *parses* — JSON via `jq`, shell via `zsh -n`,
  etc. It does not prove the file is at an address the tool reads; that's
  what `--verify` is for. Coverage remains partial. `VERIFY_TARGETS` combines
  runtime validation, path discovery, templates, and explicitly unchecked
  rows. The generated-output inventory computes the missing-file set, so the
  summary does not hide the gap.
- **Cleanup audit.** `DEPRECATED_TOOLS` (defined inside the `--cleanup`
  branch) is a large table with no CI job that diffs it against
  `brew list --formula` / `brew list --cask`. A static check would catch
  retired-but-not-removed packages before they accumulate.
- **Pre-commit hook language coverage.** The hook covers JS/TS
  (`console.log`, `debugger`), Python (`import pdb`, `pdb.set_trace`,
  `breakpoint()`), and Ruby (`binding.pry`, `binding.irb`). It does not
  catch other JS console methods (`console.debug`, `console.warn`,
  `console.info`). Add behavior coverage before you add more patterns.
- **`--verify` shell-startup coverage as a documented convention.** The
  pattern — pin `XDG_CONFIG_HOME` to the value the generated `~/.zshrc`
  exports before querying a tool, and gate a path row on the relevant
  env var so it skips itself when the env is unset — is applied per-row
  (see lazygit, k9s, ripgrep comments), but isn't extracted into a
  reusable helper or a section in this file. The risk: a future row
  author reinvents the pattern badly, or misses it entirely, and the
  row passes on a developer's interactive shell but fails on a bare
  `sh` (the failure mode the Copilot CLI install exposed via #345/#353/#354
  for `copilot`).
- **`--only` category/config cross-check.** `CONFIG_LIVES_IN_CONFIGS` keys
  are validated against `ALL_CATEGORIES` at startup (a typo fails loudly),
  but the **values** are hand-written prose lists, with no static
  cross-check against the actual `write_managed` calls in the `configs`
  segment. A category could claim to configure X but silently not, and
  nothing would notice until a user ran `--only <cat>` and reported a
  missing config.
- **§17 itself drifts.** This section is a case study: at the time of
  writing, one of its six items (the cross-platform path helpers item,
  since removed) was already stale — the repo is macOS-only (per §16),
  so "cross-platform helpers" was out of scope. Future-considerations
  lists need their own review cadence: any item that lands as a real
  PR should be **removed** from §17 in the same PR, and any item whose
  premise is invalidated by another change should be **reframed or
  removed** in the PR that invalidates it. §17 should shrink over time,
  not grow.

---

## 18. Out of scope for this file

- The release workflow (tag-push → GitHub Actions → release publish) lives
  in `.github/workflows/release.yml` and is procedurally described in
  `AGENTS.md`.
- **Evolving state.** That belongs in [`specs/`](specs/), which this repo
  adopted in #493 along with the rest of the machine's `new-project`
  template. The two do not overlap, and the boundary is worth stating
  because it used to be drawn in the opposite place:

  | This file | `specs/` |
  | --- | --- |
  | Standing rules. True until a decision changes them. | State. Changes as work progresses. |
  | *How* code here must look and behave. | *What* is being built, and where it stands. |
  | Read in full by anyone working here. | Read by whichever skill owns the file. |

  An earlier version of this section rejected `specs/` outright, on the
  grounds that it would be "a single-source duplicate of this file". That
  was right while nothing consumed it. It stopped being right once
  bigpowers was adopted for work in this repo: a skill that needs to know
  the active epic cannot get it from a normative rules document.

  Two boundaries follow, and both are load-bearing:

  - **`specs/adr/` records decisions; this file states the rules they
    produced.** ADRs 0001–0007 were extracted from sections 2, 6, 7, 12,
    14, and 16. The prose here stays. An ADR answers "why is this the
    rule", which is the question a reader has a year later; this file
    answers "what is the rule", which is the question they have today.
    When a decision changes, supersede the ADR **and** update the rule.
  - **GitHub issues remain the system of record.** `specs/bugs/registry.yaml`
    holds working notes for an investigation in progress. It does not
    replace the issue, and nothing here is tracked only in `specs/`.
- The CHANGELOG. Hand-written from 7.2.0 onward; entries are added under
  `## [Unreleased]` in `### Added` / `### Changed` / `### Fixed` /
  `### Security`, cite the **issue** number rather than the PR, and are
  retitled to a versioned heading at release time. The link definitions
  at the bottom of the file are part of that retitling — see `AGENTS.md`.

---

## 19. Verification

**`just preflight` is the local entry point.** It runs steps 1-4 below plus
the pre-commit hooks. CI adds workflow validation, Homebrew name validation,
and generated-config parser checks. The [`Justfile`](Justfile) defines the
local commands once.

Per `AGENTS.md`, every change goes through:

1. `bash -n scripts/setup-dev-tools-mac.sh` — syntax.
2. `shellcheck -x -S warning scripts/setup-dev-tools-mac.sh` — **this is
   what CI runs** (`.github/workflows/lint.yml`), `-x` included. Keep it
   clean. A green local run is not proof CI is green: the runner's
   ShellCheck can flag things that local builds miss.
3. `bats tests/` — helper behavior under `SETUP_LIB_ONLY=1`.
4. `./scripts/setup-dev-tools-mac.sh --dry-run` (or `--only <category>`)
   — preview without mutating the machine.
5. When you change a generated file, **extract and exercise it in a
   throwaway dir** rather than trusting the heredoc by eye.
6. `./scripts/setup-dev-tools-mac.sh --verify` — asks supported installed
   tools whether they read generated config. Steps 1-4 and CI check syntax
   or behavior. These checks do not prove path usage for unsupported tools.
   Run this after touching any config path.

For changes to this file specifically: this file is markdown, not Bash.
Steps 1-4 still apply to the unchanged generator. Step 6 is a good sanity
check that no heredoc references a helper or category this file has renamed
or removed.

---

## 20. Line endings and text files

Added with the rest of the machine's `new-project` template in #493. It
sits after the meta-sections because the list grows at the end; read it
with sections 1–16, which are the other rules about the code itself.

- All text files use **LF** line endings, **UTF-8**, and a final newline.
- [`.editorconfig`](.editorconfig) and [`.gitattributes`](.gitattributes)
  are the source of truth for that policy. Do not override them per-file.
- Indentation is **4 spaces for shell and bats**, 2 elsewhere, tabs for
  Go and Makefiles. The large setup script and its tests use 4 spaces, so
  the template's bare 2-space default would fight the files that matter here.
- **`scripts/*.sh` is exempt from trailing-whitespace trimming.** The
  script embeds heredocs whose content may depend on exact bytes, so an
  editor must not strip inside them. This mirrors the exclusion
  [`.pre-commit-config.yaml`](.pre-commit-config.yaml) already applies:
  its `trailing-whitespace` and `end-of-file-fixer` hooks run only on
  `md`, `yaml`, `yml`, `json`, and `toml`. Keep the two in agreement — a
  formatter and a hook that disagree produce a commit loop.
- `.editorconfig` keeps indentation consistent across compatible editors.
  Shell files use four spaces even though the general default is two spaces.
- `.gitattributes` normalizes on `text=auto eol=lf`. Adding it caused no
  renormalization: every tracked text file was already LF. Verify with
  `git ls-files --eol`, which should report `i/lf w/lf` for everything
  except the one binary asset.
