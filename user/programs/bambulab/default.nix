{ pkgs, lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuAppImagePackage = pkgs.callPackage ./appimage-package.nix { };
  bambuDesktopEntry = {
    name = "Bambu Studio";
    genericName = "3D Printing Software";
    comment = "3D printing software";
    exec = lib.getExe' bambuAppImagePackage "bambu-studio";
    icon = "${../../../icons/bambulab/BambuStudio.png}";
    terminal = false;
    type = "Application";
    categories = [ "Graphics" "Utility" ];
    startupNotify = true;
  };
in
{
  assertions = [
    {
      assertion = provider == "appimage";
      message = "settings.programs.bambulab.provider is now appimage-only and must be set to \"appimage\"";
    }
  ];

  xdg.desktopEntries = {
    "BambuStudio" = bambuDesktopEntry;
  };
}
