#!/usr/bin/env bash
# mirror-sync-forward.sh -- incremental, selective mirror: Gitea -> GitHub.
#
# Only processes new commits since the last sync tag.
# Commits from the configured author (default: jonas/j0nix) are sanitised
# (identity rewritten, secrets stripped).  Commits from external authors
# (Dependabot, PR merges, etc.) keep their original identity and message.
#
# Usage: mirror-sync-forward.sh REMOTE_URL [BRANCH]
#
# Environment:
#   PUBLIC_GITHUB_TOKEN           -- GitHub PAT (HTTPS auth).
#   PUBLIC_GITHUB_PRIVATE_KEY     -- SSH key fallback.
#   PUBLIC_CUTOFF_COMMIT          -- Optional fallback when no sync tag exists.
#   PUBLIC_CUTOFF_COMMIT_FALLBACK -- Fallback for the above secret.
#   PUBLIC_GITHUB_COMMIT_NAME     -- Author name for sanitised commits.
#   PUBLIC_GITHUB_COMMIT_EMAIL    -- Author email for sanitised commits.
#   PUBLIC_GITHUB_SIGNING_KEY     -- GPG private key (ASCII-armored) for signing
#                                     mirrored commits.  If set, all rewritten
#                                     commits are GPG-signed; the public key must
#                                     be registered at the GitHub account that
#                                     owns PUBLIC_GITHUB_COMMIT_EMAIL.  Omit to
#                                     keep commits unsigned.
#   PUBLIC_SANITIZE_AUTHOR_REGEX  -- Regex to match authors that should be
#                                     rewritten (default: ^(jonas|j0nix)).
#   PUBLIC_GITHUB_IDENTITY_MODE   -- Identity rewrite policy:
#                                     selective  -> rewrite authors matching regex (default)
#                                     rewrite_all -> rewrite every author to bot
#                                     preserve   -> keep original identity for all
#   PUBLIC_SOURCE_URL             -- Recorded in metadata.
#   PUBLIC_SYNC_TAG               -- Tag on GitHub tracking last sync
#                                     (default: last-synced-from-gitea).
#
# Design:
#   1. Clone Gitea repo into temp worktree.
#   2. Fetch GitHub remote to discover current HEAD and sync tag.
#   3. Determine sync base: last-synced tag or cutoff or repo root.
#   4. List new Gitea commits since sync base (first-parent, reverse).
#   5. For each commit:
#      - cherry-pick --no-commit
#      - apply tree-filter (blacklist/whitelist/templates/README)
#      - decide identity: rewrite (sanitise) or keep original
#      - commit with appropriate author/committer, optionally GPG-signed
#   6. Rebase resulting branch onto GitHub HEAD for fast-forward push.
#   7. Update sync tag, push branch + tag.
#
# Safety: this script NEVER force-pushes the branch.  If history diverged
# unexpectedly it aborts with instructions.

set -euo pipefail

remote_url="${1:?usage: mirror-sync-forward.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

tag="${PUBLIC_SYNC_TAG:-last-synced-from-gitea}"
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
sanitize_regex="${PUBLIC_SANITIZE_AUTHOR_REGEX:-^(jonas|j0nix)}"
identity_mode="${PUBLIC_GITHUB_IDENTITY_MODE:-selective}"

repo_root="$(git rev-parse --show-toplevel)"

# --- gpg signing setup (before work_dir exists) -------------------------------
gpg_key_id=""
gpg_dir=""
if [ -n "${PUBLIC_GITHUB_SIGNING_KEY:-}" ]; then
    gpg_dir="$(mktemp -d -t mirror_gpg.XXXXXX)"
    chmod 700 "$gpg_dir"
    export GNUPGHOME="$gpg_dir"
    printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | gpg --batch --import 2>/dev/null
    gpg_key_id="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec/{print $5}' | head -n1)"
    if [ -n "$gpg_key_id" ]; then
        printf '%s\n' "GPG signing configured (key ${gpg_key_id:0:16}...)"
        git config --global user.signingkey "$gpg_key_id"
    else
        printf '%s\n' "WARN: could not import GPG signing key" >&2
    fi
fi

# --- load shared sanitisation engine ----------------------------------------
export MS_SANITIZE_AUTHOR_NAME="$commit_name"
export MS_SANITIZE_AUTHOR_EMAIL="$commit_email"
export MS_SANITIZE_MATCH_REGEX="$sanitize_regex"
# shellcheck source=scripts/lib/mirror-sanitize.sh
source "$repo_root/scripts/lib/mirror-sanitize.sh"
ms_init "$repo_root"

printf '%s\n' "Identity mode: $identity_mode"

# --- auth setup -------------------------------------------------------------
git_auth_remote="$remote_url"
ssh_key_path=""

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
            printf '%s\n' "WARN: Unknown remote_url format; attempting PAT embed" >&2
            git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@${remote_url#*://}"
            ;;
    esac
else
    if [ -n "${PUBLIC_GITHUB_PRIVATE_KEY:-}" ]; then
        ssh_key_path="$(mktemp -t mirror_sync.XXXXXX)"
        chmod 600 "$ssh_key_path"
        printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
        export GIT_SSH_COMMAND="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    fi
fi

# --- temp workspace ---------------------------------------------------------
work_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$work_dir"
    [ -n "$ssh_key_path" ] && rm -f "$ssh_key_path" 2>/dev/null || true
    [ -n "$gpg_dir" ] && rm -rf "$gpg_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"

# --- generate public README (outside worktree) ------------------------------
readme_tmp="$repo_root/README.md.public"
if command -v python3 >/dev/null 2>&1; then
    python3 "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_tmp"
elif command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#python3 -- "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_tmp"
else
    printf '%s\n' "ERROR: python3 not found and nix not available" >&2
    exit 1
fi

# strip any embedded tokens from generated README
sed -i 's|https://oauth2:[^@]*@github.com|https://github.com|g' "$readme_tmp" 2>/dev/null || true

# --- discover sync base from GitHub -----------------------------------------
git remote add github "$git_auth_remote" 2>/dev/null || git remote set-url github "$git_auth_remote"
if ! git fetch github "$branch" --tags 2>/dev/null; then
    printf '%s\n' "ERROR: cannot fetch from GitHub remote" >&2
    exit 1
fi

github_head="$(git rev-parse "github/$branch" 2>/dev/null || true)"
if [ -z "$github_head" ]; then
    printf '%s\n' "ERROR: could not determine GitHub HEAD" >&2
    exit 1
fi

sync_base=""
if git rev-parse "refs/tags/$tag" >/dev/null 2>&1; then
    sync_base="$(git rev-parse "refs/tags/$tag")"
    printf '%s\n' "Sync tag '$tag' found at $sync_base"
elif [ -n "$cutoff_commit" ] && git rev-parse "$cutoff_commit" >/dev/null 2>&1; then
    sync_base="$cutoff_commit"
    printf '%s\n' "No sync tag; using cutoff $sync_base"
else
    # first ever run: no tag, no cutoff -> start from first commit
    sync_base="$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -n1)"
    printf '%s\n' "No sync tag or cutoff; starting from root $sync_base"
fi

# --- determine commits to sync ----------------------------------------------
new_commits=()
while IFS= read -r line; do
    new_commits+=("$line")
done < <(git log --reverse --first-parent --format='%H|%ci|%s' "${sync_base}..HEAD" 2>/dev/null || true)

if [ ${#new_commits[@]} -eq 0 ]; then
    printf '%s\n' "Nothing to sync. GitHub HEAD $github_head is up to date with Gitea."
    exit 0
fi

printf '%s\n' "=== ${#new_commits[@]} new commit(s) to sync ==="

# --- prepare branch for incremental export ----------------------------------
# We build a linear chain of new sanitised commits on top of github_head.
# For each Gitea commit we create one mirror commit.
#
# Because cherry-pick preserves merge structure, we use --first-parent above
# and cherry-pick each commit individually.  This flattens merges into a
# linear history - acceptable for a public mirror.

# create a detached HEAD at github_head to start the new chain
git checkout "$github_head" --detach 2>/dev/null

# ensure clean worktree
git reset --hard

total="${#new_commits[@]}"
current=0
failed=0

for entry in "${new_commits[@]}"; do
    current=$((current + 1))
    commit_hash="${entry%%|*}"
    commit_date="${entry#*|}"; commit_date="${commit_date%|*}"
    commit_msg="${entry##*|}"

    printf '\n%s\n' "--- [$current/$total] $commit_hash ---"
    printf '%s\n' "    $commit_msg"

    # extract author info BEFORE cherry-pick (worktree might be dirty)
    author_name="$(git log -1 --format='%an' "$commit_hash")"
    author_email="$(git log -1 --format='%ae' "$commit_hash")"
    committer_name="$(git log -1 --format='%cn' "$commit_hash")"
    committer_email="$(git log -1 --format='%ce' "$commit_hash")"

    # attempt cherry-pick (apply patch, do not commit)
    if ! git cherry-pick --no-commit "$commit_hash" 2>/dev/null; then
        # abort and mark as failed
        git cherry-pick --abort 2>/dev/null || true
        git reset --hard
        printf '%s\n' "    FAILED: cherry-pick conflict, skipped" >&2
        failed=$((failed + 1))
        continue
    fi

    # --- apply tree sanitisation ----------------------------------------
    ms_apply_tree_filter "."

    # --- decide identity ------------------------------------------------
    # Identity policy per PUBLIC_GITHUB_IDENTITY_MODE:
    #   selective   - rewrite only authors matching SANITIZE_REGEX (default)
    #   rewrite_all - rewrite every author's identity to the bot
    #   preserve    - keep original identity for all commits
    should_rewrite=0
    case "$identity_mode" in
        rewrite_all)
            should_rewrite=1
            ;;
        preserve)
            should_rewrite=0
            ;;
        *)
            local_env_filter=""
            ms_build_env_filter "$commit_hash" local_env_filter
            [ -n "$local_env_filter" ] && should_rewrite=1
            ;;
    esac

    # determine commit arguments (sign if configured)
    commit_args="--allow-empty"
    if [ -n "$gpg_key_id" ]; then
        commit_args="$commit_args -S"
    fi

    if [ "$should_rewrite" -eq 1 ]; then
        # sanitise: rewrite author/committer to mirror bot, preserve date
        GIT_AUTHOR_DATE="$commit_date" \
        GIT_COMMITTER_DATE="$commit_date" \
        GIT_AUTHOR_NAME="$commit_name" \
        GIT_AUTHOR_EMAIL="$commit_email" \
        GIT_COMMITTER_NAME="$commit_name" \
        GIT_COMMITTER_EMAIL="$commit_email" \
            git commit $commit_args -m "$commit_msg" 2>/dev/null || {
                printf '%s\n' "    FAILED: commit after sanitise" >&2
                failed=$((failed + 1))
                git reset --hard HEAD
                continue
            }
    else
        # keep original identity
        GIT_AUTHOR_DATE="$commit_date" \
        GIT_COMMITTER_DATE="$commit_date" \
        GIT_AUTHOR_NAME="$author_name" \
        GIT_AUTHOR_EMAIL="$author_email" \
        GIT_COMMITTER_NAME="$committer_name" \
        GIT_COMMITTER_EMAIL="$committer_email" \
            git commit $commit_args -m "$commit_msg" 2>/dev/null || {
                printf '%s\n' "    FAILED: commit with original identity" >&2
                failed=$((failed + 1))
                git reset --hard HEAD
                continue
            }
    fi

done

# --- finalise + metadata commit ---------------------------------------------
head_now="$(git rev-parse HEAD)"

mkdir -p .well-known
cat > .well-known/public-mirror-metadata.json <<EOF
{
  "source_repository": "${PUBLIC_SOURCE_URL:-}",
  "last_synced_source_commit": "$(git rev-parse HEAD~$((total - failed)) 2>/dev/null || echo 'unknown')",
  "commits_synced": $((total - failed)),
  "commits_skipped": $failed,
  "synced_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
git add -A

meta_args="--allow-empty"
[ -n "$gpg_key_id" ] && meta_args="$meta_args -S"
git commit $meta_args -m "chore(mirror): sync metadata" 2>/dev/null || true

# --- push (non-force) -------------------------------------------------------
# We push the new HEAD to github/$branch.  Because we built on top of
# github_head this MUST be a fast-forward.  If it is not, someone pushed
# to GitHub in the meantime and we need to re-sync.

new_head="$(git rev-parse HEAD)"

printf '\n%s\n' "=== pushing to GitHub ($branch) ==="

if ! git push github "$new_head:$branch" 2>&1; then
    printf '%s\n' ""
    printf '%s\n' "ERROR: push failed. Possible causes:" >&2
    printf '%s\n' "  - Someone pushed to GitHub while we were syncing" >&2
    printf '%s\n' "  - Branch protection rules rejected the push" >&2
    printf '%s\n' "  - Authentication failure" >&2
    printf '%s\n' ""
    printf '%s\n' "Re-run the script to retry from a fresh fetch." >&2
    exit 1
fi

# update sync tag
git tag -f "$tag" "$new_head"
if ! git push --force github "$tag" 2>&1; then
    printf '%s\n' "WARN: could not update sync tag '$tag'" >&2
fi

# --- summary ----------------------------------------------------------------
printf '\n%s\n' "=== sync complete ==="
printf '%s\n' "  synced:      $((total - failed))"
printf '%s\n' "  skipped:     $failed"
printf '%s\n' "  github head: ${github_head:0:12}"
printf '%s\n' "  new head:    ${new_head:0:12}"

[ -n "$gpg_key_id" ] && printf '%s\n' "  gpg signing: enabled"

trap - EXIT INT TERM
