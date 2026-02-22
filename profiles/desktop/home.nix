{ config, lib, pkgs, settings, ... }:
let
  storage = settings.storage or { };
  autoMountWindows = storage.autoMountWindows or true;
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
  iconThemeFallbackPackages = with pkgs; [
    hicolor-icon-theme
    adwaita-icon-theme
  ];
in
{
  imports = [
    ../../user/gaming
  ];

  home = {
    username = settings.username;
    homeDirectory = "/home/${settings.username}";
  };

  home.packages = with pkgs; [
    foot
    kitty
    git
    gh
    starship
    eza
    bat
    fd
    ripgrep
    tree
    jq

    obs-studio
    qbittorrent
    telegram-desktop
    obsidian
    drawio
    bambu-studio
    bottles
    simplescreenrecorder
    krita
    gimp
    mpv
    libreoffice-fresh

    gcc
    gnumake
    nodejs
    python3
    cargo
    rustc

    openvpn
    unzip
    android-tools
    xdg-utils
  ] ++ (with pkgs; if autoMountWindows then [ udiskie ] else [ ])
    ++ lib.optionals (pkgs ? fusion360) [ pkgs.fusion360 ]
    ++ lib.optionals (iconThemeEnabled && iconThemePackage != null) ([ iconThemePackage ] ++ iconThemeFallbackPackages);

  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "chromium.desktop" ];
      "x-scheme-handler/https" = [ "chromium.desktop" ];
      "text/html" = [ "chromium.desktop" ];
    };
  };
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    music = "${config.home.homeDirectory}/Media/Music";
    videos = "${config.home.homeDirectory}/Media/Videos";
    pictures = "${config.home.homeDirectory}/Media/Pictures";
    download = "${config.home.homeDirectory}/Downloads";
    documents = "${config.home.homeDirectory}/Documents";
    templates = null;
    desktop = null;
    publicShare = null;
    extraConfig = {
      DOTFILES = settings.dotfilesDir;
      BOOK = "${config.home.homeDirectory}/Media/Books";
    };
  };

  home.sessionVariables = {
    EDITOR = settings.preferredEditor;
    BROWSER = settings.preferredBrowser;
  } // lib.optionalAttrs iconThemeEnabled {
    XDG_ICON_THEME = iconThemeName;
    GTK_ICON_THEME = iconThemeName;
    # Quickshell/Caelestia and other Qt apps use Qt's icon theme lookup, not GTK settings.
    QT_ICON_THEME_NAME = iconThemeName;
  };

  gtk = lib.mkIf (iconThemeEnabled && iconThemePackage != null) {
    enable = true;
    iconTheme = {
      name = iconThemeName;
      package = iconThemePackage;
    };
  };

  # GNOME/libadwaita apps (e.g. Nautilus) often read the icon theme from dconf.
  dconf.settings = lib.mkIf iconThemeEnabled {
    "org/gnome/desktop/interface" = {
      icon-theme = iconThemeName;
    };
  };

  # User-space automount for additional internal/removable drives via udisks2.
  systemd.user.services.udiskie = lib.mkIf autoMountWindows {
    Unit = {
      Description = "Udiskie automount daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --smart-tray";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.11";

  assertions = [
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
  ];
}
