{ config, lib, pkgs, settings, ... }:
let
  storage = settings.storage or { };
  autoMountWindows = storage.autoMountWindows or true;
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
    vesktop
    telegram-desktop
    drawio
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
  ] ++ (with pkgs; if autoMountWindows then [ udiskie ] else [ ]);

  xdg.enable = true;
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
}
