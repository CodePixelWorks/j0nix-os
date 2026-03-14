{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  userSettings = builtins.attrValues (settings.userSettings or { });
  userEnabled =
    lib.any (userCfg: (((userCfg.programs or { }).vuescan or { }).enable or false)) userSettings;
  enabled = (cfg.enable or false) || userEnabled;
  provider = cfg.provider or "official";
in
{
  config = lib.mkIf enabled {
    j0nix.desktop.apps.flatpak.entries = if provider == "flatpak" then [
      {
        appId = "com.hamrick.VueScan";
        remote = "flathub";
        branch = "stable";
      }
    ] else [ ];

    services.udev.packages = lib.optional (provider == "official") pkgs.vuescan;

    assertions = [
      {
        assertion = builtins.elem provider [ "flatpak" "official" ];
        message = "settings.programs.vuescan.provider must be one of: flatpak, official when VueScan is enabled.";
      }
    ];
  };
}
