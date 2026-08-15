{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).davinciResolve or { };
  enabled = cfg.enable or true;
  studio = cfg.studio or true;

  resolvePkg =
    if studio then pkgs.davinci-resolve-studio else pkgs.davinci-resolve;
  binName = if studio then "davinci-resolve-studio" else "davinci-resolve";

  # Resolve ships as a buildFHSEnv bundle with its own Qt/GTK libraries.
  # Under Wayland/XWayland the GTK open-file dialog frequently crashes or
  # fails to open because GTK auto-detects Wayland and gets confused inside
  # the FHS bubble where portals and Wayland sockets are not fully wired.
  # Forcing explicit X11 backends and the xdg-desktop-portal file chooser
  # fixes the dialog reliably.
  #
  # For Studio: RLM_LICENSE points to the fake blackmagic.lic placed by the
  # patched derivation (resolvepatch approach).  bwrap inherits env vars
  # (no --clearenv) and /nix is always mounted, so the store path works
  # inside the FHS sandbox.
  rlmFlag = lib.optionalString studio
    "--set RLM_LICENSE ${resolvePkg.passthru.resolvepatched}/.license/blackmagic.lic";

  resolveFixed = pkgs.symlinkJoin {
    name = "davinci-resolve${lib.optionalString studio "-studio"}-wrapped";
    paths = [ resolvePkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${binName} \
        --set QT_QPA_PLATFORM xcb \
        --set GDK_BACKEND x11 \
        --set GTK_USE_PORTAL 1 \
        ${rlmFlag}
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resolveFixed ];
}
