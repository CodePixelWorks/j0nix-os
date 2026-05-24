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
#   PUBLIC_GITHUB_REWRITE_EMAIL_REGEX — Regex for email-based selective rewrite.
#                                       Default: ^(jonas|j0nix)  (from_secret)
#   PUBLIC_GITHUB_REWRITE_EMAIL_REGEX_FALLBACK — Fallback when secret unset.
#   PUBLIC_GITHUB_REWRITE_NAME_REGEX  — Optional. Regex for name-based matching.
#                                       Disabled by default.               (from_secret)
#   PUBLIC_GITHUB_REWRITE_NAME_REGEX_FALLBACK — Fallback when secret unset.
#   PUBLIC_CUTOFF_COMMIT         — Optional. Commits BEFORE this hash are
#                                    removed entirely from mirror history.
#   PUBLIC_CUTOFF_COMMIT_FALLBACK — Fallback when the above secret is unset.
#   PUBLIC_GITHUB_FORCE_PUSH     — "true" (default) to force-push + force-push tags.
#                                    Set to "false" to push non-destructively.
#                                    Disabling force may fail if history diverged.
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
rewrite_email_regex="${PUBLIC_GITHUB_REWRITE_EMAIL_REGEX:-${PUBLIC_GITHUB_REWRITE_EMAIL_REGEX_FALLBACK:-^(jonas|j0nix)}}"
rewrite_name_regex="${PUBLIC_GITHUB_REWRITE_NAME_REGEX:-${PUBLIC_GITHUB_REWRITE_NAME_REGEX_FALLBACK:-}}"

cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
force_push="${PUBLIC_GITHUB_FORCE_PUSH:-true}"

repo_root="$(git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# 1. Auth method: PAT (HTTPS) preferred; SSH fallback.
# ---------------------------------------------------------------------------
git_auth_remote="$remote_url"
ssh_key_path=""

if [ -n "${PUBLIC_GITHUB_TOKEN:-}" ]; then
    # GitHub PAT auth: oauth2 as username, token as password.
    # Works for both classic and Fine-Grained tokens.
    case "$remote_url" in
        https://github.com/*)
            git_auth_remote="${remote_url/https:\/\//https:\/\/oauth2:${PUBLIC_GITHUB_TOKEN}@}"
            ;;
        git@github.com:*)
            repo_path="${remote_url#git@github.com:}"
            git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@github.com/${repo_path}"
            ;;
        *)
            printf '%s\n' "WARN: Unknown remote_url format; attempting to embed PAT" >&2
            git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@${remote_url#*://}"
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
readme_path="$repo_root/README.md.public"

# Temp path placeholders (set below)
env_filter_path=""
tree_filter_path=""
parent_filter_script=""

cleanup() {
    rm -rf "$work_dir"
    rm -f "$readme_path"
    [ -n "$ssh_key_path" ] && rm -f "$ssh_key_path" 2>/dev/null || true
    [ -n "${env_filter_path:-}" ] && rm -f "$env_filter_path" 2>/dev/null || true
    [ -n "${tree_filter_path:-}" ] && rm -f "$tree_filter_path" 2>/dev/null || true
    [ -n "${parent_filter_script:-}" ] && rm -f "$parent_filter_script" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"

# ---------------------------------------------------------------------------
# 2b. Generate public-facing README.md OUTSIDE the worktree.
#     filter-branch aborts on any unstaged change; we must not touch the
#     worktree before it runs. The file is injected into every commit by
#     the tree-filter via its absolute path.
# ---------------------------------------------------------------------------
readme_path="$repo_root/README.md.public"
if command -v python3 >/dev/null 2>&1; then
    python3 "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"
elif command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#python3 -- "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"
else
    printf '%s\n' "ERROR: python3 not found and nix not available" >&2
    exit 1
fi

# Strip any embedded auth tokens so they never leak into the published tree.
sed -i 's|https://oauth2:[^@]*@github.com|https://github.com|g' "$readme_path" 2>/dev/null || true

git remote remove origin 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Build filter scripts as temp files instead of inline strings.
#    git-filter-branch passes strings through eval; quoting fights are
#    impossible to win reliably with double-quoted heredoc content.
# ---------------------------------------------------------------------------

env_filter_path="$(mktemp -t env_filter.XXXXXX)"
cat > "$env_filter_path" <<ENVFILTER
match_email=0
match_name=0
if [ -n '$rewrite_email_regex' ] && printf '%s\n' "\$GIT_AUTHOR_EMAIL" | grep -qiE '$rewrite_email_regex' 2>/dev/null; then
    match_email=1
fi
if [ -n '$rewrite_name_regex' ] && printf '%s\n' "\$GIT_AUTHOR_NAME" | grep -qiE '$rewrite_name_regex' 2>/dev/null; then
    match_name=1
fi
if [ "\$match_email" -eq 1 ] || [ "\$match_name" -eq 1 ]; then
    export GIT_AUTHOR_NAME='$commit_name'
    export GIT_AUTHOR_EMAIL='$commit_email'
    export GIT_COMMITTER_NAME='$commit_name'
    export GIT_COMMITTER_EMAIL='$commit_email'
fi
ENVFILTER

tree_filter_path="$(mktemp -t tree_filter.XXXXXX)"
cat > "$tree_filter_path" <<TREEFILTER
blacklist_path='${repo_root}/.mirror-blacklist'
if [ -f "\$blacklist_path" ]; then
    while IFS= read -r line; do
        [ -z "\$line" ] && continue
        case "\$line" in '#'* ) continue ;; esac
        rm -rf "\$line"
    done < "\$blacklist_path"
fi

whitelist_path='${repo_root}/.mirror-root-whitelist'
if [ -f "\$whitelist_path" ]; then
    whitelist=""
    while IFS= read -r line; do
        [ -z "\$line" ] && continue
        case "\$line" in '#'* ) continue ;; esac
        whitelist="\$whitelist \$line"
    done < "\$whitelist_path"

    for entry in .* *; do
        case "\$entry" in '.'|'..') continue ;; esac
        [ -f "\$entry" ] || continue
        case " \$whitelist " in
            *" \$entry "*) ;;
            *) rm -f "\$entry" ;;
        esac
    done
fi

rm -f .mirror-blacklist .mirror-root-whitelist

rm -f .sops.yaml settings.nix profiles/desktop/details.nix profiles/desktop/hardware-configuration.nix
if [ -d secrets/hosts ]; then
    find secrets/hosts -mindepth 1 -maxdepth 1 -type f -delete
fi
if [ -d secrets/users ]; then
    find secrets/users -mindepth 1 -maxdepth 1 -type f -delete
fi

cp -f settings.nix.example               settings.nix 2>/dev/null || true
cp -f profiles/desktop/details.nix.example profiles/desktop/details.nix 2>/dev/null || true
cp -f profiles/desktop/hardware-configuration.nix.example profiles/desktop/hardware-configuration.nix 2>/dev/null || true
cp -f .sops.yaml.example                 .sops.yaml 2>/dev/null || true

rm -f settings.nix.example
rm -f profiles/desktop/details.nix.example
rm -f profiles/desktop/hardware-configuration.nix.example
rm -f .sops.yaml.example

cp -f '${repo_root}/README.md.public' README.md 2>/dev/null || true
TREEFILTER

# Always run --parent-filter: strip cutoff parent if set, otherwise passthrough.
parent_filter_cmd="cat"
if [ -n "$cutoff_commit" ]; then
    # --parent-filter removes the cutoff commit as parent from the first
    # rewritten commit after the cutoff, creating a new root = clean history.
    #
    # git-filter-branch runs filters in a minimal subshell where `sed`
    # may not be available (observed in nixos/nix:2.26.1 containers).
    # We write a tiny standalone bash script instead of relying on sed.
    parent_filter_script="$(mktemp -t parent_filter.XXXXXX)"
    # shellcheck disable=SC2016
    printf '%s\n' "#!/usr/bin/env bash" \
                  "while IFS= read -r line; do" \
                  "    line=\"\${line//-p ${cutoff_commit}/}\"" \
                  "    printf '%s\\n' \"\$line\"" \
                  "done" > "$parent_filter_script"
    chmod +x "$parent_filter_script"
    parent_filter_cmd="$parent_filter_script"
fi

export FILTER_BRANCH_SQUELCH_WARNING=1

git filter-branch \
    --force \
    --parent-filter "$parent_filter_cmd" \
    --env-filter "source '$env_filter_path'" \
    --tree-filter "source '$tree_filter_path'" \
    --prune-empty \
    --tag-name-filter cat \
    -- --all

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

if [ "$force_push" = "true" ]; then
    git push --force github "HEAD:$branch"
    git push --force --tags github
else
    git push github "HEAD:$branch"
    git push --tags github
fi

# Done; cleanup runs via trap EXIT.
