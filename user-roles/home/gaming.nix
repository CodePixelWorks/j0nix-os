{ pkgs, ... }:
{
  # When gaming role is selected, add open-source games and nethack to user packages
  j0nix.user.software.packages = with pkgs; [
    supertuxkart
    supertux
    zeroad
    wesnoth
    xonotic
    luanti
    airshipper
    pioneer
    nethack
  ];

  # Add nethack configuration file
  home.file.".nethackrc" = {
    text = ''
      OPTIONS=windowtype:curses
      OPTIONS=popup_dialog
      OPTIONS=splash_screen
      OPTIONS=guicolor
      OPTIONS=perm_invent
    '';
  };
}
