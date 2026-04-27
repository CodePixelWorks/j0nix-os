{
  description = "NixOS/Home Manager integration for Autodesk Fusion on Linux";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager, ... }:
    let
      systems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        autodesk-fusion-linux = final.callPackage ./pkgs/autodesk-fusion-linux { };
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
            config.allowUnfree = true;
          };
        in
        {
          default = pkgs.autodesk-fusion-linux;
          autodesk-fusion-linux = pkgs.autodesk-fusion-linux;
        });

      homeManagerModules.default = ./modules/home-manager/autodesk-fusion.nix;
      nixosModules.default = ./modules/nixos/autodesk-fusion.nix;

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
            config.allowUnfree = true;
          };
          lib = nixpkgs.lib;
          hmEval = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home = {
                  username = "fusion-test";
                  homeDirectory = "/home/fusion-test";
                  stateVersion = "25.11";
                };
                programs.autodeskFusion = {
                  enable = true;
                  autoSetupOnLogin = false;
                };
              }
            ];
          };
          nixosEval = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                nixpkgs.overlays = [ self.overlays.default ];
                nixpkgs.config.allowUnfree = true;
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "test";
                  fsType = "ext4";
                };
                system.stateVersion = "25.11";
                programs.autodeskFusion.systemIntegration.enable = true;
              }
            ];
          };
        in
        {
          package = pkgs.autodesk-fusion-linux;
          shellcheck = pkgs.callPackage ./tests/shellcheck.nix {
            package = pkgs.autodesk-fusion-linux;
          };
          bats = pkgs.callPackage ./tests/bats.nix {
            package = pkgs.autodesk-fusion-linux;
          };
          home-manager-module = hmEval.activationPackage;
          nixos-module = nixosEval.config.system.build.toplevel;
        });
    };
}
