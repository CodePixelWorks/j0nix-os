{ config, lib, pkgs, settings, ... }:
let
  cfg = settings.terminalMultiplexer or { };
  enabled = cfg.enable or false;
in
{
  j0nix.user.software.packages = lib.mkIf enabled [ pkgs.tmux ];

  programs.tmux = lib.mkIf enabled {
    enable = true;
  };
}
