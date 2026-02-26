{ config, lib, pkgs, ... }:
let
  enabled = config.j0nix.desktop.drivers.amdgpu.enable;
in
lib.mkIf enabled {
  services.xserver.videoDrivers = lib.mkDefault [ "amdgpu" ];
  systemd.tmpfiles.rules = [
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];
}
