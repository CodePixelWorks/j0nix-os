{ config, lib, pkgs, settings, ... }:
let
  userOverrides = settings.userSettings or { };
  nvidiaEnabled = ((config.j0nix.desktop.drivers or { }).nvidia or { }).enable or false;
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
  models = ollamaCfg.models or [ ];
  extraEnv = ollamaCfg.environment or { };
  hasValue = value: value != null && value != "";
  filteredExtraEnv = lib.filterAttrs (_: value: hasValue value) extraEnv;
  serviceEnv =
    lib.filterAttrs (_: value: hasValue value) ({
      OLLAMA_HOST = host;
      OLLAMA_MODELS = modelsPath;
    } // filteredExtraEnv);
  effectiveHost = if hasValue host then host else "127.0.0.1:11434";
  effectiveModelsPath = if hasValue modelsPath then modelsPath else "/var/lib/ollama/models";
  syncModelsScript = pkgs.writeShellScriptBin "ollama-sync-models" ''
    set -eu

    export OLLAMA_HOST=${lib.escapeShellArg effectiveHost}
    export OLLAMA_MODELS=${lib.escapeShellArg effectiveModelsPath}
    export HOME=/var/lib/ollama

    for _ in $(seq 1 60); do
      if ${lib.getExe config.services.ollama.package} list >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    for model in ${lib.concatStringsSep " " (map lib.escapeShellArg models)}; do
      ${lib.getExe config.services.ollama.package} pull "$model"
    done
  '';
in
lib.mkIf enabled {
  services.ollama.enable = true;
  services.ollama.package = lib.mkIf nvidiaEnabled pkgs.ollama-cuda;

  systemd.services.ollama.serviceConfig.SupplementaryGroups = [ "users" ];
  systemd.services.ollama.serviceConfig.PermissionsStartOnly = lib.mkForce true;
  systemd.services.ollama.serviceConfig.ReadWritePaths = lib.mkIf (hasValue modelsPath) (lib.mkAfter [ modelsPath ]);

  systemd.services.ollama.preStart = lib.mkIf (hasValue modelsPath) ''
    ${lib.getExe' pkgs.coreutils "install"} -d -m 2775 -o ollama -g users ${lib.escapeShellArg modelsPath}
  '';

  systemd.services.ollama.environment =
    lib.mkIf (serviceEnv != { })
      (lib.mapAttrs (_: value: lib.mkForce value) serviceEnv);

  j0nix.software.systemPackages = lib.optional (models != [ ]) syncModelsScript;

  systemd.services.ollama-models-sync = lib.mkIf (models != [ ]) {
    description = "Pull declarative Ollama models";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" "ollama.service" ];
    after = [ "network-online.target" "ollama.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "ollama";
      Group = "ollama";
      SupplementaryGroups = [ "users" ];
      ExecStart = lib.getExe syncModelsScript;
    };
  };

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
    {
      assertion = builtins.isList models && lib.all builtins.isString models;
      message = "settings.userSettings.<name>.programs.ollama.models must be a list of model strings";
    }
  ];
}
