{
  fetchFromGitHub,
  importNpmLock,
  runCommand,
  stdenv,
  nodejs,
  jq,
  electron,
  makeDesktopItem,
  copyDesktopItems,
  makeWrapper,
  lib,
}:

let
  electronStub = runCommand "bettersoundcloud-electron-stub" { } ''
    mkdir -p $out
    cat > $out/package.json <<'EOF'
    {"name":"electron","version":"41.1.1"}
    EOF
  '';
in
stdenv.mkDerivation rec {
  pname = "bettersoundcloud";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "AlirezaKJ";
    repo = "BetterSoundCloud";
    rev = "V${version}";
    hash = "sha256-DF3DFbVR5osAAczCd46EDvZspmJGWs3cc37bPymYQwQ=";
  };

  npmDeps = importNpmLock { npmRoot = src; };

  # electron-forge tries to download electron binary during build; we provide it.
  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
  env.npm_config_nodedir = "${nodejs}";

  nativeBuildInputs = [
    nodejs
    jq
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

  configurePhase = ''
    runHook preConfigure

    export HOME="$TMPDIR"
    npm config set offline true
    npm config set progress false
    npm config set fund false

    cp --no-preserve=mode ${npmDeps}/package.json package.json
    cp --no-preserve=mode ${npmDeps}/package-lock.json package-lock.json

    tmp_package_json="$TMPDIR/package.json"
    jq '
      del(.devDependencies)
      | .dependencies.electron = $electronStub
    ' --arg electronStub "file:${electronStub}" package.json > "$tmp_package_json"
    mv "$tmp_package_json" package.json

    tmp_lockfile="$TMPDIR/package-lock.json"
    jq '
      del(.packages[""].devDependencies)
      | del(.dependencies["@electron-forge/cli"])
      | del(.dependencies["@electron-forge/maker-deb"])
      | del(.dependencies["@electron-forge/maker-rpm"])
      | del(.dependencies["@electron-forge/maker-squirrel"])
      | del(.dependencies["@electron-forge/maker-wix"])
      | del(.dependencies["@electron-forge/maker-zip"])
      | del(.dependencies["@electron-forge/plugin-auto-unpack-natives"])
      | del(.dependencies["@electron-forge/plugin-fuses"])
      | del(.dependencies["@electron/fuses"])
      | del(.dependencies.electron)
      | del(.dependencies["electron-wix-msi"])
      | del(.packages["node_modules/@electron-forge/cli"])
      | del(.packages["node_modules/@electron-forge/maker-deb"])
      | del(.packages["node_modules/@electron-forge/maker-rpm"])
      | del(.packages["node_modules/@electron-forge/maker-squirrel"])
      | del(.packages["node_modules/@electron-forge/maker-wix"])
      | del(.packages["node_modules/@electron-forge/maker-zip"])
      | del(.packages["node_modules/@electron-forge/plugin-auto-unpack-natives"])
      | del(.packages["node_modules/@electron-forge/plugin-fuses"])
      | del(.packages["node_modules/@electron/fuses"])
      | del(.packages["node_modules/electron"])
      | del(.packages["node_modules/electron-wix-msi"])
      | .dependencies.electron = {
          version: $electronStub,
          resolved: $electronStub
        }
      | .packages["node_modules/electron"] = {
          name: "electron",
          version: "41.1.1",
          resolved: $electronStub
        }
      | if .dependencies["@electron/node-gyp"] then
          .dependencies["@electron/node-gyp"] |= (
            .resolved = $nodeGypResolved
            | .version = $nodeGypResolved
            | del(.from)
          )
        else
          .
        end
      | if .dependencies["@electron/node-gyp"] then
          .dependencies["@electron/node-gyp"].resolved = $nodeGypResolved
        else
          .
        end
    ' --arg electronStub "file:${electronStub}" \
      --arg nodeGypResolved "$(jq -r '.packages["node_modules/@electron/node-gyp"].resolved' package-lock.json)" \
      package-lock.json > "$tmp_lockfile"
    mv "$tmp_lockfile" package-lock.json

    npm install --ignore-scripts --omit=dev
    patchShebangs node_modules

    runHook postConfigure
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    rm -f node_modules/electron
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
