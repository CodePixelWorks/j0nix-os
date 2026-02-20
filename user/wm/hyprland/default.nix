{ config, lib, pkgs, settings, ... }:
let
  profileDetails = settings.profileDetails or { hyprlandMonitors = [ ]; };
  selectedShell = settings.hyprlandShell or "ags";
  dmsSettings = settings.dms or { };
  dmsStartup = dmsSettings.startup or { };
  dmsStartupMode = dmsStartup.mode or "systemd";
  hyprlandDebug = ((settings.hyprland or { }).debug or { });
  installRawQuickshell = hyprlandDebug.installRawQuickshell or false;

  # `exec-once` is used for both direct Hyprland sessions and UWSM-managed sessions.
  shellStartupCommand =
    if selectedShell == "dank-material-shell" then
      if dmsStartupMode == "exec-once" then "dms-start" else null
    else if selectedShell == "noctalia-shell" then
      "noctalia-start"
    else
      "killall -q ags;sleep .5 && ags";
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

    settings = {
      monitor = (profileDetails.hyprlandMonitors or [ ]) ++ [ ",preferred,auto,1" ];

      exec-once = [
        "swww-daemon &"
        "[workspace 2 silent] firefox"
        "[workspace 3 silent] kitty btop"
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
    };

  };

  xdg.configFile."hypr/hyprland.conf".force = true;

  assertions = [
    {
      assertion = !(installRawQuickshell && selectedShell == "dank-material-shell");
      message = "settings.hyprland.debug.installRawQuickshell conflicts with hyprlandShell=dank-material-shell (quickshell package collision).";
    }
    {
      assertion = builtins.elem dmsStartupMode [ "systemd" "exec-once" ];
      message = "settings.dms.startup.mode must be one of: systemd, exec-once";
    }
  ];
}
