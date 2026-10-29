# PAT URL Placeholder Bug (Literal `***` in Auth String)

## Synopsis

When adapting PAT-embedded HTTPS URLs from redacted examples or LLM
outputs, a common copy-paste error leaves the literal string `***` in
place of the variable interpolation `${PUBLIC_GITHUB_TOKEN}`. This
causes `git push` to fail with `Invalid username or token` even when
the secret is correctly injected.

## Reproduction

```bash
# BROKEN — copied from redacted log output
case "$remote_url" in
    git@github.com:*)
        repo_path="${remote_url#git@github.com:}"
        git_auth_remote="https://oauth2:***@github.com/${repo_path}"
        ;;
esac

# Result:
# remote: Invalid username or token.
# fatal: Authentication failed for 'https://github.com/CodePixelWorks/j0nix-os.git/'
```

## Why the agent could not spot it visually

When a secret named `PUBLIC_GITHUB_TOKEN` is configured in the agent
environment, its value is masked as `***` in terminal output. This makes
the literal `***` string and the correct `${PUBLIC_GITHUB_TOKEN}`
interpolation **both render identically** in `cat`, `grep`, and
`git diff` output.

| Actual file content | Terminal display | Interpretation |
|---|---|---|
| `oauth2:${PUBLIC_GITHUB_TOKEN}@github.com` | `oauth2:***@github.com` | Correct (value masked) |
| `oauth2:***@github.com` | `oauth2:***@github.com` | Broken (literal placeholder) |

The agent cannot distinguish the two by reading terminal output alone.

## Terminal-safe verification

### Method 1: grep for literal asterisks

```bash
# Search for the exact three-asterisk literal
grep -F 'oauth2:***@' scripts/*.sh
# Any match = a broken auth path
```

### Method 2: hexdump

```bash
# Check for 0x2a (asterisk) in the auth URL patterns
hexdump -C scripts/publish-public-github.sh | grep '2a 2a 2a'
# Empty output = no literal *** in the file
```

### Method 3: Python (reliable, no heuristic ambiguity)

```python
with open("scripts/publish-public-github.sh") as f:
    content = f.read()

# Look for literal asterisks in oauth2: URLs
if "oauth2:***" in content:
    print("BUG: literal *** found")
else:
    print("OK: no literal *** (value may be masked in output)")
```

## Fix

Replace every literal `***` with the variable interpolation:

```bash
case "$remote_url" in
    https://github.com/*)
        git_auth_remote="${remote_url/https:\/\//https:\/\/oauth2:${PUBLIC_GITHUB_TOKEN}@}"
        ;;
    git@github.com:*)
        repo_path="${remote_url#git@github.com:}"
        git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@github.com/${repo_path}"
        ;;
    *)
        printf '%s\n' "WARN: Unknown remote_url format; embedding PAT" >&2
        git_auth_remote="https://oauth2:${PUBLIC_GITHUB_TOKEN}@${remote_url#*://}"
        ;;
esac
```

## Scope of impact

Scripts using the `oauth2:...` auth pattern must ALL be audited. In the
j0nix-os repo these are:

- `scripts/publish-public-github.sh`
- `scripts/mirror-sync-forward.sh`
- `scripts/mirror-sync-backward.sh`

Fixing one does NOT fix the others.

## Prevention

1. Add a repo-wide CI check that greps for `oauth2:\*\*\*` in committed files.
2. When copying from redacted logs, verify with `hexdump` or Python.
3. Prefer `sed`/`perl` replacement over manual copy-paste for auth strings.
