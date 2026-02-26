{ config, lib, pkgs, inputs, ... }:
let
  kernelPresets = import ../lib/kernel-presets.nix { };
  modprobe = import ../lib/modprobe.nix { inherit lib; };
  cfg = config.j0nix.desktop.kernel;
  preset = kernelPresets.presets.${cfg.preset};
  hasModprobeOptions = cfg.modprobeOptions != { };
in
{
  options.j0nix.desktop.kernel = {
    preset = lib.mkOption {
      type = lib.types.enum kernelPresets.presetNames;
      default = "stable";
      description = "Named kernel preset for the desktop profile.";
    };

    modules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional kernel modules to load on boot.";
    };

    modprobeOptions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
        lib.types.bool
        lib.types.int
        lib.types.float
        lib.types.str
      ]));
      default = { };
      description = "Kernel module options grouped by module name.";
    };
  };

  config = {
    nixpkgs.overlays = lib.mkIf preset.usesCachyosOverlay [
      inputs.nix-cachyos-kernel.overlays.pinned
    ];

    boot.kernelPackages = preset.mkKernelPackages pkgs;

    boot.kernelModules = lib.mkAfter cfg.modules;

    boot.extraModprobeConfig =
      lib.mkIf hasModprobeOptions (lib.mkAfter (modprobe.fromAttrset cfg.modprobeOptions));
  };
}
