{ config, lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).keepassxc or { };
  hyprlandCfg = settings.hyprland or { };
  minimizerCfg = hyprlandCfg.minimizer or { };
  minimizerEnabled = minimizerCfg.enable or false;
  minimizerVariant = minimizerCfg.variant or "denis";
  minimizerPackage =
    if minimizerVariant == "0rteip" then
      if pkgs ? "hyprland-minimizer-orteip" then pkgs."hyprland-minimizer-orteip" else null
    else if pkgs ? "hyprland-minimizer" then
      pkgs."hyprland-minimizer"
    else
      null;
  minimizerDefaultCommand =
    if minimizerPackage != null then
      lib.getExe minimizerPackage
    else
      "hyprland-minimizer";
  minimizerCommand = minimizerCfg.command or minimizerDefaultCommand;
  minimizerOrteipCfg = minimizerCfg.orteip or { };
  minimizerOrteipAppId = minimizerOrteipCfg.appId or "keepassxc";

  enabled = cfg.enable or false;
  autoStart = cfg.autoStart or false;
  startMinimized = cfg.startMinimized or true;

  workspaceCfg = cfg.workspace or { };
  workspaceEnable = workspaceCfg.enable or true;
  workspaceMode = workspaceCfg.mode or (if minimizerEnabled then "minimizer" else "special-workspace");
  workspaceName = workspaceCfg.name or "passwords";
  workspaceUsesSpecial = workspaceEnable && workspaceMode == "special-workspace";
  workspaceUsesMinimizer = workspaceEnable && workspaceMode == "minimizer";

  autoUnlockCfg = cfg.autoUnlock or { };
  autoUnlockMode = autoUnlockCfg.mode or "strict";
  keyringEntry = autoUnlockCfg.keyringEntry or "keepassxc/default/main";
  passwordSecretName = autoUnlockCfg.sopsPasswordSecret or null;

  # With special workspace mode, --minimized is counterproductive. Keepass is hidden by workspace rules.
  effectiveStartMinimized = startMinimized && !(workspaceEnable && workspaceMode == "special-workspace") && !minimizerEnabled;

  databasePath = cfg.databasePath or null;
  databaseBasename =
    if hasValue databasePath then
      builtins.baseNameOf databasePath
    else
      "";
  databaseTitleHint =
    if databaseBasename != "" then
      lib.removeSuffix ".kdbx" databaseBasename
    else
      "";
  keyFileSecretName = cfg.keyFileSecretName or null;
  keyFileTargetName = cfg.keyFileTargetName or "startup.key";

  hasValue = value: value != null && value != "";

  keyFileSecretPath =
    if hasValue keyFileSecretName && lib.hasAttrByPath [ keyFileSecretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${keyFileSecretName}.path
    else if hasValue keyFileSecretName && lib.hasAttrByPath [ keyFileSecretName ] (config.sops.templates or { }) then
      config.sops.templates.${keyFileSecretName}.path
    else
      null;

  passwordSecretPath =
    if hasValue passwordSecretName && lib.hasAttrByPath [ passwordSecretName ] (config.sops.secrets or { }) then
      config.sops.secrets.${passwordSecretName}.path
    else if hasValue passwordSecretName && lib.hasAttrByPath [ passwordSecretName ] (config.sops.templates or { }) then
      config.sops.templates.${passwordSecretName}.path
    else
      null;

  keyFilePath = "${config.xdg.configHome}/keepassxc/keys/${keyFileTargetName}";
  keepassxcBin = "${pkgs.keepassxc}/bin/keepassxc";

  keyringCfg = ((settings.dev or { }).ssh or { }).keyring or { };
  sshAgentCfg = ((settings.dev or { }).ssh or { }).agent or { };
  keyringSupported = (keyringCfg.enable or false) || ((sshAgentCfg.provider or "openssh") == "gnome-keyring");

  startupScript = pkgs.writeShellScriptBin "keepassxc-startup" ''
    set -eu

    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    db_path=${lib.escapeShellArg (if databasePath != null then databasePath else "")}
    keepass_client_filter='
      .[]
      | select(
          ((.class // "") | test("keepassxc"; "i"))
          or ((.initialClass // "") | test("keepassxc"; "i"))
        )
    '
    lock_file="$XDG_RUNTIME_DIR/keepassxc-startup.lock"
    exec 9>"$lock_file"
    if ! ${pkgs.util-linux}/bin/flock -n 9; then
      # Another startup/toggle path is already launching KeePassXC.
      exit 0
    fi

    has_client() {
      [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
        && ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e "$keepass_client_filter" >/dev/null 2>&1
    }

    has_process() {
      ${pkgs.procps}/bin/pgrep -u "$(${pkgs.coreutils}/bin/id -u)" -f '/keepassxc($| )|/.keepassxc-wrapped($| )' >/dev/null 2>&1
    }

    if has_client; then
      exit 0
    fi

    launch_keepassxc() {
      if [ "${if autoUnlockMode == "strict" then "1" else "0"}" = "1" ]; then
        exec ${keepassxcBin} ${lib.optionalString effectiveStartMinimized "--minimized"}
      fi

      if [ -z "$db_path" ]; then
        echo "warning: keepassxc.databasePath is unset; falling back to plain KeepassXC startup" >&2
        exec ${keepassxcBin} ${lib.optionalString effectiveStartMinimized "--minimized"}
      fi

      base_args=()
      if [ "${if effectiveStartMinimized then "1" else "0"}" = "1" ]; then
        base_args+=(--minimized)
      fi
      if [ "${if keyFileSecretPath != null then "1" else "0"}" = "1" ]; then
        base_args+=(--keyfile ${lib.escapeShellArg keyFilePath})
      fi
      base_args+=("$db_path")

      if [ "${if autoUnlockMode == "balanced" then "1" else "0"}" = "1" ]; then
        exec ${keepassxcBin} "''${base_args[@]}"
      fi

      if [ "${if autoUnlockMode == "convenient" then "1" else "0"}" = "1" ]; then
        db_password="$(${pkgs.libsecret}/bin/secret-tool lookup application keepassxc entry ${lib.escapeShellArg keyringEntry} 2>/dev/null || true)"
        if [ -z "$db_password" ]; then
          echo "warning: missing keyring entry for ${keyringEntry}; falling back to balanced mode" >&2
          exec ${keepassxcBin} "''${base_args[@]}"
        fi
        printf '%s\n' "$db_password" | exec ${keepassxcBin} --pw-stdin "''${base_args[@]}"
      fi

      if [ "${if autoUnlockMode == "full-auto" then "1" else "0"}" = "1" ]; then
        db_password="$(${pkgs.libsecret}/bin/secret-tool lookup application keepassxc entry ${lib.escapeShellArg keyringEntry} 2>/dev/null || true)"
        if [ -z "$db_password" ]; then
          db_password="$(tr -d '\n' < ${lib.escapeShellArg (if passwordSecretPath != null then passwordSecretPath else "")})"
        fi
        if [ -z "$db_password" ]; then
          echo "warning: empty keepass password secret; falling back to balanced mode" >&2
          exec ${keepassxcBin} "''${base_args[@]}"
        fi
        if [ "${if keyringSupported then "1" else "0"}" = "1" ]; then
          printf '%s' "$db_password" | ${pkgs.libsecret}/bin/secret-tool store --label ${lib.escapeShellArg "KeePassXC ${keyringEntry}"} application keepassxc entry ${lib.escapeShellArg keyringEntry} >/dev/null 2>&1 || true
        fi
        printf '%s\n' "$db_password" | exec ${keepassxcBin} --pw-stdin "''${base_args[@]}"
      fi

      exec ${keepassxcBin} "''${base_args[@]}"
    }

    if [ "${if workspaceUsesSpecial then "1" else "0"}" = "1" ]; then
      (
        for _ in $(seq 1 80); do
          if ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e "$keepass_client_filter" >/dev/null 2>&1; then
            ${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspacesilent "special:${workspaceName}" >/dev/null 2>&1 || true
            exit 0
          fi
          sleep 0.1
        done
      ) &
    fi

    if [ "${if workspaceUsesMinimizer && minimizerEnabled then "1" else "0"}" = "1" ]; then
      (
        for _ in $(seq 1 50); do
          if ${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -e "$keepass_client_filter" >/dev/null 2>&1; then
            if [ "${minimizerVariant}" = "0rteip" ]; then
              ${minimizerCommand} ${minimizerOrteipAppId} >/dev/null 2>&1 || true
            else
              ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "class:^(KeePassXC)$" >/dev/null 2>&1 || true
              ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow "class:^(org\\.keepassxc\\.KeePassXC)$" >/dev/null 2>&1 || true
              ${minimizerCommand} >/dev/null 2>&1 || true
            fi
            exit 0
          fi
          sleep 0.2
        done
      ) &
    fi

    launch_keepassxc
  '';

  toggleScript = pkgs.writeShellScriptBin "keepassxc-toggle" ''
    set -eu

    hyprctl_bin="${pkgs.hyprland}/bin/hyprctl"
    jq_bin="${pkgs.jq}/bin/jq"
    startup_bin="${config.home.profileDirectory}/bin/keepassxc-startup"
    pgrep_bin="${pkgs.procps}/bin/pgrep"
    id_bin="${pkgs.coreutils}/bin/id"
    keepass_client_filter='
      .[]
      | select(
          ((.class // "") | test("keepassxc"; "i"))
          or ((.initialClass // "") | test("keepassxc"; "i"))
        )
    '
    locked_title_regex='^(KeePassXC|Unlock Database.*|Quick Unlock.*|Database Locked.*|Datenbank entsperren.*|Schnellentsperrung.*|Datenbank gesperrt.*)$'
    database_title_regex='${lib.concatStringsSep "|" (lib.filter (value: value != "") [
      (lib.escapeRegex databaseBasename)
      (lib.escapeRegex databaseTitleHint)
    ])}'

    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      exec "$startup_bin"
    fi

    has_client() {
      "$hyprctl_bin" clients -j | "$jq_bin" -e "$keepass_client_filter" >/dev/null 2>&1
    }

    has_process() {
      "$pgrep_bin" -u "$("$id_bin" -u)" -f '/keepassxc($| )|/.keepassxc-wrapped($| )' >/dev/null 2>&1
    }

    special_workspace_visible() {
      "$hyprctl_bin" monitors -j | "$jq_bin" -e '
        any(
          .[];
          ((.specialWorkspace.name // "") == "special:${workspaceName}")
          or ((.specialWorkspace.name // "") == "${workspaceName}")
        )
      ' >/dev/null 2>&1
    }

    ensure_workspace_visible() {
      special_workspace_visible \
        || "$hyprctl_bin" dispatch togglespecialworkspace ${lib.escapeShellArg workspaceName} >/dev/null 2>&1 \
        || true
    }

    client_title() {
      "$hyprctl_bin" clients -j | "$jq_bin" -r "[ $keepass_client_filter ][0].title // \"\""
    }

    client_looks_locked() {
      title="$(client_title)"
      [ -n "$title" ] || return 1
      printf '%s\n' "$title" | ${pkgs.gnugrep}/bin/grep -Eiq "$locked_title_regex" && return 0
      if [ -n "$database_title_regex" ]; then
        printf '%s\n' "$title" | ${pkgs.gnugrep}/bin/grep -Eiq "$database_title_regex" || return 0
      fi
      return 1
    }

    focus_keepass() {
      "$hyprctl_bin" dispatch focuswindow "class:^(KeePassXC)$" >/dev/null 2>&1 \
        || "$hyprctl_bin" dispatch focuswindow "class:^(org\\.keepassxc\\.KeePassXC)$" >/dev/null 2>&1 \
        || true
    }

    restart_keepass() {
      ${pkgs.procps}/bin/pkill -u "$("$id_bin" -u)" -f '/keepassxc($| )|/.keepassxc-wrapped($| )' >/dev/null 2>&1 || true
      for _ in $(seq 1 50); do
        has_process || break
        sleep 0.1
      done
      "$startup_bin" >/dev/null 2>&1 &
      for _ in $(seq 1 80); do
        has_client && break
        sleep 0.1
      done
    }

    if [ "${if workspaceEnable && workspaceMode == "minimizer" then "1" else "0"}" = "1" ] && [ "${if minimizerEnabled then "1" else "0"}" = "1" ]; then
      if [ "${minimizerVariant}" = "0rteip" ]; then
        exec ${minimizerCommand} ${minimizerOrteipAppId}
      else
        exec ${minimizerCommand}
      fi
    fi

    if has_client && client_looks_locked; then
      ensure_workspace_visible
      restart_keepass
      focus_keepass
      exit 0
    fi

    if ! has_client && has_process; then
      ensure_workspace_visible
      restart_keepass
      focus_keepass
      exit 0
    fi

    if ! has_client; then
      "$startup_bin" >/dev/null 2>&1 &
      for _ in $(seq 1 80); do
        has_client && break
        sleep 0.1
      done
    fi

    "$hyprctl_bin" dispatch togglespecialworkspace ${lib.escapeShellArg workspaceName} >/dev/null 2>&1 || true
    focus_keepass
  '';

  doctorScript = pkgs.writeShellScriptBin "keepassxc-doctor" ''
    set -eu
    echo "KeePassXC doctor"
    echo "- enabled: ${if enabled then "yes" else "no"}"
    echo "- autoUnlock.mode: ${autoUnlockMode}"
    echo "- workspace.mode: ${workspaceMode}"
    echo "- databasePath: ${if databasePath != null then databasePath else "<unset>"}"
    if [ -n ${lib.escapeShellArg (if databasePath != null then databasePath else "")} ]; then
      if [ -f ${lib.escapeShellArg (if databasePath != null then databasePath else "")} ]; then
        echo "- database file: present"
      else
        echo "- database file: missing"
      fi
    fi
    if [ -n ${lib.escapeShellArg (if keyFileSecretPath != null then keyFileSecretPath else "")} ]; then
      echo "- keyfile secret source: ${if keyFileSecretPath != null then keyFileSecretPath else ""}"
    fi
    if [ -f ${lib.escapeShellArg keyFilePath} ]; then
      echo "- keyfile deployed: yes (${keyFilePath})"
    else
      echo "- keyfile deployed: no (${keyFilePath})"
    fi
    if [ "${if autoUnlockMode == "convenient" then "1" else "0"}" = "1" ]; then
      if ${pkgs.libsecret}/bin/secret-tool lookup application keepassxc entry ${lib.escapeShellArg keyringEntry} >/dev/null 2>&1; then
        echo "- keyring entry: present (${keyringEntry})"
      else
        echo "- keyring entry: missing (${keyringEntry})"
      fi
    fi
    if [ "${if autoUnlockMode == "full-auto" then "1" else "0"}" = "1" ]; then
      if [ -f ${lib.escapeShellArg (if passwordSecretPath != null then passwordSecretPath else "")} ]; then
        echo "- password secret: present"
      else
        echo "- password secret: missing"
      fi
    fi
  '';

  keyringSetScript = pkgs.writeShellScriptBin "keepassxc-secret-set" ''
    set -eu
    entry="''${1:-${keyringEntry}}"
    if [ -z "$entry" ]; then
      echo "usage: keepassxc-secret-set [entry]" >&2
      exit 2
    fi
    printf "Enter KeePassXC password for %s: " "$entry" >&2
    password="$(${pkgs.systemd}/bin/systemd-ask-password "KeePassXC password for $entry")"
    if [ -z "$password" ]; then
      echo "error: empty password" >&2
      exit 1
    fi
    printf '%s' "$password" | ${pkgs.libsecret}/bin/secret-tool store --label "KeePassXC $entry" application keepassxc entry "$entry"
    echo "stored keyring entry: $entry"
  '';
in
lib.mkIf enabled {
  j0nix.user.software.packages = [
    pkgs.keepassxc
    pkgs.libsecret
    startupScript
    toggleScript
    doctorScript
    keyringSetScript
  ];

  xdg.configFile =
    (lib.mkIf (keyFileSecretPath != null) {
      "keepassxc/keys/${keyFileTargetName}".source = keyFileSecretPath;
    })
    // (lib.mkIf (workspaceEnable && workspaceMode == "minimizer" && minimizerVariant == "0rteip") {
      "hyprland-minimizer/config.toml".text = ''
        [apps.${minimizerOrteipAppId}]
        name = "KeePassXC"
        class = "KeePassXC"
        command = ["${config.home.profileDirectory}/bin/keepassxc-startup"]
        launch_in_background = true
      '';
    });

  systemd.user.services.keepassxc-startup = lib.mkIf autoStart {
    Unit = {
      Description = "KeePassXC startup database launcher";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${config.home.profileDirectory}/bin/keepassxc-startup";
      Restart = "on-abnormal";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  assertions = [
    {
      assertion = keyFileSecretName == null || keyFileSecretPath != null;
      message = "settings.userSettings.<name>.programs.keepassxc.keyFileSecretName must reference an existing per-user secret or template.";
    }
    {
      assertion = passwordSecretName == null || passwordSecretPath != null;
      message = "settings.userSettings.<name>.programs.keepassxc.autoUnlock.sopsPasswordSecret must reference an existing per-user secret or template.";
    }
    {
      assertion = databasePath == null || builtins.isString databasePath;
      message = "settings.userSettings.<name>.programs.keepassxc.databasePath must be a string path or null.";
    }
    {
      assertion = builtins.elem autoUnlockMode [ "strict" "balanced" "convenient" "full-auto" ];
      message = "settings.userSettings.<name>.programs.keepassxc.autoUnlock.mode must be one of: strict, balanced, convenient, full-auto";
    }
    {
      assertion = builtins.elem workspaceMode [ "special-workspace" "minimizer" ];
      message = "settings.userSettings.<name>.programs.keepassxc.workspace.mode must be one of: special-workspace, minimizer";
    }
    {
      assertion = autoUnlockMode != "convenient" || keyringSupported;
      message = "keepassxc autoUnlock.mode=convenient requires an enabled keyring (settings.userSettings.<name>.dev.ssh.keyring.enable=true or agent.provider=gnome-keyring).";
    }
    {
      assertion = autoUnlockMode != "full-auto" || hasValue passwordSecretName;
      message = "keepassxc autoUnlock.mode=full-auto requires autoUnlock.sopsPasswordSecret.";
    }
    {
      assertion = !(workspaceEnable && workspaceMode == "minimizer") || minimizerEnabled;
      message = "keepassxc workspace.mode=minimizer requires settings.userSettings.<name>.hyprland.minimizer.enable=true.";
    }
    {
      assertion = autoUnlockMode == "strict" || hasValue databasePath;
      message = "keepassxc autoUnlock.mode requires databasePath to be set.";
    }
    {
      assertion = workspaceName != "";
      message = "settings.userSettings.<name>.programs.keepassxc.workspace.name must not be empty.";
    }
  ];
}
