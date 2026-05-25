{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.j0nix.desktop.drivers.amdgpu.enable;
in
lib.mkIf enabled {
  boot.kernelModules = [ "amdgpu" ];

  services.xserver.videoDrivers = lib.mkDefault [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  systemd.tmpfiles.rules = [
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];
}
