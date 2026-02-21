{ config, inputs, lib, pkgs, ... }@args:
let
  hasHomeModuleNew =
    (inputs.dank-material-shell ? homeModules)
    && (inputs.dank-material-shell.homeModules ? default);
  hasHomeModuleLegacy =
    (inputs.dank-material-shell ? homeManagerModules)
    && (inputs.dank-material-shell.homeManagerModules ? default);
  hasHomeModule = hasHomeModuleNew || hasHomeModuleLegacy;

  homeModule =
    if hasHomeModuleNew then
      inputs.dank-material-shell.homeModules.default
    else
      inputs.dank-material-shell.homeManagerModules.default;

  hasSystemPackages =
    (inputs.dank-material-shell ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.dank-material-shell.packages);
  hasPackage =
    hasSystemPackages
    && (inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system} ? default);

  dms = (args.settings or { }).dms or { };
  dmsMode = dms.mode or "integrated";
  dmsStartup = dms.startup or { };
  dmsStartupMode = dmsStartup.mode or "systemd";
  dmsUseSystemd = dmsStartupMode == "systemd";
  integratedMode = dmsMode == "integrated";
  separateMode = dmsMode == "separate";
  dmsInstall = dms.install or { };
  dmsFlakeRef = dmsInstall.flakeRef or "github:AvengeMedia/DankMaterialShell";
  dmsDgopRef = dmsInstall.dgopRef or "github:AvengeMedia/dgop";
  dmsCliVersion = dmsInstall.cliVersion or "0.2.3";
  dmsWallpaper = dms.wallpaper or { };
  wallpaperPath = dmsWallpaper.wallpaperPath or null;
  wallpaperFillMode = dmsWallpaper.wallpaperFillMode or "PreserveAspectCrop";
  monitorWallpapers = dmsWallpaper.monitorWallpapers or { };

  dmsConfigSource =
    if integratedMode && hasPackage then
      "${inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system}.default}/share/quickshell/dms"
    else
      "${config.home.homeDirectory}/.nix-profile/share/quickshell/dms";
  dmsBinaryFromPackage =
    if integratedMode && hasPackage then
      "${inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/dms"
    else
      "";
in {
  imports = lib.optional (integratedMode && hasHomeModule) homeModule;

  home.packages =
    lib.optional (integratedMode && hasPackage) inputs.dank-material-shell.packages.${pkgs.stdenv.hostPlatform.system}.default
    ++ (with pkgs; [
      (writeShellScriptBin "dms-start" ''
        state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/j0nix-os"
        startup_log="$state_dir/dms-start.log"
        dms_log="$state_dir/dms-runtime.log"
        dms_mode="${dmsMode}"

        rotate_log() {
          target="$1"
          keep=5

          [ -f "$target.$keep" ] && rm -f "$target.$keep"

          i=$((keep - 1))
          while [ "$i" -ge 1 ]; do
            if [ -f "$target.$i" ]; then
              mv "$target.$i" "$target.$((i + 1))"
            fi
            i=$((i - 1))
          done

          [ -f "$target" ] && mv "$target" "$target.1"
        }

        log() {
          msg="$1"
          printf '[%s] %s\n' "$(${coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')" "$msg" | ${coreutils}/bin/tee -a "$startup_log"
        }

        mkdir -p "$state_dir"
        rotate_log "$startup_log"
        rotate_log "$dms_log"

        touch "$startup_log" "$dms_log"
        log "Starting Dank Material Shell..."
        ${procps}/bin/pkill -x quickshell >/dev/null 2>&1 || true
        sleep 0.5

        notify_start_error() {
          msg="$1"
          full_msg="DMS start failed: $msg"

          if command -v hyprctl >/dev/null 2>&1; then
            hyprctl notify 3 12000 "rgb(ff5555)" "$full_msg" >/dev/null 2>&1 || true
          elif command -v notify-send >/dev/null 2>&1; then
            notify-send "DMS start failed" "$msg" >/dev/null 2>&1 || true
          fi

          log "$full_msg"
        }

        if [ "$dms_mode" = "integrated" ]; then
          if [ -x "${dmsBinaryFromPackage}" ]; then
            dms_cmd="${dmsBinaryFromPackage} run"
          elif command -v dms >/dev/null 2>&1; then
            dms_bin="$(command -v dms)"
            if [ "$dms_bin" = "$HOME/.local/bin/dms" ]; then
              notify_start_error "Legacy ~/.local/bin/dms detected. Remove it and rebuild to use the Nix-managed DMS binary."
              exit 1
            fi
            dms_cmd="$dms_bin run"
          else
            notify_start_error "dms binary not found in PATH. Rebuild and verify hyprlandShell=dank-material-shell."
            exit 1
          fi
        elif [ "$dms_mode" = "separate" ]; then
          if [ -x "$HOME/.local/bin/dms" ]; then
            dms_cmd="$HOME/.local/bin/dms run"
          elif command -v dms >/dev/null 2>&1; then
            dms_cmd="$(command -v dms) run"
          else
            notify_start_error "dms binary not found in PATH. Run dms-install (separate mode)."
            exit 1
          fi
        else
          notify_start_error "Invalid dms.mode '$dms_mode' (expected integrated or separate)."
          exit 1
        fi

        log "Using command: $dms_cmd"
        log "Runtime log file: $dms_log"

        export QT_QPA_PLATFORM="wayland;xcb"
        export XDG_SESSION_TYPE="wayland"

        sh -c "$dms_cmd" >>"$dms_log" 2>&1 &
        dms_pid=$!
        sleep 1

        if ! kill -0 "$dms_pid" 2>/dev/null; then
          if [ -s "$dms_log" ]; then
            last_line="$(${coreutils}/bin/tail -n 1 "$dms_log" | ${coreutils}/bin/tr -d '\r')"
            if echo "$last_line" | ${gnugrep}/bin/grep -qi "qt platform plugin"; then
              if [ "$dms_mode" = "integrated" ]; then
                notify_start_error "''${last_line:-see $dms_log} (check legacy ~/.local/bin/dms and prefer Nix-managed DMS)"
              else
                notify_start_error "''${last_line:-see $dms_log}"
              fi
            else
              notify_start_error "''${last_line:-see $dms_log}"
            fi
          else
            notify_start_error "process exited immediately (see $dms_log)"
          fi
          exit 1
        fi

        log "DMS started successfully (PID $dms_pid)."
      '')

      (writeShellScriptBin "dms-stop" ''
        echo "Stopping Dank Material Shell..."
        ${procps}/bin/pkill -x quickshell >/dev/null 2>&1 || true
        ${procps}/bin/pkill -x dms >/dev/null 2>&1 || true
      '')

      # Lock first, then suspend. Mirrors common DMS "lock before suspend" behavior.
      (writeShellScriptBin "dms-suspend" ''
        if command -v dms >/dev/null 2>&1; then
          dms ipc call lock lock >/dev/null 2>&1 || true
        fi
        sleep 0.5
        ${systemd}/bin/systemctl suspend
      '')

      (writeShellScriptBin "dms-lock" ''
        if command -v dms >/dev/null 2>&1; then
          dms ipc call lock lock
        else
          echo "dms binary not found in PATH"
          exit 1
        fi
      '')

      material-symbols
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono

      wl-clipboard
      wayland
      wayland-utils
      cliphist
      brightnessctl
      hyprpicker
      matugen
      lm_sensors
      pciutils
      glib
      networkmanager
      networkmanagerapplet
      cava
      libnotify
      libxcb
      libxkbcommon
      coreutils
      gnugrep
      procps
      qt6.qtwayland
      libsForQt5.qt5.qtwayland
      gammastep
    ])
    ++ (with pkgs; lib.optionals separateMode [
      (writeShellScriptBin "dms-install" ''
        echo "Installing Dank Material Shell (separate mode)..."

        nix profile install ${lib.escapeShellArg dmsFlakeRef}
        nix profile install ${lib.escapeShellArg dmsDgopRef}

        DMS_VERSION="${dmsCliVersion}"
        DMS_CLI_URL="https://github.com/AvengeMedia/DankMaterialShell/releases/download/v$DMS_VERSION/dms-cli-amd64.gz"
        INSTALL_DIR="$HOME/.local/bin"

        mkdir -p "$INSTALL_DIR"
        ${curl}/bin/curl -L "$DMS_CLI_URL" -o "/tmp/dms-cli-amd64.gz"
        ${gzip}/bin/gunzip -f "/tmp/dms-cli-amd64.gz"
        ${coreutils}/bin/chmod +x "/tmp/dms-cli-amd64"
        ${coreutils}/bin/mv "/tmp/dms-cli-amd64" "$INSTALL_DIR/dms"

        echo "Done. Use: dms-start"
      '')

      (writeShellScriptBin "dms-uninstall" ''
        echo "Removing Dank Material Shell (separate mode)..."
        nix profile remove ${lib.escapeShellArg dmsFlakeRef} 2>/dev/null || true
        nix profile remove ${lib.escapeShellArg dmsDgopRef} 2>/dev/null || true
        rm -f "$HOME/.local/bin/dms"
        echo "Done"
      '')
    ]);

  programs = {
    # Keep parity with black-don behavior and avoid parallel shell bars.
    waybar.enable = lib.mkForce false;
  } // lib.optionalAttrs (integratedMode && hasHomeModule) {
    dank-material-shell = {
      enable = lib.mkDefault true;
      systemd = {
        enable = lib.mkDefault dmsUseSystemd;
        restartIfChanged = lib.mkDefault true;
      };

      # Session config (wallpaper path/fill/per-monitor overrides).
      session = lib.mkIf (wallpaperPath != null) {
        inherit wallpaperPath wallpaperFillMode monitorWallpapers;
      };
    };
  };

  fonts.fontconfig.enable = true;

  xdg.configFile."dms/.keep".text = "";

  home.file.".config/quickshell/dms".source =
    config.lib.file.mkOutOfStoreSymlink dmsConfigSource;

  home.activation.dmsInfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD echo "${if integratedMode then "DMS integrated mode enabled. Use dms-start/dms-stop." else "DMS separate mode enabled. Use dms-install once, then dms-start/dms-stop/dms-uninstall."}"
  '';

  # Keep DMS alive across Home Manager reloads triggered by nixos-rebuild.
  home.activation.dmsSystemdReconcile = lib.hm.dag.entryAfter [ "reloadSystemd" "writeBoundary" ] (lib.optionalString (integratedMode && dmsUseSystemd) ''
    if command -v systemctl >/dev/null 2>&1; then
      resolved_unit=""
      for unit in dank-material-shell.service dank-material-shell dms.service; do
        if systemctl --user cat "$unit" >/dev/null 2>&1; then
          resolved_unit="$unit"
          break
        fi
      done

      if [ -n "$resolved_unit" ]; then
        $DRY_RUN_CMD systemctl --user daemon-reload || true
        $DRY_RUN_CMD systemctl --user restart "$resolved_unit" || $DRY_RUN_CMD systemctl --user start "$resolved_unit" || true
      fi
    fi
  '');

  assertions = [
    {
      assertion = builtins.elem dmsMode [ "integrated" "separate" ];
      message = "settings.dms.mode must be one of: integrated, separate";
    }
    {
      assertion = builtins.elem dmsStartupMode [ "systemd" "exec-once" ];
      message = "settings.dms.startup.mode must be one of: systemd, exec-once";
    }
    {
      assertion = builtins.elem wallpaperFillMode [ "PreserveAspectCrop" "PreserveAspectFit" "Stretch" ];
      message = "settings.dms.wallpaper.wallpaperFillMode must be one of: PreserveAspectCrop, PreserveAspectFit, Stretch";
    }
    {
      assertion = (!integratedMode) || hasHomeModule || hasPackage;
      message = ''
        Integrated DMS mode requires inputs.dank-material-shell to expose either:
        - homeModules.default (or legacy homeManagerModules.default)
        - packages.${pkgs.stdenv.hostPlatform.system}.default
      '';
    }
  ];
}
