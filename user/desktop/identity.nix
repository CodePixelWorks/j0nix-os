{ config, settings, ... }:
{
  home = {
    username = settings.username;
    homeDirectory = "/home/${settings.username}";
    stateVersion = "25.11";
  };

  gtk.gtk4.theme = config.gtk.theme;
  xdg.userDirs.setSessionVariables = true;

  programs.home-manager.enable = true;
}
