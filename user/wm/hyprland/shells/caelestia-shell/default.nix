{ inputs, lib, pkgs, settings, ... }:
let
  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemeName = iconThemeCfg.name or "Papirus-Dark";
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then pkgs."colloid-icon-theme" else null
    else if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "adwaita" then
      pkgs.adwaita-icon-theme
    else if iconThemePackageKey == "breeze" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? breeze-icons) then pkgs.kdePackages.breeze-icons
      else if pkgs ? breeze-icons then pkgs.breeze-icons
      else null
    else
      null;
  dmsSettings = settings.dms or { };
  dmsWallpaper = dmsSettings.wallpaper or { };
  configuredWallpaper = dmsWallpaper.wallpaperPath or null;
  configuredWallpaperDir =
    if configuredWallpaper != null && lib.hasInfix "/" configuredWallpaper then
      lib.removeSuffix "/${builtins.baseNameOf configuredWallpaper}" configuredWallpaper
    else
      null;
  hasInput = inputs ? caelestia-shell;
  hasHomeModule =
    hasInput
    && (inputs.caelestia-shell ? homeManagerModules)
    && (inputs.caelestia-shell.homeManagerModules ? default);
  hasSystemPackages =
    hasInput
    && (inputs.caelestia-shell ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.caelestia-shell.packages);
  packageSet =
    if hasSystemPackages then
      inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}
    else
      { };
  caelestiaPkg =
    if packageSet ? with-cli then
      packageSet.with-cli
    else if packageSet ? default then
      packageSet.default
    else
      null;
  preferredTerminal = settings.preferredTerminal or "kitty";
  seededCaelestiaConfig = {
    general = {
      apps = {
        terminal = [ preferredTerminal ];
      };
      idle = {
        lockBeforeSleep = true;
        timeouts = [
          {
            timeout = 600;
            idleAction = [ "system-suspend-then-hibernate-safe" ];
          }
        ];
      };
    };
    launcher = {
      actions = [
        {
          name = "Shutdown";
          command = [ "system-poweroff-safe" ];
        }
        {
          name = "Reboot";
          command = [ "system-reboot-safe" ];
        }
        {
          name = "Sleep";
          command = [ "system-suspend-then-hibernate-safe" ];
        }
      ];
    };
    session = {
      commands = {
        shutdown = [ "system-poweroff-safe" ];
        hibernate = [ "system-hibernate-safe" ];
        reboot = [ "system-reboot-safe" ];
      };
    };
    services = {
      smartScheme = true;
    };
  } // lib.optionalAttrs (configuredWallpaperDir != null && configuredWallpaperDir != "") {
    paths = {
      wallpaperDir = configuredWallpaperDir;
    };
  };
  seededWallpaperDirValue =
    if configuredWallpaperDir != null && configuredWallpaperDir != "" then configuredWallpaperDir else "";
in
{
  imports = lib.optional hasHomeModule inputs.caelestia-shell.homeManagerModules.default;

  programs.waybar.enable = lib.mkForce false;

  home.packages =
    lib.optionals (caelestiaPkg != null) [ caelestiaPkg ]
    ++ (with pkgs; [
      (writeShellScriptBin "caelestia-start" ''
        # Keep shell startup idempotent when wm-shell-start is triggered multiple times.
        if command -v qs >/dev/null 2>&1 && qs ipc -c caelestia call shell ping >/dev/null 2>&1; then
          exit 0
        fi

        if ${procps}/bin/pgrep -f "quickshell.*-c[[:space:]]*caelestia" >/dev/null 2>&1; then
          exit 0
        fi

        ${lib.optionalString iconThemeEnabled ''
        export XDG_ICON_THEME="${iconThemeName}"
        export GTK_ICON_THEME="${iconThemeName}"
        export QT_ICON_THEME_NAME="${iconThemeName}"
        ''}

        if command -v caelestia >/dev/null 2>&1; then
          caelestia shell -d &
          shell_pid=$!

          if [ -n "${if configuredWallpaper != null then configuredWallpaper else ""}" ] && [ -f "${if configuredWallpaper != null then configuredWallpaper else ""}" ]; then
            (
              i=0
              while [ "$i" -lt 20 ]; do
                sleep 0.5
                caelestia wallpaper -f "${if configuredWallpaper != null then configuredWallpaper else ""}" >/dev/null 2>&1 && exit 0
                i=$((i + 1))
              done
              exit 0
            ) &
          fi

          wait "$shell_pid"
          exit $?
        fi

        if command -v caelestia-shell >/dev/null 2>&1; then
          exec caelestia-shell
        fi

        echo "Neither 'caelestia' nor 'caelestia-shell' is in PATH."
        echo "Rebuild and verify wmShell=caelestia-shell."
        exit 1
      '')

      (writeShellScriptBin "caelestia-stop" ''
        if command -v caelestia >/dev/null 2>&1; then
          caelestia shell quit >/dev/null 2>&1 && exit 0 || true
        fi
        if command -v caelestia-shell >/dev/null 2>&1; then
          ${procps}/bin/pkill -x caelestia-shell >/dev/null 2>&1 && exit 0 || true
        fi
        if command -v qs >/dev/null 2>&1; then
          qs kill caelestia >/dev/null 2>&1 && exit 0 || true
        fi
        ${procps}/bin/pkill -f "quickshell.*-c[[:space:]]*caelestia" >/dev/null 2>&1 || true
      '')

      libnotify
      procps
      wl-clipboard
      cliphist
      matugen
      hicolor-icon-theme
      adwaita-icon-theme
      papirus-icon-theme
      material-symbols
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
    ])
    ++ lib.optionals (iconThemeEnabled && iconThemePackage != null) [ iconThemePackage ];

  home.activation.caelestiaConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg_dir="$HOME/.config/caelestia"
    cfg_file="$cfg_dir/shell.json"
    tmp_file="$cfg_file.codex-tmp"
    bad_file="$cfg_file.invalid"

    $DRY_RUN_CMD mkdir -p "$cfg_dir"
    if [ ! -e "$cfg_file" ] || [ -L "$cfg_file" ]; then
      $DRY_RUN_CMD rm -f "$cfg_file"
      $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
${builtins.toJSON seededCaelestiaConfig}
EOF
      $DRY_RUN_CMD chmod 644 "$cfg_file"
    elif [ -f "$cfg_file" ]; then
      # If the user file is broken JSON, keep a backup and recreate a valid minimal config.
      if ! ${pkgs.jq}/bin/jq -e . "$cfg_file" >/dev/null 2>&1; then
        $DRY_RUN_CMD mv -f "$cfg_file" "$bad_file" 2>/dev/null || true
        $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
${builtins.toJSON seededCaelestiaConfig}
EOF
        $DRY_RUN_CMD chmod 644 "$cfg_file"
      else
        # Merge required defaults into existing config without overwriting user choices.
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq \
          --arg term "${preferredTerminal}" \
          --arg wallpaperDir "${seededWallpaperDirValue}" \
          '
            .general = ((.general // {}) | .apps = ((.apps // {}) | .terminal = (.terminal // [$term])))
            | .general.idle = (.general.idle // {})
            | .general.idle.lockBeforeSleep = (.general.idle.lockBeforeSleep // true)
            | if ((.general.idle.timeouts? | type) == "array") then
                .general.idle.timeouts = (
                  .general.idle.timeouts
                  | map(
                      if (.timeout? == 600 and (.idleAction? == ["systemctl", "suspend-then-hibernate"])) then
                        .idleAction = ["system-suspend-then-hibernate-safe"]
                      else
                        .
                      end
                    )
                )
              else
                .
              end
            | .launcher = (.launcher // {})
            | if ((.launcher.actions? | type) == "array") then
                .launcher.actions = (
                  .launcher.actions
                  | map(
                      if (.name? == "Sleep") then
                        .command = ["system-suspend-then-hibernate-safe"]
                      elif (.name? == "Shutdown") then
                        .command = ["system-poweroff-safe"]
                      elif (.name? == "Reboot") then
                        .command = ["system-reboot-safe"]
                      else
                        .
                      end
                    )
                )
              else
                .
              end
            | .session = (.session // {})
            | .session.commands = (
                (.session.commands // {})
                | .hibernate = ["system-hibernate-safe"]
                | .shutdown = ["system-poweroff-safe"]
                | .reboot = ["system-reboot-safe"]
              )
            | .services = ((.services // {}) | .smartScheme = (.smartScheme // true))
            | if $wallpaperDir != "" then
                .paths = ((.paths // {}) | .wallpaperDir = (.wallpaperDir // $wallpaperDir))
              else
                .
              end
          ' "$cfg_file" >"$tmp_file"
        $DRY_RUN_CMD mv "$tmp_file" "$cfg_file"
        $DRY_RUN_CMD chmod 644 "$cfg_file"
      fi
    fi
  '';

  home.activation.caelestiaInfo = lib.hm.dag.entryAfter [ "caelestiaConfigInit" ] ''
    $DRY_RUN_CMD echo "Caelestia shell enabled. Use caelestia-start/caelestia-stop."
  '';

  assertions = [
    {
      assertion = hasInput;
      message = "wmShell=caelestia-shell requires flake input 'caelestia-shell' in flake.nix";
    }
    {
      assertion = hasHomeModule || (caelestiaPkg != null);
      message = ''
        inputs.caelestia-shell must expose either:
        - homeManagerModules.default
        - packages.${pkgs.stdenv.hostPlatform.system}.with-cli (or default)
      '';
    }
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must resolve to a package for Caelestia icon usage";
    }
  ];
}
