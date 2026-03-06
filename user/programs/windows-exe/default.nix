{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).windowsExe or { };
  enabled = cfg.enable or false;
  defaultPrefix = cfg.prefix or "$HOME/.local/share/wineprefixes/default";
  setAsDefaultHandler = cfg.setAsDefaultHandler or true;
  bootstrap = cfg.bootstrap or { };
  bootstrapEnable = bootstrap.enable or true;
  bootstrapVerbs = bootstrap.verbs or [
    "corefonts"
    "vcrun2022"
    "dxvk"
    "win10"
  ];
  bootstrapStrict = bootstrap.strict or false;

  winePackage =
    if (pkgs ? wineWow64Packages) && (pkgs.wineWow64Packages ? waylandFull) then
      pkgs.wineWow64Packages.waylandFull
    else if (pkgs ? wineWow64Packages) && (pkgs.wineWow64Packages ? full) then
      pkgs.wineWow64Packages.full
    else
      pkgs.wineWowPackages.full;

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

  prefixInitScript = pkgs.writeShellApplication {
    name = "winexe-prefix-init";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
      util-linux
      winePackage
      winetricks
    ];
    text = ''
      set -eu

      prefix="''${WINEXE_PREFIX:-${defaultPrefix}}"
      mkdir -p "$prefix"
      export WINEPREFIX="$prefix"

      marker_dir="$prefix/.j0nix/winetricks"
      mkdir -p "$marker_dir"

      if [ ! -f "$prefix/system.reg" ]; then
        echo "Initializing Wine prefix: $prefix"
        wineboot -u >/dev/null 2>&1 || true
        wineserver -w >/dev/null 2>&1 || true
      fi

      ${if bootstrapEnable then ''
        if [ $# -gt 0 ]; then
          verbs="$*"
        else
          verbs="${lib.concatStringsSep " " bootstrapVerbs}"
        fi

        for verb in $verbs; do
          marker_name="$(printf '%s' "$verb" | tr '/ :=' '____')"
          marker="$marker_dir/$marker_name.done"

          if [ -f "$marker" ]; then
            continue
          fi

          echo "Installing winetricks verb: $verb"
          if WINETRICKS_LATEST_VERSION_CHECK=disabled winetricks -q "$verb"; then
            touch "$marker"
          else
            echo "warning: winetricks verb failed: $verb" >&2
            ${if bootstrapStrict then "exit 1" else "true"}
          fi
        done
      '' else ''
        exit 0
      ''}
    '';
  };

  runScript = pkgs.writeShellApplication {
    name = "winexe-run";
    runtimeInputs = [
      prefixInitScript
      winePackage
      pkgs.coreutils
    ];
    text = ''
      set -eu

      if [ $# -lt 1 ]; then
        echo "usage: winexe-run <file.exe|file.msi> [args...]" >&2
        exit 2
      fi

      target="$1"
      shift

      winexe-prefix-init

      case "$target" in
        *.msi|*.MSI)
          exec wine msiexec /i "$target" "$@"
          ;;
        *)
          exec wine "$target" "$@"
          ;;
      esac
    '';
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages = [
    winePackage
    pkgs.winetricks
    prefixInitScript
    runScript
  ];

  xdg.desktopEntries.${winexeHandlerDesktopId} = {
    name = "Windows Program Loader";
    genericName = "Wine EXE/MSI Runner";
    comment = "Run Windows executable files with the managed default Wine prefix";
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
      assertion = builtins.isString defaultPrefix && defaultPrefix != "";
      message = "settings.programs.windowsExe.prefix must be a non-empty string";
    }
    {
      assertion = builtins.isList bootstrapVerbs;
      message = "settings.programs.windowsExe.bootstrap.verbs must be a list of winetricks verbs";
    }
  ];
}
