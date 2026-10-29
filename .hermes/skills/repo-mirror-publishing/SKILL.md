---
name: repo-mirror-publishing
description: "Publish a sanitized, history-rewritten mirror of a private repository to a public host (e.g., GitHub). Covers filter-branch workflows, secret stripping, CI container fallbacks, and auth patterns."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [git-filter-branch, mirror, publishing, secrets, CI, public-mirror]
    related_skills: [ci-cd-pipeline-authoring, github-repo-management]
---

# Repository Mirror Publishing

Publish a sanitized mirror of a private repository to a public host. The private source remains on its host (e.g., Gitea); the public mirror lives on another (e.g., GitHub). History is rewritten to strip secrets, replace sensitive files with templates, and inject a public-facing README.

> **User context (Jonas):** Private source on Gitea with Drone CI runner. Public mirror on GitHub. Maintains `PUBLIC_CUTOFF_COMMIT` to orphan history before a stable architecture milestone. `nix run` is preferred for tool fallback in CI containers.

---

## Overview

```
Private repo (Gitea)  --->  [CI: generate + filter-branch]  --->  Public mirror (GitHub)
                                    |
                                    +-- Strip secrets/settings
                                    +-- Replace with .example templates
                                    +-- Inject public README
                                    +-- Rewrite author/committer identity
                                    +-- Orphan history from cutoff commit
```

---

## 1. Environment Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `PUBLIC_GITHUB_TOKEN` | Drone secret | GitHub PAT for HTTPS push (preferred) |
| `PUBLIC_GITHUB_PRIVATE_KEY` | Drone secret | SSH key fallback when PAT absent |
| `PUBLIC_GITHUB_COMMIT_NAME` | Drone secret | Author name for rewritten commits |
| `PUBLIC_GITHUB_COMMIT_EMAIL` | Drone secret | Author email for rewritten commits |
| `PUBLIC_GITHUB_COMMITTER_NAME` | Drone secret / fallback | Committer name for rewritten commits. Falls back to `PUBLIC_GITHUB_COMMIT_NAME`. Use to distinguish the CI runner (e.g. `"Drone CI"`) from the public mirror author. |
| `PUBLIC_GITHUB_COMMITTER_EMAIL` | Drone secret / fallback | Committer email. Falls back to `PUBLIC_GITHUB_COMMIT_EMAIL`. |
| `PUBLIC_GITHUB_SIGNING_KEY` | Drone secret | GPG private key (ASCII-armored) for signing rewritten commits. May be passphrase-protected. |
| `PUBLIC_GITHUB_SIGNING_PASSPHRASE` | `from_secret` | Secret | — | Passphrase for the signing key. Required when key is protected; preserved as `MIRROR_GPG_PASSPHRASE` and injected via a `gpg-wrapper` script; original env var scrubbed before git operations |
| `PUBLIC_GITHUB_SIGNING_PUBKEY_URL` | Drone secret | Optional HTTPS URL to the ASCII-armored **public** key. Pipeline aborts if the downloaded key's fingerprint does not match the imported private key. |
| `PUBLIC_GITHUB_REWRITE_EMAILS` | Drone secret / fallback | Comma-separated substrings for **email-based** selective rewrite (default: `jonas,j0nix`). Empty = no email matching. |
| `PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK` | Plain env | Fallback when secret unset. See `references/public-cutoff-commit-workaround.md`. |
| `PUBLIC_GITHUB_REWRITE_NAMES` | Drone secret / fallback | Optional. Comma-separated substrings for **name-based** selective rewrite. Disabled by default (`""`). |
| `PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK` | Plain env | Fallback when secret unset. |
| `PUBLIC_SANITIZE_AUTHOR_REGEX` | Drone secret / fallback | **DEPRECATED.** Old regex-based variable. Migrates automatically to glob patterns when `PUBLIC_GITHUB_REWRITE_EMAILS` is set. |
| `PUBLIC_CUTOFF_COMMIT` | Drone secret | Commits BEFORE this hash are dropped from mirror history |
| `PUBLIC_CUTOFF_COMMIT_FALLBACK` | Plain env | Static fallback when secret is unset (Drone Starlark cannot define same key twice) |
| `PUBLIC_GITHUB_IDENTITY_MODE` | Plain env / secret | Identity rewrite policy: `selective` (default), `rewrite_all`, or `preserve` |
| `PUBLIC_SOURCE_URL` | Plain env | Recorded in mirror metadata |
| `PUBLIC_MIRROR_MODE` | Plain env / secret | `"full"` (default, filter-branch) or `"incremental"` (fast-forward cherry-pick) |
| `PUBLIC_SANITIZE_AUTHOR_REGEX` | Plain env / secret | PCRE regex for selective identity rewrite in incremental mode (default: `^(jonas\|j0nix)`) |
| `PUBLIC_SYNC_TAG` | Plain env / secret | Tag on GitHub tracking last sync (default: `last-synced-from-gitea`) |

**Drone Starlark note:** JSON object keys must be unique. You CANNOT define `PUBLIC_CUTOFF_COMMIT` twice (once as `from_secret`, once as plain). Use two distinct keys — see `references/public-cutoff-commit-workaround.md` for the full explanation and cascading fallback pattern.

---

## GPG public key verification (optional)

Set `PUBLIC_GITHUB_SIGNING_PUBKEY_URL` to an HTTPS URL pointing to the ASCII-armored public key that matches the private key in `PUBLIC_GITHUB_SIGNING_KEY`. Both forward sync scripts (`publish-public-github.sh` and `mirror-sync-forward.sh`) download the public key after importing the private key, compare the full fingerprints, and abort the pipeline on any mismatch.

This prevents silent misconfiguration where GitHub shows "Unverified" because the registered public key does not match the signing private key. See `references/gpg-signing-mirror-commits.md` § Public key verification for the full implementation.

---

## 2. Auth Method: PAT Preferred, SSH Fallback

### GitHub PAT username: `oauth2`, not `x-access-token`

GitHub deprecated `x-access-token` as the username for PAT-based HTTPS auth. Both classic tokens and Fine-Grained PATs now require **`oauth2`** as the username (token as password). Using the old username produces:

```
fatal: Authentication failed for 'https://github.com/...'
remote: Invalid username or token.
```

```bash
remote_url="$1"  # e.g., https://github.com/j0nix/j0nix-os.git

if [ -n "${PUBLIC_GITHUB_TOKEN:-}" ]; then
    git_auth_remote="${remote_url/https:\/\//https:\/\/oauth2:${PUBLIC_GITHUB_TOKEN}@}"
else
    # SSH fallback
    ssh_key_path="$(mktemp -t mirror.XXXXXX)"
    chmod 600 "$ssh_key_path"
    printf '%b\n' "$PUBLIC_GITHUB_PRIVATE_KEY" > "$ssh_key_path"
    export GIT_SSH_COMMAND="ssh -i '$ssh_key_path' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi
```

---

## 3. Full Publishing Script Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

remote_url="${1:?usage: $0 REMOTE_URL [BRANCH]}"
branch="${2:-main}"

commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
cutoff_commit="${PUBLIC_CUTOFF_COMMIT:-${PUBLIC_CUTOFF_COMMIT_FALLBACK:-}}"
force_push="${PUBLIC_GITHUB_FORCE_PUSH:-true}"

repo_root="$(git rev-parse --show-toplevel)"

# Run sed, pulling it from nixpkgs if the host doesn't have it.
# Required in minimal CI containers (e.g. nixos/nix:2.26.1) where sed may
# be absent but Nix is available.
run_sed() {
    if command -v sed >/dev/null 2>&1; then
        command sed "$@"
    elif command -v nix >/dev/null 2>&1; then
        nix --extra-experimental-features 'nix-command flakes' \
            shell nixpkgs#gnused --command sed "$@"
    else
        printf '%s\n' "ERROR: sed not found and nix not available" >&2
        exit 1
    fi
}

# --- 1. Auth (see section 2) ---
# ... (PAT or SSH setup) ...

# --- 2. Clone into temp workspace ---
work_dir="$(mktemp -d)"
cleanup() { rm -rf "$work_dir"; [ -n "${ssh_key_path:-}" ] && rm -f "$ssh_key_path" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

git clone --local --no-hardlinks "$repo_root" "$work_dir"
cd "$work_dir"

# --- 3. Generate public README OUTSIDE the worktree ---
# filter-branch aborts on any worktree modification after clone.
# Generate into the ORIGINAL repo root (not $work_dir), then inject
# via absolute path inside the tree-filter subshell.
readme_path="$repo_root/README.md.public"
if command -v python3 >/dev/null 2>&1; then
    python3 "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"
elif command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#python3 \
        -- "$repo_root/scripts/regenerate-readme.py" --scope public --output "$readme_path"
else
    echo "ERROR: python3 not found and nix not available" >&2; exit 1
fi

# Strip any embedded auth tokens so they never leak into the published tree.
# Regex must match the auth method configured above (oauth2 for GitHub PATs).
run_sed -i 's#https://oauth2:[^@]*@github\.com#https://github.com#g' "$readme_path" 2>/dev/null || true

git remote remove origin 2>/dev/null || true

# --- 4. filter-branch: rewrite history ---
export FILTER_BRANCH_SQUELCH_WARNING=1

env_filter="
    export GIT_AUTHOR_NAME='$commit_name'
    export GIT_AUTHOR_EMAIL='$commit_email'
    export GIT_COMMITTER_NAME='$commit_name'
    export GIT_COMMITTER_EMAIL='$commit_email'
"

# Export repo_root so the tree-filter subshell can resolve it.
REPO_ROOT="$repo_root"
export REPO_ROOT

tree_filter='
    # Strip secrets and settings
    rm -f .sops.yaml settings.nix profiles/desktop/details.nix profiles/desktop/hardware-configuration.nix
    if [ -d secrets/hosts ]; then find secrets/hosts -mindepth 1 -maxdepth 1 -type f -delete; fi
    if [ -d secrets/users ]; then find secrets/users -mindepth 1 -maxdepth 1 -type f -delete; fi

    # Replace with .example templates
    cp -f settings.nix.example settings.nix 2>/dev/null || true
    cp -f profiles/desktop/details.nix.example profiles/desktop/details.nix 2>/dev/null || true
    cp -f profiles/desktop/hardware-configuration.nix.example profiles/desktop/hardware-configuration.nix 2>/dev/null || true
    cp -f .sops.yaml.example .sops.yaml 2>/dev/null || true

    # Remove .example files so they do not linger
    rm -f settings.nix.example profiles/desktop/details.nix.example profiles/desktop/hardware-configuration.nix.example .sops.yaml.example

    ---

    ### 4.15 `git-filter-repo` strips GPG signatures and has no `--gpg-sign` equivalent

    **Cause:** `git-filter-repo` rewrites history via `git fast-export | filter | git fast-import`. The `fast-export` format does not carry `gpgsig` headers, so all existing signatures are discarded. `git-filter-repo` provides no `--gpg-sign` or callback mechanism to re-create signatures during the rewrite.

    **Fix for full-rewrite mirror scripts:** Stay with `git filter-branch` and add a `--commit-filter` that calls `git commit-tree --gpg-sign="$key_id"` when the `--env-filter` has rewritten the author identity.

    **Critical incompatibilities discovered in practice:**
    1. `--prune-empty` and `--commit-filter` are **mutually exclusive** — `filter-branch` aborts with `Cannot set --prune-empty and --commit-filter at the same time`. Empty-commit pruning must be implemented inside the filter function.
    2. The filter must be **sourced** (POSIX `.`), not executed as a standalone binary, because `filter-branch` helper `map` is only available in the filter-branch subshell.
    3. Use POSIX `.` instead of bash `source` — filter-branch may invoke the filter in `/bin/sh`.

    ```bash
    commit_filter_path="$(mktemp -t commit_filter.XXXXXX)"
    cat > "$commit_filter_path" <<'COMMITFILTER'
    run_commit_filter() {
        local tree_id="$1"
        shift
        local original_args=("$@")

        local parent_hashes=()
        while [ $# -gt 0 ]; do
            if [ "$1" = "-p" ] && [ $# -ge 2 ]; then
                parent_hashes+=("$2")
                shift 2
            else
                shift
            fi
        done

        # Prune empty commits (tree identical to any parent).
        # Replaces --prune-empty, which is forbidden with --commit-filter.
        for parent in "${parent_hashes[@]}"; do
            local ptree
            ptree=$(git rev-parse "$parent^{tree}" 2>/dev/null) || true
            if [ "$tree_id" = "$ptree" ]; then
                map "$parent"
                return 0
            fi
        done

        local mirror_email="REPLACE_MIRROR_EMAIL"
        local gpg_key="REPLACE_GPG_KEY_ID"

        if [ "$GIT_AUTHOR_EMAIL" = "$mirror_email" ] && [ -n "$gpg_key" ]; then
            git commit-tree --gpg-sign="$gpg_key" "$tree_id" "${original_args[@]}"
        else
            git commit-tree "$tree_id" "${original_args[@]}"
        fi
    }
    run_commit_filter "$@"
    COMMITFILTER
    run_sed -i "s#REPLACE_MIRROR_EMAIL#${commit_email}#g" "$commit_filter_path"
    run_sed -i "s#REPLACE_GPG_KEY_ID#${gpg_key_id}#g" "$commit_filter_path"

    git filter-branch \
        --env-filter "..." \
        --tree-filter "..." \
        --commit-filter ". '$commit_filter_path'" \
        --tag-name-filter cat \
        -- --all
    ```

    The filter script is written to a temp file (not inlined) because `filter-branch` passes strings through `eval`, which corrupts quoting. It is **sourced** via `--commit-filter ". '$path'"` rather than executed as a standalone path, because `.` runs it inside the filter-branch subshell where the `map` helper function is available.

    **Key points:**
    - `GIT_AUTHOR_EMAIL` inside the commit-filter reflects the value set by the `--env-filter`, so the script only signs commits that were actually rewritten.
    - `GNUPGHOME` must be exported in the main shell before `filter-branch` runs so the subprocess can resolve the imported key.
    - The commit-filter receives the fast-export tree ID and parent arguments (`<TREE_ID> -p <PARENT_SHA> ...`) exactly like `git commit-tree`.
    - `--prune-empty` is incompatible with `--commit-filter` and must be removed. The `run_commit_filter` function implements identical pruning by checking `git rev-parse` on all parents.
    - **Template the filter scripts with `run_sed`** — Drone CI runners based on `nixos/nix` containers may not have `sed` in the main PATH. **Never use `|` as the sed delimiter** when `run_sed` resolves to `nix run`; the Nix CLI corrupts pipe characters. Use `#` instead.
    - **Use `nix shell --command` not `nix run`** — `nix run` passes arguments through a path that corrupts single-quoted sed expressions inside gnused; `nix shell --command` preserves quoting correctly.
    - **Environment isolation inside `--commit-filter`:** The sourced subshell may not inherit `GNUPGHOME` cleanly, and `GIT_DIR`/`GIT_WORK_TREE` set by filter-branch itself can confuse `gpg` invocations inside the filter. Add a reachability check inside `run_commit_filter` (see `references/gpg-signing-mirror-commits.md` §4.5c for full diagnostics).

    ### GPG signing diagnostics after filter-branch

    Add a diagnostics block after `filter-branch` completes and before pushing, so CI logs reveal whether signing worked. Use a **pipe-delimited** format rather than space-separated — `%GS` is empty for unsigned commits (`%G? = N`), leaving an invisible trailing space that breaks `grep ' N$'`:

    ```bash
    rm -rf .git/refs/original/
    printf '%s\n' "--- GPG signing diagnostics ---"
    last_sigs=$(git log --all --format='%H|%G?|%GS|#' -5)
    printf '%s\n' "$last_sigs"
    unsigned_count=$(printf '%s\n' "$last_sigs" | grep -c '|N||#' || echo "0")
    if [ "$unsigned_count" -gt 0 ]; then
        printf '%s\n' "WARN: $unsigned_count of last 5 rewritten commits lack GPG signature"
    else
        printf '%s\n' "OK: all last 5 commits carry a GPG signature"
    fi
    printf '%s\n' "---"
    ```

    Git format placeholders:
    - `%H` — commit hash
    - `%G?` = `N` means no signature (filter not executed, key missing, or env isolation). `%G?` = `G` means valid signature.
    - `%GS` — key ID of the signer (empty when `%G? = N`).
    - `|#` sentinel — provides a robust anchor so trailing spaces never cause a silent false-negative in `grep`.

    If GitHub still shows "Unverified" after `G`, the public key is missing from GitHub or the commit email does not match the key's UID.
    git push --force --tags github
fi
## Related Files

See `references/nix-run-missing-tools-ci.md` for the full rationale and additional nixpkgs tool mappings.
- `references/nix-run-missing-tools-ci.md` — `run_sed` helper and `nix shell` pattern for fetching missing POSIX tools in minimal CI containers (preferred over Python fallbacks).
> - `references/sed-free-ci-scripting.md` — Legacy `_safe_replace` Python-fallback approach. Prefer `nix-run-missing-tools-ci` when Nix is available.
> - `references/printf-newline-bug-parent-filter.md` — Why `printf '%s\\n'` produces literal backslash-n instead of newlines, breaking generated filter scripts and causing `Not a valid object name` on merge commits.
> - `references/incremental-sync-scripts.md` — Full reproduction of `mirror-sanitize.sh`, `mirror-sync-forward.sh`, and `mirror-sync-backward.sh` for adaptation and study.

---

## Commit Message Safety (Non-Negotiable)

**Jonas' rule for this repo:** When a commit message contains backticks, Nix interpolation (`${...}`), or any shell-sensitive characters, **always** use `git commit -F /tmp/msg.txt` instead of inline `-m`. Inline `-m` with backticks triggers command substitution in bash and silently strips or corrupts technical details from the commit body.

```bash
# WRONG — backticks cause command substitution:
git commit -m "feat(dev): add `docker-compose` helper"
# Result: tries to run "docker-compose" as a command, commit becomes garbled

# CORRECT — write to file first:
cat > /tmp/msg.txt << 'EOF'
feat(dev): add `docker-compose` helper

- Wraps docker-compose for consistent env-file loading
EOF
git commit -F /tmp/msg.txt
```

---

### 4.15 `git-filter-repo` strips GPG signatures and has no `--gpg-sign` equivalent

**Cause:** `git-filter-repo` rewrites history via `git fast-export | filter | git fast-import`. The `fast-export` format does not carry `gpgsig` headers, so all existing signatures are discarded. `git-filter-repo` provides no `--gpg-sign` or callback mechanism to re-create signatures during the rewrite.

**Fix for full-rewrite mirror scripts:** Stay with `git filter-branch` and add a `--commit-filter` that calls `git commit-tree --gpg-sign="$key_id"` when the `--env-filter` has rewritten the author identity.

**Critical incompatibilities discovered in practice:**
1. `--prune-empty` and `--commit-filter` are **mutually exclusive** — `filter-branch` aborts with `Cannot set --prune-empty and --commit-filter at the same time`. Empty-commit pruning must be implemented inside the filter function.
2. The filter must be **sourced** (POSIX `.`), not executed as a standalone binary, because `filter-branch` helper `map` is only available in the filter-branch subshell.
3. Use POSIX `.` instead of bash `source` — filter-branch may invoke the filter in `/bin/sh`.

```bash
commit_filter_path="$(mktemp -t commit_filter.XXXXXX)"
cat > "$commit_filter_path" <<'COMMITFILTER'
run_commit_filter() {
    local tree_id="$1"
    shift
    local original_args=("$@")

    local parent_hashes=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "-p" ] && [ $# -ge 2 ]; then
            parent_hashes+=("$2")
            shift 2
        else
            shift
        fi
    done

    # Prune empty commits (tree identical to any parent).
    # Replaces --prune-empty, which is forbidden with --commit-filter.
    for parent in "${parent_hashes[@]}"; do
        local ptree
        ptree=$(git rev-parse "$parent^{tree}" 2>/dev/null) || true
        if [ "$tree_id" = "$ptree" ]; then
            map "$parent"
            return 0
        fi
    done

    local mirror_email="REPLACE_MIRROR_EMAIL"
    local gpg_key="REPLACE_GPG_KEY_ID"

    if [ "$GIT_AUTHOR_EMAIL" = "$mirror_email" ] && [ -n "$gpg_key" ]; then
        git commit-tree --gpg-sign="$gpg_key" "$tree_id" "${original_args[@]}"
    else
        git commit-tree "$tree_id" "${original_args[@]}"
    fi
}
run_commit_filter "$@"
COMMITFILTER
run_sed -i "s#REPLACE_MIRROR_EMAIL#${commit_email}#g" "$commit_filter_path"
run_sed -i "s#REPLACE_GPG_KEY_ID#${gpg_key_id}#g" "$commit_filter_path"

git filter-branch \
    --env-filter "..." \
    --tree-filter "..." \
    --commit-filter ". '$commit_filter_path'" \
    --tag-name-filter cat \
    -- --all
```

The filter script is written to a temp file (not inlined) because `filter-branch` passes strings through `eval`, which corrupts quoting. It is **sourced** via `--commit-filter ". '$path'"` rather than executed as a standalone path, because `.` runs it inside the filter-branch subshell where the `map` helper function is available.

**Key points:**
- `GIT_AUTHOR_EMAIL` inside the commit-filter reflects the value set by the `--env-filter`, so the script only signs commits that were actually rewritten.
- `GNUPGHOME` must be exported in the main shell before `filter-branch` runs so the subprocess can resolve the imported key.
- The commit-filter receives the fast-export tree ID and parent arguments (`<TREE_ID> -p <PARENT_SHA> ...`) exactly like `git commit-tree`.
- `--prune-empty` is incompatible with `--commit-filter` and must be removed. The `run_commit_filter` function implements identical pruning by checking `git rev-parse` on all parents.
- **Template the filter scripts with `run_sed`** — Drone CI runners based on `nixos/nix` containers may not have `sed` in the main PATH. **Never use `|` as the sed delimiter** when `run_sed` resolves to `nix run`; the Nix CLI corrupts pipe characters. Use `#` instead.
- **Use `nix shell --command` not `nix run`** — `nix run` passes arguments through a path that corrupts single-quoted sed expressions inside gnused; `nix shell --command` preserves quoting correctly.

### GPG signing diagnostics after filter-branch

Add a diagnostics block after `filter-branch` completes and before pushing, so CI logs reveal whether signing worked:

```bash
rm -rf .git/refs/original/
printf '%s\n' "--- GPG signing diagnostics ---"
last_sigs=$(git log --all --format='%H %G? %GS' -5)
printf '%s\n' "$last_sigs"
unsigned_count=$(printf '%s\n' "$last_sigs" | grep -c ' N$' || echo "0")
if [ "$unsigned_count" -gt 0 ]; then
    printf '%s\n' "WARN: $unsigned_count of last 5 rewritten commits lack GPG signature"
else
    printf '%s\n' "OK: all last 5 commits carry a GPG signature"
fi
printf '%s\n' "---"
```

`%G?` = `N` means no signature (filter not executed or key missing). `%G?` = `G` means valid signature. If GitHub still shows "Unverified" after `G`, the public key is missing from GitHub or the commit email does not match the key's UID.
### 4.16 `sed: command not found` in CI container

**Cause:** `nixos/nix` container images used by Drone CI runners may ship without `sed` in the default PATH. This affects the **parent shell** where `publish-public-github.sh` generates temp filter scripts, not just the minimal subshells spawned by `git-filter-branch`.

The error manifests during temp-script generation *before* filter-branch even starts:

```
scripts/publish-public-github.sh: line 319: sed: command not found
```

**Fix:** Provide a `run_sed` helper that fetches `gnused` from nixpkgs via `nix shell` when the host binary is missing. **Do not write a Python fallback** — in a Nix-based project `nix shell nixpkgs#gnused` is preferred over adding a new code path in Python or pure bash.

```bash
run_sed() {
    if command -v sed >/dev/null 2>&1; then
        command sed "$@"
    elif command -v nix >/dev/null 2>&1; then
        nix --extra-experimental-features 'nix-command flakes' \
            shell nixpkgs#gnused --command sed "$@"
    else
        printf '%s\n' "ERROR: sed not found and nix not available" >&2
        exit 1
    fi
}
```

**Scripts using `sed` that must be updated:**
- Commit-filter template substitution (`REPLACE_MIRROR_EMAIL`, `REPLACE_GPG_KEY_ID`)
- Parent-filter token replacement (`PFSCRIPT_CUTOFF`)
- Auth-token stripping in generated `README.md.public`

**Verification in CI:**
```bash
which sed || echo "sed missing — will fetch from nixpkgs"
```

If `sed` is missing but `nix` is present, `run_sed` silently pulls the tool from cache.nixos.org. If both are missing, the script exits with a clear error rather than producing a broken temp script that fails downstream with a cryptic `Not a valid object name` or missing variable.

### 4.17 `nix run nixpkgs#gnused` mangles `|` in sed expressions

**Cause:** When `run_sed` falls back to `nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnused -- sed`, the Nix CLI argument parser treats the pipe character `|` in the sed expression as a shell metacharacter. The expression `s|old|new|g` is truncated, producing:

```
/nix/store/...-gnused-4.9/bin/sed: -e expression #1, char 3: unterminated `s' command
```

**Additional root cause:** `nix run` also corrupts single-quoted sed expressions even when the delimiter is safe (e.g. `#`). The argument forwarding path inside `nix run` strips outer quotes before passing them to the spawned binary.

**Fix:** 
1. **Use `nix shell --command` instead of `nix run`.** `nix shell --command sed "$@"` preserves quoting correctly; `nix run` does not.
2. **Replace `|` delimiter with `#`** (or another character benign in both bash and Nix CLI contexts):

```bash
# WRONG — fails with both pipe corruption AND quote stripping by nix run
run_sed -i "s|REPLACE_MIRROR_EMAIL|${commit_email}|g" "$commit_filter_path"
# CORRECT — '#' is safe everywhere, and `nix shell --command` preserves quotes
run_sed -i "s#REPLACE_MIRROR_EMAIL#${commit_email}#g" "$commit_filter_path"
```

**Verification:**
```bash
# This fails (quote stripping):
nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnused -- \
    sed 's|foo|bar|g' <<< "foo"

# This works:
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#gnused \
    --command sed 's|foo|bar|g' <<< "foo"
```

**Rule of thumb:** When authoring sed expressions inside a `run_sed` context, use `#` as delimiter and ensure the `run_sed` helper resolves to `nix shell --command`, never `nix run`.

---

### 4.1 Cannot rewrite branches: You have unstaged changes

**Cause:** `git-filter-branch` refuses to run if the working tree or index is dirty.

**Fix:** Do NOT stage generated files with `git add`. Place them unstaged in the worktree, or overwrite existing files directly. Better yet: overwrite `README.md` directly before filter-branch starts — then the tree already contains the correct file and no injection is needed in the tree-filter.

See `references/readme-generation-and-filter-branch.md` for the full evolution from sidecar-injection to direct overwrite.

### 4.2 "python3: command not found" in CI container

**Cause:** `git-filter-branch` runs tree-filters in a minimal subshell that may not have the host's PATH. But the README generation happens BEFORE filter-branch, in the container's main shell.

**Fix:** Use cascading tool availability checks. For Nix-based CI images:

```bash
if command -v python3 >/dev/null 2>&1; then
    python3 ...
elif command -v nix >/dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#python3 ...
else
    echo "ERROR: python3 not found and nix not available" >&2; exit 1
fi
```

### 4.3 "experimental Nix feature 'nix-command' is disabled"

**Cause:** `nix run` requires `nix-command` and `flakes` experimental features, which may be disabled in CI containers.

**Fix:** Always pass `--extra-experimental-features 'nix-command flakes'` to `nix run` in CI scripts. Do not rely on `NIX_CONFIG` — some container images ignore it.

### 4.3a Forward sync only rewrites COMMITTER, leaks AUTHOR identity

In `mirror-sync-forward.sh`, when `should_rewrite=1`, the commit command must set
**both** `GIT_AUTHOR_NAME/EMAIL` and `GIT_COMMITTER_NAME/EMAIL` to the bot
identity. A common copy/paste error leaks the original author into the Git tree:

```bash
# WRONG — only COMMITTER is rewritten, AUTHOR leaks original identity:
GIT_AUTHOR_NAME="$author_name"      # ← leaks real name!
GIT_AUTHOR_EMAIL="$author_email"    # ← leaks real email!
GIT_COMMITTER_NAME="$commit_name"
GIT_COMMITTER_EMAIL="$commit_email"

# CORRECT — both author and committer use bot identity:
GIT_AUTHOR_NAME="$commit_name"
GIT_AUTHOR_EMAIL="$commit_email"
GIT_COMMITTER_NAME="$commit_name"
GIT_COMMITTER_EMAIL="$commit_email"
```

### 4.3b Author/Committer split for audit trail

When `PUBLIC_GITHUB_COMMITTER_NAME` / `PUBLIC_GITHUB_COMMITTER_EMAIL` are set,
the commit semantics become:

| Field | Value | Meaning |
|-------|-------|---------|
| `GIT_AUTHOR_NAME/EMAIL` | `PUBLIC_GITHUB_COMMIT_NAME/EMAIL` | The "public" bot who conceptually wrote the code |
| `GIT_COMMITTER_NAME/EMAIL` | `PUBLIC_GITHUB_COMMITTER_NAME/EMAIL` | The CI runner that applied + committed the patch (e.g. `Drone CI`) |

```bash
commit_name="${PUBLIC_GITHUB_COMMIT_NAME:-j0nix mirror bot}"
commit_email="${PUBLIC_GITHUB_COMMIT_EMAIL:-mirror@example.invalid}"
committer_name="${PUBLIC_GITHUB_COMMITTER_NAME:-$commit_name}"
committer_email="${PUBLIC_GITHUB_COMMITTER_EMAIL:-$commit_email}"

# In the rewrite branch:
GIT_AUTHOR_NAME="$commit_name"
GIT_AUTHOR_EMAIL="$commit_email"
GIT_COMMITTER_NAME="$committer_name"
GIT_COMMITTER_EMAIL="$committer_email"
```

This preserves meaningful git semantics: `git log` shows the public author,
`git log --format=fuller` reveals which CI runner built the commit. If the
committer vars are unset, they fall back to the author vars (no breaking change).

The `no-rewrite` branch (preserve mode) keeps original author and committer
unchanged as intended.

Verify the identity of a rewritten commit before pushing:
```bash
git log --format="%H %an <%ae> %cn <%ce>" -1 <commit-hash>
```

Both author and committer should display `PUBLIC_GITHUB_COMMIT_NAME` and
`PUBLIC_GITHUB_COMMIT_EMAIL`. If the author still shows the original identity,
the `GIT_AUTHOR_*` variables were not set to the bot values.

### 4.4 filter-branch leaves `refs/original/` — bloats clone

**Fix:** Always delete after filter-branch:
```bash
rm -rf .git/refs/original/
```

### 4.6 Blacklisted files leak into older commits

**Cause:** Reading `.mirror-blacklist` from the *current commit* inside the `tree-filter` means older commits that did not yet contain the blacklist file have nothing stripped.

**Fix:** Read the blacklist from the **source repository** (outside the worktree) so the current blacklist applies retroactively to every commit:

```bash
# In the tree-filter, read the blacklist from $repo_root (original repo, not the worktree):
tree_filter='
    # Read from source repo — applies to ALL commits, even ones before the
    # blacklist file was created.
    blacklist_path="'"$repo_root"'/.mirror-blacklist"
    if [ -f "$blacklist_path" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            rm -rf "$line"
        done < "$blacklist_path"
    fi
    rm -f .mirror-blacklist  # strip the file itself too
'
```

### 4.8 Tracked secrets files must not be listed in `.gitignore`

**Cause:** A secrets file (e.g. `settings.nix`) that is required by `nix flake check` or other build steps inside the `tree-filter` is listed in `.gitignore` but **not committed** to the source repository. Git sees an ignored, untracked file and marks the working tree as dirty, causing `filter-branch` to abort with *"Cannot rewrite branches: You have unstaged changes."*

**Fix:** Remove the file from `.gitignore` and commit it to the **private source** repository. The mirror pipeline strips or replaces it via the `tree-filter` anyway, so the public mirror never sees the real content. `.gitignore` should only cover *local-only* overrides (e.g. `settings.local.nix`, `profiles/desktop/details.local.nix`). Never ignore a file that the build requires while leaving it untracked.

```bash
# .gitignore (correct)
settings.local.nix
profiles/desktop/details.local.nix
# NOT: settings.nix  — must be tracked in private source
```

**Validation:**
```bash
git status --short
# Should show nothing (clean tree) before running filter-branch
```

> See `references/j0nix-os-gitignore-policy.md` for the repo-specific policy and rationale (j0nix-os: no required files in `.gitignore`; tracked files stay tracked, `.example` replaces them in the mirror pipeline).

---

### 4.12 Tracked files in `.gitignore` corrupt the Nix flake

**Cause:** A file required by `nix flake check` (e.g. `settings.nix`,
`.sops.yaml`) is listed in `.gitignore` but not committed to the repository.
Git sees an ignored, untracked file and marks the working tree as dirty.
More critically, **Nix flakes refuse to evaluate files not tracked by Git** —
an ignored but required file causes `nix flake check` to fail with a path
resolution error or "file not found".

This creates a dangerous ambiguity: the file exists locally (so builds succeed
for the user who created it), but it fails for anyone else cloning the repo,
and the mirror pipeline's `filter-branch` aborts with *"Cannot rewrite branches:
You have unstaged changes."*

**Fix — commit required files; never list them in `.gitignore`:**

```bash
# .gitignore (correct pattern)
settings.local.nix
profiles/desktop/details.local.nix
# NOT: settings.nix  — must be tracked in private source
# NOT: .sops.yaml     — must be tracked in private source
# NOT: hardware-configuration.nix — must be tracked in private source
```

Files that the build requires must be **tracked in the private source**
repository. The mirror pipeline will strip or replace them via the tree-filter
anyway, so the public mirror never sees the real content. `.gitignore` should
only cover *local-only* overrides (`.local.nix`, `.bak`, `*.tmp`) and files
that genuinely never belong in any commit (IDE configs, build artefacts).

**Policy for j0nix-os:**
- `settings.nix`, `.sops.yaml`, `profiles/desktop/details.nix`,
  `profiles/desktop/hardware-configuration.nix` — **tracked**, never ignored
- Their `.example` templates exist for the public mirror workflow
- `.local.nix` variants for per-developer overrides — **ignored**, never tracked

**Validation:**
```bash
git status --short
# Should show nothing (clean tree) before running filter-branch
# `nix flake check --no-build` must pass on a fresh clone
```

**Pipeline impact:** If a required file is untracked, `filter-branch` sees a
dirty tree and aborts. If the file is tracked but also in `.gitignore`, Git
behaves inconsistently across versions — some mark the tree dirty, others
don't. Remove from `.gitignore` and commit to eliminate the ambiguity entirely.

> See `references/j0nix-os-gitignore-policy.md` for the full reasoning and edge
cases.

---

### 4.8 Root whitelist safety net for unknown top-level files

**Cause:** A secret, temporary file, or developer artifact (e.g. `/RESUME.sh`, `.env.local`, `notes.txt`) lands in the repo root but is not added to `.mirror-blacklist`. Older commits may also contain root files that should never be public.

**Fix:** Maintain a **root whitelist** (`.mirror-root-whitelist`) listing every top-level file explicitly allowed. The `tree-filter` iterates root entries and removes any regular file not in the list. Directories are untouched.

```bash
tree_filter='
    whitelist_path="'"$repo_root"'/.mirror-root-whitelist"
    if [ -f "$whitelist_path" ]; then
        whitelist=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            whitelist="$whitelist $line"
        done < "$whitelist_path"

        for entry in .* *; do
            case "$entry" in "."|"..") continue ;; esac
            [ -f "$entry" ] || continue
            case " $whitelist " in
                *" $entry "*) ;;
                *) rm -f "$entry" ;;
            esac
        done
    fi
'
```

Whitelist entries: `.gitignore`, `.mirror-root-whitelist`, `.sops.yaml`, `AGENTS.md`, `LICENSE`, `Makefile`, `README.md`, `flake.lock`, `flake.nix`, `settings.nix`.

The file must be public (documented in repo) and stripped from the mirror itself:
```bash
rm -f .mirror-blacklist .mirror-root-whitelist
```

When using `--parent-filter` to strip commits before a cutoff, the first rewritten commit after the cutoff becomes a new root. Use a **token-based bash script** instead of `sed` or string substitution — both produce whitespace artifacts on merge commits and `sed` may be missing in minimal subshells:

```bash
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

git filter-branch --parent-filter "$parent_filter_path" ...
```

See `references/parent-filter-token-based-parsing.md` for full rationale, the old broken approaches (sed, `${line//pattern/}`), and verification recipes.

---

### 4.9 Incremental sync: identity rewrite silently disabled when `_FALLBACK` env vars missing

**Cause:** The incremental scripts (`mirror-sync-forward.sh`, `mirror-sync-backward.sh`) resolve rewrite patterns with the two-key fallback pattern:

```bash
rewrite_emails="${PUBLIC_GITHUB_REWRITE_EMAILS:-${PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK:-}}"
```

If the Drone step does **not** declare `PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK` (or `NAMES_FALLBACK`) in its `environment` block, and the secret is empty or not injected, the expansion yields `""` → `ms_build_patterns("")` returns `___NO_MATCH_SENTINEL___` → no commits match → **no identity rewrite happens at all**.

The full-rewrite script (`publish-public-github.sh`) had this fallback for a long time, but the incremental script and its `.drone.star` step definition were missing the fallback keys, causing a silent no-rewrite.

**Fix:** Ensure ALL mirror scripts that need a fallback have the corresponding `_FALLBACK` key in the Starlark `environment` block:

```python
"environment": {
    "PUBLIC_GITHUB_REWRITE_EMAILS": {"from_secret": "public_github_rewrite_emails"},
    "PUBLIC_GITHUB_REWRITE_EMAILS_FALLBACK": "",
    "PUBLIC_GITHUB_REWRITE_NAMES": {"from_secret": "public_github_rewrite_names"},
    "PUBLIC_GITHUB_REWRITE_NAMES_FALLBACK": "",
}
```

**Verification:**

```bash
# After injection, check that the variable is not empty when it should carry patterns
echo "rewrite_emails='$rewrite_emails'"
echo "rewrite_names='$rewrite_names'"
# Both should show the comma-separated list, not empty or no output.
```

---

## 5. Checklist Before Running

- [ ] `nix flake check --no-build` passes on source repo
- [ ] `.mirror-blacklist` exists and covers all sensitive paths
- [ ] `settings.nix.example`, `details.nix.example`, `hardware-configuration.nix.example`, `.sops.yaml.example` exist
- [ ] `PUBLIC_GITHUB_TOKEN` or `PUBLIC_GITHUB_PRIVATE_KEY` is set in CI
- [ ] PAT auth strings in ALL scripts use `${PUBLIC_GITHUB_TOKEN}`, not literal `***` (verify: `grep -F 'oauth2:***' scripts/*.sh`)
- [ ] `README.md.tmpl` renders correctly with `make readme SCOPE=public`
- [ ] `.git/hooks/pre-commit` (if any) does not interfere with temp clones
- [ ] `refs/original/` is cleaned after filter-branch

---

## 6. Makefile Targets (Reference)

```makefile
readme-public:
	python3 scripts/regenerate-readme.py --scope public --output README.md

readme-private:
	python3 scripts/regenerate-readme.py --scope private --output README.md

check-readme:
	python3 scripts/regenerate-readme.py --scope private --check

check:
	nix flake check --no-build
```

---

## 7. Incremental Safe-Sync (Non-Force, No History Rewrite)

When the mirror already has a sane baseline and you only want new commits published without rewriting every commit hash, use an **incremental forward-sync** instead of `filter-branch`.

### When to use which script

| Script | Run frequency | Destructive? | Keeps old commit hashes? | Use case |
|---|---|---|---|---|
| `publish-public-github.sh` | Rarely (cutoff changes, retroactive blacklist updates) | Yes (force-push) | No (rewrites everything) | Full history rebuild |
| `mirror-sync-forward.sh` | Every push / on a schedule | No (fast-forward push) | Yes (only new commits are fabricated) | Day-to-day publishing |
| `mirror-sync-backward.sh` | After PR merges on GitHub | No | N/A | List GitHub-only commits to cherry-pick back into Gitea |

### Three-script architecture

| Script | Role |
|---|---|
| `scripts/lib/mirror-sanitize.sh` | Shared engine: blacklist, whitelist, template injection, README replacement. Callable from both forward and backward flows. |
| `scripts/mirror-sync-forward.sh` | Exports new Gitea commits since the last sync, sanitises their trees, optionally rewrites identity per author, then fast-forward pushes to GitHub. |
| `scripts/mirror-sync-backward.sh` | Lists commits present on GitHub but not in Gitea (e.g. merged PRs by external authors) so they can be cherry-picked back into the private source. |

### Tracking state: `last-synced-from-gitea`

The forward script tracks progress with a lightweight Git **tag** on the GitHub remote side (not on Gitea). The tag name is `last-synced-from-<source_name>` (default: `last-synced-from-gitea`).

- **First run:** The tag does not exist. The script falls back to `PUBLIC_CUTOFF_COMMIT` (env var or fallback). If that is also unset, it walks to the first commit of the branch.
- **Subsequent runs:** Only commits *after* the tagged commit are exported.
- **Update after push:** The script updates the tag to the latest successfully pushed source commit.

### Forward-sync flow

```
Gitea HEAD
    │
    ├── commit A ── sanitize tree ──► github HEAD + A
    ├── commit B ── sanitize tree ──► github HEAD + A + B
    ├── commit C (Dependabot) ── sanitize tree, PRESERVE identity ──► github HEAD + A + B + C
    │
    └── fast-forward push
```

1. Read `last_synced_source_commit` from the remote tag (fallback → cutoff).
2. Enumerate new commits with `git log --reverse --format=%H`.
3. For each commit:
   - Check out its tree into a temp worktree.
   - Run `mirror-sanitize.sh` to strip secrets, replace templates, inject public README.
   - Commit onto GitHub's current HEAD with `git commit-tree` (preserving original message + parent).
4. Fast-forward push the new HEAD.
5. Update the tracking tag.

### Backward sync (full implementation)

The backward sync lists GitHub-only commits and imports them back into Gitea.

```bash
./scripts/mirror-sync-backward.sh origin github main
```

**What it does:**
1. Builds an index of all GitHub `main` commit hashes that are ancestors of the current GitHub HEAD — used by `mirror-sync-forward.sh` to skip already-backward-imported commits on the next forward run.
2. Enumerates GitHub commits not present in Gitea (`$mirror_remote/$branch..$source_remote/$branch`).
3. **Skips bot commits** — commits whose author matches `PUBLIC_GITHUB_COMMIT_NAME` (the mirror bot) are ignored (were created by forward sync, not PR merges).
4. **Skips internal authors** — commits whose author name/email matches `^(jonas|j0nix)` are ignored (already exist in Gitea, divergence due to identity rewrite).
5. **Safe-diff-filter** — calls `ms_commit_is_safe()` from `mirror-sanitize.sh` to check whether the commit touches sensitive files (`.sops.yaml`, `settings.nix`, `secrets/**/*`, etc.). Unsafe commits are listed but flagged; they require manual cherry-pick because automatic import could leak secrets into Gitea.
6. Groups remaining commits by author with `git log --format="%H %s"`.
7. **Preservation of original authors** — for PR merge commits that pass the filters, the script can re-extract the *original* author metadata from GitHub commits (before identity rewrite happened on the forward path), so when cherry-picked back into Gitea they retain correct attribution.

**Integration with forward-sync deduplication:**
The forward script (`mirror-sync-forward.sh`) loads the GitHub commit index built by the backward script. If a commit hash from Gitea already exists on GitHub (because it was backward-imported), the forward sync skips it. This prevents the two directional syncs from ping-ponging the same commits.

**Usage:**
```bash
# Dry-run: list what would be imported
./scripts/mirror-sync-backward.sh origin github main

# After reviewing the list, cherry-pick specific commits into Gitea
git fetch github
git cherry-pick <commit-hash>
```

---

## 8. Selective Author Rewrite (All Scripts)

Commits 26ea799 → 50a3b63 introduced **selective** author rewriting across
all mirror scripts. Before this change, the `env-filter` rewrote **every**
commit to the bot identity, which corrupted signatures on commits by external
contributors (e.g. Dependabot).

### Current behavior

Only commits whose **original** `GIT_AUTHOR_EMAIL` contains any of the
configured substrings (or whose `GIT_AUTHOR_NAME` matches, if name patterns
are configured) are rewritten. All other commits keep their original author.

### Input: comma-separated substrings (no regex)

```bash
PUBLIC_GITHUB_REWRITE_EMAILS="jonas,j0nix,codepixelstudio"
PUBLIC_GITHUB_REWRITE_NAMES=""   # disabled by default
```

The substrings are converted to glob patterns (`*jonas*`, `*j0nix*`) and
matched using bash `case/esac` — no `grep`, no regex, no injection risk.

### Unified across all scripts

| Script | New variable(s) | Old variable (deprecated) |
|---|---|---|
| `publish-public-github.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` |
| `mirror-sync-forward.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` |
| `mirror-sync-backward.sh` | `PUBLIC_GITHUB_REWRITE_EMAILS` / `NAMES` | `PUBLIC_SANITIZE_AUTHOR_REGEX` |

The shared engine `scripts/lib/mirror-sanitize.sh` provides `ms_build_patterns()`
and `ms_should_match_patterns()` so all three scripts share identical behavior.

### Implementation in filter-branch env-filter

```bash
case "$GIT_AUTHOR_EMAIL" in
    *jonas*|*j0nix*|*codepixelstudio*) match_email=1 ;;
esac
case "$GIT_AUTHOR_NAME" in
    $rewrite_name_patterns) match_name=1 ;;
esac
if [ "$match_email" -eq 1 ] || [ "$match_name" -eq 1 ]; then
    export GIT_AUTHOR_NAME="$commit_name"
    export GIT_AUTHOR_EMAIL="$commit_email"
    export GIT_COMMITTER_NAME="$commit_name"
    export GIT_COMMITTER_EMAIL="$commit_email"
fi
```

> **Note:** `case` is a POSIX shell builtin that is guaranteed to exist in any
> filter-branch subshell, unlike `grep`, `sed`, or `awk` which may be missing.

### Result

| Original author | Match | Resulting commit author |
|---|---|---|
| `Jonas Tschoche` / `jonas.tschoche@gmx.de` | Yes (email) | Bot identity |
| `jonix` / `codepixelstudio.de` | Yes (email+name) | Bot identity |
| `dependabot[bot]` / `@users.noreply.github.com` | No | **Original preserved** |
| `rndexternal` / `foo@bar.com` | No | Original preserved |

### Legacy fallback

If `PUBLIC_GITHUB_REWRITE_EMAILS` is unset but `PUBLIC_SANITIZE_AUTHOR_REGEX`
is set, `scripts/lib/mirror-sanitize.sh` falls back to the old grep-based
regex mode for backward compatibility.

---

## 9. Identity Rewrite Modes (Incremental Sync)

The incremental sync supports three identity policies via `PUBLIC_GITHUB_IDENTITY_MODE`.

| Mode | Behaviour | Use case |
|---|---|---|
| `selective` (default) | Rewrite only authors matching `PUBLIC_SANITIZE_AUTHOR_REGEX` | Solo maintainer + occasional external PRs |
| `rewrite_all` | Rewrite **every** commit to the bot identity | Clean, uniform mirror history |
| `preserve` | Keep original identity for all commits | Debugging or when attribution must survive untouched |

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `PUBLIC_GITHUB_IDENTITY_MODE` | `selective` | Policy selector: `selective`, `rewrite_all`, or `preserve` |
| `PUBLIC_SANITIZE_AUTHOR_REGEX` | `^(jonas\|j0nix)` | PCRE regex for `selective` mode. Empty = rewrite nothing. |

### GitHub display-name gotcha (PAT vs SSH)

GitHub resolves commit authors to accounts via the **commit email**, not the `GIT_AUTHOR_NAME` string. If the bot email set via `PUBLIC_GITHUB_COMMIT_EMAIL` is already verified on your personal GitHub account, GitHub will display **your account's display name** (e.g. "jtschoch") even when the commit metadata says "j0nix mirror bot".

| Fix | How |
|---|---|
| Use `rewrite_all` + unlinked email | Set `PUBLIC_GITHUB_COMMIT_EMAIL` to an address not verified on any GitHub account (e.g. `mirror@j0nix.invalid`). GitHub then shows the raw committer name. |
| Dedicated bot account | Create a separate GitHub account, verify the bot email there, set its display name to "j0nix mirror bot". |
| SSH fallback | Accept that GitHub shows the SSH key owner's display name regardless of commit metadata (see §3.8 in ci-cd-pipeline-authoring skill). |

### How it works inside the forward script

The forward script builds each new commit with `git commit` using either:
- Bot identity (`GIT_AUTHOR_NAME`/`EMAIL` = `PUBLIC_GITHUB_COMMIT_NAME`/`EMAIL`) for rewritten commits, OR
- Original author/committer metadata copied from the source commit for preserved commits.

The **tree** is sanitised in both cases — only identity changes.

### When to use which mode

| Scenario | Recommended mode |
|---|---|
| Solo repo, want clean history | `rewrite_all` |
| Accept external PRs, want attribution | `selective` |
| Debugging identity issues | `preserve` |

---

## 10. Comparison: Full-Rewrite vs. Incremental

| Concern | Full rewrite (`filter-branch`) | Incremental (`mirror-sync-forward`) |
|---|---|---|
| Push type | Force-push | Fast-forward (non-force) |
| Downstream forks | Must hard-reset | Uninterrupted |
| PR merge commits | Re-appear with bot identity | Retain original identity if author matches |
| Retroactive sanitization | Works (apply new blacklist to entire history) | Does not affect already-published commits |
| CI runtime | Grows with repository size | Proportional to new commits only |
| First-time setup | Requires cutoff commit | Same, or can start from an empty mirror |

**Recommendation:** Use the incremental scripts for daily publishing. Keep the full-rewrite script for rare events: rotating a leaked secret that was already published, adding a new root-whitelist entry that must apply retroactively, or changing the cutoff commit.

---

## 11. Adapting Mirror Scripts to a Different Project

The scripts in this skill were originally authored for a NixOS project (`j0nix-os`). When reusing them for an Android (or any other) project, update **three locations** that contain hardcoded paths:

| File | What to change |
|---|---|
| `scripts/lib/mirror-sanitize.sh` | `ms_sensitive_files_list()` — replace NixOS hardcoded paths with project-specific sensitive paths. |
| `scripts/publish-public-github.sh` | Tree-filter heredoc — replace `rm -f .sops.yaml settings.nix ...` with the new project's proprietary/private paths. |
| `scripts/export-public-github.sh` | `remove_paths` array — same as above. |

### Android-specific checklist
- Strip `app/src/play/`, `playDebug/`, `playUnitTest/`, `testPlay/`
- Strip `docs/private/`
- Strip signing keys (`*.jks`), `secrets/`, `keystore/`
- Strip `local.properties` (SDK paths, API keys)
- Strip `.drone.yml` AND `.drone.star` (private CI config — `.drone.star` is the Starlark variant)
- Strip `.ai/`, `.hermes/` (AI/agent working files — prompts, plans, session data)
- Strip `archive/` (internal archive directory)
- Strip `templates/` (README templates with private-scope variables)
- Strip `README.md.public` (private-to-public README transform source — the public README is injected separately)
- Strip `shared-test/` if it contains old package references (e.g. `com.taru.test` from a renamed project)
- Strip `ads.env` if present — tracked env file containing AdMob ad unit IDs and billing product IDs for the play flavor (tracked in private repo, injected at build time by `ci-inject-ad-config.sh`)

### Post-export verification (run after export-public-github.sh)

Always verify the exported tree before pushing. A single grep catches most leaks:

```bash
# Check for Google Play Services / billing / AdMob IDs in exported source
grep -r "com.google.android.gms\|com.android.billing\|ca-app-pub" /tmp/export/app/src/ | head -5

# Expected: zero hits in app/src/ (build.gradle references to playImplementation are OK
# — they're flavor-scoped and won't resolve in the fdroid build)

# Verify play/ source set is gone
ls /tmp/export/app/src/play 2>&1  # should be "No such file or directory"

# Verify CI config is gone
ls /tmp/export/.drone.star /tmp/export/.drone.yml 2>&1  # both should be missing

# Verify README has public header (not "private source")
head -3 /tmp/export/README.md
```

### Common pitfall: bare path in tree-filter
A tree-filter is a shell command. Writing a bare directory path like:
```bash
docs/private/ 2>/dev/null || true
```
does nothing (the path is interpreted as a command, not an argument to `rm`). Always prefix with `rm -rf`:
```bash
rm -rf docs/private/ 2>/dev/null || true
```

### README generator fallback
If the source project has no `templates/README.md.tmpl`, replace the template-based `regenerate-readme.py` with an in-place transformer that injects the public/private header into the existing `README.md`. This removes the template dependency entirely.

---

## Related Files

> - `references/incremental-sync-scripts.md` — Full reproduction of `mirror-sanitize.sh`, `mirror-sync-forward.sh`, and `mirror-sync-backward.sh` for adaptation and study.
> - `references/adapting-to-android-project.md` — Step-by-step adaptation notes from j0nix-os (NixOS) to rydeon-android (Android).
> - `references/private-flake-input-stripping.md` — Stripping private flake inputs (`flake.nix` block + `flake.lock` node) from public mirrors across all three mirror scripts in sync.

