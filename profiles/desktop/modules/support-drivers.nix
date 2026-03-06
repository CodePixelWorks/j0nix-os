{ ... }:
{
  j0nix.desktop.support.drivers = {
    # IT87xx Super-I/O on this motherboard (`it8718-isa-0290` in sensors).
    it87 = {
      enable = true;
      ignoreResourceConflict = true;
      # forceId = "0x8718"; # only set if autodetection fails
    };

    usb.keepAwake = {
      enable = true;
      devices = [
        # GenesysLogic USB 2.1 hub that repeatedly drops and re-enumerates.
        "05e3:0610"
        # USB PnP audio interface behind the same hub.
        "0c76:161f"
        # Logitech receivers behind the same hub.
        "046d:c539"
        "046d:c541"
      ];
    };
  };
}
