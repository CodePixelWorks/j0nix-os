{ lib, settings, ... }:
let
  ollamaCfg = ((settings.programs or { }).ollama or { });
  enabled = ollamaCfg.enable or true;
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

  systemd.services.ollama.environment = lib.mkIf (serviceEnv != { }) serviceEnv;

  assertions = [
    {
      assertion = host == null || host != "";
      message = "settings.programs.ollama.host must be a non-empty string when set";
    }
    {
      assertion = modelsPath == null || modelsPath != "";
      message = "settings.programs.ollama.modelsPath must be a non-empty string when set";
    }
    {
      assertion = builtins.isAttrs extraEnv;
      message = "settings.programs.ollama.environment must be an attrset of environment variables";
    }
  ];
}
