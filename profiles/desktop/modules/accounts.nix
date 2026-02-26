{ lib, settings, ... }:
let
  users = settings.users or [ settings.username ];
  userOverrides = settings.userSettings or { };
in
{
  j0nix.desktop.accounts = {
    inherit users;
    defaultShell = settings.shell;
    userShells = lib.mapAttrs (_: cfg: cfg.shell) (lib.filterAttrs (_: cfg: cfg ? shell) userOverrides);
    includeDockerGroup = (((settings.dev or { }).docker or { }).enable or true);
    autologinUser = null;
  };
}
