# Architecture decision records

One file per decision, named `NNNN-short-slug.md`. Each records the context that forced a
choice, the choice, and what it costs. Written by hand, not by a skill.

These are **made** decisions. Unmade ones belong in `CONVENTIONS.md` section 17 or in a
GitHub issue.

The first seven were extracted from `CONVENTIONS.md` and `AGENTS.md` in #493, where they
existed as prose. The prose stays: those documents explain the rules to someone working in
the repo today, and these explain why the rules exist to someone asking a year from now.
When a decision changes, supersede the ADR rather than editing it, and update the rule.

| ADR | Decision | Source |
|---|---|---|
| [0001](0001-generator-is-the-only-source-of-truth.md) | Edit the generator, never the output | CONVENTIONS section 2 |
| [0002](0002-managed-blocks-and-the-exact-match-deletion-test.md) | Managed blocks, and delete only on an exact match | CONVENTIONS section 2 |
| [0003](0003-derive-config-paths-from-the-tool.md) | Ask the tool where it reads; never hardcode | CONVENTIONS section 6 |
| [0004](0004-global-hooks-path-with-a-delegator-chain.md) | One global `core.hooksPath`, with a delegator chain | CONVENTIONS section 12 |
| [0005](0005-activate-mise-twice-and-link-its-shims.md) | Activate mise twice; link shims into `~/.local/bin` | CONVENTIONS section 7 |
| [0006](0006-data-driven-dispatch-needs-a-loud-default.md) | Every string dispatch gets one vocabulary and a loud default | CONVENTIONS section 14 |
| [0007](0007-macos-only.md) | macOS only; Linux lives in a sister repo | CONVENTIONS section 16 |
