# Integrations

This directory contains vendored third-party integrations that are tracked as git subtrees or subflakes but wired into the main j0nix-os architecture.

Each integration is a standalone unit with its own `flake.nix`, providing packages, NixOS modules, and/or Home Manager modules. The main flake at the repo root imports these as `inputs` with `nixpkgs` / `home-manager` follows so versions stay aligned.

## Current integrations

| Name | Path | Type | Description |
|------|------|------|-------------|
| autodesk-fusion-nixos | `integrations/autodesk-fusion-nixos/` | Subflake | Autodesk Fusion runtime helpers for NixOS. Provides `pkgs.autodesk-fusion-linux`, a NixOS module, and a Home Manager module. |

## Adding a new integration

1. Place the integration code under `integrations/<name>/`.
2. Ensure it exposes at minimum:
   - `overlays.default` for package overrides
   - `homeManagerModules.default` and/or `nixosModules.default` for system config
3. Add an `inputs.<name>` entry in the root `flake.nix` pointing to `path:./integrations/<name>`.
4. Wire the overlay into `system/lib/flake/overlays.nix` or import modules directly in the relevant `system/` / `user/` modules.

## Why vendored instead of flake inputs?

- Pins a known-good revision that has been tested with the current j0nix-os.
- Allows local patches without forking upstream.
- Keeps the repo self-contained for offline/air-gapped rebuilds.
