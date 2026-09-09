# 0005. Activate mise twice, and link its shims into `~/.local/bin`

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 7.

## Context

zsh reads `~/.zshenv`, then `~/.zprofile`, then `~/.zshrc`. `mise activate` sat in `.zshenv`
alone, for the good reason that `.zshenv` is the only file every shell type reads.

Activating first is exactly backwards for a version manager. Every later
`export PATH="X:$PATH"` prepends itself in front: `brew shellenv` in `.zprofile`, the gnubin
loop, `~/.local/bin`, `~/Scripts/bin`, `$PNPM_HOME`. mise ended at `PATH` position **24**
while Homebrew sat at **10**, and the machine disagreed with itself:

- **login or interactive shell** resolved Homebrew's node 26.8.1 and Homebrew's npm
- **non-login shell**, where `brew shellenv` never runs, resolved mise's node 24.18.1

`mise current node` reported the pinned version the whole time. Nothing errored. The visible
damage was two global `node_modules` trees with 18 packages in both, `npm install -g` writing
to whichever the invoking shell resolved, and `_npm_has` truthfully answering "installed"
about a tree `PATH` never reached (#343).

Activation is also not enough on its own. It only happens where a shell rc runs. Git hooks
run under `sh`; launchd and GUI-launched apps run under neither.

## Decision

**Activate in `.zshenv` for coverage, and again at the end of `.zshrc` for precedence.** Both,
not either. `mise activate` registers its hook with `add-zsh-hook`, which is idempotent per
function name, so the second call does not double-fire it.

**Link mise's shims into `~/.local/bin` for everything that never sources a shell rc.**
`~/.local/share/mise/shims` resolves the active version with no activation at all, which is
what those callers need. That directory cannot go on a system-wide `PATH` without `sudo`, and
`~/.local/bin` already is on `PATH` there (#345).

Two constraints, both found by testing rather than reading: **the link name must match the
shim name**, because mise dispatches on `argv[0]`, and **link the shim, not the versioned
`installs/node/<ver>/bin` path**, which silently rots at the next `mise use`.

Prefer linking by **exclusion** over an allowlist, so a tool added to mise later is picked up
automatically. Pair it with a prune scoped to symlinks pointing into the shims directory.

## Consequences

- **`command -v foo` is not an answer unless you say which shell you asked.** Check both:
  `zsh -c 'command -v foo'` and `zsh -l -i -c 'command -v foo'`.
- **`~/.local/bin` outranks Homebrew** (position 9 versus 13 in a bare `sh`), so linking a
  shim there is a machine-wide decision. That is the point for a tool mise owns. It is a
  hazard when something else depends on the Homebrew copy: `pre-commit` builds hook
  environments against whichever `python3` it finds.
- **Removing a tool from `$HOMEBREW_PREFIX/bin` removes it from nearly every `PATH`.** #344
  removed Homebrew's node for good reasons and took `node`, `npm`, and `npx` from every
  non-zsh caller, which surfaced as a prettier hook failing with `npx not found` in an
  unrelated repo.
- **Order-dependent work needs a test spanning one run, not a check afterwards.** The shim
  linking ran before the installs it covered, so a newly installed tool went one full run
  without a link (#357). Nothing looked wrong, because the next run fixed it.
