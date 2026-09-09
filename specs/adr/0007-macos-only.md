# 0007. macOS only; Linux lives in a sister repo

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 16.

## Context

The script assumes macOS at nearly every layer: Homebrew as the package manager, `.app`
bundles and `brew_cask_install`, `defaults write` for system preferences, launchd,
`~/Library/Application Support` paths, `terminal-notifier`, `trash`, Quick Look plugins,
and a bash 4+ guard that exists only because macOS ships 3.2.

Making one script serve both platforms would mean a conditional at most of those points.

## Decision

**Target macOS plus Homebrew plus zsh. Linux is not a target.** The sister repo
[`vixygrey-setup-linux`](https://github.com/vixygrey/vixygrey-setup-linux) covers that.

CI reflects the split rather than pretending otherwise. Four jobs run on `ubuntu-latest`
because they are static checks that need no macOS: ShellCheck, actionlint, bats, and the brew
name check against a downloaded API snapshot. One job runs on `macos-latest` and is the only
one that actually **runs** the script.

## Consequences

- No cross-platform path helpers, and none should be added. An earlier
  "future considerations" entry proposing them was stale on arrival and was removed.
- The macOS CI job is load-bearing and slower than the others. Until it existed, CI had never
  run the script at all: `bash -n` checks grammar, not reachability, so it could not see a
  misspelled function on an untaken branch or a flag parsed into the wrong variable. That
  class reached a real user, three times, as `Unknown option: --only core` (#376).
- The job installs bash 4+ with `brew install bash` as its first step. That is satisfying a
  documented prerequisite the way a real user does, not papering over a failure, and it means
  the job exercises the re-exec path rather than skipping it.
- Anything shared with the Linux repo is copied deliberately, not factored out.
