{ lib, settings, ... }:
let
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  defaultSession =
    settings.defaultSession
    or (
      if builtins.elem "hyprland" settings.wms then
        (if useUWSM then "hyprland-uwsm" else "hyprland")
      else if builtins.elem "gnome" settings.wms then
        "gnome"
      else
        null
    );
in {
  home.file.".dmrc" = lib.mkIf (defaultSession != null) {
    text = ''
      [Desktop]
      Session=${defaultSession}
    '';
  };
}
