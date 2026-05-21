{ lib, settings, inputs, ... }:
let
  cfg = (settings.programs or { }).aagl or { };
  enabled = cfg.enable or false;
  launchers = cfg.launchers or { };
in
{
  imports = lib.optional enabled inputs.aagl.nixosModules.default;

  config = lib.optionalAttrs enabled {
    j0nix.desktop.nix = {
      substituters = lib.mkAfter (inputs.aagl.nixConfig.substituters or [ ]);
      trustedPublicKeys = lib.mkAfter (inputs.aagl.nixConfig."trusted-public-keys" or [ ]);
    };

    programs.anime-game-launcher.enable = launchers.animeGame or true;
    programs.anime-games-launcher.enable = launchers.animeGames or true;
    programs.honkers-launcher.enable = launchers.honkers or true;
    programs.honkers-railway-launcher.enable = launchers.honkersRailway or true;
    programs.sleepy-launcher.enable = launchers.sleepy or true;
    programs.wavey-launcher.enable = launchers.wavey or true;
  };
}
