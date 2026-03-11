{
  lib,
  settings,
  isCaelestiaShell,
  hyprctlExec,
  appExec,
  launcherAppExec,
  preferredTerminalCmd,
  preferredFileManager,
  layoutToggleBind,
  dmsOverviewEnabled,
  overviewToggleBind,
  keybindDiagnosticsEnable,
  keepassEnabled,
  keepassWorkspaceEnable,
  keepassToggleBind,
  minimizerEnabled,
  minimizerToggleBind,
  minimizerRestoreBind,
  minimizerMenuBind,
  minimizerToggleCommand,
  minimizerRestoreCommand,
  minimizerMenuCommand,
  workspaceSwitchBinds,
  workspaceMoveBinds,
}:
let
  hasValue = value: value != null && value != "";
  keybindHelpCommand = appExec "wm-keybinds-show";
  directionalKeys = [
    {
      key = "h";
      direction = "l";
      label = "left";
      resizeDelta = "-60 0";
      resizeLabel = "shrink width";
    }
    {
      key = "j";
      direction = "d";
      label = "down";
      resizeDelta = "0 60";
      resizeLabel = "grow height";
    }
    {
      key = "k";
      direction = "u";
      label = "up";
      resizeDelta = "0 -60";
      resizeLabel = "shrink height";
    }
    {
      key = "l";
      direction = "r";
      label = "right";
      resizeDelta = "60 0";
      resizeLabel = "grow width";
    }
  ];
  mkMainBind = modifiers: key: dispatcher: argument:
    "$mainMod${lib.optionalString (modifiers != "") " ${modifiers}"}, ${key}, ${dispatcher}, ${argument}";
  mkHelp = section: binding: description: {
    inherit section binding description;
  };
  keyboardLayoutToggleBind =
    lib.optional (hasValue layoutToggleBind) "${layoutToggleBind}, exec, wm-kbd-layout-toggle";
  dmsOverviewToggleBind =
    lib.optional (dmsOverviewEnabled && hasValue overviewToggleBind)
      "${overviewToggleBind}, exec, wm-overview-toggle";
  mainFocusBinds = map (entry: mkMainBind "" entry.key "movefocus" entry.direction) directionalKeys;
  mainMoveBinds = map (entry: mkMainBind "SHIFT" entry.key "movewindow" entry.direction) directionalKeys;
  mainResizeBinds = map (entry: mkMainBind "ALT" entry.key "resizeactive" entry.resizeDelta) directionalKeys;
  mainSplitBinds = map (entry: mkMainBind "CTRL" entry.key "layoutmsg" "preselect ${entry.direction}") directionalKeys;

  baseHyprKeybinds = {
    bind = [
      "$mainMod, left, workspace, -1"
      "$mainMod, right, workspace, +1"
      "$mainMod SHIFT, left, movetoworkspace, -1"
      "$mainMod SHIFT, right, movetoworkspace, +1"
      "$mainMod, mouse_down, workspace, -1"
      "$mainMod, mouse_up, workspace, +1"
      "$mainMod CTRL, Backslash, centerwindow, 1"
    ] ++ mainFocusBinds ++ mainMoveBinds;
    binde = mainResizeBinds ++ [
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
      "CTRL, Print, exec, wm-screenshot-full"
    ];
    bindle = [
      ", XF86AudioRaiseVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+"
      ", XF86AudioLowerVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-"
    ];
  };

  coreBinds = [
    "$mainMod, q, killactive,"
    "$mainMod, t, togglefloating,"
    "$mainMod, comma, exec, ${keybindHelpCommand}"
    "$mainMod, f, fullscreen, 0"            # actual fullscreen (shell/waybar hidden)
    "$mainMod SHIFT, f, fullscreen, 1"      # Win+Shift+F: maximize-ish fullscreen that keeps shell/waybar visible
    "$mainMod, return, exec, ${appExec preferredTerminalCmd}"
    "$mainMod, p, exec, wm-screenshot-full"
    "$mainMod, r, exec, wm-shell-recover"
    "$mainMod CTRL, v, layoutmsg, preselect r"
    "$mainMod CTRL SHIFT, v, layoutmsg, preselect d"
    "$mainMod SHIFT, l, exec, sh -lc 'if command -v hyprlock >/dev/null 2>&1; then hyprlock; else loginctl lock-session; fi'"
    "$mainMod SHIFT, q, exit,"
    "CTRL SHIFT, Print, exec, wm-screenshot-area"
  ] ++ mainSplitBinds ++ keyboardLayoutToggleBind ++ dmsOverviewToggleBind
    ++ lib.optionals keybindDiagnosticsEnable [
      "$mainMod SHIFT, F12, exec, wm-hypr-keybind-probe super-shift-f12"
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

  effectiveBindLists = {
    bind = coreBinds ++ workspaceSwitchBinds ++ workspaceMoveBinds ++ mergedBindList "bind";
    bindi = mergedBindList "bindi";
    bindin = mergedBindList "bindin";
    binde = mergedBindList "binde";
    bindl = mergedBindList "bindl";
    bindle = mergedBindList "bindle";
    bindr = mergedBindList "bindr";
    bindm = mergedBindList "bindm";
  };

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
        exec = ${hyprctlExec} dispatch submap global
        submap = global
        ${lib.concatStringsSep "\n" launcherLines}
        ${renderedLists}
        submap = reset
      ''
    else
      "";

  helpEntries =
    [
      (mkHelp "Windows" "SUPER+Q" "Close the active window")
      (mkHelp "Windows" "SUPER+T" "Toggle floating for the active window")
      (mkHelp "Windows" "SUPER+F" "Fullscreen the active window")
      (mkHelp "Windows" "SUPER+SHIFT+F" "Maximize-like fullscreen while keeping shell bars visible")
      (mkHelp "Windows" "SUPER+Return" "Open the preferred terminal")
      (mkHelp "Windows" "SUPER+SHIFT+L" "Lock the current session")
      (mkHelp "Help" "SUPER+," "Open the Hyprland keybind reference")
      (mkHelp "Layout" "SUPER+-" "Decrease the current split ratio")
      (mkHelp "Layout" "SUPER+=" "Increase the current split ratio")
      (mkHelp "Layout" "SUPER+CTRL+V" "Legacy alias: preselect a split to the right")
      (mkHelp "Layout" "SUPER+CTRL+SHIFT+V" "Legacy alias: preselect a split downward")
      (mkHelp "Workspaces" "SUPER+Left/Right" "Switch to the previous or next workspace")
      (mkHelp "Workspaces" "SUPER+SHIFT+Left/Right" "Move the active window to the previous or next workspace")
      (mkHelp "Workspaces" "SUPER+1..0" "Jump directly to a numbered workspace")
      (mkHelp "Workspaces" "SUPER+SHIFT+1..0" "Send the active window to a numbered workspace")
      (mkHelp "Workspaces" "SUPER+MouseWheel" "Cycle workspaces relative to the current one")
      (mkHelp "System" "SUPER+P" "Take a full screenshot")
      (mkHelp "System" "CTRL+SHIFT+Print" "Take an area screenshot")
      (mkHelp "System" "SUPER+R" "Restart the desktop shell/session helpers")
    ]
    ++ lib.flatten (map
      (entry: [
        (mkHelp "Windows" "SUPER+${lib.toUpper entry.key}" "Focus the window ${entry.label}")
        (mkHelp "Windows" "SUPER+SHIFT+${lib.toUpper entry.key}" "Move the active window ${entry.label}")
        (mkHelp "Layout" "SUPER+ALT+${lib.toUpper entry.key}" "Resize the active window: ${entry.resizeLabel}")
        (mkHelp "Layout" "SUPER+CTRL+${lib.toUpper entry.key}" "Preselect the next split ${entry.label}")
      ])
      directionalKeys)
    ++ lib.optionals keepassEnabled [
      (mkHelp "Apps" "SUPER+CTRL+P" "Toggle KeePassXC via special workspace or minimizer mode")
    ]
    ++ lib.optionals minimizerEnabled [
      (mkHelp "Apps" "SUPER+CTRL+M" "Toggle the Hyprland minimizer for the configured app")
      (mkHelp "Apps" "SUPER+CTRL+SHIFT+M" "Restore the last minimized app")
      (mkHelp "Apps" "SUPER+CTRL+C" "Open the minimizer menu or toggle the configured app")
    ]
    ++ lib.optionals isCaelestiaShell [
      (mkHelp "Caelestia" "SUPER+Space" "Open the shell app overview")
      (mkHelp "Caelestia" "SUPER+B" "Open the preferred browser")
      (mkHelp "Caelestia" "SUPER+E" "Open the preferred file manager")
      (mkHelp "Caelestia" "SUPER+V" "Open the preferred editor")
      (mkHelp "Caelestia" "SUPER+M/C/Y/X" "Toggle special workspaces for music, communication, todo, or sysmon")
    ];
in
{
  inherit shellHyprKeybinds effectiveBindLists caelestiaSubmapConfig helpEntries;
}
