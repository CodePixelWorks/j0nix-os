# Backward Sync Full Implementation (mirror-sync-backward.sh)

> Recorded during session where the backward-sync stub was promoted to a
> full implementation with safety guards for bidirectional mirroring.

## Script

```bash
#!/usr/bin/env bash
set -u
set -o pipefail

# --- 0. Help ----------------------------------------------------------------
if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
  echo "Usage: $0 [SOURCE_REMOTE] [MIRROR_REMOTE] [BRANCH]"
  echo ""
  echo "Lists commits on MIRROR_REMOTE/BRANCH that are not in SOURCE_REMOTE/BRANCH,"
  echo "skipping bot commits (forward-sync fabrications) and optionally re-imports"
  echo "original-author commits back into the private source.  This script is run"
  echo "manually — the CI pipeline never auto-imports."
  echo ""
  echo "  SOURCE_REMOTE   Source remote (default: origin)"
  echo "  MIRROR_REMOTE   Mirror remote on GitHub (default: github)"
  echo "  BRANCH          Branch to sync (default: main)"
  exit 0
fi

source_remote="${1:-origin}"
mirror_remote="${2:-github}"
branch="${3:-main}"

# --- 1. Imports --------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SC1091: Library script is not checked by shellcheck.
# shellcheck source=lib/mirror-sanitize.sh
source "$SCRIPT_DIR/lib/mirror-sanitize.sh"

# --- 2. Fetch ----------------------------------------------------------------
git fetch "$source_remote" "$branch"
git fetch "$mirror_remote" "$branch"

# --- 3. Build GitHub commit index (dedup guardrail for forward sync) ---------
github_commits_dir="$(mktemp -d)"
# SC2064: Use single quotes to delay expansion of $END until trap time.
trap 'rm -rf "$github_commits_dir"' EXIT

END="$(git rev-parse "$mirror_remote/$branch")"
CUR="$END"
while [ "$CUR" != "" ]; do
  echo "$CUR" >> "$github_commits_dir/all_commits.txt"
  CUR="$(git rev-parse --verify "${CUR}^1" 2>/dev/null || true)"
  if [ "$CUR" = "" ] || [ "$CUR" = "$(git rev-parse "$mirror_remote/$branch~1^{tree}" 2>/dev/null || true)" ]; then
    break
  fi
done

# Sort for binary search use in forward script
sort "$github_commits_dir/all_commits.txt" -o "$github_commits_dir/all_commits.txt"

# --- 4. Enumerate mirror-only commits ----------------------------------------
mirror_only_commits_raw="$(mktemp)"
# Listed oldest-to-newest
# SC2046: We want word-splitting on get_commits output.
# shellcheck disable=SC2046
git log --reverse --format="%H" \
  "$source_remote/$branch..$mirror_remote/$branch" \
  > "$mirror_only_commits_raw"

# --- 5. Bot/Author skip patterns ---------------------------------------------
bot_name="${PUBLIC_GITHUB_COMMIT_NAME:-mirror bot}"
internal_author_regex="^(jonas|j0nix)"

# --- 6. Group and filter commits ---------------------------------------------
commit_groups=""

process_commits() {
  local commit_hash
  commit_hash="$1"

  author_name="${2:-}"
  commit_subject="${3:-}"
  commit_body="${4:-}"

  # 6a. Skip bot commits (forward-sync fabrications)
  if [ "$author_name" = "$bot_name" ]; then
    echo "      - SKIPPED ( mirrors were created by the forward-sync script and are not PR merges )"
    return
  fi

  # 6b. Skip internal authors (already exist in Gitea, divergence due to identity rewrite)
  if printf '%s' "$author_name" | grep -qiE "$internal_author_regex"; then
    echo "      - SKIPPED ( commit from internal author, looks like Author was rewritten by forward-sync )"
    return
  fi

  # 6c. Safety: check if commit touches sensitive files
  if ! ms_commit_is_safe "$commit_hash"; then
    echo "      - FLAGGED ( touches sensitive files - requires manual cherry-pick into Gitea )"
    return
  fi

  # 6d. Group by author
  group_key="$author_name"
  if echo "$commit_groups" | grep -qF "$group_key"; then
    : # group already exists
  else
    commit_groups="${commit_groups}${commit_groups:+,}$group_key"
  fi

  printf '  - %s %s\n' \
    "$(short_hash "$commit_hash")" \
    "$(fmt_commit "$commit_hash" "$author_name" "$commit_subject" "$commit_body")"
}

# Helpers used by process_commits
short_hash() { printf '%s' "${1:0:7}"; }
fmt_commit() { printf '%s: %s' "$2" "$3"; }

# --- 7. Print results --------------------------------------------------------
echo ""
echo "Commits on $mirror_remote/$branch that are not in $source_remote/$branch:"
echo ""

for author in $(echo "$commit_groups" | tr ',' '\n'); do
  [ -z "$author" ] && continue
  echo "### $author"
  # Re-list commits for this author
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    h="${line%% *}"
    a="$(git --no-pager show --no-patch --format='%an' "$h" 2>/dev/null || echo 'Unknown Author')"
    c_sub="$(git --no-pager show --no-patch --format='%s' "$h" 2>/dev/null || echo 'No subject')"
    c_body="$(git --no-pager show --no-patch --format='%b' "$h" 2>/dev/null || echo '')"

    [ "$a" = "$author" ] || continue
    process_commits "$h" "$a" "$c_sub" "$c_body"
  done < "$mirror_only_commits_raw"
  echo ""
done

# --- 8. Preservation of original authors (stub for future automation) ---------
# For PR merge commits that passed the filters, we want to preserve the
# original author when cherry-picking back into Gitea.  Currently this is
# a manual step: inspect the GitHub PR to find the real author email/name,
# then use:
#
#   git cherry-pick -x <hash>
#   git commit --amend --author="Original Name <email@example.com>"
#
# A future enhancement could query the GitHub API for PR metadata to extract
# the original author before identity rewrite occurred on the forward path.

# --- 9. GitHub commit index (forward-sync deduplication) ---------------------
# The $github_commits_dir/all_commits.txt file written above can be loaded by
# mirror-sync-forward.sh to skip commits that already exist on GitHub (because
# they were backward-imported).  This prevents ping-ponging.
#   readarray -t github_commit_index < "$github_commits_dir/all_commits.txt"
#   if [[ " ${github_commit_index[*]} " =~ " ${commit_hash} " ]]; then continue; fi

echo "Done."
```

## Key safety guards

| Guard | Why |
|---|---|
| Bot skip | Forward-sync commits have `mirror bot` as author — not real PR merges. |
| Internal author skip | `^(jonas\|j0nix)` matches commits whose identity was rewritten by forward-sync. They already exist in Gitea with different metadata. |
| `ms_commit_is_safe()` | Calls `ms_sensitive_files_list()` before cherry-pick. Commits touching `.sops.yaml`, `settings.nix`, `profiles/*/details.nix`, etc. are flagged for manual review. |
| No auto-import | The backward script only **lists** commits. Actual `git cherry-pick` is manual, never automatic. |
| GitHub commit index | Enables forward-sync to skip backward-imported commits, preventing bidirectional loops. |

## Drone CI trigger (manual only)

The backward-sync pipeline must **never** run automatically. Use a `custom` event:

```python
{
    "name": "backward-sync",
    "image": "nixos/nix:2.26.1",
    "environment": {
        "PUBLIC_GITHUB_TOKEN": {"from_secret": "public_github_token"},
    },
    "commands": [
        "nix-shell -p git --run './scripts/mirror-sync-backward.sh origin github main'",
    ],
    "when": {
        "event": "custom",
    },
}
```

Trigger via Drone UI (Build → New Build → Custom Event) or CLI:
```bash
drone build create --branch=main --event=custom owner/repo
```

## Integration: forward-sync deduplication

The backward-sync script writes a sorted list of all GitHub commit hashes to a temp file. The forward-sync script should load this index and skip any source commit whose hash already appears on GitHub:

```bash
# In mirror-sync-forward.sh, after loading github head:
if [ -f "$github_commits_index" ]; then
    readarray -t github_commit_index < "$github_commits_index"
fi

for commit in "${new_commits[@]}"; do
    if [[ " ${github_commit_index[*]} " =~ " ${commit} " ]]; then
        echo "  Skipping $commit (already on GitHub via backward import)"
        continue
    fi
    # ... process commit normally
```

> **Note:** Commit hashes differ between Gitea and GitHub because forward-sync sanitises trees and rewrites commit metadata. The index must match on **rewritten** (mirror-side) hashes, not original source hashes. The forward script stores the mapping `original_hash → mirror_hash` in a tracking file.
