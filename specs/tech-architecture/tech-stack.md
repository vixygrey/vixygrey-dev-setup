# Tech stack

<!-- What this project is built with, and why. Follows the map-codebase output shape. Keep it current as the stack changes. -->

## Stack

- **Bash 4+**, not the bash 3.2 that macOS ships. The script opens with a 3.2-compatible
  guard that re-execs under a newer bash and refuses to run without one. Associative arrays
  are the reason.
- **Homebrew** is the primary package manager. Four more sit beside it, each wrapped in its
  own idempotent helper: `npm_global_install`, `go_install`, `uv_tool_install`, and
  `run_remote_installer` for vendors that ship only a curl-to-shell script.
- **mise** is the version manager for Node, Python, Go, and Ruby. No `nvm`, `pyenv`, or
  `asdf`: mixing them is called out in `CONVENTIONS.md` section 16.
- **zsh** is the target login shell. The script writes `~/.zshenv`, `~/.zprofile`, and
  `~/.zshrc`, and their read order decides which tool wins on `PATH`.
- **bats** for unit tests, **ShellCheck** for lint, **pre-commit** for the local gate,
  **GitHub Actions** for CI, **just** for the task spine.
- No application runtime, no dependency manifest, no build step. There is nothing to
  compile and nothing to install before running the tests.

## Architecture

One file holds nearly everything: `scripts/setup-dev-tools-mac.sh`, about 18k lines.
It reads top to bottom in five bands.

| Band | Lines | Holds |
|---|---|---|
| Guard and constants | 1-300 | bash 4+ re-exec, `SCRIPT_VERSION`, colors, log paths |
| Helper layer | 77-1400 | Everything reusable. This is the tested surface. |
| Flags and preflight | 300-1500 | `ALL_CATEGORIES`, argument parsing, lock, disk and network checks |
| Install sections | 2438-4275 | One `should_run "<category>"` block per category |
| Config generation | 4527-14289 | Three `configs` segments plus four category-owned exceptions |

**The helper layer is the load-bearing part.** `write_managed`, `write_managed_script`, and
`remove_superseded_managed` write every generated file and carry the whole risk of the
project: each one decides whether to overwrite something a user cares about. They are
loadable in isolation under `SETUP_LIB_ONLY=1`, which is what `tests/helpers.bats` exercises.

**Categories install; the `configs` segment configures.** `should_run` gates only install
work. Every generated config file is written in one ordered segment further down, with four
deliberate exceptions: starship lives in `dracula`, `~/Scripts/*` in `filesystem`, `~/.zshrc`
in `shell`, and the mise shim links are ungated because they must reflect the final state of
a run. `CONFIG_LIVES_IN_CONFIGS` exists so that `--only git` tells the user it refreshed no
git configuration.

**Data flow is one direction: generator to machine.** The script reads almost nothing back.
The two places it does are the `jq` merge branch for `~/.claude/settings.json` and the
managed-block markers that let `write_managed` recognize its own previous output.

**Output has two delivery paths, and they behave differently.** Files written through
`write_managed` refresh on every run. `~/.claude/settings.json` writes its full heredoc only
when absent, and takes a `jq` merge on every machine that already has one. Anything guarded
by `if [[ -f ... ]]` is create-once and freezes silently. Choosing the wrong one is how a
fix reaches new machines and never reaches provisioned ones.

## Conventions (observed)

- **Error handling is counted, not thrown.** `set +e` is deliberate, so one failed formula
  cannot abandon the other 200. Failures accumulate in `INSTALL_FAILED` and `FAILED_ITEMS`,
  and the last lines of the file turn the count back into an exit status. Before that
  existed, every run exited 0 regardless of what it printed.
- **Four report verbs, four meanings.** `success` means a tool was installed, `configured`
  means a file was written and is silent under `--dry-run`, `checked` means a preflight test
  passed and counts nowhere, `warn` and `error` accumulate. They were one function once, and
  a run that installed nothing reported 71.
- **Idempotency is a helper contract, not a per-site check.** Nothing calls `brew install`
  directly. Every installer helper snapshots installed state once and skips work already
  done, and `mark_done` / `is_done` carry the same guarantee for anything else.
- **`--dry-run` must be honored by the block, not by the caller.** The managed writers handle
  it internally; any raw `git`, `curl`, `cp`, `ln`, or `mkdir` added later has to guard
  itself. A dry run that leaves a trace is a CI failure, with a denylist of paths asserted
  in the macOS job.
- **Heredocs are quoted by default.** `<<'MARKER'` keeps `$` and backticks literal, which is
  what almost every generated file needs. An unquoted heredoc is a deliberate choice to
  interpolate.
- **Comments cite issue numbers.** About 97 `#N` references across the script and docs point
  at GitHub issues, not PRs, and they carry the reasoning that would otherwise be lost.
  Reading the comment above a guard is usually faster than reconstructing why it exists.

## Testing

Five CI jobs, each answering a question the others cannot.

| Job | Runner | Proves |
|---|---|---|
| `shellcheck` | ubuntu | The file is valid bash at warning severity |
| `actionlint` | ubuntu | The workflows themselves are valid |
| `unit-tests` | ubuntu | The helper layer behaves, under `SETUP_LIB_ONLY=1` |
| `brew-name-check` | ubuntu | Every brew name exists, in the declared type, in the core API |
| `generated-config` | ubuntu | Each generated heredoc parses in its real parser |
| `dry-run` | macOS | The script runs, leaves no trace, and exits non-zero when it fails |

The layering matters. `bash -n` checks grammar, not reachability. `generated-config` proves a
file parses, never that a tool reads it. Only `--verify` can answer the last question, and it
runs on a machine rather than in CI.

## Signals and active considerations

- **`--verify` coverage is partial.** 14 path rows against a larger set of generated files.
  The summary prints `Files not verified: N (of M)` so the gap is visible rather than lost.
- **`DEPRECATED_TOOLS` has ~98 rows and no CI check** diffing it against what is installed.
  Retired-but-not-removed packages accumulate silently.
- **The pre-commit hook covers JS/TS and Python only.** No Ruby, and it misses
  `console.debug`, `console.warn`, and `console.info`.
- **`CONFIG_LIVES_IN_CONFIGS` values are unchecked prose.** The keys are validated against
  `ALL_CATEGORIES` at startup, so a typo fails loudly, but nothing proves a category actually
  writes what its description claims.
- **One file, 18k lines.** Splitting it has a real cost: the release ships a single script
  that a user runs directly, so any split needs a build step or a loader, and both weaken the
  "download one file and run it" property. Recorded here as a known tension, not a plan.

`CONVENTIONS.md` section 17 is the maintained version of this list and should shrink over
time. Anything here that lands as a PR should be removed from both.
