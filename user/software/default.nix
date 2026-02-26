{ config, lib, ... }:
let
  cfg = config.j0nix.user.software;
in
{
  options.j0nix.user.software.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Aggregated Home Manager package requirements collected from modules/roles.";
  };

  config = {
    home.packages = lib.mkAfter (lib.unique cfg.packages);
  };
}
