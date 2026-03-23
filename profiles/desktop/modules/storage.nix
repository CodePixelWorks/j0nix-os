{
  config,
  lib,
  settings,
  ...
}:
let
  polkitRules = import ../../../system/lib/polkit-rules.nix { inherit lib; };
  storageHelpers = import ../../../system/lib/storage-helpers.nix { inherit lib; };
  usersGroupGid =
    if
      (config.users.groups ? users)
      && (config.users.groups.users ? gid)
      && config.users.groups.users.gid != null
    then
      config.users.groups.users.gid
    else
      100;
  storageCfg = settings.storage or { };
  systemMounts = storageCfg.systemMounts or [ ];
  userOverrides = settings.userSettings or { };
  sambaShares = lib.concatMap (
    username:
    let
      userCfg = userOverrides.${username} or { };
      storageCfg = userCfg.storage or { };
    in
    storageCfg.sambaShares or [ ]
  ) (builtins.attrNames userOverrides);
  systemSambaShares = builtins.filter (share: (share.mode or "system") != "user") sambaShares;
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  j0nix.desktop.storage.mounts =
    (map (storageHelpers.enrichSystemMount usersGroupGid) systemMounts)
    ++ map storageHelpers.mkSambaMount systemSambaShares;

  j0nix.desktop.security.polkit.extraConfigSnippets = [ polkitRules.mkUdisksWheelMountRule ];

  assertions = map (share: {
    assertion =
      !(
        (storageHelpers.hasValue (share.secretName or null))
        && (share ? credentialsFile && share.credentialsFile != "")
      );
    message = "settings.userSettings.<name>.storage.sambaShares.${
      share.name or share.mountPoint or "share"
    } must not set both secretName and credentialsFile.";
  }) systemSambaShares;
}
