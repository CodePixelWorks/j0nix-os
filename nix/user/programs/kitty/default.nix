{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).kitty or { };
  enabled = cfg.enable or false;
  themeName = cfg.theme or "github-dark";
in
lib.mkIf enabled {
  programs.kitty = {
    enable = true;
    settings = {
      terminal-shell-shell = "${pkgs.zsh}/bin/zsh";
      window-padding-x = cfg.padding.x or 8;
      window-padding-y = cfg.padding.y or 8;
      window-opacity = cfg.opacity or 1.0;
      font-size = toString (cfg.fontSize or 12);
      font-family = "JetBrainsMono Nerd Font";
      scrollback-lines = 10000;
      copy-on-select = true;
      strip-trailing-spaces = "always";
      enable-mouse-mouse = true;
      url-color = "underline";
      confirm-window-close = true;
      close-on-child-death = true;
      startup-session = "none";
      tab-bar-edge = "top";
      tab-bar-alignment = "left";
      tab-separator = " ┊";
      tab-title-template = "{title}";
      shell-integration = "enabled";
    };
  };

  # Link theme if themes are enabled (themes are included via programs.kitty theme setting)
  home.file.".config/kitty/kitty-themes/themes/${themeName}.conf" = lib.mkIf cfg.enableThemes {
    source = "${pkgs.kitty-themes}/share/kitty-themes/themes/${themeName}.conf";
  };

  j0nix.user.software.packages = lib.unique (
    [ pkgs.kitty ]
    ++ lib.optionals (cfg.enableThemes or false) [
      pkgs.kitty-themes
    ]
  );
}
