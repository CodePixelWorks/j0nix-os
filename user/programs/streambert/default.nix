{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).streambert or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
