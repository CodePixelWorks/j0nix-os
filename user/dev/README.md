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
- The attr name of each `dev.ssh.hosts.<name>` entry becomes the generated `Host <name>` entry. `host = ...` is used as `HostName ...`, so `hosts.webserver.host = "132.145.254.17"` yields `Host webserver` plus `HostName 132.145.254.17`.
- `settings.userSettings.<name>.dev.ssh.agent.provider = "gnome-keyring"`: route SSH agent handling through the session keyring
- `settings.userSettings.<name>.dev.ssh.keyring.enable = true`: prefer askpass/keyring-assisted passphrase prompts in GUI sessions
- `SSH_ASKPASS`/`SUDO_ASKPASS` point at the GNOME askpass binary when the SSH agent provider is `gnome-keyring`
- `ssh-add-gui`: explicit `openssh-askpass`/GNOME askpass wrapper for `ssh-add`
- `settings.dev.python.enable`: install baseline Python tooling for development
- `settings.dev.python.versionManager = "mise"`: activate `mise` in the shell for fast Python version switching
- `settings.dev.python.installUv = true`: install `uv` alongside the version manager
- `pyuse 3.12`: switch the global Python version through `mise`
- `pylocal 3.12`: pin a project-local Python version through `mise`
- `claude`: shell alias for `claude-code`
- `settings.userSettings.<name>.secrets.sshKeys.<name>.passphraseKey`: optional SOPS path for automatic key loading into the keyring-backed agent
- The automatic loader waits for the `gcr` SSH socket and retries `ssh-add`, so key loading is resilient to slower desktop startup ordering
- `settings.dev.ai.installScope`: install shared AI CLIs as `system` packages or per-user via Home Manager
- `settings.dev.ai.codex.mcp.nixos`: install `mcp-nixos` and register it in `~/.codex/config.toml` as the `nixos` MCP server without clobbering other Codex settings
- `settings.dev.ai.opencode`: install the `opencode` terminal coding agent in the shared AI tool scope
- `settings.dev.ai.claudeCode`: install the `claude-code` CLI in the same AI tool scope as Codex/Gemini
