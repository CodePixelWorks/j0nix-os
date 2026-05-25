# mirror-sanitize.sh -- shared sanitization engine for Gitea -> GitHub mirror.
#
# Usage (source this file):
#   source "$(dirname "$0")/lib/mirror-sanitize.sh"
#
# Environment (must be set by caller):
#   SANITIZE_REPO_ROOT -- absolute path to source repo root
#
# Functions:
#   ms_init  repo_root
#   ms_should_sanitize_author  name  email
#   ms_apply_tree_filter  work_dir
#   ms_build_env_filter   commit_hash  output_var
#
# The caller is responsible for auth setup, temp dir management, and git push.

if [ "${__MIRROR_SANITIZE_SOURCED:-}" = "1" ]; then
    return 0
fi
__MIRROR_SANITIZE_SOURCED=1

# ============================================================================
# Defaults (caller can override before sourcing)
# ============================================================================
MS_SANITIZE_AUTHOR_NAME="${MS_SANITIZE_AUTHOR_NAME:-j0nix mirror bot}"
MS_SANITIZE_AUTHOR_EMAIL="${MS_SANITIZE_AUTHOR_EMAIL:-mirror@example.invalid}"
# New variables (pattern strings built by ms_build_patterns from comma-lists)
MS_SANITIZE_EMAIL_PATTERNS="${MS_SANITIZE_EMAIL_PATTERNS:-}"
MS_SANITIZE_NAME_PATTERNS="${MS_SANITIZE_NAME_PATTERNS:-}"
# Legacy fallback: if the old single-regex variable is still set, convert it
MS_SANITIZE_MATCH_REGEX="${MS_SANITIZE_MATCH_REGEX:-}"

# --- Build exact-match patterns from comma-separated email addresses ---
#   "me@example.com,you@domain.org" → "me@example.com|you@domain.org|..."
#   ""                              → "___NO_MATCH_SENTINEL___" (never matches)
ms_build_patterns() {
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

# ============================================================================
# ms_should_match_patterns -- return 0 if the value matches any pattern.
#
# Patterns is a pipe-separated list of exact strings built by ms_build_patterns.
# Each element in the list is compared as a separate pattern.
#
# Usage: ms_should_match_patterns "value" "foo|bar"
# ============================================================================
ms_should_match_patterns() {
    local value="$1"
    local patterns_str="$2"

    # Never match on placeholder sentinel
    [ "$patterns_str" = "___NO_MATCH_SENTINEL___" ] && return 1

    local p old_ifs="$IFS"
    IFS='|'
    for p in $patterns_str; do
        [ -z "$p" ] && continue
        case "$value" in
            $p)
                IFS="$old_ifs"
                return 0
                ;;
        esac
    done
    IFS="$old_ifs"
    return 1
}

# ============================================================================
# Init -- validate repo root, preload control files.
# ============================================================================
ms_init() {
    local repo_root="${1:?ms_init: repo_root required}"
    SANITIZE_REPO_ROOT="$repo_root"

    if [ ! -f "$repo_root/.mirror-blacklist" ]; then
        printf '%s\n' "WARN: .mirror-blacklist not found at $repo_root" >&2
    fi
    if [ ! -f "$repo_root/.mirror-root-whitelist" ]; then
        printf '%s\n' "WARN: .mirror-root-whitelist not found at $repo_root" >&2
    fi
}

# ============================================================================
# ms_should_sanitize_author -- return 0 if this author should be rewritten.
#
# Supports two input modes:
#   1. New: EMAIL_PATTERNS / NAME_PATTERNS set via ms_build_patterns from
#      comma-separated substrings.
#   2. Legacy: single MS_SANITIZE_MATCH_REGEX variable (regex via grep).
#
# If neither is configured, returns 1 (sanitize nothing = safety).
# ============================================================================
ms_should_sanitize_author() {
    local name="${1:-}"
    local email="${2:-}"

    # --- New mode: separate email/name pattern lists ---
    if [ -n "$MS_SANITIZE_EMAIL_PATTERNS" ] || [ -n "$MS_SANITIZE_NAME_PATTERNS" ]; then
        if [ -n "$MS_SANITIZE_EMAIL_PATTERNS" ] && ms_should_match_patterns "$email" "$MS_SANITIZE_EMAIL_PATTERNS"; then
            return 0
        fi
        if [ -n "$MS_SANITIZE_NAME_PATTERNS" ] && ms_should_match_patterns "$name" "$MS_SANITIZE_NAME_PATTERNS"; then
            return 0
        fi
        return 1
    fi

    # --- Legacy mode: single regex via grep ---
    [ -n "$MS_SANITIZE_MATCH_REGEX" ] || return 1

    if printf '%s\n' "$name" | grep -qiE "$MS_SANITIZE_MATCH_REGEX" 2>/dev/null; then
        return 0
    fi
    if printf '%s\n' "$email" | grep -qiE "$MS_SANITIZE_MATCH_REGEX" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ============================================================================
# ms_apply_tree_filter -- apply blacklist, whitelist, templates, README.
#
# Must be run inside a git worktree (the mirror clone).
# Reads control files from SANITIZE_REPO_ROOT (source tree), applies
# changes to the current directory.
# ============================================================================
ms_apply_tree_filter() {
    local work_dir="${1:-.}"
    local repo_root="${SANITIZE_REPO_ROOT:-}"

    if [ -z "$repo_root" ]; then
        printf '%s\n' "ERROR: ms_apply_tree_filter called without ms_init" >&2
        return 1
    fi

    (
        cd "$work_dir" || { printf '%s\n' "ERROR: cannot cd $work_dir" >&2; return 1; }

        # --- blacklist ---
        local blacklist_path="$repo_root/.mirror-blacklist"
        if [ -f "$blacklist_path" ]; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                case "$line" in \#*) continue ;; esac
                rm -rf "$line"
            done < "$blacklist_path"
        fi

        # --- whitelist ---
        local whitelist_path="$repo_root/.mirror-root-whitelist"
        if [ -f "$whitelist_path" ]; then
            local whitelist=""
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                case "$line" in \#*) continue ;; esac
                whitelist="$whitelist $line"
            done < "$whitelist_path"

            for entry in .* *; do
                case "$entry" in '.'|'..') continue ;; esac
                [ -f "$entry" ] || continue
                case " $whitelist " in
                    *" $entry "*) ;;
                    *) rm -f "$entry" ;;
                esac
            done
        fi

        # --- strip control files ---
        rm -f .mirror-blacklist .mirror-root-whitelist

        if [ -d secrets/hosts ]; then
            find secrets/hosts -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
        fi
        if [ -d secrets/users ]; then
            find secrets/users -mindepth 1 -maxdepth 1 -type f ! -name '*.example' -delete
        fi

        # --- inject public README ---
        if [ -f "$repo_root/README.md.public" ]; then
            cp -f "$repo_root/README.md.public" README.md 2>/dev/null || true
        fi
    )
}

# ============================================================================
# ms_sensitive_files_list -- list of file patterns that must never be
#     modified by external PRs in backward sync.
#
# Reads from .mirror-blacklist and adds hardcoded sensitive files.
# ============================================================================
ms_sensitive_files_list() {
    local repo_root="${SANITIZE_REPO_ROOT:-}"
    local patterns=""

    # Hardcoded sensitive files (exact paths, parent dirs)
    patterns="settings.nix
.sops.yaml
profiles/*/details.nix
profiles/*/hardware-configuration.nix
secrets/
.mirror-blacklist
.mirror-root-whitelist"

    # Add .mirror-blacklist entries
    if [ -f "$repo_root/.mirror-blacklist" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            patterns="$patterns
$line"
        done < "$repo_root/.mirror-blacklist"
    fi

    printf '%s\n' "$patterns" | sort -u
}

# ============================================================================
# ms_commit_is_safe -- check if a commit (by hash) only touches safe files.
#
# Returns 0 (safe) or 1 (touches sensitive files + lists them to stderr).
# Usage: ms_commit_is_safe <commit_hash>
# ============================================================================
ms_commit_is_safe() {
    local commit="${1:?ms_commit_is_safe: commit hash required}"
    local sensitive=""
    local bad=""

    # Build grep pattern from sensitive list
    sensitive="$(ms_sensitive_files_list | sed '/^$/d' | sed 's|/|\\/|g' | tr '\n' '|' | sed 's/|$//')"
    [ -n "$sensitive" ] || return 0  # nothing is sensitive

    bad="$(git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null | grep -iE "^($sensitive)" || true)"

    if [ -n "$bad" ]; then
        printf '%s\n' "SENSITIVE: $commit touches:" >&2
        printf '%s\n' "$bad" | while IFS= read -r f; do
            printf '  - %s\n' "$f" >&2
        done
        return 1
    fi
    return 0
}

# ============================================================================
# ms_build_env_filter -- output env-filter commands for a single commit.
#
# Reads the original author/committer from the commit, decides whether
# to rewrite identity, and prints export statements for
# GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL.
#
# Usage:
#   ms_build_env_filter <commit_hash> <output_var>
#   eval "${!output_var}"
# ============================================================================
ms_build_env_filter() {
    local commit="${1:?ms_build_env_filter: commit hash required}"
    local outvar="${2:?ms_build_env_filter: output variable name required}"

    local orig_name orig_email
    orig_name="$(git log -1 --format='%an' "$commit" 2>/dev/null || true)"
    orig_email="$(git log -1 --format='%ae' "$commit" 2>/dev/null || true)"

    local result=""

    if ms_should_sanitize_author "$orig_name" "$orig_email"; then
        result="
            export GIT_AUTHOR_NAME='${MS_SANITIZE_AUTHOR_NAME}'
            export GIT_AUTHOR_EMAIL='${MS_SANITIZE_AUTHOR_EMAIL}'
            export GIT_COMMITTER_NAME='${MS_SANITIZE_AUTHOR_NAME}'
            export GIT_COMMITTER_EMAIL='${MS_SANITIZE_AUTHOR_EMAIL}'
        "
    fi

    printf -v "$outvar" '%s' "$result"
}
