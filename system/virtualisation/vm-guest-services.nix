{ config, lib, ... }:
let
  enabled = config.j0nix.desktop.virtualisation.vmGuestServices.enable;
in
lib.mkIf enabled {
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  services.spice-webdavd.enable = true;
  virtualisation.vmware.guest.enable = true;
}
