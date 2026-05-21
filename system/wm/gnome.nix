{ pkgs, lib, settings, ... }:
let
  useGdm = (settings.displayManager or "sddm") == "gdm";
in {
  imports = [
    ./common/wayland.nix
  ];

  services.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.enable = lib.mkIf useGdm true;
  programs.dconf.enable = true;

  services.udev.packages = with pkgs; [
    gnome-settings-daemon
  ];

  j0nix.software.systemPackages = [
    pkgs.gnome-control-center
  ];
}
