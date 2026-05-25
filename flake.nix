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
      lib = nixpkgs.lib;

      overlays = import (baseDir + "/nix/system/lib/flake/overlays.nix") {
        inherit baseDir inputs nixpkgs;
      };

      # -----------------------------------------------------------------------
      # Host configuration builder
      # -----------------------------------------------------------------------
      # Builds everything needed for one NixOS host.  `profileName`
      # selects the directory under profiles/ (host-specific hw data).
      # Profile name is intentionally kept out of settings.nix — it is a
      # host/selection concern, not a cross-platform default.
      # -----------------------------------------------------------------------
      mkHostAttrs = profileName:
        let
          profileDir = baseDir + "/profiles/${profileName}";

          profileDetailsFile =
            if builtins.pathExists (profileDir + "/details.nix") then
              profileDir + "/details.nix"
            else
              throw ''
                ${profileName}: profiles/${profileName}/details.nix is required for flake evaluation.

                The matching .example file is only a template and is never imported automatically.

                Create it from:
                  cp profiles/${profileName}/details.nix.example profiles/${profileName}/details.nix
              '';
          profileDetails = import profileDetailsFile { };
          profileMeta = profileDetails;
          profileSecrets = import (profileDir + "/secrets.nix");

          pkgs = import nixpkgs {
            system = profileMeta.system;
            overlays = overlays.default;
            config.allowUnfree = true;
          };

          rawSettings = import settingsFile { inherit inputs; };
          settings = rawSettings // {
            secrets = (rawSettings.secrets or { }) // profileSecrets;
            inherit profileDetails;
            themeDetails = import (baseDir + "/themes/${rawSettings.theme}.nix") { inherit pkgs; };
          };

          baseSettings = builtins.removeAttrs settings [
            "profileDetails"
            "themeDetails"
            "username"
            "dotfilesDir"
          ];

          userOverrides = settings.userSettings or { };

          mkUserSettings = import (baseDir + "/nix/system/lib/settings/mk-user-settings.nix") {
            inherit baseDir baseSettings lib pkgs profileDetails userOverrides;
          };

          mkHomeModules = import (baseDir + "/nix/system/lib/home/mk-home-modules.nix") {
            inherit baseDir lib profileDir;
          };

          # Backward compat: old settings.nix may still contain profileName,
          # but it is ignored here.  The flake owns host → profile mapping.
        in
        {
          inherit profileDir profileDetails profileMeta profileSecrets pkgs settings baseSettings userOverrides mkUserSettings mkHomeModules;
        };

      mkNixosSystem = { profileName }:
        let
          host = mkHostAttrs profileName;
          hmUsers = builtins.attrNames (host.settings.userSettings or { });
        in
        nixpkgs.lib.nixosSystem {
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
                  extraSpecialArgs = {
                    inherit inputs;
                    profileMeta = host.profileMeta;
                  };
                  sharedModules = hmSharedModules host.settings;
                  users = builtins.listToAttrs (
                    map (username: {
                      name = username;
                      value = { ... }:
                        let
                          userSettings = host.mkUserSettings username;
                        in
                        {
                          _module.args = {
                            inherit inputs;
                            profileMeta = host.profileMeta;
                            settings = userSettings;
                          };
                          imports = host.mkHomeModules userSettings;
                        };
                    }) hmUsers
                  );
                };
              }
            )
            (host.profileDir + "/configuration.nix")
          ]
          ++ lib.optional host.settings.enableSops inputs.sops-nix.nixosModules.sops;

          specialArgs = {
            inherit inputs;
            profileMeta = host.profileMeta;
            settings = host.settings;
          };
        };

      mkHomeManagerConfiguration = { username, profileName }:
        let
          host = mkHostAttrs profileName;
          userSettings = host.mkUserSettings username;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = host.profileMeta.system;
            overlays = overlays.default;
            config.allowUnfree = true;
          };
          modules = (host.mkHomeModules userSettings) ++ hmSharedModulesStandalone host.settings;
          extraSpecialArgs = {
            inherit inputs;
            profileMeta = host.profileMeta;
            settings = userSettings;
          };
        };

      # Shared modules helpers (need settings to gate sops)
      hmSharedModules = settings: [
        inputs.plasma-manager.homeModules.plasma-manager
        inputs.nixvim.homeModules.nixvim
      ]
      ++ lib.optional (settings.enableSops or false) inputs.sops-nix.homeManagerModules.sops;

      hmSharedModulesStandalone = settings: (hmSharedModules settings) ++ [ inputs.stylix.homeModules.stylix ];

      # Settings file discovery (host-independent)
      settingsFile =
        if builtins.pathExists (baseDir + "/settings.nix") then
          baseDir + "/settings.nix"
        else
          throw ''
            settings.nix is required but was not found in the evaluated flake source.

            This usually means the flake was evaluated from a git snapshot that does not
            include your local ignored settings.nix file.

            Use:
              nixos-rebuild switch --flake path:${toString baseDir}#<hostname>
          '';

    in
    {
      # -----------------------------------------------------------------------
      # NixOS hosts — explicit host → profile mapping
      # Add new hosts here.  The rebuild command is:
      #   sudo nixos-rebuild switch --flake .#<hostname>
      # -----------------------------------------------------------------------
      nixosConfigurations = {
        Jonas-PC = mkNixosSystem { profileName = "desktop"; };
        # Example for a future laptop host:
        # Jonas-Laptop = mkNixosSystem { profileName = "laptop"; };
      };

      # -----------------------------------------------------------------------
      # Home-manager standalone configurations
      # Format: username@hostname  (e.g. jonas@Jonas-PC)
      # This mirrors the per-host profile selection so a standalone home-manager
      # install uses the correct hw-derived settings (monitors, etc.).
      # -----------------------------------------------------------------------
      homeConfigurations =
        let
          hosts = [
            { name = "Jonas-PC"; profile = "desktop"; }
            # { name = "Jonas-Laptop"; profile = "laptop"; }
          ];
          allUsers = builtins.attrNames ((import settingsFile { inherit inputs; }).userSettings or { });
        in
        builtins.listToAttrs (
          lib.concatMap (host:
            map (username: {
              name = "${username}@${host.name}";
              value = mkHomeManagerConfiguration {
                inherit username;
                profileName = host.profile;
              };
            }) allUsers
          ) hosts
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
      url = "git+https://github.com/hyprwm/Hyprland?ref=refs/tags/v0.55.2&submodules=1";
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

    # Local sub Flake: Autodesk Fusion integration for NixOS/Home Manager.
    # Vendored at integrations/autodesk-fusion-nixos/; tracked as a flake input
    # so nixpkgs/home-manager versions stay aligned with the main flake.
    autodesk-fusion = {
      url = "path:./integrations/autodesk-fusion-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };
}
