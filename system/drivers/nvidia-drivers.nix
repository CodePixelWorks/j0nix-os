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
    else if (nvidiaPackages ? production) then nvidiaPackages.production else nvidiaPackages.latest;
in
lib.mkMerge [
  (lib.mkIf enabled {
    services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = cfg.open or false;
      nvidiaSettings = true;
      package = selectedPackage;
    };

    hardware.graphics.extraPackages = lib.optionals (pkgs ? nvidia-vaapi-driver) [
      pkgs.nvidia-vaapi-driver
    ];
  })
  {
    assertions = [
      {
        assertion = builtins.elem packageChoice [ "production" "latest" "beta" ];
        message = "j0nix.desktop.drivers.nvidia.package must be one of: production, latest, beta";
      }
    ];
  }
]
