{ config, lib, pkgs, ... }:
let
  cfg = config.j0nix.desktop.thermal;
  enabled = cfg.enable;
  fanKernelModule = cfg.fan.kernelModule or (cfg.fan.module or null);
  fanHwmonName = cfg.fan.hwmonName or null;
  acpiLax = cfg.fan.acpiEnforceResourcesLax;
  governor = cfg.cpuGovernor;
  fanBoostEnabled = cfg.fan.maxOnGamingPerformanceMode;
  fanBoostScript = pkgs.writeShellScriptBin "thermal-fan-max" ''
    set -eu

    mode="''${1:-}"
    state_root="/var/lib/j0nix-fan-boost"
    mkdir -p "$state_root"

    # Favor the configured hwmon device name, but fall back to any writable pwm-capable device.
    collect_hwmons() {
      local first=1
      local hw name
      for hw in /sys/class/hwmon/hwmon*; do
        [ -d "$hw" ] || continue
        [ -e "$hw/pwm1" ] || continue
        name="$(cat "$hw/name" 2>/dev/null || true)"
        if [ -n "${fanHwmonName}" ] && [ "$name" = "${fanHwmonName}" ]; then
          printf '%s\n' "$hw"
          first=0
        fi
      done
      if [ "$first" -eq 0 ]; then
        return 0
      fi
      for hw in /sys/class/hwmon/hwmon*; do
        [ -d "$hw" ] || continue
        [ -e "$hw/pwm1" ] || continue
        printf '%s\n' "$hw"
      done
    }

    boost_on() {
      local hw pwm idx state_dir
      for hw in $(collect_hwmons); do
        [ -w "$hw" ] || true
        state_dir="$state_root/$(basename "$hw")"
        mkdir -p "$state_dir"
        for pwm in "$hw"/pwm[0-9]*; do
          [ -e "$pwm" ] || continue
          case "$(basename "$pwm")" in
            pwm[0-9]) ;;
            *) continue ;;
          esac
          idx="''${pwm##*/pwm}"
          [ -w "$pwm" ] || continue
          if [ -e "$hw/pwm''${idx}_enable" ] && [ -w "$hw/pwm''${idx}_enable" ]; then
            cat "$hw/pwm''${idx}_enable" >"$state_dir/pwm''${idx}_enable" 2>/dev/null || true
            # 1 = manual on common hwmon drivers (incl. nct6775)
            echo 1 >"$hw/pwm''${idx}_enable" 2>/dev/null || true
          fi
          cat "$pwm" >"$state_dir/pwm''${idx}" 2>/dev/null || true
          echo 255 >"$pwm" 2>/dev/null || true
        done
      done
    }

    boost_off() {
      local hw pwm idx state_dir
      for hw in /sys/class/hwmon/hwmon*; do
        [ -d "$hw" ] || continue
        state_dir="$state_root/$(basename "$hw")"
        [ -d "$state_dir" ] || continue
        for pwm in "$hw"/pwm[0-9]*; do
          [ -e "$pwm" ] || continue
          case "$(basename "$pwm")" in
            pwm[0-9]) ;;
            *) continue ;;
          esac
          idx="''${pwm##*/pwm}"
          if [ -f "$state_dir/pwm''${idx}" ] && [ -w "$pwm" ]; then
            cat "$state_dir/pwm''${idx}" >"$pwm" 2>/dev/null || true
          fi
          if [ -f "$state_dir/pwm''${idx}_enable" ] && [ -w "$hw/pwm''${idx}_enable" ]; then
            cat "$state_dir/pwm''${idx}_enable" >"$hw/pwm''${idx}_enable" 2>/dev/null || true
          fi
        done
        rm -rf "$state_dir"
      done
    }

    case "$mode" in
      start) boost_on ;;
      end) boost_off ;;
      *)
        echo "usage: thermal-fan-max <start|end>" >&2
        exit 2
        ;;
    esac
  '';
in
{
  options.j0nix.desktop.thermal = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    cpuGovernor = lib.mkOption {
      type = lib.types.str;
      default = "schedutil";
    };
    fan = {
      module = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "nct6775";
        description = "Deprecated compatibility alias for fan.kernelModule.";
      };
      kernelModule = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kernel module to load for fan/PWM control (e.g. it87, nct6775).";
      };
      hwmonName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Preferred hwmon device name for PWM fan control (e.g. it8718).";
      };
      acpiEnforceResourcesLax = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      maxOnGamingPerformanceMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set writable hwmon PWM fans to maximum while gamemode performance mode is active, then restore them.";
      };
    };
  };

  config = lib.mkIf enabled {
    boot.kernelModules = lib.optional (fanKernelModule != null && fanKernelModule != "") fanKernelModule;
    boot.kernelParams = lib.optionals acpiLax [ "acpi_enforce_resources=lax" ];

    powerManagement.cpuFreqGovernor = governor;

    environment.systemPackages = with pkgs; [
      lm_sensors
    ] ++ lib.optionals fanBoostEnabled [ fanBoostScript ];

    assertions = [
      {
        assertion = builtins.elem governor [ "performance" "powersave" "ondemand" "conservative" "schedutil" ];
        message = "j0nix.desktop.thermal.cpuGovernor must be one of: performance, powersave, ondemand, conservative, schedutil";
      }
    ];
  };
}
