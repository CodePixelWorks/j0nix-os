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

  mkLoginPowerWheelRule = mkWheelAllowRule {
    actions = [
      "org.freedesktop.login1.power-off"
      "org.freedesktop.login1.power-off-multiple-sessions"
      "org.freedesktop.login1.reboot"
      "org.freedesktop.login1.reboot-multiple-sessions"
      "org.freedesktop.login1.suspend"
      "org.freedesktop.login1.suspend-multiple-sessions"
      "org.freedesktop.login1.hibernate"
      "org.freedesktop.login1.hibernate-multiple-sessions"
      "org.freedesktop.login1.suspend-then-hibernate"
      "org.freedesktop.login1.suspend-then-hibernate-multiple-sessions"
      "org.freedesktop.login1.hybrid-sleep"
      "org.freedesktop.login1.hybrid-sleep-multiple-sessions"
    ];
  };
}
