{ config, lib, pkgs, settings, ... }:
let
  storageCfg = settings.storage or { };
  rawShares = storageCfg.sambaShares or [ ];
  userShares = builtins.filter (share: (share.mode or "system") == "user") rawShares;
  hasValue = value: value != null && value != "";
  mountRoot = "${config.home.homeDirectory}/Mounts";
  rcloneBin = "${pkgs.rclone}/bin/rclone";
  fuseUnmountBin = "${pkgs.fuse3}/bin/fusermount3";

  secretPathFor = share:
    let
      secretName = share.secretName or null;
    in
    if hasValue secretName && lib.hasAttrByPath [ secretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${secretName}.path
    else
      null;

  missingUserSecrets =
    builtins.filter
      (share:
        hasValue (share.secretName or null)
        && secretPathFor share == null)
      userShares;

  shareNameOf = share: share.name or share.share;
  mountAliasOf = share: share.mountAlias or (shareNameOf share);
  mountPathOf = share: "${mountRoot}/${mountAliasOf share}";
  runtimeConfigPathOf = share: "$XDG_RUNTIME_DIR/rclone-smb-${shareNameOf share}.conf";

  rcloneConfigScript = share:
    let
      secretPath = secretPathFor share;
      secretPathArg = lib.escapeShellArg (if secretPath != null then secretPath else "");
    in
    ''
      config_path=${lib.escapeShellArg (runtimeConfigPathOf share)}
      username=${lib.escapeShellArg (share.username or "")}
      password=""
      domain=""
      if [ -n ${secretPathArg} ]; then
        while IFS='=' read -r key value; do
          case "$key" in
            username) username="$value" ;;
            password) password="$value" ;;
            domain) domain="$value" ;;
          esac
        done < ${secretPathArg}
      fi
      if [ -z "$username" ] && [ -n ${lib.escapeShellArg (share.username or "")} ]; then
        username=${lib.escapeShellArg (share.username or "")}
      fi
      if [ -z "$username" ]; then
        echo "warning: SMB share ${shareNameOf share} has no username configured" >&2
        exit 1
      fi
      password_obscured=""
      if [ -n "$password" ]; then
        password_obscured="$(${rcloneBin} obscure "$password")"
      fi
      {
        printf '%s\n' '[share]'
        printf '%s\n' 'type = smb'
        printf 'host = %s\n' ${lib.escapeShellArg share.host}
        printf 'user = %s\n' "$username"
        printf 'pass = %s\n' "$password_obscured"
        ${lib.optionalString (share ? port && share.port != null) "printf 'port = %s\\n' ${lib.escapeShellArg (toString share.port)}"}
        printf 'domain = %s\n' "$domain"
      } > "$config_path"
      chmod 600 "$config_path"
    '';

  mountCommandFor = share:
    let
      mountPath = mountPathOf share;
      extraArgs = share.rcloneArgs or [ ];
      args =
        [
          "mount"
          "--config" (runtimeConfigPathOf share)
          "share:${share.share}"
          mountPath
          "--dir-cache-time" (share.dirCacheTime or "5m")
          "--vfs-cache-mode" (share.vfsCacheMode or "full")
          "--volname" (share.gvfsName or mountAliasOf share)
          "--network-mode"
        ] ++ extraArgs;
    in
    lib.escapeShellArgs ([ rcloneBin ] ++ args);

  mountScriptFor = share:
    let
      mountPath = mountPathOf share;
      shareName = shareNameOf share;
    in
    ''
      set -eu
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      mkdir -p ${lib.escapeShellArg mountRoot}
      mkdir -p ${lib.escapeShellArg mountPath}
      ${rcloneConfigScript share}
      if mountpoint -q ${lib.escapeShellArg mountPath}; then
        exit 0
      fi
      exec ${mountCommandFor share}
    '';

  unmountScriptFor = share:
    let
      mountPath = mountPathOf share;
      configPath = runtimeConfigPathOf share;
    in
    ''
      set -eu
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if mountpoint -q ${lib.escapeShellArg mountPath}; then
        ${fuseUnmountBin} -u ${lib.escapeShellArg mountPath} || true
      fi
      rm -f "$XDG_RUNTIME_DIR/rclone-smb-${shareNameOf share}.conf"
    '';

  shareCommands =
    lib.concatMap
      (share:
        let
          shareName = shareNameOf share;
        in
        [
          (pkgs.writeShellScriptBin "user-smb-mount-${shareName}" (mountScriptFor share))
          (pkgs.writeShellScriptBin "user-smb-unmount-${shareName}" (unmountScriptFor share))
        ])
      userShares;

  autoMountUnits =
    builtins.listToAttrs
      (map
        (share:
          let
            shareName = shareNameOf share;
          in
          {
            name = "user-smb-${shareName}";
            value = {
              Unit = {
                Description = "User SMB mount for ${shareName}";
                After = [ "graphical-session.target" "network-online.target" ];
                Wants = [ "network-online.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${config.home.profileDirectory}/bin/user-smb-mount-${shareName}";
                ExecStop = "${config.home.profileDirectory}/bin/user-smb-unmount-${shareName}";
                Restart = "on-failure";
                RestartSec = 3;
              };
              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };
          })
        (builtins.filter (share: share.autoMount or false) userShares));

  autoMountServiceNames =
    map (share: "user-smb-${shareNameOf share}.service")
      (builtins.filter (share: share.autoMount or false) userShares);
in
{
  config = lib.mkIf (userShares != [ ]) {
    home.activation.ensureUserMountRoot =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${lib.escapeShellArg mountRoot}
      '';

    home.activation.restartUserSambaMounts =
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        if autoMountServiceNames == [ ] then
          ":"
        else
          ''
            runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
            if [ -S "$runtime_dir/bus" ]; then
              systemctl --user daemon-reload
              ${lib.concatStringsSep "\n" (map (svc: ''
                systemctl --user restart ${lib.escapeShellArg svc} || true
              '') autoMountServiceNames)}
            else
              echo "warning: user session bus not available; skipping immediate SMB remount during activation" >&2
            fi
          ''
      );

    j0nix.user.software.packages = [ pkgs.rclone pkgs.fuse3 ] ++ shareCommands;

    systemd.user.services = autoMountUnits;

    assertions = [
      {
        assertion = builtins.all (share: hasValue (share.host or null) && hasValue (share.share or null)) userShares;
        message = "Each settings.userSettings.<name>.storage.sambaShares user entry requires host and share.";
      }
      {
        assertion = missingUserSecrets == [ ];
        message = "Each user-mode settings.userSettings.<name>.storage.sambaShares entry with secretName must reference an existing settings.userSettings.<name>.secrets.files secret.";
      }
    ];
  };
}
