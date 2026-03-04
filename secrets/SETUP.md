# Secret Setup

This repository uses `sops-nix` for both:

- system secrets
- user secrets

The goal is simple:

- no plaintext secrets in `settings.nix`
- encrypted secret files committed to the repo
- runtime secret files materialized only when needed

## Key Model

This repo now uses a two-tier key model:

- one **host key** for system secrets
- one **user key per user** for user secrets

Recommended split:

- `secrets/hosts/*.yaml`:
  encrypted for the host key
- `secrets/users/<user>.yaml`:
  encrypted for that user's key
  and optionally also for the host key

Why this is the right model:

- system services should not depend on user keys
- user secrets are cryptographically separated per user
- users can edit their own secret files without sharing one global secret key

Under NixOS, the Home Manager layer can still inherit the system key automatically.
But for a multi-user, professional setup, you should explicitly set a user key per user.

## Layout

Recommended structure:

- `.sops.yaml`
- `secrets/hosts/Jonas-PC.yaml`
- `secrets/users/jonas.yaml`

Use:

- host files for system services and machine-local credentials
- user files for SSH keys, API tokens, and user-scoped app secrets

## 1. Create The Host Key

The system key should live at:

- `/var/lib/sops-nix/key.txt`

Create it explicitly:

```bash
sudo install -d -m 700 /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

Print the public recipient:

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

You will use that `age1...` value for host secret files.

## Why This Path Is Correct

The pinned `sops-nix` version in this repo uses `/var/lib/sops-nix/key.txt` as the canonical documented NixOS example path, and its NixOS module can generate the key there automatically when:

- `sops.age.keyFile = "/var/lib/sops-nix/key.txt"`
- `sops.age.generateKey = true`

This repo follows that model.

## 2. Create A User Key

For your own user secrets, create a separate user key.

Recommended path:

- `/home/jonas/.config/sops/age/keys.txt`

Create it:

```bash
install -d -m 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Print the public recipient:

```bash
age-keygen -y ~/.config/sops/age/keys.txt
```

You will use that second `age1...` value for `secrets/users/jonas.yaml`.

## 3. Activate SOPS Rules

Copy the template:

```bash
cp .sops.yaml.example .sops.yaml
```

Rewrite `.sops.yaml` so host and user files use different recipients.

Recommended example:

```yaml
creation_rules:
  - path_regex: secrets/hosts/.*\\.(yaml|yml|json|env|ini|bin)$
    key_groups:
      - age:
          - age1HOSTKEY...

  - path_regex: secrets/users/jonas\\.(yaml|yml|json|env|ini|bin)$
    key_groups:
      - age:
          - age1JONASKEY...
          - age1HOSTKEY...
```

Recommended behavior:

- host files: host key only
- user file: user key first, host key also allowed

That lets:

- `jonas` edit his secrets directly
- the host still decrypt them during Home Manager activation

## 4. Create The Encrypted Secret Files

Create the expected directories:

```bash
mkdir -p secrets/hosts secrets/users
```

Create the user secret file:

```bash
sops secrets/users/jonas.yaml
```

Create the host secret file:

```bash
sops secrets/hosts/Jonas-PC.yaml
```

## 5. Put User Secrets Into `secrets/users/jonas.yaml`

Example for SSH private keys:

```yaml
ssh:
  github_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  jonas_pixel_und_code: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

Notes:

- store the full private key content
- keep this file encrypted with `sops`
- do not put these keys into `settings.nix`

## 6. Put Host Secrets Into `secrets/hosts/Jonas-PC.yaml`

Example for Syncthing and Samba:

```yaml
syncthing:
  gui_password: "YOUR-STRONG-GUI-PASSWORD"

samba:
  media: |
    username=your-user
    password=your-password
    domain=WORKGROUP
```

Notes:

- `gui_password` is stored as plaintext inside the encrypted SOPS file
- the NixOS Syncthing module reads it via `guiPasswordFile`
- Samba credentials are intentionally stored in the format expected by CIFS `credentials=...`

## 7. Register The Secrets In `settings.nix`

Add or adapt this block under `secrets = { ... };`:

```nix
secrets = {
  defaultSopsFile = ./secrets/hosts/Jonas-PC.yaml;
  defaultUserSopsFile = ./secrets/users/jonas.yaml;
  defaultSopsFormat = "yaml";

  age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
    sshKeyPaths = [ ];
  };

  system = {
    syncthing-gui-password = {
      key = "syncthing/gui_password";
      owner = "jonas";
      group = "users";
      mode = "0400";
    };

    samba-media = {
      key = "samba/media";
    };
  };

  userSettings.jonas.secrets = {
    age = {
      keyFile = "/home/jonas/.config/sops/age/keys.txt";
    };

    files = { };

    sshKeys = {
      jonas-pixel-und-code = {
        key = "ssh/id_ed25519_jonas-pixel-und-code";
        mode = "0400";
        targetName = "id_ed25519_jonas-pixel-und-code";
      };
    };
  };
};
```

This makes the intent explicit:

- system secrets use the host key
- user secrets use the user key

The Home Manager layer can inherit the system key, but for a multi-user setup this explicit per-user key is the preferred model.

## 8. Wire Syncthing To The Secret

In `settings.nix`, configure Syncthing like this:

```nix
programs.syncthing = {
  enable = true;
  guiAddress = "127.0.0.1:8384";
  guiPasswordSecretName = "syncthing-gui-password";
};
```

This makes the service use the materialized secret file automatically.

## 9. SSH Secret Keys

The repo is already prepared to use:

- `ssh-github-key`
- `jonas-pixel-und-code`

Those are referenced by the Git host profiles in `settings.nix`.

Behavior:

- Home Manager deploys `~/.ssh/<name>` as a stable symlink to the private key secret
- Home Manager regenerates `~/.ssh/<name>.pub` from the private key on activation
- if a deployed SSH key mapping exists, SSH uses that stable `~/.ssh/<name>` path
- if it does not exist yet, the config falls back to the existing `identityFile`

For your preferred naming scheme, use:

- `targetName = "id_ed25519_jonas_pixel_und_code"`
- `targetName = "id_ed25519_jonas-pixel-und-code"`

If the private key is passphrase-protected, set the public key explicitly on the mapping:

```nix
sshKeys.jonas-pixel-und-code = {
  key = "ssh/id_ed25519_jonas-pixel-und-code";
  targetName = "id_ed25519_jonas-pixel-und-code";
  publicKeyFile = ./public/users/jonas/ssh/id_ed25519_jonas-pixel-und-code.pub;
  # Optional for passphrase-protected keys:
  # passphraseKey = "ssh_passphrases/id_ed25519_jonas-pixel-und-code";
};
```

You can also inline it with `publicKey = "ssh-ed25519 AAAA... comment";`.

For passphrase-protected keys, you can also add:

- `passphraseKey = "ssh_passphrases/<key-name>"`

When `settings.userSettings.<name>.dev.ssh.agent.provider = "gnome-keyring"`, the user
session will automatically load those keys into the SSH agent during login using the
secret-backed passphrase.

Recommended location for repo-tracked public keys:

- `public/users/jonas/ssh/`

Without `publicKey` or `publicKeyFile`, Home Manager falls back to `ssh-keygen -y`.
If that fails, the existing `.pub` file is preserved instead of being overwritten with an empty file.

That means you can migrate safely without breaking SSH immediately.

## 10. Optional: Wire Samba To The Secret

For a Samba share, use the secret name in the share definition:

```nix
storage.sambaShares = [
  {
    name = "nas-media";
    host = "nas.local";
    share = "Media";
    mountPoint = "/mnt/Media";
    secretName = "samba-media";
    vers = "3.1.1";
  }
];
```

This resolves to:

- `/run/secrets/samba-media`

## 11. Apply The Configuration

Rebuild:

```bash
sudo nixos-rebuild switch --flake .#Jonas-PC
```

## 12. Verify System Secrets

Check the generated runtime files:

```bash
sudo ls -l /run/secrets
sudo ls -l /run/secrets/syncthing-gui-password
sudo ls -l /run/secrets/samba-media
```

## 13. Verify User Secrets

Check that the user key exists, then inspect the resolved SSH config:

```bash
ls -l ~/.config/sops/age/keys.txt
ssh -G github.com | rg '^identityfile'
ssh -G j0lab.xzy | rg '^identityfile'
```

If the user secrets are wired correctly, the `identityfile` output should point to the SOPS-managed secret path instead of `~/.ssh/id_ed25519`.

If you use the declarative `sshKeys` mapping, it should point to the stable deployed path, for example:

- `~/.ssh/id_ed25519_jonas_pixel_und_code`
- `~/.ssh/id_ed25519_jonas-pixel-und-code`

## 14. Verify Syncthing

Check the service:

```bash
sudo systemctl status syncthing
```

## Migration Notes

Recommended migration order:

1. create the host key
2. create the user key
3. set up `.sops.yaml` with separate host/user rules
4. create the encrypted secret files
5. register the secrets in `settings.nix`
6. rebuild
7. verify SSH and Syncthing
8. only then remove old plaintext key files if you still have them

Do not delete existing `~/.ssh` keys until the new secret-backed paths are confirmed to work.
