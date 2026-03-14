{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).vuescan or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "flatpak";
in
{
  config = lib.mkIf enabled {
    services.flatpak.enable = provider == "flatpak";

    assertions = [
      {
        assertion = builtins.elem provider [ "flatpak" ];
        message = "settings.programs.vuescan.provider must currently be \"flatpak\" when VueScan is enabled.";
      }
    ];
  };
}
