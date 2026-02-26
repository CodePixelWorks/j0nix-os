{ lib, pkgs, settings, ... }:
let
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  dmsSettings = settings.dms or { };
  dmsStartup = dmsSettings.startup or { };
  dmsStartupMode = dmsStartup.mode or "systemd";
in
{
  home.packages = with pkgs; [
    (writeShellScriptBin "wm-kbd-layout-toggle" ''
      # Generic entrypoint for a DMS action button. Runtime switching support is WM-specific.
      if command -v hyprctl >/dev/null 2>&1; then
        if hyprctl switchxkblayout current next >/dev/null 2>&1 \
          || hyprctl switchxkblayout all next >/dev/null 2>&1; then
          command -v notify-send >/dev/null 2>&1 && notify-send "Keyboard Layout" "Switched (Hyprland)" >/dev/null 2>&1 || true
          exit 0
        fi
      fi

      command -v notify-send >/dev/null 2>&1 && notify-send "Keyboard Layout" "Runtime switch not implemented for current WM" >/dev/null 2>&1 || true
      exit 1
    '')
    (writeShellScriptBin "wm-shell-start" ''
      shell="${selectedShell}"

      case "$shell" in
        none)
          exit 0
          ;;
        ags)
          killall -q ags 2>/dev/null || true
          sleep 0.3
          exec ags
          ;;
        noctalia-shell)
          exec noctalia-start
          ;;
        caelestia-shell)
          exec caelestia-start
          ;;
        dank-material-shell)
          if [ "${dmsStartupMode}" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
            for unit in dank-material-shell.service dank-material-shell dms.service; do
              if systemctl --user cat "$unit" >/dev/null 2>&1; then
                systemctl --user start "$unit" >/dev/null 2>&1 || true
                exit 0
              fi
            done
          fi
          exec dms-start
          ;;
        *)
          echo "Unknown wmShell: $shell"
          exit 1
          ;;
      esac
    '')
    (writeShellScriptBin "system-suspend-safe" ''
      # Best-effort lock before suspend to avoid resuming on an unlocked session.
      if command -v dms >/dev/null 2>&1; then
        dms ipc call lock lock >/dev/null 2>&1 || true
      fi
      if command -v hyprlock >/dev/null 2>&1; then
        hyprlock >/dev/null 2>&1 &
        sleep 0.5
      else
        loginctl lock-session >/dev/null 2>&1 || true
        sleep 0.3
      fi

      loginctl suspend || systemctl suspend
    '')
    (writeShellScriptBin "system-hibernate-safe" ''
      if command -v hyprlock >/dev/null 2>&1; then
        hyprlock >/dev/null 2>&1 &
        sleep 0.5
      else
        loginctl lock-session >/dev/null 2>&1 || true
        sleep 0.3
      fi

      loginctl hibernate || systemctl hibernate
    '')
    (writeShellScriptBin "system-reboot-safe" ''
      loginctl reboot || systemctl reboot
    '')
    (writeShellScriptBin "system-poweroff-safe" ''
      loginctl poweroff || systemctl poweroff
    '')
    (writeShellScriptBin "wm-shell-stop" ''
      shell="${selectedShell}"

      case "$shell" in
        none)
          exit 0
          ;;
        ags)
          killall -q ags 2>/dev/null || true
          ;;
        noctalia-shell)
          exec noctalia-stop
          ;;
        caelestia-shell)
          exec caelestia-stop
          ;;
        dank-material-shell)
          if [ "${dmsStartupMode}" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
            for unit in dank-material-shell.service dank-material-shell dms.service; do
              if systemctl --user cat "$unit" >/dev/null 2>&1; then
                systemctl --user stop "$unit" >/dev/null 2>&1 || true
                exit 0
              fi
            done
          fi
          exec dms-stop
          ;;
        *)
          echo "Unknown wmShell: $shell"
          exit 1
          ;;
      esac
    '')
    (writeShellScriptBin "wm-shell-restart" ''
      shell="${selectedShell}"

      case "$shell" in
        none)
          exit 0
          ;;
        ags)
          killall -q ags 2>/dev/null || true
          sleep 0.2
          exec ags
          ;;
        noctalia-shell|caelestia-shell)
          wm-shell-stop >/dev/null 2>&1 || true
          sleep 0.2
          exec wm-shell-start
          ;;
        dank-material-shell)
          if [ "${dmsStartupMode}" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
            for unit in dank-material-shell.service dank-material-shell dms.service; do
              if systemctl --user cat "$unit" >/dev/null 2>&1; then
                systemctl --user restart "$unit" >/dev/null 2>&1 || systemctl --user start "$unit" >/dev/null 2>&1 || true
                exit 0
              fi
            done
          fi
          wm-shell-stop >/dev/null 2>&1 || true
          sleep 0.3
          exec wm-shell-start
          ;;
        *)
          echo "Unknown wmShell: $shell"
          exit 1
          ;;
      esac
    '')
    (writeShellScriptBin "wm-shell-recover" ''
      # Recover from stuck input/layer states before restarting the shell UI.
      if command -v hyprctl >/dev/null 2>&1; then
        if [ "${selectedShell}" = "caelestia-shell" ]; then
          # Caelestia keeps keybinds in the persistent "global" submap.
          hyprctl dispatch submap global >/dev/null 2>&1 || true
        else
          hyprctl dispatch submap reset >/dev/null 2>&1 || true
        fi
      fi
      pkill fuzzel >/dev/null 2>&1 || true
      exec wm-shell-restart
    '')
  ];

  assertions = [
    {
      assertion = builtins.elem selectedShell [ "ags" "dank-material-shell" "noctalia-shell" "caelestia-shell" "none" ];
      message = "settings.wmShell must be one of: ags, dank-material-shell, noctalia-shell, caelestia-shell, none";
    }
  ];
}
