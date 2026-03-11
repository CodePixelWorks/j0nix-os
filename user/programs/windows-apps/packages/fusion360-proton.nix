{ config, lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  fusionCfg = programsCfg.fusion360 or { };
  protonCfg = fusionCfg.protonInstaller or { };
  protonVersion = protonCfg.protonVersion or "GE-Proton10-32";
  installRoot = protonCfg.installRoot or "$HOME/.autodesk_fusion";
  cleanupLegacyDesktop = protonCfg.cleanupLegacyDesktop or true;
  payloadsCfg = protonCfg.payloads or { };
  defaultFusionInstaller = {
    mode = "runtime-download"; # "runtime-download" | "fetchurl" | "requireFile"
    fileName = "FusionClientInstaller.exe";
    url = "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Admin%20Install.exe";
    hash = null;
  };
  defaultWebView2Installer = {
    mode = "runtime-download";
    fileName = "WebView2installer.exe";
    url = "https://github.com/aedancullen/webview2-evergreen-standalone-installer-archive/releases/download/109.0.1518.78/MicrosoftEdgeWebView2RuntimeInstallerX64.exe";
    hash = null;
  };
  fusionInstaller = defaultFusionInstaller // (payloadsCfg.fusionInstaller or { });
  webView2Installer = defaultWebView2Installer // (payloadsCfg.webview2Installer or { });

  mkStoreName = payload: lib.strings.sanitizeDerivationName (payload.fileName or "payload.exe");

  mkPayloadPackage = payload:
    if payload.mode == "fetchurl" then
      pkgs.fetchurl {
        inherit (payload) url hash;
        name = mkStoreName payload;
      }
    else if payload.mode == "requireFile" then
      pkgs.requireFile {
        name = mkStoreName payload;
        inherit (payload) url hash;
      }
    else
      null;

  fusionInstallerPackage = mkPayloadPackage fusionInstaller;
  webView2InstallerPackage = mkPayloadPackage webView2Installer;
  payloadPackages = lib.filter (pkg: pkg != null) [
    fusionInstallerPackage
    webView2InstallerPackage
  ];

  fusionInstallerRuntimeSpec =
    if fusionInstallerPackage != null then
      {
        mode = "store";
        path = fusionInstallerPackage;
        url = fusionInstaller.url;
        fileName = fusionInstaller.fileName;
      }
    else
      {
        mode = "runtime-download";
        path = "";
        url = fusionInstaller.url;
        fileName = fusionInstaller.fileName;
      };

  webView2InstallerRuntimeSpec =
    if webView2InstallerPackage != null then
      {
        mode = "store";
        path = webView2InstallerPackage;
        url = webView2Installer.url;
        fileName = webView2Installer.fileName;
      }
    else
      {
        mode = "runtime-download";
        path = "";
        url = webView2Installer.url;
        fileName = webView2Installer.fileName;
      };

  fusionInstallerRuntimeFile = pkgs.writeText "fusion360-installer-runtime.json" (builtins.toJSON fusionInstallerRuntimeSpec);
  webView2InstallerRuntimeFile = pkgs.writeText "fusion360-webview2-runtime.json" (builtins.toJSON webView2InstallerRuntimeSpec);

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
      jq
      winetricks
      wineWow64Packages.waylandFull
    ];
    text = ''
      set -euo pipefail

      export FUSION360_PROTON_VERSION="''${FUSION360_PROTON_VERSION:-${protonVersion}}"
      export FUSION360_INSTALL_ROOT="''${FUSION360_INSTALL_ROOT:-${installRoot}}"
      export FUSION360_INSTALLER_SPEC=${lib.escapeShellArg (toString fusionInstallerRuntimeFile)}
      export FUSION360_WEBVIEW2_SPEC=${lib.escapeShellArg (toString webView2InstallerRuntimeFile)}

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

      fusion360::require_prefix_layout() {
        if [ ! -d "$FUSION360_WINEPREFIX/drive_c/windows/system32" ]; then
          echo "Wine-Prefix wurde nicht korrekt initialisiert: $FUSION360_WINEPREFIX" >&2
          echo "Prüfe $FUSION360_LOGS/wineboot.log" >&2
          exit 1
        fi
      }

      fusion360::ensure_payload() {
        local spec="$1"
        local out="$2"
        if [ -s "$out" ]; then
          return 0
        fi
        local mode url store_path
        mode="$(${pkgs.jq}/bin/jq -r '.mode' "$spec")"
        url="$(${pkgs.jq}/bin/jq -r '.url' "$spec")"
        store_path="$(${pkgs.jq}/bin/jq -r '.path' "$spec")"

        if [ "$mode" = "store" ]; then
          cp "$store_path" "$out"
        else
          curl -L "$url" -o "$out"
        fi
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

      if [ -n "$(fusion360::find_fusion_exe || true)" ]; then
        exit 0
      fi

      ${lib.optionalString cleanupLegacyDesktop ''
        rm -f "$HOME/.local/share/applications/adskidmgr-opener.desktop"
      ''}

      cd "$HOME"

      fusion360::ensure_payload "$FUSION360_INSTALLER_SPEC" "$FUSION360_DOWNLOADS/FusionClientInstaller.exe"
      fusion360::ensure_payload "$FUSION360_WEBVIEW2_SPEC" "$FUSION360_DOWNLOADS/WebView2installer.exe"

      echo "Initialisiere Proton-Prefix..."
      fusion360::proton_run wineboot -u >/dev/null 2>&1 || true

      echo "Initialisiere Wine-Prefix..."
      if ! WINEPREFIX="$FUSION360_WINEPREFIX" wineboot -u >> "$FUSION360_LOGS/wineboot.log" 2>&1; then
        echo "wineboot ist fehlgeschlagen. Prüfe $FUSION360_LOGS/wineboot.log" >&2
        exit 1
      fi
      fusion360::require_prefix_layout

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

      if [ -z "$(fusion360::find_fusion_exe || true)" ]; then
        echo "Fusion 360 wurde nicht installiert. Prüfe $FUSION360_LOGS/fusion-installer-pass1.log und $FUSION360_LOGS/fusion-installer-pass2.log" >&2
        exit 1
      fi

      echo
      echo "Fertig."
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
{
  id = "fusion360-proton";
  kind = "stateful-online";

  payloadPackages = payloadPackages;
  runtimePackages = [
    fusion360ProtonSetup
    fusion360ProtonRun
    fusion360ProtonOpenIdMgr
  ];

  autoSetup = {
    enable = true;
    description = "Setup Autodesk Fusion 360 via Proton";
    command = "${config.home.profileDirectory}/bin/fusion360-proton-setup";
  };

  desktopEntries = {
    "fusion360-proton-setup" = {
      name = "Fusion 360 Setup (Proton)";
      genericName = "Fusion 360 Installer";
      comment = "Prepare and install Autodesk Fusion 360 via Proton";
      exec = "fusion360-proton-setup";
      terminal = true;
      categories = [ "Graphics" "Engineering" ];
    };

    "fusion360-proton" = {
      name = "Autodesk Fusion 360 (Proton)";
      genericName = "CAD/CAM Software";
      comment = "Run Autodesk Fusion 360 via Proton on Linux";
      exec = "fusion360-proton-run";
      terminal = false;
      type = "Application";
      categories = [ "Graphics" "Engineering" ];
      startupNotify = true;
    };

    "adskidmgr-opener" = {
      name = "Autodesk Identity Manager URL Opener";
      exec = "fusion360-proton-open-idmgr %u";
      terminal = false;
      noDisplay = true;
      type = "Application";
      mimeType = [ "x-scheme-handler/adskidmgr" ];
    };
  };

  mimeDefaults = {
    "x-scheme-handler/adskidmgr" = [ "adskidmgr-opener.desktop" ];
  };

  assertions = [
    {
      assertion = builtins.elem fusionInstaller.mode [ "runtime-download" "fetchurl" "requireFile" ];
      message = "settings.programs.fusion360.protonInstaller.payloads.fusionInstaller.mode must be one of: runtime-download, fetchurl, requireFile";
    }
    {
      assertion = builtins.elem webView2Installer.mode [ "runtime-download" "fetchurl" "requireFile" ];
      message = "settings.programs.fusion360.protonInstaller.payloads.webView2Installer.mode must be one of: runtime-download, fetchurl, requireFile";
    }
    {
      assertion =
        fusionInstaller.mode == "runtime-download"
        || (fusionInstaller.hash != null && fusionInstaller.hash != "");
      message = "Fusion 360 installer payloads using fetchurl/requireFile must define hash.";
    }
    {
      assertion =
        webView2Installer.mode == "runtime-download"
        || (webView2Installer.hash != null && webView2Installer.hash != "");
      message = "WebView2 payloads using fetchurl/requireFile must define hash.";
    }
  ];
}
