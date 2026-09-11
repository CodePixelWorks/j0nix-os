{ config, lib, pkgs, settings, ... }:
let
  cfg = config.j0nix.desktop.accounts;
  allowedShells = [ "zsh" "fish" ];
  userSettings = settings.userSettings or { };
  configuredUsers = builtins.attrNames userSettings;
  primaryUser = if configuredUsers == [ ] then null else builtins.head configuredUsers;
  configuredDefaultShell =
    if primaryUser == null then
      "zsh"
    else
      (userSettings.${primaryUser}.shell or "zsh");
  configuredUserShells = lib.mapAttrs (
    _: userConfig: userConfig.shell
  ) (lib.filterAttrs (_: userConfig: userConfig ? shell) userSettings);
  configuredDockerUsers = lib.filter (
    username: ((((userSettings.${username} or { }).dev or { }).docker or { }).enable or false)
  ) configuredUsers;
  shellForUser = username: cfg.userShells.${username} or cfg.defaultShell;
  resolvedShells = map shellForUser cfg.users;
  hmServiceNames = map (username: "home-manager-${username}") cfg.users;
  useZsh = builtins.elem "zsh" resolvedShells;
  useFish = builtins.elem "fish" resolvedShells;
  resolvePasswordSecret = username:
    let
      userCfg = userSettings.${username} or { };
      userSecretsCfg = userCfg.secrets or { };
      passwordSecret = userCfg.passwordSecret or null;
      resolvedSopsFile =
        if passwordSecret == null then
          null
        else
          passwordSecret.sopsFile or (userSecretsCfg.defaultSopsFile or settings.secrets.defaultUserSopsFile or null);
    in
    {
      inherit passwordSecret resolvedSopsFile;
    };
  mkUserPasswordSecret = username:
    let
      resolved = resolvePasswordSecret username;
    in
    lib.optionalAttrs (resolved.passwordSecret != null && resolved.resolvedSopsFile != null) {
      "${username}-password" = {
        key = resolved.passwordSecret.key or "hashedPassword";
        sopsFile = resolved.resolvedSopsFile;
        neededForUsers = true;
      };
    };
  passwordSecrets = lib.foldl' (acc: username: acc // mkUserPasswordSecret username) { } cfg.users;
  userHasPasswordFile = username:
    let
      resolved = resolvePasswordSecret username;
    in
    resolved.passwordSecret != null && resolved.resolvedSopsFile != null;
  hasDeclarativePasswordSecrets = lib.any userHasPasswordFile cfg.users;
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

    additionalExtraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra groups appended on top of the base desktop account groups.";
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
    j0nix.desktop.accounts = {
      users = lib.mkDefault configuredUsers;
      defaultShell = lib.mkDefault configuredDefaultShell;
      userShells = lib.mkDefault configuredUserShells;
      dockerUsers = lib.mkDefault configuredDockerUsers;
      autologinUser = lib.mkDefault null;
    };

    programs.zsh.enable = useZsh;
    programs.fish.enable = useFish;
    services.getty.autologinUser = lib.mkForce cfg.autologinUser;
    users.mutableUsers = lib.mkIf hasDeclarativePasswordSecrets (lib.mkDefault false);

    users.users = lib.genAttrs cfg.users (username: {
      isNormalUser = true;
      shell = pkgs.${shellForUser username};
      description = username;
      extraGroups = lib.unique (
        cfg.baseExtraGroups
        ++ cfg.additionalExtraGroups
        ++ lib.optionals (builtins.elem username cfg.dockerUsers) [ "docker" ]
      );
    } // lib.optionalAttrs (userHasPasswordFile username) {
      hashedPasswordFile = config.sops.secrets."${username}-password".path;
    });

    sops.secrets = lib.mkIf (settings.enableSops or false) passwordSecrets;

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
