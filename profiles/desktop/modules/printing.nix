{ pkgs, ... }:
{
  j0nix.desktop.printing = {
    enable = true;

    # HP OfficeJet 5220 reachable via local network.
    drivers = [ pkgs.hplipWithPlugin ];

    # Local management + HP tooling (hp-setup) + scanner UI.
    software = with pkgs; [
      system-config-printer
      hplip
    ];

    # Network printer discovery / hostname resolution via mDNS (Avahi).
    discovery.enable = true;

    printers = [
      {
        name = "HP-OfficeJet-5200";
        location = "LAN";
        description = "HP OfficeJet 5200 series";
        deviceUri = "ipp://172.17.0.3/ipp/print";
        # Prefer a stable direct IPP queue instead of transient dnssd-discovered queues.
        model = "everywhere";
      }
    ];

    defaultPrinter = "HP-OfficeJet-5200";
  };
}
