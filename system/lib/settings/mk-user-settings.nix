{
  baseDir,
  baseSettings,
  lib,
  pkgs,
  profileDetails,
  userOverrides,
}:
username:
let
  userOverride = userOverrides.${username} or { };
  userSecretOverride = userOverride.secrets or { };
  userDevOverride = userOverride.dev or { };
  userProgramOverride = userOverride.programs or { };
  userHyprlandOverride = userOverride.hyprland or { };
  merged =
    baseSettings
    // (builtins.removeAttrs userOverride [
      "secrets"
      "dev"
      "programs"
      "hyprland"
    ])
    // {
      inherit username;
      dotfilesDir = "/home/${username}/DEV/j0nix-os";
    };
  themeDetails = import (baseDir + "/themes/${merged.theme}.nix") { inherit pkgs; };
  defaultWMFromLegacy =
    if userOverride ? wms && (builtins.length userOverride.wms) > 0 then
      builtins.head userOverride.wms
    else
      null;
  resolvedDefaultWMS =
    if userOverride ? defaultWMS then
      userOverride.defaultWMS
    else if defaultWMFromLegacy != null then
      defaultWMFromLegacy
    else
      "hyprland";
  resolvedDefaultSession =
    if resolvedDefaultWMS == "hyprland" then
      (if ((merged.hyprland or { }).useUWSM or true) then "hyprland-uwsm" else "hyprland")
    else
      resolvedDefaultWMS;
in
merged
// {
  inherit profileDetails themeDetails;
  secrets = (baseSettings.secrets or { }) // {
    user = userSecretOverride;
  };
  dev = lib.recursiveUpdate (baseSettings.dev or { }) userDevOverride;
  programs = lib.recursiveUpdate (baseSettings.programs or { }) userProgramOverride;
  hyprland = lib.recursiveUpdate (baseSettings.hyprland or { }) userHyprlandOverride;
  wmShell = merged.wmShell or (merged.hyprlandShell or (themeDetails.shell or "caelestia-shell"));
  hyprlandShell = merged.wmShell or (merged.hyprlandShell or (themeDetails.shell or "caelestia-shell"));
  defaultWMS = resolvedDefaultWMS;
  defaultSession = resolvedDefaultSession;
  _userOverride = userOverride;
}
