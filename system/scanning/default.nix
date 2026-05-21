{ config, lib, pkgs, ... }:
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
      description = "Additional SANE backend packages.";
    };

    software = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Scanner management software to add via the central system package aggregator.";
    };

    enableNetBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SANE net backend.";
    };

    useHplipBackend = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include hplipWithPlugin as a SANE backend (requires allowUnfree).";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      extraBackends = cfg.extraBackends ++ lib.optionals cfg.useHplipBackend [ pkgs.hplipWithPlugin ];
      disabledDefaultBackends = lib.optionals (!cfg.enableNetBackend) [ "net" ];
    };

    j0nix.software.systemPackages = cfg.software ++ lib.optionals cfg.useHplipBackend [ pkgs.hplip ];
  };
}
