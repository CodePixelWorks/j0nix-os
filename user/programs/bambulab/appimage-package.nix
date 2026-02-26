{ pkgs }:
pkgs.appimageTools.wrapType2 rec {
  name = "BambuStudio";
  pname = "bambu-studio";
  version = "02.05.00.67";
  ubuntu_version = "24.04_PR-9540";

  src = pkgs.fetchurl {
    url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_ubuntu-${ubuntu_version}.AppImage";
    sha256 = "sha256:dee6d96e5aec389cf3d69df84228b089a80a681ee723cc4379a74558706459f8";
  };

  profile = ''
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules/"
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
