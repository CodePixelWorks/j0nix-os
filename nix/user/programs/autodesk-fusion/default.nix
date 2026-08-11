{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).autodeskFusion or { };
  enabled = cfg.enable or false;
  nvidiaEnabled = (((settings.drivers or { }).nvidia or { }).enable or false);

  installDir = cfg.installDir or "$HOME/.autodesk_fusion";
  installerMode = cfg.installerMode or "install";
  protonVersion = cfg.protonVersion or "GE-Proton11-Fusion";
  gpuBackend = cfg.gpuBackend or "auto";
  extensions = cfg.extensions or false;
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
      "https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux/raw/branch/main/files/setup/autodesk_fusion_installer_x86-64.sh";

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
    gnutar
    glibc.bin
    mokutil
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
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver-32/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LIBGL_DRIVERS_PATH="/run/opengl-driver/lib/dri:/run/opengl-driver-32/lib/dri''${LIBGL_DRIVERS_PATH:+:$LIBGL_DRIVERS_PATH}"
    export __EGL_VENDOR_LIBRARY_DIRS="/run/opengl-driver/share/glvnd/egl_vendor.d''${__EGL_VENDOR_LIBRARY_DIRS:+:$__EGL_VENDOR_LIBRARY_DIRS}"
    ${lib.optionalString nvidiaEnabled ''
      export GBM_BACKEND=nvidia-drm
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export LIBVA_DRIVER_NAME=nvidia
    ''}
    unset WAYLAND_DISPLAY
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

  postInstallDesktopFix = ''
    applications_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    fusion_desktop_dir="$applications_dir/wine/Programs/Autodesk"
    fusion_launcher=${lib.escapeShellArg (lib.getExe launcherScript)}
    fusion_login_handler=${lib.escapeShellArg (lib.getExe identityScript)}

    if [ -d "$fusion_desktop_dir" ]; then
      find "$fusion_desktop_dir" -name 'Autodesk Fusion.desktop' -type f -print0 2>/dev/null \
        | while IFS= read -r -d "" desktop_file; do
          sed -i \
            -e 's#^Exec=.*#Exec='"$fusion_launcher"' %U#' \
            -e 's#^Path=.*#Path='"$install_dir"'#' \
            "$desktop_file"
        done

      find "$fusion_desktop_dir" -name 'adskidmgr-opener.desktop' -type f -print0 2>/dev/null \
        | while IFS= read -r -d "" desktop_file; do
          sed -i \
            -e 's#^Exec=.*#Exec='"$fusion_login_handler"' %u#' \
            "$desktop_file"
        done
    fi

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
    if installerMode == "install" then
      "--install"
    else if installerMode == "install-fix" then
      "--install-fix"
    else
      "--proton=${protonVersion}";

  installerScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-install";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}
      ${protectedInstallerEnv}

      mkdir -p "$install_dir/bin" "$install_dir/logs"
      installer="$install_dir/bin/cryinkfly-autodesk-fusion-installer.sh"
      extensions_enabled=${if extensions then "1" else "0"}

      echo "Fetching Autodesk Fusion Linux installer..."
      curl -L --fail ${lib.escapeShellArg installerUrl} -o "$installer"
      chmod +x "$installer"
      ${applyGpuBackendPolicy}

      args=( ${lib.escapeShellArg installCommand} "$install_dir" )
      if [ "$extensions_enabled" = "1" ]; then
        args+=(--full)
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
      installer="$install_dir/bin/cryinkfly-autodesk-fusion-installer.sh"

      echo "Fetching Autodesk Fusion Linux installer..."
      curl -L --fail ${lib.escapeShellArg installerUrl} -o "$installer"
      chmod +x "$installer"
      ${applyGpuBackendPolicy}

      echo "Starting Autodesk Fusion repair in: $install_dir"
      "$installer" --install-fix "$install_dir"
      ${postInstallDesktopFix}
    '';
  };

  launcherScript = pkgs.writeShellApplication {
    name = "autodesk-fusion";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}

      search_roots=()
      [ -d "$prefix_dir" ] && search_roots+=("$prefix_dir")
      [ -d "$proton_prefix_dir" ] && search_roots+=("$proton_prefix_dir")

      if [ "''${#search_roots[@]}" -eq 0 ]; then
        echo "error: Autodesk Fusion is not installed at $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      launcher="$(
        find "''${search_roots[@]}" -name Fusion360.exe -printf '%T+ %p\n' 2>/dev/null \
          | sort -r \
          | head -n 1 \
          | cut -d' ' -f2-
      )"

      if [ -z "$launcher" ]; then
        echo "error: Autodesk Fusion is not installed at $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      if [ -d "$prefix_dir" ]; then
        export WINEPREFIX="$prefix_dir"
      else
        export WINEPREFIX="$proton_prefix_dir"
      fi
      export DXVK_LOG_LEVEL=none
      export WINEDEBUG=-all,+err

      exec wine "$launcher" "$@"
    '';
  };

  identityScript = pkgs.writeShellApplication {
    name = "autodesk-fusion-adskidmgr";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}

      url="''${1:-}"
      if [ -z "$url" ]; then
        echo "usage: autodesk-fusion-adskidmgr <adskidmgr-url>" >&2
        exit 2
      fi

      search_roots=()
      [ -d "$prefix_dir" ] && search_roots+=("$prefix_dir")
      [ -d "$proton_prefix_dir" ] && search_roots+=("$proton_prefix_dir")

      if [ "''${#search_roots[@]}" -eq 0 ]; then
        echo "error: Autodesk Fusion is not installed at $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      identity_manager="$(
        find "''${search_roots[@]}" -name AdskIdentityManager.exe -print 2>/dev/null \
          | sort \
          | tail -n 1
      )"

      if [ -z "$identity_manager" ]; then
        echo "error: AdskIdentityManager.exe was not found under $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      if [ -d "$prefix_dir" ]; then
        export WINEPREFIX="$prefix_dir"
      elif [ -d "$proton_prefix_dir" ]; then
        export WINEPREFIX="$proton_prefix_dir"
      fi

      exec wine "$identity_manager" "$url"
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

      for cmd in wine wineserver winetricks curl wget 7z cabextract wbinfo glxinfo xrandr xdg-open xdg-mime update-desktop-database bc mokutil; do
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

      if [ -d "$prefix_dir" ]; then
        ok "Wine prefix exists: $prefix_dir"
      elif [ -d "$proton_prefix_dir" ]; then
        ok "Proton prefix exists: $proton_prefix_dir"
      else
        warn "Fusion prefix is not installed yet under $install_dir"
      fi

      if [ -x "$install_dir/bin/autodesk_fusion_launcher.sh" ]; then
        ok "cryinkfly launcher exists"
      else
        warn "cryinkfly launcher missing; run autodesk-fusion-install"
      fi

      search_roots=()
      [ -d "$prefix_dir" ] && search_roots+=("$prefix_dir")
      [ -d "$proton_prefix_dir" ] && search_roots+=("$proton_prefix_dir")

      if [ "''${#search_roots[@]}" -gt 0 ] && find "''${search_roots[@]}" -name AdskIdentityManager.exe -print -quit 2>/dev/null | grep -q .; then
        ok "Autodesk Identity Manager exists"
      else
        warn "Autodesk Identity Manager not found yet"
      fi

      if [ "''${#search_roots[@]}" -gt 0 ] && find "''${search_roots[@]}" -iname '*WebView2*' -print -quit 2>/dev/null | grep -q .; then
        ok "WebView2 files exist"
      else
        warn "WebView2 files not found yet"
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
  j0nix.user.software.packages = [
    launcherScript
    installerScript
    repairScript
    doctorScript
    identityScript
    rendererScript
  ];

  xdg.desktopEntries.autodesk-fusion = {
    name = "Autodesk Fusion";
    genericName = "CAD/CAM/CAE";
    comment = "Run Autodesk Fusion through the managed j0nix Wine setup";
    exec = "${lib.getExe launcherScript} %U";
    terminal = false;
    type = "Application";
    categories = [
      "Graphics"
      "Engineering"
    ];
    startupNotify = true;
  };

  xdg.desktopEntries.autodesk-fusion-adskidmgr = {
    name = "Autodesk Fusion Login Handler";
    genericName = "Autodesk Identity Manager URL Handler";
    comment = "Open Autodesk Fusion login callbacks";
    exec = "${lib.getExe identityScript} %u";
    terminal = false;
    type = "Application";
    mimeType = [ "x-scheme-handler/adskidmgr" ];
    noDisplay = true;
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
        "install"
        "install-fix"
        "proton"
      ];
      message = "settings.programs.autodeskFusion.installerMode must be one of: install, install-fix, proton";
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
