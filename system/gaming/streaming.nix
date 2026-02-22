{ lib, settings, ... }:
let
  gaming = settings.gaming or { };
  gamingEnabled = gaming.enable or true;
  streaming = gaming.streaming or { };
  sunshine = streaming.sunshine or { };
  sunshineEnabled = sunshine.enable or false;
  sunshineOpenFirewall = sunshine.openFirewall or true;
in
lib.mkIf (gamingEnabled && sunshineEnabled) {
  services.sunshine = {
    enable = true;
    openFirewall = sunshineOpenFirewall;
  };

  assertions = [
    {
      assertion = builtins.isBool sunshineOpenFirewall;
      message = "settings.gaming.streaming.sunshine.openFirewall must be a boolean";
    }
  ];
}
