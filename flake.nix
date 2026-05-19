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
      overlays = import (baseDir + "/system/lib/flake/overlays.nix") {
        inherit baseDir inputs nixpkgs;
      };
      profileName = "desktop";
      profileDir = baseDir + "/profiles/${profileName}";
      profileDetails = import (profileDir + "/details.nix") { };
      profileMeta = profileDetails;
      profileSecrets = import (profileDir + "/secrets.nix");
      rawSettings = import (baseDir + "/settings.nix") { inherit inputs; };

      pkgs = import nixpkgs {
        system = profileMeta.system;
        overlays = overlays.default;
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

      mkUserSettings = import (baseDir + "/system/lib/settings/mk-user-settings.nix") {
        inherit baseDir baseSettings lib pkgs profileDetails userOverrides;
      };
      mkHomeModules = import (baseDir + "/system/lib/home/mk-home-modules.nix") {
        inherit baseDir lib profileDir;
      };
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
                  overlays.vscodeOverlay
                  overlays.localFixesOverlay
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
                overlays = overlays.default;
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
      url = "github:caelestia-dots/shell?ref=main";
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
  };
}
