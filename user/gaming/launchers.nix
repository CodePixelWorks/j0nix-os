{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
let
  gaming = config.j0nix.desktop.gaming or { };
  enabled = gaming.enable or true;
  launchers = gaming.launchers or { };
  protonCfg = gaming.proton or { };
  minecraftCfg = (settings.programs or { }).minecraft or { };
  minecraftDataDir = minecraftCfg.dataDir or null;
  bottlesPkg = pkgs.bottles-j0nix or pkgs.bottles;
  rockstarEnabled = launchers.rockstar or false;
  gdlauncherEnabled = launchers.gdlauncher or false;
  teamspeak6Enabled = launchers.teamspeak6 or false;
  gdlauncherPkg =
    if pkgs ? "gdlauncher-carbon" then
      pkgs."gdlauncher-carbon"
    else
      null;
  teamspeak6Pkg =
    if pkgs ? "teamspeak6-client" then
      pkgs."teamspeak6-client"
    else
      null;
  heroicPkg =
    if pkgs ? heroic then
      pkgs.heroic
    else if pkgs ? heroic-games-launcher then
      pkgs.heroic-games-launcher
    else
      null;
in
lib.mkIf enabled {
  programs.lutris = lib.mkIf (launchers.lutris or true) {
    enable = true;
    protonPackages = lib.optionals (protonCfg.ge or true) [ pkgs.proton-ge-bin ];
    extraPackages = with pkgs; [
      mangohud
      winetricks
      gamescope
      gamemode
      umu-launcher
    ];
  };

  j0nix.user.software.packages =
    lib.optionals ((launchers.heroic or true) && heroicPkg != null) [ heroicPkg ]
    ++ lib.optionals (launchers.bottles or true) [ bottlesPkg ]
    ++ lib.optionals (launchers.wineGui or false) [ pkgs.wineWow64Packages.waylandFull ]
    ++ lib.optionals (rockstarEnabled && (pkgs ? protontricks)) [ pkgs.protontricks ]
    ++ lib.optionals (gdlauncherEnabled && gdlauncherPkg != null) [ gdlauncherPkg ]
    ++ lib.optionals (teamspeak6Enabled && teamspeak6Pkg != null) [ teamspeak6Pkg ];

  home.file = lib.mkIf (minecraftDataDir != null) {
    ".minecraft".source = config.lib.file.mkOutOfStoreSymlink minecraftDataDir;
  };

  home.activation.minecraftDataDirPrepare = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.optionalString (minecraftDataDir != null) ''
      if [ ! -d "${minecraftDataDir}" ]; then
        mkdir -p "${minecraftDataDir}"
      fi
    ''
  );

  assertions = [
    {
      assertion = minecraftDataDir == null || (builtins.isString minecraftDataDir && minecraftDataDir != "");
      message = "settings.userSettings.<name>.programs.minecraft.dataDir must be a non-empty string path when set.";
    }
  ];
}
