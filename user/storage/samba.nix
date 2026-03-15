{ config, lib, pkgs, settings, ... }:
let
  storageCfg = settings.storage or { };
  rawShares = storageCfg.sambaShares or [ ];
  userShares = builtins.filter (share: (share.mode or "system") == "user") rawShares;
  hasValue = value: value != null && value != "";
  mountRoot = "${config.home.homeDirectory}/Mounts";
  cacheHome = lib.attrByPath [ "xdg" "cacheHome" ] "${config.home.homeDirectory}/.cache" config;
  rcloneBin = "${pkgs.rclone}/bin/rclone";
  fuseUnmountBin = "${pkgs.fuse3}/bin/fusermount3";

  secretPathFor = share:
    let
      secretName = share.secretName or null;
    in
    if hasValue secretName && lib.hasAttrByPath [ secretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${secretName}.path
    else if hasValue secretName && lib.hasAttrByPath [ secretName ] (config.sops.templates or { }) then
      config.sops.templates.${secretName}.path
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
  cacheDirOf = share: "${cacheHome}/rclone/smb/${shareNameOf share}";
  runtimeConfigPathOf = share: "$XDG_RUNTIME_DIR/rclone-smb-${shareNameOf share}.conf";

  rcloneConfigScript = share:
    let
      secretPath = secretPathFor share;
      secretPathArg = lib.escapeShellArg (if secretPath != null then secretPath else "");
      runtimeConfigName = "rclone-smb-${shareNameOf share}.conf";
    in
    ''
      config_path="$XDG_RUNTIME_DIR/${runtimeConfigName}"
      username=${lib.escapeShellArg (share.username or "")}
      password=${lib.escapeShellArg (share.password or "")}
      domain=${lib.escapeShellArg (share.domain or "")}
      if [ -f ${secretPathArg} ]; then
        while IFS= read -r line; do
          line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
          [ -z "$line" ] && continue
          case "$line" in
            \#*) continue ;;
          esac
          if printf '%s' "$line" | grep -q ': '; then
            key=''${line%%:*}
            value=''${line#*:}
          elif printf '%s' "$line" | grep -q '='; then
            key=''${line%%=*}
            value=''${line#*=}
          else
            continue
          fi
          key=$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
          value=$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
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
      extraArgsText =
        if extraArgs == [ ] then
          ""
        else
          " \\\n        ${lib.concatStringsSep " \\\n        " (map lib.escapeShellArg extraArgs)}";
    in
    ''
      ${lib.escapeShellArg rcloneBin} mount \
        --config "$XDG_RUNTIME_DIR/rclone-smb-${shareNameOf share}.conf" \
        ${lib.escapeShellArg "share:${share.share}"} \
        ${lib.escapeShellArg mountPath} \
        --cache-dir ${lib.escapeShellArg (cacheDirOf share)} \
        --dir-cache-time ${lib.escapeShellArg (share.dirCacheTime or "5m")} \
        --vfs-cache-mode ${lib.escapeShellArg (share.vfsCacheMode or "full")} \
        --vfs-cache-max-size ${lib.escapeShellArg (share.vfsCacheMaxSize or "5G")} \
        --vfs-cache-max-age ${lib.escapeShellArg (share.vfsCacheMaxAge or "1h")} \
        --volname ${lib.escapeShellArg (share.gvfsName or mountAliasOf share)} \
        --network-mode${extraArgsText}
    '';

  mountScriptFor = share:
    let
      mountPath = mountPathOf share;
      cacheDir = cacheDirOf share;
      shareName = shareNameOf share;
    in
    ''
      set -eu
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      mkdir -p ${lib.escapeShellArg mountRoot}
      mount_path=${lib.escapeShellArg mountPath}
      cache_dir=${lib.escapeShellArg cacheDir}

      # Recover from stale/broken FUSE mountpoints ("Transport endpoint is not connected").
      if [ -e "$mount_path" ] && ! ${pkgs.coreutils}/bin/stat "$mount_path" >/dev/null 2>&1; then
        ${fuseUnmountBin} -uz "$mount_path" >/dev/null 2>&1 || true
        ${pkgs.util-linux}/bin/umount -l "$mount_path" >/dev/null 2>&1 || true
        rm -rf "$mount_path" || true
      fi

      mkdir -p "$mount_path"
      mkdir -p "$cache_dir"
      ${rcloneConfigScript share}
      if ${pkgs.util-linux}/bin/mountpoint -q "$mount_path"; then
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
        ${fuseUnmountBin} -uz ${lib.escapeShellArg mountPath} >/dev/null 2>&1 \
          || ${pkgs.util-linux}/bin/umount -l ${lib.escapeShellArg mountPath} >/dev/null 2>&1 \
          || true
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
            runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
            if [ -S "$runtime_dir/bus" ]; then
              ${pkgs.systemd}/bin/systemctl --user daemon-reload
              ${lib.concatStringsSep "\n" (map (svc: ''
                ${pkgs.systemd}/bin/systemctl --user restart ${lib.escapeShellArg svc} || true
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
      {
        assertion =
          builtins.all
            (share:
              hasValue (share.secretName or null)
              || hasValue (share.password or null))
            userShares;
        message = "Each user-mode settings.userSettings.<name>.storage.sambaShares entry requires either secretName or a raw password.";
      }
    ];
  };
}
