{ settings, ... }:
{
  imports = [
    ./launchers.nix
    ./tools.nix
    ./extras.nix
  ];

  config.xdg.configFile."j0nix/game-mods.json" = {
    text = builtins.toJSON (settings.gaming.mods or { enable = false; targets = { }; });
  };
}
