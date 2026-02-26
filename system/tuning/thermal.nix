{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.thermal;
  enabled = cfg.enable;
  fanModule = cfg.fan.module;
  acpiLax = cfg.fan.acpiEnforceResourcesLax;
  governor = cfg.cpuGovernor;
in
{
  options.j0nix.desktop.thermal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    cpuGovernor = lib.mkOption {
      type = lib.types.str;
      default = "schedutil";
    };
    fan = {
      module = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "nct6775";
      };
      acpiEnforceResourcesLax = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  config = lib.mkIf enabled {
    boot.kernelModules = lib.optional (fanModule != null && fanModule != "") fanModule;
    boot.kernelParams = lib.optionals acpiLax [ "acpi_enforce_resources=lax" ];

    powerManagement.cpuFreqGovernor = governor;

    environment.systemPackages = with pkgs; [
      lm_sensors
    ];

    assertions = [
      {
        assertion = builtins.elem governor [ "performance" "powersave" "ondemand" "conservative" "schedutil" ];
        message = "j0nix.desktop.thermal.cpuGovernor must be one of: performance, powersave, ondemand, conservative, schedutil";
      }
    ];
  };
}
