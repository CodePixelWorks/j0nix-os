{
  config,
  lib,
  pkgs,
  ...
}:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  steamCfg = gaming.steam or { };
  steamEnabled = steamCfg.enable or true;
  steamRunEnabled = steamCfg.steamRun or true;

  perfCfg = gaming.performance or { };
  gamescopeEnabled = perfCfg.gamescope or true;

  protonCfg = gaming.proton or { };
  protonProvider = protonCfg.provider or "ge";
  protonGeEnabled = protonCfg.ge or true;
  protonNtSync = protonCfg.ntsync or { };
  protonNtSyncEnabled = protonNtSync.enable or false;
in
lib.mkIf (enabled && steamEnabled) {
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = steamCfg.remotePlayFirewall or false;
    dedicatedServer.openFirewall = steamCfg.dedicatedServerFirewall or false;
    extraCompatPackages = lib.optionals (protonProvider == "ge" || protonGeEnabled) [
      pkgs.proton-ge-bin
    ];
    gamescopeSession.enable = gamescopeEnabled;

    # Extra runtime libs improve compatibility for some Proton/Steam games.
    package = pkgs.steam.override {
      extraPkgs =
        pkgs': with pkgs'; [
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

  j0nix.software.systemPackages = lib.optionals steamRunEnabled [
    pkgs.steam-run
  ];

  j0nix.desktop.kernel.modules = lib.optionals protonNtSyncEnabled [
    "ntsync"
  ];

  environment.sessionVariables =
    if protonNtSyncEnabled then
      {
        PROTON_USE_NTSYNC = "1";
        PROTON_NO_FSYNC = "1";
        WINEFSYNC = "0";
      }
    else
      {
        # Explicitly ensure FSYNC is active when NTSync is not used.
        WINEFSYNC = "1";
      };

  assertions = [
    {
      assertion = builtins.elem protonProvider [
        "cachyos"
        "ge"
      ];
      message = "j0nix.desktop.gaming.proton.provider must be one of: cachyos, ge";
    }
  ];
}
