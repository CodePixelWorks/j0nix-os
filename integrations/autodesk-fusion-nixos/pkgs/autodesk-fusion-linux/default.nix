{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  curl,
  gnugrep,
  gnused,
  gawk,
  findutils,
  p7zip,
  cabextract,
  wineWow64Packages,
  winetricks,
  xdg-utils,
  desktop-file-utils,
  procps,
  util-linux,
  gnutar,
  gzip,
  iconv,
  mesa-demos ? null,
  pciutils ? null,
}:

let
  winePackage = wineWow64Packages.stagingFull or wineWow64Packages.staging;
  runtimeInputs = [
    bash
    coreutils
    curl
    gnugrep
    gnused
    gawk
    findutils
    p7zip
    cabextract
    winePackage
    winetricks
    xdg-utils
    desktop-file-utils
    procps
    util-linux
    gnutar
    gzip
    iconv
  ] ++ lib.optional (mesa-demos != null) mesa-demos
    ++ lib.optional (pciutils != null) pciutils;
in
stdenvNoCC.mkDerivation {
  pname = "autodesk-fusion-linux";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/autodesk-fusion" "$out/share/applications"
    cp scripts/* "$out/bin/"
    chmod +x "$out/bin/"*

    substituteInPlace "$out/bin/"* \
      --replace-warn "@runtimePath@" "${lib.makeBinPath runtimeInputs}" \
      --replace-warn "@wineBin@" "${winePackage}/bin/wine" \
      --replace-warn "@wineserverBin@" "${winePackage}/bin/wineserver" \
      --replace-warn "@winetricksBin@" "${winetricks}/bin/winetricks" \
      --replace-warn "@curlBin@" "${curl}/bin/curl" \
      --replace-warn "@sevenZipBin@" "${p7zip}/bin/7z"

    runHook postInstall
  '';

  passthru = {
    inherit winePackage runtimeInputs;
  };

  meta = with lib; {
    description = "NixOS-friendly runtime helpers for Autodesk Fusion on Linux";
    homepage = "https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "fusion360-launch";
    platforms = [ "x86_64-linux" ];
  };
}
