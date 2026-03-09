{ lib, pkgs, ... }:
let
  desktopBasics = lib.filter (pkg: pkg != null) [
    (pkgs.gnome-text-editor or null)
    (pkgs.file-roller or null)
    (pkgs.evince or null)
    (pkgs.loupe or null)
    (pkgs.gnome-calculator or null)
    (pkgs.pavucontrol or null)
  ];
in
{
  # General day-to-day desktop tools that should not depend on a specific WM
  # shell or on GNOME being the active desktop session.
  j0nix.user.software.packages = desktopBasics;
}
