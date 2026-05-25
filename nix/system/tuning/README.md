# System Tuning

Performance and kernel/userland tuning modules.

## Files

- `default.nix`: tuning entrypoint
- `thermal.nix`: thermal/fan baseline (governor + hwmon module)
- `sysctl/`: central sysctl collector for role-provided fragments

## Control

Sysctls are managed through `j0nix.desktop.sysctl.extraFragments`, typically from `user-roles/nix/system/*`, with `settings.custom.sysctl` reserved for explicit overrides.
Thermal tuning is managed through `settings.thermal.*`.
