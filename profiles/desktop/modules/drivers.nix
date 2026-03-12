{ settings, ... }:
let
  drivers = settings.drivers or { };
  firmware = drivers.firmware or { };
in
{
  # Host-specific driver profile for the physical desktop.
  j0nix.desktop.drivers = {
    firmware.enableRedistributable = firmware.enableRedistributable or true;

    amdgpu.enable = false;

    intel.enable = false;

    nvidia = {
      enable = true;
      open = false;
      gsp = false;
      persistenced = false;
      package = "latest"; # "production" | "latest" | "beta"
    };

    nvidiaPrime = {
      enable = false;
      intelBusID = "PCI:1:0:0";
      nvidiaBusID = "PCI:0:2:0";
    };

    hardwareClockLocalTime.enable = false;
  };
}
