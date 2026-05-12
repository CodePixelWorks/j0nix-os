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
- `settings.userSettings.<name>.secrets.gpgKeys.<name>`: SOPS-backed GPG private key material that is imported automatically into `~/.gnupg` during Home Manager activation
- `settings.userSettings.<name>.secrets.gpgKeys.<name>.passphraseKey`: optional SOPS path for preloading the matching GPG passphrase into `gpg-agent`
- `settings.userSettings.<name>.dev.gpg.agentCacheTtl`: `gpg-agent` passphrase cache TTL in seconds for managed GPG keys
- `settings.userSettings.<name>.dev.gpg.agentMaxCacheTtl`: maximum `gpg-agent` passphrase cache TTL in seconds for managed GPG keys
- `settings.userSettings.<name>.dev.gpg.presetInterval`: systemd timer interval for refreshing managed GPG passphrases in `gpg-agent`
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
- `settings.dev.androidStudio`: install Android Studio in the shared user dev package set
- Baseline user dev packages include Go and Rust toolchains (`go`, `cargo`, `rustc`)
- `settings.dev.virtualisation.enable`: install the shared VM development toolset and request the libvirt/QEMU host stack when any dev user enables it
- `settings.dev.virtualisation.vagrant = true`: install the `vagrant` CLI in the dev tool bundle
- `settings.dev.virtualisation.vagrantLibvirt = true`: use the repo-packaged `vagrant` variant with declarative `vagrant-libvirt` system plugin wiring
- `settings.dev.virtualisation.qemu = true`: install the `qemu` CLI in the dev tool bundle
- `pyuse 3.12`: switch the global Python version through `mise`
- `pylocal 3.12`: pin a project-local Python version through `mise`
- `claude`: shell alias for `claude-code`
- `settings.userSettings.<name>.secrets.sshKeys.<name>.passphraseKey`: optional SOPS path for automatic key loading into the keyring-backed agent
- Managed GPG keys are imported only when the encrypted source changes, so rebuilds stay quiet while key rotations still deploy automatically
- Managed GPG passphrases use `gpg-preset-passphrase`, refresh all keygrips through a user systemd timer, and keep signing non-interactive while leaving the encrypted source in SOPS
- The automatic loader waits for the `gcr` SSH socket and retries `ssh-add`, so key loading is resilient to slower desktop startup ordering
- `settings.dev.ai.installScope`: install shared AI CLIs as `system` packages or per-user via Home Manager
- `settings.dev.ai.codex.mcp.nixos`: install `mcp-nixos` and register it in `~/.codex/config.toml` as the `nixos` MCP server
- `settings.dev.ai.codex.mcp.github`: install `github-mcp-server` and register it in `~/.codex/config.toml` as the `github` MCP server
- `settings.dev.ai.codex.mcp.hyprland`: install `hyprmcp` and register it in `~/.codex/config.toml` as the `hyprland` MCP server; it requires a live Hyprland session so `HYPRLAND_INSTANCE_SIGNATURE` is available
- `settings.dev.ai.codex.mcp.lsp.enable`: install a dedicated LSP-to-MCP bridge and register per-language Codex MCP servers
- `settings.dev.ai.codex.mcp.lsp.languages`: choose which language-specific MCP bridges to generate; supported values are `nix`, `rust`, `python`, `typescript`, `go`
- LSP MCP server names follow `lsp-<language>` in `~/.codex/config.toml` (for example `lsp-nix`, `lsp-rust`, `lsp-python`)
- Each generated LSP MCP wrapper resolves the workspace from the current git root (or the current working directory when outside git) and starts the matching language server with the right stdio flags
- `settings.dev.ai.ncp`: install the `ncp` (`@portel/ncp`) CLI as a unified MCP host/helper in the shared AI tool scope
- `settings.dev.ai.kiloCode`: install the `kilocode` CLI (`@kilocode/cli@alpha`) in the shared AI tool scope and add the `kilocode.kilo-code` VS Code extension
- `settings.dev.ai.caveman`: install the `caveman` Agent Skill into `~/.codex/skills`, `~/.kilo/skills`, `~/.claude/skills`, and `~/.agents/skills`
- `settings.dev.ai.opencode`: install the `opencode` terminal coding agent in the shared AI tool scope
- `settings.dev.ai.claudeCode`: install the `claude-code` CLI in the same AI tool scope as Codex/Gemini
- The Codex MCP sync manages the repo-owned MCP blocks (`nixos`, `github`, `hyprland`, and any enabled `lsp-*` entries) without clobbering other Codex settings
