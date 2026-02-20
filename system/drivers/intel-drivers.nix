{ lib, pkgs, settings, ... }:
let
  cfg = (settings.drivers or { }).intel or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vaapiIntel
    vaapiVdpau
    libvdpau-va-gl
  ];
}
