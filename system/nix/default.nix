{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.nix;
in
{
  options.j0nix.desktop.nix = {
    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    experimentalFeatures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "nix-command" "flakes" ];
    };

    substituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    trustedPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "root" ];
    };

    gc = {
      automatic = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
      };
      options = lib.mkOption {
        type = lib.types.str;
        default = "--delete-older-than 14d";
      };
    };

    optimise.automatic = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = {
    nixpkgs.config.allowUnfree = cfg.allowUnfree;

    nix.settings = {
      experimental-features = cfg.experimentalFeatures;
      substituters = cfg.substituters;
      trusted-public-keys = cfg.trustedPublicKeys;
      trusted-users = cfg.trustedUsers;
    };

    nix.gc = {
      inherit (cfg.gc) automatic dates options;
    };

    nix.optimise.automatic = cfg.optimise.automatic;
  };
}
