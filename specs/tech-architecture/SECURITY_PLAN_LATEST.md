# Security plan

<!-- Threat model, trust boundaries, and the checks that guard them. Written by the security-review skill. -->

<!-- Starting material, for whoever writes this first: SECURITY.md already states
     the scope and what qualifies. The script's real trust boundaries are the
     remote installers (run_remote_installer), the sudo surface (sudo_reasons),
     file permissions on ~/.ssh and ~/.gnupg, and the managed-block deletion test
     in write_managed, which is the guard against eating user config. -->
