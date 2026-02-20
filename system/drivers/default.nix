{ lib, settings, ... }:
let
  drivers = settings.drivers or { };
  intelEnabled = ((drivers.intel or { }).enable or false);
  nvidiaEnabled = ((drivers.nvidia or { }).enable or false);
  nvidiaPrimeEnabled = ((drivers.nvidiaPrime or { }).enable or false);
  vmGuestServicesEnabled = ((drivers.vmGuestServices or { }).enable or false);
in {
  imports = [
    ./amd-drivers.nix
    ./intel-drivers.nix
    ./nvidia-drivers.nix
    ./nvidia-prime-drivers.nix
    ./local-hardware-clock.nix
    ./vm-guest-services.nix
  ];

  assertions = [
    {
      assertion = !(nvidiaPrimeEnabled && !nvidiaEnabled);
      message = "settings.drivers.nvidiaPrime.enable requires settings.drivers.nvidia.enable = true";
    }
    {
      assertion = !(nvidiaPrimeEnabled && !intelEnabled);
      message = "settings.drivers.nvidiaPrime.enable requires settings.drivers.intel.enable = true";
    }
    {
      assertion = !(nvidiaEnabled && vmGuestServicesEnabled);
      message = "settings.drivers.nvidia.enable should not be combined with settings.drivers.vmGuestServices.enable for bare-metal NVIDIA setups";
    }
  ];
}
