{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  perf = gaming.performance or { };
  thermal = settings.thermal or { };
  thermalGovernor = thermal.cpuGovernor or "schedutil";
  drivers = settings.drivers or { };
  nvidia = drivers.nvidia or { };
  nvidiaEnabled = nvidia.enable or false;
  expectedVmMaxMapCount = 2147483642;
  expectedSwappiness = 10;
  proton = gaming.proton or { };
  protonProvider = proton.provider or "ge";
  protonCachyos = proton.cachyos or { };
  protonCachyosAutoInstall = protonCachyos.autoInstall or true;
  protonCachyosVariant = protonCachyos.variant or "x86_64";
  protonCachyosKeepVersions = protonCachyos.keepVersions or 2;
  launchers = gaming.launchers or { };
  controllers = gaming.controllers or { };
  rockstarEnabled = launchers.rockstar or false;
  gamescopeEnabled = perf.gamescope or true;
  gamescopeHdrEnabled = perf.gamescopeHdr or true;
  steamSessionRun = pkgs.writeShellScriptBin "steam-session-run" ''
    set -eu

    use_gamescope=0
    proton_mode="x11"
    use_hdr=0
    use_gamemode=0
    use_mangoapp=0
    grab_cursor=1
    launcher_skip=0
    gamescope_host_mode="borderless"
    target_monitor=""
    display_index=""

    usage() {
      cat <<'EOF' >&2
usage: steam-session-run [options] <command> [args...]

Options:
  --gamescope       Run the command inside gamescope
  --x11             Force Proton/Xwayland mode (default)
  --wayland         Force Proton/Wayland mode
  --hdr             Enable HDR in gamescope
  --gamemode        Run the game through gamemoderun
  --mangoapp        Enable gamescope's --mangoapp flag when available
  --grab-cursor     Force relative cursor grab in gamescope (default)
  --no-grab-cursor  Disable forced cursor grab in gamescope
  --target-monitor  Target a specific Hyprland monitor/output for the gamescope host window
  --display-index   Override gamescope's nested display index directly
  --host-fullscreen Run the host gamescope window in fullscreen mode
  --launcher-skip   Append --launcher-skip to the game command
EOF
      exit 2
    }

    log_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/j0nix/gaming"
    mkdir -p "$log_dir"
    log_file="$log_dir/steam-session-run.log"

    log() {
      printf '[%s] %s\n' "$(${pkgs.coreutils}/bin/date -Iseconds)" "$*" >> "$log_file"
    }

    while [ $# -gt 0 ]; do
      case "$1" in
        --gamescope)
          use_gamescope=1
          shift
          ;;
        --x11|--xwayland)
          proton_mode="x11"
          shift
          ;;
        --wayland)
          proton_mode="wayland"
          shift
          ;;
        --hdr)
          use_hdr=1
          shift
          ;;
        --gamemode)
          use_gamemode=1
          shift
          ;;
        --mangoapp)
          use_mangoapp=1
          shift
          ;;
        --grab-cursor)
          grab_cursor=1
          shift
          ;;
        --no-grab-cursor)
          grab_cursor=0
          shift
          ;;
        --target-monitor|--monitor)
          [ $# -ge 2 ] || usage
          target_monitor="$2"
          shift 2
          ;;
        --display-index)
          [ $# -ge 2 ] || usage
          display_index="$2"
          shift 2
          ;;
        --host-fullscreen)
          gamescope_host_mode="fullscreen"
          shift
          ;;
        --launcher-skip)
          launcher_skip=1
          shift
          ;;
        --)
          shift
          break
          ;;
        -*)
          usage
          ;;
        *)
          break
          ;;
      esac
    done

    if [ $# -eq 0 ]; then
      usage
    fi

    cmd=( "$@" )
    if [ "$launcher_skip" = "1" ]; then
      cmd+=( --launcher-skip )
    fi

    log "mode=$proton_mode gamescope=$use_gamescope hdr=$use_hdr gamemode=$use_gamemode mangoapp=$use_mangoapp grab_cursor=$grab_cursor launcher_skip=$launcher_skip host_mode=$gamescope_host_mode target_monitor=$target_monitor display_index=$display_index"
    log "host-env DISPLAY=''${DISPLAY:-} WAYLAND_DISPLAY=''${WAYLAND_DISPLAY:-} XDG_SESSION_TYPE=''${XDG_SESSION_TYPE:-} PROTON_ENABLE_WAYLAND=''${PROTON_ENABLE_WAYLAND:-}"
    printf '[%s] argv:' "$(${pkgs.coreutils}/bin/date -Iseconds)" >> "$log_file"
    for arg in "''${cmd[@]}"; do
      printf ' %q' "$arg" >> "$log_file"
    done
    printf '\n' >> "$log_file"

    child_prefix=()
    if [ "$use_gamemode" = "1" ]; then
      child_prefix+=(${pkgs.gamemode}/bin/gamemoderun)
    fi

    selected_monitor_gamescope_args() {
      local selector selected_args

      if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        if [ -n "$display_index" ]; then
          printf '%s\n' "--display-index $display_index"
        fi
        return 0
      fi

      if [ -n "$target_monitor" ]; then
        selector='to_entries[] | select((.value.name // "") == $target and (.value.disabled // false) == false and (.value.width // 0) > 0 and (.value.height // 0) > 0)'
        selected_args="$(hyprctl -j monitors 2>/dev/null | jq -r --arg target "$target_monitor" --arg display_index "$display_index" '
          '"$selector"' |
          "-W\(.value.width) -H\(.value.height)\(
            if $display_index != \"\" then
              \" --display-index \($display_index)\"
            else
              \" --display-index \(.key)\"
            end
          )"
        ' | head -n 1)"
      else
        selected_args="$(hyprctl -j monitors 2>/dev/null | jq -r --arg display_index "$display_index" '
          to_entries[]
          | select((.value.focused // false) == true and (.value.disabled // false) == false and (.value.width // 0) > 0 and (.value.height // 0) > 0)
          | "-W\(.value.width) -H\(.value.height)\(
              if $display_index != \"\" then
                \" --display-index \($display_index)\"
              else
                \" --display-index \(.key)\"
              end
            )"
        ' | head -n 1)"
      fi

      if [ -n "$selected_args" ]; then
        printf '%s\n' "$selected_args"
      elif [ -n "$display_index" ]; then
        printf '%s\n' "--display-index $display_index"
      fi
    }

    if [ "$use_gamescope" = "1" ]; then
      gamescope_args=()
      case "$gamescope_host_mode" in
        fullscreen)
          gamescope_args+=(-f)
          ;;
        *)
          gamescope_args+=(-b)
          ;;
      esac

      monitor_args="$(selected_monitor_gamescope_args || true)"
      if [ -n "$monitor_args" ]; then
        # Match the focused monitor size in nested mode so the host window behaves like a proper full-screen surface without trapping Alt-Tab behind a real fullscreen host window.
        # shellcheck disable=SC2206
        gamescope_args+=($monitor_args)
      fi

      if [ "$use_hdr" = "1" ]; then
        gamescope_args=(--hdr-enabled "''${gamescope_args[@]}")
      fi

      if [ "$proton_mode" = "wayland" ]; then
        gamescope_args+=(--expose-wayland)
      fi

      if [ "$use_mangoapp" = "1" ]; then
        if command -v mangoapp >/dev/null 2>&1; then
          gamescope_args+=(--mangoapp)
        else
          log "mangoapp requested but not available; continuing without --mangoapp"
        fi
      fi

      if [ "$grab_cursor" = "1" ]; then
        gamescope_args+=(--force-grab-cursor)
      fi

      log "gamescope-args=''${gamescope_args[*]}"
      if [ "$proton_mode" = "wayland" ]; then
        printf '[%s] final-cmd: gamescope %s -- env PROTON_ENABLE_WAYLAND=1 ...\n' "$(${pkgs.coreutils}/bin/date -Iseconds)" "''${gamescope_args[*]}" >> "$log_file"
        exec gamescope "''${gamescope_args[@]}" -- env PROTON_ENABLE_WAYLAND=1 "''${child_prefix[@]}" "''${cmd[@]}"
      else
        printf '[%s] final-cmd: gamescope %s -- ...\n' "$(${pkgs.coreutils}/bin/date -Iseconds)" "''${gamescope_args[*]}" >> "$log_file"
        exec gamescope "''${gamescope_args[@]}" -- "''${child_prefix[@]}" "''${cmd[@]}"
      fi
    fi

    if [ "$proton_mode" = "wayland" ]; then
      printf '[%s] final-cmd: env PROTON_ENABLE_WAYLAND=1 ...\n' "$(${pkgs.coreutils}/bin/date -Iseconds)" >> "$log_file"
      exec env PROTON_ENABLE_WAYLAND=1 "''${child_prefix[@]}" "''${cmd[@]}"
    fi

    printf '[%s] final-cmd: direct ...\n' "$(${pkgs.coreutils}/bin/date -Iseconds)" >> "$log_file"
    exec "''${child_prefix[@]}" "''${cmd[@]}"
  '';
in
lib.mkIf enabled {
  j0nix.user.software.packages = [
    # Steam launch options examples:
    #   steam-session-run --gamemode %command%
    #   steam-session-run --wayland --gamemode %command%
    steamSessionRun
    (pkgs.writeShellScriptBin "steam-session-gamescope" ''
      exec ${lib.getExe steamSessionRun} --gamescope "$@"
    '')
    (pkgs.writeShellScriptBin "steam-session-gamescope-wayland" ''
      exec ${lib.getExe steamSessionRun} --gamescope --wayland "$@"
    '')
    (pkgs.writeShellScriptBin "steam-session-gamescope-hdr" ''
      exec ${lib.getExe steamSessionRun} --gamescope --hdr "$@"
    '')
    (pkgs.writeShellScriptBin "steam-session-gamescope-hdr-wayland" ''
      exec ${lib.getExe steamSessionRun} --gamescope --hdr --wayland "$@"
    '')
    (pkgs.writeShellScriptBin "game-session" ''
      exec "$@"
    '')
    (pkgs.writeShellScriptBin "game-session-gamemode" ''
      exec gamemoderun "$@"
    '')
    (pkgs.writeShellScriptBin "game-ready-check" ''
      set -eu

      ok=0
      warn=0
      fail=0

      check_ok() {
        ok=$((ok + 1))
        printf '[OK] %s\n' "$1"
      }

      check_warn() {
        warn=$((warn + 1))
        printf '[WARN] %s\n' "$1"
      }

      check_fail() {
        fail=$((fail + 1))
        printf '[FAIL] %s\n' "$1"
      }

      check_cmd() {
        cmd="$1"
        label="$2"
        if command -v "$cmd" >/dev/null 2>&1; then
          check_ok "$label"
        else
          check_fail "$label (missing command: $cmd)"
        fi
      }

      echo "=== Game Ready Check ==="
      echo "Host: $(${pkgs.coreutils}/bin/hostname)"
      echo

      # Kernel baseline
      if ${pkgs.coreutils}/bin/uname -r | ${pkgs.gnugrep}/bin/grep -qi "cachyos"; then
        check_ok "CachyOS kernel detected"
      else
        check_warn "Kernel is not CachyOS (current: $(${pkgs.coreutils}/bin/uname -r))"
      fi

      # CPU governor
      governor_file="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
      if [ -r "$governor_file" ]; then
        current_governor="$(${pkgs.coreutils}/bin/cat "$governor_file")"
        if [ "$current_governor" = "${thermalGovernor}" ]; then
          check_ok "CPU governor is ${thermalGovernor}"
        else
          check_warn "CPU governor is $current_governor (expected: ${thermalGovernor})"
        fi
      else
        check_warn "CPU governor file not readable: $governor_file"
      fi

      # Sysctl tuning
      vm_max_map_count="$(${pkgs.procps}/bin/sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
      if [ "$vm_max_map_count" -ge ${toString expectedVmMaxMapCount} ]; then
        check_ok "vm.max_map_count is $vm_max_map_count"
      else
        check_fail "vm.max_map_count is $vm_max_map_count (expected >= ${toString expectedVmMaxMapCount})"
      fi

      swappiness="$(${pkgs.procps}/bin/sysctl -n vm.swappiness 2>/dev/null || echo 999)"
      if [ "$swappiness" -le ${toString expectedSwappiness} ]; then
        check_ok "vm.swappiness is $swappiness"
      else
        check_warn "vm.swappiness is $swappiness (expected <= ${toString expectedSwappiness})"
      fi

      sched_bore_file="/proc/sys/kernel/sched_bore"
      if [ -r "$sched_bore_file" ]; then
        sched_bore="$(${pkgs.coreutils}/bin/cat "$sched_bore_file")"
        if [ "$sched_bore" = "1" ]; then
          check_ok "BORE scheduler toggle is active (kernel.sched_bore=1)"
        else
          check_warn "BORE scheduler toggle is $sched_bore (expected: 1)"
        fi
      else
        check_warn "kernel.sched_bore sysctl not exposed by current kernel"
      fi

      # Core gaming tooling
      check_cmd gamemoderun "Gamemode command available"
      if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet gamemoded.service; then
        check_ok "gamemoded.service active"
      else
        check_warn "gamemoded.service not active"
      fi

      ${
        if (perf.gamescope or true) then
          ''
            check_cmd gamescope "Gamescope installed"
          ''
        else
          ''
            check_warn "Gamescope disabled in settings"
          ''
      }

      ${
        if (perf.mangohud or true) then
          ''
            check_cmd mangohud "MangoHud installed"
          ''
        else
          ''
            check_warn "MangoHud disabled in settings"
          ''
      }

      check_cmd steam "Steam installed"
      check_cmd steam-run "steam-run installed"

      # Proton provider checks
      compat_dir="$HOME/.steam/root/compatibilitytools.d"
      if [ "${protonProvider}" = "cachyos" ]; then
        if ${pkgs.findutils}/bin/find "$compat_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Eqi 'proton.*cachy|cachy.*proton'; then
          check_ok "Proton-CachyOS found in $compat_dir"
        else
          check_warn "Proton-CachyOS not found in $compat_dir (run: proton-cachyos-install)"
        fi
      else
        check_ok "Proton provider set to GE"
      fi

      # NVIDIA checks
      ${
        if nvidiaEnabled then
          ''
            if command -v nvidia-smi >/dev/null 2>&1; then
              if nvidia-smi >/dev/null 2>&1; then
                check_ok "NVIDIA driver responds (nvidia-smi)"
              else
                check_fail "nvidia-smi exists but failed to query driver"
              fi
            else
              check_fail "nvidia-smi missing while NVIDIA is enabled"
            fi

            modeset_file="/sys/module/nvidia_drm/parameters/modeset"
            if [ -r "$modeset_file" ]; then
              modeset="$(${pkgs.coreutils}/bin/cat "$modeset_file")"
              if [ "$modeset" = "Y" ] || [ "$modeset" = "1" ]; then
                check_ok "nvidia_drm modeset enabled ($modeset)"
              else
                check_warn "nvidia_drm modeset disabled ($modeset)"
              fi
            else
              check_warn "nvidia_drm modeset parameter not readable"
            fi
          ''
        else
          ''
            check_warn "NVIDIA checks skipped (drivers.nvidia.enable = false)"
          ''
      }

      echo
      echo "Summary: OK=$ok WARN=$warn FAIL=$fail"
      if [ "$fail" -gt 0 ]; then
        exit 1
      fi
    '')
  ]
  ++ lib.optionals (perf.mangohud or true) [
    # Steam launch options example:
    #   game-session-mangohud %command%
    (pkgs.writeShellScriptBin "game-session-mangohud" ''
      exec mangohud gamemoderun "$@"
    '')
    pkgs.goverlay
  ]
  ++ [
    # Steam launch options examples (Cyberpunk 2077 appid 1091500):
    #   game-session-cyberpunk %command%
    (pkgs.writeShellScriptBin "game-session-cyberpunk" ''
      exec gamemoderun "$@" --launcher-skip
    '')
  ]
  ++ lib.optionals gamescopeEnabled (
    [
      # Steam launch options examples:
      #   game-session-gamescope %command%
      #   game-session-gamescope-wayland %command%
      #   game-session-gamescope --wayland %command%
      #   game-session-gamescope --host-fullscreen %command%
      #   game-session-gamescope --hdr --wayland %command%
      (pkgs.writeShellScriptBin "game-session-gamescope" ''
        exec ${lib.getExe steamSessionRun} --gamescope --gamemode --mangoapp "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-gamescope-wayland" ''
        exec ${lib.getExe steamSessionRun} --gamescope --wayland --gamemode --mangoapp "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-cyberpunk-gamescope" ''
        exec ${lib.getExe steamSessionRun} --gamescope --gamemode --mangoapp --launcher-skip "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-cyberpunk-gamescope-wayland" ''
        exec ${lib.getExe steamSessionRun} --gamescope --wayland --gamemode --mangoapp --launcher-skip "$@"
      '')
    ]
    ++ lib.optionals gamescopeHdrEnabled [
      (pkgs.writeShellScriptBin "game-session-gamescope-hdr" ''
        exec ${lib.getExe steamSessionRun} --gamescope --hdr --gamemode --mangoapp "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-gamescope-hdr-wayland" ''
        exec ${lib.getExe steamSessionRun} --gamescope --hdr --wayland --gamemode --mangoapp "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-cyberpunk-hdr" ''
        exec ${lib.getExe steamSessionRun} --gamescope --hdr --gamemode --mangoapp --launcher-skip "$@"
      '')
      (pkgs.writeShellScriptBin "game-session-cyberpunk-hdr-wayland" ''
        exec ${lib.getExe steamSessionRun} --gamescope --hdr --wayland --gamemode --mangoapp --launcher-skip "$@"
      '')
    ]
  )
  ++ lib.optionals (protonProvider == "cachyos") [
    (pkgs.writeShellScriptBin "proton-cachyos-install" ''
      set -eu

      repo="CachyOS/proton-cachyos"
      variant="${protonCachyosVariant}"
      keep_versions=${toString protonCachyosKeepVersions}

      compat_dir="$HOME/.steam/root/compatibilitytools.d"
      api_url="https://api.github.com/repos/$repo/releases/latest"

      mkdir -p "$compat_dir"
      tmpdir="$(${pkgs.coreutils}/bin/mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT

      echo "Fetching latest Proton-CachyOS release metadata..."
      ${pkgs.curl}/bin/curl -fsSL "$api_url" -o "$tmpdir/release.json"

      pattern="(tar\\.gz|tgz|tar\\.zst|zip)$"
      if [ "$variant" != "x86_64" ]; then
        pattern="$variant.*$pattern"
      fi

      asset_url="$(${pkgs.jq}/bin/jq -r --arg pattern "$pattern" '
        [ .assets[].browser_download_url
          | select(test($pattern; "i"))
          | select(test("sha256|checksum|sig"; "i") | not)
        ][0] // empty
      ' "$tmpdir/release.json")"

      if [ -z "$asset_url" ]; then
        echo "No matching Proton-CachyOS asset found for variant '$variant'."
        echo "Check: https://github.com/$repo/releases/latest"
        exit 1
      fi

      asset_file="$tmpdir/asset.$(${pkgs.coreutils}/bin/basename "$asset_url")"
      echo "Downloading: $asset_url"
      ${pkgs.curl}/bin/curl -fL "$asset_url" -o "$asset_file"

      extract_dir="$tmpdir/extract"
      ${pkgs.coreutils}/bin/mkdir -p "$extract_dir"

      case "$asset_file" in
        *.tar.gz|*.tgz) ${pkgs.gnutar}/bin/tar -xzf "$asset_file" -C "$extract_dir" ;;
        *.tar.zst) ${pkgs.gnutar}/bin/tar --zstd -xf "$asset_file" -C "$extract_dir" ;;
        *.zip) ${pkgs.unzip}/bin/unzip -q "$asset_file" -d "$extract_dir" ;;
        *)
          echo "Unsupported archive format: $asset_file"
          exit 1
          ;;
      esac

      new_dir="$(${pkgs.findutils}/bin/find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | ${pkgs.coreutils}/bin/head -n1)"
      if [ -z "$new_dir" ]; then
        echo "Could not locate extracted Proton directory."
        exit 1
      fi

      target_name="$(${pkgs.coreutils}/bin/basename "$new_dir")"
      target_path="$compat_dir/$target_name"

      rm -rf "$target_path"
      mv "$new_dir" "$target_path"

      echo "Installed Proton-CachyOS to: $target_path"
      echo "Restart Steam and select it in: Settings -> Compatibility"

      if [ "$keep_versions" -gt 0 ]; then
        ${pkgs.findutils}/bin/find "$compat_dir" -mindepth 1 -maxdepth 1 -type d \
          | ${pkgs.gnugrep}/bin/grep -Ei 'proton.*cachy|cachy.*proton' \
          | ${pkgs.coreutils}/bin/sort \
          | ${pkgs.coreutils}/bin/head -n "-$keep_versions" \
          | while read -r old; do
              [ -n "$old" ] && rm -rf "$old"
            done || true
      fi
    '')

    (pkgs.writeShellScriptBin "game-session-umu-cachyos" ''
      set -eu
      compat_dir="$HOME/.steam/root/compatibilitytools.d"
      proton_dir="$(${pkgs.findutils}/bin/find "$compat_dir" -mindepth 1 -maxdepth 1 -type d \
        | ${pkgs.gnugrep}/bin/grep -Ei 'proton.*cachy|cachy.*proton' \
        | ${pkgs.coreutils}/bin/sort \
        | ${pkgs.coreutils}/bin/tail -n1)"

      if [ -z "''${proton_dir:-}" ]; then
        echo "No Proton-CachyOS installation found in $compat_dir"
        echo "Run: proton-cachyos-install"
        exit 1
      fi

      export PROTONPATH="$proton_dir"
      exec ${pkgs.umu-launcher}/bin/umu-run "$@"
    '')
  ]
  ++ lib.optionals (protonProvider == "cachyos" && protonCachyosAutoInstall) [
    (pkgs.writeShellScriptBin "proton-cachyos-ensure" ''
      set -eu
      compat_dir="$HOME/.steam/root/compatibilitytools.d"
      if ! ${pkgs.findutils}/bin/find "$compat_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -Eqi 'proton.*cachy|cachy.*proton'; then
        exec proton-cachyos-install
      fi
    '')
  ]
  ++ lib.optionals rockstarEnabled [
    (pkgs.writeShellScriptBin "rockstar-steam-setup" ''
      set -eu

      base_dir="$HOME/Games/rockstar"
      download_dir="$base_dir/downloads"
      prefix_dir="$base_dir/prefix"
      installer="$download_dir/Rockstar-Games-Launcher.exe"
      installer_url="https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe"

      mkdir -p "$download_dir" "$prefix_dir"

      if [ ! -f "$installer" ]; then
        echo "Downloading Rockstar Games Launcher installer..."
        ${pkgs.curl}/bin/curl -fL "$installer_url" -o "$installer"
      fi

      echo
      echo "Add installer as non-Steam game:"
      echo "  $installer"
      echo
      echo "Recommended Steam Launch Options for installer and launcher:"
      echo "  STEAM_COMPAT_DATA_PATH=$prefix_dir game-session-gamemode %command%"
      echo
      echo "Optional with MangoHud:"
      echo "  STEAM_COMPAT_DATA_PATH=$prefix_dir game-session-mangohud %command%"
    '')
    (pkgs.writeShellScriptBin "rockstar-lutris-setup" ''
      set -eu

      base_dir="$HOME/Games/rockstar-lutris"
      download_dir="$base_dir/downloads"
      prefix_dir="$base_dir/prefix"
      installer="$download_dir/Rockstar-Games-Launcher.exe"
      installer_url="https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe"

      mkdir -p "$download_dir" "$prefix_dir"

      if [ ! -f "$installer" ]; then
        echo "Downloading Rockstar Games Launcher installer..."
        ${pkgs.curl}/bin/curl -fL "$installer_url" -o "$installer"
      fi

      echo
      echo "Lutris fallback setup:"
      echo "1) Open Lutris -> + -> Add locally installed game"
      echo "2) Runner: Wine"
      echo "3) Game options:"
      echo "   Executable: $installer"
      echo "   Wine prefix: $prefix_dir"
      echo "4) Runner options:"
      echo "   Wine version: GE-Proton (latest) or Soda"
      echo "   DXVK: ON, VKD3D: ON, Esync/Fsync: ON"
      echo
      echo "After first install run, switch executable to Launcher.exe inside:"
      echo "  $prefix_dir/drive_c/Program Files*/Rockstar Games/Launcher/"
    '')
  ]
  ++ lib.optionals (controllers.dualsense or true) [ pkgs.dualsensectl ];

  home.file.".config/MangoHud/MangoHud.conf" = lib.mkIf (perf.mangohud or true) {
    text = ''
      preset=1
      font_size=30
      background_alpha=0.0
    '';
  };

  assertions = [
    {
      assertion = builtins.elem protonProvider [
        "cachyos"
        "ge"
      ];
      message = "j0nix.desktop.gaming.proton.provider must be one of: cachyos, ge";
    }
    {
      assertion = builtins.elem protonCachyosVariant [
        "x86_64"
        "x86_64_v3"
        "x86_64_v4"
      ];
      message = "j0nix.desktop.gaming.proton.cachyos.variant must be one of: x86_64, x86_64_v3, x86_64_v4";
    }
    {
      assertion = protonCachyosKeepVersions >= 1;
      message = "j0nix.desktop.gaming.proton.cachyos.keepVersions must be >= 1";
    }
  ];
}
