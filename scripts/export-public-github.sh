#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:?usage: export-public-github.sh OUTPUT_DIR}"
repo_root="$(git rev-parse --show-toplevel)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

rm -rf "$output_dir"
mkdir -p "$(dirname "$output_dir")"

git -C "$repo_root" ls-files -co --exclude-standard -z | while IFS= read -r -d '' path; do
  case "$path" in
    .git|.git/*)
      continue
      ;;
  esac

  src="$repo_root/$path"
  dst="$tmp_dir/$path"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
done

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

cp -f "$tmp_dir/settings.nix.example" "$tmp_dir/settings.nix"
cp -f "$tmp_dir/profiles/desktop/details.nix.example" "$tmp_dir/profiles/desktop/details.nix"
cp -f "$tmp_dir/profiles/desktop/hardware-configuration.nix.example" "$tmp_dir/profiles/desktop/hardware-configuration.nix"
cp -f "$tmp_dir/.sops.yaml.example" "$tmp_dir/.sops.yaml"

mv "$tmp_dir" "$output_dir"

trap - EXIT INT TERM
