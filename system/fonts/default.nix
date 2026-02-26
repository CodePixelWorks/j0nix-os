{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.fonts;
in
{
  options.j0nix.desktop.fonts.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Font packages installed system-wide for the desktop profile.";
  };

  config = {
    fonts.packages = cfg.packages;
  };
}
