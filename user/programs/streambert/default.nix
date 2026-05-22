{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = lib.attrByPath [ "programs" "streambert" ] { enable = false; } settings;
in
lib.mkIf cfg.enable {
  j0nix.user.software.packages = [ pkgs.streambert ];
}
