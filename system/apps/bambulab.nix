{ pkgs, lib, ... }:
let
  appId = "com.bambulab.BambuStudio";
  flathubUrl = "https://flathub.org/repo/flathub.flatpakrepo";
in
{
  services.flatpak.enable = true;

  systemd.services.bambulab-flatpak-install = {
    description = "Ensure Bambu Studio Flatpak is installed from Flathub";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "dbus.service"
      "flatpak-system-helper.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      if ! ${pkgs.flatpak}/bin/flatpak remotes --system --columns=name | ${pkgs.gnugrep}/bin/grep -Fxq flathub; then
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub ${flathubUrl}
      fi

      if ! ${pkgs.flatpak}/bin/flatpak info --system ${appId} >/dev/null 2>&1; then
        ${pkgs.flatpak}/bin/flatpak install --system -y flathub ${appId}
      fi
    '';
  };
}
