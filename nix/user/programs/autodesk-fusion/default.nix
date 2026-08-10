{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).autodeskFusion or { };
  enabled = cfg.enable or false;

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
      exec "$installer" "''${args[@]}"
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
      exec "$installer" --install-fix "$install_dir"
    '';
  };

  launcherScript = pkgs.writeShellApplication {
    name = "autodesk-fusion";
    runtimeInputs = runtimePackages;
    text = ''
      set -eu
      ${commonShell}

      launcher="$install_dir/bin/autodesk_fusion_launcher.sh"
      if [ ! -x "$launcher" ]; then
        echo "error: Autodesk Fusion is not installed at $install_dir." >&2
        echo "Run: autodesk-fusion-install" >&2
        exit 1
      fi

      cd "$install_dir/bin"
      exec bash "$launcher" "$@"
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

      identity_manager="$(
        find "$prefix_dir" "$proton_prefix_dir" -name AdskIdentityManager.exe -print 2>/dev/null \
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

      wine_version="$(wine --version 2>/dev/null | sed -e 's/^wine-//' -e 's/-.*//' || true)"
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

      if find "$prefix_dir" "$proton_prefix_dir" -name AdskIdentityManager.exe -print -quit 2>/dev/null | grep -q .; then
        ok "Autodesk Identity Manager exists"
      else
        warn "Autodesk Identity Manager not found yet"
      fi

      if find "$prefix_dir" "$proton_prefix_dir" -iname '*WebView2*' -print -quit 2>/dev/null | grep -q .; then
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
  ];

  xdg.desktopEntries.autodesk-fusion = {
    name = "Autodesk Fusion";
    genericName = "CAD/CAM/CAE";
    comment = "Run Autodesk Fusion through the managed j0nix Wine setup";
    exec = "autodesk-fusion %U";
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
    exec = "autodesk-fusion-adskidmgr %u";
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
