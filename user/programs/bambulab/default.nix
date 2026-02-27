{ pkgs, lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuAppImagePackage = pkgs.callPackage ./appimage-package.nix { };
  bambuExec =
    if provider == "flatpak" then
      "flatpak run com.bambulab.BambuStudio"
    else
      lib.getExe' bambuAppImagePackage "bambu-studio";
  bambuDesktopEntry = {
    name = "Bambu Studio";
    genericName = "3D Printing Software";
    comment = "3D printing software";
    exec = bambuExec;
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
      assertion = builtins.elem provider [ "appimage" "flatpak" ];
      message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
    }
  ];

  xdg.desktopEntries = {
    "BambuStudio" = bambuDesktopEntry;
  };
}
