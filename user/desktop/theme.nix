{ config, lib, pkgs, settings, ... }:
let
  iconThemeCfg = settings.iconTheme or { };
  iconThemeEnabled = iconThemeCfg.enable or true;
  iconThemeName = iconThemeCfg.name or "Papirus-Dark";
  iconThemePackageKey = iconThemeCfg.package or "papirus";
  iconThemePackage =
    if iconThemePackageKey == "papirus" then
      pkgs.papirus-icon-theme
    else if iconThemePackageKey == "colloid" then
      if pkgs ? "colloid-icon-theme" then
        pkgs."colloid-icon-theme"
      else
        null
    else if iconThemePackageKey == "adwaita" then
      pkgs.adwaita-icon-theme
    else if iconThemePackageKey == "breeze" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? breeze-icons) then
        pkgs.kdePackages.breeze-icons
      else if pkgs ? breeze-icons then
        pkgs.breeze-icons
      else
        null
    else
      null;
  caelestiaCfg = (settings.programs or { }).caelestia or { };
  caelestiaThemeCfg = caelestiaCfg.theme or { };
  gtkScheme = caelestiaThemeCfg.scheme or (settings.theme or "catppuccin");
  gtkFlavour = caelestiaThemeCfg.flavour or "mocha";
  gtkMode = settings.colorSchemePreference or (caelestiaThemeCfg.mode or "dark");
  darkGtk = gtkMode != "light";
  useCatppuccinGtk = gtkScheme == "catppuccin" && gtkFlavour == "mocha" && darkGtk;
  gtkThemeName =
    if useCatppuccinGtk then
      "Catppuccin-GTK-Mauve-Dark-Compact"
    else if darkGtk then
      "Adwaita-dark"
    else
      "Adwaita";
  gtkThemePackage =
    if useCatppuccinGtk then
      pkgs.magnetic-catppuccin-gtk.override {
        accent = [ "mauve" ];
        shade = "dark";
        size = "compact";
        tweaks = [ "black" ];
      }
    else
      pkgs.gnome-themes-extra;
  gtkPalette =
    if darkGtk then
      {
        accent = "#a78bfa";
        accentHover = "#c4b5fd";
        accentPressed = "#ddd6fe";
        window = "#11131a";
        surface = "#1b1f2a";
        surfaceElevated = "#161925";
        header = "#151826";
        border = "#34384a";
        text = "#e5e7eb";
        textMuted = "#9ca3af";
        selectionText = "#11131a";
      }
    else
      {
        accent = "#8b5cf6";
        accentHover = "#7c3aed";
        accentPressed = "#6d28d9";
        window = "#f5f3ff";
        surface = "#ede9fe";
        surfaceElevated = "#faf5ff";
        header = "#ede9fe";
        border = "#c4b5fd";
        text = "#2e1065";
        textMuted = "#5b21b6";
        selectionText = "#faf5ff";
      };
  fallbackGtkCss = ''
    @define-color accent_color ${gtkPalette.accent};
    @define-color accent_bg_color ${gtkPalette.accent};
    @define-color accent_fg_color ${gtkPalette.selectionText};
    @define-color window_bg_color ${gtkPalette.window};
    @define-color view_bg_color ${gtkPalette.surface};
    @define-color headerbar_bg_color ${gtkPalette.header};
    @define-color headerbar_backdrop_color ${gtkPalette.surfaceElevated};
    @define-color dialog_bg_color ${gtkPalette.surfaceElevated};
    @define-color popover_bg_color ${gtkPalette.surfaceElevated};
    @define-color sidebar_bg_color ${gtkPalette.surface};
    @define-color card_bg_color ${gtkPalette.surfaceElevated};
    @define-color border_color ${gtkPalette.border};
    @define-color text_color ${gtkPalette.text};
    @define-color view_fg_color ${gtkPalette.text};
    @define-color window_fg_color ${gtkPalette.text};
    @define-color headerbar_fg_color ${gtkPalette.text};
    @define-color dialog_fg_color ${gtkPalette.text};
    @define-color secondary_fg_color ${gtkPalette.textMuted};
    @define-color selection_bg_color ${gtkPalette.accent};
    @define-color selection_fg_color ${gtkPalette.selectionText};

    * {
      box-shadow: none;
    }

    window,
    dialog,
    .background {
      background: @window_bg_color;
      color: @window_fg_color;
    }

    headerbar,
    .titlebar,
    toolbarview {
      background: @headerbar_bg_color;
      border-bottom: 1px solid alpha(@border_color, 0.7);
      color: @headerbar_fg_color;
      min-height: 38px;
      padding: 2px 6px;
    }

    button,
    entry,
    spinbutton,
    combobox,
    dropdown,
    menuitem,
    tab,
    list row,
    preferencespage row,
    actionrow {
      min-height: 30px;
      padding: 4px 10px;
      border-radius: 10px;
    }

    button {
      background: mix(@surface, @accent_bg_color, 0.08);
      border: 1px solid alpha(@border_color, 0.85);
      color: @text_color;
    }

    button:hover,
    button:focus {
      background: mix(@surface, @accent_bg_color, 0.14);
      border-color: @accent_color;
    }

    button:active,
    button.suggested-action {
      background: @accent_bg_color;
      color: @accent_fg_color;
      border-color: @accent_bg_color;
    }

    entry,
    spinbutton,
    textview,
    searchbar,
    .navigation-sidebar,
    .view,
    scrolledwindow.frame {
      background: @view_bg_color;
      border: 1px solid alpha(@border_color, 0.75);
      color: @view_fg_color;
    }

    .sidebar,
    navigationview > headerbar,
    stacksidebar {
      background: @sidebar_bg_color;
    }

    selected,
    selection {
      background: @selection_bg_color;
      color: @selection_fg_color;
    }
  '';
  compactGtkCss = ''
    headerbar,
    .titlebar,
    toolbarview {
      min-height: 36px;
      padding: 0 6px;
    }

    button,
    entry,
    spinbutton,
    combobox,
    dropdown,
    menuitem,
    tab,
    list row,
    preferencespage row,
    actionrow {
      min-height: 28px;
      padding: 3px 10px;
      border-radius: 7px;
    }
  '';
  gtk3Css =
    if useCatppuccinGtk then
      ''
        @import url("file://${gtkThemePackage}/share/themes/${gtkThemeName}/gtk-3.0/gtk.css");
      ''
      + compactGtkCss
    else
      fallbackGtkCss;
  gtk3CssFile = pkgs.writeText "j0nix-gtk-3.css" gtk3Css;
  gtk4CssFile = pkgs.writeText "j0nix-gtk-4.css" fallbackGtkCss;
  gtk4DarkCssFile = pkgs.writeText "j0nix-gtk-4-dark.css" "";
  xsettingsdConfig = ''
    Net/ThemeName "${gtkThemeName}"
    Net/IconThemeName "${iconThemeName}"
    Gtk/ApplicationPreferDarkTheme ${if darkGtk then "1" else "0"}
  '';
  applyGtkTheme = pkgs.writeShellScript "gtk-theme-apply" ''
    set -eu

    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme '${gtkThemeName}'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme '${iconThemeName}'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme '${if darkGtk then "prefer-dark" else "default"}'
  '';
  restoreGtkCss = pkgs.writeShellScript "gtk-css-restore" ''
    set -eu

    home_dir=${lib.escapeShellArg config.home.homeDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$home_dir/.config/gtk-3.0" "$home_dir/.config/gtk-4.0"
    ${pkgs.coreutils}/bin/ln -sfn ${gtk3CssFile} "$home_dir/.config/gtk-3.0/gtk.css"

    ${lib.optionalString useCatppuccinGtk ''
      ${pkgs.coreutils}/bin/rm -f "$home_dir/.config/gtk-4.0/gtk.css" "$home_dir/.config/gtk-4.0/gtk-dark.css"
    ''}${lib.optionalString (!useCatppuccinGtk) ''
      ${pkgs.coreutils}/bin/ln -sfn ${gtk4CssFile} "$home_dir/.config/gtk-4.0/gtk.css"
    ''}
  '';
in
{
  j0nix.user.software.packages = lib.unique (
    [ gtkThemePackage pkgs.xsettingsd ]
    ++ lib.optional (iconThemeEnabled && iconThemePackage != null) iconThemePackage
  );

  home.sessionVariables = lib.optionalAttrs iconThemeEnabled {
    XDG_ICON_THEME = iconThemeName;
    GTK_ICON_THEME = iconThemeName;
    GTK_THEME = gtkThemeName;
    QT_ICON_THEME_NAME = iconThemeName;
  };

  gtk = lib.mkIf (iconThemeEnabled && iconThemePackage != null) ({
    enable = true;
    theme = {
      name = gtkThemeName;
      package = gtkThemePackage;
    };
    iconTheme = {
      name = iconThemeName;
      package = iconThemePackage;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = darkGtk;
      gtk-decoration-layout = "icon:minimize,maximize,close";
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = darkGtk;
    };
  });

  xdg.configFile."gtk-3.0/gtk.css" = {
    source = gtk3CssFile;
    force = true;
  };
  xdg.configFile."gtk-4.0/gtk.css" = lib.mkMerge [
    {
      force = true;
    }
    (lib.mkIf (!useCatppuccinGtk) {
      source = gtk4CssFile;
    })
  ];
  xdg.configFile."gtk-4.0/gtk-dark.css" = {
    source = gtk4DarkCssFile;
    force = true;
  };
  xdg.configFile."xsettingsd/xsettingsd.conf".text = xsettingsdConfig;

  home.activation.cleanGtk4UserCss = lib.hm.dag.entryAfter [ "writeBoundary" ] (lib.optionalString useCatppuccinGtk ''
    rm -f ${lib.escapeShellArg config.home.homeDirectory}/.config/gtk-4.0/gtk.css
    rm -f ${lib.escapeShellArg config.home.homeDirectory}/.config/gtk-4.0/gtk-dark.css
  '');

  systemd.user.services.xsettingsd = {
    Unit = {
      Description = "XSettings daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.xsettingsd}/bin/xsettingsd -c %h/.config/xsettingsd/xsettingsd.conf";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.gtk-theme-apply = {
    Unit = {
      Description = "Apply the GTK theme preference to the live session";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "xsettingsd.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = applyGtkTheme;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.gtk-css-restore = {
    Unit = {
      Description = "Restore managed GTK user CSS after session startup";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "gtk-theme-apply.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -lc 'sleep 8; exec ${restoreGtkCss}'";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  dconf.settings = lib.mkIf iconThemeEnabled {
    "org/gnome/desktop/interface" = {
      color-scheme = if darkGtk then "prefer-dark" else "default";
      gtk-theme = gtkThemeName;
      icon-theme = iconThemeName;
      font-name = "Cantarell 11";
      document-font-name = "Cantarell 11";
      monospace-font-name = "JetBrainsMono Nerd Font 11";
    };
  };

  assertions = [
    {
      assertion = builtins.elem gtkMode [ "light" "dark" ];
      message = "settings.colorSchemePreference must be either \"light\" or \"dark\".";
    }
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
  ];
}
