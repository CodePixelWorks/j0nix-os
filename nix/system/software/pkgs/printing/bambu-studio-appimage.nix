{
  pkgs,
}:
pkgs.appimageTools.wrapType2 rec {
  name = "BambuStudio";
  pname = "bambu-studio";
  version = "02.08.01.55";
  ubuntu_version = "24.04-v02.08.01.55-20260715113557";

  src = pkgs.fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/BambuStudio_ubuntu${ubuntu_version}.AppImage";
    hash = "sha256-IlECQz2/zEdcvXm++gRTu5P5880Vu0OEgECn/iIRx94=";
  };

  profile = ''
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export QT_QPA_PLATFORM="''${QT_QPA_PLATFORM:-xcb}"
    export GDK_BACKEND="''${GDK_BACKEND:-x11}"
    export WEBKIT_DISABLE_DMABUF_RENDERER="''${WEBKIT_DISABLE_DMABUF_RENDERER:-1}"
    # Use the native host OpenGL driver. Forcing zink routes the 3D workspace
    # through OpenGL-on-Vulkan and can crash during STL import/viewport setup.
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
