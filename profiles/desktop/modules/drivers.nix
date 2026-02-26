{ ... }:
{
  # Host-specific driver profile for the physical desktop.
  j0nix.desktop.drivers = {
    amdgpu.enable = false;

    intel.enable = false;

    nvidia = {
      enable = true;
      open = false;
      package = "production"; # "production" | "latest" | "beta"
    };

    nvidiaPrime = {
      enable = false;
      intelBusID = "PCI:1:0:0";
      nvidiaBusID = "PCI:0:2:0";
    };

    hardwareClockLocalTime.enable = false;
  };
}
