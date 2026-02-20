{ lib, pkgs, settings, ... }:
let
  cfg = (settings.drivers or { }).amdgpu or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  services.xserver.videoDrivers = lib.mkDefault [ "amdgpu" ];
  systemd.tmpfiles.rules = [
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];
}
