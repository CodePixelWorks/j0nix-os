# Profiles

Profiles define top-level system/home composition.

## Available Profiles

- `desktop/`

## How It Is Used

- `nix/system/lib/flake/outputs.nix` discovers every profile containing `details.nix`
- the `hostname` from `details.nix` becomes the `nixosConfigurations` key
- then imports `profiles/desktop/configuration.nix` for NixOS
- and `profiles/desktop/home.nix` for Home Manager

To add a machine, start with the neutral template:

```bash
cp -r profiles/starter profiles/my-host
cp profiles/my-host/details.nix.example profiles/my-host/details.nix
cp profiles/my-host/secrets.nix.example profiles/my-host/secrets.nix
sudo nixos-generate-config --show-hardware-config > profiles/my-host/hardware-configuration.nix
```

Set the unique `hostname` in `details.nix`, configure hardware-specific data
there, and put users and cross-host preferences in `settings.nix`. The flake
discovers the profile automatically; no `flake.nix` edit is needed.
