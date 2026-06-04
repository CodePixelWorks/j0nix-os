{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).davinciResolve or { };
  enabled = cfg.enable or true;

  # Resolve ships as a buildFHSEnv bundle with its own Qt/GTK libraries.
  # Under Wayland/XWayland the GTK open-file dialog frequently crashes or
  # fails to open because GTK自动-detects Wayland and gets confused inside
  # the FHS bubble where portals and Wayland sockets are not fully wired.
  # Forcing explicit X11 backends and the xdg-desktop-portal file chooser
  # fixes the dialog reliably.
  resolveFixed = pkgs.symlinkJoin {
    name = "davinci-resolve";
    paths = [ pkgs.davinci-resolve ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/davinci-resolve \
        --set QT_QPA_PLATFORM xcb \
        --set GDK_BACKEND x11 \
        --set GTK_USE_PORTAL 1
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resolveFixed ];
}
