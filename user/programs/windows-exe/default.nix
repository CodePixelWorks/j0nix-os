{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).windowsExe or { };
  enabled = cfg.enable or false;
  setAsDefaultHandler = cfg.setAsDefaultHandler or true;
  bottleName = cfg.bottleName or "Default";
  bottleEnvironment = cfg.environment or "application";
  preferredRunner = cfg.runner or null;
  autoBootstrapOnLogin = cfg.autoBootstrapOnLogin or true;
  removeWarningPopup = cfg.removeWarningPopup or true;

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
    runtimeInputs = with pkgs; [ bottles coreutils gnugrep ];
    text = ''
      set -eu

      bottle_name="''${WINEXE_BOTTLE_NAME:-${bottleName}}"
      bottle_env="''${WINEXE_BOTTLE_ENV:-${bottleEnvironment}}"
      runner_name="''${WINEXE_BOTTLE_RUNNER:-${if preferredRunner != null then preferredRunner else ""}}"
      bottles_root="''${XDG_DATA_HOME:-$HOME/.local/share}/bottles/bottles"
      bottle_dir="$bottles_root/$bottle_name"

      if [ -d "$bottle_dir" ]; then
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
    runtimeInputs = [ bottleInitScript pkgs.bottles pkgs.coreutils ];
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
    pkgs.bottles
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
