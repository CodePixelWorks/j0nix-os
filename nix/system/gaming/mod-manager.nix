{
  lib,
  settings ? { },
  ...
}:
let
  cfg = settings.gaming.modManager or { };
  enabled = cfg.enable or false;
  provider = cfg.provider or "amethyst";
in
{
  config.j0nix.desktop.apps.flatpak.entries = lib.mkIf (enabled && provider == "amethyst") [
    {
      appId = "io.github.Amethyst.ModManager";
      remote = "amethyst";
      remoteUrl = "https://chrisdkn.github.io/Amethyst-Mod-Manager/amethyst.flatpakrepo";
      branch = "stable";
    }
  ];

  config.assertions = [
    {
      assertion = provider == "amethyst";
      message = "settings.gaming.modManager.provider must be \"amethyst\".";
    }
  ];
}
