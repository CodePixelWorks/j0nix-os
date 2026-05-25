#!/usr/bin/env bash
# mirror-sync-backward.sh — import GitHub-only external commits into Gitea.
#
# This is the companion to mirror-sync-forward.sh.
# It fetches GitHub, identifies commits that only exist there (typically from
# merged PRs by external contributors), validates they do not touch sensitive
# files, and cherry-picks their safe diffs into the local Gitea branch.
#
# Safety guarantees:
#   - Commits touching secrets/*, settings.nix, .sops.yaml, or any
#     .mirror-blacklist entry are skipped entirely.
#   - Commits authored by the mirror bot or by jonas/j0nix are ignored
#     (those are handled by forward sync).
#   - Commits already present in Gitea (deduplicated by message+author+date)
#     are skipped — this prevents infinite loops after forward re-export.
#
# Usage: mirror-sync-backward.sh REMOTE_URL [BRANCH]
#
# Environment:
#   PUBLIC_GITHUB_SIGNING_KEY        -- GPG private key for signing (optional).
#   PUBLIC_GITHUB_COMMIT_NAME        -- Mirror bot name (to skip bot commits).
#   PUBLIC_GITHUB_COMMIT_EMAIL       -- Mirror bot email (to skip bot commits).
#   PUBLIC_GITHUB_TOKEN              -- GitHub PAT (HTTPS auth).
#   PUBLIC_GITHUB_PRIVATE_KEY        -- SSH key fallback.
#   PUBLIC_SYNC_TAG                  -- Tag tracking last sync on GitHub
#                                       (default: last-synced-from-gitea).
#   PUBLIC_GITHUB_REWRITE_EMAILS     -- Comma-separated list of exact email
#                                         addresses to match for selective author
#                                         rewrite (e.g. "a@x.com,b@y.de").
#                                         Default: empty (no rewrite)
#   PUBLIC_GITHUB_REWRITE_NAMES      -- Optional. Same for exact author names.
#                                         Disabled by default.
#   PUBLIC_SANITIZE_AUTHOR_REGEX     -- DEPRECATED. Use PUBLIC_GITHUB_REWRITE_EMAILS.

set -euo pipefail

remote_url="${1:?usage: mirror-sync-backward.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

tag="${PUBLIC_SYNC_TAG:-last-synced-from-gitea}"
bot_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
bot_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
rewrite_emails="${PUBLIC_GITHUB_REWRITE_EMAILS:-}"
rewrite_names="${PUBLIC_GITHUB_REWRITE_NAMES:-}"
repo_root="$(git rev-parse --show-toplevel)"

print_public_signing_key() {
    local key_id="${1:-}"
    [ -n "$key_id" ] || return 0

    printf '%s\n' "GPG public key (ASCII-armored):"
    gpg --armor --export "$key_id"
    printf '%s\n' ""
}

# --- load shared sanitisation engine -----------------------------------------
# shellcheck source=scripts/lib/mirror-sanitize.sh
source "$repo_root/scripts/lib/mirror-sanitize.sh"
ms_init "$repo_root"

# Build glob patterns and inject into the shared engine
MS_SANITIZE_AUTHOR_NAME="$bot_name"
MS_SANITIZE_AUTHOR_EMAIL="$bot_email"
MS_SANITIZE_EMAIL_PATTERNS="$(ms_build_patterns "$rewrite_emails")"
MS_SANITIZE_NAME_PATTERNS="$(ms_build_patterns "$rewrite_names")"

# --- gpg signing setup (optional) --------------------------------------------
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
        print_public_signing_key "$gpg_key_id"
        git config --global user.signingkey "$gpg_key_id"
    else
        printf '%s\n' "WARN: could not import GPG signing key" >&2
    fi
fi

# --- auth setup (same pattern as forward) ------------------------------------
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
    git_auth_remote="$remote_url"
    if [ -n "${PUBLIC_GITHUB_PRIVATE_KEY:-}" ]; then
        ssh_key_path="$(mktemp -t mirror_sync.XXXXXX)"
        chmod 600 "$ssh_key_path"
        printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
        export GIT_SSH_COMMAND="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    fi
fi

# --- temp workspace ----------------------------------------------------------
# We work inside the local Gitea clone (Drone already checked it out).
cd "$repo_root"
work_branch="github-import-$(date +%s)"
cleanup() {
    git checkout "$branch" 2>/dev/null || true
    git branch -D "$work_branch" 2>/dev/null || true
    [ -n "$ssh_key_path" ] && rm -f "$ssh_key_path" 2>/dev/null || true
    [ -n "$gpg_dir" ] && rm -rf "$gpg_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- fetch GitHub ------------------------------------------------------------
if ! git remote get-url github >/dev/null 2>&1; then
    git remote add github "$git_auth_remote"
else
    git remote set-url github "$git_auth_remote"
fi

if ! git fetch github "$branch" --tags; then
    printf '%s\n' "ERROR: cannot fetch from GitHub" >&2
    exit 1
fi

# --- discover sync range -----------------------------------------------------
gitea_head="$(git rev-parse "$branch")"
github_head="$(git rev-parse "github/$branch")"

printf '%s\n' "Gitea HEAD:  ${gitea_head:0:12}"
printf '%s\n' "GitHub HEAD: ${github_head:0:12}"
printf '%s\n' ""

# Determine the commit on github/$branch where the last sync tag points.
# If the tag doesn't exist on GitHub, fallback to the common ancestor.
sync_base=""
if git rev-parse "github/$tag" >/dev/null 2>&1; then
    sync_base="$(git rev-parse "github/$tag")"
    printf '%s\n' "Sync tag '$tag' found at $sync_base on GitHub"
elif git merge-base "$gitea_head" "$github_head" >/dev/null 2>&1; then
    sync_base="$(git merge-base "$gitea_head" "$github_head")"
    printf '%s\n' "No sync tag on GitHub; using merge-base $sync_base"
else
    printf '%s\n' "ERROR: no common history between Gitea and GitHub" >&2
    exit 1
fi

# List GitHub-only commits: those reachable from github_head but NOT from sync_base
# i.e. everything added to GitHub since the last (known) sync point.
github_only=()
while IFS= read -r hash; do
    [ -z "$hash" ] && continue
    github_only+=("$hash")
done < <(git log --reverse --first-parent --format='%H' "${sync_base}..github/${branch}" 2>/dev/null || true)

if [ ${#github_only[@]} -eq 0 ]; then
    printf '%s\n' "No GitHub-only commits found. Both repos are in sync."
    exit 0
fi

printf '%s\n' "=== ${#github_only[@]} GitHub-only commit(s) since last sync ==="

# --- helper: build dedup key for a commit ------------------------------------
_commit_key() {
    git log -1 --format='%s|%an|%ae|%ad' "$1" 2>/dev/null || true
}

# Build a set of existing Gitea commit keys for deduplication.
# This prevents importing a commit that was already exported by forward sync.
printf '%s\n' "Building Gitea commit index..."
declare -A gitea_keys
while IFS= read -r hash; do
    [ -z "$hash" ] && continue
    key="$(_commit_key "$hash")"
    [ -n "$key" ] && gitea_keys["$key"]=1
done < <(git log --first-parent --format='%H' "${sync_base}..${gitea_head}" 2>/dev/null || true)
printf '%s\n' "  indexed ${#gitea_keys[@]} Gitea commits"
printf '%s\n' ""

# --- create work branch ------------------------------------------------------
git checkout -b "$work_branch" "$gitea_head" >/dev/null 2>&1

total="${#github_only[@]}"
current=0
imported=0
skipped=0
failed=0

for hash in "${github_only[@]}"; do
    current=$((current + 1))
    msg="$(git log -1 --format='%s' "$hash" 2>/dev/null || true)"
    author_name="$(git log -1 --format='%an' "$hash" 2>/dev/null || true)"
    author_email="$(git log -1 --format='%ae' "$hash" 2>/dev/null || true)"
    author_date="$(git log -1 --format='%ad' "$hash" 2>/dev/null || true)"
    committer_name="$(git log -1 --format='%cn' "$hash" 2>/dev/null || true)"
    committer_email="$(git log -1 --format='%ce' "$hash" 2>/dev/null || true)"

    printf '\n[%d/%d] %s  %s <%s>\n' "$current" "$total" "${hash:0:12}" "$author_name" "$author_email"
    printf '    %s\n' "$msg"

    # --- skip bot commits (forward-sync artifacts) ---
    if [ "$author_name" = "$bot_name" ] && [ "$author_email" = "$bot_email" ]; then
        printf '    SKIP: authored by mirror bot (forward-sync artifact)\n'
        skipped=$((skipped + 1))
        continue
    fi

    # --- skip my own commits (already in Gitea, just rewritten on GitHub) ---
    if ms_should_sanitize_author "$author_name" "$author_email"; then
        printf '    SKIP: authored by local user (already sourced from Gitea)\n'
        skipped=$((skipped + 1))
        continue
    fi

    # --- deduplication: already imported in a previous run? ---
    dup_key="$msg|$author_name|$author_email|$author_date"
    if [ "${gitea_keys[$dup_key]:-}" = "1" ]; then
        printf '    SKIP: duplicate (already present in Gitea by message+author+date)\n'
        skipped=$((skipped + 1))
        continue
    fi

    # --- safety: does this commit touch sensitive files? ---
    if ! ms_commit_is_safe "$hash"; then
        printf '    SKIP: touches sensitive files (see output above)\n' >&2
        skipped=$((skipped + 1))
        continue
    fi

    # --- identify the parent for diff generation ---
    # For merge commits we take the first parent (the mainline).
    parent_count="$(git cat-file -p "$hash" 2>/dev/null | grep -c '^parent ' || true)"
    parent=""
    if [ "${parent_count:-0}" -gt 1 ]; then
        parent="$(git rev-parse "${hash}^1")"
        printf '    NOTE: merge commit (%d parents), using first parent for diff\n' "$parent_count"
    else
        parent="$(git rev-parse "${hash}^" 2>/dev/null || true)"
    fi
    if [ -z "$parent" ]; then
        printf '    SKIP: cannot determine parent (root commit?)\n' >&2
        skipped=$((skipped + 1))
        continue
    fi

    # --- build safe file list and extract diff ---
    changed_files=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        changed_files+=("$f")
    done < <(git diff-tree --no-commit-id --name-only -r "$hash" 2>/dev/null || true)

    safe_files=()
    sensitive_list="$(ms_sensitive_files_list | sed '/^$/d')"
    for f in "${changed_files[@]}"; do
        is_sensitive=0
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            # Normalize pattern for grep: remove leading ./, support wildcards
            if printf '%s\n' "$f" | grep -qiE "^${pattern}$" 2>/dev/null; then
                is_sensitive=1
                break
            fi
            # Also check prefix match for directory patterns (e.g. secrets/)
            case "$pattern" in
                */)
                    case "$f" in
                        "${pattern%/}"/*) is_sensitive=1; break ;;
                    esac
                    ;;
            esac
        done <<< "$sensitive_list"

        if [ "$is_sensitive" -eq 0 ]; then
            safe_files+=("$f")
        fi
    done

    if [ ${#safe_files[@]} -eq 0 ]; then
        printf '    SKIP: all changed files are sensitive\n'
        skipped=$((skipped + 1))
        continue
    fi

    printf '    Importing %d of %d changed file(s)\n' "${#safe_files[@]}" "${#changed_files[@]}"

    # --- apply the safe diff to current Gitea work branch ---
    patch_file="$(mktemp -t backward_patch.XXXXXX)"
    if ! git diff "$parent" "$hash" -- "${safe_files[@]}" > "$patch_file" 2>/dev/null; then
        printf '    FAILED: could not generate diff\n' >&2
        rm -f "$patch_file"
        failed=$((failed + 1))
        continue
    fi

    if [ ! -s "$patch_file" ]; then
        printf '    SKIP: empty diff after filtering (no safe changes)\n'
        rm -f "$patch_file"
        skipped=$((skipped + 1))
        continue
    fi

    if ! git apply --check "$patch_file" 2>/dev/null; then
        printf '    FAILED: patch does not apply cleanly (divergent history/tree)\n' >&2
        rm -f "$patch_file"
        failed=$((failed + 1))
        continue
    fi

    git apply "$patch_file"
    rm -f "$patch_file"

    # --- commit with original identity ---
    commit_args="--allow-empty"
    [ -n "$gpg_key_id" ] && commit_args="$commit_args -S"

    if ! GIT_AUTHOR_DATE="$author_date" \
         GIT_AUTHOR_NAME="$author_name" \
         GIT_AUTHOR_EMAIL="$author_email" \
         GIT_COMMITTER_DATE="$author_date" \
         GIT_COMMITTER_NAME="$committer_name" \
         GIT_COMMITTER_EMAIL="$committer_email" \
             git commit $commit_args -m "$msg" 2>/dev/null; then
        printf '    FAILED: commit failed after applying patch\n' >&2
        git reset --hard HEAD
        failed=$((failed + 1))
        continue
    fi

    new_hash="$(git rev-parse HEAD)"
    printf '    IMPORTED as %s\n' "${new_hash:0:12}"
    imported=$((imported + 1))

    # Add to dedup index so subsequent commits in this run don't re-import
    gitea_keys["$dup_key"]=1
done

# --- summary -----------------------------------------------------------------
printf '\n=== backward sync summary ===\n'
printf '%s\n' "  imported:  $imported"
printf '%s\n' "  skipped:   $skipped"
printf '%s\n' "  failed:    $failed"

if [ "$imported" -eq 0 ] && [ "$failed" -eq 0 ]; then
    printf '%s\n' "No changes to push."
    exit 0
fi

if [ "$failed" -gt 0 ]; then
    printf '%s\n' ""
    printf '%s\n' "WARNING: $failed commit(s) failed to import." >&2
    printf '%s\n' "Review the output above and fix divergences before re-running." >&2
fi

# --- push to Gitea -----------------------------------------------------------
printf '\n%s\n' "Pushing imported commits to Gitea ($branch)..."
if ! git push origin "${work_branch}:${branch}"; then
    printf '%s\n' "ERROR: push to Gitea failed." >&2
    printf '%s\n' "Possible causes: branch protection, concurrent push, or diverged history." >&2
    exit 1
fi

printf '%s\n' "Done."
