{ ... }:
let
  mkPreset = attrs: attrs;
  presets = {
    stable = mkPreset {
      description = "Default NixOS kernel package set";
      usesCachyosOverlay = false;
      mkKernelPackages = pkgs: pkgs.linuxPackages;
    };

    latest = mkPreset {
      description = "Latest upstream kernel package set from nixpkgs";
      usesCachyosOverlay = false;
      mkKernelPackages = pkgs: pkgs.linuxPackages_latest;
    };

    lts = mkPreset {
      description = "Long-term support kernel package set";
      usesCachyosOverlay = false;
      mkKernelPackages = pkgs: pkgs.linuxPackages_lts;
    };

    zen = mkPreset {
      description = "linux-zen kernel package set";
      usesCachyosOverlay = false;
      mkKernelPackages = pkgs: pkgs.linuxPackages_zen;
    };

    cachyos-x86_64-v4 = mkPreset {
      description = "CachyOS latest kernel for x86_64-v4";
      usesCachyosOverlay = true;
      mkKernelPackages = pkgs: pkgs.cachyosKernels."linuxPackages-cachyos-latest-x86_64-v4";
    };
  };
in
{
  inherit presets;
  presetNames = builtins.attrNames presets;
}
