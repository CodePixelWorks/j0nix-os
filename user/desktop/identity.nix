{ settings, ... }:
{
  home = {
    username = settings.username;
    homeDirectory = "/home/${settings.username}";
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
