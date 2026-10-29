# Selective Author Rewrite in Full filter-branch Mode

## Context

Implementation in commits 26ea799 → 7b42d13 → a105dbe → fcc80a6 → 3335d3f
(main branch, scripts/publish-public-github.sh).

## Problem

The `env-filter` in `git-filter-branch` rewrote **all** commits to the bot
identity (`PUBLIC_GITHUB_COMMIT_NAME` / `EMAIL`). This corrupted signatures
and lost attribution for commits by:
- Dependabot (merged PR -> signature broken)
- External contributors (donated code -> bot attribution)

## Solution evolution

| Commit | Change |
|---|---|
| 26ea799 | Single `PUBLIC_GITHUB_REWRITE_REGEX` (regex, matched both name and email) |
| 7b42d13 | Split into `REWRITE_EMAIL_REGEX` + `REWRITE_NAME_REGEX` (regex-based) |
| a105dbe | Comma-list input with regex auto-conversion |
| fcc80a6 | Replaced regex with **glob-pattern** matching (`*jonas*`) |
| **3335d3f** | **BREAKING: glob → exact-match for safety** (`jonas` only matches `jonas`, not `alt-jonas`) |

## Current API (3335d3f+)

### Unified across ALL scripts

As of commit `3335d3f`, the comma-list / **exact-match** approach is used by
**all** mirror scripts:

| Script | Variable (new) | Variable (old, deprecated) | Direction |
|---|---|---|---|
| `publish-public-github.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` | Full rewrite (filter-branch) |
| `mirror-sync-forward.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` | Incremental forward |
| `mirror-sync-backward.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` | Backward import |

The shared engine `scripts/lib/mirror-sanitize.sh` provides `ms_build_patterns()` and
`ms_should_match_patterns()` so all three scripts share identical behavior.

### Input format: comma-separated exact values (no wildcards, no regex)

```bash
PUBLIC_GITHUB_REWRITE_EMAILS="jonas.tschoche@gmx.de,me@codepixelstudio.de,me@example.invalid"
PUBLIC_GITHUB_REWRITE_NAMES="Jonas Tschoche"   # disabled by default
```

| Input | Resulting pattern list | Matches (exact equality) |
|---|---|---|
| `jonas.tschoche@gmx.de,me@codepixelstudio.de` | `jonas.tschoche@gmx.de\|me@codepixelstudio.de` | **only** these exact emails |
| `Jonas Tschoche` | `Jonas Tschoche` | **only** this exact name |
| `` (empty) | `___NO_MATCH_SENTINEL___` | nothing → all authors preserved |
| `me@example.com` | `me@example.com` | **only** `me@example.com`, NOT `alt-me@example.com` |

### Why exact-match instead of substring/glob

- **No false positives.** Substring matching (`*jonas*`) would match `alt-jonas@gmx.de`, `not-jonas@evil.com`, or any email containing the substring. Exact-match guarantees only the intended identities are rewritten.
- **No injection risk.** No regex or shell glob expansion in user-controlled input.
- **Predictable.** What you list is what gets matched — no hidden substring semantics.

> **Important:** The input is now a list of **complete** email addresses or names, not partial substrings. If you previously used `jonas,j0nix`, you must now expand to the full list of known addresses: `jonas.tschoche@gmx.de,me@codepixelstudio.de`.

### Drone secrets

| Secret | Replaces | Purpose |
|---|---|---|
| `public_github_rewrite_emails` | `public_sanitize_author_regex` | Exact email list for selective rewrite |
| `public_github_rewrite_names` | — | Exact name list (optional, disabled by default) |

Both support cascading fallback via `_FALLBACK` variants (see `references/public-cutoff-commit-workaround.md`).

## Implementation details

### shared engine: mirror-sanitize.sh

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
        # Trim whitespace
        item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$item" ] && continue
        result="${result:+${result}|}${item}"
    done
    [ -z "$result" ] && result="___NO_MATCH_SENTINEL___"
    echo "$result"
}

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

ms_should_sanitize_author() {
    local name="${1:-}"
    local email="${2:-}"

    # New mode: separate email/name exact lists
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

### filter-branch env-filter (publish-public-github.sh)

With exact-match, we **cannot** use bash `case` because `case` does not expand
variables as alternative patterns. We use a small inline function instead:

```bash
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
rewrite_emails_input="${PUBLIC_GITHUB_REWRITE_EMAILS:-${PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK:-}}"
rewrite_names_input="${PUBLIC_GITHUB_REWRITE_NAMES:-${PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK:-}}"

rewrite_email_patterns="$(ms_build_patterns "$rewrite_emails_input")"
rewrite_name_patterns="$(ms_build_patterns "$rewrite_names_input")"

export MS_SANITIZE_EMAIL_PATTERNS="$rewrite_email_patterns"
export MS_SANITIZE_NAME_PATTERNS="$rewrite_name_patterns"

# Build the env-filter as a heredoc — the function definition is embedded
# directly into the filter subshell.
env_filter="_match_patterns() {
    local val=\"\$1\" list=\"\$2\" item
    local saved_ifs=\"\$IFS\"
    IFS='|'
    for item in \$list; do
        IFS=\"\$saved_ifs\"
        [ \"\$val\" = \"\$item\" ] && return 0
    done
    IFS=\"\$saved_ifs\"
    return 1
}
match_email=0
match_name=0
_match_patterns \"\$GIT_AUTHOR_EMAIL\" \"$rewrite_email_patterns\" && match_email=1
_match_patterns \"\$GIT_AUTHOR_NAME\" \"$rewrite_name_patterns\" && match_name=1
if [ \"\$match_email\" -eq 1 ] || [ \"\$match_name\" -eq 1 ]; then
    export GIT_AUTHOR_NAME='$commit_name'
    export GIT_AUTHOR_EMAIL='$commit_email'
    export GIT_COMMITTER_NAME='$commit_name'
    export GIT_COMMITTER_EMAIL='$commit_email'
fi"
```

### Critical: how not to escape

Unlike the glob-pattern approach where `\$GIT_AUTHOR_EMAIL` was escaped to
prevent outer-shell expansion, with the inline-function approach the variables
`$GIT_AUTHOR_EMAIL` and `$GIT_AUTHOR_NAME` **must** be passed as literal `$`
into the heredoc/string so they are resolved at runtime in the filter subshell.

The pattern variables (`$rewrite_email_patterns`, `$rewrite_name_patterns`) are
expanded by the outer shell and baked into the string — they are constants from
the subshell's perspective.

### The ___NO_MATCH_SENTINEL___ trick

When no patterns are configured, `ms_build_patterns` returns a sentinel string
that never equals any actual commit metadata. This is safer than a truly empty
pattern list which could cause unexpected behavior in the loop.

## Pitfalls

### Exact-match migrates from "jonas" to full addresses

If you update from an older version, your Drone secret must change:

```bash
# OLD (glob/substring) — no longer valid
PUBLIC_GITHUB_REWRITE_EMAILS="jonas,j0nix"

# NEW (exact-match) — must list every known address
PUBLIC_GITHUB_REWRITE_EMAILS="jonas.tschoche@gmx.de,me@codepixelstudio.de,me@example.invalid"
```

Leaving the old short-form value will result in **zero matches** (nothing gets
rewritten) because "jonas" does not equal any real email address.

### Empty default is now safe

As of commit `3335d3f`, the default is empty (`""`) instead of `"jonas,j0nix"`.
When the secret is not set, **no commits are rewritten** — a safe fail-closed
behavior. You must explicitly configure the email list in Drone secrets.

### Case sensitivity

Exact-match is case-sensitive. If a contributor uses mixed-case emails across
different Git hosts, include every variant:

```bash
PUBLIC_GITHUB_REWRITE_EMAILS="Jonas@Example.com,jonas@example.com,JONAS@EXAMPLE.COM"
```

### Do not use regex or glob syntax

The old `^(jonas|j0nix)` and glob `*jonas*` syntaxes are no longer valid:

```bash
# WRONG — literal comparison: "^(jonas" never equals any real email
PUBLIC_GITHUB_REWRITE_EMAILS="^(jonas|j0nix)"

# WRONG — literal "*jonas*" never matches
PUBLIC_GITHUB_REWRITE_EMAILS="*jonas*"

# CORRECT
PUBLIC_GITHUB_REWRITE_EMAILS="jonas.tschoche@gmx.de,me@codepixelstudio.de"
```

## Related

- Section 8 "Selective Author Rewrite" in the main `repo-mirror-publishing/SKILL.md`
- `references/public-cutoff-commit-workaround.md` — Dual-key fallback pattern for Drone secrets
- `references/incremental-sync-scripts.md` — Full reproduction of `mirror-sanitize.sh`
