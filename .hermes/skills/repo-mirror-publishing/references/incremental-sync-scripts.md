# Incremental Safe-Sync Scripts (mirror-sync-forward.sh, mirror-sync-backward.sh, mirror-sanitize.sh)

> Reproduced from commits 3335d3f+ where all three scripts use **exact-match**
> identity comparison. The shared engine (`mirror-sanitize.sh`) converts
> comma-separated values to a pipe-separated list; `ms_should_match_patterns()`
> iterates the list and checks `[ "$value" = "$pattern" ]` (exact equality).

---

## 1. mirror-sanitize.sh (shared engine)

The shared library is `scripts/lib/mirror-sanitize.sh`. It does NOT run
standalone; it must be sourced by the forward/backward scripts.

Key functions:
- `ms_build_patterns("jonas.tschoche@gmx.de,me@codepixelstudio.de")` → `"jonas.tschoche@gmx.de|me@codepixelstudio.de"`
- `ms_should_match_patterns(value, patterns)` → loop over `|`-separated list, exact string comparison, returns 0/1
- `ms_should_sanitize_author(name, email)` → checks EMAIL_PATTERNS then NAME_PATTERNS; falls back to legacy `MS_SANITIZE_MATCH_REGEX` (grep-based) if the new variables are unset.
- `ms_apply_tree_filter(work_dir)` → blacklist, whitelist, templates, README
- `ms_commit_is_safe(commit_hash)` → checks if commit touches sensitive files
- `ms_build_env_filter(commit_hash, outvar)` → builds export statements for git-filter-branch env-filter use

### Pattern building (exact-match, no globs)

```bash
ms_build_patterns() {
    local input="$1"
    if [ -z "$input" ]; then
        echo "___NO_MATCH_SENTINEL___"
        return
    fi
    local result="" item
    IFS=','
    for item in $input; do
        [ -z "$item" ] && continue
        item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$item" ] && continue
        result="${result:+${result}|}${item}"
    done
    [ -z "$result" ] && result="___NO_MATCH_SENTINEL___"
    echo "$result"
}
```

Note: the `*${item}*` glob wrapper from the old implementation was removed.
The result is a bare pipe-separated list (`foo|bar`), and each element is
compared with exact `[ "$value" = "$item" ]` equality.

### Pattern matching

```bash
ms_should_match_patterns() {
    local value="$1"
    local patterns="$2"
    local item
    local saved_ifs

    if [ "$patterns" = "___NO_MATCH_SENTINEL___" ]; then
        return 1
    fi

    saved_ifs="$IFS"
    IFS='|'
    for item in $patterns; do
        IFS="$saved_ifs"
        [ "$value" = "$item" ] && return 0
    done
    IFS="$saved_ifs"
    return 1
}
```

### Author matching

```bash
ms_should_sanitize_author() {
    local name="${1:-}"
    local email="${2:-}"

    # New mode: separate exact email/name lists
    if [ -n "$MS_SANITIZE_EMAIL_PATTERNS" ] || [ -n "$MS_SANITIZE_NAME_PATTERNS" ]; then
        if [ -n "$MS_SANITIZE_EMAIL_PATTERNS" ] && ms_should_match_patterns "$email" "$MS_SANITIZE_EMAIL_PATTERNS"; then
            return 0
        fi
        if [ -n "$MS_SANITIZE_NAME_PATTERNS" ] && ms_should_match_patterns "$name" "$MS_SANITIZE_NAME_PATTERNS"; then
            return 0
        fi
        return 1
    fi

    # Legacy fallback (grep-based regex — deprecated)
    [ -n "$MS_SANITIZE_MATCH_REGEX" ] || return 1
    if printf '%s\n' "$name" | grep -qiE "$MS_SANITIZE_MATCH_REGEX" 2>/dev/null; then return 0; fi
    if printf '%s\n' "$email" | grep -qiE "$MS_SANITIZE_MATCH_REGEX" 2>/dev/null; then return 0; fi
    return 1
}
```

---

## 2. mirror-sync-forward.sh

> **Note on the `_FALLBACK` pattern:** Drone CI cannot define the same JSON key
> twice (once as `from_secret`, once as plain constant). The Starlark uses two
> distinct keys per variable; the shell resolves the nested fallback.
> Beware: a secret may be "injected but empty" (blank UI field).`${VAR:-}` yields
> `""` which is a legal "no-rewrite" config. The `_FALLBACK` keys give a static
> default only when the secret itself is absent entirely.

```bash
#!/usr/bin/env bash
set -euo pipefail

remote_url="${1:?usage: mirror-sync-forward.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

tag="${PUBLIC_SYNC_TAG:-last-synced-from-gitea}"
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
rewrite_emails="${PUBLIC_GITHUB_REWRITE_EMAILS:-${PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK:-}}"
rewrite_names="${PUBLIC_GITHUB_REWRITE_NAMES:-${PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK:-}}"
identity_mode="${PUBLIC_GITHUB_IDENTITY_MODE:-selective}"

repo_root="$(git rev-parse --show-toplevel)"
```
# ... (auth setup, gpg signing, clone, README generation)
# ... (load shared engine, build patterns, discover sync base)
# ... (check each commit: cherry-pick, tree filter, decide rewrite)

    if [ "$should_rewrite" -eq 1 ]; then
        # BOTH author and committer rewritten to bot identity
        GIT_AUTHOR_DATE="$commit_date" \
        GIT_COMMITTER_DATE="$commit_date" \
        GIT_AUTHOR_NAME="$commit_name" \
        GIT_AUTHOR_EMAIL="$commit_email" \
        GIT_COMMITTER_NAME="$commit_name" \
        GIT_COMMITTER_EMAIL="$commit_email" \
            git commit --allow-empty $([ -n "$gpg_key_id" ] && echo "-S") -m "$commit_msg"
    else
        # keep original identity (preserve mode or no pattern match)
        GIT_AUTHOR_DATE="$commit_date" \
        GIT_COMMITTER_DATE="$commit_date" \
        GIT_AUTHOR_NAME="$author_name" \
        GIT_AUTHOR_EMAIL="$author_email" \
        GIT_COMMITTER_NAME="$committer_name" \
        GIT_COMMITTER_EMAIL="$committer_email" \
            git commit --allow-empty $([ -n "$gpg_key_id" ] && echo "-S") -m "$commit_msg"
    fi
```

---

## 2. mirror-sync-forward.sh

> **Note on the `_FALLBACK` pattern:** Drone CI cannot define the same JSON key
> twice (once as `from_secret`, once as plain constant). The Starlark uses two
> distinct keys per variable; the shell resolves the nested fallback.
> Beware: a secret may be "injected but empty" (blank UI field).`${VAR:-}` yields
> `""` which is a legal "no-rewrite" config. The `_FALLBACK` keys give a static
> default only when the secret itself is absent entirely.

```bash
#!/usr/bin/env bash
set -euo pipefail

remote_url="${1:?usage: mirror-sync-forward.sh REMOTE_URL [BRANCH]}"
branch="${2:-main}"

tag="${PUBLIC_SYNC_TAG:-last-synced-from-gitea}"
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
rewrite_emails="${PUBLIC_GITHUB_REWRITE_EMAILS:-${PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK:-}}"
rewrite_names="${PUBLIC_GITHUB_REWRITE_NAMES:-${PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK:-}}"
identity_mode="${PUBLIC_GITHUB_IDENTITY_MODE:-selective}"

repo_root="$(git rev-parse --show-toplevel)"
```
MS_SANITIZE_AUTHOR_NAME="$bot_name"
MS_SANITIZE_AUTHOR_EMAIL="$bot_email"
MS_SANITIZE_EMAIL_PATTERNS="$(ms_build_patterns "$rewrite_emails")"
MS_SANITIZE_NAME_PATTERNS="$(ms_build_patterns "$rewrite_names")"

# For each GitHub-only commit:
#   skip bot commits (forward-sync artifacts)
#   skip authors matching MS_SANITIZE_*_PATTERNS (already in Gitea)
#   check ms_commit_is_safe (no sensitive files touched)
#   apply safe diff, commit with original identity
#   push to Gitea
```

---

## Usage patterns

### Drone CI step for forward sync

```python
{
    "name": "forward-sync",
    "image": "nixos/nix:2.26.1",
    "environment": {
        "PUBLIC_GITHUB_TOKEN": {"from_secret": "public_github_token"},
        "PUBLIC_GITHUB_COMMIT_NAME": {"from_secret": "public_github_commit_name"},
        "PUBLIC_GITHUB_COMMIT_EMAIL": {"from_secret": "public_github_commit_email"},
        "PUBLIC_GITHUB_REWRITE_EMAILS": {"from_secret": "public_github_rewrite_emails"},
        "PUBLIC_GITHUB_REWRITE_NAMES": {"from_secret": "public_github_rewrite_names"},
    },
    "commands": [
        "./scripts/mirror-sync-forward.sh",
    ],
}
```

### Drone CI step for backward sync

```python
{
    "name": "import-github-prs",
    "image": "nixos/nix:2.26.1",
    "environment": {
        "PUBLIC_GITHUB_REMOTE": {"from_secret": "public_github_remote"},
        "PUBLIC_GITHUB_BRANCH": {"from_secret": "public_github_branch"},
        "PUBLIC_GITHUB_COMMIT_NAME": {"from_secret": "public_github_commit_name"},
        "PUBLIC_GITHUB_COMMIT_EMAIL": {"from_secret": "public_github_commit_email"},
        "PUBLIC_GITHUB_TOKEN": {"from_secret": "public_github_token"},
        "PUBLIC_GITHUB_PRIVATE_KEY": {"from_secret": "public_github_private_key"},
        "PUBLIC_SYNC_TAG": {"from_secret": "public_sync_tag"},
        "PUBLIC_GITHUB_REWRITE_EMAILS": {"from_secret": "public_github_rewrite_emails"},
        "PUBLIC_GITHUB_REWRITE_NAMES": {"from_secret": "public_github_rewrite_names"},
        "PUBLIC_GITHUB_SIGNING_KEY": {"from_secret": "public_github_signing_key"},
    },
    "commands": [
        "./scripts/mirror-sync-backward.sh",
    ],
}
```

### Manual dry-run

```bash
# Check what would be synced without pushing
PUBLIC_CUTOFF_COMMIT="$(git rev-parse HEAD~10)" bash -n scripts/mirror-sync-forward.sh
git log --oneline "$(git rev-parse HEAD~10)..HEAD"
```
