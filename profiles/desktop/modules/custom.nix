{ settings, ... }:

{
  j0nix.desktop.sysctl.extraFragments =
    let
      sysctl = (settings.custom or { }).sysctl or { };
    in
    if sysctl != { } then [ sysctl ] else [ ];
}
