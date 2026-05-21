{ lib }:
let
  inherit (lib) mkOption types;

  # ------------------------------------------------------------------------
  # Sub-module shape for a single output.  Reuse in option declarations.
  # ------------------------------------------------------------------------
  monitorSubmodule = { name, ... }: {
    options = {
      output = mkOption {
        type = types.str;
        description = "Connector name, e.g. DP-1, HDMI-A-2.";
      };
      mode = mkOption {
        type = types.str;
        default = "preferred";
        description = "Resolution@refresh or 'preferred'.";
      };
      position = mkOption {
        type = types.str;
        default = "auto";
        description = "Position like '0x0' or 'auto'.";
      };
      scale = mkOption {
        type = types.either types.float types.int;
        default = 1.0;
        description = "Output scale factor.";
      };
      disabled = mkOption {
        type = types.bool;
        default = false;
        description = "Start with this output disabled.";
      };
      description = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      bindIndex = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Workspace number used for the toggle keybind (1..10).";
      };
      focusOnEnable = mkOption {
        type = types.bool;
        default = false;
      };
      enabledByDefault = mkOption {
        type = types.bool;
        default = true;
      };
      workspaceHandoff = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            enable = mkOption { type = types.bool; default = true; };
            targetMonitor = mkOption { type = types.str; };
          };
        });
        default = null;
      };
    };
  };

in
rec
{
  inherit monitorSubmodule;

  # ------------------------------------------------------------------------
  # Render helpers
  # ------------------------------------------------------------------------

  /* Render a monitor attrset to the legacy "name,mode,position,scale" rule
     string (or "name,disable" when disabled). */
  renderMonitorRule = monitor:
    if monitor.disabled or false then
      "${monitor.output},disable"
    else
      "${monitor.output},${monitor.mode},${monitor.position},${toString monitor.scale}";

  /* Render a monitor attrset to Hyprland Lua hl.monitor({ ... }) syntax. */
  renderMonitorLua = monitor:
    let
      output = monitor.output or "";
      mode = monitor.mode or "preferred";
      position = monitor.position or "auto";
      scale = toString (monitor.scale or 1.0);
    in
    if monitor.disabled or false then
      ''hl.monitor({ output = ${builtins.toJSON output}, disabled = true })''
    else
      ''hl.monitor({ output = ${builtins.toJSON output}, disabled = false, mode = ${builtins.toJSON mode}, position = ${builtins.toJSON position}, scale = ${builtins.toJSON scale} })'';

  /* Parse a legacy comma-separated monitor rule into a typed attrset.
     Returns null for unparseable lines. */
  parseMonitorRule = line:
    let
      parts = map lib.trim (lib.splitString "," line);
      len = builtins.length parts;
      output = builtins.elemAt parts 0;
    in
    if len == 0 then
      null
    else if output == "" then
      { output = ""; mode = "preferred"; position = "auto"; scale = "1"; }
    else if len == 2 && builtins.elemAt parts 1 == "disable" then
      { inherit output; disabled = true; }
    else if len >= 4 then
      {
        inherit output;
        mode = builtins.elemAt parts 1;
        position = builtins.elemAt parts 2;
        scale = builtins.elemAt parts 3;
      }
    else
      null;

  /* Accept either a legacy string or an attrset and return a normalized
     attrset. */
  normalizeMonitor = m:
    if builtins.isString m then parseMonitorRule m else m;

  # Type shorthand for option declarations.
  monitorList = types.listOf (types.submodule monitorSubmodule);
}
