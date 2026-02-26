{ lib, settings, ... }:
let
  storage = settings.storage or { };
  enableUdisks2 = storage.enableUdisks2 or (storage.autoMountWindows or true);
  noPasswordMounts = storage.noPasswordMounts or true;
in
{
  services.gvfs.enable = true;
  services.udisks2.enable = enableUdisks2;

  security.polkit.enable = true;
  security.polkit.extraConfig = lib.mkIf noPasswordMounts ''
    polkit.addRule(function(action, subject) {
      var allowed = [
        "org.freedesktop.udisks2.filesystem-mount",
        "org.freedesktop.udisks2.filesystem-mount-system",
        "org.freedesktop.udisks2.filesystem-mount-other-seat",
        "org.freedesktop.udisks2.filesystem-unmount-others",
        "org.freedesktop.udisks2.encrypted-unlock",
        "org.freedesktop.udisks2.eject-media"
      ];

      if (allowed.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  assertions = [
    {
      assertion = builtins.isBool enableUdisks2 && builtins.isBool noPasswordMounts;
      message = "settings.storage.enableUdisks2/autoMountWindows and settings.storage.noPasswordMounts must be booleans";
    }
  ];
}
