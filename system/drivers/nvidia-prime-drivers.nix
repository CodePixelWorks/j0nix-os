{ lib, settings, ... }:
let
  cfg = (settings.drivers or { }).nvidiaPrime or { };
  enabled = cfg.enable or false;
in
lib.mkIf enabled {
  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    intelBusId = cfg.intelBusID or "PCI:1:0:0";
    nvidiaBusId = cfg.nvidiaBusID or "PCI:0:2:0";
  };
}
