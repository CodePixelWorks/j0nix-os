{
  inputs,
  lib,
  pkgs,
  settings,
  ...
}:
let
  cfg = (settings.programs or { }).openDesign or { };
  enabled = cfg.enable or false;
  system = pkgs.stdenv.hostPlatform.system;
  upstreamPackages = inputs.open-design.packages.${system} or { };
  openDesignPackage = upstreamPackages.default or null;
  openDesignCli =
    if openDesignPackage == null then
      null
    else
      pkgs.writeShellScriptBin "od" ''
        export OD_DATA_DIR="''${OD_DATA_DIR:-$HOME/.od}"
        exec ${lib.getExe openDesignPackage} --no-open "$@"
      '';
in
lib.mkIf enabled {
  assertions = [
    {
      assertion = openDesignPackage != null;
      message = "inputs.open-design does not provide a default package for ${system}.";
    }
  ];

  j0nix.user.software.packages = [ openDesignCli ];
}
