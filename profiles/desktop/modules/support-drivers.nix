{ ... }:
{
  j0nix.desktop.support.drivers = {
    # IT87xx Super-I/O on this motherboard (`it8718-isa-0290` in sensors).
    it87 = {
      enable = true;
      ignoreResourceConflict = true;
      # forceId = "0x8718"; # only set if autodetection fails
    };
  };
}
