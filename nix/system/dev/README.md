This module provides a baseline developer system setup.
Controlled by `settings.dev.*`.

Shared defaults live in `settings.dev.*`, but feature enablement is derived from
`settings.userSettings.<name>.dev.*`.

Notable controls:
- `settings.userSettings.<name>.dev.docker.enable`: enables the shared Docker daemon and adds that user to the `docker` group
- `settings.userSettings.<name>.dev.ai.enable`: marks the user as an AI tooling user
- `settings.dev.ai.installScope`: installs Codex/Gemini CLIs as `system` packages (`system`) or leaves them to Home Manager (`user`)
- `settings.dev.ai.caveman`: installs the shared `caveman` Agent Skill into the user skill directories used by Codex, Kilo Code, Claude Code, and compatible Agent Skills consumers

Also manages:
- SSH agent provider selection (`settings.userSettings.<name>.dev.ssh.agent.provider`)
- OpenSSH agent startup (`provider = "openssh"`)
- GNOME keyring service (`settings.userSettings.<name>.dev.ssh.keyring.enable` or `provider = "gnome-keyring"`)
- Nix dynamic loader compatibility (`settings.dev.nixLd.enable`)
- Dev virtualisation defaults (`settings.dev.virtualisation.*`) which can install `vagrant`/`qemu` in user dev bundles, optionally wire `vagrant-libvirt`, and enable the shared libvirt/QEMU host stack when requested
