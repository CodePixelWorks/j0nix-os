{ pkgs, lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuAppImagePackage = pkgs.callPackage ./appimage-package.nix { };
  bambuFlatpakWrapper = pkgs.writeShellScriptBin "bambu-studio" ''
    exec flatpak run com.bambulab.BambuStudio "$@"
  '';
  bambuDesktopEntry = {
    name = "Bambu Studio";
    genericName = "3D Printing Software";
    comment = "3D printing software";
    exec = lib.getExe' bambuAppImagePackage "bambu-studio";
    icon = "${../../../icons/bambulab/BambuStudio.png}"; # Correct: keep the explicit repo icon for the AppImage desktop entry.
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

  j0nix.user.software.packages = lib.optionals (provider == "flatpak") [
    bambuFlatpakWrapper
  ];

  xdg.desktopEntries = lib.mkIf (provider == "appimage") {
    "BambuStudio" = bambuDesktopEntry;
  };
}
