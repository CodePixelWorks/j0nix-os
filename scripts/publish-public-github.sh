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
#   PUBLIC_GITHUB_REWRITE_EMAILS   -- Comma-separated list of exact email
#                                      addresses to match for selective author
#                                      rewrite (e.g. "a@x.com,b@y.de").
#                                      Default: empty (no rewrite)         (from_secret)
#   PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK -- Fallback when secret unset.
#   PUBLIC_GITHUB_REWRITE_NAMES    -- Optional. Same for exact author names.
#                                      Disabled by default.                  (from_secret)
#   PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK — Fallback when secret unset.
#   PUBLIC_CUTOFF_COMMIT         — Optional. Commits BEFORE this hash are
#                                    removed entirely from mirror history.
#   PUBLIC_CUTOFF_COMMIT_FALLBACK — Fallback when the above secret is unset.
#   PUBLIC_GITHUB_FORCE_PUSH     — "true" (default) to force-push + force-push tags.
#                                    Set to "false" to push non-destructively.
#                                    Disabling force may fail if history diverged.
#   PUBLIC_GITHUB_SIGNING_KEY    — Optional GPG private key for diagnostics in CI.
#   PUBLIC_GITHUB_SIGNING_PASSPHRASE — Optional passphrase for the signing key above.
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
rewrite_emails_input="${PUBLIC_GITHUB_REWRITE_EMAILS:-${PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK:-}}"
rewrite_names_input="${PUBLIC_GITHUB_REWRITE_NAMES:-${PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK:-}}"

# --- Build exact-match patterns from comma-separated email addresses ---
#   "me@x.com,you@y.de"  → "me@x.com|you@y.de"
#   "me@x.com"           → "me@x.com"
#   ""                   → "___NO_MATCH_SENTINEL___" (never matches)
_build_patterns() {
    local input="$1"
    if [ -z "$input" ]; then
        echo "___NO_MATCH_SENTINEL___"
        return
    fi
    local result="" item
    IFS=','
    for item in $input; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [ -z "$item" ] && continue
        result="${result:+${result}|}${item}"
    done
    if [ -z "$result" ]; then
        result="___NO_MATCH_SENTINEL___"
    fi
    echo "$result"
}

rewrite_email_patterns="$(_build_patterns "$rewrite_emails_input")"
rewrite_name_patterns="$(_build_patterns "$rewrite_names_input")"

cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
force_push="${PUBLIC_GITHUB_FORCE_PUSH:-true}"

repo_root="$(git rev-parse --show-toplevel)"

print_public_signing_key() {
    local key_id="${1:-}"
    [ -n "$key_id" ] || return 0

    printf '%s\n' "GPG public key (ASCII-armored):"
    gpg --armor --export "$key_id"
    printf '%s\n' ""
}

normalize_cutoff_commit() {
    local raw="${1:-}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"

    [ -n "$raw" ] || return 0

    # Reject accidental multi-line or space-separated secret values early.
    # If the configured cutoff is malformed, warn and ignore it instead of
    # breaking the whole mirror publish run.
    set -- $raw
    if [ "$#" -ne 1 ]; then
        printf '%s\n' "WARN: PUBLIC_CUTOFF_COMMIT must contain exactly one commit hash/ref; ignoring invalid value: $raw" >&2
        return 0
    fi

    if ! git -C "$repo_root" rev-parse --verify "${1}^{commit}" >/dev/null 2>&1; then
        printf '%s\n' "WARN: PUBLIC_CUTOFF_COMMIT does not resolve to a valid commit; ignoring value: $1" >&2
        return 0
    fi

    printf '%s\n' "$1"
}

cutoff_commit="$(normalize_cutoff_commit "$cutoff_commit")"

# ---------------------------------------------------------------------------
# 1. Auth method: PAT (HTTPS) preferred; SSH fallback.
# ---------------------------------------------------------------------------
git_auth_remote="$remote_url"
ssh_key_path=""
gpg_key_id=""
gpg_dir=""

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

if [ -n "${PUBLIC_GITHUB_SIGNING_KEY:-}" ]; then
    gpg_dir="$(mktemp -d -t mirror_gpg.XXXXXX)"
    chmod 700 "$gpg_dir"
    export GNUPGHOME="$gpg_dir"

    if [ -n "${PUBLIC_GITHUB_SIGNING_PASSPHRASE:-}" ]; then
        printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | \
            gpg --batch --pinentry-mode loopback \
                --passphrase "$PUBLIC_GITHUB_SIGNING_PASSPHRASE" \
                --import 2>/dev/null
    else
        printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | gpg --batch --import 2>/dev/null
    fi

    gpg_key_id="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec/{print $5}' | head -n1)"
    if [ -n "$gpg_key_id" ]; then
        printf '%s\n' "GPG signing key loaded for diagnostics (key ${gpg_key_id:0:16}...)"
        print_public_signing_key "$gpg_key_id"
        unset PUBLIC_GITHUB_SIGNING_PASSPHRASE
    else
        printf '%s\n' "WARN: could not import GPG signing key" >&2
    fi
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
    [ -n "$gpg_dir" ] && rm -rf "$gpg_dir" 2>/dev/null || true
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
rewrite_email_list='$rewrite_email_patterns'
rewrite_name_list='$rewrite_name_patterns'
should_rewrite=0

_check_match() {
    local value="\$1"
    local list="\$2"
    [ -z "\$list" ] && return 1
    [ "\$list" = "___NO_MATCH_SENTINEL___" ] && return 1
    local p old_ifs="\$IFS"
    IFS='|'
    for p in \$list; do
        [ -z "\$p" ] && continue
        if [ "\$value" = "\$p" ]; then
            IFS="\$old_ifs"
            return 0
        fi
    done
    IFS="\$old_ifs"
    return 1
}

if _check_match "\$GIT_AUTHOR_EMAIL" "\$rewrite_email_list"; then
    should_rewrite=1
fi
if _check_match "\$GIT_AUTHOR_NAME" "\$rewrite_name_list"; then
    should_rewrite=1
fi

if [ "\$should_rewrite" -eq 1 ]; then
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

cp -f '${repo_root}/README.md.public' README.md 2>/dev/null || true
TREEFILTER

parent_filter_args=()
if [ -n "$cutoff_commit" ]; then
    # --parent-filter removes the cutoff commit as parent from the first
    # rewritten commit after the cutoff, creating a new root = clean history.
    #
    # git-filter-branch runs filters in a minimal subshell where `sed`
    # may not be available (observed in nixos/nix:2.26.1 containers).
    # We write a tiny standalone bash script instead of relying on sed.
    # parent-filter removes the cutoff commit as parent, creating a new root.
    # git-filter-branch passes space-separated -p <sha> tokens on one line.
    parent_filter_script="$(mktemp -t parent_filter.XXXXXX)"
    cat > "$parent_filter_script" <<'PFSCRIPT'
#!/usr/bin/env bash
cutoff_sha="PFSCRIPT_CUTOFF"
read -r raw_line || raw_line=""
set -- $raw_line

# filter-branch passes a rev-list --parents style line:
#   <commit> <parent1> <parent2> ...
# commit-tree expects:
#   -p <parent1> -p <parent2> ...
#
# Skip the commit itself and rebuild the parent flags explicitly.
if [ $# -gt 0 ]; then
    shift
fi

result=""
while [ $# -gt 0 ]; do
    if [ "$1" = "$cutoff_sha" ]; then
        shift
        continue
    fi
    result="$result -p $1"
    shift
done
printf '%s\n' "${result# }"
PFSCRIPT
    # shellcheck disable=SC2016
    sed -i "s/PFSCRIPT_CUTOFF/${cutoff_commit}/g" "$parent_filter_script"
    chmod +x "$parent_filter_script"
    parent_filter_args=(--parent-filter "$parent_filter_script")
fi

export FILTER_BRANCH_SQUELCH_WARNING=1

git filter-branch \
    --force \
    "${parent_filter_args[@]}" \
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
