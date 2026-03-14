{ lib, pkgs, ... }:
let
  desktopBasics = lib.filter (pkg: pkg != null) [
    (pkgs.gnome-text-editor or null)
    (pkgs.file-roller or null)
    (if (pkgs ? kdePackages) && (pkgs.kdePackages ? okular) then pkgs.kdePackages.okular else pkgs.okular or null)
    (pkgs.loupe or null)
    (pkgs.gnome-calculator or null)
    (pkgs.gparted-j0nix or pkgs.gparted or null)
    (pkgs.pavucontrol or null)
  ];
in
{
  # General day-to-day desktop tools that should not depend on a specific WM
  # shell or on GNOME being the active desktop session.
  j0nix.user.software.packages = desktopBasics;
}
