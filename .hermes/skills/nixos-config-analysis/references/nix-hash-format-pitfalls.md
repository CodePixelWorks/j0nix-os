# Nix Hash Format Pitfalls

When packaging external binaries (AppImage, statically linked tarballs, pre-built
deb/rpm/flatpaks) the `fetchurl` / `fetchzip` hash must be **SRI base-64**,
**not** base-32.

## Symptoms

```
error: invalid SRI hash '09m6pj4zr1llgmd1vfma4agdb2ayhgbwvm5nxfaimm9l65jh6bpz',
       length 39 != expected length 32
```

**Critical detail**: the length mismatch is expected because 39 chars is a
base-32-encoded sha256 **mislabeled** as `sha256-*` SRI.

## Root Causes

- Copy-pasting a base-32 `nix-prefetch-url` output into a `hash = "sha256-...";`
  attribute (SRI expects base-64).
- Using `nix-prefetch-url --type sha256` but forgetting `--output-format sri`
  (or forgetting `--sri`, depending on nix version).

## How to Generate the Correct Hash

### Method A: nix-prefetch-url (preferred)

```bash
nix-prefetch-url --type sha256 --sri \
  https://github.com/OWNER/REPO/releases/download/vX.Y/Z.AppImage
```

**Critical**: Without `--sri`, `nix-prefetch-url` outputs **base-32** (e.g., `09m6pj4...`, 52 chars). `fetchurl`/`fetchzip` expect **SRI base-64** (e.g., `sha256-...`, ~44 chars). Copy-pasting base-32 into `hash = "sha256-...";` produces an invalid SRI hash error at evaluation time.

## Verify Hash Format

| Format | Example | Length |
|--------|---------|--------|
| SRI base-64 | `sha256-/y4DZTE01RqV67bUzdeDXonVniKquh1afZSG/Im8piY=` | ~51 chars |
| base-32 | `09m6pj4zr1llgmd1vfma4agdb2ayhgbwvm5nxfaimm9l65jh6bpz` | 52 chars |

If `nix flake check --no-build` passes but `nixos-rebuild switch` fails with "hash mismatch in fixed-output derivation", the hash format is correct but the *value* is wrong — the upstream file changed after prefetch. Re-run Method A or B.

### Method B: local download + nix-hash

If `nix-prefetch-url` fails (network, no flakes support, or the URL is
pre-downloaded):

```bash
curl -L -o /tmp/package.appimage  https://example.com/package.AppImage
nix-hash --type sha256 --sri /tmp/package.appimage
```

Or obtain **only base-64** output:

```bash
sha256sum /tmp/package.appimage | cut -d' ' -f1 | xxd -r -p | base64
```

## Integration Checklist

1. First time packaging: use `nix-prefetch-url --type sha256 --sri`.
2. Hash changes upstream: re-run Method A or B, always verify the prefix is
   `sha256-` and the length is ~44 chars (not 52 like base-32).
3. Double-check the **version** in the download URL matches the `version =` attr
   in `rec { ... }`; otherwise the hash is silently stale.
4. Run `nix flake check --no-build` or `nix build --no-out-link` zero-rebuild
   after a hash change to confirm evaluation succeeds.
