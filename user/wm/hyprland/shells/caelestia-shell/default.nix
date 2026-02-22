{ inputs, lib, pkgs, settings, ... }:
let
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
    };
  } // lib.optionalAttrs (configuredWallpaperDir != null && configuredWallpaperDir != "") {
    paths = {
      wallpaperDir = configuredWallpaperDir;
    };
    services = {
      smartScheme = true;
    };
  };
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
    ]);

  home.activation.caelestiaConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cfg_dir="$HOME/.config/caelestia"
    cfg_file="$cfg_dir/shell.json"

    $DRY_RUN_CMD mkdir -p "$cfg_dir"
    if [ ! -e "$cfg_file" ] || [ -L "$cfg_file" ]; then
      $DRY_RUN_CMD rm -f "$cfg_file"
      $DRY_RUN_CMD cat >"$cfg_file" <<'EOF'
${builtins.toJSON seededCaelestiaConfig}
EOF
      $DRY_RUN_CMD chmod 644 "$cfg_file"
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
  ];
}
