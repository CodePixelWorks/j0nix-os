# GPG Signing for Mirror Commits

Sign rewritten commits in a public mirror so GitHub shows **Verified** badge.

## Two-key architecture (Personal vs. Mirror-bot)

Jonas' setup separates the GPG keys by trust boundary:

| Key type | Lives in | Passphrase? | Used by | Where registered |
|---|---|---|---|---|
| **Personal** (e.g. `github-codepixelstudio`) | SOPS (`secrets/users/jonas.yaml`) | Yes | Local workstation git signing | User's GitHub account + `settings.nix` `dev.gpg.keys` |
| **Mirror-bot** (e.g. `j0nix mirror bot`) | Drone secret (`public_github_signing_key`) | **Optional** | CI scripts that rewrite commits | Bot/personal GitHub account |

## Passphrase-protected key in CI — wrapper approach (since commit 5b446b4)

The forward sync supports passphrase-protected keys via a **gpg-wrapper script**
instead of the fragile `gpg --edit-key` passphrase-removal that silently
failed in CI with `|| true`.

**Why the old approach failed:**
`gpg --edit-key` with `passwd\n<old>\n\n\nsave\n` fed via `--command-fd 0`
silently failed (`|| true` masked the error), leaving the key
passphrase-protected. Later, `gpg --batch --pinentry-mode loopback` without
a passphrase produced:

```
gpg: Sorry, we are in batchmode - can't get input
```

The fix replaces passphrase-*removal* with passphrase-*injection*: keep the
passphrase in a scoped variable and inject it into every `gpg` call via a
wrapper script.

| Drone Secret | Content |
|---|---|
| `public_github_signing_key` | ASCII-armored private key (may have passphrase) |
| `public_github_signing_passphrase` | Passphrase for the key above |

Pipeline flow:

1. **Import** the key with `--pinentry-mode loopback --passphrase`:
   ```bash
   printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | \
       gpg --batch --pinentry-mode loopback \
           --passphrase "$PUBLIC_GITHUB_SIGNING_PASSPHRASE" \
           --import 2>/dev/null
   ```

2. **Preserve** the passphrase in a scoped variable, then unset the original
   secret from the environment:
   ```bash
   mirror_gpg_passphrase="${PUBLIC_GITHUB_SIGNING_PASSPHRASE:-}"
   if [ -n "$mirror_gpg_passphrase" ]; then
       unset PUBLIC_GITHUB_SIGNING_PASSPHRASE
       export MIRROR_GPG_PASSPHRASE="$mirror_gpg_passphrase"
   fi
   ```

3. **Create** a `gpg-wrapper` script inside `$GNUPGHOME` that injects
   `--pinentry-mode loopback --passphrase` when `MIRROR_GPG_PASSPHRASE` is set:
   ```bash
   gpg_wrapper="$gpg_dir/gpg-wrapper"
   cat > "$gpg_wrapper" <<'GPGWRAP'
#!/usr/bin/env bash
if [ -n "${MIRROR_GPG_PASSPHRASE:-}" ]; then
    exec gpg --pinentry-mode loopback --passphrase "$MIRROR_GPG_PASSPHRASE" "$@"
else
    exec gpg "$@"
fi
GPGWRAP
   chmod +x "$gpg_wrapper"
   git config --global gpg.program "$gpg_wrapper"
   ```

4. **Sign** commits normally with `git commit -S` or `git commit-tree --gpg-sign`.
   The wrapper transparently adds `--passphrase` for every `gpg` invocation.

5. **Cleanup** the temp GNUPGHOME on script exit.

**Security note:** The passphrase exists only in the CI container's RAM during
startup. `PUBLIC_GITHUB_SIGNING_PASSPHRASE` is `unset` from the environment
immediately; only `MIRROR_GPG_PASSPHRASE` remains (still in-process memory
only). When possible, use a passphrase-less bot key for the mirror (simpler and
fewer moving parts). Jonas' setup uses passphrase-protected as defense-in-depth
(values "nur zur Sicherheit" cascading safeguards).

**When to use which approach:**

| Approach | Pros | Cons |
|---|---|---|
| Passphrase-less bot key | Simpler, one secret | Leaked key = immediate compromise |
| Passphrase-protected key + wrapper injection | Defense-in-depth; passphrase never removed from key | One extra wrapper script |
| Passphrase-protected key + `--edit-key` removal | (broken, do not use) | Silently fails; masked by `|| true` |

---

## Deploying the personal key (SOPS → Home Manager)

For local git signing with per-email key selection:

1. **Generate the key:**
   ```bash
   gpg --full-generate-key
   # Name: Jonas Tschoche, Email: me@codepixelstudio.de
   ```

2. **Collect metadata:**
   ```bash
   gpg --list-secret-keys --with-colons me@codepixelstudio.de | awk -F: '$1=="fpr"{print $10;exit}'
   gpg --list-secret-keys --with-colons --with-keygrip me@codepixelstudio.de | awk -F: '$1=="grp"{print $10}'
   ```

3. **Export to SOPS-encrypted secrets:**
   ```bash
   sops secrets/users/jonas.yaml
   # Add under gpg:<keyname>:private and gpg:<keyname>:passphrase
   ```

4. **Register in `settings.nix` (two places):**

   a) Under `settings.userSettings.<name>.secrets.gpgKeys` (for SOPS secret import):
   ```nix
   gpgKeys = {
     github-codepixelstudio = {
       key = "gpg/github-codepixelstudio/private";
       passphraseKey = "gpg/github-codepixelstudio/passphrase";
       fingerprint = "854C0BE0F7AB04F2A8B1CB725388423005575586";
       keygrips = [
         "F19A8D49BD3B1C32D836BC53008EF52FCBBF0DEE"
         "698CFD158677015DAB48D1B12040C5A374FA022D"
       ];
       mode = "0400";
       passphraseMode = "0400";
     };
   };
   ```

   b) Under `settings.userSettings.<name>.dev.gpg.keys` (for git email→key mapping):
   ```nix
   dev.gpg.keys = {
     "github-codepixelstudio" = {
       key = "854C0BE0F7AB04F2A8B1CB725388423005575586";
       emails = [ "me@codepixelstudio.de" ];
       signByDefault = true;
     };
   };
   ```

   The `gpgKeys` block drives **secret import** (Home Manager deploys the private key + passphrase into `~/.gnupg`). The `dev.gpg.keys` block drives **git signing selection** (`default.nix` matches commit author email to the right GPG fingerprint).

5. **Validate and rebuild:**
   ```bash
   nix flake check --no-build
   sudo nixos-rebuild switch --flake .#Jonas-PC
   ```

---

## Generating the CI mirror-bot signing key

Create a keypair **without passphrase** (CI cannot interactively unlock):

```bash
# Generate key
export GNUPGHOME=$(mktemp -d)
gpg --batch --passphrase '' --quick-gen-key \
    "j0nix mirror bot <mirror@j0nix.invalid>" default default

# Export secret key (store as Drone secret: public_github_signing_key)
gpg --armor --export-secret-keys "mirror@j0nix.invalid" > mirror-signing.key

# Export public key (register on GitHub)
gpg --armor --export "mirror@j0nix.invalid" > mirror-signing.pub

rm -rf "$GNUPGHOME"
```

> **Email must match**: The email address in the GPG key **must match** `PUBLIC_GITHUB_COMMIT_EMAIL`. If it does not, GitHub will not show the Verified badge even though the commit is technically signed.

## Registering at GitHub

1. Open GitHub Settings → SSH and GPG keys → New GPG key
2. Paste contents of `mirror-signing.pub`
3. The key now validates any commit whose author/committer email matches the key's UID

## Drone CI wiring

```python
env = {
    "PUBLIC_GITHUB_SIGNING_KEY": {"from_secret": "public_github_signing_key"},
    "PUBLIC_GITHUB_COMMIT_NAME": {"from_secret": "public_github_commit_name"},
    "PUBLIC_GITHUB_COMMIT_EMAIL": {"from_secret": "public_github_commit_email"},
}
```

The `public_github_signing_key` secret contains the **ASCII-armored private key**. It is imported into a temporary `GNUPGHOME` directory inside the sync script and never written to disk outside that temp dir.

## Script implementation

Inside `mirror-sync-forward.sh`:

```bash
gpg_key_id=""
gpg_dir=""
if [ -n "${PUBLIC_GITHUB_SIGNING_KEY:-}" ]; then
    gpg_dir="$(mktemp -d -t mirror_gpg.XXXXXX)"
    chmod 700 "$gpg_dir"
    export GNUPGHOME="$gpg_dir"

    # Import: with passphrase if provided, otherwise bare import
    if [ -n "${PUBLIC_GITHUB_SIGNING_PASSPHRASE:-}" ]; then
        printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | \
            gpg --batch --pinentry-mode loopback \
                --passphrase "$PUBLIC_GITHUB_SIGNING_PASSPHRASE" \
                --import 2>/dev/null
    else
        printf '%b\n' "$PUBLIC_GITHUB_SIGNING_KEY" | gpg --batch --import 2>/dev/null
    fi

    gpg_key_id="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec/{print $5}' | head -n1)"

    if [ -n "$gpg_key_id" ]; then
        printf '%s\n' "GPG signing configured (key ${gpg_key_id:0:16}...)"

        # Preserve passphrase in a scoped variable so git/gpg pipelines can
        # sign headlessly without relying on fragile --edit-key removal.
        mirror_gpg_passphrase="${PUBLIC_GITHUB_SIGNING_PASSPHRASE:-}"
        if [ -n "$mirror_gpg_passphrase" ]; then
            unset PUBLIC_GITHUB_SIGNING_PASSPHRASE
            export MIRROR_GPG_PASSPHRASE="$mirror_gpg_passphrase"
        fi

        print_public_signing_key "$gpg_key_id"
        git config --global user.signingkey "$gpg_key_id"

        # gpg wrapper for headless signing. Git commit-tree and commit --gpg-sign
        # call gpg in non-batch mode; the wrapper injects passphrase so pinentry
        # never blocks in CI.
        gpg_wrapper="$gpg_dir/gpg-wrapper"
        cat > "$gpg_wrapper" <<'GPGWRAP'
#!/usr/bin/env bash
if [ -n "${MIRROR_GPG_PASSPHRASE:-}" ]; then
    exec gpg --pinentry-mode loopback --passphrase "$MIRROR_GPG_PASSPHRASE" "$@"
else
    exec gpg "$@"
fi
GPGWRAP
        chmod +x "$gpg_wrapper"
        git config --global gpg.program "$gpg_wrapper"
    else
        printf '%s\n' "WARN: could not import GPG signing key" >&2
    fi
fi
```
All `git commit` calls that create rewritten commits append `-S`:

```bash
commit_args="--allow-empty"
[ -n "$gpg_key_id" ] && commit_args="$commit_args -S"

GIT_AUTHOR_NAME="..." GIT_AUTHOR_EMAIL="..." \
    git commit $commit_args -m "$msg"
```

Cleanup in trap:
```bash
cleanup() {
    [ -n "$gpg_dir" ] && rm -rf "$gpg_dir" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
```

## Verified vs Unverified on GitHub

| Scenario | GitHub display |
|---|---|
| Signed, key registered, email matches UID | Green "Verified" |
| Signed, key registered, email **does not** match UID | Gray "Unverified" |
| Not signed | No badge |

## Troubleshooting

### "gpg: no valid OpenPGP data found"

The secret contains literal newlines incorrectly escaped. Ensure the Drone secret stores the **raw ASCII-armored key** including `-----BEGIN PGP PRIVATE KEY BLOCK-----` headers and newlines.

### "error: gpg failed to sign the data"

- Key was generated **with** a passphrase but `public_github_signing_passphrase` secret is missing or empty. Both secrets are required when the key is protected.
- `GNUPGHOME` is not exported in the subshell where `git commit` runs.
- The `gpg-wrapper` script is missing or not executable — check that `git config --global gpg.program` points at a valid path.

### Verified badge missing despite successful signing

- Email mismatch between GPG UID and `PUBLIC_GITHUB_COMMIT_EMAIL`
- Public key not uploaded to the **same GitHub account** that owns the target repo
- Using a Fine-Grained PAT from a different account than the one with the registered GPG key

## Full rewrite with `filter-branch --commit-filter`

The incremental approach above (§ Incremental sync scripts) creates new commits with `git commit -S` directly. But the **full-rewrite** script (`publish-public-github.sh`) must sign commits that are being rewritten by `git filter-branch`, not created from scratch.

### Why `git-filter-repo` is unsuitable

`git-filter-repo` uses `git fast-export | filter | git fast-import`. The fast-export format does not carry `gpgsig` headers, so all existing signatures are stripped. There is no `--gpg-sign` option or Python callback to recreate signatures. For full-rewrite GPG signing, stay with `git filter-branch`.

### `--commit-filter` approach (current working pattern)

`filter-branch` accepts a `--commit-filter <command>` that replaces the internal `git commit-tree` call. The filter receives `<TREE_ID> [(-p <PARENT_SHA>)...]` and the commit message on stdin. The rewritten `GIT_AUTHOR_EMAIL` is visible inside the filter, so you can sign only commits whose identity was changed.

**Critical incompatibilities discovered in practice:**
1. `--prune-empty` and `--commit-filter` are **mutually exclusive** — `filter-branch` aborts with:
   ```
   Cannot set --prune-empty and --commit-filter at the same time
   ```
   You must implement empty-commit pruning inside the filter function itself.
2. The filter must be **sourced**, not executed as a standalone binary, because `filter-branch` helper `map` is only available in the filter-branch subshell.
3. Use POSIX `.` instead of bash `source` — filter-branch may invoke the filter in `/bin/sh`.
4. `GIT_AUTHOR_EMAIL` is inherited from the `--env-filter` because it was `export`ed there.

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

**Requirements:**
- `GNUPGHOME` exported in the main shell so `git commit-tree` finds the imported key.
- The commit-filter is written to a temp file (not inlined) because `filter-branch` passes filters through `eval`.
- The `GIT_AUTHOR_EMAIL` check ensures only rewritten commits (whose author was changed by the `--env-filter`) get signed. Unchanged commits pass through unsigned.
- `--prune-empty` must be removed from the filter-branch invocation. Empty-commit pruning is handled inside `run_commit_filter`.
- **Do not use `sed`** to template the standalone filter scripts — the CI container itself may lack `sed` (observed in `nixos/nix:2.26.1` runners). Provide a `run_sed` helper that fetches `gnused` from nixpkgs when the host binary is missing. **Never use `|` as the sed delimiter** when `run_sed` resolves to `nix run nixpkgs#gnused`; `nix` CLI argument parsing mangles the pipe character. Use `#` (or another safe character) instead.

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

> **Note:** Use `nix shell --command` not `nix run`. `nix run` passes arguments through a different path that corrupts single-quoted sed expressions (e.g. `'s|foo|bar|g'` becomes `s|foo|bar|g` without quotes inside gnused).

### GPG signing diagnostics block

After filter-branch completes, print the GPG status of recent commits so CI logs reveal whether signing worked before pushing:

```bash
# After rm -rf .git/refs/original/
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

Git format placeholders:
- `%H` — commit hash
- `%G?` — `N` = not signed, `G` = valid signature, `U` = valid but untrusted
- `%GS` — key ID of the signer

This does not leak secrets because author/committer emails have already been rewritten by the env-filter at this point.

---

### 4.5b Diagnostic format-string trap: trailing whitespace breaks `grep`

**Cause:** `git log --format='%H %G? %GS' -5` leaves the `%GS` field **empty** when a commit is unsigned (`%G? = N`). The trailing whitespace after `%G?` then contains the empty `%GS`, producing lines like:

```
6806f90a8298d9f02d95b356f4561bf7ca66113f N 
```

Using `grep -c ' N$'` to count unsigned commits fails silently because the line does not actually end with `N` — it ends with `N ` (trailing space). Your diagnostic logs then show `0` unsigned commits and prematurely print *"OK: all last 5 commits carry a GPG signature"* even though every commit is unsigned.

**Fix:** Use a **pipe-delimited** format and add an explicit sentinel after `%GS` so trailing whitespace is irrelevant:

```bash
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

The `|#` sentinel gives `grep` a robust anchor that never depends on invisible trailing spaces.

---

### 4.5c GPG environment isolation inside `--commit-filter`

**Cause:** `git filter-branch --commit-filter ". '$path'"` sources the filter script in a **subshell** whose environment differs from the main script's shell. In practice:
- `GNUPGHOME` may not propagate to the commit-filter even when `export`ed in the parent shell.
- The `GIT_DIR` and `GIT_WORK_TREE` variables set *by* `filter-branch` internally can confuse `gpg` if you pass them explicitly to reach `GNUPGHOME`.
- `gpg --list-secret-keys` may report "no secret key" inside the filter but succeed in the main shell.
- `gpg-agent` may not be running inside a temp `GNUPGHOME`, causing `--batch` sign operations to silently fail with no diagnostic output.

**Fix — robust pre-test before `filter-branch`:**

The pre-test must:
1. Start `gpg-agent --daemon` explicitly inside the temp homedir (may be missing).
2. Use `--pinentry-mode loopback` so a remaining passphrase cannot silently deadlock `pinentry` in a non-interactive/CI context.
3. Capture `stderr` to a temp file and print it on failure instead of suppressing it with `2>/dev/null`.

```bash
printf '%s\n' "--- GPG pre-test ---"
if [ -n "${gpg_key_id}" ] && [ -n "${gpg_dir}" ] && [ -d "${gpg_dir}" ]; then
    GNUPGHOME="${gpg_dir}" gpg --list-secret-keys "${gpg_key_id}" \
        >/dev/null 2>/dev/null && \
        printf '%s\n' "GPG pre-test: key ${gpg_key_id:0:16}... found in GNUPGHOME" || \
        printf '%s\n' "GPG pre-test: key ${gpg_key_id:0:16}... NOT found"

    # Ensure gpg-agent is available inside the temp homedir before signing.
    GNUPGHOME="${gpg_dir}" gpg-agent --daemon 2>/dev/null || true

    # Direct signatures test with loopback so a remaining passphrase does not
    # silently deadlock pinentry in a non-interactive context.
    sign_stderr="$(mktemp -t gpg_sign_test.XXXXXX)"
    gpg_sign_test_args=()
    if [ -n "${MIRROR_GPG_PASSPHRASE:-}" ]; then
        gpg_sign_test_args=(--pinentry-mode loopback --passphrase "$MIRROR_GPG_PASSPHRASE")
    fi
    if printf '%s\n' "test body" | GNUPGHOME="${gpg_dir}" gpg --armor --detach-sign \
            --local-user="${gpg_key_id}" --batch "${gpg_sign_test_args[@]}" -o /dev/null 2>"$sign_stderr"; then
        printf '%s\n' "GPG pre-test: direct sign succeeded"
    else
        printf '%s\n' "ERROR: GPG pre-test direct sign failed"
        printf '%s\n' "--- GPG stderr ---"
        cat "$sign_stderr"
        printf '%s\n' "---"
        rm -f "$sign_stderr"
        exit 1
    fi
    rm -f "$sign_stderr"
else
    printf '%s\n' "GPG pre-test: not configured (no key_id or dir)"
fi
printf '%s\n' "---"
```

**Why `--batch` alone is dangerous in CI:**
Without `--pinentry-mode loopback`, a passphrase-protected key (or a freshly imported key whose passphrase was not removed) will attempt to spawn `pinentry`. In a non-interactive CI container this silently deadlocks and the `gpg` invocation returns failure with no stderr. Using `2>/dev/null` then makes the failure invisible.

**Why `--pinentry-mode loopback` is required even with the wrapper:**
`git commit-tree --gpg-sign` and `git commit --gpg-sign` call `gpg` in
non-batch mode. In a non-interactive CI container, `pinentry` cannot spawn a
TUI. Loopback mode forces GPG to read the passphrase from the command
line/fd provided by the wrapper, preventing the silent deadlock.

**Why capture stderr to a temp file:**
`gpg` may emit useful diagnostics (`gpg: no pinentry`, `gpg: agent_genkey failed`, `gpg: signing failed: No passphrase given`) that are the only clue to why signing failed. Routing stderr to `/dev/null` loses the only actionable error message.

2. **commit-filter reachability check** (proves the filter *itself* can reach GPG):

Inside `run_commit_filter`, before calling `git commit-tree --gpg-sign`, add:

```bash
    if [ -n "$gpg_key" ]; then
        if gpg --list-secret-keys "$gpg_key" >/dev/null 2>/dev/null; then
            git commit-tree --gpg-sign="$gpg_key" "$tree_id" "${original_args[@]}"
        else
            printf '%s\n' "[commit-filter] WARN: gpg key $gpg_key not found (GNUPGHOME=${GNUPGHOME:-not set})" >&2
            git commit-tree "$tree_id" "${original_args[@]}"
        fi
    fi
```

**Key rule:** Do **not** set `GIT_DIR="" GIT_WORK_TREE="${GNUPGHOME:-}"` before `gpg` inside the commit-filter. Those variables are Git-specific and have no meaning to GPG; they only pollute the environment.

## Advanced: One-key approach (not recommended)

If you want to use the same passphrase-protected personal key in CI without the separate passphrase secret, you would need to export the key passphrase-less beforehand. This is **less secure** because the passphrase-less key in a single secret is a single point of failure. The two-secret approach above is preferred.

---

## Public key verification (`PUBLIC_GITHUB_SIGNING_PUBKEY_URL`)

When signing commits in a CI pipeline, it is possible to misconfigure the signing key — e.g. importing a private key that belongs to a different project or environment than the public key registered on GitHub. This leads to commits that GitHub shows as "Unverified" (signature present but key not registered) with no clear diagnostic.

To prevent silent mismatches, optionally verify that the downloaded public key fingerprint matches the imported private key fingerprint before any signing happens.

### New Drone secret

| Secret | Content |
|---|---|
| `public_github_signing_pubkey_url` | URL to the ASCII-armored **public** key (e.g. `https://codepixelstudio.de/j0nix-signing.pub`). Plain HTTP must not be used — only HTTPS. |

### Verification flow

Insert this block **after** the private key is imported and its passphrase removed, and **before** `git config --global user.signingkey`:

```bash
if [ -n "${PUBLIC_GITHUB_SIGNING_PUBKEY_URL:-}" ]; then
    pubkey_temp="$(mktemp -t mirror_pubkey.XXXXXX)"
    if curl -fsSL "$PUBLIC_GITHUB_SIGNING_PUBKEY_URL" -o "$pubkey_temp" 2>/dev/null; then
        gpg --batch --import "$pubkey_temp" >/dev/null 2>&1 || true
        rm -f "$pubkey_temp"

        sec_fpr="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
        pub_fpr="$(gpg --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"

        if [ -z "$sec_fpr" ] || [ -z "$pub_fpr" ]; then
            printf '%s\n' "ERROR: Could not determine GPG fingerprints for key verification" >&2
            exit 1
        fi

        if [ "$sec_fpr" != "$pub_fpr" ]; then
            printf '%s\n' "ERROR: Public key fingerprint (${pub_fpr:0:16}...) does not match private key fingerprint (${sec_fpr:0:16}...)" >&2
            printf '%s\n' "Check PUBLIC_GITHUB_SIGNING_PUBKEY_URL and PUBLIC_GITHUB_SIGNING_KEY are a matching pair." >&2
            exit 1
        fi

        printf '%s\n' "GPG public key verified: fingerprint ${sec_fpr:0:16}... matches"
    else
        printf '%s\n' "ERROR: Failed to download public key from ${PUBLIC_GITHUB_SIGNING_PUBKEY_URL}" >&2
        exit 1
    fi
fi
```

### Requirements

- **Both scripts must implement this** — `publish-public-github.sh` (full filter-branch) and `mirror-sync-forward.sh` (incremental). The shared `lib/mirror-sanitize.sh` does not handle GPG signing, so the verification lives in each script's key-setup block.
- The verification uses **full fingerprint** comparison (`fpr` field from `--with-colons`), not abbreviated key IDs. Abbreviated IDs are vulnerable to collision attacks.
- The `--with-colons` `awk` extraction assumes exactly one signing key in the temp keyring. If multiple keys are imported, the `exit` after first match ensures only the first `fpr` line is used.
- The public key is imported into the **same temp keyring** as the private key, then discarded. No state leaks outside the temp `GNUPGHOME`.
- If `PUBLIC_GITHUB_SIGNING_PUBKEY_URL` is unset, the verification is skipped entirely (backward compatible).

### Where it lives in the scripts

**`publish-public-github.sh`** (full rewrite):
Inside the `if [ -n "$gpg_key_id" ]; then` block after passphrase removal and before `git config --global user.signingkey`.

**`mirror-sync-forward.sh`** (incremental):
Inside the `if [ -n "$gpg_key_id" ]; then` block after passphrase removal and before `git config --global user.signingkey`.

### Failure modes

| Scenario | Output | Result |
|---|---|---|
| URL unreachable / HTTP 404 | `ERROR: Failed to download public key from ...` | `exit 1` |
| Download succeeds but fingerprints differ | `ERROR: Public key fingerprint (ABCD...) does not match private key fingerprint (EFGH...)` | `exit 1` |
| `sec_fpr` or `pub_fpr` empty after import | `ERROR: Could not determine GPG fingerprints for key verification` | `exit 1` |
| URL unset | (nothing printed) | Skip, continue normally |
| Matching pair | `GPG public key verified: fingerprint ABCD1234... matches` | Continue |