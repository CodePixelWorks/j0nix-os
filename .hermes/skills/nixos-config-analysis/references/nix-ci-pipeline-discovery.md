# Nix CI Pipeline Discovery & Fixes

Self-hosted Git hosts (Gitea — this project uses Gitea, NOT Forgejo) run **Drone** for CI. The pipeline definition lives in `.drone.star` (Starlark), not `.github/workflows/` or `.forgejo/workflows/`.

## Pipeline Locations

| Platform | Config file |
|----------|-------------|
| GitHub Actions | `.github/workflows/*.yml` |
| Forgejo Actions | `.forgejo/workflows/*.yml` |
| Drone (Starlark) | `.drone.star` |
| GitLab CI | `.gitlab-ci.yml` |

## Drone Auth via Token (Tokenbase)

When Drone targets a **GitHub** remote (e.g. mirroring), it needs a token for API access — not username/password. Steps:

1. In Drone UI → Repo Settings → Secrets, add `github_token` with a GitHub PAT.
2. Map it in `.drone.star` **as a distinct key** (or inject via `from_secret`):

```starlark
{
    "name": "mirror-to-github",
    "image": "alpine/git",
    "environment": {
        "GITHUB_TOKEN": {
            "from_secret": "github_token",
        },
    },
    "commands": [
        'git push "https://x-access-token:$GITHUB_TOKEN@github.com/owner/repo.git" --tags',
    ],
}
```

If the same fallback default is also needed: use **two distinct env keys** because JSON keys must be unique. Example:

```starlark
"environment": {
    "GITHUB_TOKEN": {"from_secret": "github_token"},
    "GITHUB_TOKEN_FALLBACK": "ghp_xxxxxxxxxxxx",
}
```

In the script: `${GITHUB_TOKEN:-${GITHUB_TOKEN_FALLBACK:-}}`.

## The `nixos/nix` Container Trap

The `nixos/nix:2.26.1` image disables experimental features by default. `nix flake check` fails with:

```
error: experimental Nix feature 'nix-command' is disabled
```

### Fix: add CLI flags in every `commands` entry

```starlark
NIX_IMAGE = "nixos/nix:2.26.1"
NIX = "nix --extra-experimental-features 'nix-command flakes'"

{
    "name": "validate-source",
    "image": NIX_IMAGE,
    "commands": [
        "{} flake check --no-build".format(NIX),
    ],
}
```

Do **not** rely on `NIX_CONFIG` env var or `~/.config/nix/nix.conf` in the container — they are ignored in restricted CI environments.

## Missing `python3` in Minimal Containers

Scripts that call `python3` (e.g. `scripts/regenerate-readme.py`, `scripts/export-public-github.sh`) will fail with `python3: command not found` in Alpine or slim Nix containers. Three fixes, ordered by preference:

1. **Run via `nix run`** (works in Nix containers):
   ```bash
   nix run nixpkgs#python3 -- scripts/regenerate-readme.py --scope public --output README.md.public
   ```
2. **Use a container image with python3**:
   ```starlark
   "image": "nixos/nix:2.26.1",   # add a preceding `apk add python3` if Alpine
   ```
3. **Add a nix shell step**:
   ```bash
   nix-shell -p python3 --run "python3 scripts/regenerate-readme.py ..."
   ```

## Validating the Pipeline

After editing `.drone.star`, no local syntax checker is available for embedded Starlark. The quickest validation is:

1. Push the branch and trigger the pipeline.
2. Check the web UI for the exact step output.
3. If the step fails with `experimental Nix feature ... disabled`, the flags are missing.

## Conditional / Disabled Steps

When a step (e.g. `validate-public-export`) requires secrets or a remote that is not available in the current environment, comment the entire `dict` out rather than leaving it to fail:

```starlark
# validate-public-export disabled: requires secrets not available here.
```

Keep the commented step next to the active pipeline so the intent is visible when re-enabling.

## Runtime Secret Override with Fallback (JSON Key Uniqueness Rule)

Starlark dicts → JSON. If a variable is defined **twice** (once as `from_secret`, once as a plain constant), only one survives because JSON keys must be unique. Use two distinct keys instead:

```starlark
environment = {
    "CUTOFF_COMMIT": {"from_secret": "public_cutoff_commit"},
    "CUTOFF_COMMIT_FALLBACK": "abc123",
}
```

In the script:
```bash
CUTOFF="${CUTOFF_COMMIT:-${CUTOFF_COMMIT_FALLBACK:-}}"
```

This pattern cleanly lets a Drone secret override a static default at runtime.
