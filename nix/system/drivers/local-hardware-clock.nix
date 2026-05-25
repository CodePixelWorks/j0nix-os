{ config, lib, ... }:
let
  enabled = config.j0nix.desktop.drivers.hardwareClockLocalTime.enable;
in
lib.mkIf enabled {
  time.hardwareClockInLocalTime = true;
}
