#!/usr/bin/env bash
# mirror-sync-backward.sh — import GitHub PR commits into Gitea.
#
# Stub: fetches GitHub history and lists commits not present in Gitea.
# Full implementation planned: cherry-pick PR commits into a feature branch
# for manual review and merge.
#
# Usage: mirror-sync-backward.sh REMOTE_URL [BRANCH]

set -euo pipefail

remote_url="${1:?usage: mirror-sync-backward.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

tag="${PUBLIC_SYNC_TAG:-last-synced-from-gitea}"
repo_root="$(git rev-parse --show-toplevel)"

# --- auth setup (same pattern as forward) -----------------------------------
if [ -n "${PUBLIC_GITHUB_TOKEN:-}" ]; then
    case "$remote_url" in
        https://github.com/*)
            git_auth_remote="${remote_url/https:\/\//https:\/\/oauth2:${PUBLIC_GITHUB_TOKEN}@}"
            ;;
        git@github.com:*)
            repo_path="${remote_url#git@github.com:}"
            git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@github.com/${repo_path}"
            ;;
        *)
            git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@${remote_url#*://}"
            ;;
    esac
else
    git_auth_remote="$remote_url"
    if [ -n "${PUBLIC_GITHUB_PRIVATE_KEY:-}" ]; then
        ssh_key_path="$(mktemp -t mirror_sync.XXXXXX)"
        chmod 600 "$ssh_key_path"
        printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
        export GIT_SSH_COMMAND="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    fi
fi

# --- fetch GitHub remote -----------------------------------------------------
if ! git remote get-url github >/dev/null 2>&1; then
    git remote add github "$git_auth_remote"
else
    git remote set-url github "$git_auth_remote"
fi

git fetch github "$branch" --tags

# --- identify GitHub-only commits -------------------------------------------
gitea_head="$(git rev-parse "$branch")"
github_head="$(git rev-parse "github/$branch")"

printf '%s\n' "Gitea HEAD:  ${gitea_head:0:12}"
printf '%s\n' "GitHub HEAD: ${github_head:0:12}"
printf '%s\n' ""

# Commits in github/$branch but NOT in local branch
github_only=()
while IFS= read -r hash; do
    [ -z "$hash" ] && continue
    github_only+=("$hash")
done < <(git log --reverse --format='%H' "${gitea_head}..github/${branch}" 2>/dev/null || true)

if [ ${#github_only[@]} -eq 0 ]; then
    printf '%s\n' "No GitHub-only commits found. Both repos are in sync."
    exit 0
fi

printf '%s\n' "=== ${#github_only[@]} GitHub-only commit(s) ==="
for hash in "${github_only[@]}"; do
    msg="$(git log -1 --format='%s' "$hash")"
    author="$(git log -1 --format='%an <%ae>' "$hash")"
    printf '%s  %s  %s\n' "${hash:0:12}" "$author" "$msg"
done

printf '%s\n' ""
printf '%s\n' "To import these commits into Gitea:"
printf '%s\n' "  1. Create a feature branch: git checkout -b import-github-prs"
printf '%s\n' "  2. Cherry-pick each commit: git cherry-pick <hash>"
printf '%s\n' "  3. Review, then merge into main"
