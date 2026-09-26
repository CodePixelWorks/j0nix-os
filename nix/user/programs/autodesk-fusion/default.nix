{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).autodeskFusion or { };
  enabled = cfg.enable or false;

  # Lolig4 keeps independent prefixes per runner. Do not reuse the legacy
  # cryinkfly prefix: it is retained as a rollback source until the patched
  # runner has been verified.
  installDir = cfg.installDir or "$HOME/.local/share/Autodesk-Unofficial";
  installerMode = cfg.installerMode or "fusion-wine";
  protonVersion = cfg.protonVersion or "GE-Proton11-Fusion";
  gpuBackend = cfg.gpuBackend or "auto";
  extensions = cfg.extensions or false;
  # The upstream add-in regularly refreshes the canvas. It is required on
  # systems where Fusion otherwise leaves the DXVK viewport white.
  viewportRefreshForcer = cfg.viewportRefreshForcer or true;
  autoSetupOnLogin = cfg.autoSetupOnLogin or false;
  runnerName = cfg.runner or "wineWow64Packages.stagingFull";
  setAsDefaultLoginHandler = cfg.setAsDefaultLoginHandler or true;

  runner =
    if runnerName == "wineWow64Packages.stagingFull" then
      pkgs.wineWow64Packages.stagingFull
    else
      throw "Unsupported settings.programs.autodeskFusion.runner: ${runnerName}";

  installerUrl =
    cfg.installerUrl or
      "https://codeberg.org/Lolig4/Autodesk-Fusion-360-on-Linux/raw/branch/main/files/setup/autodesk_fusion_installer_x86-64.sh";

  runtimePackages = with pkgs; [
    runner
    winetricks
    dxvk
    cabextract
    p7zip
    curl
    wget
    samba
    mesa-demos
    vulkan-tools
    xrandr
    desktop-file-utils
    xdg-utils
    bc
    polkit
    lsb-release
    gawk
    gnugrep
    gnused
    findutils
    coreutils
    bash
    gettext
    systemd
    procps
    pciutils
    gnutar
    glibc.bin
    mokutil
    gnutls
    msitools
    util-linux
    qt6.qttools
    zenity
  ];

  commonShell = ''
    # shellcheck disable=SC2016
    raw_install_dir=${lib.escapeShellArg installDir}
    # shellcheck disable=SC2016
    case "$raw_install_dir" in
      '$HOME'/*)
        install_dir="$HOME/''${raw_install_dir#\$HOME/}"
        ;;
      '~'/*)
        install_dir="$HOME/''${raw_install_dir#~/}"
        ;;
      *)
        install_dir="$raw_install_dir"
        ;;
    esac

    prefix_dir="$install_dir/wineprefixes/default"
    proton_prefix_dir="$install_dir/protonprefix/pfx"
    : "$prefix_dir" "$proton_prefix_dir"

    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
    export SDL_VIDEODRIVER=x11
    unset WAYLAND_DISPLAY
    # The prebuilt Lolig4 runner dynamically loads libgnutls for Schannel.
    # Keep this narrow: do not reintroduce Mesa/GLVND path overrides.
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.gnutls pkgs.freetype pkgs.pkgsi686Linux.freetype ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    # v2.1.7: on NVIDIA hosts Wine's default Mesa libEGL fails to bind the GPU
    # ("failed to create dri2 screen", driver (null)) and Fusion exits with 53
    # before any window opens.  Pin the GLVND vendor explicitly to the NVIDIA
    # ICD; this only changes *which* EGL implementation is loaded, not the
    # search path (LD_LIBRARY_PATH stays untouched, so Mesa swrast cannot drift
    # in like the earlier 74b176f override did and OOM the process).
    if [ -f /run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
      export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json
    fi
  '';

  cleanInheritedQtEnvironment = ''
    # Fusion ships its own Windows Qt/Chromium stack. Do not let the
    # surrounding Nix/Flatpak session inject host Qt plugins, QML imports, or
    # a desktop theme into Wine: those libraries are ABI-incompatible and can
    # leave Electron/Fusion panes black after the native window is created.
    unset QML2_IMPORT_PATH
    unset QT_AUTO_SCREEN_SCALE_FACTOR
    unset QT_PLUGIN_PATH
    unset QT_QPA_PLATFORMTHEME
    unset QT_STYLE_OVERRIDE
    unset QT_WAYLAND_DISABLE_WINDOWDECORATION
    unset QTWEBKIT_PLUGIN_PATH
    unset ELECTRON_OZONE_PLATFORM_HINT
    unset XDG_BACKEND
  '';

  runFusionTarget = ''
    run_fusion_target() {
      target="$1"
      shift

      wine_mode="$(sed -n '4p' "$install_dir/logs/wineprefixes.log" 2>/dev/null || true)"
      case "$wine_mode" in
        ""|Wine)
          export WINEPREFIX="$prefix_dir"
          exec wine "$target" "$@"
          ;;
        Wine-fix)
          fusion_wine_dir="$HOME/fusion-wine-build/bin"
          if [ ! -x "$fusion_wine_dir/wine" ]; then
            echo "error: Fusion's patched Wine runtime is missing: $fusion_wine_dir/wine" >&2
            echo "Run: autodesk-fusion-repair" >&2
            exit 1
          fi
          export WINEPREFIX="$prefix_dir"
          export WINESERVER="$fusion_wine_dir/wineserver"
          exec "$fusion_wine_dir/wine" "$target" "$@"
          ;;
        *)
          steam_dir=""
          for candidate in \
            "$HOME/.local/share/Steam" \
            "$HOME/.steam/steam" \
            "$HOME/.steam/root" \
            "$HOME/.steam/debian-installation"; do
            if [ -x "$candidate/compatibilitytools.d/$wine_mode/proton" ]; then
              steam_dir="$candidate"
              break
            fi
          done
          if [ -z "$steam_dir" ]; then
            echo "error: Fusion's Proton runtime '$wine_mode' was not found in Steam compatibilitytools.d." >&2
            echo "Install that compatibility tool in Steam, then run autodesk-fusion-repair." >&2
            exit 1
          fi
          export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_dir"
          export STEAM_COMPAT_DATA_PATH="$install_dir/protonprefix"
          exec "$steam_dir/compatibilitytools.d/$wine_mode/proton" run "$target" "$@"
          ;;
      esac
    }
  '';

  protectedInstallerEnv = ''
    guard_bin="$(mktemp -d)"
    cleanup_guard() {
      rm -rf "$guard_bin"
    }
    trap cleanup_guard EXIT

    cat >"$guard_bin/sudo" <<'EOF'
    #!/usr/bin/env bash
    echo "error: refusing to run sudo from the Autodesk Fusion installer; install missing dependencies through Nix." >&2
    exit 126
    EOF
    cat >"$guard_bin/pkexec" <<'EOF'
    #!/usr/bin/env bash
    echo "error: refusing to run pkexec from the Autodesk Fusion installer; install missing dependencies through Nix." >&2
    exit 126
    EOF
    chmod +x "$guard_bin/sudo" "$guard_bin/pkexec"
    export PATH="$guard_bin:$PATH"
  '';

  protonInstallerRuntime = lib.optionalString (installerMode == "proton") ''
    # Bootstrap WebView2 and FusionClient through XWayland. CachyOS
    # WineWayland can launch Fusion itself, but its quiet client installer
    # creates no window or network request when it is initialized as Wayland.
    # commonShell has already selected the X11 environment for this phase.
    export PROTON_ENABLE_WAYLAND=0

    # Fusion does not require Wine's Bluetooth device driver. On the CachyOS
    # WineWayland build it can crash the Fusion client installer in winebth.sys
    # through the host BlueZ stack. Keep wineusb enabled for USB devices such
    # as SpaceMouse.
    export WINEDLLOVERRIDES="''${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}winebth.sys=d"

    # The WineWayland driver is initialized by Proton's entry point, not by a
    # bare Wine binary. Route upstream's direct Wine calls through Proton while
    # remaining on the host namespace (unlike steam-run/Bubblewrap).
    cat >"$guard_bin/j0nix-proton-run" <<'EOF'
    #!/usr/bin/env bash
    export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.vulkan-loader ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PROTON_ENABLE_WAYLAND=0
    exec "$J0NIX_PROTON_DIRECTORY/proton" run "$@"
    EOF
    chmod +x "$guard_bin/j0nix-proton-run"
    export J0NIX_PROTON_RUNNER="$guard_bin/j0nix-proton-run"

    # The runner uses the host namespace so the browser callback can reach
    # Fusion's local SSO server. nix-ld.nix supplies the i686 loader path;
    # Proton's Python bootstrap still needs the host Vulkan loader directly.
    # shellcheck disable=SC2016
    sed -i \
      -e 's|WINE="$PROTON_DIRECTORY/files/bin/wine"|export J0NIX_PROTON_DIRECTORY="$PROTON_DIRECTORY"\n        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_DIRECTORY"\n        export STEAM_COMPAT_DATA_PATH="$PROTON_COMPAT_DIRECTORY"\n        WINE="$J0NIX_PROTON_RUNNER"|' \
      -e 's|"$PROTON_DIRECTORY/proton" run wineboot --init|LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.vulkan-loader ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$PROTON_DIRECTORY/proton" run wineboot --init|' \
      "$installer"
  '';

  installerLock = ''
    lock_file="$install_dir/.j0nix-fusion-installer.lock"
    # Keep a single writer for the upstream active-prefix logs, but make the
    # flock helper close its descriptor before invoking this script. Otherwise
    # Steam inherits it and a completed installer can leave the lock held.
    if [ -z "''${J0NIX_FUSION_INSTALLER_LOCKED:-}" ]; then
      export J0NIX_FUSION_INSTALLER_LOCKED=1
      flock -n -o "$lock_file" "$0" "$@"
      status=$?
      if [ "$status" -eq 1 ]; then
        echo "error: another Autodesk Fusion installation or repair is already running." >&2
        echo "Wait for it to finish before starting a new one." >&2
      fi
      exit "$status"
    fi
  '';

  cleanupUpstreamDesktopEntries = ''
    applications_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    fusion_desktop_dir="$applications_dir/wine/Programs/Autodesk"

    if [ -d "$fusion_desktop_dir" ]; then
      # Home Manager owns the two canonical desktop entries below.  The
      # upstream installer and Wine write duplicate entries, sometimes in
      # numbered subdirectories below this path.
      find "$fusion_desktop_dir" -type f \
        \( -name 'Autodesk Fusion.desktop' -o -name 'adskidmgr-opener.desktop' \) \
        -delete
      find "$fusion_desktop_dir" -depth -type d -empty -delete
    fi
  '';

  postInstallDesktopFix = ''
    ${cleanupUpstreamDesktopEntries}
    # Fusion invokes this helper from inside Proton for adskidmgr: callbacks.
    # Do not retain the install-time wrapper path saved by the upstream script.
    cat >"$install_dir/bin/adskidmgr-opener.sh" <<'EOF'
    #!/usr/bin/env sh
    exec "$HOME/.nix-profile/bin/autodesk-fusion-adskidmgr" "$@"
    EOF
    chmod +x "$install_dir/bin/adskidmgr-opener.sh"
    update-desktop-database "$applications_dir" 2>/dev/null || true
    xdg-mime default autodesk-fusion-adskidmgr.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
  '';

  applyGpuBackendPolicy = ''
    configured_gpu_backend=${lib.escapeShellArg gpuBackend}
    case "$configured_gpu_backend" in
      auto)
        ;;
      DXVK|OpenGL)
        sed -i \
          -e "/^[[:space:]]*check_gpu_driver$/a\\
            GPU_DRIVER=\"$configured_gpu_backend\"" \
          -e "/^[[:space:]]*GPU_DRIVER=\"$configured_gpu_backend\"$/a\\
            echo \"j0nix: forced Autodesk Fusion GPU backend: $configured_gpu_backend\"" \
          "$installer"
        ;;
    esac
  '';

  rendererScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-renderer";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}

      mode="''${1:-status}"

      if [ ! -d "$prefix_dir" ]; then
        echo "error: Autodesk Fusion Wine prefix does not exist: $prefix_dir" >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      user_name="$(id -un)"
      appdata_dir="$prefix_dir/drive_c/users/$user_name/AppData"
      options_paths=(
        "$appdata_dir/Roaming/Autodesk/Neutron Platform/Options/NMachineSpecificOptions.xml"
        "$appdata_dir/Local/Autodesk/Neutron Platform/Options/NMachineSpecificOptions.xml"
        "$prefix_dir/drive_c/users/$user_name/Application Data/Autodesk/Neutron Platform/Options/NMachineSpecificOptions.xml"
      )
      wineprefix_log="$install_dir/logs/wineprefixes.log"

      current_renderer() {
        if [ -f "$wineprefix_log" ]; then
          head -n 1 "$wineprefix_log"
          return
        fi

        for options_file in "''${options_paths[@]}"; do
          if [ -f "$options_file" ]; then
            if iconv -f UTF-16 -t UTF-8 "$options_file" 2>/dev/null | grep -q 'VirtualDeviceGLCore'; then
              echo "OpenGL"
              return
            fi
            if iconv -f UTF-16 -t UTF-8 "$options_file" 2>/dev/null | grep -q 'VirtualDeviceDx11'; then
              echo "DXVK"
              return
            fi
          fi
        done

        echo "unknown"
      }

      write_options_file() {
        target="$1"
        mkdir -p "$(dirname "$target")"
        tmp_utf8="$(mktemp)"
        tmp_file="$(mktemp)"
        case "$mode" in
          opengl|OpenGL)
            cat >"$tmp_utf8" <<'EOF'
<?xml version="1.0" encoding="UTF-16" standalone="no" ?>
<OptionGroups>
  <BootstrapOptionsGroup SchemaVersion="2" ToolTip="Special preferences that require the application to be restarted after a change." UserName="Bootstrap">
    <driverOptionId ToolTip="The driver used to display the graphics" UserName="Graphics driver" Value="VirtualDeviceGLCore"/>
    <WeaveTheme ToolTip="Changes the active theme used by Fusion UI." UserName="Theme" Value="weave-dark-blue"/>
  </BootstrapOptionsGroup>
  <spacemouseDriverOptionId ToolTip="Changes the version of the SpaceMouse SDK used by Fusion. For unsupported devices, use the Older setting." UserName="SpaceMouse-Driver" Value="0"/>
  <NetworkOptionGroup SchemaVersion="2" ToolTip="This is a set of options used for network access." UserName="Network">
    <WindowsProxyOptionId ToolTip="Windows Network Proxy - Setting" UserName="Windows-Network-Proxy - Setting" Value="No Proxy"/>
    <SSLVerifyPeerOptionId ToolTip="Ensure that the Autodesk Fusion 360 client can validate the server SSL certificate." UserName="Server-Verification" Value="TrustAllServers"/>
  </NetworkOptionGroup>
</OptionGroups>
EOF
            ;;
          dxvk|DXVK)
            cat >"$tmp_utf8" <<'EOF'
<?xml version="1.0" encoding="UTF-16" standalone="no" ?>
<OptionGroups>
  <BootstrapOptionsGroup SchemaVersion="2" ToolTip="Special preferences that require the application to be restarted after a change." UserName="Bootstrap">
    <driverOptionId ToolTip="The driver used to display the graphics" UserName="Graphics driver" Value="VirtualDeviceDx11"/>
    <WeaveTheme ToolTip="Changes the active theme used by Fusion UI." UserName="Theme" Value="weave-dark-blue"/>
  </BootstrapOptionsGroup>
  <spacemouseDriverOptionId ToolTip="Changes the version of the SpaceMouse SDK used by Fusion. For unsupported devices, use the Older setting." UserName="SpaceMouse-Driver" Value="0"/>
  <NetworkOptionGroup SchemaVersion="2" ToolTip="This is a set of options used for network access." UserName="Network">
    <WindowsProxyOptionId ToolTip="Windows Network Proxy - Setting" UserName="Windows-Network-Proxy - Setting" Value="No Proxy"/>
    <SSLVerifyPeerOptionId ToolTip="Ensure that the Autodesk Fusion 360 client can validate the server SSL certificate." UserName="Server-Verification" Value="TrustAllServers"/>
  </NetworkOptionGroup>
  <CompatibilityGroup SchemaVersion="2" ToolTip="Miscellaneous options which may enable Fusion to perform better on certain hardware or network configurations, and to help diagnose undesirable application behavior.">
    <graphicsApiOptionId ToolTip="Controls the graphics API used to render the User Interface. This has no effect on the 3D modeling canvas." UserName="Qt Rendering Hardware Interface API" Value="OpenGL"/>
  </CompatibilityGroup>
</OptionGroups>
EOF
            ;;
        esac

        printf '\xff\xfe' >"$tmp_file"
        iconv -f UTF-8 -t UTF-16LE "$tmp_utf8" >>"$tmp_file"
        if [ -f "$target" ]; then
          cp -f "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
        fi
        cp -f "$tmp_file" "$target"
        rm -f "$tmp_utf8" "$tmp_file"
      }

      disable_dxvk_dlls() {
        for dll_dir in "$prefix_dir/drive_c/windows/system32" "$prefix_dir/drive_c/windows/syswow64"; do
          [ -d "$dll_dir" ] || continue
          for dll in d3d10core d3d11 d3d9 dxgi; do
            if [ -f "$dll_dir/$dll.dll" ] && [ ! -f "$dll_dir/$dll.dll.j0nix-dxvk-disabled" ]; then
              mv -f "$dll_dir/$dll.dll" "$dll_dir/$dll.dll.j0nix-dxvk-disabled"
            fi
          done
        done
      }

      restore_dxvk_dlls() {
        for dll_dir in "$prefix_dir/drive_c/windows/system32" "$prefix_dir/drive_c/windows/syswow64"; do
          [ -d "$dll_dir" ] || continue
          for dll in d3d10core d3d11 d3d9 dxgi; do
            if [ -f "$dll_dir/$dll.dll.j0nix-dxvk-disabled" ]; then
              mv -f "$dll_dir/$dll.dll.j0nix-dxvk-disabled" "$dll_dir/$dll.dll"
            fi
          done
        done
      }

      set_wineprefix_log_renderer() {
        renderer="$1"
        mkdir -p "$(dirname "$wineprefix_log")"
        if [ -f "$wineprefix_log" ]; then
          tmp_log="$(mktemp)"
          {
            echo "$renderer"
            tail -n +2 "$wineprefix_log"
          } >"$tmp_log"
          cp -f "$wineprefix_log" "$wineprefix_log.bak.$(date +%Y%m%d%H%M%S)"
          mv -f "$tmp_log" "$wineprefix_log"
        else
          {
            echo "$renderer"
            echo "$install_dir"
            echo "$prefix_dir"
            echo "Wine"
          } >"$wineprefix_log"
        fi
      }

      case "$mode" in
        status)
          echo "Renderer: $(current_renderer)"
          for options_file in "''${options_paths[@]}"; do
            if [ -f "$options_file" ]; then
              if iconv -f UTF-16 -t UTF-8 "$options_file" 2>/dev/null | grep -q 'VirtualDeviceGLCore'; then
                echo "OpenGL options: $options_file"
              elif iconv -f UTF-16 -t UTF-8 "$options_file" 2>/dev/null | grep -q 'VirtualDeviceDx11'; then
                echo "DXVK options: $options_file"
              else
                echo "Unknown options: $options_file"
              fi
            else
              echo "Missing options: $options_file"
            fi
          done
          ;;
        opengl|OpenGL)
          wineserver -k >/dev/null 2>&1 || true
          for options_file in "''${options_paths[@]}"; do
            write_options_file "$options_file"
          done
          disable_dxvk_dlls
          set_wineprefix_log_renderer "OpenGL"
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d10core' /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d11' /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*dxgi' /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d11 /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v dxgi /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d10core /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d9 /t REG_SZ /d builtin /f >/dev/null
          echo "Autodesk Fusion renderer set to OpenGL. Restart Fusion now."
          ;;
        dxvk|DXVK)
          wineserver -k >/dev/null 2>&1 || true
          restore_dxvk_dlls
          if [ -f "$prefix_dir/drive_c/windows/system32/d3d11.dll" ] && [ -f "$prefix_dir/drive_c/windows/system32/dxgi.dll" ]; then
            echo "DXVK DLLs already exist in the prefix."
          else
            WINEPREFIX="$prefix_dir" winetricks -q dxvk
          fi
          for options_file in "''${options_paths[@]}"; do
            write_options_file "$options_file"
          done
          set_wineprefix_log_renderer "DXVK"
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d10core' /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d11' /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*dxgi' /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v '*d3d9' /t REG_SZ /d builtin /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d11 /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v dxgi /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d10core /t REG_SZ /d native /f >/dev/null
          WINEPREFIX="$prefix_dir" wine REG ADD 'HKCU\Software\Wine\DllOverrides' /v d3d9 /t REG_SZ /d builtin /f >/dev/null
          echo "Autodesk Fusion renderer set to DXVK. Restart Fusion now."
          ;;
        *)
          echo "usage: autodesk-fusion-renderer [status|opengl|dxvk]" >&2
          exit 2
          ;;
      esac
    '';
  };

  installCommand =
    if installerMode == "wine" then
      "--wine"
    else if installerMode == "proton" then
      "--proton=${protonVersion}"
    else
      "--fusion-wine";

  installerScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-install";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}
      ${protectedInstallerEnv}

      mkdir -p "$install_dir/bin" "$install_dir/logs"
      installer="$install_dir/bin/autodesk_fusion_installer_x86-64.sh"
      ${installerLock}
      extensions_enabled=${if extensions then "1" else "0"}
      viewport_refresh_forcer=${if viewportRefreshForcer then "1" else "0"}

      echo "Fetching Autodesk Fusion Linux installer..."
      curl -L --fail ${lib.escapeShellArg installerUrl} -o "$installer"
      chmod +x "$installer"
      ${protonInstallerRuntime}

      # Lolig4 detects the real GPU and configures its matching DXVK/VKD3D
      # stack. Its fusion-wine runner carries the canvas and owned-window fixes.
      args=( --install fusion ${lib.escapeShellArg installCommand} )
      if [ "$extensions_enabled" = "1" ]; then
        args+=(--full)
      fi
      if [ "$viewport_refresh_forcer" = "1" ]; then
        args+=(--refresh-forcer)
      fi

      echo "Starting Autodesk Fusion setup in: $install_dir"
      "$installer" "''${args[@]}"
      ${postInstallDesktopFix}
    '';
  };
  repairScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-repair";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}
      ${protectedInstallerEnv}

      mkdir -p "$install_dir/bin" "$install_dir/logs"
      installer="$install_dir/bin/autodesk_fusion_installer_x86-64.sh"
      ${installerLock}
      viewport_refresh_forcer=${if viewportRefreshForcer then "1" else "0"}

      echo "Fetching Autodesk Fusion Linux installer..."
      curl -L --fail ${lib.escapeShellArg installerUrl} -o "$installer"
      chmod +x "$installer"
      ${protonInstallerRuntime}

      echo "Deploying a fresh, parallel Fusion prefix in: $install_dir"
      args=( --install fusion ${lib.escapeShellArg installCommand} )
      if [ "$viewport_refresh_forcer" = "1" ]; then
        args+=(--refresh-forcer)
      fi
      "$installer" "''${args[@]}"
      ${postInstallDesktopFix}
    '';
  };
  launcherScript = pkgs.writeShellApplication {
    name = "autodesk-fusion";
    runtimeInputs = runtimePackages;
    text = ''
      saved_ld_library_path="''${LD_LIBRARY_PATH-}"
      saved_wayland_display="''${WAYLAND_DISPLAY-}"
      set -eu
      ${commonShell}
      ${cleanInheritedQtEnvironment}

      active_prefix_name="$(cat "$install_dir/logs/active_fusion.log" 2>/dev/null || true)"
      if [ -z "$active_prefix_name" ]; then
        echo "error: no active Fusion prefix is configured in $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      prefix_config="$install_dir/logs/$active_prefix_name/prefix.config"
      if [ ! -r "$prefix_config" ]; then
        echo "error: Fusion prefix configuration is missing: $prefix_config" >&2
        echo "Run: autodesk-fusion-repair" >&2
        exit 1
      fi

      wine_pfx="$(sed -n '2p' "$prefix_config")"
      runner_mode="$(sed -n '3p' "$prefix_config")"
      fusion_wine="$(sed -n '4p' "$prefix_config")"
      fusion_wineserver="$(sed -n '5p' "$prefix_config")"
      if [ ! -d "$wine_pfx" ]; then
        echo "error: Fusion's active prefix is incomplete." >&2
        echo "Run: autodesk-fusion-repair" >&2
        exit 1
      fi

      fusion_exe="$(find "$wine_pfx" -type f -name Fusion360.exe -printf '%T@ %p\n' | sort -rn | head -n 1 | cut -d' ' -f2-)"
      if [ -z "$fusion_exe" ]; then
        echo "error: Fusion360.exe was not found in the active prefix." >&2
        echo "Run: autodesk-fusion-repair" >&2
        exit 1
      fi
      if [ -x "$install_dir/bin/spconvd" ]; then
        "$install_dir/bin/spconvd"
      fi

      case "$runner_mode" in
        --fusion-wine|--wine)
          if [ ! -x "$fusion_wine" ] || [ ! -x "$fusion_wineserver" ]; then
            echo "error: Fusion's managed Wine runner is incomplete." >&2
            echo "Run: autodesk-fusion-repair" >&2
            exit 1
          fi

          # Lolig4 intentionally uses DXVK for the 3D canvas, but OpenGL for
          # the Qt/Chromium shell. Fusion can overwrite the latter with D3D11.
          options_file="$wine_pfx/drive_c/users/$(id -un)/AppData/Roaming/Autodesk/Neutron Platform/Options/NMachineSpecificOptions.xml"
          if [ -f "$options_file" ]; then
            options_utf8="$(mktemp)"
            options_normalized="$(mktemp)"
            options_utf16="$(mktemp)"
            iconv -f UTF-16 -t UTF-8 "$options_file" >"$options_utf8"
            if ! grep -q '<graphicsApiOptionId ' "$options_utf8"; then
              sed -i 's@</OptionGroups>@  <CompatibilityGroup SchemaVersion="2" ToolTip="User interface renderer" UserName="Compatibility"><graphicsApiOptionId ToolTip="Controls the graphics API used to render the User Interface." UserName="Qt Rendering Hardware Interface API" Value="OpenGL"/></CompatibilityGroup></OptionGroups>@' "$options_utf8"
            fi
            sed -E \
              -e 's/(<driverOptionId[^>]*Value=")[^"]*/\1VirtualDeviceDx11/' \
              -e 's/(<graphicsApiOptionId[^>]*Value=")[^"]*/\1OpenGL/' \
              "$options_utf8" >"$options_normalized"
            printf '\xff\xfe' >"$options_utf16"
            iconv -f UTF-8 -t UTF-16LE "$options_normalized" >>"$options_utf16"
            if ! cmp -s "$options_file" "$options_utf16"; then
              cp -f "$options_utf16" "$options_file"
              echo "Normalized Fusion UI renderer to OpenGL; 3D canvas remains DXVK."
            fi
            rm -f "$options_utf8" "$options_normalized" "$options_utf16"
          fi

          echo "Starting Fusion with managed $runner_mode runner..."
          QTWEBENGINE_DISABLE_SANDBOX=1 \
          DXVK_LOG_LEVEL=none \
          WINEPREFIX="$wine_pfx" \
          WINESERVER="$fusion_wineserver" \
          WINEDEBUG="''${WINEDEBUG:--all,+err}" \
          "$fusion_wine" "$fusion_exe" "$@" &
          runner_pid=$!
          if wait "$runner_pid"; then status=0; else status=$?; fi
          WINEPREFIX="$wine_pfx" "$fusion_wineserver" -k || true
          exit "$status"
          ;;
        *)
          # A Proton runner is launched through its proton script, not its
          # wine binary. Restore the Wayland socket cleared for legacy Wine.
          if [ -z "$saved_wayland_display" ]; then
            echo "error: CachyOS WineWayland Proton requires a Wayland session." >&2
            exit 1
          fi
          export WAYLAND_DISPLAY="$saved_wayland_display"
          unset GDK_BACKEND QT_QPA_PLATFORM SDL_VIDEODRIVER
          unset __EGL_VENDOR_LIBRARY_FILENAMES

          export LD_LIBRARY_PATH="${lib.makeLibraryPath [ pkgs.vulkan-loader ]}''${saved_ld_library_path:+:$saved_ld_library_path}"
          steam_dir=""
          for candidate in \
            "$HOME/.local/share/Steam" \
            "$HOME/.steam/steam" \
            "$HOME/.steam/root" \
            "$HOME/.steam/debian-installation"; do
            if [ -x "$candidate/compatibilitytools.d/$runner_mode/proton" ]; then
              steam_dir="$candidate"
              break
            fi
          done
          if [ -z "$steam_dir" ]; then
            echo "error: Proton runner '$runner_mode' is not installed in Steam compatibilitytools.d." >&2
            echo "Run: autodesk-fusion-repair" >&2
            exit 1
          fi
          proton_dir="$steam_dir/compatibilitytools.d/$runner_mode"

          if ! pgrep -x steam >/dev/null 2>&1 && command -v steam >/dev/null 2>&1; then
            setsid -f systemd-run --user --scope --quiet steam -silent </dev/null >/dev/null 2>&1 || true
            sleep 5
          fi

          echo "Starting Fusion with CachyOS WineWayland Proton runner $runner_mode..."
          PROTON_LOG=0 \
          PROTON_ENABLE_WAYLAND=1 \
          STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_dir" \
          STEAM_COMPAT_DATA_PATH="''${wine_pfx%/pfx}" \
          "$proton_dir/proton" run "$fusion_exe" "$@" &
          runner_pid=$!
          if wait "$runner_pid"; then status=0; else status=$?; fi
          WINEPREFIX="$wine_pfx" "$proton_dir/files/bin/wineserver" -k || true
          exit "$status"
          ;;
      esac
    '';
  };

  identityScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-adskidmgr";
    runtimeInputs = runtimePackages;
    text = ''
      saved_wayland_display="''${WAYLAND_DISPLAY-}"
      set -eu
      ${commonShell}
      ${cleanInheritedQtEnvironment}

      url="''${1:-}"
      if [ -z "$url" ]; then
        echo "usage: autodesk-fusion-adskidmgr <adskidmgr-url>" >&2
        exit 2
      fi

      active_prefix_name="$(cat "$install_dir/logs/active_adskidmgr-opener.log" 2>/dev/null || cat "$install_dir/logs/active_fusion.log" 2>/dev/null || true)"
      prefix_config="$install_dir/logs/$active_prefix_name/prefix.config"
      runner_mode="$(sed -n '3p' "$prefix_config" 2>/dev/null || true)"
      wine_pfx="$(sed -n '2p' "$prefix_config" 2>/dev/null || true)"

      if [ -n "$runner_mode" ] && [ "$runner_mode" != "--wine" ] && [ "$runner_mode" != "--fusion-wine" ]; then
        if [ -z "$saved_wayland_display" ] || [ ! -d "$wine_pfx" ]; then
          echo "error: Autodesk login requires the active Wayland Proton prefix." >&2
          exit 1
        fi
        identity_exe="$(find "$wine_pfx" -type f -name AdskIdentityManager.exe -printf '%T@ %p\n' | sort -rn | head -n 1 | cut -d' ' -f2-)"
        if [ -z "$identity_exe" ]; then
          echo "error: AdskIdentityManager.exe was not found in the active Fusion prefix." >&2
          exit 1
        fi
        steam_dir=""
        for candidate in \
          "$HOME/.local/share/Steam" \
          "$HOME/.steam/steam" \
          "$HOME/.steam/root" \
          "$HOME/.steam/debian-installation"; do
          if [ -x "$candidate/compatibilitytools.d/$runner_mode/proton" ]; then
            steam_dir="$candidate"
            break
          fi
        done
        if [ -z "$steam_dir" ]; then
          echo "error: Proton runner '$runner_mode' is unavailable for Autodesk login." >&2
          exit 1
        fi
        # Fusion stays WineWayland; browser callbacks use direct Wine in the
        # same prefix via XWayland, matching the earlier working flow.
        unset WAYLAND_DISPLAY GDK_BACKEND QT_QPA_PLATFORM SDL_VIDEODRIVER __EGL_VENDOR_LIBRARY_FILENAMES
        exec env \
          WINEDEBUG="''${WINEDEBUG:--all,+err}" \
          WINEPREFIX="$wine_pfx" \
          WINESERVER="$steam_dir/compatibilitytools.d/$runner_mode/files/bin/wineserver" \
          "$steam_dir/compatibilitytools.d/$runner_mode/files/bin/wine" "$identity_exe" "$url"
      fi

      opener="$install_dir/bin/adskidmgr-opener.sh"
      if [ ! -x "$opener" ]; then
        echo "error: the Lolig4 Fusion login handler is not installed at $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      exec "$opener" "$url"
    '';
  };

  doctorScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-doctor";
    runtimeInputs = runtimePackages ++ [ launcherScript identityScript installerScript repairScript ];
    text = ''
      set -u
      ${commonShell}

      status=0
      ok() { echo "OK: $*"; }
      warn() { echo "WARN: $*"; }
      fail() { echo "FAIL: $*"; status=1; }

      require_cmd() {
        if command -v "$1" >/dev/null 2>&1; then
          ok "$1 is available"
        else
          fail "$1 is missing"
        fi
      }

      for cmd in wine wineserver winetricks curl wget 7z cabextract wbinfo glxinfo xrandr xdg-open xdg-mime update-desktop-database bc mokutil lspci; do
        require_cmd "$cmd"
      done

      wine_version="$(wine --version 2>/dev/null | sed -E -e 's/^wine-//' -e 's/[^0-9.].*$//' || true)"
      if [ -n "$wine_version" ]; then
        major="''${wine_version%%.*}"
        rest="''${wine_version#*.}"
        minor="''${rest%%.*}"
        if [ "''${major:-0}" -gt 11 ] || { [ "''${major:-0}" -eq 11 ] && [ "''${minor:-0}" -ge 1 ]; }; then
          ok "Wine version $wine_version is new enough"
        else
          fail "Wine version $wine_version is older than 11.1"
        fi
      fi

      configured_gpu_backend=${lib.escapeShellArg gpuBackend}
      case "$configured_gpu_backend" in
        auto|DXVK)
          if vulkaninfo --summary >/dev/null 2>&1; then
            ok "Vulkan is available for DXVK"
          else
            warn "Vulkan check failed; Fusion may need OpenGL mode"
          fi
          ;;
        OpenGL)
          ok "OpenGL backend configured"
          ;;
      esac

      active_prefix_name="$(cat "$install_dir/logs/active_fusion.log" 2>/dev/null || true)"
      active_prefix="$install_dir/wineprefixes/$active_prefix_name"
      if [ -n "$active_prefix_name" ] && [ -d "$active_prefix" ]; then
        ok "Active Lolig4 Fusion prefix: $active_prefix"
      else
        warn "No active Lolig4 Fusion prefix exists under $install_dir; run autodesk-fusion-install"
      fi

      if [ -x "$install_dir/bin/autodesk_fusion_launcher.sh" ]; then
        ok "Lolig4 launcher exists"
      else
        warn "Lolig4 launcher missing; run autodesk-fusion-install"
      fi

      if [ -x "$install_dir/fusion-wine-build/bin/wine" ]; then
        ok "Patched fusion-wine runner exists"
      else
        warn "Patched fusion-wine runner is missing"
      fi

      search_roots=()
      [ -d "$active_prefix" ] && search_roots+=("$active_prefix")

      if [ "''${#search_roots[@]}" -gt 0 ] && find "''${search_roots[@]}" -name AdskIdentityManager.exe -print -quit 2>/dev/null | grep -q .; then
        ok "Autodesk Identity Manager exists"
      else
        warn "Autodesk Identity Manager not found in the active prefix"
      fi

      if [ "''${#search_roots[@]}" -gt 0 ] && find "''${search_roots[@]}" -iname '*WebView2*' -print -quit 2>/dev/null | grep -q .; then
        ok "WebView2 files exist"
      else
        warn "WebView2 files not found in the active prefix"
      fi
      mime_default="$(xdg-mime query default x-scheme-handler/adskidmgr 2>/dev/null || true)"
      if [ "$mime_default" = "autodesk-fusion-adskidmgr.desktop" ]; then
        ok "adskidmgr login handler is registered"
      else
        warn "adskidmgr login handler is '$mime_default'"
      fi

      if [ -d "$install_dir/logs" ]; then
        ok "Log directory exists: $install_dir/logs"
      else
        warn "Log directory missing: $install_dir/logs"
      fi

      exit "$status"
    '';
  };

  autoSetupScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-auto-setup";
    runtimeInputs = [ installerScript ];
    text = ''
      set -eu
      ${commonShell}
      if [ -x "$install_dir/bin/autodesk_fusion_launcher.sh" ]; then
        exit 0
      fi
      exec autodesk-fusion-install
    '';
  };
in
lib.mkIf enabled {
  home.activation.removeUpstreamFusionDesktopEntries = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${cleanupUpstreamDesktopEntries}
    ${pkgs.desktop-file-utils}/bin/update-desktop-database "$applications_dir" 2>/dev/null || true
  '';

  j0nix.user.software.packages = [
    launcherScript
    installerScript
    repairScript
    doctorScript
    identityScript
    rendererScript
  ];

  xdg.dataFile = {
    "icons/hicolor/512x512/apps/autodesk-fusion.png" = {
      force = true;
      source = ./assets/autodesk-fusion.png;
    };
    "applications/autodesk-fusion.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Autodesk Fusion
        GenericName=CAD/CAM/CAE
        Comment=Run Autodesk Fusion through the managed j0nix Wine setup
        Exec=${lib.getExe launcherScript} %U
        Icon=autodesk-fusion
        StartupWMClass=fusion360.exe
        Terminal=false
        StartupNotify=true
        Categories=Graphics;Engineering;
      '';
    };
    "applications/autodesk-fusion-adskidmgr.desktop" = {
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Autodesk Fusion Login Handler
        GenericName=Autodesk Identity Manager URL Handler
        Comment=Open Autodesk Fusion login callbacks
        Exec=${lib.getExe identityScript} %u
        Terminal=false
        NoDisplay=true
        MimeType=x-scheme-handler/adskidmgr;
      '';
    };
  };

  xdg.mimeApps.defaultApplications = lib.mkIf setAsDefaultLoginHandler {
    "x-scheme-handler/adskidmgr" = [ "autodesk-fusion-adskidmgr.desktop" ];
  };

  systemd.user.services.autodesk-fusion-setup = lib.mkIf autoSetupOnLogin {
    Unit = {
      Description = "Install Autodesk Fusion user prefix";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe autoSetupScript}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  assertions = [
    {
      assertion = builtins.isBool enabled;
      message = "settings.programs.autodeskFusion.enable must be a boolean";
    }
    {
      assertion = builtins.isString installDir && installDir != "";
      message = "settings.programs.autodeskFusion.installDir must be a non-empty string";
    }
    {
      assertion = builtins.elem installerMode [
        "fusion-wine"
        "wine"
        "proton"
      ];
      message = "settings.programs.autodeskFusion.installerMode must be one of: fusion-wine, wine, proton";
    }
    {
      assertion = builtins.isString protonVersion && protonVersion != "";
      message = "settings.programs.autodeskFusion.protonVersion must be a non-empty string";
    }
    {
      assertion = builtins.elem gpuBackend [
        "auto"
        "DXVK"
        "OpenGL"
      ];
      message = "settings.programs.autodeskFusion.gpuBackend must be one of: auto, DXVK, OpenGL";
    }
    {
      assertion = builtins.isBool extensions;
      message = "settings.programs.autodeskFusion.extensions must be a boolean";
    }
    {
      assertion = builtins.isBool viewportRefreshForcer;
      message = "settings.programs.autodeskFusion.viewportRefreshForcer must be a boolean";
    }
    {
      assertion = builtins.isBool autoSetupOnLogin;
      message = "settings.programs.autodeskFusion.autoSetupOnLogin must be a boolean";
    }
    {
      assertion = runnerName == "wineWow64Packages.stagingFull";
      message = "settings.programs.autodeskFusion.runner currently supports only wineWow64Packages.stagingFull";
    }
    {
      assertion = builtins.isBool setAsDefaultLoginHandler;
      message = "settings.programs.autodeskFusion.setAsDefaultLoginHandler must be a boolean";
    }
  ];
}
