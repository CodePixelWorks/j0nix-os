{ profileMeta, settings, ... }:

{
  j0nix.desktop.network = (settings.network or { }) // {
    hostName = profileMeta.hostname;
  };
}
