{ config, lib, pkgs, settings, ... }:
let
  storageCfg = settings.storage or { };
  rawShares = storageCfg.sambaShares or [ ];
  userShares = builtins.filter (share: (share.mode or "system") == "user") rawShares;
  hasValue = value: value != null && value != "";
  mountRoot = "${config.home.homeDirectory}/Mounts";
  gioBin = "${pkgs.glib}/bin/gio";
  pythonBin = "${pkgs.python3}/bin/python3";

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

  mountScriptFor = share:
    let
      shareName = share.name or share.share;
      aliasName = share.mountAlias or shareName;
      gvfsPath = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs/smb-share:server=${share.host},share=${share.share}";
      secretPath = secretPathFor share;
    in
    ''
      set -eu
      mkdir -p ${lib.escapeShellArg mountRoot}
      export SMB_HOST=${lib.escapeShellArg share.host}
      export SMB_SHARE=${lib.escapeShellArg share.share}
      export SMB_USERNAME=${lib.escapeShellArg (share.username or "")}
      export SMB_PASSWORD=""
      ${lib.optionalString (secretPath != null) ''
        export SMB_PASSWORD="$(tr -d '\n' < ${lib.escapeShellArg secretPath})"
      ''}
      uri="$(${pythonBin} - <<'PY'
from os import environ
from urllib.parse import quote
host = environ["SMB_HOST"]
share = environ["SMB_SHARE"]
username = environ.get("SMB_USERNAME", "")
password = environ.get("SMB_PASSWORD", "")
auth = ""
if username:
    auth = quote(username, safe="")
    if password:
        auth += ":" + quote(password, safe="")
    auth += "@"
print(f"smb://{auth}{host}/{quote(share, safe=\"\")}")
PY
)"
      if [ -d ${lib.escapeShellArg gvfsPath} ]; then
        ln -sfn ${lib.escapeShellArg gvfsPath} ${lib.escapeShellArg "${mountRoot}/${aliasName}"}
        exit 0
      fi
      if ! ${gioBin} mount "$uri"; then
        echo "warning: failed to mount SMB share ${shareName}" >&2
        exit 0
      fi
      if [ -d ${lib.escapeShellArg gvfsPath} ]; then
        ln -sfn ${lib.escapeShellArg gvfsPath} ${lib.escapeShellArg "${mountRoot}/${aliasName}"}
      fi
    '';

  unmountScriptFor = share:
    let
      shareName = share.name or share.share;
      aliasName = share.mountAlias or shareName;
      gvfsPath = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs/smb-share:server=${share.host},share=${share.share}";
    in
    ''
      set -eu
      export SMB_HOST=${lib.escapeShellArg share.host}
      export SMB_SHARE=${lib.escapeShellArg share.share}
      uri="$(${pythonBin} - <<'PY'
from os import environ
from urllib.parse import quote
host = environ["SMB_HOST"]
share = environ["SMB_SHARE"]
print(f"smb://{host}/{quote(share, safe=\"\")}")
PY
)"
      if [ -L ${lib.escapeShellArg "${mountRoot}/${aliasName}"} ]; then
        rm -f ${lib.escapeShellArg "${mountRoot}/${aliasName}"}
      fi
      if [ -d ${lib.escapeShellArg gvfsPath} ]; then
        ${gioBin} mount -u "$uri" || true
      fi
    '';

  shareCommands =
    lib.concatMap
      (share:
        let
          shareName = share.name or share.share;
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
            shareName = share.name or share.share;
          in
          {
            name = "user-smb-${shareName}";
            value = {
              Unit = {
                Description = "User SMB mount for ${shareName}";
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${config.home.profileDirectory}/bin/user-smb-mount-${shareName}";
              };
              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };
          })
        (builtins.filter (share: share.autoMount or false) userShares));
in
{
  config = lib.mkIf (userShares != [ ]) {
    home.activation.ensureUserMountRoot =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${lib.escapeShellArg mountRoot}
      '';

    j0nix.user.software.packages = shareCommands;

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
