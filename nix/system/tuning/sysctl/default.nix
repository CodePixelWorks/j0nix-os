{
  config,
  lib,
  settings,
  ...
}:
let
  sysctlCollector = import ../../lib/sysctl-collector.nix { inherit lib; };

  collectedSysctl = sysctlCollector.collect (
    [
      ((settings.custom or { }).sysctl or { })
    ]
    ++ config.j0nix.desktop.sysctl.extraFragments
  );
in
{
  options.j0nix.desktop.sysctl.extraFragments = lib.mkOption {
    type = lib.types.listOf (
      lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.int
          lib.types.str
        ]
      )
    );
    default = [ ];
    description = ''
      Additional sysctl fragments to merge. Duplicate keys are deduplicated by taking
      the higher numeric value when both values are numeric; otherwise last-writer wins.
    '';
  };

  config.boot.kernel.sysctl = collectedSysctl;
}
