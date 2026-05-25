{ settings, ... }:
{
  j0nix.user.software.packages = settings.extraSoftware or [ ];
}
