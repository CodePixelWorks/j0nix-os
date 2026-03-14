{ pkgs, lib, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "official";

  vuescanFlatpakAppId = "com.hamrick.VueScan";
  vuescanFlatpakBranch = "stable";
  vuescanFlatpakWrapper = pkgs.writeShellScriptBin "vuescan" ''
    exec flatpak run --branch=${vuescanFlatpakBranch} ${vuescanFlatpakAppId} "$@"
  '';
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = builtins.elem provider [ "flatpak" "official" ];
      message = "settings.programs.vuescan.provider must be one of: flatpak, official.";
    }
  ];

  j0nix.user.software.packages =
    if provider == "flatpak" then
      [ vuescanFlatpakWrapper ]
    else
      [ pkgs.vuescan ];

  xdg.desktopEntries = lib.mkIf (provider == "flatpak") {
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
