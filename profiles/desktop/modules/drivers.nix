{ settings, ... }:
{
  j0nix.desktop.drivers = settings.drivers or { };
}
