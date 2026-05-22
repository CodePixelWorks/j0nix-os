{
  lib,
  homeBinDir,
  appExec,
  preferredTerminalCmd,
  keybindHelpCommand,
  layoutToggleBind,
  overviewToggleBind,
  dmsOverviewEnabled,
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
  keybindDiagnosticsEnable,
  toggleableOutputBindLines,
  workspaceSwitchBinds,
  workspaceMoveBinds,
}:
let
  hasValue = value: value != null && value != "";
  inherit (lib) optional optionals;

  # ---------------------------------------------------------------------------
  # Directional key helpers (h/j/k/l)
  # ---------------------------------------------------------------------------
  directionalKeys = [
    { key = "h"; direction = "l"; label = "left";  resizeDelta = "-60 0"; resizeLabel = "shrink width"; }
    { key = "j"; direction = "d"; label = "down";  resizeDelta = "0 60";  resizeLabel = "grow height"; }
    { key = "k"; direction = "u"; label = "up";    resizeDelta = "0 -60"; resizeLabel = "shrink height"; }
    { key = "l"; direction = "r"; label = "right"; resizeDelta = "60 0";  resizeLabel = "grow width"; }
  ];

  mkMainBind = modifiers: key: dispatcher: argument:
    "$mainMod${lib.optionalString (modifiers != "") " ${modifiers}"}, ${key}, ${dispatcher}, ${argument}";

  # Focus binds: $mainMod + h/j/k/l → movefocus
  mainFocusBinds = map (entry: mkMainBind "" entry.key "movefocus" entry.direction) directionalKeys;

  # Move binds: $mainMod + ALT + h/j/k/l → movetoworkspace (directional)
  mainMoveBinds = map (entry: mkMainBind "ALT" entry.key "movetoworkspace" entry.direction) directionalKeys;

  # Resize binds: $mainMod + ALT + h/j/k/l → resizeactive
  mainResizeBinds = map (entry: mkMainBind "ALT" entry.key "resizeactive" entry.resizeDelta) directionalKeys;

  # Split binds: $mainMod + CTRL + h/j/k/l → preselect direction
  mainSplitBinds = map (entry: mkMainBind "CTRL" entry.key "layoutmsg" "preselect ${entry.direction}") directionalKeys;

  # Toggle binds (conditional)
  keyboardLayoutToggleBind = optional (hasValue layoutToggleBind) "${layoutToggleBind}, exec, wm-kbd-layout-toggle";

in
{
  coreBinds = [
    "$mainMod, q, killactive,"
    "$mainMod, t, togglefloating,"
    "$mainMod, comma, exec, ${keybindHelpCommand}"
    "$mainMod CTRL, k, exec, wm-screen-keyboard-toggle"
    "$mainMod, f, fullscreen, 0"          # true fullscreen (hides shell/waybar)
    "$mainMod SHIFT, f, fullscreen, 1"    # maximize-ish, keeps shell visible
    "$mainMod, return, exec, ${appExec preferredTerminalCmd}"
    "$mainMod, r, exec, wm-shell-recover"
    "$mainMod CTRL, v, layoutmsg, preselect r"
    "$mainMod CTRL SHIFT, v, layoutmsg, preselect d"
    "$mainMod SHIFT, l, exec, wm-lock-screen"
    "$mainMod SHIFT, q, exit,"
  ]
  ++ mainSplitBinds
  ++ keyboardLayoutToggleBind
  ++ (optional (dmsOverviewEnabled && hasValue overviewToggleBind)
    "${overviewToggleBind}, exec, wm-overview-toggle")
  ++ toggleableOutputBindLines
  ++ optionals keybindDiagnosticsEnable [
    "$mainMod SHIFT, F12, exec, wm-hypr-keybind-probe super-shift-f12"
  ]
  ++ optionals (keepassEnabled && keepassWorkspaceEnable) [
    "${keepassToggleBind}, exec, ${homeBinDir}/keepassxc-toggle"
  ]
  ++ optionals minimizerEnabled [
    "${minimizerToggleBind}, exec, ${minimizerToggleCommand}"
    "${minimizerRestoreBind}, exec, ${minimizerRestoreCommand}"
    "${minimizerMenuBind}, exec, ${minimizerMenuCommand}"
  ];

  baseBind = [
    "$mainMod CTRL, Tab, workspace, previous_per_monitor"
    "$mainMod CTRL, G, workspace, previous_per_monitor"
    "$mainMod, left, workspace, -1"
    "$mainMod, right, workspace, +1"
    "$mainMod ALT, left, movetoworkspace, -1"
    "$mainMod ALT, right, movetoworkspace, +1"
    "$mainMod, mouse_down, workspace, -1"
    "$mainMod, mouse_up, workspace, +1"
    "$mainMod ALT, mouse_down, movetoworkspace, -1"
    "$mainMod ALT, mouse_up, movetoworkspace, +1"
    "$mainMod CTRL, Backslash, centerwindow, 1"
  ]
  ++ mainFocusBinds
  ++ mainMoveBinds
  ++ workspaceSwitchBinds
  ++ workspaceMoveBinds;

  baseBinde = mainResizeBinds ++ [
    "$mainMod, minus, splitratio, 0.1"
    "$mainMod, equal, splitratio, -0.1"
    "$mainMod, plus, splitratio, -0.1"
    "$mainMod, Page_Up, workspace, -1"
    "$mainMod, Page_Down, workspace, +1"
    "$mainMod ALT, Page_Up, movetoworkspace, -1"
    "$mainMod ALT, Page_Down, movetoworkspace, +1"
  ];

  baseBindm = [
    "$mainMod, mouse:272, movewindow"
    "$mainMod, mouse:273, resizewindow"
  ];

  baseBindl = [
    ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ", Print, exec, wm-screenshot-area"
  ];

  baseBindle = [
    ", XF86AudioRaiseVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 3%+"
    ", XF86AudioLowerVolume, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-"
  ];

  # Export helpers for other modules
  inherit directionalKeys mainFocusBinds mainMoveBinds mainResizeBinds mainSplitBinds;
}
