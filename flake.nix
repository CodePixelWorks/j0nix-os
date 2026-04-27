{
  description = "j0nix-os (independent gaming/dev NixOS)";

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      baseDir = ./.;

      vscodeOverlay = inputs.nix-vscode-extensions.overlays.default;
      localFixesOverlay =
        final: prev:
        let
          snPkgs = (import inputs.staging-next { system = final.system; });
          snKde = snPkgs.kdePackages;
          snQt6 = snPkgs.qt6;
        in
        {
          bottles-j0nix = final.callPackage ./system/software/pkgs/windows/bottles-j0nix.nix {
            bottles = prev.bottles;
          };
          autodesk-fusion-linux = final.callPackage ./integrations/autodesk-fusion-nixos/pkgs/autodesk-fusion-linux { };
          j0nix-wallpapers = final.callPackage ./system/software/pkgs/assets/j0nix-wallpapers.nix { };
          gparted-j0nix = final.callPackage ./system/software/pkgs/storage/gparted-j0nix.nix {
            gparted = prev.gparted;
          };
          vuescan = final.callPackage ./system/software/pkgs/scanning/vuescan.nix { };

          darkly-qt6 = final.callPackage ./system/software/pkgs/qt/darkly-qt6.nix {
            inherit (snKde)
              kcmutils
              kcoreaddons
              kcolorscheme
              kconfig
              kguiaddons
              ki18n
              kiconthemes
              kwindowsystem
              kdecoration
              kirigami
              extra-cmake-modules
              ;
            inherit (snQt6)
              wrapQtAppsHook
              qtbase
              qtdeclarative
              ;
          };
          hyprqt6engine = final.callPackage ./system/software/pkgs/qt/hyprqt6engine.nix {
            kdePackages = snKde // {
              inherit (snKde) kcolorscheme kconfig kiconthemes;
            };
            qt6 = snQt6 // {
              inherit (snQt6)
                wrapQtAppsHook
                qttools
                qt5compat
                qtbase
                qtsvg
                qtwayland
                ;
            };
            libGL = prev.libGL;
            libxkbcommon = prev.libxkbcommon;
            hyprlang = prev.hyprlang;
            hyprutils = prev.hyprutils;
          };
          mauiman4 = final.callPackage ./system/software/pkgs/maui/mauiman4.nix {
            kdePackages = snKde // {
              inherit (snKde) extra-cmake-modules;
            };
            qt6 = snQt6 // {
              inherit (snQt6) wrapQtAppsHook qtbase;
            };
          };
          mauikit4 = final.callPackage ./system/software/pkgs/maui/mauikit4.nix {
            kdePackages = snKde // {
              inherit (snKde)
                extra-cmake-modules
                kcoreaddons
                ki18n
                knotifications
                kwindowsystem
                ;
            };
            qt6 = snQt6 // {
              inherit (snQt6)
                wrapQtAppsHook
                qtbase
                qtdeclarative
                qtmultimedia
                qtsvg
                ;
            };
            libxcb = prev.libxcb;
            xcbutilwm = prev.xcbutilwm;
          };

          qt6 = snQt6;
          kdePackages = snKde;
          naps2 = prev.naps2.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              substituteInPlace $out/lib/naps2/appsettings.xml \
                --replace-fail '<Theme mode="default">Default</Theme>' \
                               '<Theme mode="default">Dark</Theme>'
            '';
          });
          qmlgreet = final.callPackage ./system/software/pkgs/greetd/qmlgreet.nix { };
          bettersoundcloud = final.callPackage ./system/software/pkgs/audio/better-soundcloud.nix { };
          mcp-language-server-j0nix = final.callPackage ./system/software/pkgs/dev/mcp-language-server.nix {
            src = inputs.mcp-language-server-src;
          };
          vagrant-with-libvirt = final.callPackage ./system/software/pkgs/dev/vagrant-with-libvirt.nix {
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
      profileName = "desktop";
      profileDir = baseDir + "/profiles/${profileName}";
      profileDetails = import (profileDir + "/details.nix") { };
      profileMeta = profileDetails;
      profileSecrets = import (profileDir + "/secrets.nix");
      rawSettings = import (baseDir + "/settings.nix") { inherit inputs; };

      pkgs = import nixpkgs {
        system = profileMeta.system;
        overlays = [
          vscodeOverlay
          localFixesOverlay
        ];
        config.allowUnfree = true;
      };

      settings = rawSettings // {
        secrets = (rawSettings.secrets or { }) // profileSecrets;
        inherit profileDetails;
        themeDetails = import (baseDir + "/themes/${rawSettings.theme}.nix") { inherit pkgs; };
      };

      lib = nixpkgs.lib;
      hmUsers = builtins.attrNames (settings.userSettings or { });
      userOverrides = settings.userSettings or { };

      baseSettings = builtins.removeAttrs settings [
        "profileDetails"
        "themeDetails"
        "username"
        "dotfilesDir"
      ];

      hmSharedModulesCommon = [
        inputs.plasma-manager.homeModules.plasma-manager
        inputs.nixvim.homeModules.nixvim
      ]
      ++ lib.optional settings.enableSops inputs.sops-nix.homeManagerModules.sops;

      hmSharedModulesNixos = hmSharedModulesCommon;
      hmSharedModulesStandalone = hmSharedModulesCommon ++ [ inputs.stylix.homeModules.stylix ];

      mkUserSettings =
        username:
        let
          userOverride = userOverrides.${username} or { };
          userSecretOverride = userOverride.secrets or { };
          userDevOverride = userOverride.dev or { };
          userProgramOverride = userOverride.programs or { };
          userHyprlandOverride = userOverride.hyprland or { };
          merged =
            baseSettings
            // (builtins.removeAttrs userOverride [
              "secrets"
              "dev"
              "programs"
              "hyprland"
            ])
            // {
              inherit username;
              dotfilesDir = "/home/${username}/DEV/j0nix-os";
            };
          themeDetails = import (baseDir + "/themes/${merged.theme}.nix") { inherit pkgs; };
          defaultWMFromLegacy =
            if userOverride ? wms && (builtins.length userOverride.wms) > 0 then
              builtins.head userOverride.wms
            else
              null;
          resolvedDefaultWMS =
            if userOverride ? defaultWMS then
              userOverride.defaultWMS
            else if defaultWMFromLegacy != null then
              defaultWMFromLegacy
            else
              "hyprland";
          resolvedDefaultSession =
            if resolvedDefaultWMS == "hyprland" then
              (if ((merged.hyprland or { }).useUWSM or true) then "hyprland-uwsm" else "hyprland")
            else
              resolvedDefaultWMS;
        in
        merged
        // {
          inherit profileDetails;
          secrets = (baseSettings.secrets or { }) // {
            user = userSecretOverride;
          };
          dev = lib.recursiveUpdate (baseSettings.dev or { }) userDevOverride;
          programs = lib.recursiveUpdate (baseSettings.programs or { }) userProgramOverride;
          hyprland = lib.recursiveUpdate (baseSettings.hyprland or { }) userHyprlandOverride;
          inherit themeDetails;
          wmShell = merged.wmShell or (merged.hyprlandShell or (themeDetails.shell or "dank-material-shell"));
          hyprlandShell =
            merged.wmShell or (merged.hyprlandShell or (themeDetails.shell or "dank-material-shell"));
          defaultWMS = resolvedDefaultWMS;
          defaultSession = resolvedDefaultSession;
          _userOverride = userOverride;
        };

      mkEditorModule =
        editor:
        let
          localDefault = baseDir + "/user/editors/${editor}/default.nix";
          localFile = baseDir + "/user/editors/${editor}.nix";
        in
        if builtins.pathExists localDefault then
          localDefault
        else if builtins.pathExists localFile then
          localFile
        else
          null;

      mkBrowserModule =
        browser:
        let
          browserFile = baseDir + "/user/browsers/${browser}.nix";
        in
        if builtins.pathExists browserFile then browserFile else null;

      mkWmModule =
        wm:
        let
          wmDefault = baseDir + "/user/wm/${wm}/default.nix";
          wmFile = baseDir + "/user/wm/${wm}.nix";
        in
        if builtins.pathExists wmDefault then
          wmDefault
        else if builtins.pathExists wmFile then
          wmFile
        else
          null;

      mkUserRoleHomeModule =
        role:
        let
          roleModule = baseDir + "/user-roles/home/${role}.nix";
        in
        if builtins.pathExists roleModule then roleModule else null;

      mkHomeModules =
        userSettings:
        let
          shellModule = baseDir + "/user/shells/${userSettings.shell}.nix";
          resolvedShellModule =
            if builtins.pathExists shellModule then shellModule else baseDir + "/user/shells/zsh.nix";

          wmShellModule = baseDir + "/user/wm/hyprland/shells/${userSettings.wmShell}";
          wmShellExists = builtins.pathExists wmShellModule;
          wmNeedsShell = builtins.elem userSettings.defaultWMS [
            "hyprland"
            "mangowc"
            "niri"
          ];
          wmShellLauncherModule = baseDir + "/user/wm/shell-launcher.nix";
          wmShellCommonModule = baseDir + "/user/wm/hyprland/shells/common/default.nix";

          wmModules = lib.filter (m: m != null) [ (mkWmModule userSettings.defaultWMS) ];
          editorModules = lib.filter (m: m != null) (map mkEditorModule userSettings.editors);
          browserModules = lib.filter (m: m != null) (map mkBrowserModule userSettings.browsers);
          roleNames = userSettings.roles or [ ];
          roleHomeModules = lib.filter (m: m != null) (map mkUserRoleHomeModule roleNames);
          missingRoleNames = lib.filter (role: (mkUserRoleHomeModule role) == null) roleNames;
          devModule = baseDir + "/user/dev/default.nix";
          devEnabled = (userSettings.dev or { }).enable or true;
        in
        [
          (profileDir + "/home.nix")
          (baseDir + "/user/software/default.nix")
          (baseDir + "/user/custom/default.nix")
          (baseDir + "/user/security/secrets.nix")
          resolvedShellModule
          (baseDir + "/user/session-default.nix")
          (baseDir + "/user/programs/default.nix")
          (
            { lib, ... }:
            {
              assertions = [
                {
                  assertion = builtins.elem userSettings.defaultWMS [
                    "hyprland"
                    "gnome"
                    "mangowc"
                    "niri"
                  ];
                  message = "userSettings.<name>.defaultWMS must be one of: hyprland, gnome, mangowc, niri";
                }
                {
                  assertion = !(userSettings._userOverride ? wms);
                  message = "Per-user wm list is deprecated. Use userSettings.<name>.defaultWMS only.";
                }
                {
                  assertion = !(userSettings._userOverride ? defaultSession);
                  message = "Per-user defaultSession is deprecated. Use userSettings.<name>.defaultWMS and global settings.hyprland.useUWSM.";
                }
                {
                  assertion = missingRoleNames == [ ];
                  message = "Unknown user role(s) for ${userSettings.username}: ${lib.concatStringsSep ", " missingRoleNames}. Expected modules under user-roles/home/<role>.nix";
                }
              ]
              ++ lib.optional wmNeedsShell {
                assertion = wmShellExists;
                message = "Unknown wmShell '${userSettings.wmShell}'. Valid examples: ags, dank-material-shell, noctalia-shell, caelestia-shell, none.";
              };
            }
          )
        ]
        ++ lib.optional wmNeedsShell wmShellCommonModule
        ++ lib.optional wmNeedsShell wmShellLauncherModule
        ++ wmModules
        ++ editorModules
        ++ browserModules
        ++ roleHomeModules
        ++ lib.optional (devEnabled && builtins.pathExists devModule) devModule
        ++ lib.optional (wmNeedsShell && wmShellExists) wmShellModule;
      systemSettings = settings;

      mkHmUserModule =
        username:
        let
          userSettings = mkUserSettings username;
        in
        { ... }:
        {
          _module.args = {
            inherit inputs profileMeta;
            settings = userSettings;
          };
          imports = mkHomeModules userSettings;
        };
    in
    {
      nixosConfigurations = {
        ${profileMeta.hostname} = nixpkgs.lib.nixosSystem {
          modules = [
            inputs.stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
            (
              { ... }:
              {
                nixpkgs.overlays = [
                  vscodeOverlay
                  localFixesOverlay
                ];
              }
            )
            (
              { ... }:
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "backup";
                  extraSpecialArgs = { inherit inputs profileMeta; };
                  sharedModules = hmSharedModulesNixos;
                  users = builtins.listToAttrs (
                    map (username: {
                      name = username;
                      value = mkHmUserModule username;
                    }) hmUsers
                  );
                };
              }
            )
            (profileDir + "/configuration.nix")
          ]
          ++ lib.optional settings.enableSops inputs.sops-nix.nixosModules.sops;

          specialArgs = {
            inherit inputs profileMeta;
            settings = systemSettings;
          };
        };
      };

      homeConfigurations = builtins.listToAttrs (
        map (username: {
          name = username;
          value =
            let
              userSettings = mkUserSettings username;
            in
            home-manager.lib.homeManagerConfiguration {
              pkgs = import nixpkgs {
                system = profileMeta.system;
                overlays = [
                  vscodeOverlay
                  localFixesOverlay
                ];
                config.allowUnfree = true;
              };
              modules = (mkHomeModules userSettings) ++ hmSharedModulesStandalone;
              extraSpecialArgs = {
                inherit inputs profileMeta;
                settings = userSettings;
              };
            };
        }) hmUsers
      );
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-language-server-src = {
      url = "github:isaacphi/mcp-language-server";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags = {
      url = "git+https://github.com/Aylur/ags?rev=60180a184cfb32b61a1d871c058b31a3b9b0743d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dank-material-shell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Quickshell overview plugin (Hyprland-focused, runs alongside DMS).
    quickshell-overview = {
      url = "github:Shanu-Kumawat/quickshell-overview";
      flake = false;
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprmcp-src = {
      url = "github:stefanoamorelli/hyprmcp";
      flake = false;
    };

    quickshell-stable = {
      url = "github:quickshell-mirror/quickshell?ref=v0.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell-dev = {
      url = "github:quickshell-mirror/quickshell?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell-stable";
    };

    caelestia-shell-dev = {
      url = "github:caelestia-dots/shell?rev=0eaca375abd76fbe08e7e0d62708ae910a7ac6d9";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell-dev";
    };

    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors";
      inputs.hyprland.follows = "hyprland";
    };

    hyprkcs = {
      url = "github:kosa12/hyprKCS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland-minimizer-orteip = {
      url = "github:0rteip/hyprland_minimizer";
      flake = false;
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    staging-next = {
      url = "github:nixos/nixpkgs/staging-next";
    };
  };
}
