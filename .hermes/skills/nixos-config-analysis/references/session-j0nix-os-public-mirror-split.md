# Session: GitHub Public Mirror Split — Template Rewrite + Export Validation (j0nix-os, May 22 2026)

## Context

The repo maintains a private `settings.nix` with real host data and user credentials. A public GitHub mirror must be publishable with secrets stripped and template/example files substituted. The export script `scripts/export-public-github.sh` copies tracked files, removes secrets, and replaces `settings.nix` with `settings.nix.example`.

## Goal

Rewrite all `.example` files so a new user can:
1. Clone the public mirror
2. Copy `settings.nix.example` -> `settings.nix`
3. Copy `profiles/desktop/details.nix.example` -> `profiles/desktop/details.nix`
4. Generate hardware config with `nixos-generate-config --root /mnt > profiles/desktop/hardware-configuration.nix`
5. Run `nix flake check --no-build` -> all checks pass

## Example Files Rewritten

### `settings.nix.example`

Complete rewrite covering all categories (was ~150 lines, now ~600 lines):
- **Locale & Input**: timezone, locale, keyboard layouts, options
- **Audio**: backend (`pipewire`/`pulseaudio`), Bluetooth codecs
- **Network**: tailscale, firewall, etc.
- **Dev**: Docker, BuildKit, AI CLI toggles (`codex`, `gemini`), git identity
- **Gaming**: steam, proton, performance, controllers, launchers, extras
- **Storage**: Samba mounts, disk configs
- **Logging**: journald settings
- **Programs**: enable/disable per-app
- **Users**: `userSettings.<name>` with all sub-options (editors, browsers, roles, WM shell, dev, ssh, sops)
- **Secrets**: `enableSops = true` (example-ready)
- **Theme**: theme name, wallpaper engine

Markers used:
- `# REQUIRED` -- must be set for a working install
- `# OPTIONAL` -- safe to leave at default
- Inline default values shown for every option

### `profiles/desktop/details.nix.example`

Documented the `monitorLib` API from `system/lib/monitor.nix`:
- `renderMonitorRule` -- Hyprland `monitor=` syntax
- `parseMonitorRule` -- inverse (string -> attrset)
- `normalizeMonitor` -- canonicalizes mixed input
- `monitorList` -- list of typed monitors with `coercedTo` option type
- `resolutionList` -- same for resolutions

Example configs included:
```nix
monitorConfiguration.main = {
  monitors = [
    { output = "DP-1"; mode = "3440x1440@144"; position = "0x0"; scale = 1; }
    { output = "HDMI-A-1"; mode = "1920x1080@100"; position = "3440x0"; scale = 1; extra = "transform,0"; }
  ];
  layouts = {
    standard = [ "DP-1" "HDMI-A-1" ];
    solo = [ "DP-1" ];
  };
  outputs = {
    DP-1 = { primary = true; wallpaper = "wallhaven-123.jpg"; };
  };
};
```

**Critical signature fix**: Changed from `{ lib, ... }:` to `{ ... }:` -- matches the import contract in `flake.nix` which calls `import profileDetailsFile { }`.

### `profiles/desktop/hardware-configuration.nix.example`

Added step-by-step instructions:
1. Run `nixos-generate-config` on target hardware
2. Copy output to `profiles/desktop/hardware-configuration.nix`
3. Do not edit the example file directly -- it is not imported when the real file exists

Placeholders for `fileSystems."/"`, `boot.loader.grub`, `networking.hostName`, and `powerManagement.cpuFreqGovernor`.

### `README.md`

Rewritten for public mirror clarity:
- Fixed outdated project structure (removed `j0nix-os/` sub-directory references)
- Documented the Settings vs Profiles architecture boundary
- Added Quick-Start section with 5 steps
- Documented the export/publish script flow

## Validation Protocol

After every rewrite:
```bash
# On original repo (with real settings.nix)
nix flake check --no-build

# On exported mirror (after running export-public-github.sh)
cd /tmp/j0nix-export-test
git init -q && git add -A
nix flake check --no-build
```

**Trap**: The export script uses `git ls-files`, so uncommitted rewrites are invisible. Must commit before testing export.

## Git History Incident

During the session, a `git rebase` in progress caused confusion. The user ran `git commit -a` while inside a rebase, creating a root commit that contained all working tree files as new creates. The original history was unreachable from the new root commit (reflog showed only the root commit). Recovery required `git rebase --abort` to return to the pre-rebase state, restoring the full history.

**Lesson**: Never `git commit -a` during a rebase unless you know exactly which branch you're on. Check `git status` first.

## Update: CI Pipeline + History Cutoff

The public mirror is published via a Drone CI pipeline (`.drone.star`) with two steps:

### Drone Config Pattern

```python
# .drone.star -- minimal publish pipeline
def main(ctx):
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "j0nix-os-public-mirror",
        "steps": [
            {
                "name": "validate-source",
                "image": "nixos/nix:latest",
                "commands": ["nix flake check --no-build --experimental-features 'nix-command flakes'"],
            },
            {
                "name": "export-public-github",
                "image": "nixos/nix:latest",
                "commands": ["./scripts/export-public-github.sh"],
                "environment": {
                    "DRONE_REPO_LINK": "${DRONE_REPO_LINK}",
                },
                "when": {"branch": ["main"]},
            },
            {
                "name": "publish-public-github",
                "image": "nixos/nix:latest",
                "commands": ["./scripts/publish-public-github.sh"],
                "environment": {
                    "PUBLIC_GITHUB_REMOTE": {"from_secret": "public_github_remote"},
                    "PUBLIC_GITHUB_BRANCH": {"from_secret": "public_github_branch"},
                    "PUBLIC_GITHUB_COMMIT_NAME": {"from_secret": "public_github_commit_name"},
                    "PUBLIC_GITHUB_COMMIT_EMAIL": {"from_secret": "public_github_commit_email"},
                    "PUBLIC_SOURCE_URL": {"from_secret": "public_source_url"},
                    "PUBLIC_CUTOFF_COMMIT": "370ccbc",  # hardcoded cutoff -- see below
                },
                "when": {"branch": ["main"], "event": ["push"]},
            },
        ],
        "trigger": {
            "event": ["push", "cron"],
        },
    }
```

### History Cutoff Pattern

When the pre-public history contains experimental commits, architecture-dead-ends, or sensitive work-in-progress, strip history entirely on the public mirror by initializing a fresh orphan-branch repo at publish time.

**Cutoff commit** (`PUBLIC_CUTOFF_COMMIT`): The last private commit that is "safe" to describe as antecedent. Not a merge-base -- the public repo gets zero actual history from the private repo. The cutoff is metadata only, injected into `.well-known/public-mirror-metadata.json` and the root commit message.

`scripts/export-public-github.sh`:
```bash
# ... after copy and strip operations ...
if [ -n "${PUBLIC_CUTOFF_COMMIT:-}" ]; then
    mkdir -p "$EXPORT_DIR/.well-known"
    cat > "$EXPORT_DIR/.well-known/public-mirror-metadata.json" <<EOF
{
  "publicMirror": true,
  "sourceUrl": "${SOURCE_URL:-}",
  "cutoffCommit": "${PUBLIC_CUTOFF_COMMIT}",
  "cutoffDescription": "Pre-public history stripped -- orphan branch initialized at publish time."
}
EOF
fi
```

`scripts/publish-public-github.sh`:
```bash
if [ -n "${PUBLIC_CUTOFF_COMMIT:-}" ]; then
    msg="Published from private source at ${SOURCE_URL:-unknown}"
    msg="${msg}${NL}${NL}Pre-public history ends at ${PUBLIC_CUTOFF_COMMIT}."
    msg="${msg}${NL}This commit starts a fresh orphan-branch history for the public mirror."
    git init -q
    git add -A
    git -c "user.name=${PUBLIC_GITHUB_COMMIT_NAME}" \
        -c "user.email=${PUBLIC_GITHUB_COMMIT_EMAIL}" \
        commit -m "$msg"
else
    # historical path: full repo clone + filter-branch or similar
    ...
fi
git remote add public "$PUBLIC_GITHUB_REMOTE"
git push public HEAD:"$PUBLIC_GITHUB_BRANCH" --force
```

**Rationale**: Private repos accumulate experiments, bad migrations, and sensitive data in history. A public mirror with full git history leaks all of that. Orphan-branch init is simpler and safer than `git filter-repo` or `git filter-branch` for a one-way publishing flow.

**Gotchas**:
- `cutoffCommit` is **not a parent** -- it's a string in metadata only, not a git object.
- The Drone step must pass `PUBLIC_CUTOFF_COMMIT` as an environment variable. Hardcoding in Starlark is fine if the cutoff changes rarely (architectural inflection points).
- Force-push is required because the orphan branch has no common ancestor with the previous public history.

## Complete Export Script Reference

`scripts/export-public-github.sh` (annotated structure):
```bash
#!/usr/bin/env bash
set -euo pipefail

EXPORT_DIR="${EXPORT_DIR:-.public-export}"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Copy tracked files only (respects .gitignore in the export target, not source)
git ls-files > "$EXPORT_DIR/.git-ls-files"
rsync -av --files-from="$EXPORT_DIR/.git-ls-files" . "$EXPORT_DIR/"
rm "$EXPORT_DIR/.git-ls-files"

# Strip secrets directories (recursively, even if nested)
rm -rf "$EXPORT_DIR/secrets"
rm -rf "$EXPORT_DIR/.backups"

# Replace private files with example templates
rm -f "$EXPORT_DIR/profiles/desktop/details.nix"
cp "$EXPORT_DIR/profiles/desktop/details.nix.example" \
   "$EXPORT_DIR/profiles/desktop/details.nix"

rm -f "$EXPORT_DIR/profiles/desktop/hardware-configuration.nix"
# No example hardware config -- generate from live hardware instead

cp "$EXPORT_DIR/settings.nix.example" "$EXPORT_DIR/settings.nix"

# Optional: add public mirror metadata
if [ -n "${DRONE_REPO_LINK:-}" ] || [ -n "${PUBLIC_SOURCE_URL:-}" ]; then
    # ... public-mirror-metadata.json logic above ...
fi

# Validate the export builds (optional, can be done in next CI step)
# (cd "$EXPORT_DIR" && nix flake check --no-build)

echo "Public export prepared in: $EXPORT_DIR/"
```

`scripts/publish-public-github.sh` (annotated structure):
```bash
#!/usr/bin/env bash
set -euo pipefail

EXPORT_DIR="${EXPORT_DIR:-.public-export}"
REMOTE="${PUBLIC_GITHUB_REMOTE:-}"
BRANCH="${PUBLIC_GITHUB_BRANCH:-main}"
NAME="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix-os Publish Bot}"
EMAIL="${PUBLIC_GITHUB_COMMIT_EMAIL:-publish@j0nix-os.invalid}"
SOURCE_URL="${PUBLIC_SOURCE_URL:-}"
CUTOFF="${PUBLIC_CUTOFF_COMMIT:-}"

if [ -z "$REMOTE" ]; then
    echo "PUBLIC_GITHUB_REMOTE not set. Aborting."
    exit 1
fi

cd "$EXPORT_DIR"

if [ -n "$CUTOFF" ]; then
    # Fresh orphan branch -- no history from private repo
    git init -q
    git add -A
    NL=$'\n'
    msg="Published from private source at ${SOURCE_URL:-unknown}"
    msg="${msg}${NL}${NL}Pre-public history ends at ${CUTOFF}."
    msg="${msg}${NL}This commit starts a fresh orphan-branch history for the public mirror."
    git -c "user.name=$NAME" -c "user.email=$EMAIL" commit -m "$msg"
else
    # Fallback: filter repo approach (retains pre-cutoff history)
    echo "No cutoff configured -- this path is deprecated"
    exit 1
fi

git remote add public "$REMOTE"
git push public "HEAD:${BRANCH}" --force

echo "Published to ${REMOTE} branch ${BRANCH}"
```
