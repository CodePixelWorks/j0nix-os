{ config, lib, pkgs, settings, ... }:
let
  profileDetails = settings.profileDetails or { hyprlandMonitors = [ ]; };
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  dmsSettings = settings.dms or { };
  dmsWorkspaceSettings = dmsSettings.workspaces or { };
  preferredTerminal = settings.preferredTerminal or "kitty";
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
  coreBinds = [
    "$mainMod, q, killactive,"
    "$mainMod, t, togglefloating,"
    "$mainMod, f, fullscreen, 0"
    "$mainMod, return, exec, ${preferredTerminal}"
    "$mainMod SHIFT, q, exit,"
  ];
  hyprlandDebug = ((settings.hyprland or { }).debug or { });
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
    extraConfig = lib.optionalString (selectedShell == "dank-material-shell") ''
      # DMS writes these files at runtime to sync compositor visuals.
      source = ~/.config/hypr/dms/colors.conf
      source = ~/.config/hypr/dms/cursor.conf
      source = ~/.config/hypr/dms/outputs.conf
      source = ~/.config/hypr/dms/windowrules.conf
      source = ~/.config/hypr/dms/binds.conf
      # Backwards compatibility with older DMS layouts.
      source = ~/.config/hypr/dms/layout.conf
    '';

    settings = {
      "$mainMod" = "SUPER";
      monitor = (profileDetails.hyprlandMonitors or [ ]) ++ [ ",preferred,auto,1" ];

      exec-once = [
        "swww-daemon &"
        "[workspace 2 silent] firefox"
        "[workspace 3 silent] ${preferredTerminal} btop"
      ] ++ lib.optionals (shellStartupCommand != null) [ shellStartupCommand ];

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

      bind =
        coreBinds
        ++ workspaceSwitchBinds
        ++ workspaceMoveBinds;
    };

  };

  xdg.configFile."hypr/hyprland.conf".force = true;

  assertions = [
    {
      assertion = !(installRawQuickshell && selectedShell == "dank-material-shell");
      message = "settings.hyprland.debug.installRawQuickshell conflicts with hyprlandShell=dank-material-shell (quickshell package collision).";
    }
    {
      assertion = workspaceCountRaw >= 1 && workspaceCountRaw <= 10;
      message = "settings.dms.workspaces.count must be between 1 and 10";
    }
  ];
}
