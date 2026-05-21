#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:?usage: publish-public-github.sh OUTPUT_DIR REMOTE_URL [BRANCH]}"
remote_url="${2:?usage: publish-public-github.sh OUTPUT_DIR REMOTE_URL [BRANCH]}"
branch="${3:-main}"
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"

"$(git rev-parse --show-toplevel)/scripts/export-public-github.sh" "$output_dir"

git -C "$output_dir" init -q
git -C "$output_dir" checkout -B "$branch" -q
git -C "$output_dir" config user.name "$commit_name"
git -C "$output_dir" config user.email "$commit_email"
git -C "$output_dir" add -A
git -C "$output_dir" commit -q -m "chore: publish public mirror"

if git -C "$output_dir" remote get-url github >/dev/null 2>&1; then
  git -C "$output_dir" remote set-url github "$remote_url"
else
  git -C "$output_dir" remote add github "$remote_url"
fi

git -C "$output_dir" push -q --force github "HEAD:$branch"
