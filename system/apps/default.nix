{
  lib,
  pkgs,
  settings,
  inputs,
  ...
}:
with lib;
let
  cfg = settings;
in
{
  imports = [
    ./aagl.nix
    ./bambulab.nix
    ./flatpak-sync.nix
    ./fusion360.nix
    ./ollama.nix
    ./syncthing.nix
    ./twintail-launcher.nix
    ./vuescan.nix
  ];
}
