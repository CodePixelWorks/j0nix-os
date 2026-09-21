# Migrating Secrets Between SOPS Files / Repos

Use this reference when moving SOPS-encrypted material from one
encrypted file to another — typically when extracting user secrets
into a dedicated shared-identity repo, splitting per-host vs per-user
storage, or rotating the recipient set on an existing file.

This is the **migration** class. For *adding* a new GPG/SSH key to an
already-deployed SOPS file, see `gpg-key-deployment-sops-nix.md`.

## Security Contract (Non-Negotiable)

Migration scripts touch plaintext private-key material. The contract:

1. **Never** decrypt with the intent of "let me look at it". Use
   `sops -d file.yaml >/dev/null` (exit code only) to confirm
   decryptability. A successful exit means the structure parses and at
   least one recipient can decrypt — that is the whole information you
   need.

2. **Never** run `sops -d file.yaml | head` or pipe through `tee`,
   `cat`, `less`, or any pager. Even one line of plaintext in the
   output buffer ends up in your context. Use structured extraction
   (`yq`/`jq` reading the file, writing a file) instead.

3. **Plaintext lives only in `chmod 700`/`chmod 600` temp files**,
   ideally under `mktemp -d`, with a `trap` that `shred -u`s every
   file before the temp directory is removed. Do this even for "I'll
   only inspect for a moment" workflows.

4. **The legacy file is NOT deleted** until the new layout has been
   built and verified end-to-end. The migration script leaves both
   copies in place; removal is a separate commit gated on observed
   success.

## Re-Encrypting into a New Recipient Set

The destination `.sops.yaml` typically uses `path_regex` to bind
recipients to file paths. When encrypting from a temp file (path is
under `/tmp/...`), the regex won't match and sops aborts with
`error loading config: no matching creation rules found`.

Two working patterns:

**Pattern A — explicit `--age` flag.** Pass recipients on the command
line. Safe because age recipients are public keys (asymmetric), already
published in `.sops.yaml`:

```bash
AGE_RECIPIENTS="age1xxx,age1yyy,age1zzz"
sops --age "$AGE_RECIPIENTS" \
    --input-type yaml --output-type yaml \
    --encrypt "$PLAINTEXT_FILE" > "$OUTPUT_FILE"
```

Disadvantage: the recipient list is duplicated in the script and the
`.sops.yaml`. A drift comment + a self-check (`grep` the recipients
out of `.sops.yaml` and compare) catches silent drift.

**Pattern B — `--filename-override`.** Tell sops to use the
destination's path when matching the regex, while still reading the
plaintext from the temp file:

```bash
sops --config "$DEST_SOPS_CONFIG" \
    --filename-override "secrets/ssh.yaml" \
    --input-type yaml --output-type yaml \
    --encrypt "$SSH_PLAIN" > "${DEST_REPO}/secrets/ssh.yaml"
```

This is cleaner because the recipient set stays in one place
(`.sops.yaml`) — but it requires the `--config` flag, otherwise sops
auto-loads `.sops.yaml` from cwd and the path_regex matches a
*different* file.

## lib/ Path Resolution

When `lib/default.nix` in a flake exposes sopsFile paths to
consumers, Nix resolves them **relative to the lib file**, not the
repo root. `./secrets/ssh.yaml` inside `lib/default.nix` becomes
`lib/secrets/ssh.yaml` after import, which breaks sops-nix's
existence assertion.

```nix
# WRONG — resolves to <store>/lib/secrets/ssh.yaml
sshSopsFile = ./secrets/ssh.yaml;

# RIGHT — resolves to <store>/secrets/ssh.yaml
sshSopsFile = ../secrets/ssh.yaml;
```

Symptom in `nix flake check --no-build`:

```
error: Failed assertions:
- jonas profile: Referenced user sopsFile path(s) for jonas do not exist:
  /nix/store/...-source/lib/secrets/ssh.yaml
```

The path string in the error reveals the prefix `lib/` — that is the
diagnostic signature.

## Backward-Compat Fallback Pattern (Migration Phase Only)

When moving user secrets from a local file to a shared flake, leave
the legacy file in place and wire both into settings.nix:

```nix
identityLib = inputs.j0nix-identity-secrets.lib or null;
hasSharedIdentity = identityLib != null;
sharedSshSopsFile = if hasSharedIdentity then identityLib.sshSopsFile else null;
legacyUserSopsFile = ./secrets/users/jonas.yaml;
sshSopsFile = if hasSharedIdentity then sharedSshSopsFile else legacyUserSopsFile;
```

This means:
- A clean checkout with the shared flake available uses the new
  layout.
- A minimal checkout, CI mirror, or a consumer who disables the input
  falls back to the legacy file with zero changes.
- The legacy file stays in the repo as the rollback path; deletion is
  a *separate* commit gated on observed success.

The same pattern generalizes to any flake input that supplies paths
(`hasInput ? newPath : oldPath`). Document the fallback choice in
settings.nix so a future reader understands which file currently
wins.

**WARNING — silent fallbacks are inappropriate for the final
consumer.** A silent `if input-available then new-path else old-path`
selector routes keys to whichever recipient set happens to be
reachable. If both the new and legacy paths are reachable (different
machines, stale lockfile, partially-set-up CI), the wrong recipient
set gets selected silently and the secrets fail to decrypt at
activation time. The migration fallback above is acceptable only
during the transition window where you control all consumers; once
the new layout is stable, replace it with the explicit-mode pattern
below.

## Explicit Mode Selector (Final Consumer Pattern)

When the migration is done and both layouts could plausibly coexist
(the shared flake input is declared in `flake.nix` AND the legacy file
remains in the repo), an **explicit** mode selector is the correct
shape. Operators MUST name the active source; the module refuses to
guess.

### Migration phase ordering (the part that is easy to skip)

The migration has three named phases; the silent-fallback pattern is
correct only for the middle one. Skipping phase 3 is the most common
review-pass failure mode.

| Phase | Layout that exists in `flake.nix` | Layout that exists in `settings/users/*.yaml` | Selector shape |
|---|---|---|---|
| 1. Pre-migration | input absent | legacy file present | `sopsFile = legacyUserSopsFile;` |
| 2. Migration (transition window) | input declared + legacy file present | both decryptable | `hasInput ? newPath : oldPath` (silent fallback) |
| 3. Stable | input declared (private) OR stripped (mirror) | legacy file preserved as rollback | **explicit `mode = "legacy" \| "shared-flake"`** |

Phase 2 is acceptable only because you control every consumer during
the transition — the moment you publish a public mirror, fork the
flake, or hand a CI job to a third party, the silent selector picks
the *wrong* path silently and the secrets fail to decrypt at
activation. Phase 3 lands in a separate commit gated on the
transition being observably complete (mirror eval succeeds, CI
runner is decrypting the shared files, legacy file is no longer
the primary source for any consumer).

**Triggering condition for phase 3:** if you can answer "yes" to
*any* of the following, the silent fallback is now a latent bug:

- A public mirror of the consumer repo exists (or is about to).
- The legacy file's recipient set and the shared file's recipient
  set both include at least one common machine — so the resolver
  cannot distinguish them by decryptability.
- More than one operator maintains `flake.lock` (lockfile drift
  produces different `hasInput` states across machines).
- CI or CI-adjacent tooling depends on the consumer.

If any of those fire during phase 2, land phase 3 immediately. Do
not wait until "the next refactor".

```nix
# settings.nix
identityMode = "legacy"; # "legacy" | "shared-flake"

sharedSopsFile =
  if identityMode == "shared-flake" then
    if sharedIdentityLib == null then
      throw ''
        settings.secrets.identity.mode = "shared-flake" but
        inputs.j0nix-identity-secrets is unavailable or does not
        expose lib.sshSopsFile. Either add the input to flake.nix
        or set mode = "legacy".
      ''
    else sharedIdentityLib.sshSopsFile
  else
    legacyUserSopsFile;
```

Three things matter:
1. **Default is the safer mode.** `"legacy"` is the safe default
   because it does not require any flake input. The shared-flake
   mode is opt-in by name only.
2. **Misconfiguration is a hard error, not a fallback.** The
   `throw` runs at evaluation time. A user who flipped the mode but
   forgot to add the input to `flake.nix` (or has a stale lockfile)
   gets a clear error message instead of silent decryption failure
   at activation.
3. **The legacy file is preserved as an explicit rollback path.**
   Setting `identityMode = "legacy";` is a one-line revert. No
   transition commit, no data migration needed.

Publish the resolved state in the output attrset so downstream
modules can introspect it:

```nix
secrets = {
  ...
  identity = {
    mode = identityMode;
    sshSopsFile = sshSopsFile;
    gpgSopsFile = gpgSopsFile;
    flakeInput = if sharedIdentityInput != null then "j0nix-identity-secrets" else null;
    package = sharedIdentityPackage;
  };
};
```

The `secrets.identity.*` block is also what `settings.nix.example`
should carry, with `mode = "legacy"` as the public-mirror default
(see "Public-Mirror-Safe Defaults" below).

## Public-Mirror-Safe Defaults

When a Nix flake input is consumed by the private source but stripped
from the public mirror (via `scripts/publish-public-github.sh`,
`scripts/export-public-github.sh`, and `scripts/lib/mirror-sanitize.sh`
— see `repo-mirror-publishing` skill § private-flake-input-stripping),
the consumer's `settings.nix` MUST have a default mode that does not
require the stripped input.

Verification: after running the public-mirror export, the resulting
tree must still pass `nix flake check --no-build` after
`settings.nix.example` → `settings.nix` replacement. If the mirror
only evaluates in shared-flake mode, you have a leak the next time
the mirror is published — strip the input first, fix the default
second.

## Resolve-Key-Set Helper (Mixed Group + Individual Refs)

When a shared-identity lib needs to expose "the keys for role X" but
the role can be described either as a **group name** (`"pc"`,
`"server"`, `"git"`) OR as an **individual key name**
(`"jonas-server-webserver"`), put the resolution logic in one place.
Consumers MUST go through the helper, never branch on keySet
semantics themselves.

```nix
rec {
  ssh = { pc = { ... }; server = { ... }; git = { ... }; };
  keySets = {
    workstation = { ssh = [ "pc" ]; gpg = [ ... ]; };
    server = {
      ssh = [
        "jonas-server-webserver"      # individual ref
        "jonas-server-homeassistant"
        "jonas-server-gagaland"
      ];
      gpg = [ ];
    };
  };

  sshGroups = builtins.attrNames ssh;

  lookupSshKey = name:
    let
      candidates = builtins.concatLists (
        map
          (group:
            let hit = ssh.${group}.${name} or null; in
            if hit != null then [ { name = name; spec = hit; } ] else [ ])
          sshGroups
      );
    in if candidates == [ ] then null else builtins.head candidates;

  resolveSshRef = ref:
    if builtins.elem ref sshGroups then
      map (n: { name = n; kind = "ssh"; spec = ssh.${ref}.${n}; })
          (builtins.attrNames ssh.${ref})
    else
      let hit = lookupSshKey ref; in
      if hit != null then
        [ { name = hit.name; kind = "ssh"; spec = hit.spec; } ]
      else throw ''
        j0nix-identity-secrets: resolveKeySet: unknown SSH reference "${ref}".
        Known SSH group names: ${builtins.concatStringsSep ", " sshGroups}.
        Pass an individual ssh.<group>.<name> reference or a group name.
      '';

  resolveKeySet = keySet:
    let
      sshItems = builtins.concatMap resolveSshRef (keySet.ssh or [ ]);
      gpgItems = map
        (n: { name = n; kind = "gpg";
              spec = gpg.${n} or (throw ''
                j0nix-identity-secrets: resolveKeySet: unknown GPG identity "${n}".
                Known GPG identities: ${builtins.concatStringsSep ", " (builtins.attrNames gpg)}.
              ''); })
        (keySet.gpg or [ ]);
    in sshItems ++ gpgItems;
}
```

Why this matters:
- **Single source of truth for the group-vs-individual convention.**
  Consumers never call `ssh.${group}.${name}` directly; they iterate
  `resolveKeySet`. If you later decide to allow nested group refs or
  regex aliases, the change is one helper edit.
- **Server keyset uses individual refs to express "no GPG material".**
  `workstation.ssh = [ "pc" ]` expands to all pc keys via the group
  ref; `server.ssh = [ "jonas-server-webserver" ... ]` lists the
  three server keys explicitly so the empty `gpg = [ ]` is
  unambiguous.
- **Unknown refs throw with diagnostic context.** A typo
  (`"jonas-serve-webserver"`) errors out with the list of known
  group names rather than evaluating to `null` and breaking the
  deploy script at activation time.

## Lockfile Updates After Shared-Repo Changes

When the shared-identity repo's `lib/default.nix` adds a new attribute
that consumers dereference (`identityLib.sshSopsFile`), the
consumer's `flake.lock` is pinned to the *old* shared-repo commit. The
eval fails with `attribute 'X' missing` because the old `lib/default.nix`
does not export it.

`nix flake update j0nix-identity-secrets` rewrites the lockfile entry,
but only when the working tree has no dirty edits to the consumer's
`settings.nix`. Sequence:

1. Push the shared-repo commit.
2. From the consumer repo, run `nix flake update j0nix-identity-secrets`.
3. Verify `flake.lock` now references the new `rev`.
4. Run `nix flake check --no-build`.

Do NOT amend the shared-repo commit after the lockfile points at it —
that requires `--allow-dirty-locks` and risks forgetting to re-bump
on the next change.

## Verification Recipes (No Plaintext Output)

```bash
# Confirm decryptability without leaking plaintext.
SOPS_AGE_KEY_FILE=/path/to/keys.txt sops -d secrets/ssh.yaml >/dev/null 2>&1 \
    && echo "OK: ssh.yaml decrypts"

# Confirm the recipient list is correct (no value, just metadata).
sops --config .sops.yaml -d --show-master-keys secrets/ssh.yaml 2>/dev/null \
    | grep -E 'recipient' | head

# Confirm the recipient count matches what .sops.yaml declares.
grep -c 'recipient:' secrets/ssh.yaml
```

## Reference Implementation (Template)

A complete one-shot migration script that satisfies the security
contract is included as a template at
`scripts/sops-migrate-between-repos.sh`. Key features:
- `mktemp -d` + `chmod 700` for the work dir
- `touch` THEN `chmod 600` (chmod fails on missing files — see
  troubleshooting)
- `sops --decrypt > file` for the legacy read (no stdout)
- `yq -y` or `jq` for projection (reads file, writes file)
- `sops --filename-override` for re-encrypt
- `trap cleanup EXIT INT TERM` that shreds files before `rm -rf`
- `sops -d >/dev/null` for the post-encrypt verification

Copy the template and adjust the three inputs:
- `LEGACY_FILE` — the source sops file
- `DEST_REPO` — the destination repo root
- The recipient list (mirror `keys:` from the destination `.sops.yaml`)

The script intentionally ships untracked in the consumer's `scripts/`
directory and is meant to be deleted after the migration is committed —
not to be a long-lived tool.
