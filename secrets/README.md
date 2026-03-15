# Secrets

This repository is wired for `sops-nix` and expects encrypted secret files to live here.

For the full step-by-step setup guide, see:

- `secrets/SETUP.md`

Recommended layout:

- `secrets/common.yaml`
- `secrets/hosts/Jonas-PC.yaml`
- `secrets/users/jonas.yaml`
- `.sops.yaml`
- `secrets/scripts/sops-safe-rekey.sh`
- `secrets/scripts/sops-migrate-system-split.sh`
- `secrets/scripts/sops-autofix-decrypt.sh`

Recommended key model:

- host key for `secrets/hosts/*`
- one user key per user for `secrets/users/*`
- optionally encrypt user files for both the user key and the host key

Bootstrap:

1. Copy `.sops.yaml.example` to `.sops.yaml`
2. Replace the placeholder `age1...` recipients with separate host/user Age public keys
3. Create an encrypted file, for example:
   - `sops secrets/hosts/Jonas-PC.yaml`
4. Reference entries from `settings.secrets.system`

For user secrets:

1. Create an encrypted file, for example:
   - `sops secrets/users/jonas.yaml`
2. Reference generic secret files from `settings.userSettings.jonas.secrets.files`
3. Reference secret-backed SSH keys from `settings.userSettings.jonas.secrets.sshKeys`

When you change recipients in `.sops.yaml`, run:

- `./secrets/scripts/sops-safe-rekey.sh`

This script creates timestamped encrypted backups in `secrets/.backups/` and then runs
`sops updatekeys --yes` for all host/user secret YAML files.

To move known system-owned keys from a user file into the host file:

- `./secrets/scripts/sops-migrate-system-split.sh`

By default this migrates `syncthing.gui_password` from `secrets/users/jonas.yaml` to
`secrets/hosts/Jonas-PC.yaml`, re-encrypts both files, and keeps encrypted backups.

If decrypt fails during rebuild with `0 successful groups required, got 0`, run:

- `./secrets/scripts/sops-autofix-decrypt.sh`

This re-encrypts host/user files with recipients derived from local key files
(`~/.config/sops/age/keys.txt` and `/var/lib/sops-nix/key.txt`) and verifies decryptability.
It enforces a strict mapping:

- `secrets/hosts/*` -> host key recipient only
- `secrets/users/*` -> user key recipient + host key recipient

If host secrets exist, run it with permissions that can read `/var/lib/sops-nix/key.txt`:

- `sudo ./secrets/scripts/sops-autofix-decrypt.sh`

Example:

```nix
secrets = {
  defaultSopsFile = ./secrets/hosts/Jonas-PC.yaml;
  system.samba-media = {
    key = "samba/media";
  };
};
```

At runtime this becomes available as:

- `/run/secrets/samba-media`

Use that path from modules (for example Samba `credentials=` files) instead of storing passwords in `settings.nix`.

User example:

```nix
userSettings.jonas.secrets = {
  defaultSopsFile = ./secrets/users/jonas.yaml;
  files = { };
  sshKeys.jonas-pixel-und-code = {
    key = "ssh/id_ed25519_jonas-pixel-und-code";
    targetName = "id_ed25519_jonas-pixel-und-code";
  };
};
```

User modules consume these via:

- `config.sops.secrets.<name>.path`

This is the intended path for SSH private keys, API tokens, and user-scoped application secrets.

For `sshKeys`, Home Manager deploys:

- `~/.ssh/<name>` as a symlink to the secret-backed private key
- `~/.ssh/<name>.pub` regenerated from that private key during activation

For passphrase-protected private keys, set one of these on the `sshKeys` entry:

- `publicKey = "ssh-ed25519 AAAA... comment"`
- `publicKeyFile = ./public/users/jonas/ssh/<name>.pub`
- `passphraseKey = "ssh_passphrases/<name>"` to materialize a second secret and allow automatic agent loading

If neither is set, Home Manager tries `ssh-keygen -y` as a fallback.
If that fails, it keeps the existing `.pub` file instead of truncating it.

If `passphraseKey` is set and the user uses `dev.ssh.agent.provider = "gnome-keyring"`,
the user session installs `ssh-load-secret-keys` and automatically loads those keys into
the SSH agent during the graphical session.

## SOPS Rename Rule

Do not rename encrypted key paths in a SOPS file with a normal text edit.

Reason:

- SOPS binds encrypted values to their exact tree path and MAC
- manually renaming a key like `ssh.id_ed22519_foo` -> `ssh.id_ed25519_foo`
  can make the affected value undecryptable
- the result is typically:
  - `Could not decrypt with AES_GCM: cipher: message authentication failed`

Use one of these methods instead:

- `sops edit <file>`
- `sops set`
- `sops unset`

Safe migration pattern:

1. decrypt or extract the old value with `sops`
2. write it to the new path with `sops set`
3. remove the old path with `sops unset`

Do not "refactor" encrypted YAML keys with plain text search/replace.

Store repo-tracked public keys outside `secrets/`, for example:

- `public/users/jonas/ssh/`

If you want an explicit filename scheme, set `targetName`. Example:

- `targetName = "id_ed25519_jonas-pixel-und-code"`

Without an `sshKeys` entry, no visible `~/.ssh/<name>` file is created. Use `secrets.files` for ordinary secret files that should stay only in the SOPS-managed path.

Under NixOS, the Home Manager layer can automatically reuse the system Age key:

- `sops.age.keyFile = /var/lib/sops-nix/key.txt`

For a professional multi-user setup, explicitly set a per-user key source via:

- `settings.userSettings.<name>.secrets.age.keyFile`

The full recommended host-key + per-user-key workflow is documented in:

- `secrets/SETUP.md`
