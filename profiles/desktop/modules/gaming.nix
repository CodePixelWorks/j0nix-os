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
          capture = "auto"; # Let Sunshine choose the least-broken capture path for the current driver stack.
          resolutions = [
            "2880x1800"
            "2560x1600"
            "1920x1200"
            "1920x1080"
            "1600x900"
            "1280x720"
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
    };
  };
}
