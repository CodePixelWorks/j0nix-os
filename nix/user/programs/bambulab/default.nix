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
  extractedAppImage = "${bambuAppImagePackage}/bin/bambu-studio";
  bambuLauncher = pkgs.writeShellScriptBin "bambu-studio" ''
    cd "$HOME"
    exec ${extractedAppImage} "$@"
  '';
  bambuDesktopExec = lib.getExe bambuLauncher;
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
      assertion = provider == "appimage";
      message = "settings.programs.bambulab.provider must be appimage.";
    }
  ];

  j0nix.user.software.packages = [ bambuLauncher ];

  xdg.dataFile = {
    "applications/BambuStudio.desktop" = {
      text = bambuDesktopEntry.text;
      force = true;
    };
  };
}
