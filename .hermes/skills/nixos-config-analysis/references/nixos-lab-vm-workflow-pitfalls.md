# NixOS Lab VM Workflow Pitfalls

Session-derived reference for working with NixOS lab VMs (QEMU/KVM) inside flake-based repositories, especially when adding new lab scenarios or variants.

---

## 1. Untracked Files Are Invisible to Flakes

Nix flakes evaluate the git tree, not the working tree. Newly created `.nix` files must be `git add`-ed **before** any flake command can see them.

**Symptom:**
```
error: Path 'labs/scenarios/foo-apache.nix' in the repository "/path/to/repo" is not tracked by Git.

To make it visible to Nix, run:
  git -C "/path/to/repo" add "labs/scenarios/foo-apache.nix"
```

**Fix:**
```bash
git add labs/scenarios/*-apache.nix
# Then re-run the eval or build
```

**Rule of thumb:** After creating any new `.nix` file that will be referenced by a flake output, `git add` it immediately. `nix flake check` and `nix build` will silently fail otherwise.

---

## 2. QEMU Port Forwards Need `lib.mkForce`

When overriding `virtualisation.forwardPorts` in a lab scenario definition, the base module may already define ports. Without `mkForce`, Nix merges the lists, which often produces duplicate or conflicting forwards.

**Correct pattern in `labs/default.nix`:**
```nix
qemuModule = {
  virtualisation.forwardPorts = lib.mkForce [
    { from = "host"; host.address = "127.0.0.1"; host.port = 10022; guest.port = 22; }
    { from = "host"; host.address = "127.0.0.1"; host.port = 10080; guest.port = 80; }
  ];
};
```

**Without `mkForce`:** Ports from the base scenario and the override accumulate, causing QEMU to fail with "address already in use" or silently ignore duplicates.

---

## 3. `networking.hostName` in Variants Needs `lib.mkForce`

The base lab module usually sets `networking.hostName = "lab-something"`. When a variant (e.g. `*-apache`) overrides it, use `lib.mkForce` to avoid the "has conflicting definition values" error.

```nix
{ config, lib, ... }: {
  networking.hostName = lib.mkForce "lab-checkmk-apache";
}
```

---

## 4. Eval Checks != VM Builds

Three distinct verification layers exist for lab scenarios. Do not confuse them.

| Layer | Command | What it proves | What it does NOT prove |
|---|---|---|---|
| **Static eval** | `nix flake check --no-build` | All flake outputs evaluate without Nix syntax/type errors | Nothing about runtime behavior |
| **Focused eval** | `nix build .#checks.x86_64-linux.eval-foo` | A specific check closure evaluates successfully | Not that the VM boots or services start |
| **VM build** | `nix run .#lab-foo-kvm` or `nix build .#nixosConfigurations.lab-foo.config.system.build.vm` | The VM closure builds, kernel + initrd + rootfs are assembled | Not that the VM boots successfully or that services answer requests |
| **Runtime test** | Boot the VM, run `systemctl status`, hit forwarded ports | Actual operational correctness | Nothing about evaluation correctness |

**Session trap:** We verified static eval and focused eval for all Apache variants, but did not build or boot any VM. The user asked "hast du auch schon die labs gebaut und getestet" — the honest answer was no, only eval.

**Recommendation:** After creating new lab variants, always run at least one VM build (`nix build .#nixosConfigurations.lab-foo.config.system.build.vm`) to confirm the closure assembles. Runtime boot tests are only needed when service integration changed.

---

## 5. `lib` Must Be in Every Scenario's Function Arguments

Lab scenario files that use `lib.mkForce`, `lib.mkIf`, or any other `lib.*` helper must declare `lib` in their top-level function arguments. The NixOS module system passes `lib` automatically, but the file must accept it.

**Wrong:**
```nix
{ labCredentials, ... }:
{
  networking.hostName = lib.mkForce "lab-foo-apache";  # ERROR: undefined variable 'lib'
}
```

**Correct:**
```nix
{ lib, labCredentials, ... }:
{
  networking.hostName = lib.mkForce "lab-foo-apache";
}
```

**Same applies to `config` and `pkgs`:**
- If you read `config.services.foo`, include `config`
- If you reference `pkgs.somePackage`, include `pkgs`

**Batch check pattern:**
```bash
# Find scenarios using lib. but missing lib in args
for f in labs/scenarios/*.nix labs/scenarios/*/*.nix; do
  if grep -q "lib\." "$f" && ! grep -q "^.*lib.*:" "$f"; then
    echo "MISSING lib: $f"
  fi
done
```

---

## 6. Service-Specific Required Options in Variants

When creating an Apache variant of an existing lab scenario, the service module may require options that were automatically satisfied by the Nginx base module but must be set explicitly when switching web servers.

**Example — OpenReception:**
The Nginx base lab (`labs/scenarios/openreception.nix`) sets:
```nix
serverStacks.apps.openreception = {
  domain = "reception.lab.test";
  rootUrl = "http://reception.lab.test/";
  httpPort = 8090;
  jwtSecretFile = labCredentials.openreception.jwtSecretFile;
};
```

An Apache variant that only sets `nginx.enable = lib.mkForce false` and `apache.enable = true` will fail with:
```
Failed assertions:
- serverStacks.apps.openreception.jwtSecretFile must be set
- serverStacks.apps.openreception.rootUrl should match the generated frontend domain
```

**Fix:** Copy all required options from the base scenario into the variant, then add the Apache override:
```nix
serverStacks.apps.openreception = {
  domain = "reception.lab.test";
  rootUrl = "http://reception.lab.test/";
  httpPort = 8090;
  nginx.enable = lib.mkForce false;
  apache = { enable = true; httpPort = 80; };
  jwtSecretFile = labCredentials.openreception.jwtSecretFile;
};
```

**Rule:** Read the service module's `assertions` section to find required options, then ensure every variant satisfies them.

---

## 7. QEMU Port Forward Collisions Between Concurrent VMs

Running multiple `nix run .#lab-*-kvm` processes simultaneously causes QEMU port forwarding collisions if scenarios share the same forwarded ports (e.g., 10080, 10443, 10022).

**Symptom:**
```
qemu-system-x86_64: ...hostfwd=tcp:127.0.0.1:10080-:80,...: Could not set up host forwarding rule
```

**Fix:** Stop or kill all running QEMU VMs before starting a new one:
```bash
# Kill all QEMU VMs for this repo
pkill -f "qemu-system-x86_64.*lab-"

# Or use make targets:
make stop-all
```

**Better:** Assign unique ports for each variant in `labs/default.nix` so parallel builds are possible. But even with unique ports, watch for SSH (10022) collisions across labs.

---

## 8. Makefile `list-variants` Must Be Kept in Sync

When adding new scenario variants (e.g. `apache` for `etherpad`), update `Makefile` line 83-91 (`list-variants` target). Otherwise `make list-variants SCENARIO=etherpad` will omit the new variant and operators won't know it exists.

**Pattern:**
```make
list-variants: validate-scenario
	@case "$(SCENARIO)" in \
		etherpad) printf '%s\n' default authentik apache ;; \
		pterodactyl) printf '%s\n' panel node combined panel-apache combined-apache ;; \
		*) printf '%s\n' default ;; \
	esac
```

---

## 6. Import Path Depth from File Location, Not Scenario Root

When a lab variant lives in a subdirectory (e.g. `labs/scenarios/pterodactyl/panel-apache.nix`), the relative import path to `profiles/` must be computed from the subfile's actual location, not from `labs/scenarios/`.

**Original (root-level):**
```nix
# labs/scenarios/pterodactyl/panel.nix
imports = [ ../../../profiles/pterodactyl-panel.nix ];
```

**Wrong copy (only 2 levels up):**
```nix
# labs/scenarios/pterodactyl/panel-apache.nix
imports = [ ../../profiles/pterodactyl-panel.nix ];
# ERROR: Path 'labs/profiles/pterodactyl-panel.nix' does not exist
```

**Correct:**
```nix
imports = [ ../../../profiles/pterodactyl-panel.nix ];
```

**Rule:** Count `../` from the actual file location. A file at `labs/scenarios/<subdir>/foo.nix` needs `../../../profiles/` to reach `profiles/`.

**Batch check for all Apache variants in subdirs:**
```bash
# Verify no ../../profiles/ imports exist in subdir scenarios
for f in labs/scenarios/*/*-apache.nix; do
  [ -f "$f" ] || continue
  if grep -q '\.\./\.\./profiles/' "$f"; then
    echo "WRONG import depth: $f"
  fi
done
```

---

## 7. `lib` and `config` Must Be Explicitly Declared in Module Arguments

NixOS modules only receive arguments they declare. Using `lib.mkForce` or `config.some.option` without declaring `lib` or `config` in the function head produces:

```
error: undefined variable 'lib'
  at labs/scenarios/foo-apache.nix:8:25:
    networking.hostName = lib.mkForce "lab-foo-apache";
                          ^
```

**Safe pattern for all lab scenario files:**
```nix
{ lib, config, labCredentials, ... }:
{
  networking.hostName = lib.mkForce "lab-foo-apache";
  # ...
}
```

**Common oversight:** When copying a scenario that doesn't use `lib` (e.g. the original Nginx variant where `hostName` is set without `mkForce`), the new Apache variant that adds `mkForce` forgets to add `lib` to the argument list.

**Automated pre-commit check:**
```bash
# Find files using lib./config./pkgs. without declaring them in args
perl -ne '
  BEGIN { @files = glob("labs/scenarios/*.nix labs/scenarios/*/*.nix"); }
  END {
    for my $f (@files) {
      open(my $fh, "<", $f) or next;
      my $first = <$fh>;
      close($fh);
      for my $var (qw(lib config pkgs)) {
        my $uses = `grep -c "$var\." "$f" 2>/dev/null` || 0;
        chomp $uses;
        if ($uses > 0 && $first !~ /\b$var\b/) {
          print "MISSING $var: $f\n";
        }
      }
    }
  }
'
```

---

## 8. VM Runtime Port Conflicts When Testing Multiple Labs

Running multiple QEMU labs simultaneously on the same host causes TCP port conflicts on forwarded ports. QEMU fails with:

```
Could not set up host forwarding rule 'tcp:127.0.0.1:10080-:80'
```

**Symptom:** The first lab claims `127.0.0.1:10080`; any second lab using the same host port fails to start.

**Fix strategies:**
1. **Stop previous VMs** before starting the next (`pkill -f qemu-system-x86_64` or `make stop SCENARIO=...`)
2. **Assign non-overlapping ports** per variant in `labs/default.nix`
3. **Run VMs sequentially**, not in parallel, during testing

**Port assignment convention observed in this repo:**
- Default nginx labs: `10022→22`, `10080→80`, `10443→443`
- Apache variants: check before assigning; some reuse defaults, others get shifted ports (e.g. `12080→8080` for pterodactyl combined-apache)

When creating a new variant that might run concurrently with its default sibling, consider shifting all forwarded ports by +1000 or +2000 to avoid collision.

---

## 9. `_module.args` / `base.nix` Pattern — Extra Module Arguments

Some lab scenario families (e.g. Pterodactyl) use a `base.nix` that injects extra module arguments via `_module.args`. When an Apache variant forgets to import `base.nix`, these arguments are unavailable and evaluation fails:

```
error: attribute 'dbPasswordFile' missing
at labs/scenarios/pterodactyl/combined-apache.nix:
  database.passwordFile = dbPasswordFile;
                          ^
```

**Root cause:** The original scenario imports `./base.nix`:
```nix
# labs/scenarios/pterodactyl/base.nix
{ labCredentials, ... }: {
  _module.args = {
    inherit (labCredentials.pterodactyl)
      adminPasswordFile
      dbPasswordFile
      wingsTokenFile
      wingsTokenIdFile
      ;
  };
}
```

**Fix:** Always copy all `imports` from the original scenario, including `./base.nix`:
```nix
{ lib, config, adminPasswordFile, dbPasswordFile, wingsTokenFile, wingsTokenIdFile, labCredentials, ... }:
{
  imports = [
    ./base.nix              # <-- DO NOT FORGET
    ../../../profiles/pterodactyl-combined.nix
  ];
  # ...
}
```

**Lesson:** When creating a variant from a scenario that imports a local `base.nix`, `common.nix`, or `lib.nix`, preserve those imports. They are not boilerplate — they inject required arguments or shared configuration.

---

## 10. Hidden Assertion Dependencies — Side Effects Can Mask Requirements

When copying a scenario with working assertions, the new variant may expose previously hidden requirements. The original scenario may satisfy an assertion through a side effect (e.g. `integration.enable = true` auto-provisioning auth tokens) that disappears when unrelated parts change.

**Example — Pterodactyl combined-apache:**
The original `combined.nix` sets `integration.enable = true`. The Apache variant initially omitted `enable = true` and set `output.panelConfigFile` instead. The wings module then asserted:

```
Failed assertions:
- serverStacks.apps.pterodactyl.wings.auth.tokenIdFile must be set
- serverStacks.apps.pterodactyl.wings.auth.tokenFile must be set
```

The fix was explicit auth wiring:
```nix
wings = {
  auth = {
    tokenIdFile = wingsTokenIdFile;
    tokenFile = wingsTokenFile;
  };
  # ... rest of wings config
};
```

**Discovery pattern:** When a variant fails assertions the original didn't, read the service module's `assertions` list and trace each condition back to the option that satisfies it. The satisfying option may have been set implicitly (via a default, a side-effecting submodule, or a shared import).

---

## 11. Web-Server Design Limitations — Apache vs Nginx

Some app stacks enforce web-server coupling in their module design. An Apache variant may be impossible even when the app itself is web-server agnostic, because the NixOS module hardcodes nginx-specific integration points.

**Example — Hedgedoc authentik variants:**
Hedgedoc with SSO (`sso.enable = true`, `mode = "native"`, `provider = "authentik"`) requires nginx as the HTTP enforcement point for the SSO adapter. The module asserts:
```
- serverStacks.apps.hedgedoc.sso.enable requires nginx integration
- serverStacks.apps.hedgedoc.sso.mode = "native" with provider = "authentik"
  requires serverStacks.apps.authentik.enable = true
```

Creating `hedgedoc-apache-authentik` is therefore architecturally blocked. Do not register impossible variants in `labs/default.nix`.

**Check before creating variants:** Read the service module's `assertions` section for web-server-specific checks before assuming an Apache variant is viable.

---

## Quick Verification Checklist for New Lab Variants

- [ ] File created at `labs/scenarios/<name>[-<subname>].nix`
- [ ] `networking.hostName = lib.mkForce "lab-<name>[-<subname>]";`
- [ ] `lib` and `config` declared in function args if used in the file
- [ ] Import paths computed from the file's actual directory depth
- [ ] `git add` the new file
- [ ] Registered in `labs/default.nix` under the correct scenario's `variants`
- [ ] `qemuModule` with `lib.mkForce` on `virtualisation.forwardPorts` (if ports differ from default)
- [ ] `Makefile` `list-variants` updated (if the scenario has variants)
- [ ] `nix flake check --no-build` passes
- [ ] `nix build .#checks.x86_64-linux.eval-<relevant-check>` passes
- [ ] `nix build .#nixosConfigurations.lab-<name>.config.system.build.vm` assembles (smoke test)
- [ ] At least one VM boot test succeeds when run in isolation (no other VM using same ports)

1. Copy the original `.nix` to `*-apache.nix`
2. Change `networking.hostName` with `lib.mkForce`
3. Import the Apache web stack module instead of the Nginx one (or add the Apache override)
4. Remove any Nginx-specific forwarded ports from the scenario file (they belong in `labs/default.nix`'s `qemuModule`)

**Anti-pattern:** Duplicating the entire scenario including port forwards, secrets setup, and checkmk wiring. The variant should only express the delta from the default scenario.

---

## Quick Verification Checklist for New Lab Variants

- [ ] File created at `labs/scenarios/<name>[-<subname>].nix`
- [ ] `networking.hostName = lib.mkForce "lab-<name>[-<subname>]";`
- [ ] `git add` the new file
- [ ] Registered in `labs/default.nix` under the correct scenario's `variants`
- [ ] `qemuModule` with `lib.mkForce` on `virtualisation.forwardPorts` (if ports differ from default)
- [ ] `Makefile` `list-variants` updated (if the scenario has variants)
- [ ] `nix flake check --no-build` passes
- [ ] `nix build .#checks.x86_64-linux.eval-<relevant-check>` passes
- [ ] `nix build .#nixosConfigurations.lab-<name>.config.system.build.vm` assembles (smoke test)
