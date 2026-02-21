{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).alacritty or { };
  enabled = cfg.enable or true;
in
lib.mkIf enabled {
  programs.alacritty = {
    enable = true;
    settings = {
      terminal.shell = {
        program = "/run/current-system/sw/bin/zsh";
      };
      window = {
        opacity = cfg.opacity or 0.92;
        padding = {
          x = ((cfg.padding or { }).x or 8);
          y = ((cfg.padding or { }).y or 8);
        };
      };
      font = {
        normal.family = "JetBrainsMono Nerd Font";
        size = cfg.fontSize or 12;
      };
      scrolling.history = 10000;
      selection.save_to_clipboard = true;
    };
  };
}
