{ lib, pkgs, settings, ... }:
let
  cfg = settings.thermal or { };
  enabled = cfg.enable or true;
  fan = cfg.fan or { };
  fanModule = fan.module or "nct6775";
  acpiLax = fan.acpiEnforceResourcesLax or true;
  governor = cfg.cpuGovernor or "schedutil";
in
lib.mkIf enabled {
  boot.kernelModules = lib.optional (fanModule != null && fanModule != "") fanModule;
  boot.kernelParams = lib.optionals acpiLax [ "acpi_enforce_resources=lax" ];

  powerManagement.cpuFreqGovernor = governor;

  environment.systemPackages = with pkgs; [
    lm_sensors
  ];

  assertions = [
    {
      assertion = builtins.elem governor [ "performance" "powersave" "ondemand" "conservative" "schedutil" ];
      message = "settings.thermal.cpuGovernor must be one of: performance, powersave, ondemand, conservative, schedutil";
    }
  ];
}
