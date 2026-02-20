# Profiles

Profiles define top-level system/home composition.

## Available Profiles

- `desktop/`

## How It Is Used

- `flake.nix` reads `settings.profile`
- then imports `profiles/<profile>/configuration.nix` for NixOS
- and `profiles/<profile>/home.nix` for Home Manager
