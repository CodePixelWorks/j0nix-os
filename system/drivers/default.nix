{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.drivers;
  intelEnabled = cfg.intel.enable;
  nvidiaEnabled = cfg.nvidia.enable;
  nvidiaPrimeEnabled = cfg.nvidiaPrime.enable;
  vmGuestServicesEnabled = config.j0nix.desktop.virtualisation.vmGuestServices.enable;
in {
  options.j0nix.desktop.drivers = {
    firmware = {
      enableRedistributable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable redistributable firmware for devices that require it (e.g. Wi-Fi).";
      };
    };

    amdgpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
    intel.enable = lib.mkOption { type = lib.types.bool; default = false; };
    nvidia = {
      enable = lib.mkOption { type = lib.types.bool; default = false; };
      open = lib.mkOption { type = lib.types.bool; default = false; };
      gsp = lib.mkOption { type = lib.types.bool; default = false; };
      persistenced = lib.mkOption { type = lib.types.bool; default = true; };
      powerManagement = {
        enable = lib.mkOption { type = lib.types.bool; default = false; };
        finegrained = lib.mkOption { type = lib.types.bool; default = false; };
      };
      package = lib.mkOption {
        type = lib.types.enum [ "production" "latest" "beta" "vulkan_beta" ];
        default = "production";
      };
      expectedVersion = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      lact.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
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

  config.hardware.enableRedistributableFirmware = cfg.firmware.enableRedistributable;
}
