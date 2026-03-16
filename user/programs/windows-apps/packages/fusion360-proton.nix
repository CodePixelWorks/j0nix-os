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
    mode = "manual"; # "manual" | "runtime-download" | "fetchurl" | "requireFile"
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
        mode = fusionInstaller.mode;
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
        mode = webView2Installer.mode;
        path = "";
        url = webView2Installer.url;
        fileName = webView2Installer.fileName;
      };

  fusionInstallerRuntimeFile = pkgs.writeText "fusion360-installer-runtime.json" (builtins.toJSON fusionInstallerRuntimeSpec);
  webView2InstallerRuntimeFile = pkgs.writeText "fusion360-webview2-runtime.json" (builtins.toJSON webView2InstallerRuntimeSpec);
  upstreamInstallerRaw = pkgs.fetchurl {
    url = "https://codeberg.org/cryinkfly/Autodesk-Fusion-360-on-Linux/raw/branch/main/files/setup/autodesk_fusion_installer_x86-64.sh";
    hash = "sha256-7BMn2JREc/RURjA3iKR08gvMsHbJoTf3xJy/X3oAH/o=";
  };
  upstreamInstallerLibrary = pkgs.runCommandLocal "autodesk_fusion_installer_x86-64-lib.sh" { } ''
    sed '$d' ${upstreamInstallerRaw} | sed '$d' > "$out"
    chmod 0555 "$out"
  '';

  fusion360ProtonLib = pkgs.writeShellApplication {
    name = "fusion360-proton-lib";
    runtimeInputs = with pkgs; [
      bc
      cabextract
      coreutils
      curl
      file
      findutils
      gawk
      gettext
      glib
      gnugrep
      gnused
      jq
      lsb-release
      mesa-demos
      mokutil
      p7zip
      procps
      samba
      util-linux
      wget
      which
      winetricks
      xdg-utils
      xrandr
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
          "$FUSION360_COMPAT_DIR" \
          "$FUSION360_DOWNLOADS" \
          "$FUSION360_LOGS" \
          "$FUSION360_INSTALL_ROOT/resources" \
          "$(dirname "$FUSION360_WINEPREFIX")"
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
        local manual_source="''${3:-}"
        if [ -s "$out" ]; then
          return 0
        fi
        local mode url store_path
        mode="$(${pkgs.jq}/bin/jq -r '.mode' "$spec")"
        url="$(${pkgs.jq}/bin/jq -r '.url' "$spec")"
        store_path="$(${pkgs.jq}/bin/jq -r '.path' "$spec")"

        if [ "$mode" = "store" ]; then
          cp "$store_path" "$out"
        elif [ "$mode" = "manual" ]; then
          if [ -z "$manual_source" ]; then
            echo "Fusion installer erforderlich. Nutze: fusion360-setup /pfad/zum/Fusion\\ Admin\\ Install.exe" >&2
            return 1
          fi
          if [ ! -f "$manual_source" ]; then
            echo "Fusion installer nicht gefunden: $manual_source" >&2
            return 1
          fi
          cp "$manual_source" "$out"
        else
          curl -L "$url" -o "$out"
        fi
      }

      fusion360::resolve_manual_installer() {
        local candidate="$1"
        if [ -z "$candidate" ]; then
          echo "Fusion installer erforderlich." >&2
          echo "Nutze: fusion360-setup /pfad/zum/Fusion\\ Admin\\ Install.exe" >&2
          echo "Relative Pfade aus dem aktuellen Arbeitsverzeichnis werden unterstützt." >&2
          return 1
        fi

        if [ ! -f "$candidate" ]; then
          echo "Installer-Datei nicht gefunden: $candidate" >&2
          return 1
        fi

        local resolved
        resolved="$(realpath -e "$candidate")"

        case "''${resolved##*/}" in
          *.exe|*.EXE)
            ;;
          *)
            echo "Installer muss eine .exe-Datei sein: $resolved" >&2
            return 1
            ;;
        esac

        local file_info
        file_info="$(file -b "$resolved")"
        case "$file_info" in
          PE32*|MS-DOS*)
            ;;
          *)
            echo "Installer sieht nicht wie eine Windows-Executable aus: $resolved" >&2
            echo "file(1): $file_info" >&2
            return 1
            ;;
        esac

        case "''${resolved##*/}" in
          *Downloader*.exe|*Downloader*.EXE)
            echo "Der uebergebene Installer ist nur der Fusion-Downloader: $resolved" >&2
            echo "Nutze stattdessen die Autodesk Admin-Installer-EXE, z. B. 'Fusion Admin Install.exe'." >&2
            return 1
            ;;
        esac

        printf '%s\n' "$resolved"
      }

      fusion360::stage_manual_installer() {
        local source_path="$1"
        local destination_path="$2"
        local metadata_path="$FUSION360_INSTALL_ROOT/resources/fusion-installer.json"
        local sha256

        sha256="$(sha256sum "$source_path" | awk '{print $1}')"
        mkdir -p "$(dirname "$destination_path")"
        cp "$source_path" "$destination_path"
        chmod 0644 "$destination_path"

        cat > "$metadata_path" <<EOF
{
  "sourcePath": $(printf '%s' "$source_path" | jq -Rs .),
  "stagedPath": $(printf '%s' "$destination_path" | jq -Rs .),
  "sha256": $(printf '%s' "$sha256" | jq -Rs .),
  "stagedAt": $(date -Iseconds | jq -Rs .)
}
EOF

        echo "Fusion-Installer übernommen:"
        echo "  Quelle: $source_path"
        echo "  Ziel:   $destination_path"
        echo "  SHA256: $sha256"
      }

      fusion360::find_identity_manager() {
        find "$FUSION360_WINEPREFIX" -name AdskIdentityManager.exe 2>/dev/null | head -n 1
      }

      fusion360::find_fusion_exe() {
        find "$FUSION360_WINEPREFIX" -iname Fusion360.exe 2>/dev/null | grep -E '/Autodesk/|/Fusion/' | head -n 1
      }

      fusion360::find_fusion_launcher() {
        find "$FUSION360_WINEPREFIX" -iname FusionLauncher.exe 2>/dev/null | grep -E '/Autodesk/|/Fusion/' | head -n 1
      }

      fusion360::find_fusion_entrypoint() {
        local exe
        exe="$(fusion360::find_fusion_exe || true)"
        if [ -n "$exe" ]; then
          printf '%s\n' "$exe"
          return 0
        fi

        fusion360::find_fusion_launcher
      }

      fusion360::run_installer_until_fusion_present() {
        local log_file="$1"
        local timeout_seconds="$2"

        WINEPREFIX="$FUSION360_WINEPREFIX" wine "$FUSION360_DOWNLOADS/FusionClientInstaller.exe" --quiet >> "$log_file" 2>&1 &
        local installer_pid=$!

        for _ in $(seq 1 "$timeout_seconds"); do
          if [ -n "$(fusion360::find_fusion_entrypoint || true)" ]; then
            WINEPREFIX="$FUSION360_WINEPREFIX" wineserver -k >/dev/null 2>&1 || true
            wait "$installer_pid" >/dev/null 2>&1 || true
            return 0
          fi
          if ! kill -0 "$installer_pid" >/dev/null 2>&1; then
            wait "$installer_pid" >/dev/null 2>&1 || true
            break
          fi
          sleep 1
        done

        WINEPREFIX="$FUSION360_WINEPREFIX" wineserver -k >/dev/null 2>&1 || true
        wait "$installer_pid" >/dev/null 2>&1 || true
        [ -n "$(fusion360::find_fusion_entrypoint || true)" ]
      }
    '';
  };

  fusion360ProtonSetup = pkgs.writeShellApplication {
    name = "fusion360-setup";
    runtimeInputs = [ fusion360ProtonLib ];
    text = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      source "${fusion360ProtonLib}/bin/fusion360-proton-lib"
      installer_path="''${1:-}"
      manual_installer_path=""
      selected_option="--install"
      selected_directory_arg="$FUSION360_INSTALL_ROOT"

      if [ -n "$FUSION360_PROTON_VERSION" ]; then
        selected_option="--proton=$FUSION360_PROTON_VERSION"
        fusion360::ensure_proton
      fi
      fusion360::ensure_dirs

      existing_fusion_exe="$(fusion360::find_fusion_entrypoint || true)"
      if [ -n "$existing_fusion_exe" ]; then
        echo "Fusion 360 ist bereits installiert:"
        echo "  $existing_fusion_exe"
        echo "Wenn du neu installieren willst, lösche zuerst den bestehenden Prefix unter:"
        echo "  $FUSION360_INSTALL_ROOT"
        exit 0
      fi

      ${lib.optionalString cleanupLegacyDesktop ''
        rm -f "$HOME/.local/share/applications/adskidmgr-opener.desktop"
      ''}

      cd "$HOME"

      if [ "$(${pkgs.jq}/bin/jq -r '.mode' "$FUSION360_INSTALLER_SPEC")" = "manual" ]; then
        manual_installer_path="$(fusion360::resolve_manual_installer "$installer_path")"
        fusion360::stage_manual_installer "$manual_installer_path" "$FUSION360_DOWNLOADS/FusionClientInstaller.exe"
      fi

      set -- "$selected_option" "$selected_directory_arg" "--full"
      # shellcheck disable=SC1090
      source "${upstreamInstallerLibrary}"

      if [ -n "$FUSION360_PROTON_VERSION" ]; then
        PROTON_VERSION="$FUSION360_PROTON_VERSION"
        PROTONPREFIX_DIRECTORY="$SELECTED_DIRECTORY/protonprefix"
        WINE_PFX="$PROTONPREFIX_DIRECTORY/pfx"
      else
        PROTON_VERSION=""
        WINE_PFX="$SELECTED_DIRECTORY/wineprefixes/default"
      fi

      check_required_packages() {
        echo "Überspringe Paketprüfung: j0nix stellt die benötigten Runtime-Tools bereit."
      }

      install_required_packages() {
        echo "Automatische Paketinstallation ist in j0nix deaktiviert." >&2
        echo "Fehlende Tools müssen deklarativ über Nix bereitgestellt werden." >&2
        return 1
      }

      check_and_install_wine() {
        if ! command -v wine >/dev/null 2>&1; then
          echo "Wine fehlt in PATH." >&2
          exit 1
        fi
        if ! command -v winetricks >/dev/null 2>&1; then
          echo "winetricks fehlt in PATH." >&2
          exit 1
        fi
        echo "Überspringe Wine-Installation: j0nix stellt Wine/winetricks bereit."
      }

      check_required_packages
      deactivate_window_not_responding_dialog
      create_data_structure
      check_secure_boot
      check_ram
      check_gpu_driver
      check_gpu_vram
      check_disk_space
      if [ -n "$PROTON_VERSION" ]; then
        check_steam_proton
      fi
      download_files
      check_and_install_wine
      wine_autodesk_fusion_install
      autodesk_fusion_patch_qt6webenginecore
      autodesk_fusion_patch_siappdll
      wine_autodesk_fusion_install_extensions
      autodesk_fusion_shortcuts_load
      autodesk_fusion_safe_logfile
      reset_window_not_responding_dialog

      installed_fusion_exe="$(fusion360::find_fusion_exe || true)"
      installed_fusion_launcher="$(fusion360::find_fusion_launcher || true)"
      if [ -z "$installed_fusion_exe" ] && [ -n "$installed_fusion_launcher" ]; then
        echo "Nur FusionLauncher.exe wurde installiert:" >&2
        echo "  $installed_fusion_launcher" >&2
        echo "Das ist ein unvollstaendiger Bootstrap und deutet meist auf den falschen Autodesk-Installer hin." >&2
        echo "Nutze die Admin-Installer-EXE und fuehre fusion360-setup erneut aus." >&2
        exit 1
      fi

      if [ -z "$installed_fusion_exe" ]; then
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

  fusion360ProtonSetupHelp = pkgs.writeShellApplication {
    name = "fusion360-setup-help";
    text = ''
      set -euo pipefail

      cat <<'EOF'
Usage:
  fusion360-setup /path/to/Fusion\ Admin\ Install.exe

The Autodesk installer EXE must be supplied explicitly.
Relative paths from the current working directory are supported.
The setup wrapper validates the file, stages it into the managed Fusion install
root, records a SHA256 manifest, and then runs the Proton-based installation.
EOF

      printf '\nPress Enter to close...\n'
      read -r _ || true
    '';
  };

  fusion360ProtonRun = pkgs.writeShellApplication {
    name = "fusion360-proton-run";
    runtimeInputs = [ fusion360ProtonLib ];
    text = ''
      set -euo pipefail
      # shellcheck disable=SC1091
      source "${fusion360ProtonLib}/bin/fusion360-proton-lib"
      launcher="$FUSION360_BIN_DIR/autodesk_fusion_launcher.sh"
      if [ ! -x "$launcher" ]; then
        echo "Fusion 360 Launcher nicht gefunden: $launcher" >&2
        echo "Führe zuerst 'fusion360-setup /pfad/zum/Fusion Admin Install.exe' aus." >&2
        exit 1
      fi

      exec "$launcher" "$@"
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
        echo "Führe zuerst 'fusion360-setup /pfad/zum/Fusion\\ Admin\\ Install.exe' aus." >&2
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
    fusion360ProtonSetupHelp
    fusion360ProtonRun
    fusion360ProtonOpenIdMgr
  ];

  autoSetup = {
    enable = fusionInstaller.mode != "manual";
    description = "Setup Autodesk Fusion 360 via Proton";
    command = "${config.home.profileDirectory}/bin/fusion360-setup";
  };

  desktopEntries = {
    "fusion360-setup" = {
      name = "Fusion 360 Setup (Proton)";
      genericName = "Fusion 360 Installer";
      comment = "Show the manual Fusion 360 installer workflow";
      exec = "fusion360-setup-help";
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
      assertion = builtins.elem fusionInstaller.mode [ "manual" "runtime-download" "fetchurl" "requireFile" ];
      message = "settings.programs.fusion360.protonInstaller.payloads.fusionInstaller.mode must be one of: manual, runtime-download, fetchurl, requireFile";
    }
    {
      assertion = builtins.elem webView2Installer.mode [ "runtime-download" "fetchurl" "requireFile" ];
      message = "settings.programs.fusion360.protonInstaller.payloads.webView2Installer.mode must be one of: runtime-download, fetchurl, requireFile";
    }
    {
      assertion =
        builtins.elem fusionInstaller.mode [ "manual" "runtime-download" ]
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
