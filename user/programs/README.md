# User Program Modules

Common user program configs shared across shells/WMs.

## Files

- `default.nix`: aggregation entrypoint
- `alacritty/default.nix`
- `element/default.nix`
- `betterdiscord/default.nix`
- `fastfetch/default.nix`
- `wlogout/default.nix`

Program toggles should be wired through `settings.programs.*`.

`Element` is user-scoped via `settings.userSettings.<name>.programs.element.*` and supports:
- package selection (`desktop` or `web` if available)
- plain declarative `config` JSON
- raw `configText`
- `configFileSecretName` for a secret-backed `~/.config/Element/config.json`
