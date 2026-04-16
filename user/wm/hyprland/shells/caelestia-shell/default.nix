{
  inputs,
  lib,
  pkgs,
  settings,
  ...
}:
let
  listMerge = import ../../../../../system/lib/list-merge.nix { inherit lib; };
  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemeName = iconThemeCfg.name or "Papirus-Dark";
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then pkgs."colloid-icon-theme" else null
    else if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "adwaita" then
      pkgs.adwaita-icon-theme
    else if iconThemePackageKey == "breeze" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? breeze-icons) then
        pkgs.kdePackages.breeze-icons
      else if pkgs ? breeze-icons then
        pkgs.breeze-icons
      else
        null
    else
      null;
  dmsSettings = settings.dms or { };
  caelestiaSettings = (settings.programs or { }).caelestia or { };
  caelestiaThemeSettings = caelestiaSettings.theme or { };
  quickshellRuntime = caelestiaSettings.quickshellRuntime or "wrapped";
  caelestiaChannel = caelestiaSettings.channel or "stable";
  caelestiaInputName = if caelestiaChannel == "dev" then "caelestia-shell-dev" else "caelestia-shell";
  hasValue = value: value != null && value != "";
  selectedInput =
    if caelestiaChannel == "dev" then
      (if inputs ? caelestia-shell-dev then inputs.caelestia-shell-dev else null)
    else if inputs ? caelestia-shell then
      inputs.caelestia-shell
    else
      null;
  dmsWallpaper = dmsSettings.wallpaper or { };
  configuredWallpaper = dmsWallpaper.wallpaperPath or null;
  configuredWallpaperDir =
    if configuredWallpaper != null && lib.hasInfix "/" configuredWallpaper then
      lib.removeSuffix "/${builtins.baseNameOf configuredWallpaper}" configuredWallpaper
    else
      null;
  hasInput = selectedInput != null;
  useUpstreamQuickshell = builtins.elem quickshellRuntime [
    "upstream"
    "upstream-dev"
  ];
  quickshellInput =
    if hasInput && (selectedInput ? inputs) && (selectedInput.inputs ? quickshell) then
      selectedInput.inputs.quickshell
    else
      null;
  quickshellSource =
    if quickshellInput != null then (quickshellInput.outPath or quickshellInput) else null;
  quickshellRev =
    if quickshellInput != null && (quickshellInput ? rev) then quickshellInput.rev else null;
  cpptraceWithLibunwind = pkgs.cpptrace.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.libunwind ];
    propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ pkgs.libunwind ];
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ (lib.cmakeBool "CPPTRACE_UNWIND_WITH_LIBUNWIND" true) ];
  });
  upstreamQuickshellFromSource =
    if useUpstreamQuickshell && quickshellSource != null then
      pkgs.quickshell.overrideAttrs (old: {
        pname = "quickshell-upstream";
        version =
          if quickshellRev != null then
            "unstable-${builtins.substring 0 8 quickshellRev}"
          else
            "unstable-dev";
        src = quickshellSource;
        buildInputs = (old.buildInputs or [ ]) ++ [
          cpptraceWithLibunwind
          pkgs.libsysprof-capture
          pkgs.polkit
        ];
        cmakeFlags =
          (lib.filter (flag: !(lib.hasInfix "GIT_REVISION" flag)) (old.cmakeFlags or [ ]))
          ++ lib.optional (quickshellRev != null) (lib.cmakeFeature "GIT_REVISION" quickshellRev);
      })
    else
      null;
  hasQuickshellInputPackages =
    !useUpstreamQuickshell
    && quickshellInput != null
    && (quickshellInput ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system quickshellInput.packages);
  quickshellInputPackageSet =
    if hasQuickshellInputPackages then
      quickshellInput.packages.${pkgs.stdenv.hostPlatform.system}
    else
      { };
  upstreamQuickshellPkg =
    if upstreamQuickshellFromSource != null then
      upstreamQuickshellFromSource
    else if quickshellInputPackageSet ? quickshell then
      quickshellInputPackageSet.quickshell
    else if quickshellInputPackageSet ? default then
      quickshellInputPackageSet.default
    else
      null;
  hasSystemPackages =
    hasInput
    && (selectedInput ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system selectedInput.packages);
  packageSet =
    if hasSystemPackages then selectedInput.packages.${pkgs.stdenv.hostPlatform.system} else { };
  caelestiaShellPkg =
    if packageSet ? default then
      packageSet.default
    else if packageSet ? caelestia-shell then
      packageSet.caelestia-shell
    else if packageSet ? with-cli then
      packageSet.with-cli
    else
      null;
  caelestiaCliInput =
    if hasInput && (selectedInput ? inputs) && (selectedInput.inputs ? caelestia-cli) then
      selectedInput.inputs.caelestia-cli
    else
      null;
  hasCliSystemPackages =
    caelestiaCliInput != null
    && (caelestiaCliInput ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system caelestiaCliInput.packages);
  cliPackageSet =
    if hasCliSystemPackages then caelestiaCliInput.packages.${pkgs.stdenv.hostPlatform.system} else { };
  upstreamCaelestiaCliPkg =
    if cliPackageSet ? default then
      cliPackageSet.default
    else if cliPackageSet ? caelestia-cli then
      cliPackageSet.caelestia-cli
    else
      null;
  caelestiaCliSchemeSourceDir =
    if caelestiaCliInput != null then "${caelestiaCliInput}/src/caelestia/data/schemes" else null;
  caelestiaCliPkg =
    if upstreamCaelestiaCliPkg != null && hasValue caelestiaCliSchemeSourceDir then
      upstreamCaelestiaCliPkg.overrideAttrs (old: {
        patchPhase =
          (old.patchPhase or "")
          + "\n"
          + ''
            substituteInPlace src/caelestia/utils/material/generator.py \
              --replace-fail 'from materialyoucolor.dynamiccolor.dynamic_scheme import DynamicScheme' \
                             'from materialyoucolor.scheme.dynamic_scheme import DynamicScheme'
          '';
        postInstall =
          (old.postInstall or "")
          + "\n"
          + ''
            target="$out/${pkgs.python3.sitePackages}/caelestia/data/schemes"
            rm -rf "$target"
            mkdir -p "$(dirname "$target")"
            cp -r ${caelestiaCliSchemeSourceDir} "$target"
          '';
      })
    else
      null;
  configuredScheme = caelestiaThemeSettings.scheme or (settings.theme or null);
  configuredFlavour = caelestiaThemeSettings.flavour or null;
  configuredMode = caelestiaThemeSettings.mode or null;
  configuredVariant = caelestiaThemeSettings.variant or null;
  explicitThemeRequested = builtins.any hasValue [
    configuredScheme
    configuredFlavour
    configuredMode
    configuredVariant
  ];
  smartSchemeConfigured = caelestiaThemeSettings ? smartScheme;
  smartSchemeEnabled =
    if smartSchemeConfigured then caelestiaThemeSettings.smartScheme else !explicitThemeRequested;
  manualThemeApply = explicitThemeRequested && !smartSchemeEnabled;
  themeApplyArgs = lib.concatStringsSep " " (
    lib.optionals (hasValue configuredScheme) [ "-n ${lib.escapeShellArg configuredScheme}" ]
    ++ lib.optionals (hasValue configuredFlavour) [ "-f ${lib.escapeShellArg configuredFlavour}" ]
    ++ lib.optionals (hasValue configuredMode) [ "-m ${lib.escapeShellArg configuredMode}" ]
    ++ lib.optionals (hasValue configuredVariant) [ "-v ${lib.escapeShellArg configuredVariant}" ]
  );
  hyprlandCfg = settings.hyprland or { };
  keepassCfg = (settings.programs or { }).keepassxc or { };
  keepassEnabled = keepassCfg.enable or false;
  keepassWorkspaceCfg = keepassCfg.workspace or { };
  keepassWorkspaceEnable = keepassWorkspaceCfg.enable or true;
  minimizerEnabled = ((hyprlandCfg.minimizer or { }).enable or false);
  keepassWorkspaceMode =
    keepassWorkspaceCfg.mode or (if minimizerEnabled then "minimizer" else "special-workspace");
  keepassWorkspaceName = keepassWorkspaceCfg.name or "passwords";
  keepassSpecialWorkspaceEnabled =
    keepassEnabled && keepassWorkspaceEnable && keepassWorkspaceMode == "special-workspace";
  specialWorkspaceIcons = [
    {
      name = "discord";
      icon = "forum";
    }
    {
      name = "media";
      icon = "music_note";
    }
    {
      name = "sysmon";
      icon = "monitoring";
    }
  ]
  ++ lib.optionals keepassSpecialWorkspaceEnabled [
    {
      name = keepassWorkspaceName;
      icon = "password";
    }
  ];
  preferredTerminal = settings.preferredTerminal or "kitty";
  materialIconFontDefault = "Material Symbols Rounded";
  materialIconFontAllowed = [
    "Material Symbols Rounded"
    "Material Symbols Outlined"
    "Material Symbols Sharp"
  ];
  materialIconFontAllowedJson = builtins.toJSON materialIconFontAllowed;
  seededCaelestiaConfig = {
    appearance = {
      font = {
        family = {
          material = materialIconFontDefault;
        };
      };
    };
    general = {
      apps = {
        terminal = [ preferredTerminal ];
      };
      idle = {
        lockBeforeSleep = true;
        timeouts = [ ];
      };
    };
    launcher = {
      actions = [
        {
          name = "Shutdown";
          command = [
            "system-power-action"
            "poweroff"
          ];
        }
        {
          name = "Reboot";
          command = [
            "system-power-action"
            "reboot"
          ];
        }
        {
          name = "Sleep";
          command = [
            "system-power-action"
            "suspend"
          ];
        }
        {
          name = "Auto Theme";
          command = [
            "caelestia-smart-theme"
            "enable"
          ];
        }
        {
          name = "Manual Theme";
          command = [
            "caelestia-smart-theme"
            "disable"
          ];
        }
      ]
      ++ lib.optionals keepassEnabled [
        {
          name = "Passwords";
          command = [ "keepassxc-toggle" ];
        }
      ];
    };
    session = {
      commands = {
        shutdown = [
          "system-power-action"
          "poweroff"
        ];
        hibernate = [
          "system-power-action"
          "hibernate"
        ];
        reboot = [
          "system-power-action"
          "reboot"
        ];
      };
    };
    services = {
      smartScheme = smartSchemeEnabled;
    };
    theme = {
      enableGtk = false;
      enableQt = false;
    };
  }
  // lib.optionalAttrs (configuredWallpaperDir != null && configuredWallpaperDir != "") {
    paths = {
      wallpaperDir = configuredWallpaperDir;
    };
  }
  // {
    bar = {
      workspaces = {
        specialWorkspaceIcons = specialWorkspaceIcons;
      };
    };
  };
  seededWallpaperDirValue =
    if configuredWallpaperDir != null && configuredWallpaperDir != "" then
      configuredWallpaperDir
    else
      "";
  shellRuntimePackages = with pkgs; [
    libnotify
    procps
    wl-clipboard
    cliphist
    # Caelestia runtime/tooling dependencies.
    ddcutil
    app2unit
    cava
    fish
    aubio
    qt6.qtbase
    qt6.qtdeclarative
    stdenv.cc.cc.lib
    libqalculate
    cmake
    ninja
    # Caelestia shell screen recording actions expect these in PATH.
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    matugen
    hicolor-icon-theme
    adwaita-icon-theme
    papirus-icon-theme
  ];
  shellFontPackages = with pkgs; [
    material-symbols
    nerd-fonts.caskaydia-cove
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];
  shellScriptPackages = with pkgs; [
    (writeShellScriptBin "caelestia-start" ''
      # Keep shell startup idempotent when wm-shell-start is triggered multiple times.
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      state_dir="$runtime_dir/caelestia-shell"
      supervisor_pid_file="$state_dir/supervisor.pid"
      supervisor_lock_file="$state_dir/supervisor.lock"
      flock_bin="${pkgs.util-linux}/bin/flock"

      mkdir -p "$state_dir"

      exec 9>"$supervisor_lock_file"
      if ! "$flock_bin" -n 9; then
        exit 0
      fi

      shell_processes_running() {
        if command -v qs >/dev/null 2>&1 && qs ipc -c caelestia call shell ping >/dev/null 2>&1; then
          return 0
        fi
        ${procps}/bin/pgrep -f 'quickshell.*-c[[:space:]]*caelestia' >/dev/null 2>&1 && return 0
        ${procps}/bin/pgrep -f '/share/caelestia-shell' >/dev/null 2>&1 && return 0
        return 1
      }

      if [ -f "$supervisor_pid_file" ]; then
        existing_pid="$(${coreutils}/bin/cat "$supervisor_pid_file" 2>/dev/null || true)"
        if [ -n "''${existing_pid:-}" ] && ${procps}/bin/kill -0 "$existing_pid" >/dev/null 2>&1; then
          exit 0
        fi
        rm -f "$supervisor_pid_file"
      fi

      echo $$ >"$supervisor_pid_file"
      cleanup_supervisor_state() {
        current_pid="$(${coreutils}/bin/cat "$supervisor_pid_file" 2>/dev/null || true)"
        if [ "''${current_pid:-}" = "$$" ]; then
          rm -f "$supervisor_pid_file"
        fi
      }
      trap cleanup_supervisor_state EXIT INT TERM

      if shell_processes_running; then
        exit 0
      fi

      append_unique_colon_path() {
        # Keep Quickshell desktop-entry rescans stable by avoiding duplicated search roots.
        # Duplicate XDG_DATA_DIRS entries cause repeated app replacement churn in Quickshell.
        local current="$1"
        local item="$2"
        local part

        [ -n "$item" ] || { printf '%s' "$current"; return 0; }

        IFS=':'
        for part in $current; do
          if [ "$part" = "$item" ]; then
            printf '%s' "$current"
            return 0
          fi
        done
        unset IFS

        if [ -n "$current" ]; then
          printf '%s:%s' "$current" "$item"
        else
          printf '%s' "$item"
        fi
      }

      ${lib.optionalString iconThemeEnabled ''
        export XDG_ICON_THEME="${iconThemeName}"
        export GTK_ICON_THEME="${iconThemeName}"
        export QT_ICON_THEME_NAME="${iconThemeName}"
        export QT_QUICK_CONTROLS_ICON_THEME_NAME="${iconThemeName}"
      ''}
      # Quickshell app icons are resolved through freedesktop icon lookup paths.
      # UWSM/systemd user sessions can miss Home Manager profile paths here.
      # Keep the list deduplicated to avoid repeated desktop-entry replacement churn.
      xdg_data_dirs=""
      for d in ${
        lib.concatStringsSep " " (
          [
            ''"$HOME/.nix-profile/share"''
            ''"/etc/profiles/per-user/$USER/share"''
            ''"/run/current-system/sw/share"''
            ''"$HOME/.local/share/flatpak/exports/share"''
            ''"/var/lib/flatpak/exports/share"''
          ]
          ++ lib.optionals (iconThemePackage != null) [ ''"${iconThemePackage}/share"'' ]
          ++ [
            ''"${hicolor-icon-theme}/share"''
            ''"${adwaita-icon-theme}/share"''
            ''"${papirus-icon-theme}/share"''
          ]
        )
      }; do
        xdg_data_dirs="$(append_unique_colon_path "$xdg_data_dirs" "$d")"
      done
      IFS=':'
      for d in ''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        xdg_data_dirs="$(append_unique_colon_path "$xdg_data_dirs" "$d")"
      done
      unset IFS
      export XDG_DATA_DIRS="$xdg_data_dirs"
      unset xdg_data_dirs d

      # Prefer the conservative render loop for shell stability on NVIDIA/QtQuick.
      export QSG_RENDER_LOOP="''${QSG_RENDER_LOOP:-basic}"
      # Caelestia actions (e.g. screen recording) execute from the shell process env.
      # Ensure GPU Screen Recorder binaries are resolvable even if the session PATH is incomplete.
      export PATH="/run/wrappers/bin:${
        lib.makeBinPath [
          gpu-screen-recorder
          gpu-screen-recorder-gtk
        ]
      }:$PATH"
      upstream_runtime="${if useUpstreamQuickshell then "1" else "0"}"
      hyprctl_bin="${lib.getExe' pkgs.hyprland "hyprctl"}"
      jq_bin="${pkgs.jq}/bin/jq"

      repair_caelestia_shell_config() {
        local cfg_dir cfg_file tmp_file

        cfg_dir="$HOME/.config/caelestia"
        cfg_file="$cfg_dir/shell.json"
        tmp_file="$cfg_file.codex-font-tmp"

        [ -f "$cfg_file" ] || return 0
        "$jq_bin" -e . "$cfg_file" >/dev/null 2>&1 || return 0

        "$jq_bin" \
          --arg defaultMaterial "${materialIconFontDefault}" \
          --argjson allowedFonts '${materialIconFontAllowedJson}' '
          def as_num($default):
            if type == "number" then . else $default end;
          def clamp($min; $max):
            if . < $min then $min elif . > $max then $max else . end;
          .general = (.general // {})
          | .general.idle = (.general.idle // {})
          | if ((.general.idle.timeouts? | type) == "array") then
              .general.idle.timeouts = (
                .general.idle.timeouts
                | map(
                    if (.timeout? == 600 and ((.idleAction? == ["systemctl", "suspend-then-hibernate"]) or (.idleAction? == ["system-suspend-then-hibernate-safe"]))) then
                      .idleAction = ["system-power-action", "suspend-then-hibernate"]
                    else
                      .
                    end
                  )
                | map(select(.idleAction? != ["system-power-action", "suspend-then-hibernate"]))
              )
            else
              .
            end
          | .launcher = (.launcher // {})
          | if ((.launcher.actions? | type) == "array") then
              .launcher.actions = (
                .launcher.actions
                | map(select(.name? != "Hibernate"))
                | map(
                    if (.name? == "Sleep") then
                      .command = ["system-power-action", "suspend"]
                    elif (.name? == "Shutdown") then
                      .command = ["system-power-action", "poweroff"]
                    elif (.name? == "Reboot") then
                      .command = ["system-power-action", "reboot"]
                    else
                      .
                    end
                  )
              )
            else
              .
            end
          | .session = (.session // {})
          | .session.commands = (
              (.session.commands // {})
              | .hibernate = ["system-power-action", "hibernate"]
              | .shutdown = ["system-power-action", "poweroff"]
              | .reboot = ["system-power-action", "reboot"]
            )
          | .appearance = (.appearance // {})
          | .appearance.font = (.appearance.font // {})
          | .appearance.font.family = (.appearance.font.family // {})
          | .appearance.font.family.material = (
              (.appearance.font.family.material? // "") as $materialFont
              | ($materialFont | tostring) as $materialFontString
              | if ($allowedFonts | index($materialFontString)) != null then
                  $materialFontString
                else
                  $defaultMaterial
                end
            )
          | .appearance.padding = (.appearance.padding // {})
          | .appearance.padding.scale = ((.appearance.padding.scale // 1) | as_num(1) | clamp(0.5; 2.0))
          | .appearance.spacing = (.appearance.spacing // {})
          | .appearance.spacing.scale = ((.appearance.spacing.scale // 1) | as_num(1) | clamp(0.5; 2.0))
          | .appearance.rounding = (.appearance.rounding // {})
          | .appearance.rounding.scale = ((.appearance.rounding.scale // 1) | as_num(1) | clamp(0.5; 2.0))
          | .appearance.font.size = (.appearance.font.size // {})
          | .appearance.font.size.scale = ((.appearance.font.size.scale // 1) | as_num(1) | clamp(0.5; 2.0))
        ' "$cfg_file" >"$tmp_file" \
          && mv -f "$tmp_file" "$cfg_file"
      }

      ensure_hyprland_global_submap() {
        local attempts=0

        [ -x "$hyprctl_bin" ] || return 0

        while [ "$attempts" -lt 50 ]; do
          if "$hyprctl_bin" -j activeworkspace >/dev/null 2>&1; then
            "$hyprctl_bin" dispatch submap global >/dev/null 2>&1 || true
            return 0
          fi
          attempts=$((attempts + 1))
          sleep 0.1
        done

        return 0
      }

      launch_shell_once() {
        if [ "$upstream_runtime" = "1" ]; then
          if command -v caelestia-shell >/dev/null 2>&1; then
            caelestia-shell &
            shell_pid=$!
            return 0
          fi
          return 127
        fi

        if command -v caelestia >/dev/null 2>&1; then
          caelestia shell -d &
          shell_pid=$!
          return 0
        fi

        if command -v caelestia-shell >/dev/null 2>&1; then
          caelestia-shell &
          shell_pid=$!
          return 0
        fi

        return 127
      }

      # Quickshell can occasionally crash in the Hyprland IPC bridge.
      # Keep the shell available by restarting a few times before giving up.
      restart_window_s=120
      max_restarts=6
      first_restart_at=0
      restart_count=0

      if command -v caelestia-gamemode-fan-sync >/dev/null 2>&1; then
        caelestia-gamemode-fan-sync start >/dev/null 2>&1 || true
      fi

      repair_caelestia_shell_config

      ${lib.optionalString (smartSchemeEnabled || manualThemeApply) ''
        if command -v caelestia-apply-theme >/dev/null 2>&1; then
          caelestia-apply-theme >/dev/null 2>&1 || true
        fi
      ''}

      while true; do
        ensure_hyprland_global_submap

        if ! launch_shell_once; then
          echo "Neither 'caelestia' nor 'caelestia-shell' is in PATH."
          echo "Rebuild and verify wmShell=caelestia-shell."
          exit 1
        fi

        wait "$shell_pid"
        exit_code=$?

        # Manual stop/restart should terminate cleanly without respawn.
        if [ "$exit_code" -eq 0 ]; then
          exit 0
        fi

        now="$(${coreutils}/bin/date +%s)"
        if [ "$first_restart_at" -eq 0 ] || [ $((now - first_restart_at)) -gt "$restart_window_s" ]; then
          first_restart_at="$now"
          restart_count=0
        fi
        restart_count=$((restart_count + 1))

        if [ "$restart_count" -ge "$max_restarts" ]; then
          if command -v notify-send >/dev/null 2>&1; then
            notify-send "Caelestia shell crashed repeatedly" "Use Super+R (wm-shell-recover) to restart manually." >/dev/null 2>&1 || true
          fi
          echo "caelestia-start: shell exited with code $exit_code too often in ${toString 120}s; stopping auto-restart" >&2
          exit "$exit_code"
        fi

        sleep 0.5
      done
    '')

    (writeShellScriptBin "caelestia-gamemode-fan-sync" ''
      set -eu

      state_dir="''${XDG_RUNTIME_DIR:-/tmp}/caelestia-gamemode-fan-sync"
      pid_file="$state_dir/pid"
      mkdir -p "$state_dir"

      qs_bin="$(command -v qs || true)"
      fan_cmd="$(command -v thermal-fan-max || true)"

      sync_once() {
        [ -n "$qs_bin" ] || return 0
        [ -n "$fan_cmd" ] || return 0
        enabled="$($qs_bin ipc -c caelestia call gameMode isEnabled 2>/dev/null | ${coreutils}/bin/tr -d '\r\n' || true)"
        case "$enabled" in
          true|1|\"true\")
            "$fan_cmd" start >/dev/null 2>&1 || true
            ;;
          false|0|\"false\")
            "$fan_cmd" end >/dev/null 2>&1 || true
            ;;
          *)
            ;;
        esac
      }

      run_loop() {
        # Apply current state immediately, then follow Caelestia RPC signal changes.
        sync_once
        while true; do
          [ -n "$qs_bin" ] || exit 0
          if ! "$qs_bin" ipc -c caelestia listen gameMode enabledChanged 2>/dev/null | while IFS= read -r _; do
            sync_once
          done; then
            sleep 1
            sync_once
          fi
          sleep 1
        done
      }

      case "''${1:-}" in
        start)
          if [ -f "$pid_file" ]; then
            old_pid="$(${coreutils}/bin/cat "$pid_file" 2>/dev/null || true)"
            if [ -n "''${old_pid:-}" ] && ${procps}/bin/kill -0 "$old_pid" >/dev/null 2>&1; then
              exit 0
            fi
          fi
          run_loop &
          echo $! >"$pid_file"
          ;;
        stop)
          if [ -f "$pid_file" ]; then
            old_pid="$(${coreutils}/bin/cat "$pid_file" 2>/dev/null || true)"
            if [ -n "''${old_pid:-}" ]; then
              ${procps}/bin/kill "$old_pid" >/dev/null 2>&1 || true
            fi
            rm -f "$pid_file"
          fi
          if [ -n "$fan_cmd" ]; then
            "$fan_cmd" end >/dev/null 2>&1 || true
          fi
          ;;
        *)
          echo "usage: caelestia-gamemode-fan-sync <start|stop>" >&2
          exit 2
          ;;
      esac
    '')

    (writeShellScriptBin "caelestia-stop" ''
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      state_dir="$runtime_dir/caelestia-shell"
      supervisor_pid_file="$state_dir/supervisor.pid"
      supervisor_lock_file="$state_dir/supervisor.lock"

      shell_processes_running() {
        ${procps}/bin/pgrep -f '/bin/caelestia-start' >/dev/null 2>&1 && return 0
        ${procps}/bin/pgrep -f 'quickshell.*-c[[:space:]]*caelestia' >/dev/null 2>&1 && return 0
        ${procps}/bin/pgrep -f '/share/caelestia-shell' >/dev/null 2>&1 && return 0
        return 1
      }

      wait_for_shell_shutdown() {
        local attempts=0

        while [ "$attempts" -lt 50 ]; do
          if ! shell_processes_running; then
            return 0
          fi
          attempts=$((attempts + 1))
          sleep 0.1
        done

        return 0
      }

      if [ -f "$supervisor_pid_file" ]; then
        supervisor_pid="$(${coreutils}/bin/cat "$supervisor_pid_file" 2>/dev/null || true)"
        if [ -n "''${supervisor_pid:-}" ]; then
          ${procps}/bin/kill "$supervisor_pid" >/dev/null 2>&1 || true
          for _ in $(seq 1 20); do
            ${procps}/bin/kill -0 "$supervisor_pid" >/dev/null 2>&1 || break
            sleep 0.1
          done
        fi
        rm -f "$supervisor_pid_file"
      fi

      if command -v caelestia-gamemode-fan-sync >/dev/null 2>&1; then
        caelestia-gamemode-fan-sync stop >/dev/null 2>&1 || true
      fi
      if command -v caelestia >/dev/null 2>&1; then
        caelestia shell quit >/dev/null 2>&1 || true
      fi
      if command -v caelestia-shell >/dev/null 2>&1; then
        ${procps}/bin/pkill -x caelestia-shell >/dev/null 2>&1 || true
      fi
      if command -v qs >/dev/null 2>&1; then
        qs kill caelestia >/dev/null 2>&1 || true
      fi
      if command -v quickshell >/dev/null 2>&1; then
        quickshell kill caelestia >/dev/null 2>&1 || true
      fi
      ${procps}/bin/pkill -f '/share/caelestia-shell' >/dev/null 2>&1 || true
      ${procps}/bin/pkill -f 'quickshell.*-c[[:space:]]*caelestia' >/dev/null 2>&1 || true
      ${procps}/bin/pkill -f '/bin/caelestia-start' >/dev/null 2>&1 || true
      wait_for_shell_shutdown
      rm -f "$supervisor_pid_file" "$supervisor_lock_file"
    '')

    (writeShellScriptBin "caelestia-apply-theme" ''
      set -eu

      if ! command -v caelestia >/dev/null 2>&1; then
        exit 0
      fi

      ${
        if smartSchemeEnabled then
          ''
            exec caelestia scheme set -n dynamic
          ''
        else if manualThemeApply then
          ''
            exec caelestia scheme set ${themeApplyArgs}
          ''
        else
          ''
            exit 0
          ''
      }
    '')

    (writeShellScriptBin "caelestia-smart-theme" ''
            set -eu

            cfg_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/caelestia"
            cfg_file="$cfg_dir/shell.json"
            tmp_file="$cfg_file.codex-tmp"

            mkdir -p "$cfg_dir"
            if [ ! -f "$cfg_file" ]; then
              cat >"$cfg_file" <<'EOF'
      ${builtins.toJSON seededCaelestiaConfig}
      EOF
            fi

            case "''${1:-toggle}" in
              enable)
                ${pkgs.jq}/bin/jq '.services = ((.services // {}) | .smartScheme = true)' "$cfg_file" >"$tmp_file"
                mv "$tmp_file" "$cfg_file"
                if command -v caelestia >/dev/null 2>&1; then
                  caelestia scheme set -n dynamic >/dev/null 2>&1 || true
                fi
                ;;
              disable)
                ${pkgs.jq}/bin/jq '.services = ((.services // {}) | .smartScheme = false)' "$cfg_file" >"$tmp_file"
                mv "$tmp_file" "$cfg_file"
                if command -v caelestia >/dev/null 2>&1; then
                  ${
                    if manualThemeApply then
                      ''
                        caelestia scheme set ${themeApplyArgs} >/dev/null 2>&1 || true
                      ''
                    else
                      ''
                        true
                      ''
                  }
                fi
                ;;
              *)
                echo "usage: caelestia-smart-theme <enable|disable>" >&2
                exit 2
                ;;
            esac
    '')
  ];
  caelestiaUpstreamShellWrapper =
    if useUpstreamQuickshell && upstreamQuickshellPkg != null && caelestiaShellPkg != null then
      lib.hiPrio (
        pkgs.writeShellScriptBin "caelestia-shell" ''
              set -eu
              export PATH="${
                lib.makeBinPath [
                  pkgs.fish
                  pkgs.ddcutil
                  pkgs.brightnessctl
                  pkgs.app2unit
                  pkgs.networkmanager
                  pkgs.lm_sensors
                  pkgs.swappy
                  pkgs.wl-clipboard
                  pkgs.libqalculate
                  pkgs.bashInteractive
                  pkgs.hyprland
                ]
              }:$PATH"
              export CAELESTIA_XKB_RULES_PATH="${pkgs.xkeyboard-config}/share/X11/xkb/rules/base.lst"

              # Keep optional native helper lookups compatible with the upstream wrapper.
              if [ -z "''${CAELESTIA_LIB_DIR:-}" ] && [ -x "${caelestiaShellPkg}/bin/caelestia-shell" ]; then
                guessed_lib_dir="$(${pkgs.binutils}/bin/strings ${lib.escapeShellArg "${caelestiaShellPkg}/bin/caelestia-shell"} | ${pkgs.gnugrep}/bin/grep -m1 '/caelestia-extras/lib' || true)"
                if [ -n "$guessed_lib_dir" ]; then
                  export CAELESTIA_LIB_DIR="$guessed_lib_dir"
                fi
              fi

          # Use correct QML paths for upstream quickshell + caelestia-qml-plugin
          # The caelestia-shell package includes caelestia-qml-plugin as a runtime dependency
          quickshell_qml="${upstreamQuickshellPkg}/lib/qt-6/qml"
          caelestia_qml="${caelestiaShellPkg}/lib/qt-6/qml"

          # Add quickshell upstream QML path
          if [ -d "$quickshell_qml" ]; then
            export NIXPKGS_QT6_QML_IMPORT_PATH="''${NIXPKGS_QT6_QML_IMPORT_PATH:+''${NIXPKGS_QT6_QML_IMPORT_PATH}:}$quickshell_qml"
          fi

          # Add caelestia QML path if it exists in the caelestia-shell package
          if [ -d "$caelestia_qml" ]; then
            export NIXPKGS_QT6_QML_IMPORT_PATH="''${NIXPKGS_QT6_QML_IMPORT_PATH:+''${NIXPKGS_QT6_QML_IMPORT_PATH}:}$caelestia_qml"
          fi

          # Find caelestia-qml-plugin from caelestia-shell dependencies and add its QML path
          for qs_path in ${caelestiaShellPkg}/lib/qt-6/qml /nix/store/*caelestia-qml-plugin*/lib/qt-6/qml; do
            if [ -d "$qs_path" ] && [ "$qs_path" != "$caelestia_qml" ]; then
              export NIXPKGS_QT6_QML_IMPORT_PATH="''${NIXPKGS_QT6_QML_IMPORT_PATH:+''${NIXPKGS_QT6_QML_IMPORT_PATH}:}$qs_path"
            fi
          done

          # Set CAELESTIA_LIB_DIR to the caelestia-extras lib directory
          if [ -z "''${CAELESTIA_LIB_DIR:-}" ]; then
            for lib_path in ${caelestiaShellPkg}/lib /nix/store/*caelestia-extras*/lib /nix/store/*caelestia-qml-plugin*/lib; do
              if [ -d "$lib_path" ]; then
                export CAELESTIA_LIB_DIR="$lib_path"
                break
              fi
            done
          fi

          exec ${lib.getExe upstreamQuickshellPkg} -p ${lib.escapeShellArg "${caelestiaShellPkg}/share/caelestia-shell"} "$@"
        ''
      )
    else
      null;
in
{
  programs.waybar.enable = lib.mkForce false;

  j0nix.user.shells.quickshell.packages = lib.mkAfter (
    listMerge.mergeUnique [
      (lib.optionals (caelestiaShellPkg != null) [ caelestiaShellPkg ])
      (lib.optionals (caelestiaCliPkg != null) [ caelestiaCliPkg ])
      (lib.optionals (useUpstreamQuickshell && upstreamQuickshellPkg != null) [ upstreamQuickshellPkg ])
      (lib.optionals (caelestiaUpstreamShellWrapper != null) [ caelestiaUpstreamShellWrapper ])
      shellRuntimePackages
      shellScriptPackages
      (lib.optionals (iconThemeEnabled && iconThemePackage != null) [ iconThemePackage ])
    ]
  );

  j0nix.user.shells.fonts.packages = lib.mkAfter shellFontPackages;

  home.activation.caelestiaConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        cfg_dir="$HOME/.config/caelestia"
        cfg_file="$cfg_dir/shell.json"
        tmp_file="$cfg_file.codex-tmp"
        bad_file="$cfg_file.invalid"

        $DRY_RUN_CMD mkdir -p "$cfg_dir"
        if [ ! -e "$cfg_file" ] || [ -L "$cfg_file" ]; then
          $DRY_RUN_CMD rm -f "$cfg_file"
          $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
    ${builtins.toJSON seededCaelestiaConfig}
    EOF
          $DRY_RUN_CMD chmod 644 "$cfg_file"
        elif [ -f "$cfg_file" ]; then
          # If the user file is broken JSON, keep a backup and recreate a valid minimal config.
          if ! ${pkgs.jq}/bin/jq -e . "$cfg_file" >/dev/null 2>&1; then
            $DRY_RUN_CMD mv -f "$cfg_file" "$bad_file" 2>/dev/null || true
            $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
    ${builtins.toJSON seededCaelestiaConfig}
    EOF
            $DRY_RUN_CMD chmod 644 "$cfg_file"
          else
            # Merge required defaults into existing config without overwriting user choices.
            $DRY_RUN_CMD ${pkgs.jq}/bin/jq \
              --arg term "${preferredTerminal}" \
              --arg wallpaperDir "${seededWallpaperDirValue}" \
              --arg keepassWorkspaceName "${keepassWorkspaceName}" \
              --argjson keepassEnabled ${if keepassEnabled then "true" else "false"} \
              --argjson keepassSpecialWorkspaceEnabled ${
                if keepassSpecialWorkspaceEnabled then "true" else "false"
              } \
              --arg defaultMaterial "${materialIconFontDefault}" \
              --argjson allowedMaterialFonts '${materialIconFontAllowedJson}' \
              '
                def as_num($default):
                  if type == "number" then . else $default end;
                def clamp($min; $max):
                  if . < $min then $min elif . > $max then $max else . end;
                .general = ((.general // {}) | .apps = ((.apps // {}) | .terminal = (.terminal // [$term])))
                | .general.idle = (.general.idle // {})
                | .general.idle.lockBeforeSleep = (.general.idle.lockBeforeSleep // true)
                | if ((.general.idle.timeouts? | type) == "array") then
                    .general.idle.timeouts = (
                      .general.idle.timeouts
                      | map(
                          if (.timeout? == 600 and ((.idleAction? == ["systemctl", "suspend-then-hibernate"]) or (.idleAction? == ["system-suspend-then-hibernate-safe"]))) then
                            .idleAction = ["system-power-action", "suspend-then-hibernate"]
                          else
                            .
                          end
                        )
                      | map(select(.idleAction? != ["system-power-action", "suspend-then-hibernate"]))
                    )
                  else
                    .
                  end
                | .launcher = (.launcher // {})
                | if ((.launcher.actions? | type) == "array") then
                    .launcher.actions = (
                      .launcher.actions
                      | map(select(.name? != "Hibernate"))
                      | map(
                          if (.name? == "Sleep") then
                            .command = ["system-power-action", "suspend"]
                          elif (.name? == "Shutdown") then
                            .command = ["system-power-action", "poweroff"]
                          elif (.name? == "Reboot") then
                            .command = ["system-power-action", "reboot"]
                          elif (.name? == "Auto Theme") then
                            .command = ["caelestia-smart-theme", "enable"]
                          elif (.name? == "Manual Theme") then
                            .command = ["caelestia-smart-theme", "disable"]
                          elif ($keepassEnabled and .name? == "Passwords") then
                            .command = ["keepassxc-toggle"]
                          else
                            .
                          end
                        )
                      | if any(.[]; .name? == "Auto Theme") then . else . + [{ "name": "Auto Theme", "command": ["caelestia-smart-theme", "enable"] }] end
                      | if any(.[]; .name? == "Manual Theme") then . else . + [{ "name": "Manual Theme", "command": ["caelestia-smart-theme", "disable"] }] end
                      | if ($keepassEnabled and (any(.[]; .name? == "Passwords") | not)) then . + [{ "name": "Passwords", "command": ["keepassxc-toggle"] }] else . end
                    )
                  else
                    .
                  end
                | if $keepassSpecialWorkspaceEnabled then
                    .bar = (.bar // {})
                    | .bar.workspaces = (.bar.workspaces // {})
                    | .bar.workspaces.specialWorkspaceIcons = (
                        (if ((.bar.workspaces.specialWorkspaceIcons? | type) == "array") then .bar.workspaces.specialWorkspaceIcons else [] end)
                        | if any(.[]; .name? == $keepassWorkspaceName) then . else . + [{ "name": $keepassWorkspaceName, "icon": "password" }] end
                      )
                  else
                    .
                  end
                | .session = (.session // {})
                | .session.commands = (
                    (.session.commands // {})
                    | .hibernate = ["system-power-action", "hibernate"]
                    | .shutdown = ["system-power-action", "poweroff"]
                    | .reboot = ["system-power-action", "reboot"]
                  )
                | .services = ((.services // {}) | .smartScheme = ${
                  if smartSchemeEnabled then "true" else "false"
                })
                | .theme = (.theme // {})
                | .theme.enableGtk = false
                | .theme.enableQt = false
                | .appearance = (.appearance // {})
                | .appearance.font = (.appearance.font // {})
                | .appearance.font.family = (.appearance.font.family // {})
                | .appearance.font.family.material =
                    (
                      (.appearance.font.family.material? // "") as $materialFont
                      | ($materialFont | tostring) as $materialFontString
                      | if ($allowedMaterialFonts | index($materialFontString)) != null then
                          $materialFontString
                        else
                          $defaultMaterial
                        end
                    )
                | .appearance.padding = (.appearance.padding // {})
                | .appearance.padding.scale = ((.appearance.padding.scale // 1) | as_num(1) | clamp(0.5; 2.0))
                | .appearance.spacing = (.appearance.spacing // {})
                | .appearance.spacing.scale = ((.appearance.spacing.scale // 1) | as_num(1) | clamp(0.5; 2.0))
                | .appearance.rounding = (.appearance.rounding // {})
                | .appearance.rounding.scale = ((.appearance.rounding.scale // 1) | as_num(1) | clamp(0.5; 2.0))
                | .appearance.font.size = (.appearance.font.size // {})
                | .appearance.font.size.scale = ((.appearance.font.size.scale // 1) | as_num(1) | clamp(0.5; 2.0))
                | if $wallpaperDir != "" then
                    .paths = ((.paths // {}) | .wallpaperDir = $wallpaperDir)
                  else
                    .
                  end
              ' "$cfg_file" >"$tmp_file"
            $DRY_RUN_CMD mv "$tmp_file" "$cfg_file"
            $DRY_RUN_CMD chmod 644 "$cfg_file"
          fi
        fi
  '';

  home.activation.caelestiaInfo = lib.hm.dag.entryAfter [ "caelestiaConfigInit" ] ''
    $DRY_RUN_CMD echo "Caelestia shell enabled. Use caelestia-start/caelestia-stop."
  '';

  home.activation.caelestiaWallpaperSeed = lib.hm.dag.entryAfter [ "caelestiaConfigInit" ] ''
    state_dir="$HOME/.local/state/caelestia/wallpaper"
    state_file="$state_dir/path.txt"

    if [ -n "${if configuredWallpaper != null then configuredWallpaper else ""}" ] \
      && [ -f "${if configuredWallpaper != null then configuredWallpaper else ""}" ] \
      && [ ! -e "$state_file" ]; then
      $DRY_RUN_CMD mkdir -p "$state_dir"
      $DRY_RUN_CMD printf '%s\n' "${
        if configuredWallpaper != null then configuredWallpaper else ""
      }" >"$state_file"
    fi
  '';

  assertions = [
    {
      assertion = hasInput;
      message = "wmShell=caelestia-shell requires flake input '${caelestiaInputName}' in flake.nix";
    }
    {
      assertion = builtins.elem caelestiaChannel [
        "stable"
        "dev"
      ];
      message = "settings.programs.caelestia.channel must be one of: stable, dev";
    }
    {
      assertion = builtins.elem quickshellRuntime [
        "wrapped"
        "upstream"
        "upstream-dev"
      ];
      message = "settings.programs.caelestia.quickshellRuntime must be one of: wrapped, upstream (legacy upstream-dev is also accepted)";
    }
    {
      assertion = caelestiaShellPkg != null;
      message = ''
        inputs.${caelestiaInputName} must expose packages.${pkgs.stdenv.hostPlatform.system}.with-cli
        (or default) for the selected Caelestia channel.
      '';
    }
    {
      assertion =
        (!useUpstreamQuickshell) || (upstreamQuickshellPkg != null && caelestiaShellPkg != null);
      message = ''
        settings.programs.caelestia.quickshellRuntime=upstream requires:
        - inputs.${caelestiaInputName}.inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}
        - inputs.${caelestiaInputName}.packages.${pkgs.stdenv.hostPlatform.system}.caelestia-shell (or default)
      '';
    }
    {
      assertion =
        (!hasValue configuredMode)
        || (builtins.elem configuredMode [
          "light"
          "dark"
        ]);
      message = "settings.programs.caelestia.theme.mode must be one of: light, dark";
    }
    {
      assertion = configuredScheme == null || configuredScheme != "";
      message = "settings.programs.caelestia.theme.scheme must be a non-empty string when set";
    }
    {
      assertion = configuredFlavour == null || configuredFlavour != "";
      message = "settings.programs.caelestia.theme.flavour must be a non-empty string when set";
    }
    {
      assertion = configuredVariant == null || configuredVariant != "";
      message = "settings.programs.caelestia.theme.variant must be a non-empty string when set";
    }
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must resolve to a package for Caelestia icon usage";
    }
  ];
}
