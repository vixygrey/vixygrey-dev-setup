# Contributing

Thank you for taking the time to contribute.

## Before you start

Two files define how this repository works. This document does not repeat them.

- **[`AGENTS.md`](AGENTS.md)** — procedural rules: the workflow, the commands, the
  verification loop, and how a change reaches a machine that is already provisioned.
- **[`CONVENTIONS.md`](CONVENTIONS.md)** — normative rules: helper usage, managed-block
  discipline, category structure, test architecture, line endings.

Read both before you open a pull request. They apply to human contributors and to coding
agents alike. When the two conflict, follow the process in `AGENTS.md` and the substance in
`CONVENTIONS.md`.

One rule from `AGENTS.md` is worth stating here, because it is the step people skip:
**edit the generator, never the output.** Almost every config file and the complete OMP
environment come from heredocs inside
[`scripts/setup-dev-tools-mac.sh`](scripts/setup-dev-tools-mac.sh). Editing a produced file
does nothing. The next run overwrites it.

## Setup

You need **bash 4+**. macOS ships 3.2, and the script refuses to run without a newer one.

```bash
brew install bash          # the one manual prerequisite
brew install just          # the task runner used below
pre-commit install         # installs the git hook
```

## The short version

1. **Open an issue first.** Use the templates in
   [`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/). State the problem, the proposed fix,
   and how we will know it worked. The issue is where the root cause gets recorded before the
   fix shapes your thinking.
2. Branch from `main` and keep the branch short lived. Prefixes are `feature/`, `fix/`,
   `chore/`, and `docs/`.
3. Implement in small commits, using [conventional commits](https://www.conventionalcommits.org/).
4. **Update [`CHANGELOG.md`](CHANGELOG.md) as part of the change, not afterwards.** Add an
   entry under `## [Unreleased]`, and cite the **issue** number rather than the pull request.
5. Run `just preflight` until it passes.
6. Open a pull request with a summary, the changes, and a test plan. Reference the issue with
   `Closes #N`.

Do not commit directly to `main`.

## Verification

```bash
just preflight    # lint, tests, dry run, and the pre-commit hooks
just verify       # ask supported installed tools whether they read generated config
```

`just --list` shows every recipe. `preflight` covers the local equivalents of the core
checks. CI adds workflow validation, Homebrew name validation, and generated-config parsing.

- A green local ShellCheck is **not** proof that CI is green. The runner may use a different
  build. When CI disagrees with your ShellCheck, CI is the gate.
- `verify` is separate on purpose. It queries the tools installed on your own machine, so it
  cannot gate a pull request. Run it after you touch any config path. Read a `FAIL` as
  *the file is fine, the tool is ignoring it*.

## Adding a tool

`AGENTS.md` and `CONVENTIONS.md` carry the full rules. In outline:

1. Find the right category in the script, or propose a new one.
2. Install through the existing helper, never through a raw `brew install`. The helpers
   snapshot installed state and skip work already done, which is what keeps the script
   idempotent.
3. Put any configuration in the `configs` category, not beside the install. Categories
   install. The three ordered `configs` segments configure.
4. Name the **binary**, not the package. A permission rule or a document that says `trippy`
   never matches, because the binary is `trip`.
5. Update the README tool table and `--list`.

The `brew-name-check` CI job rejects a formula name that does not exist, in the declared
type, in Homebrew's core API. CI also validates workflows and generated config.

## Reporting bugs and requesting features

Use the issue templates. Include your macOS version, the output of
`./scripts/setup-dev-tools-mac.sh --version`, and the relevant log from
`~/.local/share/dev-setup/`. Check the existing issues first.

## Security

Do not open a public issue for a security problem. See [`SECURITY.md`](SECURITY.md).

## License

Your contributions are licensed under the [MIT License](LICENSE).
