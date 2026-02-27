{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.scanning;
in
{
  options.j0nix.desktop.scanning = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable scanner support (SANE) configuration.";
    };

    extraBackends = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional SANE backend packages (for example hplipWithPlugin).";
    };

    software = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Scanner management software to add via the central system package aggregator.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      extraBackends = cfg.extraBackends;
    };

    j0nix.software.systemPackages = cfg.software;
  };
}
