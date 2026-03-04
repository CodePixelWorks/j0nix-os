{ lib, settings, ... }:
let
  programsCfg = settings.programs or { };
  ollamaCfg = programsCfg.ollama or { };
in
{
  home.sessionVariables =
    {
      EDITOR = settings.preferredEditor;
      BROWSER = settings.preferredBrowser;
    }
    // lib.optionalAttrs ((ollamaCfg ? modelsPath) && ollamaCfg.modelsPath != null) {
      OLLAMA_MODELS = ollamaCfg.modelsPath;
    }
    // lib.optionalAttrs ((ollamaCfg ? host) && ollamaCfg.host != null) {
      OLLAMA_HOST = ollamaCfg.host;
    };
}
