# Profiles

Profiles define top-level system/home composition.

## Available Profiles

- `desktop/`

## How It Is Used

- `nix/system/lib/flake/outputs.nix` discovers every profile containing `details.nix`
- the `hostname` from `details.nix` becomes the `nixosConfigurations` key
- then imports `profiles/desktop/configuration.nix` for NixOS
- and `profiles/desktop/home.nix` for Home Manager

To add a machine, copy a profile directory, provide a real `details.nix` and
`secrets.nix`, and set its unique `hostname`. No central flake edit is needed.
