# CI / Public Mirror Pipeline

This document covers the Drone CI pipeline that publishes a sanitized,
secrets-stripped mirror of this repository to GitHub.

---

## Overview

There are **two directions** of sync and **two modes** of forward sync:

| Direction | Script | Purpose |
|-----------|--------|---------|
| **Forward** (Gitea → GitHub) | `publish-public-github.sh` | Full history rewrite via `git filter-branch` |
| **Forward** (Gitea → GitHub) | `mirror-sync-forward.sh` | Incremental: only new commits since last sync |
| **Backward** (GitHub → Gitea) | `mirror-sync-backward.sh` | Import external PR commits safely |

Both forward scripts use the shared sanitisation engine at
`scripts/lib/mirror-sanitize.sh`.

The pipeline is defined in `.drone.star` and runs in a `nixos/nix:2.26.1`
container.

---

## Forward Sync Modes

Selectable via the `public_mirror_mode` plain env / secret.

### `full` (default)

`publish-public-github.sh` performs a **destructive but complete** rewrite:

- Clones the repo into a temp workspace
- Runs `git filter-branch` over **all** commits since the cutoff (or the
  entire history if no cutoff is set)
- Strips files listed in `.mirror-blacklist`
- Strips root files not listed in `.mirror-root-whitelist` (safety net)
- Replaces sensitive files with `.example` templates
- Injects the public-facing `README.md.public` into every commit
- Rewrites commit author/committer identity **selectively**
- **Force-pushes** branch + tags to GitHub

Use this for the initial setup and after structural changes (blacklist updates,
cutoff changes, etc.).

### `incremental`

`mirror-sync-forward.sh` performs a **non-destructive** sync:

- Fetches the current GitHub HEAD and sync tag
- Lists only new Gitea commits since the last sync point
- Cherry-picks each commit individually (first-parent, linearised)
- Applies the same tree sanitisation per commit
- Rewrites identity **selectively**
- Fast-forward pushes to GitHub (aborts if history diverged)
- Updates the sync tag

Use this for day-to-day syncs. Keeps old commit hashes on the GitHub side
intact; only appends new history.

---

## Backward Sync (Manual)

`mirror-sync-backward.sh` runs via `custom` trigger only (never auto-runs on
push). It imports commits that exist **only on GitHub** — typically merged PRs
from external contributors — back into Gitea.

Safety checks:
- Skips commits by the mirror bot (forward-sync artifacts)
- Skips commits by configured local authors via `public_github_rewrite_emails`
- Skips commits that touch sensitive files (blacklist entries)
- Deduplicates by message + author + date

---

## Environment Variables

All variables use the `PUBLIC_` prefix for namespacing. Those listed without
`(secret)` are plain env vars set in `.drone.star`; the rest are Drone secrets.

### Auth & Remote

| Variable | In `.drone.star` | Type | Default | Description |
|----------|-------------------|------|---------|-------------|
| `PUBLIC_GITHUB_REMOTE` | `from_secret` | Secret | — | GitHub remote URL. `https://github.com/...` or `git@github.com:...` |
| `PUBLIC_GITHUB_BRANCH` | `from_secret` | Secret | `main` | Target branch on GitHub |
| `PUBLIC_GITHUB_TOKEN` | `from_secret` | Secret | — | GitHub PAT for HTTPS push. Preferred over SSH |
| `PUBLIC_GITHUB_PRIVATE_KEY` | `from_secret` | Secret | — | SSH key fallback when PAT is absent |
| `PUBLIC_SOURCE_URL` | `from_secret` | Secret | — | Optional origin URL, recorded in metadata |

### Commit Identity (Mirror Bot)

| Variable | In `.drone.star` | Type | Default | Description |
|----------|-------------------|------|---------|-------------|
| `PUBLIC_GITHUB_COMMIT_NAME` | `from_secret` | Secret | `j0nix mirror bot` | Author name for rewritten commits |
| `PUBLIC_GITHUB_COMMIT_EMAIL` | `from_secret` | Secret | `mirror@example.invalid` | Author email for rewritten commits |
| `PUBLIC_GITHUB_COMMITTER_NAME` | `from_secret` | Secret | *(COMMIT_NAME)* | Committer name. Use to distinguish the CI runner (e.g. `"Drone CI"`) from the public mirror author |
| `PUBLIC_GITHUB_COMMITTER_EMAIL` | `from_secret` | Secret | *(COMMIT_EMAIL)* | Committer email. Falls back to COMMIT_EMAIL when not set |

### Selective Author Rewrite

| Variable | In `.drone.star` | Type | Default | Description |
|----------|-------------------|------|---------|-------------|
| `PUBLIC_GITHUB_REWRITE_EMAILS` | `from_secret` | Secret | *(empty)* | Comma-separated list of exact email addresses. Commits whose original `GIT_AUTHOR_EMAIL` matches any entry exactly are rewritten |
| `PUBLIC_GITHUB_REWRITE_NAMES` | `from_secret` | Secret | *(empty)* | Same for `GIT_AUTHOR_NAME`. Disabled by default |
| `PUBLIC_SANITIZE_AUTHOR_REGEX` | *(not wired)* | Legacy | `^(jonas\|j0nix)` | **DEPRECATED**. Use `PUBLIC_GITHUB_REWRITE_EMAILS` instead. Still supported as a fallback in `scripts/lib/mirror-sanitize.sh` |

**Input format:** comma-separated full email addresses. No regex, no escaping needed.

```
me@example.com,you@other.org,old@domain.net
```

Each entry must match the entire author email **exactly** (case-insensitive).
bash `case/esac`. This is injection-safe: the input is never evaluated.

### Cutoff & History Control

| Variable | In `.drone.star` | Type | Default | Description |
|----------|-------------------|------|---------|-------------|
| `PUBLIC_CUTOFF_COMMIT` | `from_secret` | Secret | — | Commits **before** this hash are removed entirely from mirror history |
| `PUBLIC_CUTOFF_COMMIT_FALLBACK` | Plain env | String | `370ccbc...` | Hardcoded fallback when the secret above is absent |
| `PUBLIC_GITHUB_FORCE_PUSH` | `from_secret` | Secret | `true` | Set to `false` for non-destructive push. Only safe when history is known in sync |
| `PUBLIC_SYNC_TAG` | `from_secret` | Secret | `last-synced-from-gitea` | Tag on GitHub tracking the last successful sync point (incremental mode) |
| `PUBLIC_MIRROR_MODE` | `from_secret` | Secret | `full` | `full` or `incremental` |

### GPG Commit Signing (Optional)

If configured, mirrored commits on GitHub appear **Verified**.

| Variable | In `.drone.star` | Type | Default | Description |
|----------|-------------------|------|---------|-------------|
| `PUBLIC_GITHUB_SIGNING_KEY` | `from_secret` | Secret | — | ASCII-armored GPG private key. Register the matching public key on GitHub |
| `PUBLIC_GITHUB_SIGNING_PASSPHRASE` | `from_secret` | Secret | — | Passphrase for the signing key. Removed from memory after unlocking |

The passphrase is consumed at container startup, the key is stripped of its
passphrase in-memory, and the passphrase variable is then `unset` before any
git operations.

### Identity Mode (Incremental Only)

`PUBLIC_GITHUB_IDENTITY_MODE` controls how author rewriting behaves in
`mirror-sync-forward.sh`:

| Value | Behaviour |
|-------|-----------|
| `selective` | **Default**. Rewrite authors whose email/name exactly matches `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` |
| `rewrite_all` | Rewrite **every** author to the mirror bot identity |
| `preserve` | Keep original identity for **all** commits |

---

## How to Configure in Drone

1. Go to your Gitea repository → **Settings** → **Secrets**
2. Add each secret by name (e.g. `public_github_token`)
3. The `*_FALLBACK` variables (like `public_cutoff_commit_fallback`) are plain
   env vars in `.drone.star` — no secret needed

Cutoff input rule:
`PUBLIC_CUTOFF_COMMIT` should resolve to exactly one commit hash/ref after trimming whitespace. If the secret contains multiple hashes, newlines, or another invalid value, the forward sync scripts emit a warning and ignore the cutoff instead of failing the mirror run.

### Minimal Required Secrets

For a working forward sync you need at least:

```
public_github_remote
public_github_token          (or public_github_private_key)
```

Everything else has sensible defaults.

---

## Troubleshooting

### "push failed" in incremental mode

Someone pushed to GitHub while the sync was running, or the mirror history
diverged. Run a **full sync** (`public_mirror_mode=full`) to reconcile.

### "Verified" badge missing on GitHub

- Ensure `public_github_signing_key` and `public_github_signing_passphrase`
  are set correctly
- Ensure the matching **public** key is registered on the GitHub account that
  owns `PUBLIC_GITHUB_COMMIT_EMAIL`
- Check that the GitHub email address is verified

### External contributor commits show as "j0nix mirror bot"

Check `public_github_rewrite_emails`. It might be too broad. Use exact email addresses
like `me@example.com,you@other.org`. Generic substrings like `@` or `.com` will match
too many commits.

### Safety: empty rewrite list

If you set `public_github_rewrite_emails` to an **empty** value, **no commits**
are rewritten. This is the safest state — useful for testing.

---

## Files & Entry Points

| File | Purpose |
|------|---------|
| `.drone.star` | Drone CI pipeline definition (Starlark) |
| `scripts/drone-publish-step.sh` | Wrapper that dispatches to full or incremental script based on `PUBLIC_MIRROR_MODE` |
| `scripts/publish-public-github.sh` | Full `filter-branch` rewrite (full mode) |
| `scripts/mirror-sync-forward.sh` | Incremental cherry-pick sync (incremental mode) |
| `scripts/mirror-sync-backward.sh` | Backward import of GitHub-only PR commits |
| `scripts/lib/mirror-sanitize.sh` | Shared sanitisation engine: tree filter, author matching, dedup |
| `.mirror-blacklist` | Files/dirs to strip from every commit |
| `.mirror-root-whitelist` | Root files explicitly allowed; all others are stripped as safety net |
