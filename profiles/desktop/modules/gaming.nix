{ ... }:
{
  j0nix.desktop.gaming = {
    enable = true;

    steam = {
      enable = true;
      remotePlayFirewall = false;
      dedicatedServerFirewall = false;
      steamRun = true;
    };

    proton = {
      # Preferred provider for Steam compatibility tools.
      provider = "cachyos"; # "cachyos" | "ge"
      ge = true; # keep GE installed as fallback
      ntsync.enable = true;
      updater = true; # protonup-qt
      cachyos = {
        autoInstall = true;
        variant = "x86_64"; # "x86_64" | "x86_64_v3" | "x86_64_v4"
        keepVersions = 2;
      };
    };

    performance = {
      gamescope = true;
      gamescopeHdr = true;
      gamemode = true;
      autoPerformanceMode = true;
      # Negative values prioritize game CPU scheduling more aggressively.
      gamemodeRenice = -10;
      mangohud = true;
    };

    controllers = {
      enable = true;
      xbox = true;
      nintendo = true;
      dualsense = true;
      ratbag = true;
    };

    launchers = {
      lutris = true;
      heroic = true;
      bottles = true;
      wineGui = false;
      rockstar = true;
      gdlauncher = true;
      teamspeak6 = true;
    };

    streaming = {
      sunshine = {
        enable = true;
        openFirewall = true;
        capSysAdmin = true;
        autoStart = true;
        performance = {
          mode = "aggressive"; # "balanced" | "aggressive"
          addRenderGroup = true;
          addInputGroup = true;
          network = {
            enable = true;
            mode = "aggressive"; # "balanced" | "aggressive"
          };
        };
        virtualDisplay = {
          enable = true;
          appName = "Adaptive Display";
          outputName = "SUNSHINE-HEADLESS";
          capture = "auto"; # On Hyprland this resolves to wlroots/wlr so the legacy fallback stays on the Wayland capture path.
          resolutions = [
            { width = 2880; height = 1800; }
            { width = 2560; height = 1600; }
            { width = 1920; height = 1200; }
            { width = 1920; height = 1080; }
            { width = 1600; height = 900; }
            { width = 1280; height = 720; }
          ];
          fps = [
            60
            90
            120
          ];
        };
      };
    };

    extras = {
      umuLauncher = true;
      nethack = false;
      openSourceGames = false;
      archisteamfarm = true;
    };
  };
}
