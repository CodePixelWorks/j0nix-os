{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  enabled = cfg.enable or false;
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
