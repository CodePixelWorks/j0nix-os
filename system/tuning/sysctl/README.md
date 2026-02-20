# Sysctl Profiles

Split sysctl model for clean composition.

## Files

- `default.nix`: merge layer
- `gaming.nix`: gaming-oriented kernel parameters
- `dev.nix`: development-oriented kernel parameters

## Control Keys

- `settings.sysctlProfiles.fileMax`
- `settings.sysctlProfiles.gaming.*`
- `settings.sysctlProfiles.dev.*`
- `settings.sysctlProfiles.custom`
