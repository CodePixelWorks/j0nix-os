# SOPS-NIX Backup & Recovery Guide

The private repo may keep encrypted secret files as the source-of-truth setup.
The public GitHub mirror generated from it excludes those payloads and ships
only templates and documentation needed to recreate the secrets locally.

## Critical Files to Backup

### 1. Host Age Key
**Path:** `/var/lib/sops-nix/key.txt`

Systemd service decrypts host secrets. Lose this = reinstall or manual secret recovery.

```bash
# Backup
sudo cat /var/lib/sops-nix/key.txt > host-key-backup.txt

# Restore on new machine
sudo install -d -m 700 /var/lib/sops-nix
sudo install -m 600 host-key-backup.txt /var/lib/sops-nix/key.txt
```

### 2. User Age Key
**Path:** `~/.config/sops/age/keys.txt`

Your personal key for user secrets. Lose this = re-encrypt all user secrets with new key.

```bash
# Backup
cp ~/.config/sops/age/keys.txt user-key-backup.txt

# Restore on new machine
install -d -m 700 ~/.config/sops/age
install -m 600 user-key-backup.txt ~/.config/sops/age/keys.txt
```

### 3. Repository Files
- `.sops.yaml` - key recipients and rules
- `secrets/` - encrypted secret files
- `settings.nix` - secret references

## New Machine Rollout

### Step 1: Install NixOS
Standard installation. Host key can be:
- **Option A:** Copy existing `/var/lib/sops-nix/key.txt` from backup
- **Option B:** Generate new key, re-encrypt all secrets

### Step 2: Copy User Key
```bash
install -d -m 700 ~/.config/sops/age
install -m 600 /path/to/backup/keys.txt ~/.config/sops/age/keys.txt
```

### Step 3: Clone Repository
```bash
git clone <repo> ~/j0nix-os
cd ~/j0nix-os
```

### Step 4: Verify Decryption Works
```bash
# Test host secrets
sudo sops -d secrets/hosts/Jonas-PC.yaml

# Test user secrets  
sops -d secrets/users/jonas.yaml
```

### Step 5: Rebuild System
```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

## User Passwords via SOPS

### Create Password Hash
```bash
# Generate hash (method: sha-512)
mkpasswd -m sha-512

# Or use yescrypt (modern, recommended)
mkpasswd -m yescrypt
```

### Structure in secrets/users.yaml
```yaml
users:
  jonas:
    hashedPassword: "<hash-from-mkpasswd>"
```

### Reference in settings.nix
```nix
users.users.jonas = {
  hashedPasswordFile = config.sops.secrets.jonas-password.path;
};
```

## Key Rotation

### Rotate User Key
1. Generate new key: `age-keygen -o ~/.config/sops/age/keys.txt.new`
2. Add both old+new to `.sops.yaml` recipients
3. Re-encrypt: `sops rotate -i secrets/users/*.yaml`
4. Remove old key from `.sops.yaml`
5. Replace key file: `mv keys.txt.new keys.txt`

### Rotate Host Key
1. Generate new key on host
2. Add both keys to `.sops.yaml`
3. Re-encrypt host secrets
4. Remove old key
5. Update `/var/lib/sops-nix/key.txt`

## Troubleshooting

### "0 successful groups required, got 0"
Key missing or wrong recipient. Run:
```bash
./secrets/scripts/sops-autofix-decrypt.sh
```

### "Could not decrypt with AES_GCM"
SOPS file corrupted or key renamed incorrectly. Restore from backup or re-create.

### Forgot User Key
1. If host key also recipient: decrypt with host key, re-encrypt with new user key
2. If not: secrets lost, recreate from source

## Security Notes

- **Never commit plaintext keys**
- **Backup keys offline** (password manager, encrypted USB)
- **Host key = root access to all system secrets**
- **User key = access to that user's secrets only**
- **Rotation:** do user keys yearly, host keys on compromise suspicion
