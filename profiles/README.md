# Profiles

Profiles define top-level system/home composition.

## Available Profiles

- `desktop/`

## How It Is Used

- `flake.nix` reads `profiles/desktop/meta.nix` for machine identity
- then imports `profiles/desktop/configuration.nix` for NixOS
- and `profiles/desktop/home.nix` for Home Manager
