{ lib, settings, ... }:
let
  profiles = settings.sysctlProfiles or { };
  gaming = profiles.gaming or { };
  dev = profiles.dev or { };
  gamingEnabled = gaming.enable or true;
  devEnabled = dev.enable or true;

  gamingSysctl = import ./gaming.nix { inherit settings; };
  devSysctl = import ./dev.nix { inherit settings; };

  resolvedFileMax =
    profiles.fileMax
    or (gaming.fileMax or (dev.fileMax or 2097152));

  legacyFileMaxConflict =
    (gaming ? fileMax)
    && (dev ? fileMax)
    && (gaming.fileMax != dev.fileMax)
    && !(profiles ? fileMax);
in {
  boot.kernel.sysctl = lib.mkMerge [
    (lib.mkIf gamingEnabled gamingSysctl)
    (lib.mkIf devEnabled devSysctl)
    {
      # Unified definition avoids duplicate fs.file-max when multiple profiles are enabled.
      "fs.file-max" = lib.mkDefault resolvedFileMax;
    }
    (profiles.custom or { })
  ];

  assertions = [
    {
      assertion = (gaming.swappiness or 10) >= 0 && (gaming.swappiness or 10) <= 200;
      message = "settings.sysctlProfiles.gaming.swappiness must be between 0 and 200";
    }
    {
      assertion = (gaming.dirtyBackgroundRatio or 5) >= 1 && (gaming.dirtyBackgroundRatio or 5) <= 50;
      message = "settings.sysctlProfiles.gaming.dirtyBackgroundRatio must be between 1 and 50";
    }
    {
      assertion = (gaming.dirtyRatio or 15) >= 1 && (gaming.dirtyRatio or 15) <= 80;
      message = "settings.sysctlProfiles.gaming.dirtyRatio must be between 1 and 80";
    }
    {
      assertion = resolvedFileMax >= 131072;
      message = "settings.sysctlProfiles.fileMax should be >= 131072";
    }
    {
      assertion = !legacyFileMaxConflict;
      message = "Conflicting legacy values in settings.sysctlProfiles.gaming.fileMax and dev.fileMax. Set a single value in settings.sysctlProfiles.fileMax.";
    }
    {
      assertion = (dev.inotifyWatches or 1048576) >= 8192;
      message = "settings.sysctlProfiles.dev.inotifyWatches should be >= 8192";
    }
    {
      assertion = (dev.somaxconn or 4096) >= 128;
      message = "settings.sysctlProfiles.dev.somaxconn should be >= 128";
    }
  ];
}
