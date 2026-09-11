{ config, lib, settings, ... }:
let
  cfg = config.j0nix.desktop.nix;
  users = builtins.attrNames (settings.userSettings or { });
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
    j0nix.desktop.nix = {
      allowUnfree = lib.mkDefault true;
      experimentalFeatures = lib.mkDefault [ "nix-command" "flakes" ];
      trustedUsers = lib.mkDefault ([ "root" ] ++ users);
      substituters = lib.mkDefault [
        "https://attic.xuyh0120.win/lantian"
        "https://hyprland.cachix.org"
      ];
      trustedPublicKeys = lib.mkDefault [
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
      gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 14d";
      };
      optimise.automatic = lib.mkDefault true;
    };

    nixpkgs.config.allowUnfree = cfg.allowUnfree;

    # Let sudo pass SSH_AUTH_SOCK so nix-daemon can use the user's
    # SSH agent for private git+ssh:// flake inputs.
    security.sudo.extraConfig = "Defaults env_keep += SSH_AUTH_SOCK";

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
