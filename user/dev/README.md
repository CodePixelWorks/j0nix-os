# User Dev Modules

User-facing dev tooling modules.

## Files

- `default.nix`: core dev CLI/tooling packages
- `ai-cli.nix`: Codex/Gemini CLI integration

## Control

Managed by `settings.dev.*`.

Notable controls:
- `settings.dev.git.*`: global `git` identity and host-based include rules
- `settings.dev.git.hostProfiles.<name>.*`: host, per-host `userName`/`userEmail`, and SSH key mapping
- `settings.dev.ssh.addKeysToAgent`: propagated into SSH client config
