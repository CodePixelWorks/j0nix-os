{ lib, pkgs, settings, ... }:
let
  preferredTerminal = settings.preferredTerminal or "kitty";
in
{
  # MangoWC is a compositor only. Keep basic session tools available.
  home.packages = with pkgs; [
    wlr-randr
    wtype
    waybar
  ] ++ lib.optionals (pkgs ? mmsg) [ pkgs.mmsg ];

  # MangoWC reads ~/.config/mango/config.conf
  xdg.configFile."mango/config.conf".text = ''
    # Keep defaults minimal but usable.
    xkb_rules_layout=${settings.keyboardLayout or "de"}
    repeat_rate=25
    repeat_delay=600
    cursor_size=24

    # Gap/border baseline
    gappih=5
    gappiv=5
    gappoh=10
    gappov=10
    borderpx=4

    # Default layout: grid on all tags
    tagrule=id:1,layout_name:grid
    tagrule=id:2,layout_name:grid
    tagrule=id:3,layout_name:grid
    tagrule=id:4,layout_name:grid
    tagrule=id:5,layout_name:grid
    tagrule=id:6,layout_name:grid
    tagrule=id:7,layout_name:grid
    tagrule=id:8,layout_name:grid
    tagrule=id:9,layout_name:grid

    # Core binds
    bind=SUPER,q,killclient,
    bind=SUPER,t,togglefloating,
    bind=SUPER,f,togglefullscreen,
    bind=SUPER,Return,spawn,${preferredTerminal}
    bind=SUPER+SHIFT,q,quit

    # Focus movement
    bind=SUPER,h,focusdir,left
    bind=SUPER,l,focusdir,right
    bind=SUPER,k,focusdir,up
    bind=SUPER,j,focusdir,down

    # Tag view (10th tag via 0)
    bind=SUPER,1,view,1,0
    bind=SUPER,2,view,2,0
    bind=SUPER,3,view,3,0
    bind=SUPER,4,view,4,0
    bind=SUPER,5,view,5,0
    bind=SUPER,6,view,6,0
    bind=SUPER,7,view,7,0
    bind=SUPER,8,view,8,0
    bind=SUPER,9,view,9,0
    bind=SUPER,0,view,10,0

    # Move focused client to tag
    bind=SUPER+SHIFT,1,tag,1,0
    bind=SUPER+SHIFT,2,tag,2,0
    bind=SUPER+SHIFT,3,tag,3,0
    bind=SUPER+SHIFT,4,tag,4,0
    bind=SUPER+SHIFT,5,tag,5,0
    bind=SUPER+SHIFT,6,tag,6,0
    bind=SUPER+SHIFT,7,tag,7,0
    bind=SUPER+SHIFT,8,tag,8,0
    bind=SUPER+SHIFT,9,tag,9,0
    bind=SUPER+SHIFT,0,tag,10,0
  '';

  # Simple shell/startup baseline for MangoWC sessions.
  systemd.user.services.mangowc-shell = {
    Unit = {
      Description = "MangoWC session shell startup";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -lc 'pkill -x waybar >/dev/null 2>&1 || true; waybar >/dev/null 2>&1 &'";
      ExecStop = "${pkgs.procps}/bin/pkill -x waybar >/dev/null 2>&1 || true";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
