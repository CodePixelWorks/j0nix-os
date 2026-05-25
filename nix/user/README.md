# User Modules

Home Manager modules composed per user.

## Structure

- `shells/`: interactive shell setup (zsh/fish)
- `wm/`: user-side WM config (Hyprland shell selection, GNOME user settings)
- `editors/`: Neovim/VSCode
- `browsers/`: browser modules
- `programs/`: shared user app configs
- `storage/`: user-scoped storage helpers (e.g. GVFS-backed SMB mounts)
- `dev/`: user dev/AI tools
- `gaming/`: user gaming launchers and extras
- `session-default.nix`: per-user default DM session (`.dmrc`)

## Control Keys

- `settings.userSettings.<name>.*`
- `settings.userSettings.<name>.wmShell` (legacy alias: `hyprlandShell`)
