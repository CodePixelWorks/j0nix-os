{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.virtualisation;
in
{
  imports = [
    ./vm-guest-services.nix
  ];

  options.j0nix.desktop.virtualisation = {
    libvirtd.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    vmGuestServices.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = {
    virtualisation.libvirtd.enable = cfg.libvirtd.enable;
  };
}
