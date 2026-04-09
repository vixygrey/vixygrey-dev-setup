# Security Policy

## Scope

This policy covers the setup scripts in this repository (`setup-dev-tools-mac.sh`, `setup-dev-tools-linux.sh`, `setup-dev-tools-windows.ps1`) and their configuration outputs. It does not cover vulnerabilities in the third-party tools these scripts install.

## Reporting a Vulnerability

If you discover a security issue in this project, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email **grey@vixygrey.dev** with:
   - A description of the vulnerability
   - Steps to reproduce
   - Affected script(s) and line numbers if known
   - Potential impact
3. You will receive an acknowledgment within 48 hours
4. A fix will be prioritized based on severity

## What Qualifies

- Scripts that write secrets, credentials, or tokens to world-readable files
- Command injection via user input or environment variables
- Unsafe file permissions on sensitive config files (SSH keys, GPG, etc.)
- Heredocs or config blocks that could be exploited if a tool name contains shell metacharacters
- Sudo escalation beyond what is documented

## What Does Not Qualify

- Vulnerabilities in third-party tools installed by the scripts (report those upstream)
- Missing features or hardening suggestions (open a regular issue instead)
