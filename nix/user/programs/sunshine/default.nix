{ config, lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).sunshine or { };
  webUiCfg = cfg.webUi or { };
  enabled = webUiCfg.enable or false;
  autoApply = webUiCfg.autoApply or true;
  username = webUiCfg.username or (settings.username or null);
  passwordSecretName = webUiCfg.passwordSecretName or null;

  hasValue = value: value != null && value != "";

  passwordSecretPath =
    if hasValue passwordSecretName && lib.hasAttrByPath [ passwordSecretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${passwordSecretName}.path
    else if hasValue passwordSecretName && lib.hasAttrByPath [ passwordSecretName ] (config.sops.templates or { }) then
      config.sops.templates.${passwordSecretName}.path
    else
      null;

  resetScript = pkgs.writeShellScriptBin "sunshine-reset-creds" ''
    set -eu

    username=${lib.escapeShellArg (if username != null then username else "")}
    secret_file=${lib.escapeShellArg (if passwordSecretPath != null then passwordSecretPath else "")}
    sunshine_bin=${lib.escapeShellArg "${pkgs.sunshine}/bin/sunshine"}
    tr_bin=${lib.escapeShellArg "${pkgs.coreutils}/bin/tr"}

    usage() {
      echo "usage: sunshine-reset-creds [--prompt]" >&2
    }

    if [ $# -gt 1 ]; then
      usage
      exit 1
    fi

    mode="''${1:-secret}"

    if [ -z "$username" ]; then
      echo "error: settings.userSettings.<name>.programs.sunshine.webUi.username must not be empty" >&2
      exit 1
    fi

    case "$mode" in
      secret)
        if [ -z "$secret_file" ]; then
          echo "error: no sunshine web password secret is configured; set programs.sunshine.webUi.passwordSecretName or use --prompt" >&2
          exit 1
        fi
        if [ ! -r "$secret_file" ]; then
          echo "error: sunshine web password secret is not readable: $secret_file" >&2
          exit 1
        fi
        password="$("$tr_bin" -d '\r\n' < "$secret_file")"
        ;;
      --prompt)
        stty_state="$(${pkgs.coreutils}/bin/stty -g)"
        cleanup() {
          ${pkgs.coreutils}/bin/stty "$stty_state" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT HUP INT TERM
        printf 'New Sunshine Web UI password for %s: ' "$username" >&2
        ${pkgs.coreutils}/bin/stty -echo
        IFS= read -r password
        printf '\nConfirm password: ' >&2
        IFS= read -r confirm
        ${pkgs.coreutils}/bin/stty echo
        printf '\n' >&2
        if [ "$password" != "$confirm" ]; then
          echo "error: passwords do not match" >&2
          exit 1
        fi
        ;;
      *)
        usage
        exit 1
        ;;
    esac

    if [ -z "$password" ]; then
      echo "error: sunshine web password must not be empty" >&2
      exit 1
    fi

    exec "$sunshine_bin" --creds "$username" "$password"
  '';
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ resetScript ];

  home.activation.sunshineWebUiCredentials =
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if autoApply && passwordSecretPath != null then
        ''
          if ${lib.getExe resetScript} >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/systemctl --user try-restart sunshine.service >/dev/null 2>&1 || true
          else
            echo "warning: failed to apply Sunshine Web UI credentials from secret '${passwordSecretName}'" >&2
          fi
        ''
      else
        ":"
    );

  assertions = [
    {
      assertion = hasValue username;
      message = "settings.userSettings.<name>.programs.sunshine.webUi.username must not be empty when Sunshine Web UI credential management is enabled.";
    }
    {
      assertion = !hasValue passwordSecretName || passwordSecretPath != null;
      message = "settings.userSettings.<name>.programs.sunshine.webUi.passwordSecretName must reference an existing per-user secret or template.";
    }
  ];
}
