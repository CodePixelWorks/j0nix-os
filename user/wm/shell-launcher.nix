{ config, inputs, lib, pkgs, settings, ... }:
let
  selectedShell = settings.wmShell or (settings.hyprlandShell or "dank-material-shell");
  dmsSettings = settings.dms or { };
  overviewSettings = dmsSettings.overview or { };
  overviewEnable = overviewSettings.enable or false;
  overviewName = "overview";
  overviewSource = inputs.quickshell-overview;
  dmsStartup = dmsSettings.startup or { };
  dmsStartupMode = dmsStartup.mode or "systemd";
  supportsOverview = builtins.elem selectedShell [ "dank-material-shell" "caelestia-shell" "noctalia-shell" ];
  quickshellBin = if pkgs ? quickshell then lib.getExe pkgs.quickshell else null;
in
{
  j0nix.user.software.packages = with pkgs; [
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
    (writeShellScriptBin "wm-overview-start" ''
      if [ "${if overviewEnable then "1" else "0"}" != "1" ]; then
        echo "quickshell-overview is disabled (settings.dms.overview.enable = false)"
        exit 1
      fi

      if [ "${if supportsOverview then "1" else "0"}" != "1" ]; then
        echo "quickshell-overview is not available for wmShell=${selectedShell}"
        exit 1
      fi

      if ${pkgs.procps}/bin/pgrep -f "quickshell.*-c[[:space:]]*${overviewName}" >/dev/null 2>&1; then
        exit 0
      fi

      if command -v qs >/dev/null 2>&1; then
        nohup qs -c ${overviewName} >/dev/null 2>&1 &
        exit 0
      fi

      if [ -n "${if quickshellBin != null then quickshellBin else ""}" ] && [ -x "${if quickshellBin != null then quickshellBin else "/nonexistent"}" ]; then
        nohup ${if quickshellBin != null then quickshellBin else "true"} -c ${overviewName} >/dev/null 2>&1 &
        exit 0
      fi

      if command -v quickshell >/dev/null 2>&1; then
        nohup quickshell -c ${overviewName} >/dev/null 2>&1 &
        exit 0
      fi

      echo "Neither qs nor quickshell is available in PATH"
      exit 1
    '')
    (writeShellScriptBin "wm-overview-toggle" ''
      if [ "${if overviewEnable then "1" else "0"}" != "1" ]; then
        echo "quickshell-overview is disabled (settings.dms.overview.enable = false)"
        exit 1
      fi

      if [ "${if supportsOverview then "1" else "0"}" != "1" ]; then
        echo "quickshell-overview is not available for wmShell=${selectedShell}"
        exit 1
      fi

      if command -v qs >/dev/null 2>&1; then
        qs ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        wm-overview-start >/dev/null 2>&1 || exit 1
        sleep 0.3
        qs ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        echo "Failed to toggle quickshell-overview via qs ipc"
        exit 1
      fi

      if command -v quickshell >/dev/null 2>&1; then
        quickshell ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        wm-overview-start >/dev/null 2>&1 || exit 1
        sleep 0.3
        quickshell ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        echo "Failed to toggle quickshell-overview via quickshell ipc"
        exit 1
      fi

      if [ -n "${if quickshellBin != null then quickshellBin else ""}" ] && [ -x "${if quickshellBin != null then quickshellBin else "/nonexistent"}" ]; then
        ${if quickshellBin != null then quickshellBin else "true"} ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        wm-overview-start >/dev/null 2>&1 || exit 1
        sleep 0.3
        ${if quickshellBin != null then quickshellBin else "true"} ipc -c ${overviewName} call overview toggle >/dev/null 2>&1 && exit 0
        echo "Failed to toggle quickshell-overview via quickshell ipc"
        exit 1
      fi

      echo "Neither qs nor quickshell is available for overview IPC toggle"
      exit 1
    '')
    (writeShellScriptBin "wm-overview-stop" ''
      if command -v qs >/dev/null 2>&1; then
        qs kill ${overviewName} >/dev/null 2>&1 && exit 0
      fi
      if [ -n "${if quickshellBin != null then quickshellBin else ""}" ] && [ -x "${if quickshellBin != null then quickshellBin else "/nonexistent"}" ]; then
        ${if quickshellBin != null then quickshellBin else "true"} kill ${overviewName} >/dev/null 2>&1 && exit 0
      fi
      if command -v quickshell >/dev/null 2>&1; then
        quickshell kill ${overviewName} >/dev/null 2>&1 && exit 0
      fi
      ${pkgs.procps}/bin/pkill -f "quickshell.*-c[[:space:]]*${overviewName}" >/dev/null 2>&1 || true
    '')
    (writeShellScriptBin "wm-screenshot-full" ''
      out_dir="$HOME/Pictures/Screenshots"
      ts="$(date +%Y-%m-%d_%H-%M-%S)"
      out_file="$out_dir/screenshot-$ts.png"

      mkdir -p "$out_dir"

      if ! command -v grim >/dev/null 2>&1; then
        echo "grim is not available in PATH"
        exit 1
      fi

      grim "$out_file" || exit 1

      if command -v notify-send >/dev/null 2>&1; then
        notify-send "Screenshot saved" "$out_file" >/dev/null 2>&1 || true
      fi
    '')
    (writeShellScriptBin "wm-screenshot-area" ''
      out_dir="$HOME/Pictures/Screenshots"
      ts="$(date +%Y-%m-%d_%H-%M-%S)"
      out_file="$out_dir/screenshot-$ts.png"

      mkdir -p "$out_dir"

      if ! command -v grim >/dev/null 2>&1; then
        echo "grim is not available in PATH"
        exit 1
      fi

      if ! command -v slurp >/dev/null 2>&1; then
        echo "slurp is not available in PATH"
        exit 1
      fi

      region="$(slurp)" || exit 1
      [ -n "$region" ] || exit 1

      grim -g "$region" "$out_file" || exit 1

      if command -v notify-send >/dev/null 2>&1; then
        notify-send "Screenshot saved" "$out_file" >/dev/null 2>&1 || true
      fi
    '')
    (writeShellScriptBin "system-suspend-safe" ''
      timeout_bin="${pkgs.coreutils}/bin/timeout"
      loginctl_bin="${pkgs.systemd}/bin/loginctl"
      systemctl_bin="${pkgs.systemd}/bin/systemctl"

      # Best-effort lock before suspend to avoid resuming on an unlocked session.
      if command -v dms >/dev/null 2>&1; then
        "$timeout_bin" 1s dms ipc call lock lock >/dev/null 2>&1 || true
      fi
      if command -v hyprlock >/dev/null 2>&1; then
        pgrep -x hyprlock >/dev/null 2>&1 || hyprlock >/dev/null 2>&1 &
        sleep 0.5
      else
        "$loginctl_bin" lock-session >/dev/null 2>&1 || true
        sleep 0.3
      fi

      "$loginctl_bin" suspend \
        || "$systemctl_bin" suspend
    '')
    (writeShellScriptBin "system-hibernate-safe" ''
      timeout_bin="${pkgs.coreutils}/bin/timeout"
      loginctl_bin="${pkgs.systemd}/bin/loginctl"
      systemctl_bin="${pkgs.systemd}/bin/systemctl"

      if command -v dms >/dev/null 2>&1; then
        "$timeout_bin" 1s dms ipc call lock lock >/dev/null 2>&1 || true
      fi
      if command -v hyprlock >/dev/null 2>&1; then
        pgrep -x hyprlock >/dev/null 2>&1 || hyprlock >/dev/null 2>&1 &
        sleep 0.5
      else
        "$loginctl_bin" lock-session >/dev/null 2>&1 || true
        sleep 0.3
      fi

      "$loginctl_bin" hibernate \
        || "$systemctl_bin" hibernate
    '')
    (writeShellScriptBin "system-suspend-then-hibernate-safe" ''
      timeout_bin="${pkgs.coreutils}/bin/timeout"
      loginctl_bin="${pkgs.systemd}/bin/loginctl"
      systemctl_bin="${pkgs.systemd}/bin/systemctl"

      if command -v dms >/dev/null 2>&1; then
        "$timeout_bin" 1s dms ipc call lock lock >/dev/null 2>&1 || true
      fi
      if command -v hyprlock >/dev/null 2>&1; then
        pgrep -x hyprlock >/dev/null 2>&1 || hyprlock >/dev/null 2>&1 &
        sleep 0.5
      else
        "$loginctl_bin" lock-session >/dev/null 2>&1 || true
        sleep 0.3
      fi

      "$loginctl_bin" suspend-then-hibernate \
        || "$systemctl_bin" suspend-then-hibernate
    '')
    (writeShellScriptBin "system-reboot-safe" ''
      "${pkgs.systemd}/bin/loginctl" reboot || "${pkgs.systemd}/bin/systemctl" reboot
    '')
    (writeShellScriptBin "system-poweroff-safe" ''
      "${pkgs.systemd}/bin/loginctl" poweroff || "${pkgs.systemd}/bin/systemctl" poweroff
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
          hyprctl dispatch submap global >/dev/null 2>&1 || true
        else
          hyprctl dispatch submap reset >/dev/null 2>&1 || true
        fi
      fi
      pkill fuzzel >/dev/null 2>&1 || true
      exec wm-shell-restart
    '')
  ];

  home.file.".config/quickshell/${overviewName}" = lib.mkIf (overviewEnable && supportsOverview) {
    source = config.lib.file.mkOutOfStoreSymlink "${overviewSource}";
  };

  assertions = [
    {
      assertion = builtins.elem selectedShell [ "ags" "dank-material-shell" "noctalia-shell" "caelestia-shell" "none" ];
      message = "settings.userSettings.<name>.wmShell must be one of: ags, dank-material-shell, noctalia-shell, caelestia-shell, none";
    }
  ];
}
