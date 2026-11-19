{
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).betterdiscord or { };
  enabled = cfg.enable or false;
  installDiscord = cfg.installDiscord or true;

  # Screen-share needs the Electron GPU process (NVENC lives there), so the
  # historical `--disable-gpu` workaround is gone: the SIGTRAP regression was
  # NVIDIA 610.57.04; the current driver (615.71.09) starts the GPU process
  # cleanly (verified 2026-11-14). commandLineArgs reaches the bwrap launcher
  # (desktop-entry override is no longer needed).
  discordPkg = pkgs.discord.override {
    commandLineArgs = lib.strings.optionalString (cfg.commandLineArgs or "" != "") cfg.commandLineArgs;
  };
in
lib.mkIf enabled {
  j0nix.user.software.packages =
    [ pkgs.betterdiscordctl ]
    ++ lib.optionals installDiscord [ discordPkg ];
}
