{ lib, pkgs, settings, ... }:
let
  cfg = (settings.programs or { }).betterdiscord or { };
  enabled = cfg.enable or false;
  installDiscord = cfg.installDiscord or true;

  # NVIDIA regression (610.57.04): Electron's GPU process dies with SIGTRAP
  # (SI_KERNEL) right after start — the window never maps (reproduced
  # 2026-10-01: plain Discord → processes run, zero windows; `--disable-gpu`
  # → window maps). Flag injection via package override doesn't reach the
  # bwrap launcher script, so override the desktop entry instead. Discord
  # lives in a `special:discord` workspace (SUPER+C), same as before.
  discordDesktopOverride = {
    discord = {
      name = "Discord";
      genericName = "Voice and Text Chat";
      exec = "Discord --disable-gpu %U";
      icon = "discord";
      terminal = false;
      type = "Application";
      categories = [
        "Network"
        "InstantMessaging"
      ];
      mimeType = [ "x-scheme-handler/discord" ];
    };
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages =
    [ pkgs.betterdiscordctl ]
    ++ lib.optionals installDiscord [ pkgs.discord ];

  xdg.desktopEntries = lib.mkIf installDiscord discordDesktopOverride;
}
