# Tech stack

<!-- What this project is built with, and why. Follows the map-codebase output shape. Keep it current as the stack changes. -->

## Stack

- **Bash 4+**, not the bash 3.2 that macOS ships. The script opens with a 3.2-compatible
  guard that re-execs under a newer bash and refuses to run without one. Associative arrays
  are the reason.
- **Homebrew** is the primary package manager. Six installation paths sit beside it.
  Each path uses an idempotent helper: `npm_global_install`, `omp_plugin_install`,
  `go_install`, `uv_tool_install`, `cargo_install`, or `run_remote_installer`.
  Pinned source builds cover releases without suitable packages.
- **mise** manages Node and Python. Go and Rust install separately. No `nvm`, `pyenv`,
  or `asdf`: mixing version managers is called out in `CONVENTIONS.md` section 16.
- **zsh** is the target login shell. The script writes `~/.zshenv`, `~/.zprofile`, and
  `~/.zshrc`, and their read order decides which tool wins on `PATH`.
- **Bun** installs OMP plugin packages. OMP remains a prebuilt native binary.
- **bats** for unit tests, **ShellCheck** for lint, **pre-commit** for the local gate,
  **GitHub Actions** for CI, **just** for the task spine.
- No application runtime, no dependency manifest, no build step. There is nothing to
  compile and nothing to install before running the tests.

## Architecture

One large file holds nearly everything: `scripts/setup-dev-tools-mac.sh`.
It reads top to bottom in these bands.

| Band | Holds |
|---|---|
| Guard and constants | Bash 4+ re-exec, `SCRIPT_VERSION`, colors, log paths |
| Helper layer | Reusable installers, file writers, logging, and safety checks |
| Flags and preflight | Categories, argument parsing, lock, disk, and network checks |
| Install sections | One `should_run "<category>"` block per category |
| Machine configuration | Three `configs` segments and category-owned exceptions |
| Finalization | Desktop docs, first-run actions, mise links, verification, and summary |

**The file writers are load-bearing.** `write_managed`, `write_managed_script`,
`write_generated`, `write_seed_once`, JSON merge helpers, and
`remove_superseded_managed` decide whether to overwrite something a user cares about.
The reusable helpers load in isolation under `SETUP_LIB_ONLY=1`, which is what
`tests/helpers.bats` exercises.

**Categories install. The `configs` category configures.** `should_run` gates only install
work. Generated config files are written in three ordered segments further down.
Three exceptions are starship in `dracula`, `~/Scripts/*` in `filesystem`, and
`~/.zshrc` in `shell`. The mise shim links are ungated.
They must reflect the final state of a run.
`CONFIG_LIVES_IN_CONFIGS` makes `--only git` report that it did not refresh Git configuration.

**Data flow is one direction: generator to machine.** The script reads back only
when a safe update requires existing state. Managed markers establish ownership,
JSON merges preserve user settings, and seed files remain user-owned after creation.

**Output policies have different delivery behavior.** Managed and generated files
refresh on every run. JSON merges preserve unrelated settings while reasserting owned
keys. Seed files write only when absent. Choosing the wrong policy can make a fix reach
new machines but not provisioned ones.

## Conventions (observed)

- **Error handling is counted, not thrown.** `set +e` is deliberate, so one failed formula
  cannot abandon the remaining installs. Failures accumulate in `INSTALL_FAILED` and
  `FAILED_ITEMS`, and the last lines of the file turn the count back into an exit status.
  Before that existed, every run exited 0 regardless of what it printed.
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

Six CI jobs, each answering a question the others cannot.

| Job | Runner | Proves |
|---|---|---|
| `shellcheck` | ubuntu | The file is valid bash at warning severity |
| `actionlint` | ubuntu | The workflows themselves are valid |
| `unit-tests` | ubuntu | The helper layer behaves, under `SETUP_LIB_ONLY=1` |
| `brew-name-check` | ubuntu | Every brew name exists, in the declared type, in the core API |
| `generated-config` | ubuntu | Each generated heredoc parses in its real parser |
| `dry-run` | macOS | The script runs, leaves no trace, and exits non-zero when it fails |

The layering matters. `bash -n` checks grammar, not reachability. `generated-config` proves a
file parses, never that a tool reads it. `--verify` answers the last question for supported
tools, and it runs on a machine rather than in CI.

## Signals and active considerations

- **`--verify` coverage is partial.** It combines runtime validation, path discovery,
  templates, and explicitly unchecked rows. The summary reports the actual missing-file set.
- **`DEPRECATED_TOOLS` has no CI comparison with installed packages.** Retired packages can
  remain installed without a report.
- **The pre-commit hook covers JS/TS, Python, and Ruby.** It misses
  `console.debug`, `console.warn`, and `console.info`.
- **`CONFIG_LIVES_IN_CONFIGS` values are unchecked prose.** The keys are validated against
  `ALL_CATEGORIES` at startup, so a typo fails loudly, but nothing proves a category actually
  writes what its description claims.
- **One large source file is a known tension.** Splitting it has a real cost: the release
  ships a single script that a user runs directly, so any split needs a build step or a
  loader. Both options weaken the "download one file and run it" property.

`CONVENTIONS.md` section 17 is the maintained version of this list and should shrink over
time. Anything here that lands as a PR should be removed from both.
