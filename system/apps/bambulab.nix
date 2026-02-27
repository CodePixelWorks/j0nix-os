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
        assertion = builtins.elem provider [ "appimage" "flatpak" ];
        message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
      }
    ];
  };
}
