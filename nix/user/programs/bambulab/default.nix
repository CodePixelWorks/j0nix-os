{
  pkgs,
  lib,
  settings,
  ...
}:
let
  programsCfg = settings.programs or { };
  cfg = programsCfg.bambulab or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "appimage";
  bambuAppImagePackage = pkgs.bambu-studio-appimage;
  bambuFlatpakBranch = "stable";
  bambuFlatpakWrapper = pkgs.writeShellScriptBin "bambu-studio" ''
    exec flatpak run --branch=${bambuFlatpakBranch} com.bambulab.BambuStudio "$@"
  '';
  extractedAppImage = "${bambuAppImagePackage}/bin/bambu-studio";
  bambuLauncher = pkgs.writeShellScriptBin "bambu-studio" ''
    cd "$HOME"
    exec ${extractedAppImage} "$@"
  '';
  bambuDesktopExec = lib.getExe (
    if provider == "flatpak" then bambuFlatpakWrapper else bambuLauncher
  );
  bambuDesktopIcon = "${../../../../icons/bambulab/BambuStudio.png}";
  bambuDesktopEntry = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Bambu Studio
      GenericName=3D Printing Software
      Comment=3D printing software
      Exec=${bambuDesktopExec} %U
      Icon=${bambuDesktopIcon}
      Terminal=false
      StartupNotify=true
      Categories=Graphics;Utility;
      MimeType=model/stl;model/3mf;application/sla;application/vnd.ms-3mfdocument;
    '';
  };
in
lib.mkIf enabled {
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

  xdg.dataFile = {
    "applications/BambuStudio.desktop" = {
      text = bambuDesktopEntry.text;
      force = true;
    };
  };
}
