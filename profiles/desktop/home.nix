{ config, lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  bambuProvider = bambuCfg.provider or "appimage";
  # Storage policy moved to the desktop storage profile module; keep user-space udisks automount enabled here.
  enableUdiskieAutomount = true;
  configuredFileManagersRaw =
    settings.fileManagers
    or (lib.optional ((settings.preferredFileManager or null) != null) settings.preferredFileManager);
  configuredFileManagers =
    lib.unique (if configuredFileManagersRaw != [ ] then configuredFileManagersRaw else [ "nautilus" ]);
  preferredFileManager =
    settings.preferredFileManager
    or (if configuredFileManagers != [ ] then builtins.head configuredFileManagers else "nautilus");
  fileManagerPackage = name:
    if name == "nautilus" then
      pkgs.nautilus
    else if name == "nemo" then
      pkgs.nemo
    else if name == "dolphin" then
      if (pkgs ? kdePackages) && (pkgs.kdePackages ? dolphin) then pkgs.kdePackages.dolphin else null
    else if name == "thunar" then
      if (pkgs ? xfce) && (pkgs.xfce ? thunar) then pkgs.xfce.thunar else null
    else
      null;
  fileManagerDesktopId = name:
    if name == "nautilus" then
      "org.gnome.Nautilus.desktop"
    else if name == "nemo" then
      "nemo.desktop"
    else if name == "dolphin" then
      "org.kde.dolphin.desktop"
    else if name == "thunar" then
      "thunar.desktop"
    else
      null;
  fileManagerPackages = lib.filter (pkg: pkg != null) (map fileManagerPackage configuredFileManagers);
  preferredFileManagerDesktopId = fileManagerDesktopId preferredFileManager;
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
    nextcloud-client
    obsidian
    drawio
  ]
  ++ [
    bottles
    simplescreenrecorder
    gpu-screen-recorder
    gpu-screen-recorder-gtk
    krita
    blender
    gimp
    naps2
    keepassxc
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
  ] ++ fileManagerPackages
    ++ (with pkgs; if enableUdiskieAutomount then [ udiskie ] else [ ])
    ++ lib.optionals (pkgs ? fusion360) [ pkgs.fusion360 ]
    ++ lib.optionals (iconThemeEnabled && iconThemePackage != null) ([ iconThemePackage ] ++ iconThemeFallbackPackages);

  xdg.enable = true;
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "chromium.desktop" ];
      "x-scheme-handler/https" = [ "chromium.desktop" ];
      "text/html" = [ "chromium.desktop" ];
    } // lib.optionalAttrs (preferredFileManagerDesktopId != null) {
      "inode/directory" = [ preferredFileManagerDesktopId ];
      "x-scheme-handler/file" = [ preferredFileManagerDesktopId ];
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
  }
  // lib.optionalAttrs (((settings.programs or { }).ollama or { }).modelsPath != null) {
    OLLAMA_MODELS = ((settings.programs or { }).ollama or { }).modelsPath;
  }
  // lib.optionalAttrs (((settings.programs or { }).ollama or { }).host != null) {
    OLLAMA_HOST = ((settings.programs or { }).ollama or { }).host;
  }
  // lib.optionalAttrs iconThemeEnabled {
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
  systemd.user.services.udiskie = lib.mkIf enableUdiskieAutomount {
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
      assertion = builtins.elem bambuProvider [ "appimage" "flatpak" ];
      message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
    }
    {
      assertion = (!iconThemeEnabled) || (iconThemePackage != null);
      message = "settings.iconTheme.package must be one of: colloid, papirus, adwaita, breeze";
    }
    {
      assertion = builtins.elem preferredFileManager configuredFileManagers;
      message = "settings.preferredFileManager must also be included in settings.fileManagers";
    }
    {
      assertion = lib.all (name: builtins.elem name [ "nautilus" "nemo" "dolphin" "thunar" ]) configuredFileManagers;
      message = "settings.fileManagers may only contain: nautilus, nemo, dolphin, thunar";
    }
  ];
}
