{ config, lib, options, pkgs, settings, ... }:
let
  cfg = config.j0nix.software;
  custom = settings.custom or { };
  repoRoot = lib.removeSuffix "/system/software" (toString ./.);
  softwareDefinitions =
    lib.filter
      (def:
        let
          file = toString (def.file or "");
        in
          file != "" && lib.hasPrefix "${repoRoot}/" file)
      (options.j0nix.software.systemPackages.definitionsWithLocations or [ ]);
  profileSoftwareDefinitions =
    lib.filter
      (def:
        let
          file = toString (def.file or "");
        in
          lib.hasInfix "/profiles/" file)
      softwareDefinitions;
  profileSoftwareFiles =
    lib.unique (map (def: toString (def.file or "<unknown>")) profileSoftwareDefinitions);
in
{
  imports = [
    ./base.nix
  ];

  options.j0nix.software.systemPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = "Aggregated system package requirements collected from modules/roles.";
  };

  config = {
    j0nix.software.systemPackages = with pkgs; [
      age
      sops
    ] ++ (custom.systemPackages or [ ]);

    environment.systemPackages = lib.mkAfter (lib.unique cfg.systemPackages);
    assertions = [
      {
        assertion = profileSoftwareDefinitions == [ ];
        message = ''
          Do not declare j0nix.software.systemPackages in profile modules.
          Put package selections in system/software/* or feature modules instead.
          Offending profile file(s): ${lib.concatStringsSep ", " profileSoftwareFiles}
        '';
      }
    ];
  };
}
