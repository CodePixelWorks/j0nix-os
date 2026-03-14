{ lib, pkgs, settings, ... }:
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
  gtkMode = caelestiaThemeCfg.mode or "dark";
  darkGtk = gtkMode != "light";
  useCatppuccinGtk = gtkScheme == "catppuccin" && gtkFlavour == "mocha" && darkGtk;
  gtkThemeName =
    if useCatppuccinGtk then
      "Catppuccin-Mauve-Dark-Compact"
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
        tweaks = [ ];
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
      min-height: 34px;
      padding: 0 4px;
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
      min-height: 26px;
      padding: 2px 8px;
      border-radius: 10px;
    }
  '';
  gtkCss = if useCatppuccinGtk then compactGtkCss else fallbackGtkCss;
in
{
  home.sessionVariables = lib.optionalAttrs iconThemeEnabled {
    XDG_ICON_THEME = iconThemeName;
    GTK_ICON_THEME = iconThemeName;
    QT_ICON_THEME_NAME = iconThemeName;
    GTK_THEME = gtkThemeName;
  };

  gtk = lib.mkIf (iconThemeEnabled && iconThemePackage != null) {
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
    gtk3.extraCss = gtkCss;
    gtk4.extraCss = gtkCss;
  };

  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;

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
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
  ];
}
