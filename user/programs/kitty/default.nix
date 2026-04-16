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
  themePackage = if cfg.enableThemes or false then pkgs.kitty-themes else null;
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
      shell-integration = {
        enabled = true;
        no-rc = false;
      };
    };
  };

  # Link theme if themes are enabled
  home.file.".config/kitty/kitty-themes/themes/${themeName}.conf" = lib.mkIf (themePackage != null) {
    source = "${themePackage}/share/kitty-themes/themes/${themeName}.conf";
  };

  # Add theme include to kitty.conf if themes enabled
  programs.kitty.finalSettings = lib.mkIf (themePackage != null) {
    include = "./kitty-themes/themes/${themeName}.conf";
  };

  j0nix.user.software.packages = lib.unique (
    [ pkgs.kitty ]
    ++ lib.optional (cfg.enableTabs or false) (
      pkgs.python3.override {
        enableUnstableFreeze = false;
      }
    )
    ++ lib.optionals (cfg.enableTabs or false) [
      (pkgs.python3Packages.toPython3 pkgs.python3Packages.kitty-tabs)
    ]
  );
}
