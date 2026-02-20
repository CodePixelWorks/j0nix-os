{ lib, settings, ... }:
let
  cfg = (settings.drivers or { }).vmGuestServices or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
  services.spice-webdavd.enable = true;
  virtualisation.vmware.guest.enable = true;
}
