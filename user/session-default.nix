{ lib, settings, ... }:
let
  useUWSM = (settings.hyprland or { }).useUWSM or true;
  defaultWMS = settings.defaultWMS or null;
  defaultSession =
    settings.defaultSession
    or (
      if defaultWMS == "hyprland" then
        (if useUWSM then "hyprland-uwsm" else "hyprland")
      else if defaultWMS == "gnome" then
        "gnome"
      else if defaultWMS == "mangowc" then
        "mangowc"
      else if builtins.elem "hyprland" (settings.wms or [ ]) then
        (if useUWSM then "hyprland-uwsm" else "hyprland")
      else if builtins.elem "gnome" (settings.wms or [ ]) then
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
