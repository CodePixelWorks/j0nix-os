# Flatpak-Based Program Module Pattern

When a desired application is not packaged in nixpkgs but is available as a
Flatpak, create a dedicated Home Manager program module that declares the
Flatpak installation alongside any desktop integration (icons, .desktop files,
autostart) the user expects.

## When to Use This Pattern

- The application has **no nixpkgs package** (e.g. `balena-etcher` at the time
  of writing).
- The Flatpak is officially maintained and available on Flathub.
- The app does not need deep NixOS system integration (kernel modules, udev
  rules, etc.) that would require a system-level module.

## When NOT to Use This Pattern

- A native nixpkgs package exists — prefer `pkgs.foo` in a role or
  `j0nix.user.software.packages`.
- The app needs custom udev rules, kernel modules, or polkit policies that
  cannot be expressed inside a Flatpak sandbox. Use a system module instead.

## Module Template

```nix
# nix/user/programs/balena-etcher/default.nix
{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).balenaEtcher or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "flatpak";

  # Optional: derive the exact Flatpak ref from settings
  flatpakRef = cfg.flatpakRef or "com.balena.etcher";
in
lib.mkIf enabled {
  # 1. Install the Flatpak declaratively
  services.flatpak.packages = [ flatpakRef ];

  # 2. Optional: add a wrapper script or desktop file if the Flatpak
  #    does not expose a convenient binary name
  home.packages = lib.optional (provider == "wrapper")
    (pkgs.writeShellScriptBin "balena-etcher" ''
      exec flatpak run ${flatpakRef} "$@"
    '');

  # 3. Optional: autostart or systemd user service
  # systemd.user.services.balena-etcher = { ... };
}
```

## Settings Contract

```nix
# settings.nix
{
  programs.balenaEtcher = {
    enable = true;
    provider = "flatpak";      # future-proof: could become "nixpkgs" later
    flatpakRef = "com.balena.etcher";
  };
}
```

## Registering the Module

Add the module name to `defaultHomePrograms` (or a role's `imports`):

```nix
# settings.nix
defaultHomePrograms = [
  # ... other programs ...
  "balena-etcher"
];
```

Or attach it to a role:

```nix
# nix/roles/home/imaging.nix
{ pkgs, ... }:
{
  imports = [ ../../user/programs/balena-etcher ];
  j0nix.user.software.packages = with pkgs; [ rpi-imager ];
}
```

## Pitfalls

- **Flatpak ID typos**: `services.flatpak.packages` does not validate IDs at
  evaluation time. A typo only surfaces at activation (build succeeds, install
  fails). Double-check the Flathub ID.
- **Icon themes**: Flatpak apps may not inherit the host icon theme. If the
  app shows a generic icon, check whether the Flatpak runtime matches the
  host's icon directory (`xdg-data/icons`).
- **Portal availability**: Some Flatpak apps require `xdg-desktop-portal-gtk`
  or `xdg-desktop-portal-gnome` on the host. Ensure the system WM module
  installs the correct portal backend.
- **No rollback granularity**: Flatpak installations are managed outside the
  Nix store. A `nixos-rebuild switch --rollback` does not rollback Flatpak
  app updates. Pin the Flatpak ref to a specific commit if reproducibility
  matters.
- **Permission changes**: Flatpak overrides (filesystem, device, network)
  must be applied with `flatpak override` or a dedicated system module. The
  HM `services.flatpak.packages` only installs — it does not configure
  sandbox permissions.

## Testing Checklist

- [ ] `nix flake check --no-build` passes after adding the module.
- [ ] The Flatpak ID is confirmed on Flathub (`flatpak search <name>`).
- [ ] After rebuild, `flatpak list` shows the app.
- [ ] The app launches and basic functionality works.
- [ ] If a wrapper script is provided, `which <wrapper-name>` resolves.
