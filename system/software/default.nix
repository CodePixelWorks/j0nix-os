{ config, lib, ... }:
let
  cfg = config.j0nix.software;
in
{
  options.j0nix.software.systemPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Aggregated system package requirements collected from modules/roles.";
  };

  config = {
    environment.systemPackages = lib.mkAfter (lib.unique cfg.systemPackages);
  };
}
