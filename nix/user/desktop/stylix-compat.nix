{ lib, pkgs, settings, ... }:
let
  stylixEnabled = ((settings.stylix or { }).enable or false);
  stylixManagedConfigFiles = [
    "gtk-3.0/gtk.css"
    "gtk-3.0/settings.ini"
    "gtk-4.0/gtk.css"
    "gtk-4.0/settings.ini"
    "qt5ct/qt5ct.conf"
    "qt6ct/qt6ct.conf"
    "Kvantum/kvantum.kvconfig"
  ];
in
lib.mkIf stylixEnabled {
  # Stylix defines these files with force=false. The previous j0nix theme stack
  # already owned the same paths, so force replacement when Stylix is active.
  xdg.configFile = lib.genAttrs stylixManagedConfigFiles (_: {
    force = lib.mkForce true;
  });

  home.activation.cleanLegacyJ0nixThemeFiles = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"

    ${pkgs.coreutils}/bin/rm -f "$config_home/gtk-4.0/gtk-dark.css"
    ${pkgs.coreutils}/bin/rm -f "$config_home/qt5ct/colors/caelestia.colors"
    ${pkgs.coreutils}/bin/rm -f "$config_home/qt6ct/colors/caelestia.colors"
    ${pkgs.coreutils}/bin/rm -rf "$config_home/gtk-4.0/assets"

    for file in gtk-3.0/gtk.css gtk-4.0/gtk.css; do
      target="$config_home/$file"
      if [ -L "$target" ]; then
        link_target="$(${pkgs.coreutils}/bin/readlink "$target")"
        case "$link_target" in
          *-j0nix-gtk-*.css)
            ${pkgs.coreutils}/bin/rm -f "$target"
            ;;
        esac
      fi
    done
  '';
}
