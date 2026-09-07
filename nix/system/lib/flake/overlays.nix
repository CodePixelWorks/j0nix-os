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
    gitea-mcp = final.callPackage (baseDir + "/nix/system/software/pkgs/dev/gitea-mcp.nix") { };
    donsetch = final.callPackage (baseDir + "/nix/system/software/pkgs/dev/donsetch.nix") { };
    nexus-collection-dl = final.callPackage (baseDir + "/nix/system/software/pkgs/gaming/nexus-collection-dl.nix") { };
    nms-patcher = final.callPackage (baseDir + "/nix/system/software/pkgs/gaming/nms-patcher.nix") { };
    nms-amumss = final.callPackage (baseDir + "/nix/system/software/pkgs/gaming/nms-amumss.nix") { };
    openldap = prev.openldap.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
      dontCheck = true;
    });
    udisks = prev.udisks.overrideAttrs (_: {
      # udisks 2.11.1 currently aborts one spawned-job unit test on this nixpkgs
      # revision, which blocks the system closure through gvfs/udiskie.
      doCheck = false;
    });
    vagrant-with-libvirt = final.callPackage (baseDir + "/nix/system/software/pkgs/dev/vagrant-with-libvirt.nix") {
      nixpkgsSrc = nixpkgs.outPath;
    };
    bambu-studio-appimage = final.callPackage (baseDir + "/nix/system/software/pkgs/printing/bambu-studio-appimage.nix") { };
    firecrawl-py = final.python312Packages.callPackage (baseDir + "/nix/pkgs/firecrawl-py") { };
    hermes-extra-python = final.callPackage (baseDir + "/nix/pkgs/hermes-extra-python") {
      inherit (final) firecrawl-py;
      inherit (final.python312Packages) qdrant-client;
    };
    hermes-agent-with-firecrawl =
      let
        system = final.stdenv.hostPlatform.system;
        hermesPkg =
          if (inputs ? hermes-agent)
             && (inputs.hermes-agent ? packages)
             && (inputs.hermes-agent.packages.${system} or null) != null
             && (inputs.hermes-agent.packages.${system} ? default)
          then inputs.hermes-agent.packages.${system}.default
          else null;
      in
      if hermesPkg != null then
        final.callPackage (baseDir + "/nix/pkgs/hermes-agent-ext") {
          hermesPackage = hermesPkg;
          hermesExtraPython = final.hermes-extra-python;
        }
      else
        null;
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
    # Pinned Sunshine release (newer than this nixpkgs snapshot), based on the
    # nixpkgs by-name expression, plus the boost-dynlink fixups this flake
    # already needed (upstream's FetchContent boost conflicts with ours).
    sunshine =
      let
        sunshineBase = final.callPackage (baseDir + "/nix/system/software/pkgs/gaming/sunshine-new.nix") { };
      in
      sunshineBase.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.boost.out ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace cmake/compile_definitions/linux.cmake \
            --replace-fail 'add_compile_definitions(SUNSHINE_PLATFORM="linux")' \
                           $'add_compile_definitions(SUNSHINE_PLATFORM="linux")\nadd_compile_definitions(BOOST_LOG_DYN_LINK BOOST_LOG_SETUP_DYN_LINK)'
          substituteInPlace cmake/compile_definitions/common.cmake \
            --replace-fail '        ''${Boost_LIBRARIES}' $'        ''${Boost_LIBRARIES}\n        ${final.boost.out}/lib/libboost_log_setup.so\n        ${final.boost.out}/lib/libboost_thread.so\n        ${final.boost.out}/lib/libboost_chrono.so\n        ${final.boost.out}/lib/libboost_atomic.so\n        ${final.boost.out}/lib/libboost_regex.so\n        ${final.boost.out}/lib/libboost_date_time.so'
          substituteInPlace cmake/compile_definitions/common.cmake \
            --replace-fail '        ${final.boost.out}/lib/libboost_log_setup.so' \
                           $'        ${final.boost.out}/lib/libboost_log.so\n        ${final.boost.out}/lib/libboost_log_setup.so'
          substituteInPlace cmake/targets/common.cmake \
            --replace-fail 'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})' \
                           $'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})\ntarget_link_libraries(sunshine ${final.boost.out}/lib/libboost_log.so ${final.boost.out}/lib/libboost_log_setup.so ${final.boost.out}/lib/libboost_thread.so ${final.boost.out}/lib/libboost_chrono.so ${final.boost.out}/lib/libboost_atomic.so ${final.boost.out}/lib/libboost_regex.so ${final.boost.out}/lib/libboost_date_time.so)'
        '';
      });
  };
  resolveOverlay =
    if (inputs ? resolve-patch) then
      final: prev: {
        davinci-resolve-studio = final.callPackage (inputs.resolve-patch + "/package.nix") {
          davinci-resolve-studio = prev.davinci-resolve-studio;
        };
      }
    else
      final: prev: { };
in
{
  inherit vscodeOverlay localFixesOverlay resolveOverlay;

  default = [
    vscodeOverlay
    localFixesOverlay
    resolveOverlay
  ];
}
