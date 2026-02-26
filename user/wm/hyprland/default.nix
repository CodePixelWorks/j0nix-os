{ config, lib, pkgs, settings, ... }:
let
  profileDetails = settings.profileDetails or { hyprlandMonitors = [ ]; };
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  isCaelestiaShell = selectedShell == "caelestia-shell";
  isDmsShell = selectedShell == "dank-material-shell";
  dmsSettings = settings.dms or { };
  dmsWorkspaceSettings = dmsSettings.workspaces or { };
  hyprDmsDir = "${config.home.homeDirectory}/.config/hypr/dms";
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
  preferredFileManager = settings.preferredFileManager or "nautilus";
  layoutToggleBind = hyprlandCfg.layoutToggleBind or "$mainMod SHIFT, SPACE";
  overviewToggleBind = hyprlandCfg.overviewToggleBind or "$mainMod, TAB";
  dmsOverviewSettings = dmsSettings.overview or { };
  dmsOverviewEnabled = dmsOverviewSettings.enable or false;
  dmsOverviewAutostart = dmsOverviewSettings.autostart or false;
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
  hasValue = value: value != null && value != "";
  keyboardLayoutToggleBind =
    lib.optional (hasValue layoutToggleBind) "${layoutToggleBind}, exec, wm-kbd-layout-toggle";
  dmsOverviewToggleBind =
    lib.optional (isDmsShell && dmsOverviewEnabled && hasValue overviewToggleBind)
      "${overviewToggleBind}, exec, dms-overview-toggle";
  dmsOverviewRemoteToggleBind =
    lib.optional (isDmsShell && dmsOverviewEnabled) "CTRL ALT, SPACE, exec, dms-overview-toggle";
  baseHyprKeybinds = {
    bind = [
      "$mainMod, left, movefocus, l"
      "$mainMod, right, movefocus, r"
      "$mainMod, up, movefocus, u"
      "$mainMod, down, movefocus, d"
      "CTRL ALT, left, movefocus, l"
      "CTRL ALT, right, movefocus, r"
      "CTRL ALT, up, movefocus, u"
      "CTRL ALT, down, movefocus, d"
      "$mainMod SHIFT, left, movewindow, l"
      "$mainMod SHIFT, right, movewindow, r"
      "$mainMod SHIFT, up, movewindow, u"
      "$mainMod SHIFT, down, movewindow, d"
      "CTRL SHIFT ALT, left, movewindow, l"
      "CTRL SHIFT ALT, right, movewindow, r"
      "CTRL SHIFT ALT, up, movewindow, u"
      "CTRL SHIFT ALT, down, movewindow, d"
      "$mainMod, mouse_down, workspace, -1"
      "$mainMod, mouse_up, workspace, +1"
      "$mainMod CTRL, Backslash, centerwindow, 1"
    ];
    binde = [
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
    "$mainMod, return, exec, ${preferredTerminalCmd}"
    "$mainMod, r, exec, wm-shell-restart"
    "CTRL ALT, return, exec, ${preferredTerminalCmd}"
    "CTRL ALT, l, exec, sh -lc 'if command -v hyprlock >/dev/null 2>&1; then hyprlock; else loginctl lock-session; fi'"
    "CTRL ALT, c, centerwindow, 1"
    "$mainMod SHIFT, q, exit,"
  ] ++ keyboardLayoutToggleBind ++ dmsOverviewToggleBind ++ dmsOverviewRemoteToggleBind;
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
          "$mainMod SHIFT, l, global, caelestia:lock"
          "CTRL ALT, BackSpace, global, caelestia:lock"
          "$mainMod, n, global, caelestia:clearNotifs"
          "$mainMod, v, exec, pkill fuzzel || caelestia clipboard"
          "$mainMod ALT, v, exec, pkill fuzzel || caelestia clipboard -d"
          "$mainMod, period, exec, pkill fuzzel || caelestia emoji -p"
          "$mainMod ALT, r, exec, caelestia record -s"
          "CTRL ALT, r, exec, caelestia record"
          "$mainMod SHIFT ALT, r, exec, caelestia record -r"
          "$mainMod SHIFT, s, global, caelestia:screenshotFreeze"
          "$mainMod SHIFT ALT, s, global, caelestia:screenshot"
          "$mainMod, b, exec, app2unit -- ${settings.preferredBrowser or "chromium"}"
          "$mainMod, e, exec, app2unit -- ${settings.preferredEditor or "nvim"}"
          "$mainMod ALT, e, exec, app2unit -- ${preferredFileManager}"
          "$mainMod, g, exec, app2unit -- github-desktop"
          "CTRL ALT, v, exec, app2unit -- pavucontrol"
          "CTRL ALT, Escape, exec, app2unit -- qps"
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
  # Final merged bind lists used either via HM settings or via the Caelestia raw submap block.
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
  # Caelestia uses a dedicated submap for bare-Super launcher behavior and catchall interrupts.
  # `catchall` is only valid inside a submap, so we render a raw Hyprland block here.
  caelestiaSubmapConfig =
    if isCaelestiaShell then
      let
        submapLauncherLines = [
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
              # `bindin` is intentionally not rendered here; launcher interrupt binds are explicit above.
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
        ${lib.concatStringsSep "\n" submapLauncherLines}
        ${renderedLists}
        submap = reset
      ''
    else
      "";
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;

  # `exec-once` is used for both direct Hyprland sessions and UWSM-managed sessions.
  shellStartupCommand = if selectedShell == "none" then null else "wm-shell-start";
in {
  home.packages = with pkgs; [
    swww
    wayvnc
    wl-clipboard
    grim
    slurp
    swappy
    playerctl
  ] ++ lib.optional (installRawQuickshell && (pkgs ? quickshell)) pkgs.quickshell;

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

      exec-once = [
        "swww-daemon &"
        "[workspace 2 silent] firefox"
        "[workspace 3 silent] ${preferredTerminalCmd} btop"
      ] ++ lib.optionals (shellStartupCommand != null) [ shellStartupCommand ]
        ++ lib.optionals (isDmsShell && dmsOverviewEnabled && dmsOverviewAutostart) [ "dms-overview-start" ];

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
      "decoration:blur:enabled" = true;
      "decoration:blur:size" = 8;
      "decoration:blur:passes" = 2;

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      windowrule = defaultFloatWindowRules;

      bind =
        if isCaelestiaShell then [ ] else effectiveBindLists.bind;
      bindi = mergedBindList "bindi";
      bindin = mergedBindList "bindin";
      binde = if isCaelestiaShell then [ ] else mergedBindList "binde";
      bindl = if isCaelestiaShell then [ ] else mergedBindList "bindl";
      bindle = if isCaelestiaShell then [ ] else mergedBindList "bindle";
      bindr = if isCaelestiaShell then [ ] else mergedBindList "bindr";
      bindm = if isCaelestiaShell then [ ] else mergedBindList "bindm";
    };

  };

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
  ];
}
