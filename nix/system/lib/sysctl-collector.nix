{ lib }:
let
  numericStringPattern = "^-?[0-9]+(\\.[0-9]+)?$";

  isNumericString = value:
    builtins.isString value && (builtins.match numericStringPattern value) != null;

  toNumber = value:
    if builtins.isInt value || builtins.isFloat value then value
    else if isNumericString value then builtins.fromJSON value
    else null;

  preferHigher = old: new:
    let
      oldN = toNumber old;
      newN = toNumber new;
    in
    if oldN != null && newN != null then
      if newN > oldN then new else old
    else
      # For non-numeric sysctls (e.g. "4096 131072 33554432"), keep last writer behavior.
      new;

  mergeTwo = acc: attrs:
    lib.foldlAttrs
      (innerAcc: key: value:
        innerAcc
        // {
          ${key} =
            if innerAcc ? ${key}
            then preferHigher innerAcc.${key} value
            else value;
        })
      acc
      attrs;
in
{
  collect = fragments:
    lib.foldl' mergeTwo { } (lib.filter (f: f != null) fragments);
}
