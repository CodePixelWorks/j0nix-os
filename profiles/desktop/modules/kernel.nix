{ settings, ... }:
{
  j0nix.desktop.kernel = settings.kernel or { };
}
