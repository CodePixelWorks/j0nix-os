{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.apps.flatpak;
  entries = lib.unique cfg.entries;
  entriesJson = pkgs.writeText "j0nix-flatpak-apps.json" (builtins.toJSON entries);
  stateDir = "/var/lib/j0nix/flatpak";
  trackedFile = "${stateDir}/tracked-apps";
  desiredFile = "${stateDir}/desired-apps";

  installScript = pkgs.writeShellScript "j0nix-flatpak-install" ''
    set -eu

    mkdir -p ${stateDir}
    : > ${desiredFile}

    if [ "$(${pkgs.jq}/bin/jq 'length' ${entriesJson})" -eq 0 ]; then
      exit 0
    fi

    ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system \
      flathub https://flathub.org/repo/flathub.flatpakrepo

    ${pkgs.jq}/bin/jq -r '.[] | [.remote, .appId] | @tsv' ${entriesJson} | \
    while IFS=$'\t' read -r remote appId; do
      [ -n "$appId" ] || continue
      if ! ${pkgs.flatpak}/bin/flatpak info --system "$appId" >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak install --system --noninteractive "$remote" "$appId"
      fi
      printf '%s\n' "$appId" >> ${desiredFile}
    done

    ${pkgs.coreutils}/bin/sort -u -o ${desiredFile} ${desiredFile}
  '';

  pruneScript = pkgs.writeShellScript "j0nix-flatpak-prune" ''
    set -eu

    mkdir -p ${stateDir}
    touch ${trackedFile} ${desiredFile}

    while IFS= read -r appId; do
      [ -n "$appId" ] || continue
      if ! ${pkgs.gnugrep}/bin/grep -Fxq "$appId" ${desiredFile}; then
        ${pkgs.flatpak}/bin/flatpak uninstall --system --noninteractive --delete-data "$appId" || true
      fi
    done < ${trackedFile}

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
