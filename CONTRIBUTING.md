# Contributing

Thanks for your interest in contributing to this project! Here's how to get involved.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch: `git switch -c feature/your-change`
4. Make your changes
5. Run the linters (see below)
6. Commit using [conventional commits](https://www.conventionalcommits.org/): `type(scope): description`
7. Push and open a pull request against `main`

## Development Requirements

- [shellcheck](https://github.com/koalaman/shellcheck) for linting bash scripts
- [PowerShell](https://github.com/PowerShell/PowerShell) + [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) for linting the Windows script (optional, runs in CI)

## Linting

All scripts must pass their respective linters with zero issues before merging.

```bash
# Bash scripts (macOS + Linux)
shellcheck scripts/setup-dev-tools-mac.sh
shellcheck scripts/setup-dev-tools-linux.sh

# PowerShell script (Windows) -- requires pwsh
pwsh -Command "Invoke-ScriptAnalyzer -Path scripts/setup-dev-tools-windows.ps1 -Severity Warning,Error"
```

CI runs both ShellCheck and PSScriptAnalyzer automatically on every PR.

## Guidelines

- **Keep scripts idempotent** -- every install block should skip if the tool is already present
- **Use the existing helper functions** (`installed`, `brew_install`, `log`, `info`, `warn`, etc.) rather than raw commands
- **Test with `--dry-run`** before running a full install to verify your changes parse correctly
- **One tool per commit** when adding new tools; group related config changes together
- **Update documentation** if you add a new tool or change behavior (README, platform guides, shortcuts)
- **Don't break cross-platform parity** -- if a tool is available on all platforms, add it to all three scripts
- **Follow the category system** -- place tools in the correct category and update `ALL_CATEGORIES` if adding a new one

## Adding a New Tool

1. Find the right category in the script (or propose a new one)
2. Add an install block using the existing pattern:
   ```bash
   if ! installed tool_name; then
     info "Installing tool_name..."
     brew_install tool_name
     mark_done "tool_name"
   fi
   ```
3. Add any configuration below the install block
4. Update `--list` output and the README tool table
5. Test with `--dry-run` and a real install on a clean-ish system if possible

## Reporting Issues

- Use GitHub Issues for bugs, feature requests, and tool suggestions
- Include your OS version and the script output/log when reporting bugs
- Check existing issues before opening a new one

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
