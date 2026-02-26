{ lib }:
let
  mkWheelAllowRule = { actions }:
    ''
      polkit.addRule(function(action, subject) {
        var allowed = [
          ${lib.concatMapStringsSep "\n" (a: ''"${a}",'') actions}
        ];

        if (allowed.indexOf(action.id) >= 0 && subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';
in
{
  mkUdisksWheelMountRule = mkWheelAllowRule {
    actions = [
      "org.freedesktop.udisks2.filesystem-mount"
      "org.freedesktop.udisks2.filesystem-mount-system"
      "org.freedesktop.udisks2.filesystem-mount-other-seat"
      "org.freedesktop.udisks2.filesystem-unmount-others"
      "org.freedesktop.udisks2.encrypted-unlock"
      "org.freedesktop.udisks2.eject-media"
    ];
  };
}
