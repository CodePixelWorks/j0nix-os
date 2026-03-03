# Public Data

This directory is for non-secret, repo-tracked public material.

Use it for data that should be versioned, but must not live under `secrets/`.

Examples:

- SSH public keys
- GPG public keys
- Age public keys
- other publishable identity material

Recommended layout:

- `public/users/<name>/ssh/*.pub`
- `public/users/<name>/gpg/*`
- `public/users/<name>/age/*`

For Jonas SSH public keys, use:

- `public/users/jonas/ssh/`

Keep private keys and encrypted secret payloads out of this directory.
