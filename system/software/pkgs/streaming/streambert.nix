{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
}:

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
Categories=AudioVideo;Video;Player;
Comment=Stream and download movies, TV series, and anime
EOF
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
