{ pkgs, ... }:
{
  # Keep MangoWC tools available in user sessions.
  home.packages = with pkgs; [
    wlr-randr
    wtype
  ];
}
