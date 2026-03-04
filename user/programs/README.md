# User Program Modules

Common user program configs shared across shells/WMs.

## Files

- `default.nix`: aggregation entrypoint
- `alacritty/default.nix`
- `betterdiscord/default.nix`
- `fastfetch/default.nix`
- `keepassxc/default.nix`
- `wlogout/default.nix`

Program toggles should be wired through `settings.programs.*`.

`KeePassXC` is user-scoped via `settings.userSettings.<name>.programs.keepassxc.*` and supports:
- optional autostart
- optional startup database path
- optional secret-backed key file deployment (`keyFileSecretName`)
- optional workspace integration (`workspace.mode = special-workspace|minimizer`)
- optional unlock modes (`autoUnlock.mode = strict|balanced|convenient|full-auto`)
- autostart via user systemd (`graphical-session.target`), which is reliable on Hyprland

Installed helper commands:
- `keepassxc-startup`: start KeePassXC with configured unlock/workspace behavior
- `keepassxc-toggle`: toggle Keepass visibility (special workspace or minimizer mode)
- `keepassxc-doctor`: print effective runtime checks (db/keyfile/keyring/secret)
- `keepassxc-secret-set [entry]`: store KeePass database password in keyring for convenient mode

If `settings.userSettings.<name>.hyprland.minimizer.enable = true` and `workspace.mode = \"minimizer\"`,
KeePassXC startup prefers the minimizer workflow over `--minimized`.
