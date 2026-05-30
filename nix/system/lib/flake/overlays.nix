{
  baseDir,
  inputs,
  nixpkgs,
}:
let
  vscodeOverlay = inputs.nix-vscode-extensions.overlays.default;

  localFixesOverlay = final: prev: {
    bottles-j0nix = final.callPackage (baseDir + "/nix/system/software/pkgs/windows/bottles-j0nix.nix") {
      bottles = prev.bottles;
    };
    autodesk-fusion-linux = final.callPackage (baseDir + "/integrations/autodesk-fusion-nixos/pkgs/autodesk-fusion-linux") { };
    j0nix-wallpapers = final.callPackage (baseDir + "/nix/system/software/pkgs/assets/j0nix-wallpapers.nix") { };
    gparted-j0nix = final.callPackage (baseDir + "/nix/system/software/pkgs/storage/gparted-j0nix.nix") {
      gparted = prev.gparted;
    };
    darkly-qt6 = final.kdePackages.callPackage (baseDir + "/nix/system/software/pkgs/qt/darkly-qt6.nix") { };
    hyprqt6engine = final.callPackage (baseDir + "/nix/system/software/pkgs/qt/hyprqt6engine.nix") { };
    mauiman4 = final.callPackage (baseDir + "/nix/system/software/pkgs/maui/mauiman4.nix") { };
    mauikit4 = final.callPackage (baseDir + "/nix/system/software/pkgs/maui/mauikit4.nix") { };
    naps2 = prev.naps2.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/lib/naps2/appsettings.xml \
          --replace-fail '<Theme mode="default">Default</Theme>' \
                         '<Theme mode="default">Dark</Theme>'
      '';
    });
    qmlgreet = final.callPackage (baseDir + "/nix/system/software/pkgs/greetd/qmlgreet.nix") { };
    bettersoundcloud = final.callPackage (baseDir + "/nix/system/software/pkgs/audio/better-soundcloud.nix") { };
    mcp-language-server-j0nix = final.callPackage (baseDir + "/nix/system/software/pkgs/dev/mcp-language-server.nix") {
      src = inputs.mcp-language-server-src;
    };
    openldap = prev.openldap.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
      dontCheck = true;
    });
    vagrant-with-libvirt = final.callPackage (baseDir + "/nix/system/software/pkgs/dev/vagrant-with-libvirt.nix") {
      nixpkgsSrc = nixpkgs.outPath;
    };
    streambert = final.callPackage (baseDir + "/nix/system/software/pkgs/streaming/streambert.nix") { };
    bambu-studio-appimage = final.callPackage (baseDir + "/nix/system/software/pkgs/printing/bambu-studio-appimage.nix") { };
    hyprland-minimizer-orteip = prev.rustPlatform.buildRustPackage {
      pname = "hyprland_minimizer";
      version = "unstable";
      src = inputs."hyprland-minimizer-orteip";
      cargoLock = {
        lockFile = "${inputs."hyprland-minimizer-orteip"}/Cargo.lock";
      };
      meta = with prev.lib; {
        description = "Hyprland minimizer implementation by 0rteip";
        homepage = "https://github.com/0rteip/hyprland_minimizer";
        license = licenses.mit;
        maintainers = [ ];
        mainProgram = "hyprland-minimizer";
        platforms = platforms.linux;
      };
    };
    lager = prev.lager.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [
        "-DBoost_NO_BOOST_CMAKE=ON"
        "-Dlager_BUILD_TESTS=OFF"
      ];
    });
    sunshine = final.callPackage (baseDir + "/nix/system/software/pkgs/streaming/sunshine.nix") {
      nixpkgsSrc = nixpkgs.outPath;
    };
  };
in
{
  inherit vscodeOverlay localFixesOverlay;
  default = [
    vscodeOverlay
    localFixesOverlay
  ];
}
