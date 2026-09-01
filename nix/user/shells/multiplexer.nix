{ config, lib, pkgs, settings, ... }:
let
  cfg = settings.terminalMultiplexer or { };
  enabled = cfg.enable or false;
  command = cfg.command or "tmux";
  startMultiplexer = ''
    if [ -n "$PS1" ] && [ -z "''${TMUX:-}" ] && [ "''${TERM:-}" != "dumb" ] && command -v ${command} >/dev/null 2>&1; then
      exec ${command} new-session
    fi
  '';
in
{
  j0nix.user.software.packages = lib.mkIf enabled [ pkgs.tmux ];

  programs.tmux = lib.mkIf enabled {
    enable = true;
  };

  programs.bash = lib.mkIf enabled {
    enable = true;
    initExtra = startMultiplexer;
  };

  programs.zsh.initContent = lib.mkIf enabled (lib.mkBefore startMultiplexer);

  programs.fish.interactiveShellInit = lib.mkIf enabled (lib.mkBefore ''
    if status is-interactive; and test -z "$TMUX"; and test "$TERM" != dumb; and command -q ${command}
      exec ${command} new-session
    end
  '');
}
