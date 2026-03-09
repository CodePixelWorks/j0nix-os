{ config, lib, pkgs, settings, ... }:
let
  profileDetails = settings.profileDetails or { hyprlandMonitors = [ ]; };
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  isCaelestiaShell = selectedShell == "caelestia-shell";
  isDmsShell = selectedShell == "dank-material-shell";
  dmsSettings = settings.dms or { };
  dmsWorkspaceSettings = dmsSettings.workspaces or { };
  hyprDmsDir = "${config.home.homeDirectory}/.config/hypr/dms";
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  appExecBackend = (settings.hyprland or { }).appExecBackend or "auto";
  app2unitExec = lib.getExe pkgs.app2unit;
  uwsmExec = lib.getExe pkgs.uwsm;
  effectiveAppExecBackend =
    if !useUWSM then "app2unit"
    else if appExecBackend == "auto" then "app2unit"
    else appExecBackend;
  uwsmAppPrefix = "${uwsmExec} app --";
  appExecPrefix =
    if effectiveAppExecBackend == "uwsm" then "${uwsmAppPrefix} "
    else "${app2unitExec} -- ";
  appExec = cmd: "${appExecPrefix}${cmd}";
  launcherAppExec = appExec;
  preferredTerminal = settings.preferredTerminal or "kitty";
  preferredTerminalCmd =
    if builtins.elem preferredTerminal [ "gnome-console" "gnome console" ] then "kgx" else preferredTerminal;
  workspaceCountRaw = dmsWorkspaceSettings.count or 10;
  workspaceCount = lib.min 10 (lib.max 1 workspaceCountRaw);
  workspaceKeyPairs = builtins.genList
    (i:
      let
        ws = i + 1;
      in
      {
        workspace = toString ws;
        key = if ws == 10 then "0" else toString ws;
      })
    workspaceCount;
  workspaceSwitchBinds = map (pair: "$mainMod, ${pair.key}, workspace, ${pair.workspace}") workspaceKeyPairs;
  workspaceMoveBinds = map (pair: "$mainMod SHIFT, ${pair.key}, movetoworkspace, ${pair.workspace}") workspaceKeyPairs;
  remoteWorkspaceSwitchBinds = map (pair: "CTRL ALT, ${pair.key}, workspace, ${pair.workspace}") workspaceKeyPairs;
  remoteWorkspaceMoveBinds = map (pair: "CTRL SHIFT ALT, ${pair.key}, movetoworkspace, ${pair.workspace}") workspaceKeyPairs;
  hyprlandCfg = settings.hyprland or { };
  hyprlandDebug = hyprlandCfg.debug or { };
  keybindDiagnosticsCfg = hyprlandDebug.keybindDiagnostics or { };
  keybindDiagnosticsEnable = keybindDiagnosticsCfg.enable or false;
  keybindDiagnosticsDelaySeconds = keybindDiagnosticsCfg.delaySeconds or 8;
  keybindDiagnosticsLogDir = keybindDiagnosticsCfg.logDir or "\${XDG_STATE_HOME:-$HOME/.local/state}/hyprland/diagnostics";
  keybindDiagnosticsProbeScript = pkgs.writeShellScriptBin "wm-hypr-keybind-probe" ''
    set -eu
    label="''${1:-unknown}"
    log_dir="${keybindDiagnosticsLogDir}"
    mkdir -p "$log_dir"
    log_file="$log_dir/keybind-probe.log"
    printf '%s label=%s uid=%s wayland=%s hypr=%s\n' \
      "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)" \
      "$label" \
      "$(${pkgs.coreutils}/bin/id -u)" \
      "''${WAYLAND_DISPLAY:-}" \
      "''${HYPRLAND_INSTANCE_SIGNATURE:-}" >>"$log_file"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Hyprland keybind probe" "$label" >/dev/null 2>&1 || true
    fi
  '';
  keybindDiagnosticsScript = pkgs.writeShellScriptBin "wm-hypr-keybind-dump" ''
    set -eu

    phase="''${1:-manual}"
    case "$phase" in
      --phase=*) phase="''${phase#--phase=}" ;;
    esac

    log_dir="${keybindDiagnosticsLogDir}"
    mkdir -p "$log_dir"

    ts="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
    out_file="$log_dir/keybinds-$ts-$phase.log"

    run_hyprctl() {
      label="$1"
      shift
      echo
      echo "## $label"
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl "$@" 2>&1 || true
      else
        echo "hyprctl not found in PATH"
      fi
    }

    run_cmd() {
      label="$1"
      shift
      echo
      echo "## $label"
      "$@" 2>&1 || true
    }

    {
      echo "# Hyprland keybind diagnostics"
      echo "timestamp=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      echo "phase=$phase"
      echo "pid=$$"
      echo "user=''${USER:-unknown}"
      echo "uid=$(${pkgs.coreutils}/bin/id -u)"
      echo "session_type=''${XDG_SESSION_TYPE:-}"
      echo "session_class=''${XDG_SESSION_CLASS:-}"
      echo "desktop=''${XDG_CURRENT_DESKTOP:-}"
      echo "wayland_display=''${WAYLAND_DISPLAY:-}"
      echo "hypr_instance=''${HYPRLAND_INSTANCE_SIGNATURE:-}"
      echo "xdg_runtime_dir=''${XDG_RUNTIME_DIR:-}"
      echo "path=$PATH"

      run_hyprctl "version" version
      run_hyprctl "instances" instances
      run_hyprctl "activeworkspace" activeworkspace
      run_hyprctl "configerrors" configerrors
      run_hyprctl "globalshortcuts" globalshortcuts
      run_hyprctl "binds" binds
      run_hyprctl "devices" devices
      run_hyprctl "layers" layers
      run_cmd "app2unit probe" ${app2unitExec} -- true
      run_cmd "uwsm app probe" ${uwsmExec} app -- true
    } >"$out_file"

    echo "$out_file"
  '';
  minimizerCfg = hyprlandCfg.minimizer or { };
  minimizerEnabled = minimizerCfg.enable or false;
  minimizerVariant = minimizerCfg.variant or "denis";
  minimizerIsDenis = minimizerVariant == "denis";
  minimizerIsOrteip = minimizerVariant == "0rteip";
  minimizerPackage =
    if minimizerIsOrteip then
      if pkgs ? "hyprland-minimizer-orteip" then pkgs."hyprland-minimizer-orteip" else null
    else if pkgs ? "hyprland-minimizer" then
      pkgs."hyprland-minimizer"
    else
      null;
  minimizerDefaultCommand =
    if minimizerPackage != null then
      lib.getExe minimizerPackage
    else if minimizerIsOrteip then
      "hyprland-minimizer"
    else
      "hyprland-minimizer";
  minimizerCommand = minimizerCfg.command or minimizerDefaultCommand;
  minimizerOrteipCfg = minimizerCfg.orteip or { };
  minimizerOrteipAppId = minimizerOrteipCfg.appId or "keepassxc";
  minimizerBinds = minimizerCfg.binds or { };
  minimizerToggleBind = minimizerBinds.toggle or "$mainMod CTRL, m";
  minimizerRestoreBind = minimizerBinds.restore or "$mainMod CTRL SHIFT, m";
  minimizerMenuBind = minimizerBinds.menu or "$mainMod CTRL, c";
  minimizerToggleCommand =
    if minimizerIsOrteip then "${minimizerCommand} ${minimizerOrteipAppId}" else minimizerCommand;
  minimizerRestoreCommand =
    if minimizerIsDenis then "${minimizerCommand} --restore-last" else minimizerToggleCommand;
  minimizerMenuCommand =
    if minimizerIsDenis then "${minimizerCommand} --menu" else minimizerToggleCommand;
  keepassCfg = ((settings.programs or { }).keepassxc or { });
  keepassEnabled = keepassCfg.enable or false;
  keepassWorkspaceCfg = keepassCfg.workspace or { };
  keepassWorkspaceEnable = keepassWorkspaceCfg.enable or true;
  keepassWorkspaceMode = keepassWorkspaceCfg.mode or (if minimizerEnabled then "minimizer" else "special-workspace");
  keepassWorkspaceName = keepassWorkspaceCfg.name or "keepass";
  keepassToggleBind = keepassWorkspaceCfg.toggleBind or "$mainMod CTRL, p";
  preferredFileManager = settings.preferredFileManager or "nautilus";
  layoutToggleBind = hyprlandCfg.layoutToggleBind or "$mainMod SHIFT, SPACE";
  overviewToggleBind = hyprlandCfg.overviewToggleBind or "$mainMod, TAB";
  dmsOverviewSettings = dmsSettings.overview or { };
  dmsOverviewEnabled = dmsOverviewSettings.enable or false;
  defaultFloatWindowRules = [
    # Do not center every floating window globally: popup/context menus in Flatpak apps
    # can also be floating and would otherwise jump to screen center.
    "match:modal 1, float 1, center 1"
    "match:group 1, float 1, center 1"

    # Common utility windows that are almost always better as floating dialogs.
    "match:class ^(pavucontrol)$, float 1, center 1"
    "match:class ^(nm-connection-editor)$, float 1, center 1"
    "match:class ^(blueman-manager)$, float 1, center 1"
    "match:class ^(org\\.gnome\\.Calculator)$, float 1, center 1"
    "match:class ^(zenity)$, float 1, center 1"
    "match:class ^(yad)$, float 1, center 1"
    "match:class ^(pinentry.*)$, float 1, center 1"
    "match:class ^(polkit-gnome-authentication-agent-1)$, float 1, center 1"
    "match:class ^(org\\.freedesktop\\.secrets)$, float 1, center 1"
    "match:class ^(org\\.gnome\\.FileRoller)$, float 1, center 1"
    "match:class ^(qt5ct|qt6ct)$, float 1, center 1"
    "match:class ^(xdg-desktop-portal-gtk)$, float 1, center 1"
    "match:class ^(org\\.freedesktop\\.impl\\.portal\\.FileChooser)$, float 1, center 1"

    # Bambu Studio popup dialogs (e.g. filament selection) position themselves;
    # forcing center breaks the in-window send/print flow. Keep this before generic
    # title rules in case the parser/runtime applies first-match semantics.
    "match:class ^(BambuStudio)$, float 1, center 0"
    "match:title ^(bambu-studio)$, float 1, center 0"

    # Generic dialog-like titles (file choosers, properties, about/preferences dialogs).
    "match:title ^(Open( File)?|Save( File)?|Select (File|Folder)|Choose (File|Folder)|Properties|Preferences|Settings|About)( .*)?$, float 1, center 1"
    "match:title ^(Datei öffnen|Datei speichern|Datei auswählen|Ordner auswählen|Eigenschaften|Einstellungen|Über)( .*)?$, float 1, center 1"
    "match:title ^(Save As|Open Folder|Open Files|Choose Application|Authentication Required|Confirm|Confirmation|Warning|Error|Information)( .*)?$, float 1, center 1"
    "match:title ^(Speichern unter|Bestätigung|Warnung|Fehler|Information|Authentifizierung erforderlich|Anmeldung|Anmelden)( .*)?$, float 1, center 1"
    "match:title ^(Sign In|Sign in|Login|Log in|Authenticate|Authentication)( .*)?$, float 1, center 1"
    "match:title ^(.*(Preferences|Settings|Properties|Dialog|Picker|Chooser).*)$, float 1, center 1"
    "match:title ^(.*(Einstellungen|Eigenschaften|Auswahl|Dialog|Anmeldung|Anmelden).*)$, float 1, center 1"

    # Duplicate Bambu exceptions after generic rules as well, so they still win if
    # Hyprland applies last-match semantics for rule actions.
    "match:class ^(BambuStudio)$, float 1, center 0"
    "match:title ^(bambu-studio)$, float 1, center 0"
  ];
  additionalWindowRules = [
    # Terminal TUIs: keep nmtui readable and centered.
    "match:class ^(foot)$, match:title ^(nmtui)$, float 1, size 60% 70%, center 1"

    # Larger settings dialogs benefit from a predictable size.
    "match:class ^(org\\.gnome\\.Settings)$, float 1, size 70% 80%, center 1"
    "match:class ^(org\\.pulseaudio\\.pavucontrol|pavucontrol|yad-icon-browser)$, float 1, size 60% 70%, center 1"
    "match:class ^(nwg-look)$, float 1, size 50% 60%, center 1"

    # Picture-in-picture windows: keep them floating, pinned and ratio-safe.
    "match:title ^(Picture(-| )in(-| )[Pp]icture)$, float 1, pin 1, keep_aspect_ratio 1, move 100%-w-2% 100%-h-3%"

    # Steam friends list should behave like a utility window.
    "match:class ^(steam)$, match:title ^(Friends List)$, float 1, center 1"

    # Hide blur artefacts in Fusion overlays.
    "match:class ^(fusion360\\.exe)$, match:title ^(Fusion360|(Marking Menu))$, no_blur 1"

    # Ueberzugpp helper surfaces should not steal focus.
    "match:class ^(ueberzugpp_.*)$, float 1, no_initial_focus 1"
  ];
  hasValue = value: value != null && value != "";
  keyboardLayoutToggleBind =
    lib.optional (hasValue layoutToggleBind) "${layoutToggleBind}, exec, wm-kbd-layout-toggle";
  dmsOverviewToggleBind =
    lib.optional (dmsOverviewEnabled && hasValue overviewToggleBind)
      "${overviewToggleBind}, exec, wm-overview-toggle";
  dmsOverviewRemoteToggleBind =
    lib.optional dmsOverviewEnabled "CTRL ALT, SPACE, exec, wm-overview-toggle";
  baseHyprKeybinds = {
    bind = [
      "$mainMod, h, movewindow, l"
      "$mainMod, j, movewindow, d"
      "$mainMod, k, movewindow, u"
      "$mainMod, l, movewindow, r"
      "CTRL ALT, h, movefocus, l"
      "CTRL ALT, j, movefocus, d"
      "CTRL ALT, k, movefocus, u"
      "CTRL ALT, l, movefocus, r"
      "$mainMod, left, workspace, -1"
      "$mainMod, right, workspace, +1"
      "$mainMod SHIFT, left, movetoworkspace, -1"
      "$mainMod SHIFT, right, movetoworkspace, +1"
      "CTRL SHIFT ALT, h, movewindow, l"
      "CTRL SHIFT ALT, j, movewindow, d"
      "CTRL SHIFT ALT, k, movewindow, u"
      "CTRL SHIFT ALT, l, movewindow, r"
      "$mainMod, mouse_down, workspace, -1"
      "$mainMod, mouse_up, workspace, +1"
      "$mainMod CTRL, Backslash, centerwindow, 1"
    ];
    binde = [
      "$mainMod ALT, h, resizeactive, -60 0"
      "$mainMod ALT, j, resizeactive, 0 60"
      "$mainMod ALT, k, resizeactive, 0 -60"
      "$mainMod ALT, l, resizeactive, 60 0"
      "$mainMod, minus, splitratio, -0.1"
      "$mainMod, equal, splitratio, 0.1"
      "$mainMod, Page_Up, workspace, -1"
      "$mainMod, Page_Down, workspace, +1"
      "$mainMod ALT, Page_Up, movetoworkspace, -1"
      "$mainMod ALT, Page_Down, movetoworkspace, +1"
    ];
    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
    ];
    bindl = [
      ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      "CTRL ALT, m, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      "CTRL SHIFT ALT, m, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      "CTRL, Print, exec, wm-screenshot-full"
    ];
    bindle = [
      ", XF86AudioRaiseVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+"
      ", XF86AudioLowerVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-"
      "CTRL ALT, equal, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+"
      "CTRL ALT, minus, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-"
      "CTRL SHIFT ALT, equal, exec, brightnessctl set +5%"
      "CTRL SHIFT ALT, minus, exec, brightnessctl set 5%-"
    ];
  };
  coreBinds = [
    "$mainMod, q, killactive,"
    "CTRL ALT, q, killactive,"
    "$mainMod, t, togglefloating,"
    "CTRL ALT, t, togglefloating,"
    "$mainMod, f, fullscreen, 0"            # actual fullscreen (shell/waybar hidden)
    "$mainMod SHIFT, f, fullscreen, 1"      # Win+Shift+F: maximize-ish fullscreen that keeps shell/waybar visible
    "CTRL ALT, f, fullscreen, 0"
    "CTRL SHIFT ALT, f, fullscreen, 1"
    "$mainMod, return, exec, ${appExec preferredTerminalCmd}"
    "$mainMod, p, exec, wm-screenshot-full"
    "$mainMod, r, exec, wm-shell-recover"
    "$mainMod CTRL, v, layoutmsg, preselect r"
    "$mainMod CTRL SHIFT, v, layoutmsg, preselect d"
    "$mainMod SHIFT, l, exec, sh -lc 'if command -v hyprlock >/dev/null 2>&1; then hyprlock; else loginctl lock-session; fi'"
    "CTRL ALT, return, exec, ${appExec preferredTerminalCmd}"
    "CTRL ALT, c, centerwindow, 1"
    "$mainMod SHIFT, q, exit,"
    "CTRL SHIFT, Print, exec, wm-screenshot-area"
  ] ++ keyboardLayoutToggleBind ++ dmsOverviewToggleBind ++ dmsOverviewRemoteToggleBind
    ++ lib.optionals keybindDiagnosticsEnable [
      "$mainMod SHIFT, F12, exec, wm-hypr-keybind-probe super-shift-f12"
      "CTRL ALT, F12, exec, wm-hypr-keybind-probe ctrl-alt-f12"
    ]
    ++ lib.optionals (keepassEnabled && keepassWorkspaceEnable) [
      "${keepassToggleBind}, exec, keepassxc-toggle"
    ]
    ++ lib.optionals minimizerEnabled [
      "${minimizerToggleBind}, exec, ${minimizerToggleCommand}"
      "${minimizerRestoreBind}, exec, ${minimizerRestoreCommand}"
      "${minimizerMenuBind}, exec, ${minimizerMenuCommand}"
    ];
  shellHyprKeybinds =
    if isCaelestiaShell then
      {
        # Caelestia exposes many actions via Hyprland "global" dispatch commands.
        extraConfig = "";
        bindi = [ ];
        bind = [
          "$mainMod, escape, global, caelestia:session"
          "$mainMod, space, global, caelestia:showall"
          "CTRL ALT, space, global, caelestia:launcher"
          "CTRL SHIFT ALT, space, global, caelestia:showall"
          "CTRL ALT, BackSpace, global, caelestia:lock"
          "$mainMod, n, global, caelestia:clearNotifs"
          "$mainMod SHIFT, v, exec, pkill fuzzel || caelestia clipboard"
          "$mainMod ALT, v, exec, pkill fuzzel || caelestia clipboard -d"
          "$mainMod, period, exec, pkill fuzzel || caelestia emoji -p"
          "$mainMod ALT, r, exec, caelestia record -s"
          "CTRL ALT, r, exec, caelestia record"
          "$mainMod SHIFT ALT, r, exec, caelestia record -r"
          "$mainMod SHIFT, s, global, caelestia:screenshotFreeze"
          "$mainMod SHIFT ALT, s, global, caelestia:screenshot"
          "$mainMod, b, exec, ${launcherAppExec (settings.preferredBrowser or "chromium")}"
          "$mainMod, e, exec, ${launcherAppExec preferredFileManager}"
          "$mainMod, v, exec, ${launcherAppExec (settings.preferredEditor or "nvim")}"
          "$mainMod, g, exec, ${launcherAppExec "github-desktop"}"
          "CTRL ALT, v, exec, ${launcherAppExec "pavucontrol"}"
          "CTRL ALT, Escape, exec, ${launcherAppExec "qps"}"
          "$mainMod ALT, s, movetoworkspace, special:special"
          "$mainMod, s, exec, caelestia toggle specialws"
          "$mainMod CTRL SHIFT, up, movetoworkspace, special:special"
          "$mainMod CTRL SHIFT, down, movetoworkspace, e+0"
          "$mainMod CTRL SHIFT, right, movetoworkspace, +1"
          "$mainMod CTRL SHIFT, left, movetoworkspace, -1"
          "$mainMod ALT, mouse_down, movetoworkspace, -1"
          "$mainMod ALT, mouse_up, movetoworkspace, +1"
          "$mainMod, slash, exec, caelestia shell controlCenter open"
          "CTRL ALT, slash, exec, caelestia shell controlCenter open"
          "$mainMod, m, exec, caelestia toggle music"
          "$mainMod, c, exec, caelestia toggle communication"
          "$mainMod, y, exec, caelestia toggle todo"
          "$mainMod, x, exec, caelestia toggle sysmon"
          "$mainMod SHIFT, c, exec, hyprpicker -a"
        ];
        bindl = [
          ", Print, exec, caelestia screenshot"
          ", XF86MonBrightnessUp, global, caelestia:brightnessUp"
          ", XF86MonBrightnessDown, global, caelestia:brightnessDown"
          "CTRL SUPER, Space, global, caelestia:mediaToggle"
          ", XF86AudioPlay, global, caelestia:mediaToggle"
          ", XF86AudioPause, global, caelestia:mediaToggle"
          "CTRL SUPER, Equal, global, caelestia:mediaNext"
          ", XF86AudioNext, global, caelestia:mediaNext"
          "CTRL SUPER, Minus, global, caelestia:mediaPrev"
          ", XF86AudioPrev, global, caelestia:mediaPrev"
          ", XF86AudioStop, global, caelestia:mediaStop"
          ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          "$mainMod SHIFT, m, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          "CTRL SHIFT ALT, v, exec, sleep 0.5s && ydotool type -d 1 \"$(cliphist list | head -1 | cliphist decode)\""
          "$mainMod ALT, f12, exec, notify-send -u low -i dialog-information-symbolic 'Test notification' \"Here's a really long message to test truncation and wrapping\\nYou can middle click or flick this notification to dismiss it!\" -a 'Shell' -A \"Test1=I got it!\" -A \"Test2=Another action\""
          "$mainMod SHIFT, BackSpace, exec, caelestia shell -d"
          "$mainMod SHIFT, BackSpace, global, caelestia:lock"
        ];
        bindle = [
          ", XF86AudioRaiseVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+"
          ", XF86AudioLowerVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-"
        ];
        binde = [
          "$mainMod, Page_Up, workspace, -1"
          "$mainMod, Page_Down, workspace, +1"
          "CTRL ALT, Tab, changegroupactive, f"
          "CTRL SHIFT ALT, Tab, changegroupactive, b"
          "$mainMod, minus, splitratio, -0.1"
          "$mainMod, equal, splitratio, 0.1"
        ];
        bindr = [
          "CTRL SUPER SHIFT, R, exec, qs -c caelestia kill"
          "CTRL SUPER ALT, R, exec, qs -c caelestia kill; sleep .1; caelestia shell -d"
        ];
        bindm = [
          "Super, mouse:272, movewindow"
          "Super, mouse:273, resizewindow"
        ];
      }
    else
      {
        extraConfig = "";
      };
  mergedBindList = key: (baseHyprKeybinds.${key} or [ ]) ++ (shellHyprKeybinds.${key} or [ ]);
  renderBindLines = key: entries:
    lib.concatStringsSep "\n" (map (entry: "${key} = ${entry}") entries);
  # Final merged bind lists rendered through Home Manager Hyprland settings.
  effectiveBindLists = {
    bind = coreBinds ++ workspaceSwitchBinds ++ workspaceMoveBinds ++ remoteWorkspaceSwitchBinds ++ remoteWorkspaceMoveBinds ++ mergedBindList "bind";
    bindi = mergedBindList "bindi";
    bindin = mergedBindList "bindin";
    binde = mergedBindList "binde";
    bindl = mergedBindList "bindl";
    bindle = mergedBindList "bindle";
    bindr = mergedBindList "bindr";
    bindm = mergedBindList "bindm";
  };
  # Keep Caelestia keybind handling aligned with upstream dots:
  # run all binds inside a persistent "global" submap with launcher catchall interrupts.
  caelestiaSubmapConfig =
    if isCaelestiaShell then
      let
        launcherLines = [
          "bindi = Super, Super_L, global, caelestia:launcher"
          "bindin = Super, catchall, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:272, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:273, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:274, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:275, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:276, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse:277, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse_up, global, caelestia:launcherInterrupt"
          "bindin = Super, mouse_down, global, caelestia:launcherInterrupt"
        ];
        renderedLists =
          lib.concatStringsSep "\n"
            (lib.filter (s: s != "") [
              (renderBindLines "bind" effectiveBindLists.bind)
              (renderBindLines "bindi" effectiveBindLists.bindi)
              (renderBindLines "binde" effectiveBindLists.binde)
              (renderBindLines "bindl" effectiveBindLists.bindl)
              (renderBindLines "bindle" effectiveBindLists.bindle)
              (renderBindLines "bindr" effectiveBindLists.bindr)
              (renderBindLines "bindm" effectiveBindLists.bindm)
            ]);
      in
      ''
        exec = hyprctl dispatch submap global
        submap = global
        ${lib.concatStringsSep "\n" launcherLines}
        ${renderedLists}
        submap = reset
      ''
    else
      "";
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;
  shellStartupCommand = if selectedShell == "none" then null else "wm-shell-start";
  hyprlandSessionCheckScript = pkgs.writeShellScript "wm-hypr-session-check" ''
    if [ "''${XDG_CURRENT_DESKTOP:-}" = "Hyprland" ] \
      || [ "''${XDG_SESSION_DESKTOP:-}" = "hyprland" ] \
      || [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      exit 0
    fi

    if command -v hyprctl >/dev/null 2>&1 && hyprctl instances >/dev/null 2>&1; then
      exit 0
    fi

    exit 1
  '';
  hyprlandStartupAppsScript = pkgs.writeShellScriptBin "wm-hypr-startup-apps" ''
    hyprctl_bin="$(command -v hyprctl || true)"
    [ -n "$hyprctl_bin" ] || exit 0

    launch_on_workspace() {
      workspace="$1"
      command="$2"
      "$hyprctl_bin" dispatch exec "[workspace $workspace silent] $command" >/dev/null 2>&1 || true
    }

    if ! ${pkgs.procps}/bin/pgrep -x firefox >/dev/null 2>&1; then
      launch_on_workspace 2 '${launcherAppExec "firefox"}'
    fi

    if ! ${pkgs.procps}/bin/pgrep -x btop >/dev/null 2>&1; then
      launch_on_workspace 3 '${launcherAppExec "${preferredTerminalCmd} btop"}'
    fi
  '';
  hyprlandKeybindDiagnosticsStartupScript = pkgs.writeShellScriptBin "wm-hypr-keybind-diagnostics-startup" ''
    wm-hypr-keybind-dump --phase=login-initial
    sleep ${toString keybindDiagnosticsDelaySeconds}
    wm-hypr-keybind-dump --phase=login-delayed
  '';
in {
  j0nix.user.software.packages = with pkgs; [
    swww
    wayvnc
    wl-clipboard
    grim
    slurp
    swappy
    playerctl
  ]
  ++ lib.optionals keybindDiagnosticsEnable [
    keybindDiagnosticsScript
    keybindDiagnosticsProbeScript
  ]
  ++ lib.optional (installRawQuickshell && (pkgs ? quickshell)) pkgs.quickshell
  ++ lib.optionals (minimizerEnabled && minimizerPackage != null) [ minimizerPackage ];

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    extraConfig =
      (lib.optionalString isDmsShell ''
      # DMS writes these files at runtime to sync compositor visuals.
      source = ${hyprDmsDir}/colors.conf
      source = ${hyprDmsDir}/cursor.conf
      source = ${hyprDmsDir}/outputs.conf
      source = ${hyprDmsDir}/windowrules.conf
      source = ${hyprDmsDir}/binds.conf
      # Backwards compatibility with older DMS layouts.
      source = ${hyprDmsDir}/layout.conf
      '')
      + (shellHyprKeybinds.extraConfig or "")
      + caelestiaSubmapConfig;

    settings = {
      "$mainMod" = "SUPER";
      monitor = (profileDetails.hyprlandMonitors or [ ]) ++ [ ",preferred,auto,1" ];

      input = {
        kb_layout = settings.keyboardLayout or "de";
        kb_options = settings.keyboardOptions or "caps:escape";
        follow_mouse = true;
        touchpad.natural_scroll = true;
      };

      general = {
        gaps_in = 6;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(89b4faff)";
        "col.inactive_border" = "rgba(313244ff)";
      };

      "decoration:rounding" = 8;
      "decoration:active_opacity" = 1.0;
      "decoration:inactive_opacity" = 0.94;
      "decoration:fullscreen_opacity" = 1.0;
      "decoration:blur:enabled" = true;
      "decoration:blur:size" = 8;
      "decoration:blur:passes" = 2;

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      binds = {
        # Keep compositor shortcuts responsive even if a client requests a
        # shortcuts inhibitor (seen intermittently with shell overlays).
        disable_keybind_grabbing = true;
      };

      misc = {
        vfr = true;
        vrr = 1;
        animate_manual_resizes = false;
        animate_mouse_windowdragging = false;
        force_default_wallpaper = 0;
        on_focus_under_fullscreen = 2;
        allow_session_lock_restore = true;
        middle_click_paste = false;
        focus_on_activate = true;
        session_lock_xray = true;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      debug = {
        error_position = 1;
      };

      windowrule = defaultFloatWindowRules ++ additionalWindowRules;

      bind = if isCaelestiaShell then [ ] else effectiveBindLists.bind;
      bindi = effectiveBindLists.bindi;
      bindin = effectiveBindLists.bindin;
      binde = if isCaelestiaShell then [ ] else effectiveBindLists.binde;
      bindl = if isCaelestiaShell then [ ] else effectiveBindLists.bindl;
      bindle = if isCaelestiaShell then [ ] else effectiveBindLists.bindle;
      bindr = if isCaelestiaShell then [ ] else effectiveBindLists.bindr;
      bindm = if isCaelestiaShell then [ ] else effectiveBindLists.bindm;
    };

  };

  systemd.user.services = lib.mkMerge [
    {
      hyprland-wallpaper = {
        Unit = {
          Description = "Hyprland wallpaper daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecCondition = hyprlandSessionCheckScript;
          ExecStart = lib.getExe' pkgs.swww "swww-daemon";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      hyprland-startup-apps = {
        Unit = {
          Description = "Hyprland startup apps";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecCondition = hyprlandSessionCheckScript;
          ExecStart = lib.getExe hyprlandStartupAppsScript;
          RemainAfterExit = true;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    }
    (lib.mkIf (shellStartupCommand != null) {
      hyprland-shell = {
        Unit = {
          Description = "Hyprland shell startup";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "simple";
          ExecCondition = hyprlandSessionCheckScript;
          ExecStart = "${lib.getExe pkgs.bash} -lc 'exec ${shellStartupCommand}'";
          ExecStop = "${lib.getExe pkgs.bash} -lc 'wm-shell-stop >/dev/null 2>&1 || true'";
          Restart = "on-failure";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
    (lib.mkIf keybindDiagnosticsEnable {
      hyprland-keybind-diagnostics = {
        Unit = {
          Description = "Hyprland keybind diagnostics startup";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecCondition = hyprlandSessionCheckScript;
          ExecStart = lib.getExe hyprlandKeybindDiagnosticsStartupScript;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })
  ];

  xdg.configFile."hypr/hyprland.conf".force = true;

  assertions = [
    {
      assertion = !(installRawQuickshell && isDmsShell);
      message = "settings.hyprland.debug.installRawQuickshell conflicts with hyprlandShell=dank-material-shell (quickshell package collision).";
    }
    {
      assertion = workspaceCountRaw >= 1 && workspaceCountRaw <= 10;
      message = "settings.dms.workspaces.count must be between 1 and 10";
    }
    {
      assertion = builtins.elem appExecBackend [ "auto" "app2unit" "uwsm" ];
      message = "settings.hyprland.appExecBackend must be one of: auto, app2unit, uwsm";
    }
    {
      assertion = !minimizerEnabled || minimizerCommand != "";
      message = "settings.hyprland.minimizer.command must not be empty when minimizer is enabled.";
    }
    {
      assertion = builtins.elem minimizerVariant [ "denis" "0rteip" ];
      message = "settings.hyprland.minimizer.variant must be one of: denis, 0rteip";
    }
    {
      assertion = !minimizerEnabled || minimizerOrteipAppId != "";
      message = "settings.hyprland.minimizer.orteip.appId must not be empty when minimizer is enabled.";
    }
    {
      assertion = keybindDiagnosticsDelaySeconds >= 0;
      message = "settings.hyprland.debug.keybindDiagnostics.delaySeconds must be >= 0.";
    }
  ];
}
