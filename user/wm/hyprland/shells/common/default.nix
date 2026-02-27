{ config, lib, ... }:
let
  listMerge = import ../../../../../system/lib/list-merge.nix { inherit lib; };
  cfg = config.j0nix.user.shells;
in
{
  options.j0nix.user.shells = {
    quickshell.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Aggregated package requirements shared by quickshell-based shell modules.";
    };

    fonts.packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Font packages required by active shell modules.";
    };
  };

  config = {
    j0nix.user.software.packages = lib.mkAfter (listMerge.mergeUnique [
      cfg.quickshell.packages
      cfg.fonts.packages
    ]);
  };
}
