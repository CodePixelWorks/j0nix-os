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
  cfg = (settings.ai or { }).hermesConfig or { };
  enabled = cfg.enable or false;
  managedBlocks = cfg.managedBlocks or { };

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
  config = lib.mkIf enabled {
    home.packages = [ hermesConfigPolicy ];
    home.activation.hermesConfigPolicy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe hermesConfigPolicy}
    '';
  };
}
