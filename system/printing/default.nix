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

    sane = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SANE scanner support when printing is enabled.";
      };

      extraBackends = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional SANE backend packages (for example hplipWithPlugin).";
      };
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

        j0nix.software.systemPackages = cfg.software;
      })

      (lib.mkIf (cfg.enable && cfg.sane.enable) {
        hardware.sane = {
          enable = true;
          extraBackends = cfg.sane.extraBackends;
        };
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
