# 0004. One global `core.hooksPath`, with a delegator chain

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 12.

## Context

The setup installs a machine-wide pre-commit hook, which means setting
`core.hooksPath` to `~/.config/git/hooks`. That setting is absolute: git then reads **only**
that directory, for every hook type, in every repo. A repo's own `.git/hooks` is never
consulted again, and third-party tools that install hooks there stop running.

## Decision

Write a **delegator for every hook type**, each sourcing `dev-setup-chain.sh`, which runs the
repo's own hook and then anything in `<type>.d/`. `preserve_foreign_hook` moves a foreign hook
aside before a delegator takes its name, and re-runs on every setup because tools re-create
their hooks.

Three constraints, each found by breaking something:

**Never resolve the per-repo hook with `git rev-parse --git-path hooks/<type>`.** That call is
itself `core.hooksPath` aware, so it returns the delegator's own path. The hook then runs
itself forever and every `git commit` on the machine hangs. Use `--git-common-dir`: common,
not absolute, because a linked worktree shares the main repo's `hooks/`.

**Hooks fed data on stdin** (`pre-push`, `post-rewrite`, `push-to-checkout`) need it buffered
and replayed per link. The first reader would otherwise consume it and the rest see nothing.

**git-lfs is deliberately not chained (#311).** It is `core.hooksPath` aware and installs
hooks here from any repo, which made `git lfs pre-push` run on every push on the machine,
including repos with no LFS object. Against a GitHub wiki remote its lock verification cannot
succeed, the hook exits non-zero, and the chain aborts: every wiki push blocked by an error
naming authentication rather than LFS. So `preserve_foreign_hook` **discards** git-lfs hooks
rather than preserving them. Per-repo opt-in is `git-lfs-enable-repo`.

## Consequences

- One machine-wide hook set, which is the point: the pre-commit checks apply everywhere
  without per-repo setup.
- The git-lfs exclusion trades one silent failure for another, so it is **guarded, not just
  documented** (#313). A repo that uses LFS and never opts in would push pointer files
  without their objects, and the push would succeed. The `pre-push` chain now refuses it.
  It aborts rather than warns, deliberately: a warning would not stop the bad push.
- Escapes are `--no-verify` and `git config dev-setup.lfsguard false`.
- `git lfs install --local` cannot substitute: `--local` governs the config, not the hooks,
  so with `core.hooksPath` set it writes the hooks globally anyway. Verified against
  git-lfs 3.7.1.
