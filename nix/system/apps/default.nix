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
    ./autodesk-fusion.nix
    ./bambulab.nix
    ./flatpak-sync.nix
    ./ollama.nix
    ./syncthing.nix
    ./twintail-launcher.nix
  ];
}
