{ pkgs, lib, settings, ... }:
let
  appId = "com.bambulab.BambuStudio";
  flathubUrl = "https://flathub.org/repo/flathub.flatpakrepo";
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "flatpak";
  bambuDesktop = pkgs.makeDesktopItem {
    name = "bambulab-flatpak";
    desktopName = "Bambu Studio (Flatpak)";
    exec = "${pkgs.flatpak}/bin/flatpak run ${appId}";
    terminal = false;
    categories = [
      "Graphics"
      "Utility"
    ];
    startupNotify = true;
  };
in
{
  config = {
    assertions = [
      {
        assertion = builtins.elem provider [ "flatpak" "nix" ];
        message = "settings.programs.bambulab.provider must be one of: flatpak, nix";
      }
    ];
  } // lib.mkIf (provider == "flatpak") {
    services.flatpak.enable = true;
    environment.systemPackages = [ bambuDesktop ];

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
  };
}
