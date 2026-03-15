{ lib, settings, ... }:
let
  cfg = (settings.programs or { }).twintailLauncher or { };
  userSettings = builtins.attrValues (settings.userSettings or { });
  userEnabled =
    lib.any (userCfg: (((userCfg.programs or { }).twintailLauncher or { }).enable or false)) userSettings;
  enabled = (cfg.enable or false) || userEnabled;
  provider = cfg.provider or "flatpak";
in
{
  config = lib.mkIf enabled {
    j0nix.desktop.apps.flatpak.entries = if provider == "flatpak" then [
      {
        appId = "app.twintaillauncher.ttl";
        remote = "flathub";
        branch = "stable";
      }
    ] else [ ];

    assertions = [
      {
        assertion = provider == "flatpak";
        message = "settings.programs.twintailLauncher.provider must be flatpak when Twintail Launcher is enabled.";
      }
    ];
  };
}
