# Desktop Profile

Main desktop profile for `j0nix-os`.

## Files

- `configuration.nix`: core system config, users, audio, locale, packages
- `home.nix`: base user packages and XDG defaults
- `details.nix`: profile-specific metadata used by settings merge
- `hardware-configuration.nix`: hardware-generated baseline

## Key Settings Hooks

- `settings.users`, `settings.userSettings.*`
- `settings.audio.*`
- `settings.storage.*`
- `settings.locale`, `settings.timezone`
- `settings.wms`

## Storage

- `settings.storage.sambaShares` defines declarative CIFS/Samba mounts.
- Shares are mapped into the shared desktop storage model and mounted with:
  - `_netdev`
  - `nofail`
  - `x-systemd.automount`
- This means they persist declaratively, but only mount on access and do not block boot when the server is offline.
