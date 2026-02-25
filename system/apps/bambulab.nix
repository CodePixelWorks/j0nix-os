{ settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
in
{
  config = {
    # Keep Flatpak available system-wide, but Bambu itself is handled via the AppImage provider.
    services.flatpak.enable = true;

    assertions = [
      {
        assertion = provider == "appimage";
        message = "settings.programs.bambulab.provider is now appimage-only and must be set to \"appimage\"";
      }
    ];
  };
}
