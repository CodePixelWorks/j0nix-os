{ config, lib, pkgs, ... }:
let
  enabled = config.j0nix.desktop.drivers.intel.enable;
in
lib.mkIf enabled {
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vaapiIntel
    vaapiVdpau
    libvdpau-va-gl
  ];
}
