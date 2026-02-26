{ config, lib, ... }:
{
  options.j0nix.desktop.printing = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable desktop printing (CUPS) configuration.";
    };

    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "CUPS driver packages to install via services.printing.drivers.";
    };

    printers = lib.mkOption {
      type = lib.types.listOf lib.types.anything;
      default = [ ];
      description = "Reserved for future printer definitions (currently not applied declaratively).";
    };

    defaultPrinter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Reserved for future default printer selection (currently not applied declaratively).";
    };
  };

  config =
    let
      cfg = config.j0nix.desktop.printing;
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
        services.printing = {
          enable = true;
          drivers = cfg.drivers;
        };
      })
    ];
}
