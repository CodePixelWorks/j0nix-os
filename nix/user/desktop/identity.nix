{ config, lib, settings, ... }:
let
  stylixEnabled = ((settings.stylix or { }).enable or false);
in
{
  home = {
    username = settings.username;
    homeDirectory = "/home/${settings.username}";
    stateVersion = "25.11";
  };

  gtk.gtk4.theme = lib.mkIf (!stylixEnabled) config.gtk.theme;
  xdg.userDirs.setSessionVariables = true;

  programs.home-manager.enable = true;
}
