#!/usr/bin/env bash
# Usage: generate-keybind-docs.sh [OUTPUT_FILE]
# Generates a Markdown keybind reference by evaluating bind data via Nix.
# Must be run from the repository root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTFILE="${1:-$REPO_ROOT/docs/KEYBINDS.md}"

cd "$REPO_ROOT"

# Ensure jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Evaluate structured bind data as JSON via separate Nix file
# ---------------------------------------------------------------------------
nix eval --json --impure --expr 'import ./scripts/generate-keybind-data.nix' \
  > /tmp/keybinds.json 2>/tmp/keybind-eval.err || {
  echo "Error: Failed to evaluate bind data via Nix." >&2
  if [ -s /tmp/keybind-eval.err ]; then
    echo "--- Nix stderr ---" >&2
    cat /tmp/keybind-eval.err >&2
  fi
  exit 1
}

# ---------------------------------------------------------------------------
# Generate Markdown from JSON — all output appended to OUTFILE
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTFILE")"

{
  cat <<'HEADER'
# Keybind Reference

Auto-generated from `user/wm/hyprland/config/keybinds/`.

> [!NOTE]
> `$mainMod` = `SUPER` (Windows key). Some binds may vary by selected shell.

HEADER

  # Category ordering
  CATEGORIES="
Navigation
Window Management
Resizing
Layout
Window State
Session
Screenshot
Media
Launcher
App Launch
Shell
Other
"

  for category in $CATEGORIES; do
    # Skip if category not present in JSON
    count=$(jq --arg cat "$category" '.[$cat] | length' /tmp/keybinds.json)
    if [ "$count" -eq 0 ]; then
      continue
    fi

    echo ""
    echo "## ${category}"
    echo ""
    echo "| Mods | Key | Dispatcher | Argument | Type |"
    echo "|------|-----|------------|----------|------|"

    jq -r --arg cat "$category" '
      .[$cat] | sort_by(.dispatcher // "", .key // "") | .[] |
      "| \(.mods // "" ) | \(.key // "" | gsub("XF86"; "")) | \(.dispatcher // "") | \(.arg // "" ) | \(._type // "bind") |"
    ' /tmp/keybinds.json | sed -e 's/\$mainMod/`SUPER`/g' -e 's/|  |/|  |/g'
  done

  echo ""
  echo "---"
  echo ""
  echo "Generated at $(date -Iseconds)"

} > "$OUTFILE"

echo ""
echo "Keybind reference written to: $OUTFILE"