{ lib, ... }:
{
  programs.waybar.enable = lib.mkForce false;
}
