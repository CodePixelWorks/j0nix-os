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
MS_SANITIZE_MATCH_REGEX="${MS_SANITIZE_MATCH_REGEX:-^(jonas|j0nix)}"

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
# Policy: Only rewrite authors that match the configured regex (default:
#     jonas / j0nix).  External contributors (Dependabot, GitHub Actions,
#     or manual PR merges) keep their original identity.
# ============================================================================
ms_should_sanitize_author() {
    local name="${1:-}"
    local email="${2:-}"

    # Empty regex = sanitize nothing (safety)
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

        # --- strip + template substitution ---
        rm -f .sops.yaml settings.nix profiles/desktop/details.nix profiles/desktop/hardware-configuration.nix

        if [ -d secrets/hosts ]; then
            find secrets/hosts -mindepth 1 -maxdepth 1 -type f -delete
        fi
        if [ -d secrets/users ]; then
            find secrets/users -mindepth 1 -maxdepth 1 -type f -delete
        fi

        cp -f settings.nix.example settings.nix 2>/dev/null || true
        cp -f profiles/desktop/details.nix.example profiles/desktop/details.nix 2>/dev/null || true
        cp -f profiles/desktop/hardware-configuration.nix.example profiles/desktop/hardware-configuration.nix 2>/dev/null || true
        cp -f .sops.yaml.example .sops.yaml 2>/dev/null || true

        rm -f settings.nix.example profiles/desktop/details.nix.example profiles/desktop/hardware-configuration.nix.example .sops.yaml.example

        # --- inject public README ---
        if [ -f "$repo_root/README.md.public" ]; then
            cp -f "$repo_root/README.md.public" README.md 2>/dev/null || true
        fi
    )
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
            export GIT_AUTHOR_NAME='$MS_SANITIZE_AUTHOR_NAME'
            export GIT_AUTHOR_EMAIL='$MS_SANITIZE_AUTHOR_EMAIL'
            export GIT_COMMITTER_NAME='$MS_SANITIZE_AUTHOR_NAME'
            export GIT_COMMITTER_EMAIL='$MS_SANITIZE_AUTHOR_EMAIL'
        "
    fi

    printf -v "$outvar" '%s' "$result"
}
