{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  userSettings = builtins.attrValues (settings.userSettings or { });
  userEnabled =
    lib.any (userCfg: (((userCfg.programs or { }).vuescan or { }).enable or false)) userSettings;
  enabled = (cfg.enable or false) || userEnabled;
  provider = cfg.provider or "flatpak";
in
{
  config = lib.mkIf enabled {
    j0nix.desktop.apps.flatpak.entries = [
      {
        appId = "com.hamrick.VueScan";
        remote = "flathub";
        branch = "stable";
      }
    ];

    assertions = [
      {
        assertion = builtins.elem provider [ "flatpak" ];
        message = "settings.programs.vuescan.provider must currently be \"flatpak\" when VueScan is enabled.";
      }
    ];
  };
}
