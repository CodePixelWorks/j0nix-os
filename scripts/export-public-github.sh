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
  [ -e "$src" ] || continue
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
  find "$tmp_dir/secrets/hosts" -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
fi
if [ -d "$tmp_dir/secrets/users" ]; then
  find "$tmp_dir/secrets/users" -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
fi
rm -rf "$tmp_dir/secrets/identity"
rm -rf "$tmp_dir/secrets/.backups"

# ---------------------------------------------------------------------------
# 2b. Strip private flake inputs (j0nix-identity-secrets points to a
#     private Gitea repo whose URL must never leak into the public mirror).
#     The consumer defaults to settings.secrets.identity.mode = "legacy"
#     so removing the input does not break evaluation; switching to
#     shared-flake mode requires the input and is documented as opt-in.
# ---------------------------------------------------------------------------
if [ -f "$tmp_dir/flake.nix" ]; then
    python3 -c "
import re, sys
with open('$tmp_dir/flake.nix', 'r') as f:
    src = f.read()
# Strip every private flake input block listed here. Each block is an
# attrset entry of the form
#   <name> = {
#     url = ...;
#     inputs.nixpkgs.follows = ...;
#   };
# Single-line forms are also accepted. Re.sub is called twice with
# distinct anchoring patterns because the entry can sit at any indent.
names = ('j0nix-identity-secrets', 'resolve-patch')
for name in names:
    pat_anywhere = re.compile(
        r'\n\s*' + re.escape(name) + r'\s*=\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\s*;\s*\n',
        re.MULTILINE,
    )
    src = pat_anywhere.sub('\n', src, count=1)
with open('$tmp_dir/flake.nix', 'w') as f:
    f.write(src)
"
fi

if [ -f "$tmp_dir/flake.lock" ]; then
    python3 -c "
import json
with open('$tmp_dir/flake.lock') as f:
    d = json.load(f)
# Remove the node entirely and drop every reference (root + transitive).
for name in ('j0nix-identity-secrets', 'resolve-patch'):
    d.get('nodes', {}).pop(name, None)
    for node in d.get('nodes', {}).values():
        if isinstance(node, dict) and 'inputs' in node:
            node['inputs'].pop(name, None)
with open('$tmp_dir/flake.lock', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
fi

# ---------------------------------------------------------------------------
# 3. Redact the private-source indicator in README.
# ---------------------------------------------------------------------------
if [ -f "$tmp_dir/README.md" ]; then
  sed -i 's/\[\!NOTE\]/[!IMPORTANT]/ ; s/> This repository is the \*\*private source\*\*. A public mirror is maintained separately with secrets and host keys stripped out./> This is the public mirror of j0nix-os. Secrets and machine-specific data have been stripped. Contributions welcome - open an issue or PR!/' "$tmp_dir/README.md"
fi

mv "$tmp_dir" "$output_dir"
trap - EXIT INT TERM
