# Secret Setup

This repository uses `sops-nix` for both:

- system secrets
- user secrets

The goal is simple:

- no plaintext secrets in `settings.nix`
- encrypted secret files committed to the repo
- runtime secret files materialized only when needed

## Key Source Model

There are two layers:

- NixOS system secrets
- Home Manager user secrets

In this repo, the intended model is:

- the NixOS system uses `/var/lib/sops-nix/key.txt`
- Home Manager user secrets reuse that same key automatically when running under NixOS

That means you do not need a second separate Age key for user secrets on this machine.

For standalone Home Manager (without NixOS integration), you must configure an explicit user key file.

## Layout

Recommended structure:

- `secrets/.sops.yaml`
- `secrets/hosts/Jonas-PC.yaml`
- `secrets/users/jonas.yaml`

Use:

- host files for system services and machine-local credentials
- user files for SSH keys, API tokens, and user-scoped app secrets

## 1. Ensure The Age Key Exists

This setup expects the host Age key at:

- `/var/lib/sops-nix/key.txt`

Check for it:

```bash
sudo ls -l /var/lib/sops-nix/key.txt
```

If it does not exist yet, create/apply the current config first:

```bash
sudo nixos-rebuild switch --flake .#Jonas-PC
```

Then print the public recipient:

```bash
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

You will use that `age1...` value in the SOPS config.

## Why This Path Is Correct

The pinned `sops-nix` version in this repo uses `/var/lib/sops-nix/key.txt` as the canonical documented NixOS example path, and its NixOS module can generate the key there automatically when:

- `sops.age.keyFile = "/var/lib/sops-nix/key.txt"`
- `sops.age.generateKey = true`

This repo follows that model.

## 2. Activate SOPS Rules

Copy the template:

```bash
cp secrets/.sops.yaml.example secrets/.sops.yaml
```

Edit `secrets/.sops.yaml` and replace the placeholder recipient with your real Age public key.

Example:

```yaml
creation_rules:
  - path_regex: secrets/.*\\.(yaml|yml|json|env|ini|bin)$
    key_groups:
      - age:
          - age1...
```

## 3. Create The Encrypted Secret Files

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

## 4. Put User Secrets Into `secrets/users/jonas.yaml`

Example for SSH private keys:

```yaml
ssh:
  github_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  j0nixlab_key: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

Notes:

- store the full private key content
- keep this file encrypted with `sops`
- do not put these keys into `settings.nix`

## 5. Put Host Secrets Into `secrets/hosts/Jonas-PC.yaml`

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

## 6. Register The Secrets In `settings.nix`

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

  users.jonas = {
    items = {
      ssh-github-key = {
        key = "ssh/github_key";
        mode = "0400";
      };

      ssh-j0nixlab-key = {
        key = "ssh/j0nixlab_key";
        mode = "0400";
      };
    };
  };
};
```

If you ever run Home Manager standalone on another machine, you can additionally set:

```nix
secrets.users.jonas.age.keyFile = "/home/jonas/.config/sops/age/keys.txt";
```

On this NixOS host, that should usually not be necessary because the user layer inherits the system key automatically.

## 7. Wire Syncthing To The Secret

In `settings.nix`, configure Syncthing like this:

```nix
programs.syncthing = {
  enable = true;
  guiAddress = "127.0.0.1:8384";
  guiPasswordSecretName = "syncthing-gui-password";
};
```

This makes the service use the materialized secret file automatically.

## 8. SSH Secret Keys

The repo is already prepared to use:

- `ssh-github-key`
- `ssh-j0nixlab-key`

Those are referenced by the Git host profiles in `settings.nix`.

Behavior:

- if the user secret exists, SSH uses the SOPS-materialized key path
- if it does not exist yet, the config falls back to the existing `identityFile`

That means you can migrate safely without breaking SSH immediately.

## 9. Optional: Wire Samba To The Secret

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

## 10. Apply The Configuration

Rebuild:

```bash
sudo nixos-rebuild switch --flake .#Jonas-PC
```

## 11. Verify System Secrets

Check the generated runtime files:

```bash
sudo ls -l /run/secrets
sudo ls -l /run/secrets/syncthing-gui-password
sudo ls -l /run/secrets/samba-media
```

## 12. Verify User Secrets

Check the Home Manager generation and then inspect the resolved SSH config:

```bash
systemctl --user status home-manager-jonas
ssh -G github.com | rg '^identityfile'
ssh -G git.j0nixlab.xyz | rg '^identityfile'
```

If the user secrets are wired correctly, the `identityfile` output should point to the SOPS-managed secret path instead of `~/.ssh/id_ed25519`.

## 13. Verify Syncthing

Check the service:

```bash
sudo systemctl status syncthing
```

## Migration Notes

Recommended migration order:

1. set up `.sops.yaml`
2. create the encrypted secret files
3. register the secrets in `settings.nix`
4. rebuild
5. verify SSH and Syncthing
6. only then remove old plaintext key files if you still have them

Do not delete existing `~/.ssh` keys until the new secret-backed paths are confirmed to work.
