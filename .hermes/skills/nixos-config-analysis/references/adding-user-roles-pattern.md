# Adding a New User Role to j0nix-os

Minimal, deterministic recipe for adding a new user-facing role (home-only or system+home) to the modular NixOS setup.

## When to use

- User asks for a new category of software (e.g. photo-editing, audio-production, CAD).
- A role does not yet exist under `nix/roles/home/` or `nix/roles/system/`.

## Recipe

### 1. Inspect existing roles for pattern

```bash
ls nix/roles/home/
ls nix/roles/system/
```

Read one home role and one system role (e.g. `video-editing`) to understand the current contract:
- Home roles set `j0nix.user.software.packages` and optional `home.file.*`.
- System roles set `j0nix.desktop.sysctl.extraFragments`, `boot.kernelParams`, or other NixOS-level options.

### 2. Discover packages

```bash
nix search nixpkgs '<term>' --json
```

Verify exact attribute names (`pname`) before writing the `.nix` file.

### 3. Create role files

**Home-only role** (no system config needed):
```nix
# nix/roles/home/<role>.nix
{ pkgs, ... }:
{
  j0nix.user.software.packages = with pkgs; [
    pkg1
    pkg2
  ];
}
```

**System+home role** (needs sysctl, kernel params, or system services):
```nix
# nix/roles/system/<role>.nix
{ ... }:
{
  j0nix.desktop.sysctl.extraFragments = [
    {
      # tuning appropriate to workload
    }
  ];
}
```

Plus the home counterpart from above.

### 4. Register system role (if system file created)

In `nix/roles/system/default.nix`, add the role name to `rolesWithSystemModules`. Home-only roles do **not** need registration.

### 5. Validate

```bash
nix flake check --no-build
```

Address any assertion failures before committing.

### 6. Commit

One commit per completed scope:
```bash
git add nix/roles/home/<role>.nix nix/roles/system/<role>.nix nix/roles/system/default.nix
git commit -F /tmp/msg.txt
```

Use `git commit -F /tmp/msg.txt` if the message contains backticks, Nix interpolation, or shell-sensitive characters.

## Common Pitfalls

- **Forgetting `rolesWithSystemModules`**: If a system `.nix` exists but the name is missing from the list, the flake evaluates but the system module is silently skipped. Always pair a system role file with a list registration.
- **Package name mismatch**: `nix search` outputs `legacyPackages.x86_64-linux.foo`. The attribute to use in a `.nix` file is `pkgs.foo`, not `pkgs.legacyPackages.x86_64-linux.foo`.
- **Home vs system boundary**: Package installation belongs in the home role. Kernel params, sysctl, and system services belong in the system role. Do not mix them.

## Integration with settings.nix

Roles are assigned per-user in `settings.nix`:

```nix
userSettings.jonas = {
  roles = [ "gaming" "developer" "photo-editing" ];
};
```

After adding the role files and registering the system side, instruct the user to add the role name to their `roles` list and rebuild.
