{ lib, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  users = builtins.attrNames userOverrides;
  primaryUser = if users == [ ] then null else builtins.head users;
  defaultShell =
    if primaryUser == null then
      "zsh"
    else
      (userOverrides.${primaryUser}.shell or "zsh");
in
{
  j0nix.desktop.accounts = {
    inherit users;
    inherit defaultShell;
    userShells = lib.mapAttrs (_: cfg: cfg.shell) (lib.filterAttrs (_: cfg: cfg ? shell) userOverrides);
    includeDockerGroup = (((settings.dev or { }).docker or { }).enable or true);
    autologinUser = null;
  };
}
