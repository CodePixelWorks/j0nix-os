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
          cpuRealtimePriority = 20; # keep high, but below pathological RT values like 99
          addRenderGroup = true;
          addInputGroup = true;
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
