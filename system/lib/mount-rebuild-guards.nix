{ lib, utils }:
mounts:
let
  normalizedMounts = lib.filter (m:
    (m.enable or true)
    && (m.preventRemount or false)
    && (m ? mountPoint)
    && m.mountPoint != ""
  ) mounts;

  mountUnitName = mountPoint: "${utils.escapeSystemdPath (lib.removeSuffix "/" mountPoint)}.mount";
  automountUnitName = mountPoint: "${utils.escapeSystemdPath (lib.removeSuffix "/" mountPoint)}.automount";

  mkNoRemountUnit = unitName: {
    name = unitName;
    value = {
      stopIfChanged = false;
      restartIfChanged = false;
    };
  };
in
builtins.listToAttrs (
  lib.concatMap
    (m:
      [ (mkNoRemountUnit (mountUnitName m.mountPoint)) ]
      ++ lib.optionals (m.automount or false) [
        (mkNoRemountUnit (automountUnitName m.mountPoint))
      ])
    normalizedMounts
)
