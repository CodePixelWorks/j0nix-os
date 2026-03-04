# User Dev Modules

User-facing dev tooling modules.

## Files

- `default.nix`: core dev CLI/tooling packages
- `ai-cli.nix`: Codex/Gemini CLI integration

## Control

Managed by global `settings.dev.*` defaults plus per-user `settings.userSettings.<name>.dev.*`.

Notable controls:
- `settings.userSettings.<name>.dev.docker.enable`: opt the user into Docker access (`docker` group and shared daemon)
- `settings.userSettings.<name>.dev.ai.enable`: opt the user into AI CLI tooling
- `settings.userSettings.<name>.dev.git.*`: per-user git identity and per-host git identity overrides
- `settings.userSettings.<name>.dev.git.hostProfiles.<name>.*`: per-host `userName`/`userEmail` overrides for git includes
- `settings.userSettings.<name>.dev.ssh.*`: per-user SSH client policy
- `settings.userSettings.<name>.dev.ssh.hosts.<name>.*`: SSH host definitions, aliases, and identity mapping
- `settings.dev.ai.installScope`: install shared AI CLIs as `system` packages or per-user via Home Manager
