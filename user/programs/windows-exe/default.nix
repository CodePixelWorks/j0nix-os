{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).windowsExe or { };
  enabled = cfg.enable or false;
  setAsDefaultHandler = cfg.setAsDefaultHandler or true;
  bottleName = cfg.bottleName or "Default";
  bottleEnvironment = cfg.environment or "application";

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
      bottles_root="''${XDG_DATA_HOME:-$HOME/.local/share}/bottles/bottles"
      bottle_dir="$bottles_root/$bottle_name"

      if [ -d "$bottle_dir" ]; then
        exit 0
      fi

      echo "Initializing Bottles bottle '$bottle_name' (environment: $bottle_env)"
      if bottles-cli new -b "$bottle_name" -e "$bottle_env" >/dev/null 2>&1; then
        exit 0
      fi

      if bottles-cli new --bottle "$bottle_name" --environment "$bottle_env" >/dev/null 2>&1; then
        exit 0
      fi

      echo "warning: could not create bottle via CLI automatically." >&2
      echo "Open Bottles once and create bottle '$bottle_name', then retry." >&2
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

      bottle_name="''${WINEXE_BOTTLE_NAME:-${bottleName}}"
      winexe-prefix-init
      exec bottles-cli run -b "$bottle_name" -e "$target"
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
  ];
}
