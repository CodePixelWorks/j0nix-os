# profiles/desktop/modules/ipv6-client.nix
#
# The desktop is a pure IPv6 client of the home OPNsense: it must learn a
# global /64 and the default route from Router Advertisements.
#
# Why this exists: on 2026-11-17 the wired uplink reported
# `net.ipv6.conf.enp5s0.accept_ra = 0` although the kernel default is 1 and
# NetworkManager runs the connection with `ipv6.method=auto`. The host then
# had no global address and no default route at all, while the firewall was
# already advertising (bridge0 holding 2a02:2455:a084:ae09::/64). Pin the
# knob explicitly so a NetworkManager or kernel default change cannot
# silently disable IPv6 again.
{ lib, ... }:
let
  # Keep in sync with `lanDiscoveryInterfaces` in profiles/desktop/details.nix:
  # that list already names the uplink that owns the home L2 segment.
  uplinkInterfaces = [ "enp5s0" ];
in
{
  # accept_ra = 2 also accepts advertisements when forwarding is enabled
  # somewhere on the host (Docker/containers flip it), 1 would be ignored then.
  boot.kernel.sysctl = lib.listToAttrs (
    lib.concatMap (iface: [
      {
        name = "net.ipv6.conf.${iface}.accept_ra";
        value = 2;
      }
      {
        name = "net.ipv6.conf.${iface}.accept_ra_defrtr";
        value = 1;
      }
      {
        name = "net.ipv6.conf.${iface}.accept_ra_privacy";
        value = 1;
      }
    ]) uplinkInterfaces
  );
}
