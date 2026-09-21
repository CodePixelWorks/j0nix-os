# Cross-Module Integration Coverage Audit

Systematic technique for finding gaps where modular NixOS stacks fail to register hooks in shared subsystems (checkmk agent, restic backup, nginx, SELinux registry, etc.).

## When to Use

- A user asks "does every app/stack already have X integration when X is enabled?"
- Adding a new shared subsystem (e.g. a backup provider, monitoring agent, reverse proxy) and wanting to verify full coverage
- Refactoring an existing subsystem and needing to know which stacks must be updated
- Periodic hygiene audit before a production deployment

## Prerequisites

Know the shared subsystem's registration mechanism:
- **CheckMK agent**: `serverStacks.checkmkAgent.localChecks = mkAfter [...]`
- **Restic backup**: `serverStacks.backup.restic.jobs.*.paths` + pre/post hooks
- **Nginx vhost**: `services.nginx.virtualHosts.<name>.enable` + location blocks
- **SELinux registry**: `serverBase.security.mandatoryAccess.registry.{services,ports}`
- **Systemd service ordering**: `systemd.services.*.before`/`after`/`wants`

## Step-by-Step Audit Procedure

### 0. Start from the known-covered set

Before searching for gaps, establish the baseline: which stacks are *already* registering hooks. Search subsystem-specific patterns in one shot:

```bash
# Find every .nix file under modules/stacks that registers checkmkAgent.localChecks
grep -rln 'checkmkAgent\.localChecks' modules/stacks/
# Or more targeted: count registrations per file
grep -rn 'checkmkAgent\.localChecks\s*=' modules/stacks/ | wc -l
```

A good baseline question: "If the user asks whether every app integrates with checkmkAgent when checkmk is enabled, how many files already have the hook?" This gives the denominator for a coverage percentage.

### 1. Identify all modules in the subsystem's scope

List every `.nix` file that represents a concrete, deployable stack (not re-exports or thin wrappers):

```bash
find modules/stacks -name '*.nix' -not -path '*/default.nix' \
  | sort
```

### 2. Search for existing hook registrations

```bash
grep -rn 'checkmkAgent\.localChecks' modules/stacks/
grep -rn 'serverBase\.security\.mandatoryAccess\.registry' modules/stacks/
grep -rn 'backupPaths' modules/stacks/apps/
```

### 3. Classify each module

| Classification | Meaning | Action |
|---|---|---|
| **Covered** | Has explicit hook registration | None; verify it is still correct |
| **Has-own-service, uncovered** | Runs a real service but no hook | **Add hook** |
| **Structural / aggregator** | Only imports submodules (`default.nix`, re-export wrappers) | None; hooks belong in leaf modules |
| **Infrastructure, no service** | Postgres, Redis, Nginx base module, etc. | Evaluate case-by-case; some need hooks (nginx vhost), some don't |

### 4. Verify guard patterns

Every hook MUST be gated by the module's `cfg.enable`. It should NOT be gated by a check for whether the subsystem itself is enabled (the subsystem module should be a no-op when disabled). Correct pattern:

```nix
config = mkIf cfg.enable {
  serverStacks.checkmkAgent.localChecks = mkAfter [
    {
      id = "myapp-myservice";
      script = ''
        if systemctl is-active --quiet myservice.service; then
          echo '0 "MyApp myservice" - myservice.service is active'
        else
          echo '2 "MyApp myservice" - myservice.service is not active'
        fi
      '';
    }
  ];
};
```

Incorrect: checking `config.serverStacks.checkmkAgent.enable` inside the app module. The subsystem handles its own enable gate; the app just registers the check.

### 5. Check for missing lib imports

When adding `mkAfter`, verify it is listed in the `inherit (lib)` block:

```bash
grep -n 'inherit (lib)' modules/stacks/apps/pterodactyl/integration.nix
# Must include mkAfter
```

Forgetting this causes `nix flake check --no-build` to fail with:
```
error: undefined variable 'mkAfter'
```

## Common Gaps Found in Practice

### CheckMK agent coverage gaps

Stacks with own services but NO checkmk localCheck (as of last audit):
- `modules/stacks/apps/authentik/` (directory module)
- `modules/stacks/apps/headplane.nix`
- `modules/stacks/apps/srs.nix`
- `modules/stacks/database/postgresql.nix` (runs a real service)
- `modules/stacks/database/mysql.nix`
- `modules/stacks/cache/redis.nix`
- `modules/stacks/mail/relay.nix`
- `modules/stacks/storage/garage.nix`
- `modules/stacks/logging/vector.nix`
- `modules/stacks/network/headscale.nix`
- `modules/stacks/network/wireguard.nix`
- `modules/stacks/network/tailscale.nix`
- `modules/stacks/network/cloudflared.nix`
- `modules/stacks/ha/haproxy.nix`

Path-drift warning (2026-08): `apps/authentik.nix` became `apps/authentik/` (default.nix).
Direct relative imports of the old file path in tests broke at build time
("Path ... does not exist in Git repository") — e.g. tests/gitea-vm.nix,
tests/nextcloud-vm.nix. After ANY file→directory refactor of a module, grep
for the old path across tests/, labs/, hosts/, customers/ and repoint imports
at the directory.

### Infrastructure modules with partial coverage

- `modules/stacks/proxy/nginx.nix` — HAS checkmk localCheck (shared Nginx health)
- `modules/stacks/container/docker.nix` — HAS checkmk localCheck (Docker daemon status)
- `modules/stacks/container/podman.nix` — NO checkmk localCheck (should match Docker)

## Verification

After adding hooks, run the narrowest evaluation check for the affected stack:

```bash
nix build --no-link '.#checks.x86_64-linux.eval-<stack-name>'
```

Always fix `mkAfter` (or any missing lib helper) before the evaluation check or the error will surface:
```
error: undefined variable 'mkAfter'
```

## Companion: Apache Lab Variant Pattern

When a stack supports both `nginx.enable` and `apache.enable`, every Nginx-only lab scenario should have a matching Apache lab for parity testing.

### Discovery

Find stacks with dual-proxy support by grepping for `apache = {` inside `modules/stacks/apps/`:

```bash
grep -rln 'apache\s*=\s*{' modules/stacks/apps/
```

Then check whether each has both Nginx and Apache lab scenarios registered in `labs/default.nix`.

### Creating an Apache Lab Variant

Structure: mirror the Nginx lab, but override `nginx.enable = lib.mkForce false` and set `apache = { enable = true; httpPort = 80; }`.

Key points:
- **Hostname uniqueness**: Use `lib.mkForce` on `networking.hostName` to prevent collisions with the Nginx variant.
- **Firewall ports**: The stack's `listenAddress:httpPort` AND Apache's `httpPort` must be open (or just open the guest ports the operator will hit).
- **QEMU port forwards**: In `labs/default.nix`, forward host:10080 → guest:80 (Apache's port) and any additional app-specific ports. Remove HTTPS/443 forwards if the Apache variant does not use them.
- **State version**: Keep `system.stateVersion` consistent with sibling scenarios.

Example Apache lab:

```nix
{ lib, labCredentials, ... }:
{
  imports = [
    ../../profiles/mystack.nix
  ];

  networking.hostName = lib.mkForce "lab-mystack-apache";
  networking.firewall.allowedTCPPorts = [
    80
    8085
  ];

  serverStacks.apps.mystack = {
    domain = "app.lab.test";
    rootUrl = "http://app.lab.test/";
    httpPort = 8085;
    nginx.enable = lib.mkForce false;
    apache = {
      enable = true;
      httpPort = 80;
    };
  };

  system.stateVersion = "25.05";
}
```

Register in `labs/default.nix`:

```nix
mystack = {
  defaultVariant = "default";
  variants = {
    default.module = ./scenarios/mystack.nix;
    apache.module = ./scenarios/mystack-apache.nix;
  };
};
```

If the scenario uses `qemuModule` with forwarded ports, duplicate the port list but remap guest ports to the Apache equivalents (guest:80 instead of guest:8085, guest:8081 for headplane, etc.).

### Pitfalls

- **Forgetting `lib.mkForce` on hostName**: If the base profile or imported module already sets a hostname, a plain assignment will silently fail or conflict with sibling scenarios.
- **Wrong guest port in QEMU forward**: The guest port must match where Apache actually listens (usually 80 or the stack's `apache.httpPort`), not the app's internal HTTP port.
- **Missing QEMU forward registration**: Without adding the `qemuModule` block in `labs/default.nix`, the host proxy cannot reach the Apache listener.

## Template: Adding a CheckMK localCheck to a New Stack

```nix
{ config, lib, ... }:

let
  inherit (lib) mkAfter mkEnableOption mkIf;
  cfg = config.serverStacks.apps.myapp;
  serviceName = "myapp-service";
in
{
  options.serverStacks.apps.myapp = {
    enable = mkEnableOption "the MyApp stack";
  };

  config = mkIf cfg.enable {
    serverStacks.checkmkAgent.localChecks = mkAfter [
      {
        id = "myapp-service";
        script = ''
          if systemctl is-active --quiet ${serviceName}.service; then
            echo '0 "MyApp service" - ${serviceName}.service is active'
          else
            echo '2 "MyApp service" - ${serviceName}.service is not active'
          fi
        '';
      }
    ];
  };
}
```
