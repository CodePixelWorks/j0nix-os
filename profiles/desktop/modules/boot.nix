{ lib, pkgs, settings, ... }:
let
  bootCfg = settings.boot or { };
  splashCfg = bootCfg.splash or { };
  splashEnabled = splashCfg.enable or false;
  hasAdiPlymouthThemes = pkgs ? adi1090x-plymouth-themes;
in
{
  j0nix.desktop.boot = {
    tmp = {
      useTmpfs = false;
      tmpfsSize = "30%";
    };

    loader = {
      systemdBoot = {
        enable = true;
        configurationLimit = 3;
      };
      efi.canTouchEfiVariables = true;
    };

    # Hibernate via swapfile on / (ext4). resumeOffset is derived from
    # `filefrag -v /swapfile` and must be updated if the swapfile is recreated.
    #
    # VERIFY: sudo filefrag -v /swapfile | grep -E "^\s*0:" | awk '{print $4}'
    # If the output differs from the value below, update it before hibernate will work.
    resumeDevice = "/dev/disk/by-uuid/28c5e755-f2df-4f57-af8a-36998a4a2f25";
    resumeOffset = 63145984;

    swapfile = {
      enable = true;
      path = "/swapfile";
      sizeMiB = 68 * 1024;
    };

    splash = {
      enable = splashEnabled;
      theme = splashCfg.theme or (if hasAdiPlymouthThemes then "cuts" else "bgrt");
      themePackages =
        lib.optionals (splashEnabled && hasAdiPlymouthThemes) [ pkgs.adi1090x-plymouth-themes ];
      quietBoot = splashCfg.quietBoot or true;
      highResolution = splashCfg.highResolution or true;
    };
  };
}
