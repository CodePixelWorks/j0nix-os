{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.drivers;
  intelEnabled = cfg.intel.enable;
  nvidiaEnabled = cfg.nvidia.enable;
  nvidiaPrimeEnabled = cfg.nvidiaPrime.enable;
  vmGuestServicesEnabled = config.j0nix.desktop.virtualisation.vmGuestServices.enable;
in {
  options.j0nix.desktop.drivers = {
    amdgpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
    intel.enable = lib.mkOption { type = lib.types.bool; default = false; };
    nvidia = {
      enable = lib.mkOption { type = lib.types.bool; default = false; };
      open = lib.mkOption { type = lib.types.bool; default = false; };
      package = lib.mkOption {
        type = lib.types.enum [ "production" "latest" "beta" ];
        default = "production";
      };
    };
    nvidiaPrime = {
      enable = lib.mkOption { type = lib.types.bool; default = false; };
      intelBusID = lib.mkOption { type = lib.types.str; default = "PCI:1:0:0"; };
      nvidiaBusID = lib.mkOption { type = lib.types.str; default = "PCI:0:2:0"; };
    };
    hardwareClockLocalTime.enable = lib.mkOption { type = lib.types.bool; default = false; };
  };

  imports = [
    ./amd-drivers.nix
    ./intel-drivers.nix
    ./nvidia-drivers.nix
    ./nvidia-prime-drivers.nix
    ./local-hardware-clock.nix
  ];

  config.assertions = [
    {
      assertion = !(nvidiaPrimeEnabled && !nvidiaEnabled);
      message = "j0nix.desktop.drivers.nvidiaPrime.enable requires j0nix.desktop.drivers.nvidia.enable = true";
    }
    {
      assertion = !(nvidiaPrimeEnabled && !intelEnabled);
      message = "j0nix.desktop.drivers.nvidiaPrime.enable requires j0nix.desktop.drivers.intel.enable = true";
    }
    {
      assertion = !(nvidiaEnabled && vmGuestServicesEnabled);
      message = "j0nix.desktop.drivers.nvidia.enable should not be combined with j0nix.desktop.virtualisation.vmGuestServices.enable for bare-metal NVIDIA setups";
    }
  ];
}
