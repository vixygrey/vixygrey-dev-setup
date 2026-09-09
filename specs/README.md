# Specs

All planning, scope, architecture, release, and verification artifacts for this project live here.

This directory holds **evolving state**. `CONVENTIONS.md` holds **normative rules** and
`AGENTS.md` holds **procedure**. When a fact changes as work progresses, it belongs here.
When a fact is a standing rule, it belongs in one of those two files. See `CONVENTIONS.md`
section 18 for the boundary.

Most files here are written by a bigpowers skill rather than by hand. The owning skill is
named in each file.

| Path | Holds | Written by |
|---|---|---|
| `state.yaml` | Session state: workflow mode, active phase, handoff | `session-state` |
| `planning-status.yaml` | Discover-phase checklist | `run-planning` |
| `execution-status.yaml` | Per-story and per-epic status | `build-epic` |
| `release-plan.yaml` | Release index, epics in WSJF order | `plan-release` |
| `product/` | Scope, vision, glossary | `scope-work`, `elaborate-spec`, `define-language` |
| `tech-architecture/` | Stack, test plan, security plan, design and refactor plans | `map-codebase`, `plan-tests`, `security-review` |
| `adr/` | Architecture decision records | Written by hand, one file per decision |
| `epics/` | Epic capsules and their stories | `slice-tasks`, `plan-work` |
| `bugs/` | `registry.yaml` plus one `BUG-*.md` per investigation | `investigate-bug` |
| `verifications/` | Verification output per story | `verify-work` |
| `metrics/` | Cycle times and benchmark output | `generate-allure-report` |

## Reading order

Start with `state.yaml`. It names the active phase and the next skill to run. `survey-context`
does this for you and is the right entry point at the start of any task.
