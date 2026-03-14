{ settings, ... }:
let
  programsCfg = settings.programs or { };
  bambuCfg = programsCfg.bambulab or { };
  provider = bambuCfg.provider or "appimage";
in
{
  config = {
    j0nix.desktop.sysctl.extraFragments = [
      {
        # Bambu/related wrappers require unprivileged user namespaces.
        "kernel.unprivileged_userns_clone" = 1;
        "user.max_user_namespaces" = 1048576;
      }
    ];

    j0nix.desktop.apps.flatpak.entries = if provider == "flatpak" then [
      {
        appId = "com.bambulab.BambuStudio";
        remote = "flathub";
      }
    ] else [ ];

    assertions = [
      {
        assertion = builtins.elem provider [ "appimage" "flatpak" ];
        message = "settings.programs.bambulab.provider must be one of: appimage, flatpak";
      }
    ];
  };
}
