# Explicit Host-to-Profile Mapping Pattern

## Problem

Putting `profileName` into `settings.nix` violates the architecture boundary:

- `settings.nix` = cross-platform toggles and defaults
- `profiles/`     = host-specific hardware data and machine-local constants

When `profileName` lives in `settings.nix`, every host must share one value. Multi-host becomes impossible without duplicating the entire settings file.

## Solution: Move mapping into `flake.nix`

Use a helper function that accepts `profileName` explicitly per host definition:

```nix
# flake.nix
let
  mkNixosSystem = { profileName, extraModules ? [ ] }:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./settings.nix
        (./profiles + "/${profileName}/configuration.nix")
      ] ++ extraModules;
    };
in
{
  nixosConfigurations = {
    Jonas-PC      = mkNixosSystem { profileName = "desktop"; };
    # Jonas-Laptop  = mkNixosSystem { profileName = "laptop"; };
  };
}
```

### Same pattern for Home Manager

Home Manager `homeConfigurations` must also use per-host profile selection:

```nix
homeConfigurations = {
  "jonas@Jonas-PC" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ./settings.nix
      (./profiles/desktop/home.nix)
      {
        home.username = "jonas";
        home.homeDirectory = "/home/jonas";
      }
    ];
  };
};
```

**Format convention**: use `"user@hostname"` as the home configuration attribute name, mirroring the NixOS host naming. This makes `home-manager switch --flake .#jonas@Jonas-PC` unambiguous.

## Verification checklist

After refactoring:
1. `nix flake check --no-build` passes
2. `settings.nix` no longer contains any `profileName` field
3. `nix flake show` lists all expected hosts and home configurations
4. `nixos-rebuild switch --flake .#<hostname>` still works (CLI unchanged)

## Multi-host impact

Before (broken):
```nix
# settings.nix
profileName = "desktop";  # laptop would need a separate settings.nix
```

After (host-agnostic settings):
```nix
# settings.nix — no profileName, pure cross-platform defaults
# flake.nix — explicit host wiring
Jonas-PC     = mkNixosSystem { profileName = "desktop"; };
Jonas-Laptop = mkNixosSystem { profileName = "laptop"; };
```

Both hosts share the same `settings.nix` while picking different hardware profiles.
