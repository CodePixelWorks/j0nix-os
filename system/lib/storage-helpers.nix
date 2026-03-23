{ lib }:
let
  hasValue = value: value != null && value != "";
  hasUidOption = opts: builtins.any (opt: lib.hasPrefix "uid=" opt) opts;
  hasGidOption = opts: builtins.any (opt: lib.hasPrefix "gid=" opt) opts;
  hasMaskOption =
    opts:
    builtins.any (
      opt: (lib.hasPrefix "umask=" opt) || (lib.hasPrefix "fmask=" opt) || (lib.hasPrefix "dmask=" opt)
    ) opts;
in
{
  inherit
    hasValue
    hasUidOption
    hasGidOption
    hasMaskOption
    ;

  mkSambaMount =
    share:
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

  enrichSystemMount =
    usersGroupGid: mount:
    let
      mountFsType = mount.fsType or "";
      mountOptions = mount.options or [ ];
      isNtfs = builtins.elem mountFsType [
        "ntfs3"
        "ntfs"
      ];
      addNtfsOwnerDefaults = isNtfs && (!hasUidOption mountOptions) && (!hasGidOption mountOptions);
      addNtfsMaskDefaults = isNtfs && (!hasMaskOption mountOptions);
    in
    mount
    // {
      options =
        mountOptions
        ++ lib.optionals addNtfsOwnerDefaults [
          "uid=0"
          "gid=${toString usersGroupGid}"
        ]
        ++ lib.optionals addNtfsMaskDefaults [
          # Group-writable so all normal users in group `users` can write.
          "umask=0002"
        ];
    };
}
