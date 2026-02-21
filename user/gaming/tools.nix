{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  perf = gaming.performance or { };
  thermal = settings.thermal or { };
  thermalGovernor = thermal.cpuGovernor or "schedutil";
  drivers = settings.drivers or { };
  nvidia = drivers.nvidia or { };
  nvidiaEnabled = nvidia.enable or false;
  sysctlProfiles = settings.sysctlProfiles or { };
  sysctlGaming = sysctlProfiles.gaming or { };
  expectedVmMaxMapCount = sysctlGaming.vmMaxMapCount or 2147483642;
  expectedSwappiness = sysctlGaming.swappiness or 10;
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
in
lib.mkIf enabled {
  home.packages =
    [
      # Steam launch options examples:
      #   game-session %command%
      #   game-session-gamemode %command%
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

        ${if (perf.gamescope or true) then ''
        check_cmd gamescope "Gamescope installed"
        '' else ''
        check_warn "Gamescope disabled in settings"
        ''}

        ${if (perf.mangohud or true) then ''
        check_cmd mangohud "MangoHud installed"
        '' else ''
        check_warn "MangoHud disabled in settings"
        ''}

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
        ${if nvidiaEnabled then ''
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
        '' else ''
        check_warn "NVIDIA checks skipped (drivers.nvidia.enable = false)"
        ''}

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
    ++ lib.optionals (gamescopeEnabled && gamescopeHdrEnabled) [
      # Steam launch options example:
      #   game-session-gamescope-hdr %command%
      (pkgs.writeShellScriptBin "game-session-gamescope-hdr" ''
        exec gamescope --hdr-enabled --expose-wayland -- gamemoderun "$@"
      '')
    ]
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
      assertion = builtins.elem protonProvider [ "cachyos" "ge" ];
      message = "settings.gaming.proton.provider must be one of: cachyos, ge";
    }
    {
      assertion = builtins.elem protonCachyosVariant [ "x86_64" "x86_64_v3" "x86_64_v4" ];
      message = "settings.gaming.proton.cachyos.variant must be one of: x86_64, x86_64_v3, x86_64_v4";
    }
    {
      assertion = protonCachyosKeepVersions >= 1;
      message = "settings.gaming.proton.cachyos.keepVersions must be >= 1";
    }
  ];
}
