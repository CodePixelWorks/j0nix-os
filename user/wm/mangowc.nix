{ config, inputs, lib, pkgs, settings, ... }:
let
  preferredTerminal = settings.preferredTerminal or "kitty";
  homeBinDir = "${config.home.profileDirectory}/bin";
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  useDmsShell = selectedShell == "dank-material-shell";
  dms = (settings.dms or { });
  dmsMode = dms.mode or "integrated";
  integratedMode = dmsMode == "integrated";

  hasSystemPackages =
    (inputs.dank-material-shell ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.dank-material-shell.packages);
  hasPackage =
    hasSystemPackages
    && (inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system} ? default);
  mangowcSessionCheckScript = pkgs.writeShellScript "wm-mangowc-session-check" ''
    case "''${XDG_CURRENT_DESKTOP:-}:''${XDG_SESSION_DESKTOP:-}" in
      *mangowc*|*MangoWC*) exit 0 ;;
    esac
    exit 1
  '';
  wlPasteExe = lib.getExe' pkgs.wl-clipboard "wl-paste";
  cliphistExe = lib.getExe pkgs.cliphist;
in
{
  j0nix.user.software.packages =
    (with pkgs; [
      wlr-randr
      wtype
      wl-clipboard
      cliphist
      libnotify
      coreutils
      procps
      qt6.qtwayland
      libsForQt5.qt5.qtwayland
    ])
    ++ lib.optionals (pkgs ? mmsg) [ pkgs.mmsg ];

  programs.waybar.enable = lib.mkForce false;

  # MangoWC reads ~/.config/mango/config.conf
  xdg.configFile = {
    "mango/config.conf".text = ''
    # Keep defaults minimal but usable.
    xkb_rules_layout=${settings.keyboardLayout or "de"}
    repeat_rate=25
    repeat_delay=600
    cursor_size=24

    # Environment
    env=QT_QPA_PLATFORM,wayland
    env=ELECTRON_OZONE_PLATFORM_HINT,auto
    env=QT_QPA_PLATFORMTHEME,gtk3

    # Startup

    # Appearance
    border_radius=12
    borderpx=0
    focused_opacity=1.0
    unfocused_opacity=0.9
    gappih=5
    gappiv=5
    gappoh=5
    gappov=5
    shadows=1
    shadow_only_floating=1
    shadows_size=10
    shadows_blur=15

${lib.optionalString useDmsShell ''
    # DMS generated files
    source=~/.config/mango/dms/colors.conf
    source=~/.config/mango/dms/layout.conf
    source=~/.config/mango/dms/outputs.conf

    # DMS layer behavior
    layerrule=noanim:1,layer_name:^dms
''}

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
    tagrule=id:10,layout_name:grid

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

${lib.optionalString useDmsShell ''
    # DMS keybinds
    bind=SUPER,space,spawn,dms ipc call spotlight toggle
    bind=SUPER,v,spawn,dms ipc call clipboard toggle
    bind=SUPER,m,spawn,dms ipc call processlist focusOrToggle
    bind=SUPER,comma,spawn,dms ipc call settings focusOrToggle
    bind=SUPER,n,spawn,dms ipc call notifications toggle
    bind=SUPER,y,spawn,dms ipc call dankdash wallpaper
    bind=SUPER+ALT,l,spawn,dms ipc call lock lock
    bind=NONE,XF86AudioRaiseVolume,spawn,dms ipc call audio increment 3
    bind=NONE,XF86AudioLowerVolume,spawn,dms ipc call audio decrement 3
    bind=NONE,XF86AudioMute,spawn,dms ipc call audio mute
    bind=NONE,XF86MonBrightnessUp,spawn,dms ipc call brightness increment 5
    bind=NONE,XF86MonBrightnessDown,spawn,dms ipc call brightness decrement 5
''}

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

    # Window rules
    windowrule=isnoborder:1,appid:^org\.gnome\.
    windowrule=isnoborder:1,appid:^org\.wezfurlong\.wezterm$
    windowrule=isnoborder:1,appid:^Alacritty$
    windowrule=isnoborder:1,appid:^com\.mitchellh\.ghostty$
    windowrule=isnoborder:1,appid:^kitty$
${lib.optionalString useDmsShell ''
    windowrule=isfloating:1,appid:^org\.quickshell$
''}
  '';
  } // lib.optionalAttrs useDmsShell {
    "mango/dms/colors.conf".text = "";
    "mango/dms/layout.conf".text = "";
    "mango/dms/outputs.conf".text = "";
  };

  systemd.user.services = {
    mangowc-shell = {
      Unit = {
        Description = "MangoWC shell startup";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecCondition = mangowcSessionCheckScript;
        ExecStart = "${homeBinDir}/wm-shell-start";
        ExecStop = "${homeBinDir}/wm-shell-stop";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    mangowc-cliphist = {
      Unit = {
        Description = "MangoWC clipboard history watcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecCondition = mangowcSessionCheckScript;
        ExecStart = "${wlPasteExe} --type text --watch ${cliphistExe} store";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  assertions = [
    {
      assertion = builtins.elem dmsMode [ "integrated" "separate" ];
      message = "settings.dms.mode must be one of: integrated, separate";
    }
    {
      assertion = (!useDmsShell) || (!integratedMode) || hasPackage;
      message = "MangoWC + integrated DMS requires inputs.dank-material-shell.packages.<system>.default";
    }
  ];
}
