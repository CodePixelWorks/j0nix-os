{ lib, pkgs, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  ollamaUsers = lib.filter
    (username:
      let cfg = (((userOverrides.${username} or { }).programs or { }).ollama or { });
      in cfg.enable or false)
    (builtins.attrNames userOverrides);
  enabled = ollamaUsers != [ ];
  serviceUser = if enabled then builtins.head ollamaUsers else null;
  ollamaCfg = if enabled then (((userOverrides.${serviceUser} or { }).programs or { }).ollama or { }) else { };
  host = ollamaCfg.host or null;
  modelsPath = ollamaCfg.modelsPath or null;
  extraEnv = ollamaCfg.environment or { };
  hasValue = value: value != null && value != "";
  filteredExtraEnv = lib.filterAttrs (_: value: hasValue value) extraEnv;
  serviceEnv =
    lib.filterAttrs (_: value: hasValue value) ({
      OLLAMA_HOST = host;
      OLLAMA_MODELS = modelsPath;
    } // filteredExtraEnv);
in
lib.mkIf enabled {
  services.ollama.enable = true;

  systemd.services.ollama.serviceConfig.SupplementaryGroups = [ "users" ];
  systemd.services.ollama.serviceConfig.PermissionsStartOnly = lib.mkForce true;

  systemd.services.ollama.preStart = lib.mkIf (hasValue modelsPath) ''
    ${lib.getExe' pkgs.coreutils "install"} -d -m 2775 -o ollama -g users ${lib.escapeShellArg modelsPath}
  '';

  systemd.services.ollama.environment =
    lib.mkIf (serviceEnv != { })
      (lib.mapAttrs (_: value: lib.mkForce value) serviceEnv);

  assertions = [
    {
      assertion = builtins.length ollamaUsers <= 1;
      message = "At most one user may enable userSettings.<name>.programs.ollama for the shared system Ollama service.";
    }
    {
      assertion = host == null || host != "";
      message = "settings.userSettings.<name>.programs.ollama.host must be a non-empty string when set";
    }
    {
      assertion = modelsPath == null || modelsPath != "";
      message = "settings.userSettings.<name>.programs.ollama.modelsPath must be a non-empty string when set";
    }
    {
      assertion = builtins.isAttrs extraEnv;
      message = "settings.userSettings.<name>.programs.ollama.environment must be an attrset of environment variables";
    }
  ];
}
