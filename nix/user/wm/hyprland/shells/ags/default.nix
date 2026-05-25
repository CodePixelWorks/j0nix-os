{ inputs, lib, pkgs, ... }:
let
  hasAgsModule = (inputs ? ags) && (inputs.ags ? homeManagerModules) && (inputs.ags.homeManagerModules ? default);
in {
  imports = lib.optional hasAgsModule inputs.ags.homeManagerModules.default;

  programs.waybar.enable = lib.mkForce false;

  j0nix.user.software.packages = lib.mkAfter (with pkgs; [
    ags
    bun
    dart-sass
    gjs
    gtk3
    networkmanager
    pavucontrol
  ]);
}
