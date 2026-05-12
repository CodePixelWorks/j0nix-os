# Desktop Profile

Main desktop profile for `j0nix-os`.

## Files

- `configuration.nix`: core system config, users, audio, locale, packages
- `home.nix`: base user packages and XDG defaults
- `details.nix`: profile-specific metadata used by settings merge
- `secrets.nix`: profile-scoped system secret defaults (merged into settings.secrets)
- `hardware-configuration.nix`: hardware-generated baseline

## Key Settings Hooks

- `settings.userSettings.*` (user names are derived from its attribute keys)
- `settings.audio.*`
- `settings.userSettings.<name>.storage.*`
- `settings.locale`, `settings.timezone`
- `settings.inputMethod.*`
- `settings.wms`

## Storage

- `settings.userSettings.<name>.storage.sambaShares` defines per-user declarative CIFS/Samba mounts.
- The desktop profile aggregates all user-defined Samba shares into the system mount set.
- Shares are mapped into the shared desktop storage model and mounted with:
  - `_netdev`
  - `nofail`
  - `x-systemd.automount`
- User-mode SMB mounts can either use raw `username` / `password` / `domain` fields in the share entry or `secretName` via the per-user SOPS layer. If both are present, the secret values override the raw fields.
- This means they persist declaratively, but only mount on access and do not block boot when the server is offline.
