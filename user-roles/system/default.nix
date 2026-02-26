{ lib, settings, ... }:
let
  users = settings.users or [ settings.username ];
  userOverrides = settings.userSettings or { };

  rolesForUser =
    username:
    let
      userCfg = userOverrides.${username} or { };
    in
    userCfg.roles or [ ];

  allRoles = lib.unique (lib.concatMap rolesForUser users);

  rolePath = role: ./. + "/${role}.nix";
  existingRoleModules = lib.filter builtins.pathExists (map rolePath allRoles);
  missingRoles = lib.filter (role: !(builtins.pathExists (rolePath role))) allRoles;
in
{
  imports = existingRoleModules;

  assertions = [
    {
      assertion = missingRoles == [ ];
      message = "Unknown user system role(s): ${lib.concatStringsSep ", " missingRoles}. Expected modules under user-roles/system/<role>.nix";
    }
  ];
}
