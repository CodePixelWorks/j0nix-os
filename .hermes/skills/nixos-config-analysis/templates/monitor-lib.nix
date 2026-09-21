{ lib }:
let
  inherit (lib) mkOption types;

  monitorSubmodule = { name, ... }: {
    options = {
      output   = mkOption { type = types.str; description = "Connector name, e.g. DP-1"; };
      mode     = mkOption { type = types.str; default = "preferred"; };
      position = mkOption { type = types.str; default = "auto"; };
      scale    = mkOption { type = types.either types.float types.int; default = 1.0; };
      disabled = mkOption { type = types.bool; default = false; };
    };
  };

  renderMonitorRule = monitor:
    if monitor.disabled or false then
      "${monitor.output},disable"
    else
      "${monitor.output},${monitor.mode},${monitor.position},${toString monitor.scale}";

  renderMonitorLua = monitor:
    let
      output   = monitor.output or "";
      mode     = monitor.mode or "preferred";
      position = monitor.position or "auto";
      scale    = toString (monitor.scale or 1.0);
    in
    if monitor.disabled or false then
      ''hl.monitor({ output = ${builtins.toJSON output}, disabled = true })''
    else
      ''hl.monitor({ output = ${builtins.toJSON output}, disabled = false, mode = ${builtins.toJSON mode}, position = ${builtins.toJSON position}, scale = ${builtins.toJSON scale} })'';

  parseMonitorRule = line:
    let
      parts  = map lib.trim (lib.splitString "," line);
      len    = builtins.length parts;
      output = builtins.elemAt parts 0;
    in
    if len == 0 then null
    else if output == "" then { output = ""; mode = "preferred"; position = "auto"; scale = "1"; }
    else if len == 2 && builtins.elemAt parts 1 == "disable" then { inherit output; disabled = true; }
    else if len >= 4 then { inherit output; mode = builtins.elemAt parts 1; position = builtins.elemAt parts 2; scale = builtins.elemAt parts 3; }
    else null;

  normalizeMonitor = m:
    if builtins.isString m then parseMonitorRule m else m;

  renderResolution = res:
    if builtins.isString res then res
    else "${toString res.width}x${toString res.height}";

  parseResolution = str:
    let match = builtins.match "^([0-9]+)x([0-9]+)$" str;
    in if match == null then null
       else { width = lib.toInt (builtins.elemAt match 0); height = lib.toInt (builtins.elemAt match 1); };

  normalizeResolution = res:
    if builtins.isString res then parseResolution res else res;

in
{
  inherit monitorSubmodule;
  inherit renderMonitorRule renderMonitorLua parseMonitorRule normalizeMonitor;
  inherit renderResolution parseResolution normalizeResolution;

  monitorList    = types.listOf (types.submodule monitorSubmodule);
  resolutionList = types.listOf (types.either types.str (types.submodule {
    options = {
      width  = mkOption { type = types.int; };
      height = mkOption { type = types.int; };
    };
  }));
}
