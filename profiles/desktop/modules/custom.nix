{ lib, settings, ... }:
let
  custom = settings.custom or { };
  customSysctl = custom.sysctl or { };
in
{
  j0nix.desktop.sysctl.extraFragments =
    lib.optional (customSysctl != { }) customSysctl;
}
