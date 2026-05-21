{
  baseDir,
  inputs,
  nixpkgs,
}:
let
  vscodeOverlay = inputs.nix-vscode-extensions.overlays.default;

  localFixesOverlay = final: prev: {
    bottles-j0nix = final.callPackage (baseDir + "/system/software/pkgs/windows/bottles-j0nix.nix") {
      bottles = prev.bottles;
    };
    autodesk-fusion-linux = final.callPackage (baseDir + "/integrations/autodesk-fusion-nixos/pkgs/autodesk-fusion-linux") { };
    j0nix-wallpapers = final.callPackage (baseDir + "/system/software/pkgs/assets/j0nix-wallpapers.nix") { };
    gparted-j0nix = final.callPackage (baseDir + "/system/software/pkgs/storage/gparted-j0nix.nix") {
      gparted = prev.gparted;
    };
    darkly-qt6 = final.kdePackages.callPackage (baseDir + "/system/software/pkgs/qt/darkly-qt6.nix") { };
    hyprqt6engine = final.callPackage (baseDir + "/system/software/pkgs/qt/hyprqt6engine.nix") { };
    mauiman4 = final.callPackage (baseDir + "/system/software/pkgs/maui/mauiman4.nix") { };
    mauikit4 = final.callPackage (baseDir + "/system/software/pkgs/maui/mauikit4.nix") { };
    naps2 = prev.naps2.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        substituteInPlace $out/lib/naps2/appsettings.xml \
          --replace-fail '<Theme mode="default">Default</Theme>' \
                         '<Theme mode="default">Dark</Theme>'
      '';
    });
    qmlgreet = final.callPackage (baseDir + "/system/software/pkgs/greetd/qmlgreet.nix") { };
    bettersoundcloud = final.callPackage (baseDir + "/system/software/pkgs/audio/better-soundcloud.nix") { };
    mcp-language-server-j0nix = final.callPackage (baseDir + "/system/software/pkgs/dev/mcp-language-server.nix") {
      src = inputs.mcp-language-server-src;
    };
    openldap = prev.openldap.overrideAttrs (_: {
      doCheck = false;
      doInstallCheck = false;
      dontCheck = true;
    });
    vagrant-with-libvirt = final.callPackage (baseDir + "/system/software/pkgs/dev/vagrant-with-libvirt.nix") {
      nixpkgsSrc = nixpkgs.outPath;
    };
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
    sunshine = prev.sunshine.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ prev.boost.out ];
      postPatch = (old.postPatch or "") + ''
        substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
          --replace-fail $'        system\n' ""
        substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
          --replace-fail 'find_package(Boost CONFIG ''${BOOST_VERSION} EXACT COMPONENTS ''${BOOST_COMPONENTS})' \
                         $'set(Boost_NO_BOOST_CMAKE ON)\nfind_package(Boost 1.56 REQUIRED COMPONENTS ''${BOOST_COMPONENTS})'
        substituteInPlace third-party/Simple-Web-Server/CMakeLists.txt \
          --replace-fail 'find_package(Boost 1.53.0 COMPONENTS system REQUIRED)' \
                         'find_package(Boost 1.53.0 REQUIRED)' \
          --replace-fail 'target_link_libraries(simple-web-server INTERFACE Boost::boost Boost::system)' \
                         'target_link_libraries(simple-web-server INTERFACE Boost::boost)'
        substituteInPlace cmake/compile_definitions/linux.cmake \
          --replace-fail 'add_compile_definitions(SUNSHINE_PLATFORM="linux")' \
                         $'add_compile_definitions(SUNSHINE_PLATFORM="linux")\nadd_compile_definitions(BOOST_LOG_DYN_LINK BOOST_LOG_SETUP_DYN_LINK)'
        substituteInPlace cmake/compile_definitions/common.cmake \
          --replace-fail '        ''${Boost_LIBRARIES}' $'        ''${Boost_LIBRARIES}\n        ${prev.boost.out}/lib/libboost_log_setup.so\n        ${prev.boost.out}/lib/libboost_thread.so\n        ${prev.boost.out}/lib/libboost_chrono.so\n        ${prev.boost.out}/lib/libboost_atomic.so\n        ${prev.boost.out}/lib/libboost_regex.so\n        ${prev.boost.out}/lib/libboost_date_time.so'
        substituteInPlace cmake/compile_definitions/common.cmake \
          --replace-fail '        ${prev.boost.out}/lib/libboost_log_setup.so' \
                         $'        ${prev.boost.out}/lib/libboost_log.so\n        ${prev.boost.out}/lib/libboost_log_setup.so'
        substituteInPlace cmake/targets/common.cmake \
          --replace-fail 'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})' \
                         $'target_link_libraries(sunshine ''${SUNSHINE_EXTERNAL_LIBRARIES} ''${EXTRA_LIBS})\ntarget_link_libraries(sunshine ${prev.boost.out}/lib/libboost_log.so ${prev.boost.out}/lib/libboost_log_setup.so ${prev.boost.out}/lib/libboost_thread.so ${prev.boost.out}/lib/libboost_chrono.so ${prev.boost.out}/lib/libboost_atomic.so ${prev.boost.out}/lib/libboost_regex.so ${prev.boost.out}/lib/libboost_date_time.so)'
      '';
    });
  };
in
{
  inherit vscodeOverlay localFixesOverlay;
  default = [
    vscodeOverlay
    localFixesOverlay
  ];
}
