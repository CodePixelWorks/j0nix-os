{ config, lib, settings, ... }:
let
  polkitRules = import ../../../system/lib/polkit-rules.nix { inherit lib; };
  usersGroupGid =
    if (config.users.groups ? users) && (config.users.groups.users ? gid) && config.users.groups.users.gid != null then
      config.users.groups.users.gid
    else
      100;
  storageCfg = settings.storage or { };
  systemMounts = storageCfg.systemMounts or [ ];
  userOverrides = settings.userSettings or { };
  sambaShares = lib.concatMap
    (username:
      let
        userCfg = userOverrides.${username} or { };
        storageCfg = userCfg.storage or { };
      in
      storageCfg.sambaShares or [ ])
    (builtins.attrNames userOverrides);
  systemSambaShares = builtins.filter (share: (share.mode or "system") != "user") sambaShares;
  hasValue = value: value != null && value != "";
  mkSambaMount = share:
    let
      mountName = share.name or "samba-share";
      gvfsLabel = share.gvfsName or mountName;
      secretName = share.secretName or null;
      credentialsPath =
        if hasValue secretName then
          "/run/secrets/${secretName}"
        else if share ? credentialsFile && share.credentialsFile != "" then
          share.credentialsFile
        else
          null;
    in
    {
      name = mountName;
      enable = share.enable or true;
      mountPoint = share.mountPoint;
      device = "//${share.host}/${share.share}";
      fsType = "cifs";
      options = [
        "nofail"
        "_netdev"
        "x-systemd.mount-timeout=${share.mountTimeout or "10s"}"
      ]
      ++ lib.optional (credentialsPath != null) "credentials=${credentialsPath}"
      ++ lib.optional (share ? username && share.username != "") "username=${share.username}"
      ++ lib.optional (share ? domain && share.domain != "") "domain=${share.domain}"
      ++ lib.optional (share ? vers && share.vers != "") "vers=${share.vers}"
      ++ (share.options or [ ]);
      gvfsShow = share.gvfsShow or true;
      gvfsName = gvfsLabel;
      automount = share.automount or true;
      idleTimeout = share.idleTimeout or "15min";
      preventRemount = share.preventRemount or false;
      forceDirtyNtfsMount = false;
      lazyUnmountOnShutdown = false;
    };
  hasUidOption = opts: builtins.any (opt: lib.hasPrefix "uid=" opt) opts;
  hasGidOption = opts: builtins.any (opt: lib.hasPrefix "gid=" opt) opts;
  enrichSystemMount = mount:
    let
      mountFsType = mount.fsType or "";
      mountOptions = mount.options or [ ];
      addNtfsOwnerDefaults =
        builtins.elem mountFsType [ "ntfs3" "ntfs" ]
        && (!hasUidOption mountOptions)
        && (!hasGidOption mountOptions);
    in
    mount // {
      options =
        mountOptions
        ++ lib.optionals addNtfsOwnerDefaults [
          "uid=0"
          "gid=${toString usersGroupGid}"
        ];
    };
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  j0nix.desktop.storage.mounts =
    (map enrichSystemMount systemMounts)
    ++ map mkSambaMount systemSambaShares;

  j0nix.desktop.security.polkit.extraConfigSnippets =
    [ polkitRules.mkUdisksWheelMountRule ];

  assertions = map
    (share: {
      assertion = !((hasValue (share.secretName or null)) && (share ? credentialsFile && share.credentialsFile != ""));
      message = "settings.userSettings.<name>.storage.sambaShares.${share.name or share.mountPoint or "share"} must not set both secretName and credentialsFile.";
    })
    systemSambaShares;
}
