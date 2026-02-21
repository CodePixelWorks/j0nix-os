{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  steamCfg = gaming.steam or { };
  steamEnabled = steamCfg.enable or true;
  steamRunEnabled = steamCfg.steamRun or true;

  perfCfg = gaming.performance or { };
  gamescopeEnabled = perfCfg.gamescope or true;

  protonCfg = gaming.proton or { };
  protonProvider = protonCfg.provider or "ge";
  protonGeEnabled = protonCfg.ge or true;
in
lib.mkIf (enabled && steamEnabled) {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = steamCfg.remotePlayFirewall or false;
    dedicatedServer.openFirewall = steamCfg.dedicatedServerFirewall or false;
    extraCompatPackages =
      lib.optionals (protonProvider == "ge" || protonGeEnabled) [ pkgs.proton-ge-bin ];
    gamescopeSession.enable = gamescopeEnabled;

    # Extra runtime libs improve compatibility for some Proton/Steam games.
    package = pkgs.steam.override {
      extraPkgs = pkgs': with pkgs'; [
        libusb1
        udev
        SDL2
        libXcursor
        libXi
        libXinerama
        libXScrnSaver
        libXcomposite
        libXdamage
        libXrender
        libXext
        libpng
        libpulseaudio
        libvorbis
        stdenv.cc.cc.lib
        libkrb5
        keyutils
      ];
    };
  };

  environment.systemPackages = lib.optionals steamRunEnabled [
    pkgs.steam-run
  ];

  assertions = [
    {
      assertion = builtins.elem protonProvider [ "cachyos" "ge" ];
      message = "settings.gaming.proton.provider must be one of: cachyos, ge";
    }
  ];
}
