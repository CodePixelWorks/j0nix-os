{
  description = "j0nix-os (independent gaming/dev NixOS)";

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      baseDir = ./.;

      vscodeOverlay = inputs.nix-vscode-extensions.overlays.default;
      rawSettings = import (baseDir + "/settings.nix") { inherit inputs; };

      pkgs = import nixpkgs {
        system = rawSettings.system;
        overlays = [ vscodeOverlay ];
        config.allowUnfree = true;
      };

      settings = rawSettings // {
        profileDetails = import (baseDir + "/profiles/${rawSettings.profile}/details.nix") { };
        themeDetails = import (baseDir + "/themes/${rawSettings.theme}.nix") { inherit pkgs; };
      };

      lib = nixpkgs.lib;
      hmUsers = settings.users or [ settings.username ];
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
      ] ++ lib.optional settings.enableSops inputs.sops-nix.homeManagerModules.sops;

      hmSharedModulesNixos = hmSharedModulesCommon;
      hmSharedModulesStandalone = hmSharedModulesCommon ++ [ inputs.stylix.homeModules.stylix ];

      mkUserSettings = username:
        let
          userOverride = userOverrides.${username} or { };
          merged = baseSettings // userOverride // {
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
        merged // {
          profileDetails = import (baseDir + "/profiles/${merged.profile}/details.nix") { };
          inherit themeDetails;
          wmShell =
            merged.wmShell
            or (merged.hyprlandShell or (themeDetails.shell or "dank-material-shell"));
          hyprlandShell =
            merged.wmShell
            or (merged.hyprlandShell or (themeDetails.shell or "dank-material-shell"));
          defaultWMS = resolvedDefaultWMS;
          defaultSession = resolvedDefaultSession;
          _userOverride = userOverride;
        };

      mkEditorModule = editor:
        let
          localDefault = baseDir + "/user/editors/${editor}/default.nix";
          localFile = baseDir + "/user/editors/${editor}.nix";
        in
          if builtins.pathExists localDefault then localDefault
          else if builtins.pathExists localFile then localFile
          else null;

      mkBrowserModule = browser:
        let
          browserFile = baseDir + "/user/browsers/${browser}.nix";
        in
          if builtins.pathExists browserFile then browserFile else null;

      mkWmModule = wm:
        let
          wmDefault = baseDir + "/user/wm/${wm}/default.nix";
          wmFile = baseDir + "/user/wm/${wm}.nix";
        in
          if builtins.pathExists wmDefault then wmDefault
          else if builtins.pathExists wmFile then wmFile
          else null;

      mkUserRoleHomeModule = role:
        let roleModule = baseDir + "/user-roles/home/${role}.nix";
        in if builtins.pathExists roleModule then roleModule else null;

      mkHomeModules = userSettings:
        let
          shellModule = baseDir + "/user/shells/${userSettings.shell}.nix";
          resolvedShellModule = if builtins.pathExists shellModule then shellModule else baseDir + "/user/shells/zsh.nix";

          wmShellModule = baseDir + "/user/wm/hyprland/shells/${userSettings.wmShell}";
          wmShellExists = builtins.pathExists wmShellModule;
          wmNeedsShell = builtins.elem userSettings.defaultWMS [ "hyprland" "mangowc" "niri" ];
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
          (baseDir + "/profiles/${userSettings.profile}/home.nix")
          (baseDir + "/user/software/default.nix")
          (baseDir + "/user/custom/default.nix")
          resolvedShellModule
          (baseDir + "/user/session-default.nix")
          (baseDir + "/user/programs/default.nix")
          ({ lib, ... }: {
            assertions = [
              {
                assertion = builtins.elem userSettings.defaultWMS [ "hyprland" "gnome" "mangowc" "niri" ];
                message = "userSettings.<name>.defaultWMS must be one of: hyprland, gnome, mangowc, niri";
              }
              {
                assertion = builtins.elem userSettings.defaultWMS settings.wms;
                message = "userSettings.<name>.defaultWMS must also be present in global settings.wms";
              }
              {
                assertion = !(userSettings._userOverride ? wms);
                message = "Per-user wm list is deprecated. Use userSettings.<name>.defaultWMS only.";
              }
              {
                assertion = !(userSettings._userOverride ? wmShell);
                message = "Per-user wmShell is deprecated. Configure settings.wmShell globally.";
              }
              {
                assertion = !(userSettings._userOverride ? hyprlandShell);
                message = "Per-user hyprlandShell is deprecated. Configure settings.hyprlandShell globally.";
              }
              {
                assertion = !(userSettings._userOverride ? defaultSession);
                message = "Per-user defaultSession is deprecated. Use userSettings.<name>.defaultWMS and global settings.hyprland.useUWSM.";
              }
              {
                assertion = missingRoleNames == [ ];
                message = "Unknown user role(s) for ${userSettings.username}: ${lib.concatStringsSep ", " missingRoleNames}. Expected modules under user-roles/home/<role>.nix";
              }
            ] ++ lib.optional wmNeedsShell {
              assertion = wmShellExists;
              message = "Unknown wmShell '${userSettings.wmShell}'. Valid examples: ags, dank-material-shell, noctalia-shell, caelestia-shell, none.";
            };
          })
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

      mkHmUserModule = username:
        let userSettings = mkUserSettings username;
        in { ... }: {
          _module.args = {
            inherit inputs;
            settings = userSettings;
          };
          imports = mkHomeModules userSettings;
        };
    in {
      nixosConfigurations = {
        ${settings.hostname} = nixpkgs.lib.nixosSystem {
          modules = [
            inputs.stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
            ({ ... }: { nixpkgs.overlays = [ vscodeOverlay ]; })
            ({ ... }: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                extraSpecialArgs = { inherit inputs; };
                sharedModules = hmSharedModulesNixos;
                users = builtins.listToAttrs (map (username: {
                  name = username;
                  value = mkHmUserModule username;
                }) hmUsers);
              };
            })
            (baseDir + "/profiles/${settings.profile}/configuration.nix")
          ] ++ lib.optional settings.enableSops inputs.sops-nix.nixosModules.sops;

          specialArgs = {
            inherit inputs;
            settings = systemSettings;
          };
        };
      };

      homeConfigurations = builtins.listToAttrs (map (username: {
        name = username;
        value = let userSettings = mkUserSettings username; in
          home-manager.lib.homeManagerConfiguration {
            pkgs = import nixpkgs {
              system = settings.system;
              overlays = [ vscodeOverlay ];
              config.allowUnfree = true;
            };
            modules = (mkHomeModules userSettings) ++ hmSharedModulesStandalone;
            extraSpecialArgs = {
              inherit inputs;
              settings = userSettings;
            };
          };
      }) hmUsers);
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli-nix.url = "github:sadjow/codex-cli-nix";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags.url = "git+https://github.com/Aylur/ags?rev=60180a184cfb32b61a1d871c058b31a3b9b0743d";

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

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
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

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
