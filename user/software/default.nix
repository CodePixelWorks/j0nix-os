{ config, lib, options, ... }:
let
  cfg = config.j0nix.user.software;
  repoRoot = lib.removeSuffix "/user/software" (toString ./.);
  localModuleDefinitions =
    lib.filter
      (def:
        let
          file = toString (def.file or "");
        in
          file != "" && lib.hasPrefix "${repoRoot}/" file)
      (options.home.packages.definitionsWithLocations or [ ]);
  disallowedHomePackagesDefinitions =
    lib.filter
      (def:
        let
          file = toString (def.file or "");
        in
          !(lib.hasSuffix "/user/software/default.nix" file))
      localModuleDefinitions;
  disallowedHomePackagesFiles =
    lib.unique (map (def: toString (def.file or "<unknown>")) disallowedHomePackagesDefinitions);
in
{
  imports = [
    ./desktop-base.nix
  ];

  options.j0nix.user.software.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Aggregated Home Manager package requirements collected from modules/roles.";
  };

  config = {
    home.packages = lib.mkAfter (lib.unique cfg.packages);
    assertions = [
      {
        assertion = disallowedHomePackagesDefinitions == [ ];
        message = ''
          Do not define home.packages directly in repository modules.
          Use j0nix.user.software.packages instead.
          Offending module file(s): ${lib.concatStringsSep ", " disallowedHomePackagesFiles}
        '';
      }
    ];
  };
}
