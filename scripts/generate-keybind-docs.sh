#!/usr/bin/env bash
# Usage: generate-keybind-docs.sh [OUTPUT_FILE]
# Generates a Markdown keybind reference by evaluating bind data via Nix.
# This script must be run from the repository root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTFILE="${1:-$REPO_ROOT/docs/KEYBINDS.md}"

cd "$REPO_ROOT"

# Evaluate structured bind data as JSON via the flake.
# We use nix eval with the flake root to access all required inputs.
nix eval --json --impure --expr '
  let
    # Import the repo flake to get lib, settings, etc.
    flake = builtins.getFlake (toString ./.);
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    lib = pkgs.lib;

    # Load keybind lib
    keybindLib = import ./user/wm/hyprland/config/keybinds/lib.nix { inherit lib; };

    # Load shell binds (raw strings)
    shellBindsRaw = import ./user/wm/hyprland/config/keybinds/shells.nix {
      launcherAppExec = x: x;
      settings = { preferredBrowser = "chromium"; preferredEditor = "nvim"; };
      preferredFileManager = "nautilus";
    };

    # Parse all bind strings into structured data
    parseAllBinds = shellData:
      let
        allBinds = lib.concatLists (lib.mapAttrsToList (shellName: bindTypes:
          lib.concatLists (lib.mapAttrsToList (bindType: lines:
            map (line:
              let parsed = keybindLib.parseBindString line;
              in parsed // {
                _shell = shellName;
                _bindType = bindType;
                _original = line;
              }
            ) lines
          ) bindTypes)
        ) shellData);
      in allBinds;

    allParsed = parseAllBinds shellBindsRaw;
    categorized = keybindLib.categorizeBinds allParsed;
  in
  categorized
' > /tmp/keybinds.json 2>/dev/null || {
  echo "Error: Failed to evaluate bind data via Nix." >&2
  echo "Ensure you're running this from the repo root with flake.nix present." >&2
  exit 1
}

# Generate Markdown from JSON
cat > "$OUTFILE" <<'HEADER'
# Keybind Reference

Auto-generated from `user/wm/hyprland/config/keybinds/`.

> [!NOTE]
> `$mainMod` = `SUPER` (Windows key). Some binds may vary by selected shell.

HEADER

# Process each category
jq -r 'keys | sort | .[]' /tmp/keybinds.json | while IFS= read -r category; do
  echo ""
  echo "## ${category}"
  echo ""
  echo "| Mods | Key | Action | Argument |"
  echo "|------|-----|--------|----------|"

  jq -r --arg cat "$category" '
    .[$cat] | sort_by(.dispatcher, .key) | .[] |
    "| \(.mods // "") | \(.key // "") | \(.dispatcher // "") | \(.arg // "" ) |"
  ' /tmp/keybinds.json | sed 's/| \$mainMod |/| `SUPER` |/g'
done

echo ""
echo "---"
echo ""
echo "Generated at $(date -Iseconds)"

echo "Keybind reference written to: $OUTFILE"
