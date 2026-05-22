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
    hash = "sha256-09m6pj4zr1llgmd1vfma4agdb2ayhgbwvm5nxfaimm9l65jh6bpz";
  };

  extraInstallCommands = ''
    install -Dm644 $out/share/applications/streambert.desktop \
      $out/share/applications/streambert.desktop

    substituteInPlace $out/share/applications/streambert.desktop \
      --replace-fail "Exec=AppRun" "Exec=streambert"
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
