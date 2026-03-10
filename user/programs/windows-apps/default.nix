{ config, lib, pkgs, settings, ... }:
let
  programsCfg = settings.programs or { };
  cfg = programsCfg.windowsApps or { };
  legacyFusionCfg = programsCfg.fusion360 or { };
  legacyFusionProtonCfg = legacyFusionCfg.protonInstaller or { };
  legacyFusionEnabled =
    (legacyFusionCfg.enable or false)
    || (legacyFusionProtonCfg.enable or false)
    || (legacyFusionCfg != { });

  requestedPackages =
    lib.unique (
      (cfg.packages or [ ])
      ++ lib.optionals legacyFusionEnabled [ "fusion360-proton" ]
    );
  autoSetupOnLogin = cfg.autoSetupOnLogin or true;

  definitionPath = name: ./packages + "/${name}.nix";
  knownPackages = lib.filter (name: builtins.pathExists (definitionPath name)) requestedPackages;
  missingPackages = lib.filter (name: !(builtins.pathExists (definitionPath name))) requestedPackages;
  packageDefs = map (name: import (definitionPath name) { inherit config lib pkgs settings; }) knownPackages;

  aggregatedPackages = lib.unique (lib.concatMap (def: def.packages or [ ]) packageDefs);
  aggregatedDesktopEntries = lib.mkMerge (map (def: def.desktopEntries or { }) packageDefs);
  aggregatedMimeDefaults = lib.mkMerge (map (def: def.mimeDefaults or { }) packageDefs);
  autoSetupDefs = builtins.filter (def: ((def.autoSetup or { }).enable or false)) packageDefs;

  serviceNameOf = def: "windows-app-setup-${def.id}";

  autoSetupUnits =
    builtins.listToAttrs
      (map
        (def:
          {
            name = serviceNameOf def;
            value = {
              Unit = {
                Description = (def.autoSetup.description or "Setup Windows app ${def.id}");
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = def.autoSetup.command;
              };
              Install = lib.optionalAttrs autoSetupOnLogin {
                WantedBy = [ "graphical-session.target" ];
              };
            };
          })
        autoSetupDefs);

  autoSetupServiceNames = map serviceNameOf autoSetupDefs;
in
lib.mkIf (requestedPackages != [ ]) {
  j0nix.user.software.packages = aggregatedPackages;

  xdg.desktopEntries = aggregatedDesktopEntries;
  xdg.mimeApps.defaultApplications = aggregatedMimeDefaults;

  systemd.user.services = autoSetupUnits;

  home.activation.restartWindowsAppSetups =
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      if autoSetupServiceNames == [ ] then
        ":"
      else
        ''
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
          if [ -S "$runtime_dir/bus" ]; then
            ${pkgs.systemd}/bin/systemctl --user daemon-reload
            ${lib.concatStringsSep "\n" (map (svc: ''
              ${pkgs.systemd}/bin/systemctl --user restart ${lib.escapeShellArg svc} || true
            '') autoSetupServiceNames)}
          else
            echo "warning: user session bus not available; skipping immediate Windows app setup restart during activation" >&2
          fi
        ''
    );

  assertions = [
    {
      assertion = lib.all builtins.isString requestedPackages;
      message = "settings.programs.windowsApps.packages must be a list of package names.";
    }
    {
      assertion = missingPackages == [ ];
      message = "Unknown Windows app package(s): ${lib.concatStringsSep ", " missingPackages}. Expected definitions under user/programs/windows-apps/packages/<name>.nix";
    }
  ];
}
