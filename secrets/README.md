# Secrets

This repository is wired for `sops-nix` and expects encrypted secret files to live here.

Recommended layout:

- `secrets/common.yaml`
- `secrets/hosts/Jonas-PC.yaml`
- `secrets/users/jonas.yaml`
- `secrets/.sops.yaml`

Bootstrap:

1. Copy `secrets/.sops.yaml.example` to `secrets/.sops.yaml`
2. Replace the placeholder `age1...` recipients with your real Age public keys
3. Create an encrypted file, for example:
   - `sops secrets/hosts/Jonas-PC.yaml`
4. Reference entries from `settings.secrets.system`

For user secrets:

1. Create an encrypted file, for example:
   - `sops secrets/users/jonas.yaml`
2. Reference entries from `settings.secrets.users.jonas.items`

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
  users.jonas.items = {
    ssh-github-key = {
      key = "ssh/github_key";
    };
  };
};
```

User modules consume these via:

- `config.sops.secrets.<name>.path`

This is the intended path for SSH private keys, API tokens, and user-scoped application secrets.
