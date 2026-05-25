{
  lib,
  pkgs,
  hyprlandDebug,
  app2unitExec,
  uwsmExec,
}:
let
  cfg = hyprlandDebug.keybindDiagnostics or { };
  logDir = cfg.logDir or "\${XDG_STATE_HOME:-$HOME/.local/state}/hyprland/diagnostics";
in
{
  keybindDiagnosticsEnable = cfg.enable or false;
  keybindDiagnosticsDelaySeconds = cfg.delaySeconds or 8;
  keybindDiagnosticsLogDir = logDir;
  keybindDiagnosticsProbeScript = pkgs.writeShellScriptBin "wm-hypr-keybind-probe" ''
    set -eu
    label="''${1:-unknown}"
    log_dir="${logDir}"
    mkdir -p "$log_dir"
    log_file="$log_dir/keybind-probe.log"
    printf '%s label=%s uid=%s wayland=%s hypr=%s\n' \
      "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)" \
      "$label" \
      "$(${pkgs.coreutils}/bin/id -u)" \
      "''${WAYLAND_DISPLAY:-}" \
      "''${HYPRLAND_INSTANCE_SIGNATURE:-}" >>"$log_file"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Hyprland keybind probe" "$label" >/dev/null 2>&1 || true
    fi
  '';
  keybindDiagnosticsScript = pkgs.writeShellScriptBin "wm-hypr-keybind-dump" ''
    set -eu

    phase="''${1:-manual}"
    case "$phase" in
      --phase=*) phase="''${phase#--phase=}" ;;
    esac

    log_dir="${logDir}"
    mkdir -p "$log_dir"

    ts="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
    out_file="$log_dir/keybinds-$ts-$phase.log"

    run_hyprctl() {
      label="$1"
      shift
      echo
      echo "## $label"
      if command -v hyprctl >/dev/null 2>&1; then
        hyprctl "$@" 2>&1 || true
      else
        echo "hyprctl not found in PATH"
      fi
    }

    run_cmd() {
      label="$1"
      shift
      echo
      echo "## $label"
      "$@" 2>&1 || true
    }

    {
      echo "# Hyprland keybind diagnostics"
      echo "timestamp=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      echo "phase=$phase"
      echo "pid=$$"
      echo "user=''${USER:-unknown}"
      echo "uid=$(${pkgs.coreutils}/bin/id -u)"
      echo "session_type=''${XDG_SESSION_TYPE:-}"
      echo "session_class=''${XDG_SESSION_CLASS:-}"
      echo "desktop=''${XDG_CURRENT_DESKTOP:-}"
      echo "wayland_display=''${WAYLAND_DISPLAY:-}"
      echo "hypr_instance=''${HYPRLAND_INSTANCE_SIGNATURE:-}"
      echo "xdg_runtime_dir=''${XDG_RUNTIME_DIR:-}"
      echo "path=$PATH"

      run_hyprctl "version" version
      run_hyprctl "instances" instances
      run_hyprctl "activeworkspace" activeworkspace
      run_hyprctl "configerrors" configerrors
      run_hyprctl "globalshortcuts" globalshortcuts
      run_hyprctl "binds" binds
      run_hyprctl "devices" devices
      run_hyprctl "layers" layers
      run_cmd "app2unit probe" ${app2unitExec} -- true
      run_cmd "uwsm app probe" ${uwsmExec} app -- true
    } >"$out_file"

    echo "$out_file"
  '';
}
