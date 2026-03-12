{ config, inputs, pkgs, lib, settings, ... }:
let
  mkExt = set: path: lib.attrByPath path null set;
  pick = ext: lib.optional (ext != null) ext;

  marketplace = pkgs.nix-vscode-extensions.vscode-marketplace or {};

  vscodeCfg = settings.vscode or { };
  themeCfg = vscodeCfg.theme or { };
  extensionCfg = vscodeCfg.extensions or { };
  codex = import ../../../system/dev/codex.nix { inherit inputs lib pkgs settings; };
  openVSXIds = extensionCfg.openVSX or [ ];
  marketplaceIds = extensionCfg.marketplace or [ ];
  colorTheme = themeCfg.colorTheme or null;
  hasValue = value: value != null && value != "";
  seededUserSettings = {
    "editor.fontLigatures" = true;
    "editor.formatOnSave" = true;
    "files.autoSave" = "onFocusChange";
    "editor.codeActionsOnSave" = {
      "source.fixAll" = "explicit";
      "source.organizeImports" = "explicit";
    };
    "terminal.integrated.defaultProfile.linux" = "zsh";
    "docker.languageserver.formatter.ignoreMultilineInstructions" = true;
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nixd";
    "rust-analyzer.check.command" = "clippy";
    "python.analysis.typeCheckingMode" = "basic";
    "yaml.format.enable" = true;
  } // lib.optionalAttrs (hasValue colorTheme) {
    "workbench.colorTheme" = colorTheme;
  };

  mkExtFromId = set: extId:
    let
      parts = lib.splitString "." extId;
    in
      if builtins.length parts < 2 then
        null
      else
        mkExt set [
          (builtins.elemAt parts 0)
          (lib.concatStringsSep "." (lib.drop 1 parts))
        ];

  resolveExts = set: ids: lib.concatMap (id: pick (mkExtFromId set id)) ids;
in {
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions =
        resolveExts pkgs.vscode-extensions openVSXIds
        ++ resolveExts marketplace marketplaceIds
        ++ lib.optionals (codex.enabled && codex.vscodeEnable && codex.vscodeExtension != null) [ codex.vscodeExtension ];
    };
  };

  # Seed VSCode settings once so the file stays writable in the UI.
  home.activation.vscodeSeedUserSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    seeded_settings_json='${lib.escapeShellArg (builtins.toJSON seededUserSettings)}'
    for settings_file in \
      "$HOME/.config/Code/User/settings.json" \
      "$HOME/.config/VSCodium/User/settings.json" \
      "$HOME/.config/code-server/User/settings.json"
    do
      if [ -L "$settings_file" ]; then
        $DRY_RUN_CMD rm -f "$settings_file"
      fi

      if [ ! -e "$settings_file" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$settings_file")"
        $DRY_RUN_CMD cat >"$settings_file" <<'EOF'
${builtins.toJSON seededUserSettings}
EOF
        $DRY_RUN_CMD chmod 644 "$settings_file"
      elif [ -n "$seeded_settings_json" ]; then
        SETTINGS_FILE="$settings_file" SEEDED_SETTINGS_JSON="$seeded_settings_json" \
          $DRY_RUN_CMD ${pkgs.python3}/bin/python <<'PY'
import json
import os
import pathlib
import re
import sys

path = pathlib.Path(os.environ["SETTINGS_FILE"])
seeded = json.loads(os.environ["SEEDED_SETTINGS_JSON"])
raw = path.read_text(encoding="utf-8-sig")

def strip_jsonc(text: str) -> str:
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_string = False
            i += 1
            continue
        if ch == "\"":
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < len(text) and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

try:
    current = json.loads(strip_jsonc(raw)) if raw.strip() else {}
except json.JSONDecodeError as exc:
    print(f"warning: skipping VSCode settings merge for {path}: {exc}", file=sys.stderr)
    raise SystemExit(0)
changed = False
for key, value in seeded.items():
    if key not in current:
        current[key] = value
        changed = True

if changed:
    path.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")
PY
      fi
    done
  '';

  assertions = [
    {
      assertion = (!codex.enabled) || (!codex.vscodeEnable) || codex.vscodeExtension != null;
      message = "Codex VSCode integration is enabled, but the OpenAI VSCode extension is unavailable in nix-vscode-extensions.";
    }
  ];
}
