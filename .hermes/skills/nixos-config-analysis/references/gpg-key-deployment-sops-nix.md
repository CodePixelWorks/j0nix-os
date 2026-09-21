# GPG Key Deployment via sops-nix in j0nix-os

## Overview

User GPG keys are stored encrypted in per-user SOPS files (e.g. `secrets/users/<name>.yaml`) and declaratively imported into `~/.gnupg` at Home Manager activation time. Passphrases can be preloaded into `gpg-agent` automatically so signing stays non-interactive.

## Workflow: Adding a New Managed GPG Key

### 1. Generate Key Locally

```bash
gpg --full-generate-key
```

Collect metadata after creation:

```bash
# Fingerprint
fpr=$(gpg --list-secret-keys --with-colons me@example.com | awk -F: '$1=="fpr"{print $10;exit}')

# Keygrips (note: there may be MULTIPLE for sign + encrypt subkeys)
gpg --list-secret-keys --with-colons --with-keygrip me@example.com | awk -F: '$1=="grp"{print $10}'
```

Export the private key:

```bash
gpg --armor --export-secret-keys me@example.com > /tmp/new-key.asc
```

### 2. Insert into SOPS Secrets

Edit the user secrets file:

```bash
sops secrets/users/jonas.yaml
```

Add a block under the existing `gpg:` hierarchy:

```yaml
    new-key-name:
        private: |
            -----BEGIN PGP PRIVATE KEY BLOCK-----

            ... paste /tmp/new-key.asc content ...
            -----END PGP PRIVATE KEY BLOCK-----
        passphrase: "the-gpg-passphrase-here"
```

The YAML path becomes `gpg/new-key-name/private` and `gpg/new-key-name/passphrase`.

### 3. Register in settings.nix (Secrets Import)

In the user's `secrets.gpgKeys` attrset (inside `settings.userSettings.<name>.secrets`):

```nix
new-key-name = {
  key            = "gpg/new-key-name/private";
  passphraseKey  = "gpg/new-key-name/passphrase";
  fingerprint    = "854C0BE0F7AB04F2A8B1CB725388423005575586";
  keygrip        = "F19A8D49BD3B1C32D836BC53008EF52FCBBF0DEE";  # single subkey
  mode           = "0400";
  passphraseMode = "0400";
};
```

### 4. Register in settings.nix (Git Signing Key Map)

**This is a separate step and a common omission.** Managed GPG keys enable `gpg-agent` import, but Git-Signing key selection is driven by `dev.gpg.keys` (not `secrets.gpgKeys`).

In the user's `dev.gpg.keys` attrset (inside `settings.userSettings.<name>.dev.gpg.keys`):

```nix
"github-codepixelstudio" = {
  key = "854C0BE0F7AB04F2A8B1CB725388423005575586";
  emails = [
    "me@codepixelstudio.de"
  ];
  signByDefault = true;
};
```

**Why both registrations?**
- `secrets.gpgKeys.*` — tells sops-nix/HM where to find the encrypted key material and how to import it into `~/.gnupg`
- `dev.gpg.keys.*` — maps a named key + email list to Git-Signing logic so `git commit -S` picks the right key per repo

### 5. Git Signing Key Auto-Matching by Email

The Home Manager Git module (`user/dev/default.nix`) auto-selects signing keys based on email matching. When a `hostProfile` has a specific `userEmail`, the module searches `dev.gpg.keys` for a key whose `emails` list contains that email.

Example multi-identity Git config:

```nix
dev.git = {
  enable = true;
  defaultBranch = "main";
  hostProfiles = {
    github = {
      userName = "TheJ0nix";
      userEmail = "268841066+TheJ0nix@users.noreply.github.com";
    };
    codepixelworks = {
      host = "github.com";
      userName = "Jonas Tschoche";
      userEmail = "me@codepixelstudio.de";
    };
  };
};
```

Result: Repos with remote `git@github.com` and user email `me@codepixelstudio.de` automatically sign with the `github-codepixelstudio` GPG key (fingerprint `854C0BE0...`), because the module finds that key's `emails` list contains `me@codepixelstudio.de`.

**If you skip `dev.gpg.keys`**: The key is imported into `gpg-agent` but Git has no mapping — commits will either fail to sign or use the wrong default key (first key in the map, or whichever `gpg.program` resolves via `gpg-agent`'s default-key).

### 4. Keygrip Handling: Singular vs Plural

**Crucial**: GnuPG may emit **multiple keygrips** for a single primary key (one per subkey, e.g. signing + encryption).

- Use **`keygrip`** (string) when there is exactly one keygrip.
- Use **`keygrips`** (list of strings) when there are multiple.

Example with multiple keygrips:

```nix
github-codepixelstudio = {
  key            = "gpg/github-codepixelstudio/private";
  passphraseKey  = "gpg/github-codepixelstudio/passphrase";
  fingerprint    = "854C0BE0F7AB04F2A8B1CB725388423005575586";
  keygrips       = [
    "F19A8D49BD3B1C32D836BC53008EF52FCBBF0DEE"
    "698CFD158677015DAB48D1B12040C5A374FA022D"
  ];
  mode           = "0400";
  passphraseMode = "0400";
};
```

The Home Manager module (see `user/dev/gpg.nix`) iterates over `keygrips` and preloads the passphrase for each via `gpg-preset-passphrase`. If the wrong variant is used (single string when multiple exist), only the first subkey gets preloaded and signing/decrypting with the other may still prompt interactively.

### 5. Validate & Deploy

```bash
nix flake check --no-build
sudo nixos-rebuild switch --flake .#<hostname>
```

After switch, the `gpg-secret-keys-load` systemd user service imports the key and preloads passphrases. Verify with:

```bash
gpg --list-secret-keys me@example.com
echo "test" | gpg --clearsign --default-key me@example.com > /dev/null
```

No pinentry popup on the second command means preset-passphrase is working.
