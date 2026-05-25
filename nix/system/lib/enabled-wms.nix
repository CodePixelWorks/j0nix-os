{ lib }:
settings:
let
  userDefaults = lib.mapAttrsToList (_: userCfg: userCfg.defaultWMS or null) (settings.userSettings or { });
  fromUsers = builtins.filter (wm: wm != null && wm != "") userDefaults;
  fromSystem = settings.wms or [ ];
in
lib.unique (fromSystem ++ fromUsers)
