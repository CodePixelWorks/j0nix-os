{ lib, settings, ... }:
let
  polkitRules = import ../../../system/lib/polkit-rules.nix { inherit lib; };
  storageCfg = settings.storage or { };
  sambaShares = storageCfg.sambaShares or [ ];
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
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  j0nix.desktop.storage.mounts = [
    {
      name = "games";
      enable = true;
      mountPoint = "/mnt/Games";
      device = "/dev/disk/by-uuid/6A68028468024F6F";
      fsType = "ntfs3";
      options = [
        "rw"
        "uid=1000"
        "gid=100"
        "umask=0022"
        "nofail"
      ];
      gvfsShow = true;
      gvfsName = "GAMES";
      automount = false;
      idleTimeout = "5min";
      preventRemount = true;
      forceDirtyNtfsMount = false;
      lazyUnmountOnShutdown = true;
    }
  ] ++ map mkSambaMount sambaShares;

  j0nix.desktop.security.polkit.extraConfigSnippets =
    [ polkitRules.mkUdisksWheelMountRule ];

  assertions = map
    (share: {
      assertion = !((hasValue (share.secretName or null)) && (share ? credentialsFile && share.credentialsFile != ""));
      message = "settings.storage.sambaShares.${share.name or share.mountPoint or "share"} must not set both secretName and credentialsFile.";
    })
    sambaShares;
}
