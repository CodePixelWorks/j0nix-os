{
  config,
  lib,
  pkgs,
  settings ? { },
  ...
}:
let
  cfg = config.j0nix.desktop.apps.flatpak;
  entries = lib.unique cfg.entries;
  entriesJson = pkgs.writeText "j0nix-flatpak-apps.json" (builtins.toJSON entries);
  configuredUsers =
    lib.mapAttrsToList
      (name: userCfg: {
        inherit name;
        home = userCfg.home or "/home/${name}";
      })
      (settings.userSettings or { });
  configuredUsersJson = pkgs.writeText "j0nix-flatpak-users.json" (builtins.toJSON configuredUsers);
  stateDir = "/var/lib/j0nix/flatpak";
  trackedFile = "${stateDir}/tracked-apps";
  desiredFile = "${stateDir}/desired-apps";

  installScript = pkgs.writeShellScript "j0nix-flatpak-install" ''
    set -eu

    # Flatpak remote-add and install hit the network (flathub.org). During a
    # switch/boot the network may be momentarily unavailable or the remote
    # fetch may flake — without a retry the whole oneshot unit fails with
    # "Can't load uri https://flathub.org/repo/flathub.flatpakrepo". Retry a
    # few times with a short backoff before giving up.
    retry() {
      local n=0 max=5 delay=10
      until "$@"; do
        n=$((n + 1))
        if [ "$n" -ge "$max" ]; then
          echo "j0nix-flatpak-install: command failed after $max attempts: $*" >&2
          return 1
        fi
        echo "j0nix-flatpak-install: attempt $n failed, retrying in ''${delay}s: $*" >&2
        sleep "$delay"
      done
    }

    mkdir -p ${stateDir}
    : > ${desiredFile}

    if [ "$(${pkgs.jq}/bin/jq 'length' ${entriesJson})" -eq 0 ]; then
      exit 0
    fi

    retry ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system \
      flathub https://flathub.org/repo/flathub.flatpakrepo

    ${pkgs.jq}/bin/jq -r '.[] | [.remote, .appId, .branch, (.remoteUrl // "")] | @tsv' ${entriesJson} | \
    while IFS=$'\t' read -r remote appId branch remoteUrl; do
      [ -n "$appId" ] || continue
      if [ -n "$remoteUrl" ]; then
        retry ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system "$remote" "$remoteUrl"
      fi
      ref="app/$appId/$(uname -m)/$branch"
      if ! ${pkgs.flatpak}/bin/flatpak info --system "$ref" >/dev/null 2>&1; then
        retry ${pkgs.flatpak}/bin/flatpak install --system --noninteractive "$remote" "$ref"
      fi
      printf '%s\n' "$ref" >> ${desiredFile}
    done

    ${pkgs.coreutils}/bin/sort -u -o ${desiredFile} ${desiredFile}
  '';

  pruneScript = pkgs.writeShellScript "j0nix-flatpak-prune" ''
    set -eu

    mkdir -p ${stateDir}
    touch ${trackedFile} ${desiredFile}

    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if ! ${pkgs.gnugrep}/bin/grep -Fxq "$ref" ${desiredFile}; then
        ${pkgs.flatpak}/bin/flatpak uninstall --system --noninteractive --delete-data "$ref" || true
      fi
    done < ${trackedFile}

    ${pkgs.jq}/bin/jq -r '.[] | [.name, .home] | @tsv' ${configuredUsersJson} | \
    while IFS=$'\t' read -r username home; do
      [ -n "$username" ] || continue
      [ -n "$home" ] || continue
      ${pkgs.getent}/bin/getent passwd "$username" >/dev/null || continue
      [ -d "$home/.local/share/flatpak" ] || continue

      while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        if ${pkgs.util-linux}/bin/runuser -u "$username" -- \
          ${pkgs.coreutils}/bin/env \
            HOME="$home" \
            XDG_DATA_HOME="$home/.local/share" \
            XDG_CONFIG_HOME="$home/.config" \
            XDG_CACHE_HOME="$home/.cache" \
            ${pkgs.flatpak}/bin/flatpak info --user "$ref" >/dev/null 2>&1; then
          ${pkgs.util-linux}/bin/runuser -u "$username" -- \
            ${pkgs.coreutils}/bin/env \
              HOME="$home" \
              XDG_DATA_HOME="$home/.local/share" \
              XDG_CONFIG_HOME="$home/.config" \
              XDG_CACHE_HOME="$home/.cache" \
              ${pkgs.flatpak}/bin/flatpak uninstall --user --noninteractive "$ref" || true
        fi
      done < ${desiredFile}
    done

    ${pkgs.coreutils}/bin/cp ${desiredFile} ${trackedFile}
  '';
in
{
  options.j0nix.desktop.apps.flatpak.entries = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        appId = lib.mkOption {
          type = lib.types.str;
          description = "Flatpak app id to manage declaratively.";
        };
        remote = lib.mkOption {
          type = lib.types.str;
          default = "flathub";
          description = "Flatpak remote to use for installs.";
        };
        remoteUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional remote URL to add before installing.";
        };
        branch = lib.mkOption {
          type = lib.types.str;
          default = "stable";
          description = "Flatpak branch to install, typically stable.";
        };
      };
    });
    default = [ ];
    description = "Flatpak apps that j0nix should install and remove declaratively.";
  };

  config = {
    services.flatpak.enable = entries != [ ];

    systemd.services.j0nix-flatpak-install = {
      description = "Install managed Flatpak applications";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = installScript;
        # Transient network failures (flathub fetch) must not leave the unit
        # in a failed state on switch/boot — retry the whole oneshot.
        Restart = "on-failure";
        RestartSec = "30s";
        RestartMaxDelaySec = "5min";
        RestartSteps = 5;
      };
    };

    systemd.services.j0nix-flatpak-prune = {
      description = "Prune unmanaged j0nix Flatpak applications";
      after = [ "j0nix-flatpak-install.service" ];
      requires = [ "j0nix-flatpak-install.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pruneScript;
      };
    };

    system.activationScripts.j0nixFlatpakSync = lib.stringAfter [ "users" "groups" ] ''
      if ${pkgs.systemd}/bin/systemctl list-unit-files j0nix-flatpak-prune.service >/dev/null 2>&1; then
        ${pkgs.systemd}/bin/systemctl daemon-reload >/dev/null 2>&1 || true
        ${pkgs.systemd}/bin/systemctl start j0nix-flatpak-prune.service >/dev/null 2>&1 || true
      fi
    '';
  };
}
