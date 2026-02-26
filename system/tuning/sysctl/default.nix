{ config, lib, settings, ... }:
let
  profiles = settings.sysctlProfiles or { };
  gaming = profiles.gaming or { };
  dev = profiles.dev or { };
  network = profiles.network or { };
  gamingEnabled = gaming.enable or true;
  devEnabled = dev.enable or true;
  networkEnabled = network.enable or true;

  gamingSysctl = import ./gaming.nix { inherit settings; };
  devSysctl = import ./dev.nix { inherit settings; };
  networkSysctl = import ./network.nix { inherit lib settings; };
  sysctlCollector = import ../../lib/sysctl-collector.nix { inherit lib; };

  resolvedFileMax =
    profiles.fileMax
    or (gaming.fileMax or (dev.fileMax or 2097152));

  collectedSysctl = sysctlCollector.collect (
    [
      (lib.mkIf gamingEnabled gamingSysctl)
      (lib.mkIf devEnabled devSysctl)
      (lib.mkIf networkEnabled networkSysctl)
      # Unified definition avoids duplicate fs.file-max when multiple profiles are enabled.
      { "fs.file-max" = resolvedFileMax; }
      (profiles.custom or { })
    ]
    ++ config.j0nix.desktop.sysctl.extraFragments
  );
in {
  options.j0nix.desktop.sysctl.extraFragments = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf (lib.types.oneOf [
      lib.types.int
      lib.types.float
      lib.types.str
    ]));
    default = [ ];
    description = ''
      Additional sysctl fragments to merge. Duplicate keys are deduplicated by taking
      the higher numeric value when both values are numeric; otherwise last-writer wins.
    '';
  };

  config = {
    boot.kernel.sysctl = collectedSysctl;

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
        assertion = (dev.inotifyWatches or 1048576) >= 8192;
        message = "settings.sysctlProfiles.dev.inotifyWatches should be >= 8192";
      }
      {
        assertion = (dev.somaxconn or 4096) >= 128;
        message = "settings.sysctlProfiles.dev.somaxconn should be >= 128";
      }
      {
        assertion = builtins.elem (network.defaultQdisc or "fq") [ "fq" "fq_codel" "cake" ];
        message = "settings.sysctlProfiles.network.defaultQdisc must be one of: fq, fq_codel, cake";
      }
      {
        assertion = builtins.elem (network.tcpCongestionControl or "bbr") [ "bbr" "cubic" "reno" ];
        message = "settings.sysctlProfiles.network.tcpCongestionControl must be one of: bbr, cubic, reno";
      }
      {
        assertion = (network.rmemMax or 67108864) >= 212992 && (network.wmemMax or 67108864) >= 212992;
        message = "settings.sysctlProfiles.network.rmemMax and wmemMax must be >= 212992";
      }
    ];
  };
}
