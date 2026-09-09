# 0002. Managed blocks, and delete only on an exact match

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 2.

## Context

ADR 0001 says the script owns its generated files. It does not own the files whole. Users
keep real content in the same files: `Host` entries in `~/.ssh/config`, profiles in
`~/.aws/config`, hand edits in `~/.zshrc`. Overwriting a file wholesale would destroy them.

Before #130 the writer **appended** its block instead of replacing it. Nineteen configs ended
up carrying a duplicate copy of their own block, frozen outside the markers, drifting.
Repairing that meant deleting content outside the markers, which is the single most dangerous
operation in the project: outside the markers is exactly where user content lives.

#259 proposed the obvious repair, replacing the file wholesale. That was rejected in #261.

## Decision

Generated content is wrapped in markers:

```text
# >>> dev-setup managed block (do not edit between the markers) >>>
# <<< dev-setup managed block <<<
```

Content **between** them refreshes every run. Content **outside** them is never rewritten.

`write_managed` deletes an outside region only when it **exactly matches** the block being
written, or the block already on disk. Both are provably our own output.

`remove_superseded_managed` applies the same test for the other half of a path change: it
clears a file we wrote at an address the tool no longer reads, and only when the file carries
our markers and holds nothing outside them.

**Do not loosen this test.** Anything short of an exact match to our own output eats real
user config.

## Consequences

- Leftover outside-marker content cannot always be cleaned. A `k9s/config.yaml` written by a
  pre-`write_managed` version has our content but no markers, so ownership cannot be proven
  and it stays, with a warning. A harmless stale file beats deleting something unproven.
- The run reports outside-marker content once at the end, so the residue is visible rather
  than silent.
- This is the highest-risk code in the repo and carries the most test weight in
  `tests/helpers.bats`.
