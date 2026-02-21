# System Tuning

Performance and kernel/userland tuning modules.

## Files

- `default.nix`: tuning entrypoint
- `thermal.nix`: thermal/fan baseline (governor + hwmon module)
- `sysctl/`: split sysctl profiles (gaming/dev/custom merge)

## Control

Managed through `settings.sysctlProfiles.*`.
Thermal tuning is managed through `settings.thermal.*`.
