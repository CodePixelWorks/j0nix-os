{ lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  fusionCfg = programsCfg.fusion360 or { };
  protonCfg = fusionCfg.protonInstaller or { };
  enabled = protonCfg.enable or true;
  protonVersion = protonCfg.protonVersion or "GE-Proton10-30";
  installRoot = protonCfg.installRoot or "$HOME/.autodesk_fusion";
  fusionInstallerUrl =
    protonCfg.fusionInstallerUrl
    or "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Admin%20Install.exe";
  webView2InstallerUrl =
    protonCfg.webview2InstallerUrl
    or "https://github.com/aedancullen/webview2-evergreen-standalone-installer-archive/releases/download/109.0.1518.78/MicrosoftEdgeWebView2RuntimeInstallerX64.exe";
  cleanupLegacyDesktop = protonCfg.cleanupLegacyDesktop or true;

  fusion360ProtonLib = pkgs.writeShellApplication {
    name = "fusion360-proton-lib";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gawk
      gnugrep
      gnused
      procps
      xdg-utils
      winetricks
      wineWow64Packages.staging
    ];
    text = ''
      set -euo pipefail

      export FUSION360_PROTON_VERSION="''${FUSION360_PROTON_VERSION:-${protonVersion}}"
      export FUSION360_INSTALL_ROOT="''${FUSION360_INSTALL_ROOT:-${installRoot}}"
      export FUSION360_INSTALLER_URL="''${FUSION360_INSTALLER_URL:-${fusionInstallerUrl}}"
      export FUSION360_WEBVIEW2_URL="''${FUSION360_WEBVIEW2_URL:-${webView2InstallerUrl}}"

      export FUSION360_STEAM_DIR="''${FUSION360_STEAM_DIR:-$HOME/.local/share/Steam}"
      export FUSION360_PROTON_DIR="$FUSION360_STEAM_DIR/compatibilitytools.d/$FUSION360_PROTON_VERSION"
      export FUSION360_COMPAT_DIR="$FUSION360_INSTALL_ROOT/protonprefix"
      export FUSION360_WINEPREFIX="$FUSION360_INSTALL_ROOT/wineprefixes/default"
      export FUSION360_DOWNLOADS="$FUSION360_INSTALL_ROOT/downloads"
      export FUSION360_LOGS="$FUSION360_INSTALL_ROOT/logs"
      export FUSION360_BIN_DIR="$FUSION360_INSTALL_ROOT/bin"
      export FUSION360_USER_IN_PREFIX="steamuser"

      fusion360::proton_env() {
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$FUSION360_STEAM_DIR"
        export STEAM_COMPAT_DATA_PATH="$FUSION360_COMPAT_DIR"
      }

      fusion360::proton_run() {
        fusion360::proton_env
        "$FUSION360_PROTON_DIR/proton" run "$@"
      }

      fusion360::ensure_proton() {
        if [ ! -d "$FUSION360_STEAM_DIR" ]; then
          echo "Steam nicht gefunden: $FUSION360_STEAM_DIR" >&2
          exit 1
        fi
        if [ ! -x "$FUSION360_PROTON_DIR/proton" ]; then
          echo "Proton nicht gefunden: $FUSION360_PROTON_DIR/proton" >&2
          echo "Installiere zuerst $FUSION360_PROTON_VERSION in Steam." >&2
          exit 1
        fi
      }

      fusion360::ensure_dirs() {
        mkdir -p \
          "$FUSION360_BIN_DIR" \
          "$FUSION360_DOWNLOADS" \
          "$FUSION360_LOGS" \
          "$FUSION360_INSTALL_ROOT/resources"
      }

      fusion360::download() {
        local url="$1"
        local out="$2"
        if [ -s "$out" ]; then
          return 0
        fi
        curl -L "$url" -o "$out"
      }

      fusion360::find_identity_manager() {
        find "$FUSION360_WINEPREFIX" -name AdskIdentityManager.exe 2>/dev/null | head -n 1
      }

      fusion360::find_fusion_exe() {
        find "$FUSION360_WINEPREFIX" \
          \( -iname Fusion360.exe -o -iname FusionLauncher.exe \) \
          2>/dev/null \
          | grep -E '/Autodesk/|/Fusion/' \
          | head -n 1
      }
    '';
  };

  fusion360ProtonSetup = pkgs.writeShellApplication {
    name = "fusion360-proton-setup";
    runtimeInputs = [ fusion360ProtonLib ];
    text = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      source "${fusion360ProtonLib}/bin/fusion360-proton-lib"

      fusion360::ensure_proton
      fusion360::ensure_dirs

      ${lib.optionalString cleanupLegacyDesktop ''
        rm -f "$HOME/.local/share/applications/adskidmgr-opener.desktop"
      ''}

      cd "$HOME"

      fusion360::download "$FUSION360_INSTALLER_URL" "$FUSION360_DOWNLOADS/FusionClientInstaller.exe"
      fusion360::download "$FUSION360_WEBVIEW2_URL" "$FUSION360_DOWNLOADS/WebView2installer.exe"

      echo "Initialisiere Proton-Prefix..."
      fusion360::proton_run wineboot -u >/dev/null 2>&1 || true

      echo "Initialisiere Wine-Prefix..."
      WINEPREFIX="$FUSION360_WINEPREFIX" wineboot -u >> "$FUSION360_LOGS/wineboot.log" 2>&1 || true

      mkdir -p "$FUSION360_WINEPREFIX/dosdevices"
      [ -L "$FUSION360_WINEPREFIX/dosdevices/g:" ] || ln -s / "$FUSION360_WINEPREFIX/dosdevices/g:"

      if [ -d "$FUSION360_WINEPREFIX/drive_c/users/$FUSION360_USER_IN_PREFIX" ]; then
        rm -rf "$FUSION360_WINEPREFIX/drive_c/users/$FUSION360_USER_IN_PREFIX/Downloads"
        ln -s "$FUSION360_DOWNLOADS" "$FUSION360_WINEPREFIX/drive_c/users/$FUSION360_USER_IN_PREFIX/Downloads"
      fi

      echo "Winetricks Basis-Setup (kann dauern)..."
      WINEPREFIX="$FUSION360_WINEPREFIX" winetricks -q sandbox >> "$FUSION360_LOGS/winetricks-sandbox.log" 2>&1 || true
      WINEPREFIX="$FUSION360_WINEPREFIX" winetricks -q atmlib gdiplus corefonts cjkfonts msxml4 msxml6 vcrun2022 fontsmooth=rgb winhttp win10 >> "$FUSION360_LOGS/winetricks-base.log" 2>&1 || true
      WINEPREFIX="$FUSION360_WINEPREFIX" winetricks -q cjkfonts >> "$FUSION360_LOGS/winetricks-cjkfonts.log" 2>&1 || true
      WINEPREFIX="$FUSION360_WINEPREFIX" winetricks -q win11 >> "$FUSION360_LOGS/winetricks-win11.log" 2>&1 || true

      echo "Registry-Overrides setzen..."
      WINEPREFIX="$FUSION360_WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "adpclientservice.exe" /t REG_SZ /d native /f >> "$FUSION360_LOGS/registry.log" 2>&1 || true
      WINEPREFIX="$FUSION360_WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "AdCefWebBrowser.exe" /t REG_SZ /d builtin /f >> "$FUSION360_LOGS/registry.log" 2>&1 || true
      WINEPREFIX="$FUSION360_WINEPREFIX" wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "bcp47langs" /t REG_SZ /d "" /f >> "$FUSION360_LOGS/registry.log" 2>&1 || true

      echo "Installiere WebView2..."
      WINEPREFIX="$FUSION360_WINEPREFIX" wine "$FUSION360_DOWNLOADS/WebView2installer.exe" /silent /install >> "$FUSION360_LOGS/webview2.log" 2>&1 || true

      echo "Starte Fusion-Installer (1/2)..."
      WINEPREFIX="$FUSION360_WINEPREFIX" timeout -k 10m 9m wine "$FUSION360_DOWNLOADS/FusionClientInstaller.exe" --quiet >> "$FUSION360_LOGS/fusion-installer-pass1.log" 2>&1 || true
      echo "Starte Fusion-Installer (2/2)..."
      WINEPREFIX="$FUSION360_WINEPREFIX" timeout -k 5m 2m wine "$FUSION360_DOWNLOADS/FusionClientInstaller.exe" --quiet >> "$FUSION360_LOGS/fusion-installer-pass2.log" 2>&1 || true

      echo
      echo "Fertig (best effort)."
      echo "Launcher: Autodesk Fusion 360 (Proton)"
      echo "Logs: $FUSION360_LOGS"
      echo "Starten mit: fusion360-proton-run"
    '';
  };

  fusion360ProtonRun = pkgs.writeShellApplication {
    name = "fusion360-proton-run";
    runtimeInputs = [ fusion360ProtonLib ];
    text = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      source "${fusion360ProtonLib}/bin/fusion360-proton-lib"
      fusion360::ensure_proton

      exe="$(fusion360::find_fusion_exe || true)"
      if [ -z "$exe" ]; then
        echo "Fusion 360 executable nicht gefunden im Prefix: $FUSION360_WINEPREFIX" >&2
        echo "Führe zuerst 'fusion360-proton-setup' aus." >&2
        exit 1
      fi

      fusion360::proton_run "$exe" "$@"
    '';
  };

  fusion360ProtonOpenIdMgr = pkgs.writeShellApplication {
    name = "fusion360-proton-open-idmgr";
    runtimeInputs = [ fusion360ProtonLib ];
    text = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      source "${fusion360ProtonLib}/bin/fusion360-proton-lib"
      fusion360::ensure_proton

      url="''${1:-}"
      exe="$(fusion360::find_identity_manager || true)"
      if [ -z "$exe" ]; then
        echo "AdskIdentityManager.exe nicht gefunden. Führe zuerst 'fusion360-proton-setup' aus." >&2
        exit 1
      fi

      if [ -n "$url" ]; then
        fusion360::proton_run "$exe" "$url"
      else
        fusion360::proton_run "$exe"
      fi
    '';
  };
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = protonVersion != "";
      message = "settings.programs.fusion360.protonInstaller.protonVersion must not be empty";
    }
  ];

  home.packages = [
    fusion360ProtonSetup
    fusion360ProtonRun
    fusion360ProtonOpenIdMgr
  ];

  xdg.desktopEntries."fusion360-proton-setup" = {
    name = "Fusion 360 Setup (Proton)";
    genericName = "Fusion 360 Installer";
    comment = "Prepare and install Autodesk Fusion 360 via Proton";
    exec = "fusion360-proton-setup";
    terminal = true;
    categories = [ "Graphics" "Engineering" ];
  };

  xdg.desktopEntries."fusion360-proton" = {
    name = "Autodesk Fusion 360 (Proton)";
    genericName = "CAD/CAM Software";
    comment = "Run Autodesk Fusion 360 via Proton on Linux";
    exec = "fusion360-proton-run";
    terminal = false;
    type = "Application";
    categories = [ "Graphics" "Engineering" ];
    startupNotify = true;
  };

  xdg.desktopEntries."adskidmgr-opener" = {
    name = "Autodesk Identity Manager URL Opener";
    exec = "fusion360-proton-open-idmgr %u";
    terminal = false;
    noDisplay = true;
    type = "Application";
    mimeType = [ "x-scheme-handler/adskidmgr" ];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/adskidmgr" = [ "adskidmgr-opener.desktop" ];
  };
}
