{ settings, ... }:
let
  drivers = settings.drivers or { };
  firmware = drivers.firmware or { };
  nvidia = drivers.nvidia or { };
  nvidiaLact = nvidia.lact or { };
in
{
  # Host-specific driver profile for the physical desktop.
  j0nix.desktop.drivers = {
    firmware.enableRedistributable = firmware.enableRedistributable or true;

    amdgpu.enable = false;

    intel.enable = false;

    nvidia = {
      enable = nvidia.enable or true;
      open = nvidia.open or false;
      gsp = nvidia.gsp or false;
      persistenced = nvidia.persistenced or false;
      package = nvidia.package or "latest"; # "production" | "latest" | "beta" | "vulkan_beta"
      expectedVersion = nvidia.expectedVersion or null;
      lact.enable = nvidiaLact.enable or false;
    };

    nvidiaPrime = {
      enable = false;
      intelBusID = "PCI:1:0:0";
      nvidiaBusID = "PCI:0:2:0";
    };

    hardwareClockLocalTime.enable = false;
  };
}
