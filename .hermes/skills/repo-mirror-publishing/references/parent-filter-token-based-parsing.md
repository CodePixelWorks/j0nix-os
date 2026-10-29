# Parent-Filter: Token-Based Parsing vs. String Substitution

## Synopsis

A `git-filter-branch` `--parent-filter` receives parent SHAs as a single
whitespace-separated string prefixed with `-p`:

```
-p <sha1> -p <sha2>
```

Using `sed` or bash string substitution (`${line//-p SHA/}`) to remove a
cutoff commit produces **whitespace artifacts** that collapse multiple
parents into a single invalid object name. The fix is token-based parsing
via `set -- $(cat)` and re-emitting only valid `-p <sha>` pairs.

## Why String Substitution Fails

```bash
# BROKEN — bash string substitution leaves whitespace artifacts
line="-p sha1 -p sha2"
line="${line//-p sha1/}"
echo "$line"
# Output: "  -p sha2"  (leading spaces — harmless but ugly)
#
# On merge commits where the cutoff is parent #2:
line="-p sha1 -p cutoff"
line="${line//-p cutoff/}"
echo "$line"
# Output: "-p sha1  "  (trailing spaces — harmless)
#
# But when the cutoff commit string is substituted via a variable
# and the script is generated with printf, subtle quoting bugs
# cause the entire line to be emitted as one token:
#   fatal: Not a valid object name 56e1aabb... 6ec3a232...
```

The `sed` variant has the same problem and is additionally unavailable in
filter-branch's minimal subshell (no `sed`, `grep`, `awk`).

## Token-Based Solution

```bash
parent_filter_script="$(mktemp -t parent_filter.XXXXXX)"
cat > "$parent_filter_script" <<'PFSH'
#!/usr/bin/env bash
while IFS= read -r line; do
    # Tokenize the parent line into individual arguments.
    set -- $(printf '%s' "$line")
    # Re-emit only valid -p <sha> pairs.
    while [ $# -ge 2 ]; do
        flag="$1"
        sha="$2"
        shift 2
        if [ "$flag" = "-p" ] && [ "$sha" != "CUTOFF_SHA" ]; then
            printf '%s %s\n' "$flag" "$sha"
        fi
    done
done
PFSH
chmod +x "$parent_filter_script"
```

### Why this works

| Input (`read`) | Tokens after `set --` | Output after filtering |
|---|---|---|
| `-p sha1` | `(-p, sha1)` | `-p sha1` (if not cutoff) |
| `-p sha1 -p sha2` | `(-p, sha1, -p, sha2)` | `-p sha1 -p sha2` |
| `-p cutoff` | `(-p, cutoff)` | *(nothing)* |
| `-p sha1 -p cutoff` | `(-p, sha1, -p, cutoff)` | `-p sha1` |
| Empty string | `()` | *(nothing)* |

The `shift 2` arithmetic exactly consumes the `-p <sha>` pair, so no
whitespace artifacts can survive. Merge commits with any number of parents
are handled correctly because the loop processes all tokens.

## Complete Integration in Publish Script

```bash
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"

parent_filter_path="$(mktemp -t parent_filter.XXXXXX)"
cat > "$parent_filter_path" <<PFSH
#!/usr/bin/env bash
while IFS= read -r line; do
    set -- \$(printf '%s' "\$line")
    while [ \$# -ge 2 ]; do
        flag="\$1"
        sha="\$2"
        shift 2
        if [ "\$flag" = "-p" ] && [ "\$sha" != "${cutoff_commit}" ]; then
            printf '%s %s\\n' "\$flag" "\$sha"
        fi
    done
done
PFSH
chmod +x "$parent_filter_path"

git filter-branch \
    --force \
    --parent-filter "$parent_filter_path" \
    --env-filter "source $env_filter_path" \
    --tree-filter "source $tree_filter_path" \
    --prune-empty \
    --tag-name-filter cat \
    -- --all

rm -f "$parent_filter_path"
```

**Note on heredoc quoting:** The outer `cat` uses `<<PFSH` (unquoted)
because `${cutoff_commit}` must be interpolated at script-generation time.
All shell metacharacters inside (`$line`, `$#`, `$1`, `$2`) are escaped
with backslash so they survive into the generated file and are expanded at
filter runtime, not at generation time.

## Comparison

| Approach | Merge commits | Minimal subshell | Whitespace-safe |
|---|---|---|---|
| `sed` | ❌ Brittle | ❌ `sed` unavailable | ❌ |
| `${line//pattern/}` | ⚠️ Works for simple cases | ✅ Pure bash | ❌ Artifacts |
| **Token-based (`set --`)** | ✅ Any number of parents | ✅ Pure bash | ✅ Exact pairs |

## Verification

```bash
# Test the filter script against sample inputs
echo '-p sha1 -p cutoff -p sha2' | bash "$parent_filter_path"
# Expected: -p sha1
#           -p sha2

# Test with merge commit (two parents, neither is cutoff)
echo '-p sha1 -p sha2' | bash "$parent_filter_path"
# Expected: -p sha1
#           -p sha2

# Test with single-parent commit
echo '-p sha1' | bash "$parent_filter_path"
# Expected: -p sha1
```
