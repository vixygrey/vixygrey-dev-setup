## Target

The Kiro extension declarations and the merged Kiro settings in `scripts/setup-dev-tools-mac.sh`.

## Dependents (5)

- `--list` reads each `kiro_extension_install` declaration.
- The progress counter counts each extension declaration.
- The `dx` category installs Kiro and its extensions.
- The `configs` category merges Kiro defaults into the user settings file.
- `just preflight` checks helper behavior and generated JSON syntax.

## Affected Stories

- Issue 594: Provision the installed Kiro extension set and defaults.

## Test Coverage

- `tests/helpers.bats` covers extension installation and dry-run behavior.
- `tests/helpers.bats` covers the Kiro defaults merge and user-value preservation.
- The generated-config CI job parses the Kiro settings JSON.
- Gap: Kiro does not provide a headless validator for extension settings.

## Risk: Medium

The settings merge is shared and user-owned. Invalid keys can fail silently, but local extension manifests provide the current schemas.

## Recommended action

Proceed with schema-derived defaults. Keep the existing defaults-first merge so that user values win.
