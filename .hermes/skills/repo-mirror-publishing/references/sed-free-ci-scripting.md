# Sed-Free CI Scripting

Drone CI runners using `nixos/nix` containers may ship without common POSIX utilities like `sed`, `grep`, or `awk` in the default PATH. This affects the parent shell where setup scripts run, not just the minimal subshells spawned by tools like `git-filter-branch`.

## `_safe_replace` — template substitution without sed

Drop this helper near the top of any CI script that generates temporary filter scripts or patches files in-place:

```bash
_safe_replace() {
    local file="$1" old="$2" new="$3"
    if command -v sed >/dev/null 2>&1; then
        sed -i "s|${old}|${new}|g" "$file"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace(sys.argv[2], sys.argv[3])
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$file" "$old" "$new"
    else
        printf '%s\n' "ERROR: neither sed nor python3 found" >&2
        exit 1
    fi
}
```

**When to use:**
- Templating `git-filter-branch` filter scripts (`--env-filter`, `--tree-filter`, `--commit-filter`, `--parent-filter`)
- Stripping auth tokens from generated files before publishing
- Any in-place file modification that would otherwise use `sed -i`

**Example — commit-filter GPG signing:**
```bash
commit_filter_path="$(mktemp -t commit_filter.XXXXXX)"
cat > "$commit_filter_path" <<'COMMITFILTER'
#!/usr/bin/env bash
mirror_email="REPLACE_MIRROR_EMAIL"
gpg_key="REPLACE_GPG_KEY_ID"
if [ "$GIT_AUTHOR_EMAIL" = "$mirror_email" ] && [ -n "$gpg_key" ]; then
    git commit-tree --gpg-sign="$gpg_key" "$@"
else
    git commit-tree "$@"
fi
COMMITFILTER
_safe_replace "$commit_filter_path" "REPLACE_MIRROR_EMAIL" "$commit_email"
_safe_replace "$commit_filter_path" "REPLACE_GPG_KEY_ID" "$gpg_key_id"
chmod +x "$commit_filter_path"
```

## Auth-token strip without sed

When a generated `README.md.public` may contain embedded PAT URLs, strip them with Python instead of `sed`:

```bash
if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import re, sys
with open(sys.argv[1], 'r') as f: content = f.read()
content = re.sub(r'https://oauth2:[^@]*@github\\.com', 'https://github.com', content)
with open(sys.argv[1], 'w') as f: f.write(content)
" "$readme_path" 2>/dev/null || true
elif command -v sed >/dev/null 2>&1; then
    sed -i 's|https://oauth2:[^@]*@github.com|https://github.com|g' "$readme_path" 2>/dev/null || true
fi
```

## Verification

Add these lines early in the CI step to confirm tool availability:

```bash
for tool in sed grep awk python3; do
    printf '%s: ' "$tool"
    command -v "$tool" >/dev/null 2>&1 && echo "yes" || echo "NO"
done
```

If `python3` is present but `sed` is not, the `_safe_replace` helper silently falls back. If both are missing, the script exits cleanly with a clear error before producing broken filter scripts.
