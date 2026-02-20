{ lib, settings, ... }:
let
  cfg = (settings.drivers or { }).hardwareClockLocalTime or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  time.hardwareClockInLocalTime = true;
}
