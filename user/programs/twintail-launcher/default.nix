{ pkgs, lib, settings, ... }:
let
  cfg = (settings.programs or { }).twintailLauncher or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "flatpak";
  appId = "app.twintaillauncher.ttl";
  branch = "stable";
  twintailWrapper = pkgs.writeShellScriptBin "twintail-launcher" ''
    exec flatpak run --branch=${branch} ${appId} "$@"
  '';
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = provider == "flatpak";
      message = "settings.programs.twintailLauncher.provider must be flatpak.";
    }
  ];

  j0nix.user.software.packages = [ twintailWrapper ];
}
