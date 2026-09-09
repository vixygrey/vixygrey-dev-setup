# 0003. Ask the tool where it reads; never hardcode the path

**Status:** Accepted. Recorded 2026-09-08 from `CONVENTIONS.md` section 6.

## Context

This is the defect class the repo has shipped most often. A generated file can be perfectly
well-formed and sit somewhere its tool never looks. Nothing errors. The tool starts, falls
back to its defaults, and carries on.

| Tool | We wrote | The tool reads |
|---|---|---|
| asciinema (#329) | `~/.config/asciinema/config`, 2.x INI | `config.toml`, TOML |
| ngrok (#332) | `~/.config/ngrok/ngrok.yml` | `~/Library/Application Support/ngrok/ngrok.yml` |
| k9s, lazygit, nushell (#333) | `~/Library/Application Support/<tool>/` | `~/.config/<tool>/` |

It survives well for four reasons. No check in the repo can see it: the `generated-config` CI
job proves a heredoc parses, and a file that parses perfectly and is read by nobody passes
every time. A warning is not enough: asciinema and nushell both printed a banner on every
invocation, across releases, and a banner naming a config file reads as advisory noise. The
tool usually keeps working. And the cause can be ours: #333's three came from our own
generated `~/.zshrc` exporting `XDG_CONFIG_HOME`, which relocated every XDG-aware tool on the
machine while those config blocks kept hardcoded macOS paths.

## Decision

**Where a tool will tell you, derive the path from it**, so a tool that moves again is
self-correcting: `lazygit --print-config-dir`, `k9s info`, `nu -c '$nu.env-path'`,
`bat --config-dir`.

**Pin `XDG_CONFIG_HOME` to the value our own `.zshrc` exports when you query.** The question
is not where the tool looks in whatever shell is running setup, possibly a bare bash on a
fresh box that has never sourced the generated zshrc, but where it will look once setup is
done. Without the pin, a first run on a fresh machine resolves to the old paths and bakes in
the bug.

**The rule is per-tool, never per-directory.** A blanket "move everything to XDG" sweep would
have broken two: VS Code is genuinely Library-based on macOS, and ngrok ignores
`XDG_CONFIG_HOME` entirely. #334 deliberately moved ngrok into Library in the same release
that #337 moved three other tools out of it.

**Finish the move.** Writing the new file fixes fresh installs only. Every provisioned machine
keeps the old one. `remove_superseded_managed` is the canonical way to clear it.

## Consequences

- Config blocks are longer, because deriving a path costs a subshell and a fallback.
- `--verify` exists for this and is the only check that can answer "does anything read this".
  Read a `FAIL` as *the file is fine, the tool is ignoring it*.
- `--verify` coverage is partial, 14 path rows at time of writing, and bounded by whether a
  tool surfaces where it reads from. When it does not, a file-existence probe is the honest
  answer. The summary prints the unverified count so the gap is never lost.
