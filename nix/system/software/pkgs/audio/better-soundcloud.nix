{
  buildNpmPackage,
  fetchFromGitHub,
  stdenv,
  electron,
  makeDesktopItem,
  copyDesktopItems,
  makeWrapper,
  lib,
}:
buildNpmPackage rec {
  pname = "bettersoundcloud";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "AlirezaKJ";
    repo = "BetterSoundCloud";
    rev = "V${version}";
    hash = "sha256-DF3DFbVR5osAAczCd46EDvZspmJGWs3cc37bPymYQwQ=";
  };

  npmDepsHash = "sha256-oR2bMtRZ2qP63ElT/xcUvAln1GR7RK4IIRKKh+RIJj0=";
  dontNpmBuild = true;

  # electron-forge tries to download electron binary during build; we provide it.
  ELECTRON_SKIP_BINARY_DOWNLOAD = 1;

  nativeBuildInputs = [
    electron
    makeWrapper
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "bettersoundcloud";
      desktopName = "BetterSoundCloud";
      genericName = "SoundCloud Client";
      comment = "SoundCloud desktop client with themes and adblocker";
      exec = "bettersoundcloud %U";
      icon = "bettersoundcloud";
      categories = [
        "Audio"
        "Music"
        "AudioVideo"
      ];
    })
  ];

  postInstall = ''
    # Install icon
    install -Dm644 app/lib/assets/icon.png $out/share/icons/hicolor/256x256/apps/bettersoundcloud.png 2>/dev/null || \
    install -Dm644 app/lib/assets/icon.ico $out/share/icons/hicolor/256x256/apps/bettersoundcloud.png 2>/dev/null || true

    makeWrapper ${lib.getExe electron} $out/bin/${pname} \
      --add-flags $out/lib/node_modules/${pname}/main.js \
      --set ELECTRON_FORCE_WINDOW_MENU_BAR 0
  '';

  meta = with lib; {
    description = "SoundCloud desktop client with themes and adblocker";
    homepage = "https://github.com/AlirezaKJ/BetterSoundCloud";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = pname;
  };
}
