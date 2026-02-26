{ ... }:
{
  j0nix.desktop.thermal = {
    enable = true;
    cpuGovernor = "schedutil";
    fan = {
      # Gigabyte/desktop Super-I/O chips are typically exposed through nct6775.
      module = "nct6775";
      # Needed on many boards so hwmon PWM interfaces become writable.
      acpiEnforceResourcesLax = true;
      # During gamemode performance sessions, force writable PWM channels to max and restore afterwards.
      maxOnGamingPerformanceMode = true;
    };
  };
}
