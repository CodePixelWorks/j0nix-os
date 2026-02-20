{
  description = "j0nix-os (independent gaming/dev NixOS)";

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      baseDir = ./.;

      vscodeOverlay = inputs.nix-vscode-extensions.overlays.default;
      xorgCompatOverlay = final: prev: {
        # Compatibility shims for inputs still referencing deprecated aliases.
        system = prev.stdenv.hostPlatform.system;
        xorg = prev.xorg // {
          libxcb = prev.libxcb;
        };
      };
      rawSettings = import (baseDir + "/settings.nix") { inherit inputs; };

      pkgs = import nixpkgs {
        system = rawSettings.system;
        overlays = [ vscodeOverlay xorgCompatOverlay ];
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
          merged = baseSettings // (userOverrides.${username} or { }) // {
            inherit username;
            dotfilesDir = "/home/${username}/nixos-dotfiles";
          };
          themeDetails = import (baseDir + "/themes/${merged.theme}.nix") { inherit pkgs; };
        in
        merged // {
          profileDetails = import (baseDir + "/profiles/${merged.profile}/details.nix") { };
          inherit themeDetails;
          hyprlandShell = merged.hyprlandShell or (themeDetails.shell or "dank-material-shell");
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

      mkHomeModules = userSettings:
        let
          shellModule = baseDir + "/user/shells/${userSettings.shell}.nix";
          resolvedShellModule = if builtins.pathExists shellModule then shellModule else baseDir + "/user/shells/zsh.nix";

          hyprlandShellModule = baseDir + "/user/wm/hyprland/shells/${userSettings.hyprlandShell}";
          hyprlandShellExists = builtins.pathExists hyprlandShellModule;

          wmModules = lib.filter (m: m != null) (map mkWmModule userSettings.wms);
          editorModules = lib.filter (m: m != null) (map mkEditorModule userSettings.editors);
          browserModules = lib.filter (m: m != null) (map mkBrowserModule userSettings.browsers);
          devModule = baseDir + "/user/dev/default.nix";
          devEnabled = (userSettings.dev or { }).enable or true;
        in
        [
          (baseDir + "/profiles/${userSettings.profile}/home.nix")
          resolvedShellModule
          (baseDir + "/user/session-default.nix")
          (baseDir + "/user/programs/default.nix")
          ({ lib, ... }: {
            assertions = lib.optional (builtins.elem "hyprland" userSettings.wms) {
              assertion = hyprlandShellExists;
              message = "Unknown hyprlandShell '${userSettings.hyprlandShell}'. Valid examples: ags, dank-material-shell, noctalia-shell.";
            };
          })
        ]
        ++ wmModules
        ++ editorModules
        ++ browserModules
        ++ lib.optional (devEnabled && builtins.pathExists devModule) devModule
        ++ lib.optional (builtins.elem "hyprland" userSettings.wms && hyprlandShellExists)
          hyprlandShellModule;

      systemWms = lib.unique (builtins.concatLists (map (username: (mkUserSettings username).wms) hmUsers));
      systemSettings = settings // { wms = systemWms; };

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
            ({ ... }: { nixpkgs.overlays = [ vscodeOverlay xorgCompatOverlay ]; })
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
              overlays = [ vscodeOverlay xorgCompatOverlay ];
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

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
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
