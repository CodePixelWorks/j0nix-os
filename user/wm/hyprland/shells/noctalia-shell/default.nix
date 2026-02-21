{ inputs, lib, pkgs, settings, ... }:
let
  hasNoctaliaInput = inputs ? noctalia;
  noctaliaCfg = ((settings.programs or { }).noctalia or { });
  initializeConfig = noctaliaCfg.initializeConfig or true;
  preferredTerminal = settings.preferredTerminal or "kitty";

  hasHomeModule =
    hasNoctaliaInput
    && (inputs.noctalia ? homeModules)
    && (inputs.noctalia.homeModules ? default);

  hasPackage =
    hasNoctaliaInput
    && (inputs.noctalia ? packages)
    && (builtins.hasAttr pkgs.stdenv.hostPlatform.system inputs.noctalia.packages)
    && (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system} ? default);
in {
  imports = lib.optional hasHomeModule inputs.noctalia.homeModules.default;

  programs.waybar.enable = lib.mkForce false;

  home.file.".config/noctalia/settings.json.template".text = builtins.toJSON {
    appLauncher = {
      position = "center";
      sortByMostUsed = true;
      enableClipboardHistory = true;
      terminalCommand = preferredTerminal;
    };
    bar = {
      position = "top";
      floating = false;
      density = "default";
      widgets = {
        left = [
          {
            id = "Workspace";
          }
          {
            id = "ActiveWindow";
            showIcon = true;
          }
        ];
        center = [
          {
            id = "Clock";
            formatHorizontal = "HH:mm, dd.MM";
          }
        ];
        right = [
          {
            id = "Tray";
          }
          {
            id = "SystemMonitor";
            showCpuUsage = true;
            showMemoryUsage = true;
          }
          {
            id = "Volume";
          }
          {
            id = "ControlCenter";
            useDistroLogo = true;
          }
        ];
      };
    };
    general = {
      language = "de";
      scaleRatio = 1;
      animationDisabled = false;
      lockOnSuspend = true;
    };
    location = {
      name = "Berlin";
      weatherEnabled = true;
      use12hourFormat = false;
      useFahrenheit = false;
    };
    notifications = {
      location = "top_right";
      doNotDisturb = false;
      overlayLayer = true;
    };
    ui = {
      fontDefault = "FiraCode Nerd Font";
      fontFixed = "JetBrainsMono Nerd Font";
      panelsOverlayLayer = true;
    };
    wallpaper = {
      enabled = true;
      transitionType = "random";
      randomEnabled = false;
    };
    settingsVersion = 16;
    setupCompleted = true;
  };

  home.packages =
    lib.optional hasPackage inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    ++ (with pkgs; [
      (writeShellScriptBin "noctalia-start" ''
        echo "Starting Noctalia Shell..."
        killall -q noctalia-shell 2>/dev/null || true
        sleep 0.5

        if command -v noctalia-shell >/dev/null 2>&1; then
          noctalia-shell &
        else
          echo "noctalia-shell binary not found in PATH."
          echo "Noctalia is managed declaratively. Rebuild and verify hyprlandShell=noctalia-shell."
          exit 1
        fi
      '')
      (writeShellScriptBin "noctalia-stop" ''
        echo "Stopping Noctalia Shell..."
        killall -q noctalia-shell 2>/dev/null || true
      '')
      pkgs.matugen
    ]);

  home.activation.noctaliaSettingsInit = lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.optionalString initializeConfig ''
    SETTINGS_DIR="$HOME/.config/noctalia"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
    TEMPLATE_FILE="$SETTINGS_DIR/settings.json.template"

    $DRY_RUN_CMD mkdir -p "$SETTINGS_DIR"

    if [ ! -f "$SETTINGS_FILE" ] || [ -L "$SETTINGS_FILE" ]; then
      $DRY_RUN_CMD rm -f "$SETTINGS_FILE"
      $DRY_RUN_CMD cp "$TEMPLATE_FILE" "$SETTINGS_FILE"
      $DRY_RUN_CMD chmod 644 "$SETTINGS_FILE"
    fi
  '');

  home.activation.noctaliaInfo = lib.hm.dag.entryAfter [ "noctaliaSettingsInit" ] ''
    $DRY_RUN_CMD echo "Noctalia enabled and managed by Nix. Use noctalia-start/noctalia-stop."
  '';

  assertions = [
    {
      assertion = hasNoctaliaInput;
      message = "hyprlandShell=noctalia-shell requires flake input 'noctalia' in flake.nix";
    }
    {
      assertion = hasHomeModule || hasPackage;
      message = ''
        inputs.noctalia must expose either:
        - homeModules.default
        - packages.${pkgs.stdenv.hostPlatform.system}.default
      '';
    }
  ];
}
