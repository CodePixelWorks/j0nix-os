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

    j0nix.desktop.sysctl.extraFragments = [
      {
        # Bambu/related wrappers can require unprivileged user namespaces.
        "kernel.unprivileged_userns_clone" = 1;
        "user.max_user_namespaces" = 1048576;
      }
    ];

    assertions = [
      {
        assertion = builtins.elem provider [ "appimage" "flatpak" ];
        message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
      }
    ];
  };
}
