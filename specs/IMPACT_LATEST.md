## Target

Bigpowers provisioning, OMP plugin state, generated documentation, and project scaffold language.

## Dependents (8)

- `scripts/setup-dev-tools-mac.sh`: plugin installation helper and declaration.
- `scripts/setup-dev-tools-mac.sh`: installed configuration verification target.
- `scripts/setup-dev-tools-mac.sh`: OMP MCP denylist migration.
- `scripts/setup-dev-tools-mac.sh`: generated project scaffold copy.
- `scripts/setup-dev-tools-mac.sh`: generated machine reference copy.
- `tests/helpers.bats`: plugin installation and MCP denylist behavior.
- `README.md`: active tool inventory and OMP description.
- `~/.omp/plugins`: installed plugin package, lock entry, and registry state.

## Affected Stories

- Issue #576: original OMP plugin installation.
- Issue #580: redundant Bigpowers MCP server suppression.
- Issue #596: complete removal from provisioning and the current machine.

## Test Coverage

- `tests/helpers.bats`: OMP plugin lifecycle and atomic MCP JSON updates.
- `tests/generated-config.bats`: generated scaffold and configuration parsing.
- `just dry-run`: complete generator behavior without machine mutation.
- Gap: OMP supplies no isolated plugin root flag for an end-to-end uninstall check.

## Risk: Medium

The removal crosses package state, user-owned JSON, generated references, and existing-machine delivery.

## Recommended action

Proceed with a normal-run plugin retirement, an atomic denylist cleanup, focused helper checks, and a live uninstall on this machine.
