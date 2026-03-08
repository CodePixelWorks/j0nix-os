{ lib, settings, ... }:
let
  resolveEnabledWms = import ../system/lib/enabled-wms.nix { inherit lib; };
  enabledWms = resolveEnabledWms settings;
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
      else if defaultWMS == "niri" then
        "niri"
      else if builtins.elem "hyprland" enabledWms then
        (if useUWSM then "hyprland-uwsm" else "hyprland")
      else if builtins.elem "niri" enabledWms then
        "niri"
      else if builtins.elem "gnome" enabledWms then
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
