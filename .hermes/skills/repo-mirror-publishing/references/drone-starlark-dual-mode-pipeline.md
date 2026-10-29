# .drone.star — Dual-Mode Public Mirror Pipeline (v3)

This reference reflects the **current** `.drone.star` after introducing the
dual-mode dispatcher (`full` vs `incremental`).  It supersedes the
single-mode pipelines in `drone-starlark-public-mirror-v2.md`.

## New Concepts

| Variable | Role |
|---|---|
| `PUBLIC_MIRROR_MODE` | `"full"` (default, legacy filter-branch) or `"incremental"` (fast-forward cherry-pick + selective identity rewrite). |
| `PUBLIC_SANITIZE_AUTHOR_REGEX` | PCRE regex matched against author name/email in incremental mode. Default `^(jonas\|j0nix)`. Empty = rewrite nothing. |
| `PUBLIC_SYNC_TAG` | Lightweight tag on the GitHub side tracking the last successfully synced commit. Default `last-synced-from-gitea`. |

## Applicability

- **Full mode:** Use when the cutoff changes, the blacklist/whitelist must
  apply retroactively to all history, or you need a clean-slate mirror.
- **Incremental mode:** Use for day-to-day publishing. Only new commits are
  processed, old commit hashes remain intact, push is non-force.

## Full `.drone.star`

```python
"""
j0nix-os public mirror Drone CI pipeline (Starlark)

Publish flow — two modes selectable via PUBLIC_MIRROR_MODE:

  full (default)
    publish-public-github.sh clones the source repo, runs git filter-branch
    to strip secrets + host-specific data, replaces sensitive files with
    .example templates, rewrites commit authors, and force-pushes the
    sanitized history to the configured GitHub remote.

  incremental
    mirror-sync-forward.sh only exports new commits since the last sync,
    cherry-picks each commit individually, applies tree sanitisation,
    rewrites identity selectively (jonas/j0nix → bot, external authors kept),
    and fast-forward pushes to GitHub. Non-destructive; keeps old commit
    hashes intact.

Environment secrets expected by Drone (type: secret, name as listed):

  public_github_remote          GitHub remote URL (e.g. git@github.com:user/repo.git)
  public_github_branch          Target branch on GitHub (default: main)
  public_github_commit_name     Commit author name (default: j0nix mirror bot)
  public_github_commit_email    Commit author email (default: mirror@example.invalid)
  public_source_url             Optional URL of the Gitea source origin.
  public_cutoff_commit          Optional. Overrides the Starlark hardcoded cutoff.
  public_github_force_push      Optional; set to "false" to push non-destructively.
                                  Default is "true" (force-push branch + tags).
                                  Only disable when mirror history is known in sync.
  public_github_token           GitHub Personal Access Token for HTTPS push.
                                Preferred over SSH; bypasses display-name
                                override on GitHub. Generate at:
                                GitHub Settings > Developer settings >
                                Personal access tokens (classic, repo scope).
  public_github_private_key     SSH private key for git push (fallback).
                                Drone strips newlines; the script restores them.
  public_sanitize_author_regex  Optional PCRE regex to match authors that should
                                be rewritten in incremental mode.
                                  Default: ^(jonas|j0nix)
                                  Empty = rewrite nothing (safety).
  public_sync_tag               Optional tag name for tracking last sync on GitHub.
                                  Default: last-synced-from-gitea

Additional plain env (not a secret):
  public_cutoff_commit_fallback  Hardcoded fallback when the above secret is absent.
  public_mirror_mode             "full" (default) or "incremental".
"""

NIX_IMAGE = "nixos/nix:2.26.1"
NIX = "nix --extra-experimental-features 'nix-command flakes'"

# Commits before this hash are excluded from the public mirror history.
# Set once, keep stable. Changing this triggers a force-push orphan-branch
# reset on the next publish run.
PUBLIC_CUTOFF_COMMIT_FALLBACK = "370ccbc95c860ea5a2ec6a9e1bff752ad7562fbb"


def public_mirror_pipeline():
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "public-mirror",
        "trigger": {
            "event": ["push", "pull_request", "custom"],
            "branch": ["main"],
        },
        "steps": [
            {
                "name": "publish-github",
                "image": NIX_IMAGE,
                "environment": {
                    "PUBLIC_GITHUB_REMOTE": {
                        "from_secret": "public_github_remote",
                    },
                    "PUBLIC_GITHUB_BRANCH": {
                        "from_secret": "public_github_branch",
                    },
                    "PUBLIC_GITHUB_COMMIT_NAME": {
                        "from_secret": "public_github_commit_name",
                    },
                    "PUBLIC_GITHUB_COMMIT_EMAIL": {
                        "from_secret": "public_github_commit_email",
                    },
                    "PUBLIC_SOURCE_URL": {
                        "from_secret": "public_source_url",
                    },
                    "PUBLIC_CUTOFF_COMMIT": {
                        "from_secret": "public_cutoff_commit",
                    },
                    "PUBLIC_CUTOFF_COMMIT_FALLBACK": PUBLIC_CUTOFF_COMMIT_FALLBACK,
                    "PUBLIC_GITHUB_FORCE_PUSH": {
                        "from_secret": "public_github_force_push",
                    },
                    "PUBLIC_GITHUB_PRIVATE_KEY": {
                        "from_secret": "public_github_private_key",
                    },
                    "PUBLIC_GITHUB_TOKEN": {
                        "from_secret": "public_github_token",
                    },
                    "PUBLIC_MIRROR_MODE": {
                        "from_secret": "public_mirror_mode",
                    },
                    "PUBLIC_SANITIZE_AUTHOR_REGEX": {
                        "from_secret": "public_sanitize_author_regex",
                    },
                    "PUBLIC_SYNC_TAG": {
                        "from_secret": "public_sync_tag",
                    },
                },
                "commands": [
                    'echo "Mirror mode: ${PUBLIC_MIRROR_MODE:-full}"',
                    "env | grep '^PUBLIC' | cut -d= -f1 | sort",
                    'case "${PUBLIC_MIRROR_MODE:-full}" in',
                    '  incremental)',
                    '    scripts/mirror-sync-forward.sh "$PUBLIC_GITHUB_REMOTE" "$PUBLIC_GITHUB_BRANCH"',
                    '    ;;',
                    '  *)',
                    '    scripts/publish-public-github.sh "$PUBLIC_GITHUB_REMOTE" "$PUBLIC_GITHUB_BRANCH"',
                    '    ;;',
                    'esac',
                ],
                "when": {
                    "branch": ["main"],
                    "event": ["push"],
                },
            },
        ],
    }


def main(ctx):
    return [
        public_mirror_pipeline(),
    ]
```

## Key Design Decisions

1. **Mode default:** Omitting `PUBLIC_MIRROR_MODE` (or leaving the secret
   empty) falls through to `full` via `${PUBLIC_MIRROR_MODE:-full}`. This
   preserves backward compatibility with existing Drone configurations.

2. **Env variable listing:** The second command (`env | grep '^PUBLIC' ...`)
   is intentionally value-safe. It only prints variable *names*, confirming
   which secrets Drone actually injected without leaking tokens in CI logs.

3. **Script path stability:** Both `publish-public-github.sh` and
   `mirror-sync-forward.sh` live in `scripts/` and are invoked by relative
   path. They share `scripts/lib/mirror-sanitize.sh` for tree sanitisation.

4. **No `--dry-run` flag:** Neither script accepts a dry-run flag in the
   current implementation. To test locally without pushing, create a throwaway
   GitHub fork and point `PUBLIC_GITHUB_REMOTE` at it.
