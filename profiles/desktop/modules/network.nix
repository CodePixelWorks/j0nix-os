{ lib, profileMeta, settings, ... }:

{
  j0nix.desktop.network = lib.recursiveUpdate (settings.network or { }) {
    hostName = profileMeta.hostname;
    discovery.mdns.allowInterfaces = settings.profileDetails.lanDiscoveryInterfaces or [ ];
  };
}
