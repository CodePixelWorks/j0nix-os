{ ... }:
{
  j0nix.desktop.thermal = {
    enable = true;
    cpuGovernor = "schedutil";
    fan = {
      # Separate kernel module name and hwmon device name (they are not always identical).
      kernelModule = "it87";
      hwmonName = "it8718";
      # Needed on many boards so hwmon PWM interfaces become writable.
      acpiEnforceResourcesLax = true;
      # During gamemode performance sessions, force writable PWM channels to max and restore afterwards.
      maxOnGamingPerformanceMode = true;
    };
  };
}
