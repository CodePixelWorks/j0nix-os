{ pkgs, lib, settings, ... }:
let
  appId = "com.bambulab.BambuStudio";
  flathubUrl = "https://flathub.org/repo/flathub.flatpakrepo";
  bambuFlatpakIcons = pkgs.stdenvNoCC.mkDerivation {
    pname = "bambulab-flatpak-icons";
    version = "1.0.0";
    src = ../../icons/bambulab;
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out/share/icons/hicolor/128x128/apps"
      cp "$src/BambuStudio.png" "$out/share/icons/hicolor/128x128/apps/BambuStudio.png"
      cp "$src/BambuStudio.png" "$out/share/icons/hicolor/128x128/apps/bambulab-flatpak.png"
    '';
  };
  bambuLauncherIconPath = "${bambuFlatpakIcons}/share/icons/hicolor/128x128/apps/bambulab-flatpak.png";
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "flatpak";
  bambuDesktop = pkgs.makeDesktopItem {
    name = "bambulab-flatpak";
    desktopName = "Bambu Studio (Flatpak)";
    # Qt/Wayland Flatpak startup on Hyprland/NVIDIA can show a black pre-window.
    exec = "${pkgs.flatpak}/bin/flatpak run --env=QT_QPA_PLATFORM=xcb ${appId}";
    icon = bambuLauncherIconPath;
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
    environment.systemPackages = [
      bambuDesktop
      bambuFlatpakIcons
    ];

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
