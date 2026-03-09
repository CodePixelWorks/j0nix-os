{ lib, pkgs, useUWSM, appExecBackend ? "auto" }:
let
  app2unitExe = lib.getExe pkgs.app2unit;
  uwsmExe = lib.getExe pkgs.uwsm;
  effectiveBackend =
    if !useUWSM then "app2unit"
    else if appExecBackend == "auto" then "app2unit"
    else appExecBackend;
  prefix =
    if effectiveBackend == "uwsm" then "${uwsmExe} app -- "
    else "${app2unitExe} -- ";
in
{
  inherit app2unitExe uwsmExe effectiveBackend;
  autoFallbackToUwsm = appExecBackend == "auto" && useUWSM;
  mkExec = cmd: "${prefix}${cmd}";
}
