This module provides a baseline developer system setup.
Controlled by `settings.dev.*`.

Also manages:
- SSH agent provider selection (`settings.dev.ssh.agent.provider`)
- OpenSSH agent startup (`provider = "openssh"`)
- GNOME keyring service (`settings.dev.ssh.keyring.enable` or `provider = "gnome-keyring"`)
