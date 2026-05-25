# Secrets

Public quickstart for the `secrets/` tree used by `sops-nix`.

What stays in the public mirror:
- `.sops.yaml.example`
- `secrets/hosts/example-host.yaml.example`
- `secrets/users/example-user.yaml.example`

What does **not** stay in the public mirror:
- real encrypted host payloads
- real encrypted user payloads
- backup material and private helper scripts

## Layout

```text
secrets/
  hosts/
    example-host.yaml.example
    <hostname>.yaml
  users/
    example-user.yaml.example
    <username>.yaml
```

Use:
- `secrets/hosts/<hostname>.yaml` for machine-scoped secrets
- `secrets/users/<username>.yaml` for user-scoped secrets

## 1. Create age keys

Host key:

```bash
sudo install -d -m 700 /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo age-keygen -y /var/lib/sops-nix/key.txt
```

User key:

```bash
install -d -m 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

## 2. Create live files from templates

```bash
cp .sops.yaml.example .sops.yaml
cp secrets/hosts/example-host.yaml.example secrets/hosts/Jonas-PC.yaml
cp secrets/users/example-user.yaml.example secrets/users/jonas.yaml
```

Adjust the filenames to your real host and user names.

## 3. Edit `.sops.yaml`

Set the real `age1...` recipients for your host and user keys.

```yaml
creation_rules:
  - path_regex: secrets/hosts/.*\.ya?ml$
    age:
      - age1replace-with-your-host-recipient
  - path_regex: secrets/users/.*\.ya?ml$
    age:
      - age1replace-with-your-user-recipient
```

## 4. Edit and encrypt the secret payloads in place

```bash
sops secrets/hosts/Jonas-PC.yaml
sops secrets/users/jonas.yaml
```

Typical host payloads:
- Wi-Fi credentials
- VPN or Tailscale auth keys
- machine-local service tokens

Typical user payloads:
- SSH private keys
- GitHub or GitLab tokens
- app credentials

## 5. Verify decryption

```bash
sudo sops -d secrets/hosts/Jonas-PC.yaml >/dev/null
sops -d secrets/users/jonas.yaml >/dev/null
```

## 6. Rebuild

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

## Password hash example

Generate a password hash:

```bash
mkpasswd -m yescrypt
```

Then store it in the user secret file, for example:

```yaml
users:
  jonas:
    hashedPassword: "$y$..."
```

## Backup guidance

Back up these files out of band:
- `/var/lib/sops-nix/key.txt`
- `~/.config/sops/age/keys.txt`
- `.sops.yaml`
- your real `secrets/hosts/*.yaml`
- your real `secrets/users/*.yaml`

If you lose the keys, you will need to re-encrypt or recreate the secret payloads.
