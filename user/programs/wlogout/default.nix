{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).wlogout or { };
  enabled = cfg.enable or true;
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  logoutCmd =
    if useUWSM then
      "sleep 1; uwsm stop"
    else
      "sleep 1; hyprctl dispatch exit";
in
lib.mkIf enabled {
  home.packages = [ pkgs.wlogout ];

  programs.wlogout = {
    enable = true;
    layout = [
      {
        label = "lock";
        action = "sleep 1; if command -v hyprlock >/dev/null 2>&1; then hyprlock; else loginctl lock-session; fi";
        text = "Lock";
        keybind = "l";
      }
      {
        label = "logout";
        action = logoutCmd;
        text = "Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "sleep 1; systemctl suspend";
        text = "Suspend";
        keybind = "u";
      }
      {
        label = "reboot";
        action = "sleep 1; systemctl reboot";
        text = "Reboot";
        keybind = "r";
      }
      {
        label = "shutdown";
        action = "sleep 1; systemctl poweroff";
        text = "Shutdown";
        keybind = "s";
      }
      {
        label = "hibernate";
        action = "sleep 1; systemctl hibernate";
        text = "Hibernate";
        keybind = "h";
      }
    ];
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font", monospace;
        background-image: none;
        box-shadow: none;
        transition: 140ms;
      }

      window {
        background-color: rgba(10, 10, 10, 0.55);
      }

      button {
        color: #cdd6f4;
        background-color: rgba(20, 20, 20, 0.75);
        border: 2px solid #6c7086;
        border-radius: 14px;
        margin: 14px;
        min-width: 140px;
        min-height: 90px;
      }

      button:hover,
      button:focus,
      button:active {
        color: #11111b;
        background-color: #89b4fa;
        border-color: #89b4fa;
      }
    '';
  };
}
