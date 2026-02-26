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
      # Keep this generic; NixOS validates the final shape via hardware.printers.ensurePrinters.
      type = lib.types.listOf lib.types.anything;
      default = [ ];
      description = "Declarative printers for hardware.printers.ensurePrinters.";
    };

    defaultPrinter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default printer name for hardware.printers.ensureDefaultPrinter.";
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

        hardware.printers.ensurePrinters = cfg.printers;
      })

      (lib.mkIf (cfg.enable && cfg.defaultPrinter != null) {
        hardware.printers.ensureDefaultPrinter = cfg.defaultPrinter;
      })
    ];
}
