{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).davinciResolve or { };
  enabled = cfg.enable or true;

  # Resolve's FHS environment confuses GTK under Wayland.
  # Force X11 backends and portal file chooser.
  resolveFixed = pkgs.symlinkJoin {
    name = "davinci-resolve-studio-wrapped";
    paths = [ pkgs.davinci-resolve-studio ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/davinci-resolve-studio \
        --set QT_QPA_PLATFORM xcb \
        --set GDK_BACKEND x11 \
        --set GTK_USE_PORTAL 1
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resolveFixed ];
}
