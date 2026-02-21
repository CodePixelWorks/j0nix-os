{ lib, pkgs, settings, ... }:
let
  preferredTerminal = settings.preferredTerminal or "kitty";
in
{
  # Keep MangoWC tools available in user sessions.
  home.packages = with pkgs; [
    wlr-randr
    wtype
  ] ++ lib.optionals (pkgs ? mmsg) [ pkgs.mmsg ];

  # MangoWC reads this by default (~/.config/mangowc/config).
  xdg.configFile."mangowc/config".text = ''
    MODKEY = SUPER
    TERMINAL = ${preferredTerminal}
    TAGCOUNT = 10
    LAYOUT = 4

    super+q = killclient
    super+t = togglefloating
    super+f = togglefullscreen
    super+Return = spawn ${preferredTerminal}
    super+shift+q = quit

    super+1 = view 1
    super+2 = view 2
    super+3 = view 3
    super+4 = view 4
    super+5 = view 5
    super+6 = view 6
    super+7 = view 7
    super+8 = view 8
    super+9 = view 9
    super+0 = view 10

    super+shift+1 = tag 1
    super+shift+2 = tag 2
    super+shift+3 = tag 3
    super+shift+4 = tag 4
    super+shift+5 = tag 5
    super+shift+6 = tag 6
    super+shift+7 = tag 7
    super+shift+8 = tag 8
    super+shift+9 = tag 9
    super+shift+0 = tag 10
  '';
}
