{ pkgs, lib, settings, ... }:
let
  scanning = settings.scanning or { };
  enable = scanning.enable or true;
  useHplipBackend = scanning.useHplipBackend or true;
in
{
  j0nix.desktop.scanning = {
    enable = enable;
    extraBackends = lib.optionals useHplipBackend [ pkgs.hplipWithPlugin ];
    software = with pkgs; [
      simple-scan
    ];
  };
}
