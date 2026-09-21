# Session: Settings vs Profiles Boundary Correction (j0nix-os, May 21 2026)

## What Happened

During a profile thin-piping refactor, host-specific data was mistakenly moved from profile modules into `settings.nix`:
- `resumeDevice`, `resumeOffset` (boot)
- `it87` fan controller config (thermal)
- kernel module names, `kvmfr` blacklist (kernel)
- NVIDIA package version selector string (drivers)

## Why It Was Wrong

Settings.nix is for **cross-platform defaults** (feature toggles, user preferences, app configs). Profiles are for **host-specific hardware declarations** (UUIDs, kernel params, I2C sensor IDs, GPU packages). A laptop or server would never reuse a desktop's `resumeOffset` or `it87` config.

Thin-piping *everything* into settings destroys the boundary and pollutes portable configuration with machine-local data.

## Correction Applied

Commits `ab5a0b8` and `27af0dd` were reverted via `b2c19f0`.

AGENTS.md was updated with two new rules:
- Do: "Profiles host-specific data; settings host-generic data"
- Don't: "Don't move host-specific declarations into settings.nix"

## Distinction Examples

| Belongs in Settings | Belongs in Profile |
|---|---|
| `settings.boot.splash.theme` (cross-platform preference for Plymouth) | `resumeDevice` / `resumeOffset` (unique to this host) |
| `settings.drivers.nvidia.enable` (feature toggle) | `it87` / `jc42` fan/sensor names (board-specific) |
| `settings.kernel.preset = "cachyos"` (could be shared) | `kernelParams = ["usbcore.autosuspend=-1"]` (specific to this hardware)
| `settings.audio.backend` (user preference) | blacklisted modules for a specific board (e.g. `ee1004`) |

## Rule of Thumb

Ask: "Would another host (laptop, server, different desktop) need to override this?"
- **Yes** → settings.nix
- **No** → profile module

## Multi-Host Flake Refactoring Pattern

When a repo outgrows a single host, host→profile mapping should be explicit in `flake.nix`, not hidden in `settings.nix`.

### Before (host-specific data in settings)
```nix
# settings.nix (WRONG — host-generic file contains host-specific mapping)
{ profileName = "desktop"; }

# flake.nix (reads host-specific value from supposedly generic settings)
nixosConfigurations.Jonas-PC = nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs settings; };
};
```

### After (explicit host mapping in flake)
```nix
# settings.nix (CORRECT — pure cross-platform defaults, no profileName)
{ userSettings = { ... }; audio = { ... }; }

# flake.nix (hosts declared explicitly, settings stays host-agnostic)
mkNixosSystem = { profileName }: nixpkgs.lib.nixosSystem {
  specialArgs = {
    inherit inputs;
    settings = baseSettings;
    profilePath = ./profiles/${profileName};
  };
};

nixosConfigurations = {
  Jonas-PC    = mkNixosSystem { profileName = "desktop"; };
  Jonas-Laptop = mkNixosSystem { profileName = "laptop";  };
};

homeConfigurations = nixpkgs.lib.mapAttrs' (hostName: hostConfig: {
  name = "${username}@${hostName}";
  value = home-manager.lib.homeManagerConfiguration { ... };
}) hosts;
```

### Benefits
- `settings.nix` remains a portable contract: copy it unmodified to any host.
- Adding a host is a one-line change in `flake.nix`.
- `homeConfigurations` use `username@hostname` keys, allowing per-host home-manager differences from shared settings.
- The rebuild command (`nixos-rebuild switch --flake .#Jonas-PC`) stays unchanged — backward compat preserved.

### Concrete Example (j0nix-os, commit 370ccbc)
- `profileName` removed from `settings.nix` AND from `settings.nix.example` (example files must follow architecture changes even though they don't participate in `nix flake check`)
- `flake.nix` introduced `mkHostAttrs`, `mkNixosSystem`, `mkHomeManagerConfiguration`
- `nixosConfigurations.Jonas-PC = mkNixosSystem { profileName = "desktop"; }`
- `settings.nix` shrank by 7 lines; flake.nix grew by explicit host wiring
- Post-refactor example file audit: `settings.nix.example` rewritten to remove `profileName`, add full category docs, and safe placeholder defaults (commit af6e5f7)
- Validation: `nix flake check --no-build` passed immediately after refactor; example files verified standalone via `nix-instantiate --eval`
