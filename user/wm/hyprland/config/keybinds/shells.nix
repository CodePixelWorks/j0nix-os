{ launcherAppExec, settings, preferredFileManager }:
{
  caelestia = {
    extraConfig = "";
    bindi = [ ];
    bind = [
      "$mainMod, escape, global, caelestia:session"
      "$mainMod, space, global, caelestia:showall"
      "$mainMod, n, global, caelestia:clearNotifs"
      "$mainMod SHIFT, n, global, caelestia:clearNotifs"
      "$mainMod SHIFT, v, exec, pkill fuzzel || caelestia clipboard"
      "$mainMod ALT, v, exec, pkill fuzzel || caelestia clipboard -d"
      "$mainMod, period, exec, pkill fuzzel || caelestia emoji -p"
      "$mainMod ALT, r, exec, caelestia record -s"
      "CTRL ALT, r, exec, caelestia record"
      "$mainMod SHIFT ALT, r, exec, caelestia record -r"
      "$mainMod, p, exec, caelestia screenshot"
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
      "$mainMod, m, exec, caelestia toggle media"
      "$mainMod, c, exec, caelestia toggle discord"
      "$mainMod, x, exec, caelestia toggle sysmon"
      "$mainMod SHIFT, c, exec, hyprpicker -a"
    ];
    bindl = [
      ", Print, exec, caelestia screenshot"
      "SHIFT, Print, exec, caelestia screenshot"
      "CTRL, Print, exec, caelestia screenshot"
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
      "$mainMod, minus, splitratio, 0.1"
      "$mainMod, equal, splitratio, -0.1"
      "$mainMod, plus, splitratio, -0.1"
    ];
    bindr = [
      "CTRL SUPER SHIFT, R, exec, qs -c caelestia kill"
      "CTRL SUPER ALT, R, exec, qs -c caelestia kill; sleep .1; caelestia shell -d"
    ];
    bindm = [
      "Super, mouse:272, movewindow"
      "Super, mouse:273, resizewindow"
    ];
  };
}
