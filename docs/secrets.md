# Secrets Quick Reference

Condensed guide. For the full walkthrough, see `secrets/SETUP.md`.

## Key Model

- **Host key** → `/var/lib/sops-nix/key.txt` (system secrets)
- **User key** → `~/.config/sops/age/keys.txt` (user secrets)

## 1. Create Keys

```bash
# Host key
sudo install -d -m 700 /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo age-keygen -y /var/lib/sops-nix/key.txt

# User key  
install -d -m 700 ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

## 2. Configure `.sops.yaml`

```bash
cp .sops.yaml.example .sops.yaml
```

```yaml
creation_rules:
  - path_regex: secrets/hosts/.*\.(yaml|yml|json)$
    key_groups:
      - age:
          - age1HOSTKEY...
  - path_regex: secrets/users/jonas\.(yaml|yml|json)$
    key_groups:
      - age:
          - age1JONASKEY...
          - age1HOSTKEY...
```

## 3. Create Secret Files

```bash
mkdir -p secrets/hosts secrets/users
sops secrets/users/jonas.yaml
sops secrets/hosts/Jonas-PC.yaml
```

## 4. Register in `settings.nix`

```nix
secrets = {
  defaultSopsFile = ./secrets/hosts/Jonas-PC.yaml;
  age = {
    generateKey = true;
    keyFile = "/var/lib/sops-nix/key.txt";
  };
};

userSettings.jonas.secrets = {
  age.keyFile = "/home/jonas/.config/sops/age/keys.txt";
  files = { };
  sshKeys = { };
};
```

## 5. Verify

```bash
sudo ls -l /run/secrets
ls -l ~/.ssh/
```
