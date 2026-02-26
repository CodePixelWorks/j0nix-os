{ config, lib, pkgs, inputs, ... }:
let
  kernelPresets = import ../lib/kernel-presets.nix { };
  cfg = config.j0nix.desktop.kernel;
  preset = kernelPresets.presets.${cfg.preset};
in
{
  options.j0nix.desktop.kernel.preset = lib.mkOption {
    type = lib.types.enum kernelPresets.presetNames;
    default = "stable";
    description = "Named kernel preset for the desktop profile.";
  };

  config = {
    nixpkgs.overlays = lib.mkIf preset.usesCachyosOverlay [
      inputs.nix-cachyos-kernel.overlays.pinned
    ];

    boot.kernelPackages = preset.mkKernelPackages pkgs;
  };
}
