{ pkgs }:
pkgs.appimageTools.wrapType2 rec {
  name = "BambuStudio";
  pname = "bambu-studio";
  version = "02.05.02.51";
  ubuntu_version = "24.04_v02.05.02.51-20260327222803";

  src = pkgs.fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/BambuStudio_ubuntu-24.04_${ubuntu_version}.AppImage";
    sha256 = "sha256:0i1p47w2b3vq78zjg9rs10rd19hram364a6irrhmww9p8grmlrxm";
  };

  profile = ''
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-xcb}"
    export GDK_BACKEND="''${GDK_BACKEND:-x11}"
    export WEBKIT_DISABLE_DMABUF_RENDERER="''${WEBKIT_DISABLE_DMABUF_RENDERER:-1}"
    export MESA_LOADER_DRIVER_OVERRIDE="''${MESA_LOADER_DRIVER_OVERRIDE:-zink}"
    export GALLIUM_DRIVER="''${GALLIUM_DRIVER:-zink}"
    # Do not override GIO_MODULE_DIR: replacing it can hide default GLib modules.
    # Add glib-networking modules on top of defaults instead.
    export GIO_EXTRA_MODULES="${pkgs.glib-networking}/lib/gio/modules"
  '';

  extraPkgs =
    appPkgs: with appPkgs; [
      cacert
      glib
      glib-networking
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      webkitgtk_4_1
    ];

  # We provide a custom Home Manager desktop entry (`Exec=bambulab`, custom icon).
  # Drop upstream AppImage desktop files to avoid duplicate menu entries.
  extraInstallCommands = ''
    rm -f "$out"/share/applications/*.desktop
  '';
}
