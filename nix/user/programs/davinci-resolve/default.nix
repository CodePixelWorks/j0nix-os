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
  # fails to open because GTK auto-detects Wayland and gets confused inside
  # the FHS bubble where portals and Wayland sockets are not fully wired.
  # Forcing explicit X11 backends and the xdg-desktop-portal file chooser
  # fixes the dialog reliably.
  #
  # RLM_LICENSE points to the fake blackmagic.lic (resolvepatch approach).
  # bwrap inherits env vars (no --clearenv) and /nix is always mounted,
  # so the store path works inside the FHS sandbox.
  resolvePkg = pkgs.davinci-resolve-studio;

  blackmagicLic = pkgs.writeText "blackmagic.lic" ''
    LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted
      hostid=ANY issuer=ANY customer=ANY issued=14-Aug-2025
      akey=0000-0000-0000-0000-0000 _ck=00 sig="00"
  '';

  resolveFixed = pkgs.symlinkJoin {
    name = "davinci-resolve-studio-wrapped";
    paths = [ resolvePkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/davinci-resolve-studio \
        --set QT_QPA_PLATFORM xcb \
        --set GDK_BACKEND x11 \
        --set GTK_USE_PORTAL 1 \
        --set RLM_LICENSE "${blackmagicLic}"
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resolveFixed ];
}
