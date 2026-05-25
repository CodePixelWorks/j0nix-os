{ lib, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  users = builtins.attrNames userOverrides;

  rolesForUser =
    username:
    let
      userCfg = userOverrides.${username} or { };
    in
    userCfg.roles or [ ];

  allRoles = lib.unique (lib.concatMap rolesForUser users);

  # Roles that actually contribute system-level configuration.
  # Home-only roles (e.g. desktop-basics, ai-work) live under user-roles/home/
  # and are not imported here.
  rolesWithSystemModules = [
    "3d-creation"
    "3d-printing"
    "developer"
    "gaming"
    "network-performance"
    "office"
    "remote-work"
    "video-editing"
  ];

  systemRoles = lib.filter (role: builtins.elem role rolesWithSystemModules) allRoles;
  rolePath = role: ./. + "/${role}.nix";
  existingRoleModules = lib.filter builtins.pathExists (map rolePath systemRoles);
  missingRoles = lib.filter (role: !(builtins.pathExists (rolePath role))) systemRoles;
in
{
  imports = existingRoleModules;

  assertions = [
    {
      assertion = missingRoles == [ ];
      message = "Unknown user system role(s): ${lib.concatStringsSep ", " missingRoles}. Expected modules under nix/roles/system/<role>.nix";
    }
  ];
}
