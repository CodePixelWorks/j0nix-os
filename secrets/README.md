# Secrets

This repository is wired for `sops-nix` and expects encrypted secret files to live here.

For the full step-by-step setup guide, see:

- `secrets/SETUP.md`

Recommended layout:

- `secrets/common.yaml`
- `secrets/hosts/Jonas-PC.yaml`
- `secrets/users/jonas.yaml`
- `.sops.yaml`

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
2. Reference entries from `settings.userSettings.jonas.secrets.items`

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
secrets = {
  defaultUserSopsFile = ./secrets/users/jonas.yaml;
  users.jonas = {
    items = {
      jonas-pixel-und-code = {
        key = "ssh/jonas_pixel_und_code";
      };
    };
    sshKeys.jonas-pixel-und-code = {
      secretName = "jonas-pixel-und-code";
      targetName = "id_ed25519_jonas-pixel-und-code";
    };
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

If neither is set, Home Manager tries `ssh-keygen -y` as a fallback.
If that fails, it keeps the existing `.pub` file instead of truncating it.

Store repo-tracked public keys outside `secrets/`, for example:

- `public/users/jonas/ssh/`

If you want an explicit filename scheme, set `targetName`. Example:

- `targetName = "id_ed25519_jonas-pixel-und-code"`

Without an `sshKeys` entry, no visible `~/.ssh/<name>` file is created. The secret only exists in the SOPS-managed path.

Under NixOS, the Home Manager layer can automatically reuse the system Age key:

- `sops.age.keyFile = /var/lib/sops-nix/key.txt`

For a professional multi-user setup, explicitly set a per-user key source via:

- `settings.userSettings.<name>.secrets.age.keyFile`

The full recommended host-key + per-user-key workflow is documented in:

- `secrets/SETUP.md`
