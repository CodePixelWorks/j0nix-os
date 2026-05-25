{ pkgs, lib, settings, ... }:
let
  resolveEnabledWms = import ../lib/enabled-wms.nix { inherit lib; };
  gnomeEnabled = builtins.elem "gnome" (resolveEnabledWms settings);
  useGdm = (settings.displayManager or "sddm") == "gdm";
in
{
  imports = [
    ./common/wayland.nix
  ];

  config = lib.mkIf gnomeEnabled {
    services.desktopManager.gnome.enable = true;
    services.xserver.displayManager.gdm.enable = lib.mkIf useGdm true;
    programs.dconf.enable = true;

    services.udev.packages = with pkgs; [
      gnome-settings-daemon
    ];

    j0nix.software.systemPackages = [
      pkgs.gnome-control-center
    ];
  };
}
