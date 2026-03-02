{ config, lib, pkgs, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  perfCfg = gaming.performance or { };
  gamemodeRenice = perfCfg.gamemodeRenice or (-10);
  autoPerformanceMode = perfCfg.autoPerformanceMode or true;
  preventIdleLockDuringGame = perfCfg.preventIdleLockDuringGame or true;

  profileSwitcher = pkgs.writeShellScript "gamemode-power-profile-switch" ''
    set -eu

    state_dir="''${XDG_RUNTIME_DIR:-/tmp}/gamemode-power-profile"
    count_file="$state_dir/count"
    prev_file="$state_dir/previous"
    inhibit_pid_file="$state_dir/idle-inhibit.pid"
    mkdir -p "$state_dir"

    get_count() {
      if [ -f "$count_file" ]; then
        cat "$count_file"
      else
        echo 0
      fi
    }

    mode="$1"
    count="$(get_count)"

    if [ "$mode" = "start" ]; then
      if [ "$count" -eq 0 ]; then
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl get >"$prev_file" 2>/dev/null || true
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance >/dev/null 2>&1 || true
        ${lib.optionalString preventIdleLockDuringGame ''
        # Prevent idle-based locking/suspend while a gamemode session is active.
        ${pkgs.systemd}/bin/systemd-inhibit \
          --what=idle \
          --who="gamemode" \
          --why="Active game session" \
          ${pkgs.coreutils}/bin/sleep infinity >/dev/null 2>&1 &
        echo $! >"$inhibit_pid_file"
        ''}
      fi
      echo $((count + 1)) >"$count_file"
      exit 0
    fi

    if [ "$mode" = "end" ]; then
      if [ "$count" -le 1 ]; then
        if [ -f "$prev_file" ]; then
          prev_profile="$(cat "$prev_file")"
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$prev_profile" >/dev/null 2>&1 || true
          rm -f "$prev_file"
        else
          ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced >/dev/null 2>&1 || true
        fi
        ${lib.optionalString preventIdleLockDuringGame ''
        if [ -f "$inhibit_pid_file" ]; then
          inhibit_pid="$(cat "$inhibit_pid_file" 2>/dev/null || true)"
          if [ -n "''${inhibit_pid:-}" ]; then
            kill "$inhibit_pid" >/dev/null 2>&1 || true
          fi
          rm -f "$inhibit_pid_file"
        fi
        ''}
        rm -f "$count_file"
      else
        echo $((count - 1)) >"$count_file"
      fi
      exit 0
    fi

    echo "usage: $0 <start|end>" >&2
    exit 2
  '';
in
lib.mkIf enabled {
  services.power-profiles-daemon.enable = lib.mkIf autoPerformanceMode true;

  programs.gamemode = lib.mkIf (perfCfg.gamemode or true) {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        # Negative nice gives game processes more CPU priority.
        renice = gamemodeRenice;
      };
    } // lib.optionalAttrs autoPerformanceMode {
      custom = {
        start = "${profileSwitcher} start";
        end = "${profileSwitcher} end";
      };
    };
  };

  j0nix.software.systemPackages =
    lib.optionals (perfCfg.gamescope or true) [
      pkgs.gamescope
    ]
    ++ lib.optionals (perfCfg.mangohud or true) [
      (pkgs.mangohud.override { lowerBitnessSupport = true; })
    ];

  assertions = [
    {
      assertion = gamemodeRenice >= -20 && gamemodeRenice <= 19;
      message = "j0nix.desktop.gaming.performance.gamemodeRenice must be between -20 and 19";
    }
    {
      assertion = builtins.isBool autoPerformanceMode;
      message = "j0nix.desktop.gaming.performance.autoPerformanceMode must be a boolean";
    }
    {
      assertion = builtins.isBool preventIdleLockDuringGame;
      message = "j0nix.desktop.gaming.performance.preventIdleLockDuringGame must be a boolean";
    }
  ];
}
