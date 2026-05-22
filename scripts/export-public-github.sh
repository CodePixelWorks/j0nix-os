#!/usr/bin/env bash
set -euo pipefail

# export-public-github.sh — Simple sanitized TREE export (no history).
# Use this for local verification of what the mirror looks like.
#
# Usage: export-public-github.sh OUTPUT_DIR

output_dir="${1:?usage: export-public-github.sh OUTPUT_DIR}"
repo_root="$(git rev-parse --show-toplevel)"
tmp_dir="$(mktemp -d)"

cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

rm -rf "$output_dir"
mkdir -p "$(dirname "$output_dir")"

# ---------------------------------------------------------------------------
# 1. Copy working tree (current HEAD, including untracked files that are
#    not ignored).
# ---------------------------------------------------------------------------
git -C "$repo_root" ls-files -co --exclude-standard -z | while IFS= read -r -d '' path; do
  case "$path" in .git|.git/*) continue ;; esac
  src="$repo_root/$path"
  dst="$tmp_dir/$path"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
done

# ---------------------------------------------------------------------------
# 2. Strip secrets and host-specific data.
# ---------------------------------------------------------------------------
remove_paths=(
  ".sops.yaml"
  "settings.nix"
  "profiles/desktop/details.nix"
  "profiles/desktop/hardware-configuration.nix"
)
for path in "${remove_paths[@]}"; do
  rm -f "$tmp_dir/$path"
done

if [ -d "$tmp_dir/secrets/hosts" ]; then
  find "$tmp_dir/secrets/hosts" -mindepth 1 -maxdepth 1 -type f -delete
fi
if [ -d "$tmp_dir/secrets/users" ]; then
  find "$tmp_dir/secrets/users" -mindepth 1 -maxdepth 1 -type f -delete
fi
rm -rf "$tmp_dir/secrets/.backups"

# ---------------------------------------------------------------------------
# 3. Replace sensitive files with their public-safe example templates.
# ---------------------------------------------------------------------------
cp -f "$tmp_dir/settings.nix.example" "$tmp_dir/settings.nix"
cp -f "$tmp_dir/profiles/desktop/details.nix.example" "$tmp_dir/profiles/desktop/details.nix"
cp -f "$tmp_dir/profiles/desktop/hardware-configuration.nix.example" "$tmp_dir/profiles/desktop/hardware-configuration.nix"
cp -f "$tmp_dir/.sops.yaml.example" "$tmp_dir/.sops.yaml"

# ---------------------------------------------------------------------------
# 4. Redact the private-source indicator in README.
# ---------------------------------------------------------------------------
if [ -f "$tmp_dir/README.md" ]; then
  sed -i 's/\[\!NOTE\]/[!IMPORTANT]/ ; s/> This repository is the \*\*private source\*\*. A public mirror is maintained separately with secrets and host keys stripped out./> This is the public mirror of j0nix-os. Secrets and machine-specific data have been stripped. Contributions welcome - open an issue or PR!/' "$tmp_dir/README.md"
fi

mv "$tmp_dir" "$output_dir"
trap - EXIT INT TERM
