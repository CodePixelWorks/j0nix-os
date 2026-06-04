{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).balenaEtcher or { };
  enabled = cfg.enable or false;
  flatpakWrapper = pkgs.writeShellScriptBin "balena-etcher" ''
    exec flatpak run --branch=stable com.balena.etcher "$@"
  '';
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ flatpakWrapper ];
}
