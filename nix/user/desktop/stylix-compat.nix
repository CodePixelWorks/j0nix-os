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
  # Stylix manages theme config files (gtk-3.0/gtk.css, gtk-4.0/gtk.css,
  # qt5ct/qt6ct, Kvantum, gtk-3.0/gtk-4.0 settings.ini) via its own
  # `home.file` mechanism — NOT `xdg.configFile`. The previous
  # implementation of this module also wrote `xdg.configFile.<path>.force =
  # mkForce true` for these paths, which created empty xdg.configFile
  # entries without a `source`. Home Manager's home-file layer would then
  # read `xdg.configFile."gtk-3.0/gtk.css".source` while materializing the
  # activation script and throw "accessed but has no value", breaking
  # every homeConfiguration evaluation. The right thing here is therefore
  # to leave `xdg.configFile` alone and only run the legacy cleanup.
  #
  # Future schema drift between Stylix and the legacy theme stack should be
  # handled by extending `stylixManagedConfigFiles` below with explicit
  # `xdg.configFile` overrides only when Stylix actually writes a given
  # path through `xdg.configFile` instead of `home.file`.

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
