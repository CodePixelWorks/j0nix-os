{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
}:

let
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/truelockmc/streambert/main/public/sized/256x256.png";
    hash = "sha256-OGMPrFKFvpQIHRUYYV+hubNQwHnU2TLG9zi2pLE++iM=";
  };
in
appimageTools.wrapType2 rec {
  pname = "streambert";
  version = "2.4.0";

  src = fetchurl {
    url = "https://github.com/truelockmc/streambert/releases/download/2.4/Streambert-${version}.AppImage";
    hash = "sha256-/y4DZTE01RqV67bUzdeDXonVniKquh1afZSG/Im8piY=";
  };

  # No upstream .desktop in the AppImage; provide a minimal one manually.
  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat > $out/share/applications/streambert.desktop <<EOF
[Desktop Entry]
Name=Streambert
Exec=streambert
Type=Application
Terminal=false
Icon=streambert
Categories=AudioVideo;Video;Player;
Comment=Stream and download movies, TV series, and anime
EOF

    install -Dm644 ${icon} $out/share/icons/hicolor/256x256/apps/streambert.png
  '';

  meta = {
    description = "Cross-platform desktop app to stream and download movies, TV series, and anime";
    homepage = "https://github.com/truelockmc/streambert";
    license = lib.licenses.unfree; # No explicit license in repo
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "streambert";
  };
}
