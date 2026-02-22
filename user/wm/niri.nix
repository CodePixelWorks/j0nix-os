{ lib, pkgs, settings, ... }:
let
  preferredTerminal = settings.preferredTerminal or "kitty";
in
{
  home.packages = with pkgs; [
    niri
    wl-clipboard
    cliphist
    wlr-randr
  ];

  xdg.configFile."niri/config.kdl".text = ''
    input {
      keyboard {
        xkb {
          layout "${settings.keyboardLayout or "de"}"
          options "${settings.keyboardOptions or "caps:escape"}"
        }
      }
    }

    spawn-at-startup "wm-shell-start"
    spawn-at-startup "wl-paste --type text --watch cliphist store"

    binds {
      Mod+Q { close-window; }
      Mod+T { toggle-window-floating; }
      Mod+F { fullscreen-window; }
      Mod+Return { spawn "${preferredTerminal}"; }
    }
  '';

  programs.waybar.enable = lib.mkForce false;
}
