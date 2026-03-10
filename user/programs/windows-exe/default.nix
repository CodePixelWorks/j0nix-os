{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).windowsExe or { };
  enabled = cfg.enable or false;
  bottlesPkg = pkgs.bottles-j0nix or pkgs.bottles;
  setAsDefaultHandler = cfg.setAsDefaultHandler or true;
  bottleName = cfg.bottleName or "Default";
  bottleEnvironment = cfg.environment or "application";
  preferredRunner = cfg.runner or null;
  autoBootstrapOnLogin = cfg.autoBootstrapOnLogin or true;
  removeWarningPopup = cfg.removeWarningPopup or true;
  yamlFormat = pkgs.formats.yaml { };
  bottleRunner = if preferredRunner != null then preferredRunner else "soda-9.0-1";
  bottleEnvironmentLabel =
    if bottleEnvironment == "application" then "Application"
    else if bottleEnvironment == "gaming" then "Gaming"
    else "Custom";
  bottleTemplateVersion = "j0nix-default-bottle-v1";

  bottleTemplateConfig = {
    Arch = "win64";
    CompatData = "";
    Creation_Date = "__J0NIX_TIMESTAMP__";
    Custom_Path = false;
    DLL_Overrides = { };
    DXVK = "dxvk-2.7.1";
    Environment = bottleEnvironmentLabel;
    Environment_Variables = { };
    External_Programs = { };
    Inherited_Environment_Variables = [
      "DBUS_SESSION_BUS_ADDRESS"
      "DISPLAY"
      "HOME"
      "LANG"
      "LC_ALL"
      "LC_CTYPE"
      "LC_MESSAGES"
      "PATH"
      "PULSE_SERVER"
      "TERM"
      "TZ"
      "USER"
      "WAYLAND_DISPLAY"
      "XAUTHORITY"
      "XDG_RUNTIME_DIR"
    ];
    Installed_Dependencies = [ ];
    Language = "sys";
    LatencyFleX = "latencyflex-v0.1.1";
    Limit_System_Environment = true;
    NVAPI = "dxvk-nvapi-v0.9.1";
    Name = "__J0NIX_BOTTLE_NAME__";
    Parameters = {
      custom_dpi = 96;
      decorated = true;
      discrete_gpu = false;
      dxvk = true;
      dxvk_nvapi = false;
      fixme_logs = false;
      fsr = false;
      fsr_quality_mode = "none";
      fsr_sharpening_strength = 2;
      fullscreen_capture = false;
      gamemode = false;
      gamescope = false;
      gamescope_borderless = false;
      gamescope_custom_options = "";
      gamescope_fps = 0;
      gamescope_fps_no_focus = 0;
      gamescope_fullscreen = true;
      gamescope_game_height = 0;
      gamescope_game_width = 0;
      gamescope_scaling = false;
      gamescope_window_height = 0;
      gamescope_window_width = 0;
      latencyflex = false;
      mangohud = false;
      mangohud_display_on_game_start = true;
      mouse_warp = true;
      obsvkc = false;
      pulseaudio_latency = false;
      renderer = "gl";
      sandbox = false;
      sync = "wine";
      take_focus = false;
      use_be_runtime = true;
      use_eac_runtime = true;
      use_runtime = false;
      use_steam_runtime = false;
      versioning_automatic = false;
      versioning_compression = false;
      versioning_exclusion_patterns = false;
      virtual_desktop = false;
      virtual_desktop_res = "1280x720";
      vkbasalt = false;
      vkd3d = true;
      vmtouch = false;
      vmtouch_cache_cwd = false;
      wayland = false;
      winebridge = false;
    };
    Path = "__J0NIX_BOTTLE_NAME__";
    Registry_Rules = [ ];
    Runner = bottleRunner;
    RunnerPath = "";
    Sandbox = {
      share_net = false;
      share_sound = false;
    };
    State = 0;
    Uninstallers = { };
    Update_Date = "__J0NIX_TIMESTAMP__";
    VKD3D = "vkd3d-proton-3.0";
    Versioning = false;
    Versioning_Exclusion_Patterns = [ ];
    Windows = "win10";
    Winebridge = false;
    WorkingDir = "";
    data = { };
    run_in_terminal = false;
    session_arguments = "";
  };
  bottleTemplateMetadata = {
    config = bottleTemplateConfig;
    created = "__J0NIX_TEMPLATE_CREATED__";
    env = bottleEnvironment;
    uuid = "__J0NIX_TEMPLATE_UUID__";
  };
  bottleTemplateConfigFile = yamlFormat.generate "j0nix-default-bottle.yml" bottleTemplateConfig;
  bottleTemplateMetadataFile = yamlFormat.generate "j0nix-default-template.yml" bottleTemplateMetadata;

  winexeMimeTypes = [
    "application/x-ms-dos-executable"
    "application/x-msdownload"
    "application/vnd.microsoft.portable-executable"
    "application/x-dosexec"
    "application/x-msi"
  ];

  winexeHandlerDesktopId = "j0nix-winexe";
  winexeDefaultMimeApps =
    lib.genAttrs winexeMimeTypes (_: lib.mkDefault [ "${winexeHandlerDesktopId}.desktop" ]);

  bottleInitScript = pkgs.writeShellApplication {
    name = "winexe-prefix-init";
    runtimeInputs = [ bottlesPkg pkgs.coreutils pkgs.gnugrep ];
    text = ''
      set -eu

      bottle_name="''${WINEXE_BOTTLE_NAME:-${bottleName}}"
      bottle_env="''${WINEXE_BOTTLE_ENV:-${bottleEnvironment}}"
      runner_name="''${WINEXE_BOTTLE_RUNNER:-${if preferredRunner != null then preferredRunner else ""}}"
      bottles_root="''${XDG_DATA_HOME:-$HOME/.local/share}/bottles/bottles"
      bottle_dir="$bottles_root/$bottle_name"
      template_marker="$bottle_dir/.j0nix-template-version"
      timestamp="$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"

      materialize_template_file() {
        src="$1"
        dst="$2"
        ${pkgs.gnused}/bin/sed \
          -e "s#__J0NIX_BOTTLE_NAME__#$bottle_name#g" \
          -e "s#__J0NIX_TIMESTAMP__#$timestamp#g" \
          -e "s#__J0NIX_TEMPLATE_CREATED__#$timestamp#g" \
          -e "s#__J0NIX_TEMPLATE_UUID__#${bottleTemplateVersion}#g" \
          "$src" >"$dst"
      }

      if [ -d "$bottle_dir" ]; then
        if [ -f "$template_marker" ]; then
          exit 0
        fi
        echo "note: existing Bottles bottle '$bottle_name' left unchanged (no j0nix template marker found)." >&2
        exit 0
      fi

      echo "Initializing Bottles bottle '$bottle_name' (environment: $bottle_env)"
      runner_args=()
      if [ -n "$runner_name" ] && [ -x "''${XDG_DATA_HOME:-$HOME/.local/share}/bottles/runners/$runner_name/bin/wine" ]; then
        runner_args=(--runner "$runner_name")
      fi
      bottles-cli new --bottle-name "$bottle_name" --environment "$bottle_env" "''${runner_args[@]}" >/dev/null 2>&1 || true

      # bottles-cli may return success even when component bootstrap failed.
      if [ -d "$bottle_dir" ]; then
        materialize_template_file ${lib.escapeShellArg bottleTemplateConfigFile} "$bottle_dir/bottle.yml"
        materialize_template_file ${lib.escapeShellArg bottleTemplateMetadataFile} "$bottle_dir/template.yml"
        printf '%s\n' "$timestamp" >"$bottle_dir/.update-timestamp"
        printf '%s\n' ${lib.escapeShellArg bottleTemplateVersion} >"$template_marker"
        exit 0
      fi

      echo "error: Bottles konnte die Bottle '$bottle_name' nicht anlegen." >&2
      echo "Grund meist: fehlende Bottles-Komponenten (Runner/DXVK/VKD3D)." >&2
      echo "Bitte einmal Bottles GUI starten und Komponenten installieren," >&2
      echo "danach erneut ausfuehren." >&2
      exit 1
    '';
  };

  runScript = pkgs.writeShellApplication {
    name = "winexe-run";
    runtimeInputs = [ bottleInitScript bottlesPkg pkgs.coreutils ];
    text = ''
      set -eu

      if [ $# -lt 1 ]; then
        echo "usage: winexe-run <file.exe|file.msi>" >&2
        exit 2
      fi

      target="$1"
      shift || true

      if [ ! -e "$target" ]; then
        echo "error: Datei nicht gefunden: $target" >&2
        exit 1
      fi

      target="$(${pkgs.coreutils}/bin/readlink -f "$target")"
      bottle_name="''${WINEXE_BOTTLE_NAME:-${bottleName}}"
      winexe-prefix-init
      exec bottles-cli run --bottle "$bottle_name" --executable "$target" "$@"
    '';
  };

  bootstrapServiceScript = pkgs.writeShellApplication {
    name = "winexe-bootstrap-on-login";
    runtimeInputs = [ bottleInitScript pkgs.coreutils ];
    text = ''
      set -eu
      if ! winexe-prefix-init; then
        echo "warning: windows-exe bootstrap skipped (Bottle/Komponenten fehlen)." >&2
      fi
      exit 0
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [
    bottlesPkg
    bottleInitScript
    runScript
  ];

  xdg.desktopEntries.${winexeHandlerDesktopId} = {
    name = "Windows Program Loader";
    genericName = "Bottles EXE/MSI Runner";
    comment = "Run Windows executable files with the managed default Bottles bottle";
    exec = "winexe-run %f";
    terminal = false;
    type = "Application";
    categories = [ "Utility" ];
    mimeType = winexeMimeTypes;
  };

  xdg.mimeApps.defaultApplications = lib.mkIf setAsDefaultHandler winexeDefaultMimeApps;

  dconf.settings = lib.mkIf removeWarningPopup {
    "com/usebottles/bottles" = {
      show-sandbox-warning = false;
    };
  };

  systemd.user.services.winexe-bottle-bootstrap = lib.mkIf autoBootstrapOnLogin {
    Unit = {
      Description = "Initialize default Bottles bottle for Windows EXE support";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe bootstrapServiceScript}";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Keep retrying in the background until the default bottle exists.
  # Once created, winexe-prefix-init returns immediately.
  systemd.user.timers.winexe-bottle-bootstrap = lib.mkIf autoBootstrapOnLogin {
    Unit = {
      Description = "Periodic bootstrap for default Bottles bottle";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "30m";
      Unit = "winexe-bottle-bootstrap.service";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  assertions = [
    {
      assertion = builtins.isBool enabled;
      message = "settings.programs.windowsExe.enable must be a boolean";
    }
    {
      assertion = builtins.isString bottleName && bottleName != "";
      message = "settings.programs.windowsExe.bottleName must be a non-empty string";
    }
    {
      assertion = builtins.elem bottleEnvironment [ "application" "gaming" "custom" ];
      message = "settings.programs.windowsExe.environment must be one of: application, gaming, custom";
    }
    {
      assertion = preferredRunner == null || (builtins.isString preferredRunner && preferredRunner != "");
      message = "settings.programs.windowsExe.runner must be null or a non-empty string";
    }
    {
      assertion = builtins.isBool autoBootstrapOnLogin;
      message = "settings.programs.windowsExe.autoBootstrapOnLogin must be a boolean";
    }
    {
      assertion = builtins.isBool removeWarningPopup;
      message = "settings.programs.windowsExe.removeWarningPopup must be a boolean";
    }
  ];
}
