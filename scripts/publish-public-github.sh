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
#   PUBLIC_GITHUB_REQUIRE_SIGNING — "true" to fail when no signing key is loaded.
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
require_signing="${PUBLIC_GITHUB_REQUIRE_SIGNING:-false}"

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
    # shellcheck disable=SC2086 # Intentional split to reject multi-token cutoff values.
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

# Run sed, pulling it from nixpkgs if the host doesn't have it.
# Required in minimal CI containers (e.g. nixos/nix:2.26.1) where sed may
# be absent but Nix is available.
run_sed() {
    if command -v sed >/dev/null 2>&1; then
        command sed "$@"
    elif command -v nix >/dev/null 2>&1; then
        nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#gnused --command sed "$@"
    else
        printf '%s\n' "ERROR: sed not found and nix not available" >&2
        exit 1
    fi
}

ensure_gpg_available() {
    if command -v gpg >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v nix >/dev/null 2>&1; then
        printf '%s\n' "ERROR: gpg not found and nix not available" >&2
        exit 127
    fi

    local gpg_bin gpg_dir nix_output
    if ! nix_output="$(nix --extra-experimental-features 'nix-command flakes' shell --inputs-from "$repo_root" nixpkgs#gnupg --command sh -c 'command -v gpg' 2>&1)"; then
        printf '%s\n' "ERROR: could not make gnupg available through nix" >&2
        printf '%s\n' "$nix_output" >&2
        exit 127
    fi

    while IFS= read -r gpg_bin; do
        [ -n "$gpg_bin" ] || continue
        if [ -x "$gpg_bin" ]; then
            gpg_dir="${gpg_bin%/*}"
            export PATH="$gpg_dir:$PATH"
            git config --global gpg.program "$gpg_bin"
            return 0
        fi
    done <<< "$nix_output"

    printf '%s\n' "ERROR: gnupg shell did not report an executable gpg path" >&2
    printf '%s\n' "$nix_output" >&2
    exit 127
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
    ensure_gpg_available

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

    gpg_key_id=""
    while IFS=: read -r f1 _ _ _ f5 _; do
        if [ "$f1" = "sec" ]; then
            gpg_key_id="$f5"
            break
        fi
    done <<EOF
$(gpg --list-secret-keys --with-colons 2>/dev/null)
EOF
    if [ -n "$gpg_key_id" ]; then
        printf '%s\n' "GPG signing configured (key ${gpg_key_id:0:16}...)"

        # Preserve passphrase in a scoped variable so git/gpg pipelines can
        # sign headlessly without relying on fragile --edit-key removal.
        mirror_gpg_passphrase="${PUBLIC_GITHUB_SIGNING_PASSPHRASE:-}"
        if [ -n "$mirror_gpg_passphrase" ]; then
            unset PUBLIC_GITHUB_SIGNING_PASSPHRASE
            export MIRROR_GPG_PASSPHRASE="$mirror_gpg_passphrase"
        fi

        print_public_signing_key "$gpg_key_id"
        git config --global user.signingkey "$gpg_key_id"

        # gpg wrapper for headless signing. Git commit-tree and commit --gpg-sign
        # call gpg in non-batch mode; the wrapper injects passphrase so pinentry
        # never blocks in CI.
        gpg_wrapper="$gpg_dir/gpg-wrapper"
        cat > "$gpg_wrapper" <<'GPGWRAP'
#!/usr/bin/env bash
if [ -n "${MIRROR_GPG_PASSPHRASE:-}" ]; then
    exec gpg --pinentry-mode loopback --passphrase "$MIRROR_GPG_PASSPHRASE" "$@"
else
    exec gpg "$@"
fi
GPGWRAP
        chmod +x "$gpg_wrapper"
        git config --global gpg.program "$gpg_wrapper"

        # -------------------------------------------------------------------
        # Verify downloaded public key belongs to the imported private key.
        # -------------------------------------------------------------------
        if [ -n "${PUBLIC_GITHUB_SIGNING_PUBKEY_URL:-}" ]; then
            pubkey_temp="$(mktemp -t mirror_pubkey.XXXXXX)"
            if curl -fsSL "$PUBLIC_GITHUB_SIGNING_PUBKEY_URL" -o "$pubkey_temp" 2>/dev/null; then
                gpg --batch --import "$pubkey_temp" >/dev/null 2>&1 || true
                rm -f "$pubkey_temp"

                sec_fpr="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
                pub_fpr="$(gpg --list-keys       --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"

                if [ -z "$sec_fpr" ] || [ -z "$pub_fpr" ]; then
                    printf '%s\n' "ERROR: Could not determine GPG fingerprints for key verification" >&2
                    exit 1
                fi

                if [ "$sec_fpr" != "$pub_fpr" ]; then
                    printf '%s\n' "ERROR: Public key fingerprint (${pub_fpr:0:16}...) does not match private key fingerprint (${sec_fpr:0:16}...)" >&2
                    printf '%s\n' "Check PUBLIC_GITHUB_SIGNING_PUBKEY_URL and PUBLIC_GITHUB_SIGNING_KEY are a matching pair." >&2
                    exit 1
                fi

                printf '%s\n' "GPG public key verified: fingerprint ${sec_fpr:0:16}... matches"
            else
                printf '%s\n' "ERROR: Failed to download public key from ${PUBLIC_GITHUB_SIGNING_PUBKEY_URL}" >&2
                exit 1
            fi
        fi
    else
        printf '%s\n' "WARN: could not import GPG signing key" >&2
    fi
fi

if [ "$require_signing" = "true" ] && [ -z "$gpg_key_id" ]; then
    printf '%s\n' "ERROR: PUBLIC_GITHUB_REQUIRE_SIGNING=true but no GPG signing key was loaded." >&2
    printf '%s\n' "Ensure the Drone secret public_github_signing_key is available to this pipeline step." >&2
    exit 1
fi

if [ -n "$gpg_dir" ]; then
    export GNUPGHOME="$gpg_dir"
fi
export GIT_MIRROR_SIGNING_KEY="${gpg_key_id:-}"

# ---------------------------------------------------------------------------
# 2. Clone source repo into a temporary workspace.
# ---------------------------------------------------------------------------
work_dir="$(mktemp -d)"
readme_path="$repo_root/README.md.public"

# Temp path placeholders (set below)
env_filter_path=""
tree_filter_path=""
commit_filter_path=""
parent_filter_script=""

cleanup() {
    rm -rf "$work_dir"
    rm -f "$readme_path"
    [ -n "$ssh_key_path" ] && rm -f "$ssh_key_path" 2>/dev/null || true
    [ -n "$gpg_dir" ] && rm -rf "$gpg_dir" 2>/dev/null || true
    [ -n "${env_filter_path:-}" ] && rm -f "$env_filter_path" 2>/dev/null || true
    [ -n "${tree_filter_path:-}" ] && rm -f "$tree_filter_path" 2>/dev/null || true
    [ -n "${commit_filter_path:-}" ] && rm -f "$commit_filter_path" 2>/dev/null || true
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
run_sed -i 's#https://oauth2:[^@]*@github\.com#https://github.com#g' "$readme_path" 2>/dev/null || true

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
    find secrets/hosts -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
fi
if [ -d secrets/users ]; then
    find secrets/users -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
fi

cp -f '${repo_root}/README.md.public' README.md 2>/dev/null || true
TREEFILTER

commit_filter_path="$(mktemp -t commit_filter.XXXXXX)"
cat > "$commit_filter_path" <<'COMMITFILTER'
run_commit_filter() {
    local tree_id="$1"
    shift
    local original_args=("$@")

    local parent_hashes=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "-p" ] && [ $# -ge 2 ]; then
            parent_hashes+=("$2")
            shift 2
        else
            shift
        fi
    done

    # Prune empty commits (tree identical to any parent).
    # This replaces --prune-empty, which git-filter-branch forbids
    # when --commit-filter is active.
    if [ -n "$tree_id" ]; then
        for parent in "${parent_hashes[@]}"; do
            local ptree
            ptree=$(git rev-parse "$parent^{tree}" 2>/dev/null) || true
            if [ "$tree_id" = "$ptree" ]; then
                map "$parent"
                return 0
            fi
        done
    fi

    local mirror_email="REPLACE_MIRROR_EMAIL"
    local gpg_key="${GIT_MIRROR_SIGNING_KEY:-}"

    if [ -n "$gpg_key" ]; then
        if ! gpg --list-secret-keys "$gpg_key" >/dev/null 2>/dev/null; then
            printf '%s\n' "[commit-filter] ERROR: gpg key $gpg_key not found (GNUPGHOME=${GNUPGHOME:-})" >&2
            return 1
        fi
        git commit-tree --gpg-sign="$gpg_key" "$tree_id" "${original_args[@]}"
    else
        git commit-tree "$tree_id" "${original_args[@]}"
    fi
}

run_commit_filter "$@"
COMMITFILTER
run_sed -i "s#REPLACE_MIRROR_EMAIL#${commit_email}#g" "$commit_filter_path"

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
    run_sed -i "s#PFSCRIPT_CUTOFF#${cutoff_commit}#g" "$parent_filter_script"
    chmod +x "$parent_filter_script"
    parent_filter_args=(--parent-filter "$parent_filter_script")
fi

export FILTER_BRANCH_SQUELCH_WARNING=1

# Pre-test GPG signing before rewrite.
printf '%s\n' "--- GPG pre-test ---"
if [ -n "${gpg_key_id}" ] && [ -n "${gpg_dir}" ] && [ -d "${gpg_dir}" ]; then
    GNUPGHOME="${gpg_dir}" gpg --list-secret-keys "${gpg_key_id}" >/dev/null 2>/dev/null && \
        printf '%s\n' "GPG pre-test: key ${gpg_key_id:0:16}... found in GNUPGHOME" || \
        printf '%s\n' "GPG pre-test: key ${gpg_key_id:0:16}... NOT found"
    # Ensure gpg-agent is available inside the temp homedir before signing.
    GNUPGHOME="${gpg_dir}" gpg-agent --daemon 2>/dev/null || true
    # Direct signatures test with loopback so a remaining passphrase does not
    # silently deadlock pinentry in a non-interactive context.
    sign_stderr="$(mktemp -t gpg_sign_test.XXXXXX)"
    gpg_sign_test_args=()
    if [ -n "${MIRROR_GPG_PASSPHRASE:-}" ]; then
        gpg_sign_test_args=(--pinentry-mode loopback --passphrase "$MIRROR_GPG_PASSPHRASE")
    fi
    if printf '%s\n' "test body" | GNUPGHOME="${gpg_dir}" gpg --armor --detach-sign \
            --local-user="${gpg_key_id}" --batch "${gpg_sign_test_args[@]}" -o /dev/null 2>"$sign_stderr"; then
        printf '%s\n' "GPG pre-test: direct sign succeeded"
    else
        printf '%s\n' "ERROR: GPG pre-test direct sign failed"
        printf '%s\n' "--- GPG stderr ---"
        cat "$sign_stderr"
        printf '%s\n' "---"
        rm -f "$sign_stderr"
        exit 1
    fi
    rm -f "$sign_stderr"
else
    printf '%s\n' "GPG pre-test: no key loaded, skipping"
fi
printf '%s\n' "---"

git filter-branch \
    --force \
    "${parent_filter_args[@]}" \
    --env-filter "source '$env_filter_path'" \
    --tree-filter "source '$tree_filter_path'" \
    --commit-filter ". '$commit_filter_path'" \
    --tag-name-filter cat \
    -- --all

# filter-branch leaves refs in refs/original/ — drop them so they are
# not accidentally pushed and do not bloat the clone.
rm -rf .git/refs/original/

# ---------------------------------------------------------------------------
# 3b. GPG signing diagnostics.
#    Only commit-hash and key-ID are printed; author/committer emails are
#    already rewritten by the env-filter above.
# ---------------------------------------------------------------------------
printf '%s\n' "--- GPG signing diagnostics ---"
last_sigs=$(git log --all --format='%H|%G?|%GS' -5)
printf '%s\n' "$last_sigs"
unsigned_count=$(printf '%s\n' "$last_sigs" | grep -c '|N|') || true
if [ "${unsigned_count:-0}" = "0" ]; then
    printf '%s\n' "OK: all last 5 commits carry a GPG signature"
else
    printf '%s\n' "WARN: $unsigned_count of last 5 rewritten commits lack GPG signature"
    if [ -n "${gpg_key_id}" ]; then
        exit 1
    fi
fi
printf '%s\n' "---"

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
    amend_args=(--amend --no-edit --reset-author)
    if [ -n "$gpg_key_id" ]; then
        amend_args+=(--gpg-sign="$gpg_key_id")
    fi
    if ! GIT_COMMITTER_DATE="$(git log -1 --format=%cI)" git commit "${amend_args[@]}"; then
        if [ -n "$gpg_key_id" ]; then
            exit 1
        fi
    fi
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
