{ config, lib, ... }:
let
  cfg = config.j0nix.desktop.drivers.nvidiaPrime;
  enabled = cfg.enable;
in
lib.mkIf enabled {
  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    intelBusId = cfg.intelBusID;
    nvidiaBusId = cfg.nvidiaBusID;
  };
}
