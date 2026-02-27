#!/usr/bin/env bash
set -euo pipefail

# Update flake inputs used by Hyprland shell layers.
default_inputs=(
  ags
  dank-material-shell
  quickshell-overview
  noctalia
  caelestia-shell
  caelestia-shell-dev
)

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  scripts/update-shell-inputs.sh [input ...]

Without args, updates the default shell-related flake inputs.
With args, updates only the provided input names.
EOF
  exit 0
fi

inputs=("$@")
if [[ ${#inputs[@]} -eq 0 ]]; then
  inputs=("${default_inputs[@]}")
fi

echo "Updating shell inputs: ${inputs[*]}"
nix flake update "${inputs[@]}"

echo
echo "Done. Review changes in flake.lock and run:"
echo "  nix flake check --no-build"
