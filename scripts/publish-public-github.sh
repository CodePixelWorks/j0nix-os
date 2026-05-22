#!/usr/bin/env bash
set -euo pipefail

# publish-public-github.sh — publish a sanitized, history-preserving mirror.
#
# Usage: publish-public-github.sh REMOTE_URL [BRANCH]
#
# Environment:
#   PUBLIC_GITHUB_TOKEN          — GitHub Personal Access Token (HTTPS auth).
#                                    Preferred over SSH. Will not leak in logs.
#   PUBLIC_GITHUB_PRIVATE_KEY    — SSH key for git push (fallback when PAT absent).
#   PUBLIC_GITHUB_COMMIT_NAME    — Author/committer name for rewritten history.
#   PUBLIC_GITHUB_COMMIT_EMAIL   — Author/committer email for rewritten history.
#   PUBLIC_CUTOFF_COMMIT         — Optional. Commits BEFORE this hash are
#                                    removed entirely from mirror history.
#   PUBLIC_CUTOFF_COMMIT_FALLBACK — Fallback when the above secret is unset.
#   PUBLIC_SOURCE_URL             — Optional, recorded in metadata.
#
# Rewrites every commit since the cutoff (or all commits if no cutoff):
#   - strips sensitive files, replaces with .example templates
#   - patches README.md for public mirror phrasing
#   - rewrites committer/author to the configured identity

remote_url="${1:?usage: publish-public-github.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"

repo_root="$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# 1. Auth method: PAT (HTTPS) preferred; SSH fallback.
# ---------------------------------------------------------------------------
git_auth_remote="$remote_url"
ssh_key_path=""

if [ -n "${PUBLIC_GITHUB_TOKEN:-}" ]; then
    case "$remote_url" in
        https://github.com/*)
            git_auth_remote="${remote_url/https:\/\//https:\/\/x-access-token:${PUBLIC_GITHUB_TOKEN}@}"
            ;;
        git@github.com:*)
            git_auth_remote="https://x-access-token:${PUBLIC_GITHUB_TOKEN}@github.com${remote_url#git@github.com}"
            ;;
        *)
            printf '%s\n' "WARN: Unknown remote_url format; attempting to embed PAT" >&2
            git_auth_remote="https://x-access-token:${PUBLIC_GITHUB_TOKEN}@${remote_url#*://}"
            ;;
    esac
else
    GIT_SSH_CMD="ssh"
    if [ -n "${PUBLIC_GITHUB_PRIVATE_KEY:-}" ]; then
        ssh_key_path="$(mktemp -t public_github.XXXXXX)"
        chmod 600 "$ssh_key_path"
        printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
        GIT_SSH_CMD="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    fi
    export GIT_SSH_COMMAND="$GIT_SSH_CMD"
fi

# ---------------------------------------------------------------------------
# 2. Clone source repo into a temporary workspace.
# ---------------------------------------------------------------------------
work_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$work_dir"
    [ -n "$ssh_key_path" ] && rm -f "$ssh_key_path" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"

git remote remove origin 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Combined filter-branch pass: orphan history from cutoff + sanitize
#    all remaining commits + rewrite identity.
# ---------------------------------------------------------------------------
export FILTER_BRANCH_SQUELCH_WARNING=1

# Environment variables expanded at script build time.
env_filter="
    export GIT_AUTHOR_NAME='__COMMIT_NAME__'
    export GIT_AUTHOR_EMAIL='__COMMIT_EMAIL__'
    export GIT_COMMITTER_NAME='__COMMIT_NAME__'
    export GIT_COMMITTER_EMAIL='__COMMIT_EMAIL__'
"

tree_filter='
    rm -f .sops.yaml settings.nix profiles/desktop/details.nix profiles/desktop/hardware-configuration.nix
    if [ -d secrets/hosts ]; then
        find secrets/hosts -mindepth 1 -maxdepth 1 -type f -delete
    fi
    if [ -d secrets/users ]; then
        find secrets/users -mindepth 1 -maxdepth 1 -type f -delete
    fi
    rm -rf secrets/.backups

    # Substitute templates.  Use cp -f so a missing .example does not abort.
    cp -f settings.nix.example               settings.nix 2>/dev/null || true
    cp -f profiles/desktop/details.nix.example       profiles/desktop/details.nix 2>/dev/null || true
    cp -f profiles/desktop/hardware-configuration.nix.example profiles/desktop/hardware-configuration.nix 2>/dev/null || true
    cp -f .sops.yaml.example                 .sops.yaml 2>/dev/null || true

    if [ -f README.md ]; then
        # Patch README: switch note type and replace private-source line.
        sed -i "s/\[\!NOTE\]/[!IMPORTANT]/ ; s/> This repository is the \*\*private source\*\*. A public mirror is maintained separately with secrets and host keys stripped out./> This is the public mirror of j0nix-os. Secrets and machine-specific data have been stripped. Contributions welcome \xe2\x80\x94 open an issue or PR!/" README.md 2>/dev/null || true
    fi
'

# Inline-commit placeholders replaced at script build time.
env_filter="${env_filter//__COMMIT_NAME__/$commit_name}"
env_filter="${env_filter//__COMMIT_EMAIL__/$commit_email}"

if [ -n "$cutoff_commit" ]; then
    # --parent-filter removes the cutoff commit as parent from the first
    # rewritten commit after the cutoff, creating a new root = clean history.
    git filter-branch \
        --force \
        --parent-filter "sed 's/-p ${cutoff_commit}//'" \
        --env-filter "$env_filter" \
        --tree-filter "$tree_filter" \
        --prune-empty \
        --tag-name-filter cat \
        -- --all
else
    git filter-branch \
        --force \
        --env-filter "$env_filter" \
        --tree-filter "$tree_filter" \
        --prune-empty \
        --tag-name-filter cat \
        -- --all
fi

# filter-branch leaves refs in refs/original/ — drop them so they are
# not accidentally pushed and do not bloat the clone.
rm -rf .git/refs/original/

# ---------------------------------------------------------------------------
# 4. Optional metadata at HEAD.
# ---------------------------------------------------------------------------
if [ -n "$cutoff_commit" ]; then
    mkdir -p .well-known
    total_commits=$(git rev-list --all --count 2>/dev/null || echo "unknown")
    kept_commits=$(git log --oneline --all | wc -l | tr -d ' ')
    cutoff_msg=$(git log -1 --format="%s" "$cutoff_commit" 2>/dev/null || echo "unknown")
    cat > .well-known/public-mirror-metadata.json <<EOF
{
  "source_repository": "${PUBLIC_SOURCE_URL:-}",
  "cutoff_commit": "$cutoff_commit",
  "cutoff_subject": "$cutoff_msg",
  "original_total_commits": $total_commits,
  "commits_after_cutoff": $kept_commits,
  "cutoff_reason": "Experimental phase concluded. Stable Settings/Profiles architecture established. Dead references removed.",
  "exported_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    git add -A
    # Amend HEAD without changing commit date; preserve original timestamp.
    GIT_COMMITTER_DATE="$(git log -1 --format=%cI)" \
        git commit --amend --no-edit --reset-author || true
fi

# ---------------------------------------------------------------------------
# 5. Push to GitHub.
# ---------------------------------------------------------------------------
git remote add github "$git_auth_remote" 2>/dev/null || git remote set-url github "$git_auth_remote"

git push --force github "HEAD:$branch"
git push --force --tags github

trap - EXIT INT TERM
