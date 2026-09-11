## Target

The generated OMP `modelRoles.default` assignment and fallback chain.

## Dependents (4)

- `scripts/setup-dev-tools-mac.sh`: generated OMP configuration merge.
- `tests/routing.bats`: exact role and fallback contract.
- `README.md`: documented model routing behavior.
- `~/.omp/agent/config.yml`: active merged configuration on provisioned machines.

## Affected Stories

- Issue #538: workload-based OMP model routing.
- Issue #598: GPT-5.6-Luna as the default OMP agent.

## Test Coverage

- `tests/routing.bats`: validates every model role, fallback chain, local final fallback, and retry policy.
- `just verify`: asks OMP for the effective configuration.
- Live model catalog: confirms the Luna selector and supported reasoning levels.

## Risk: Low

One role changes to a model from the current OMP catalog. Specialized roles and fallback policy remain unchanged.

## Recommended action

Proceed with an exact role update, an explicit Luna fallback chain, a routing contract update, and live configuration verification.
