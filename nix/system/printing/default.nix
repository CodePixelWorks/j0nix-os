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

    software = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Printer management software to add via the central system package aggregator.";
    };

    discovery = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable mDNS/Avahi service discovery for network printers.";
      };
    };

    printers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "^[^/#[:space:]]+$";
              description = "CUPS queue name.";
            };

            location = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional human-readable printer location.";
            };

            description = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional human-readable printer description.";
            };

            deviceUri = lib.mkOption {
              type = lib.types.str;
              description = "Printer device URI.";
            };

            model = lib.mkOption {
              type = lib.types.str;
              description = "Printer model/PPD identifier.";
            };

            ppdOptions = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Optional PPD option overrides.";
            };
          };
        }
      );
      default = [ ];
      description = "CUPS printers to declare via hardware.printers.ensurePrinters.";
    };

    defaultPrinter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default CUPS printer queue to declare via hardware.printers.ensureDefaultPrinter.";
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

        hardware.printers = {
          ensurePrinters = cfg.printers;
          ensureDefaultPrinter = cfg.defaultPrinter;
        };

        j0nix.software.systemPackages = cfg.software;
      })

      (lib.mkIf (cfg.enable && cfg.discovery.enable) {
        services.avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };
      })
    ];
}
