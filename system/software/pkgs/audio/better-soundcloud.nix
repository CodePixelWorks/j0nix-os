{
  fetchFromGitHub,
  buildNpmPackage,
  electron,
  makeDesktopItem,
  copyDesktopItems,
  makeWrapper,
  lib,
}:

buildNpmPackage rec {
  pname = "bettersoundcloud";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "AlirezaKJ";
    repo = "BetterSoundCloud";
    rev = "V${version}";
    hash = "sha256-tFJgpAsqh4N2wTyrXGjIzJYxMDfjDpq5ncl3aqlltG8=";
  };

  npmDepsHash = "sha256-Gemcva/Yq7/a4q2DP2PQOurNg6mEqhr0c3EWcubNuLQ=";

  forceGitDeps = true;

  # electron-forge tries to download electron binary during build; we provide it.
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

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

  # Skip the default npm build step — we just need node_modules.
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/bettersoundcloud
    cp -r . $out/share/bettersoundcloud

    # Install icon
    install -Dm644 app/lib/assets/icon.png $out/share/icons/hicolor/256x256/apps/bettersoundcloud.png 2>/dev/null || \
    install -Dm644 app/lib/assets/icon.ico $out/share/icons/hicolor/256x256/apps/bettersoundcloud.png 2>/dev/null || true

    # Create wrapper
    mkdir -p $out/bin
    makeWrapper ${electron}/bin/electron $out/bin/bettersoundcloud \
      --add-flags $out/share/bettersoundcloud \
      --set ELECTRON_FORCE_WINDOW_MENU_BAR 0

    runHook postInstall
  '';

  meta = with lib; {
    description = "SoundCloud desktop client with themes and adblocker";
    homepage = "https://github.com/AlirezaKJ/BetterSoundCloud";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
