#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:?usage: publish-public-github.sh OUTPUT_DIR REMOTE_URL [BRANCH]}"
remote_url="${2:?usage: publish-public-github.sh OUTPUT_DIR REMOTE_URL [BRANCH]}"
branch="${3:-main}"

if [ -z "$remote_url" ]; then
    printf '%s\n' "Missing secret: PUBLIC_GITHUB_REMOTE is empty or not injected" >&2
    exit 1
fi

commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
# Prefer secret over fallback constant. Either may be absent.
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---------------------------------------------------------------------------
# SSH key: inject if provided via Drone secret, otherwise assume agent or
# that the remote uses https.
# ---------------------------------------------------------------------------
GIT_SSH_CMD="ssh"
if [ -n "${PUBLIC_GITHUB_PRIVATE_KEY:-}" ]; then
    ssh_key_path="$(mktemp -t public_github.XXXXXX)"
    chmod 600 "$ssh_key_path"
    # Drone strips newlines from multiline secrets by default; restore LF
    # via printf %b which interprets \n as newline.
    printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
    GIT_SSH_CMD="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi
export GIT_SSH_COMMAND="$GIT_SSH_CMD"

script_dir="$(cd "$(dirname "$0")" && pwd)"
"$script_dir/export-public-github.sh" "$output_dir"

repo_root="$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# Build commit message. Include cutoff metadata when configured.
# ---------------------------------------------------------------------------
if [ -n "$cutoff_commit" ]; then
  total_commits=$(git -C "$repo_root" rev-list --all --count 2>/dev/null || echo "unknown")
  kept_commits=$(git -C "$repo_root" rev-list "$cutoff_commit..HEAD" --count 2>/dev/null || echo "unknown")
  cutoff_msg=$(git -C "$repo_root" log -1 --format="%s" "$cutoff_commit" 2>/dev/null || echo "unknown")

  commit_msg="chore: publish public mirror

This mirror reflects the current state of j0nix-os.

Historical cutoff applied:
  cutoff_commit: ${cutoff_commit}
  cutoff_subject: ${cutoff_msg}
  original_total_commits: ${total_commits}
  commits_after_cutoff: ${kept_commits}

The pre-cutoff history contains experimental architecture,
dead references, and stale dependencies that do not represent
 the current Settings/Profiles boundary contract.

exported_at: ${timestamp}"
else
  commit_msg="chore: publish public mirror (${timestamp})"
fi

# ---------------------------------------------------------------------------
# Initialise fresh repo (orphan branch = no history leakage).
# ---------------------------------------------------------------------------
git -C "$output_dir" init -q
git -C "$output_dir" checkout -B "$branch" -q
git -C "$output_dir" config user.name "$commit_name"
git -C "$output_dir" config user.email "$commit_email"
git -C "$output_dir" add -A
git -C "$output_dir" commit -q -m "$commit_msg" || true

# ---------------------------------------------------------------------------
# Push to public remote.
# ---------------------------------------------------------------------------
if git -C "$output_dir" remote get-url github >/dev/null 2>&1; then
  git -C "$output_dir" remote set-url github "$remote_url"
else
  git -C "$output_dir" remote add github "$remote_url"
fi

git -C "$output_dir" push -q --force github "HEAD:$branch"
