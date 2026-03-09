{ lib, pkgs, settings, ... }:
let
  preferredTerminal = settings.preferredTerminal or "kitty";
  niriSessionCheckScript = pkgs.writeShellScript "wm-niri-session-check" ''
    case "''${XDG_CURRENT_DESKTOP:-}:''${XDG_SESSION_DESKTOP:-}" in
      *niri*|*Niri*) exit 0 ;;
    esac
    exit 1
  '';
  wlPasteExe = lib.getExe' pkgs.wl-clipboard "wl-paste";
  cliphistExe = lib.getExe pkgs.cliphist;
in
{
  j0nix.user.software.packages = with pkgs; [
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

    binds {
      Mod+Q { close-window; }
      Mod+T { toggle-window-floating; }
      Mod+F { fullscreen-window; }
      Mod+Return { spawn "${preferredTerminal}"; }
    }
  '';

  systemd.user.services = {
    niri-shell = {
      Unit = {
        Description = "Niri shell startup";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecCondition = niriSessionCheckScript;
        ExecStart = "${lib.getExe pkgs.bash} -lc 'exec wm-shell-start'";
        ExecStop = "${lib.getExe pkgs.bash} -lc 'wm-shell-stop >/dev/null 2>&1 || true'";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    niri-cliphist = {
      Unit = {
        Description = "Niri clipboard history watcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecCondition = niriSessionCheckScript;
        ExecStart = "${wlPasteExe} --type text --watch ${cliphistExe} store";
        Restart = "always";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  programs.waybar.enable = lib.mkForce false;
}
