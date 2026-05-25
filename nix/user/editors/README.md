# User Editor Modules

Editor modules are selected via `userSettings.<name>.editors`.

## Current Modules

- `neovim/default.nix`
- `vscode/default.nix`

Each module should stay editor-focused and avoid unrelated package bloat.

VS Code defaults are sourced from `settings.vscode.*`. The current module seeds
missing user settings keys into the writable `settings.json` and uses
`settings.vscode.theme.colorTheme` as the default color theme without forcing it
over later in-UI changes.
