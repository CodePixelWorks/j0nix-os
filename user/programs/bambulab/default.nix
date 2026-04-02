{
  pkgs,
  lib,
  settings,
  ...
}:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
  bambuAppImagePackage = pkgs.callPackage ./appimage-package.nix { };
  bambuFlatpakBranch = "stable";
  steamRunBin = "${pkgs.steam-run}/bin/steam-run";
  bambuFlatpakWrapper = pkgs.writeShellScriptBin "bambu-studio" ''
    exec flatpak run --branch=${bambuFlatpakBranch} com.bambulab.BambuStudio "$@"
  '';
  extractedAppImage = "${bambuAppImagePackage}/bin/bambu-studio";
  bambuLauncher = pkgs.writeShellScriptBin "bambu-studio" ''
    cd "$HOME"
    exec ${steamRunBin} ${extractedAppImage} "$@"
  '';
  bambuDesktopEntry = {
    name = "Bambu Studio";
    genericName = "3D Printing Software";
    comment = "3D printing software";
    exec = "${lib.getExe bambuLauncher}";
    icon = "${../../../icons/bambulab/BambuStudio.png}";
    terminal = false;
    type = "Application";
    categories = [
      "Graphics"
      "Utility"
    ];
    startupNotify = true;
  };
in
{
  assertions = [
    {
      assertion = builtins.elem provider [
        "appimage"
        "flatpak"
      ];
      message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
    }
  ];

  j0nix.user.software.packages = [
    (lib.mkIf (provider == "flatpak") bambuFlatpakWrapper)
    (lib.mkIf (provider == "appimage") bambuLauncher)
  ];

  xdg.desktopEntries = lib.mkIf (provider == "appimage") {
    "BambuStudio" = bambuDesktopEntry;
  };
}
