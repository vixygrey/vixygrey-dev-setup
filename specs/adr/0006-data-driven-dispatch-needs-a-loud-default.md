# 0006. One vocabulary and a loud default for every string dispatch

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 14.

## Context

`--cleanup` reads `DEPRECATED_TOOLS`, rows shaped `type:name:display:replacement:appname`,
and dispatches on `type` through a `case`.

For several releases the array mixed **two type words for the same thing**: `formula:` and
`brew:`, both meaning a Homebrew formula. The `case` had only a `formula)` branch. All 12
`brew:` rows matched nothing, so they were never uninstalled and never even counted. The run
reported `0 removed, 104 not found (already clean)` while a dozen retired tools sat installed.

It stayed invisible because **a `case` with no `*)` default is a silent no-op on an
unrecognized key** (#241, #242).

## Decision

Whenever a table is dispatched on a string field:

**One canonical vocabulary.** Two spellings must not mean the same branch. A new row's type
must be a value the `case` actually matches. Grep the branches; do not assume.

**Every dispatch gets a `*)` default that fails loudly** — `warn` plus a count as skipped — so
the next unhandled type is a visible warning rather than a tool that quietly never gets
touched.

The same smell applies to any lookup keyed on data. A missing key should never be silently
correct.

## Consequences

- `CONFIG_LIVES_IN_CONFIGS` keys are validated against `ALL_CATEGORIES` at startup, so a
  typo fails at launch rather than producing a notice that can never fire.
- The `generated-config` CI job applies the same discipline to itself: an extraction that
  produces no content fails the job, rather than letting every check pass vacuously because a
  heredoc was renamed.
- The `dry-run` CI job asserts its injection actually changed the file before testing it.
- Still unenforced: the **values** in `CONFIG_LIVES_IN_CONFIGS` are hand-written prose with no
  cross-check against the real `write_managed` calls. A category could claim to configure
  something and silently not. Tracked in `CONVENTIONS.md` section 17.
