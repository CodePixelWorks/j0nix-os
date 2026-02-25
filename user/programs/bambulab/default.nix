{ pkgs, lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "flatpak";
  bambulabLauncher = pkgs.writeShellApplication {
    name = "bambulab";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      set -euo pipefail

      # shellcheck disable=SC2194
      case "${provider}" in
        flatpak)
          exec flatpak run com.bambulab.BambuStudio "$@"
          ;;
        nix)
          exec bambu-studio "$@"
          ;;
        appimage)
          exec BambuStudio "$@"
          ;;
        *)
          echo "Unknown Bambu provider: ${provider}" >&2
          exit 1
          ;;
      esac
    '';
  };
  bambulabFlatpak = pkgs.writeShellApplication {
    name = "bambulab-flatpak";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      set -euo pipefail

      app_id="com.bambulab.BambuStudio"
      remote_name="flathub"
      remote_url="https://flathub.org/repo/flathub.flatpakrepo"
      cmd="''${1:-run}"

      ensure_remote() {
        flatpak remote-add --if-not-exists "$remote_name" "$remote_url"
      }

      is_installed() {
        flatpak info --user "$app_id" >/dev/null 2>&1 || flatpak info "$app_id" >/dev/null 2>&1
      }

      case "$cmd" in
        install)
          ensure_remote
          exec flatpak install --user -y "$remote_name" "$app_id"
          ;;
        run)
          if ! is_installed; then
            echo "Bambu Studio Flatpak ist nicht installiert. Installiere nach..."
            ensure_remote
            flatpak install --user -y "$remote_name" "$app_id"
          fi
          exec flatpak run "$app_id"
          ;;
        update)
          exec flatpak update --user -y "$app_id"
          ;;
        uninstall)
          exec flatpak uninstall --user -y "$app_id"
          ;;
        *)
          cat <<EOF
      Usage: bambulab-flatpak [install|run|update|uninstall]

      install    Installiert Bambu Studio aus Flathub (User-Installation)
      run        Startet Bambu Studio und installiert es bei Bedarf zuerst
      update     Aktualisiert nur Bambu Studio
      uninstall  Entfernt Bambu Studio (User-Installation)
      EOF
          exit 1
          ;;
      esac
    '';
  };
in
{
  home.packages =
    [ bambulabLauncher ]
    ++ lib.optionals (provider == "flatpak") [ bambulabFlatpak ];
}
