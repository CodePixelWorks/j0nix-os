# Starter Profile

Copy this directory to a new profile name, then create the required real
files from the templates:

```bash
cp -r profiles/starter profiles/my-host
cp profiles/my-host/details.nix.example profiles/my-host/details.nix
cp profiles/my-host/secrets.nix.example profiles/my-host/secrets.nix
sudo nixos-generate-config --show-hardware-config > profiles/my-host/hardware-configuration.nix
```

Edit `details.nix`, especially `system`, `hostname`, monitors, drivers, boot
resume data, and `storage.systemMounts`. Put cross-host preferences and users
in `settings.nix`; keep UUIDs, PCI IDs, kernel quirks, and other hardware data
in this profile.

The flake discovers the new profile automatically once `details.nix` exists.
Validate it with:

```bash
nix flake check --no-build
```
