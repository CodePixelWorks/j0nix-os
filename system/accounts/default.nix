{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.accounts;
  allowedShells = [ "zsh" "fish" ];
  shellForUser = username: cfg.userShells.${username} or cfg.defaultShell;
  resolvedShells = map shellForUser cfg.users;
  hmServiceNames = map (username: "home-manager-${username}") cfg.users;
  useZsh = builtins.elem "zsh" resolvedShells;
  useFish = builtins.elem "fish" resolvedShells;
in
{
  options.j0nix.desktop.accounts = {
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    defaultShell = lib.mkOption {
      type = lib.types.str;
      default = "zsh";
    };

    userShells = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Per-user shell overrides keyed by username.";
    };

    baseExtraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "wheel" "networkmanager" "audio" "video" "gamemode" ];
    };

    dockerUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    autologinUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  config = {
    programs.zsh.enable = useZsh;
    programs.fish.enable = useFish;
    services.getty.autologinUser = lib.mkForce cfg.autologinUser;

    users.users = lib.genAttrs cfg.users (username: {
      isNormalUser = true;
      shell = pkgs.${shellForUser username};
      description = username;
      extraGroups =
        cfg.baseExtraGroups
        ++ lib.optionals (builtins.elem username cfg.dockerUsers) [ "docker" ];
    });

    # HM activation scripts call `systemctl`; make it available inside the
    # generated home-manager-<user> systemd service environment.
    systemd.services = lib.genAttrs hmServiceNames (_: {
      path = [ pkgs.systemd ];
    });

    assertions = [
      {
        assertion = cfg.users != [ ];
        message = "j0nix.desktop.accounts.users must not be empty";
      }
      {
        assertion = builtins.elem cfg.defaultShell allowedShells;
        message = "j0nix.desktop.accounts.defaultShell must be one of: zsh, fish";
      }
      {
        assertion = lib.all (shell: builtins.elem shell allowedShells) resolvedShells;
        message = "All resolved account shells must be one of: zsh, fish";
      }
    ];
  };
}
