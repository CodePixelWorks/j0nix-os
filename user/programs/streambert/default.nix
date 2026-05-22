{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (lib.attrByPath [ "userSettings" "jonas" "programs" "streambert" ] { } settings);
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
