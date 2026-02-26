{ lib }:
let
  renderValue = v:
    if builtins.isBool v then
      (if v then "1" else "0")
    else if builtins.isInt v then
      builtins.toString v
    else if builtins.isFloat v then
      builtins.toString v
    else
      toString v;

  renderModuleOptions = moduleName: opts:
    let
      renderedOpts = lib.mapAttrsToList (k: v: "${k}=${renderValue v}") opts;
    in
    "options ${moduleName} ${lib.concatStringsSep " " renderedOpts}";
in
{
  fromAttrset = moduleOptions:
    lib.concatStringsSep "\n"
      (lib.mapAttrsToList renderModuleOptions moduleOptions)
    + "\n";
}
