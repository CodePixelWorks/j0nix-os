# User Dev Modules

User-facing dev tooling modules.

## Files

- `default.nix`: core dev CLI/tooling packages
- `ai-cli.nix`: Codex/Gemini CLI integration

## Control

Managed by global `settings.dev.*` plus per-user `settings.userSettings.<name>.dev.*`.

Notable controls:
- `settings.userSettings.<name>.dev.git.*`: per-user git identity and per-host git identity overrides
- `settings.userSettings.<name>.dev.git.hostProfiles.<name>.*`: per-host `userName`/`userEmail` overrides for git includes
- `settings.userSettings.<name>.dev.ssh.*`: per-user SSH client policy
- `settings.userSettings.<name>.dev.ssh.hosts.<name>.*`: SSH host definitions, aliases, and identity mapping
