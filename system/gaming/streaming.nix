{ config, lib, ... }:
let
  gaming = config.j0nix.desktop.gaming or { };
  gamingEnabled = gaming.enable or true;
  streaming = gaming.streaming or { };
  sunshine = streaming.sunshine or { };
  sunshineEnabled = sunshine.enable or false;
  sunshineOpenFirewall = sunshine.openFirewall or true;
  sunshineCapSysAdmin = sunshine.capSysAdmin or true;
  sunshineAutoStart = sunshine.autoStart or true;
  sunshinePerf = sunshine.performance or { };
  sunshinePerfMode = sunshinePerf.mode or "aggressive";
  sunshineCpuRealtimePriority = sunshinePerf.cpuRealtimePriority or 20;
  sunshineAddRenderGroup = sunshinePerf.addRenderGroup or true;
  sunshineAddInputGroup = sunshinePerf.addInputGroup or true;
  sunshineExtraGroups =
    lib.unique (
      lib.optionals sunshineAddRenderGroup [ "render" ]
      ++ lib.optionals sunshineAddInputGroup [ "input" ]
    );
  sunshineServicePriorityConfig =
    if sunshinePerfMode == "aggressive" then
      {
        Nice = -20;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
        CPUSchedulingPolicy = "rr";
        CPUSchedulingPriority = sunshineCpuRealtimePriority;
        LimitRTPRIO = "infinity";
        LimitRTTIME = "infinity";
      }
    else
      {
        Nice = -10;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 0;
      };
in
lib.mkIf (gamingEnabled && sunshineEnabled) {
  services.sunshine = {
    enable = true;
    openFirewall = sunshineOpenFirewall;
    capSysAdmin = sunshineCapSysAdmin;
    autoStart = sunshineAutoStart;
  };

  # Sunshine benefits from direct render-node access and reliable virtual input
  # permissions for low-latency capture and controller/keyboard injection.
  j0nix.desktop.accounts.baseExtraGroups = lib.mkAfter sunshineExtraGroups;

  # Apply a dedicated service-priority profile on top of the upstream user unit.
  # This mirrors the useful part of common Sunshine tuning gists without forcing
  # an extreme RT priority that can starve a daily-driver desktop.
  systemd.user.services.sunshine.serviceConfig = sunshineServicePriorityConfig;

  assertions = [
    {
      assertion = builtins.isBool sunshineOpenFirewall;
      message = "j0nix.desktop.gaming.streaming.sunshine.openFirewall must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineCapSysAdmin;
      message = "j0nix.desktop.gaming.streaming.sunshine.capSysAdmin must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineAutoStart;
      message = "j0nix.desktop.gaming.streaming.sunshine.autoStart must be a boolean";
    }
    {
      assertion = builtins.elem sunshinePerfMode [ "balanced" "aggressive" ];
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.mode must be one of: balanced, aggressive";
    }
    {
      assertion = sunshineCpuRealtimePriority >= 1 && sunshineCpuRealtimePriority <= 99;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.cpuRealtimePriority must be between 1 and 99";
    }
    {
      assertion = builtins.isBool sunshineAddRenderGroup;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.addRenderGroup must be a boolean";
    }
    {
      assertion = builtins.isBool sunshineAddInputGroup;
      message = "j0nix.desktop.gaming.streaming.sunshine.performance.addInputGroup must be a boolean";
    }
  ];
}
