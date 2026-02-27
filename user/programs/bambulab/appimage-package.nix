{ pkgs }:
pkgs.appimageTools.wrapType2 rec {
  name = "BambuStudio";
  pname = "bambu-studio";
  version = "02.05.00.67";
  ubuntu_version = "24.04_PR-8834";

  src = pkgs.fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_ubuntu-${ubuntu_version}.AppImage";
    sha256 = "sha256:26bc07dccb04df2e462b1e03a3766509201c46e27312a15844f6f5d7fdf1debd";
  };

  profile = ''
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
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
