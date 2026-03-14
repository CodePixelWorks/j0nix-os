{ pkgs, lib, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "flatpak";

  vuescanFlatpakAppId = "com.hamrick.VueScan";
  vuescanFlatpakWrapper = pkgs.writeShellScriptBin "vuescan" ''
    exec flatpak run ${vuescanFlatpakAppId} "$@"
  '';
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = builtins.elem provider [ "flatpak" ];
      message = "settings.programs.vuescan.provider must be \"flatpak\".";
    }
  ];

  j0nix.user.software.packages = [ vuescanFlatpakWrapper ];

  xdg.desktopEntries = {
    "VueScan" = {
      name = "VueScan";
      genericName = "Scanner Software";
      comment = "Scan documents and photos with VueScan";
      exec = "${lib.getExe vuescanFlatpakWrapper}";
      icon = vuescanFlatpakAppId;
      terminal = false;
      type = "Application";
      categories = [ "Graphics" "Office" "Scanning" ];
      startupNotify = true;
    };
  };
}
