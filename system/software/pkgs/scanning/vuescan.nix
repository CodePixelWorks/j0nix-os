{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  wrapGAppsHook3,
  gtk3,
  gdk-pixbuf,
  pango,
  cairo,
  glib,
  libX11,
  libpng,
  libxkbcommon,
  util-linux,
  systemd,
  zlib,
}:

stdenv.mkDerivation rec {
  pname = "vuescan";
  version = "9.8.52";

  src = fetchurl {
    url = "https://www.vuescan.com/files/vuex6498.tgz";
    hash = "sha256-up7Xx1GRS2+YT6q+rnaOMbKzVOUb9W1FV3BWoPW8jww=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    gtk3
    gdk-pixbuf
    pango
    cairo
    glib
    libpng
    libX11
    libxkbcommon
    util-linux
    systemd
    zlib
    stdenv.cc.cc.lib
  ];

  sourceRoot = ".";

  desktopItems = [
    (makeDesktopItem {
      name = "vuescan";
      desktopName = "VueScan";
      genericName = "Scanner Software";
      comment = "Scan documents and photos with VueScan";
      exec = "vuescan";
      icon = "vuescan";
      terminal = false;
      categories = [
        "Graphics"
        "Office"
        "Scanning"
      ];
      startupNotify = true;
    })
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/icons/hicolor/scalable/apps $out/lib/udev/rules.d
    install -Dm755 VueScan/vuescan $out/bin/vuescan
    install -Dm644 VueScan/vuescan.svg $out/share/icons/hicolor/scalable/apps/vuescan.svg
    install -Dm644 VueScan/vuescan.rul $out/lib/udev/rules.d/60-vuescan.rules

    runHook postInstall
  '';

  meta = with lib; {
    description = "Scanner software for Linux";
    homepage = "https://www.vuescan.com/";
    license = licenses.unfreeRedistributable;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = platforms.linux;
    mainProgram = "vuescan";
  };
}
