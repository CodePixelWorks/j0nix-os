# hermes-policy.nix - declarative hermes config management for the
# workstation (the server's managedConfig pattern, scaled down).
#
# The server (nixos-server-base hermes.nix) renders /etc/hermes/
# config.yaml fully from structured settings. On the workstation the
# config is user-owned (wizard edits, model switches, channel config),
# so this module uses the hermes-mcp-sync pattern instead: only the
# configured managedBlocks are written into ~/.hermes/config.yaml,
# everything else stays user-owned. Idempotent (write only on change),
# mode-preserving, backup before replace.
#
# Managed blocks are defined in settings:
#   settings.ai.hermesConfig.managedBlocks = {
#     agent.max_turns = 500;
#     approvals.mode = "smart";
#     ...
#   };
{
  lib,
  pkgs,
  settings,
  ...
}:
let
  # settings layout: the AI block lives under dev (settings.dev.ai.*).
  aiSettings = ((settings.dev or { }).ai or { });
  cfg = aiSettings.hermesConfig or { };
  enabled = cfg.enable or false;
  managedBlocks = cfg.managedBlocks or { };

  # Server-framework parity for the workstation memory stack: render
  # $HERMES_HOME/mem0.json declaratively (mirrors nixos-server-base
  # hermes-mem0.nix renderMemoryBlock for the OSS mode — the mem0
  # plugin's native config file; secrets never enter store paths, the
  # OSS providers here are loopback-only ollama/qdrant). Fully managed
  # file (no user merge): a write only happens on content change.
  mem0Config = aiSettings.hermesMem0 or { };
  mem0Enabled = mem0Config.enable or false;
  mem0Json = builtins.toJSON {
    mode = "oss";
    user_id = mem0Config.userId or "jonas";
    agent_id = mem0Config.agentId or "hermes-jonas-pc";
    sync_max_chars = mem0Config.syncMaxChars or 1800;
    oss = {
      llm = {
        provider = (mem0Config.oss or { }).llm.provider or "ollama";
        config = {
          model = (mem0Config.oss or { }).llm.model or "";
          ollama_base_url = (mem0Config.oss or { }).llm.baseUrl or "http://127.0.0.1:11434";
        };
      };
      embedder = {
        provider = (mem0Config.oss or { }).embedder.provider or "ollama";
        config = {
          model = (mem0Config.oss or { }).embedder.model or "";
          ollama_base_url = (mem0Config.oss or { }).embedder.baseUrl or "http://127.0.0.1:11434";
          embedding_dims = (mem0Config.oss or { }).embedder.dims or 768;
        };
      };
      vector_store = {
        provider = "qdrant";
        config =
          if (mem0Config.oss or { }).qdrantUrl != null then
            { url = mem0Config.oss.qdrantUrl; }
          else
            { path = (mem0Config.oss or { }).qdrantPath or ""; };
      };
    };
  };

  mem0ConfigWriter = pkgs.writeShellApplication {
    name = "hermes-mem0-config";
    runtimeInputs = [
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
    ];
    text = ''
      config_file="$HOME/.hermes/mem0.json"
      mkdir -p "$(dirname "$config_file")"
      HERMES_MEM0_DESIRED=${lib.escapeShellArg mem0Json} \
        HERMES_MEM0_FILE="$config_file" \
        ${pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ])}/bin/python <<'PY'
      import json
      import os
      from pathlib import Path

      path = Path(os.environ["HERMES_MEM0_FILE"])
      desired = json.loads(os.environ["HERMES_MEM0_DESIRED"])
      try:
          current = json.loads(path.read_text(encoding="utf-8"))
      except (OSError, ValueError):
          current = None
      if current == desired:
          raise SystemExit(0)
      backup = path.with_suffix(".json.pre-policy")
      if path.exists():
          backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
      path.write_text(json.dumps(desired, indent=2) + "\n", encoding="utf-8")
      PY
    '';
  };

  hermesConfigPolicy = pkgs.writeShellApplication {
    name = "hermes-config-policy";
    runtimeInputs = [
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
    ];
    text = ''
      config_file="$HOME/.hermes/config.yaml"
      mkdir -p "$(dirname "$config_file")"

      HERMES_POLICY_CONFIG_FILE="$config_file" \
        HERMES_POLICY_BLOCKS=${lib.escapeShellArg (builtins.toJSON managedBlocks)} \
        ${pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ])}/bin/python <<'PY'
      import json
      import os
      from pathlib import Path
      import tempfile
      import yaml

      path = Path(os.environ["HERMES_POLICY_CONFIG_FILE"])
      if not path.exists():
          raise SystemExit(0)
      config = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
      mode = path.stat().st_mode & 0o777

      blocks = json.loads(os.environ["HERMES_POLICY_BLOCKS"])
      changed = False

      def deep_merge(dst, src):
          changed = False
          for key, value in src.items():
              if isinstance(value, dict) and isinstance(dst.get(key), dict):
                  if deep_merge(dst[key], value):
                      changed = True
              elif dst.get(key) != value:
                  dst[key] = value
                  changed = True
          return changed

      for name, block in blocks.items():
          target = config.setdefault(name, {})
          if deep_merge(target, block):
              changed = True

      if not changed:
          raise SystemExit(0)

      backup = path.with_suffix(".yaml.pre-policy")
      backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")

      path.parent.mkdir(parents=True, exist_ok=True)
      with tempfile.NamedTemporaryFile(
          mode="w", encoding="utf-8", dir=path.parent, delete=False
      ) as handle:
          yaml.safe_dump(config, handle, sort_keys=False, allow_unicode=True)
          temporary_path = Path(handle.name)
      temporary_path.chmod(mode)
      temporary_path.replace(path)
      PY
    '';
  };
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      # Only the activation references the script (repo rule: no direct
      # home.packages in modules — the script lives in the store via
      # the activation's derivation reference).
      home.activation.hermesConfigPolicy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.getExe hermesConfigPolicy}
      '';
    })
    (lib.mkIf mem0Enabled {
      home.activation.hermesMem0Config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.getExe mem0ConfigWriter}
      '';
    })
  ];
}
