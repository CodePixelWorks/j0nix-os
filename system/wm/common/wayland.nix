{ pkgs, lib, settings, ... }:
{
  j0nix.software.systemPackages = [
    pkgs.wayland
    pkgs.wayland-utils
    pkgs.wl-clipboard
    pkgs.libxcb
    pkgs.libxkbcommon
    pkgs.libnotify
  ];

  services.xserver = {
    enable = true;
    desktopManager.xterm.enable = false;
    xkb = {
      variant = "";
      layout = settings.keyboardLayout or "de";
      options = settings.keyboardOptions or "caps:escape";
    };
    displayManager.startx.enable = lib.mkDefault false;
  };
}
