# Drone Starlark: Public Cutoff Commit Fallback Workaround

## Problem

In Drone CI Starlark, environment variables are defined as a JSON object. JSON keys must be unique — defining the same key twice causes a parse error.

```python
# WRONG — this is invalid JSON:
env = {
    "PUBLIC_CUTOFF_COMMIT": {"from_secret": "cutoff_commit"},
    "PUBLIC_CUTOFF_COMMIT": "abc123def...",  # Duplicate key!
}
```

## Solution

Use two distinct keys: one from the secret store, one as a static fallback.

```python
env = {
    "PUBLIC_CUTOFF_COMMIT": {"from_secret": "cutoff_commit"},
    "PUBLIC_CUTOFF_COMMIT_FALLBACK": "abc123def...",
}
```

In the shell script, resolve with cascading fallbacks:

```bash
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
```

## Why This Matters

When `PUBLIC_CUTOFF_COMMIT` is empty (secret not set, or set to empty string), the fallback value is used. This allows:
1. CI runners with the secret to override the default
2. Local test runs without the secret to use the fallback
3. Clean separation between runtime secret and static default

## Context

Learned while setting up the j0nix-os public mirror pipeline. Jonas uses Gitea + Drone CI, not Forgejo. The cutoff commit orphans all history before a stable architecture milestone.
