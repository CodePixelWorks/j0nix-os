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
    ./ollama.nix
    ./penguin-burner.nix
    ./syncthing.nix
    ./twintail-launcher.nix
  ];
}
