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

  config = lib.mkMerge [
    (lib.mkIf cfg.libvirtd.enable {
      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          swtpm.enable = true;
        };
      };
      j0nix.desktop.accounts.additionalExtraGroups = [
        "libvirtd"
        "kvm"
      ];
    })
    {
      virtualisation.libvirtd.enable = cfg.libvirtd.enable;
    }
  ];
}
