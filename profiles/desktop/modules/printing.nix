{ pkgs, ... }:
{
  j0nix.desktop.printing = {
    enable = true;

    # HP OfficeJet 5220 reachable via local network.
    drivers = [ pkgs.hplip ];

    printers = [
      {
        name = "HP-OfficeJet-5220";
        location = "LAN";
        description = "HP OfficeJet 5220";
        deviceUri = "ipp://172.17.0.3/ipp/print";
        # IPP Everywhere is generally the most robust choice over network IPP.
        model = "everywhere";
      }
    ];

    defaultPrinter = "HP-OfficeJet-5220";
  };
}
