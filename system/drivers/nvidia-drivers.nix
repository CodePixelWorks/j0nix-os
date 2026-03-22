{ lib, config, pkgs, ... }:
let
  cfg = config.j0nix.desktop.drivers.nvidia;
  enabled = cfg.enable;
  packageChoice = cfg.package;
  nvidiaPackages = config.boot.kernelPackages.nvidiaPackages;
  selectedPackage =
    if packageChoice == "production" && (nvidiaPackages ? production) then nvidiaPackages.production
    else if packageChoice == "latest" && (nvidiaPackages ? latest) then nvidiaPackages.latest
    else if packageChoice == "beta" && (nvidiaPackages ? beta) then nvidiaPackages.beta
    else if packageChoice == "vulkan_beta" && (nvidiaPackages ? vulkan_beta) then nvidiaPackages.vulkan_beta
    else if (nvidiaPackages ? production) then nvidiaPackages.production else nvidiaPackages.latest;
  selectedFirmware = if selectedPackage ? firmware then selectedPackage.firmware else null;
in
lib.mkMerge [
  (lib.mkIf enabled {
    boot.initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.firmware = lib.optional (selectedFirmware != null) selectedFirmware;

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = cfg.open or false;
      gsp.enable = cfg.gsp or false;
      nvidiaPersistenced = cfg.persistenced;
      nvidiaSettings = true;
      package = selectedPackage;
    };

    hardware.graphics.extraPackages = lib.optionals (pkgs ? nvidia-vaapi-driver) [
      pkgs.nvidia-vaapi-driver
    ];

    services.lact.enable = cfg.lact.enable;
  })
  {
    assertions = [
      {
        assertion = builtins.elem packageChoice [ "production" "latest" "beta" "vulkan_beta" ];
        message = "j0nix.desktop.drivers.nvidia.package must be one of: production, latest, beta, vulkan_beta";
      }
      {
        assertion = cfg.expectedVersion == null || selectedPackage.version == cfg.expectedVersion;
        message = "j0nix.desktop.drivers.nvidia.expectedVersion does not match the selected NVIDIA package version";
      }
    ];
  }
]
