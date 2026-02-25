{ pkgs, lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuDesktopEntry = {
    name = "Bambu Studio";
    genericName = "3D Printing Software";
    comment = "3D printing software";
    exec = "bambulab";
    icon = "${../../../icons/bambulab/BambuStudio.png}";
    terminal = false;
    type = "Application";
    categories = [ "Graphics" "Utility" ];
    startupNotify = true;
  };
  bambulabLauncher = pkgs.writeShellApplication {
    name = "bambulab";
    text = ''
      set -euo pipefail

      exec BambuStudio "$@"
    '';
  };
in
{
  assertions = [
    {
      assertion = provider == "appimage";
      message = "settings.programs.bambulab.provider is now appimage-only and must be set to \"appimage\"";
    }
  ];

  home.packages = [ bambulabLauncher ];

  xdg.desktopEntries = {
    "BambuStudio" = bambuDesktopEntry;
    "com.bambulab.BambuStudio" = bambuDesktopEntry // {
      noDisplay = true;
    };
  };
}
