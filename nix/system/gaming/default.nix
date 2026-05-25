{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.j0nix.desktop.gaming = mkOption {
    type = types.attrs;
    default = { };
    description = "Desktop gaming profile settings consumed by system/user gaming modules.";
  };

  imports = [
    ./steam.nix
    ./performance.nix
    ./controllers.nix
    ./streaming.nix
    ./extras.nix
  ];
}
