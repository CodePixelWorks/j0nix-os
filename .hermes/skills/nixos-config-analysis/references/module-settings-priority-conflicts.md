# Module Settings Priority Conflicts — Case Study (nixos-server-base headscale DNS, 2026-08)

## Symptom
`nix flake check --no-build` fails for the WHOLE flake (every host, every check):

```
error: The option `services.headscale.settings.dns.magic_dns' has conflicting definition values:
       - In `.../modules/stacks/network/headscale.nix': false
       - In `.../modules/stacks/network/headscale.nix': true
Use `lib.mkForce value` or `lib.mkDefault value` to change the priority...
```

Note both conflicting sites resolve to the SAME file: the framework's own
derived mapping vs the freeform `cfg.settings` passthrough used by a host.

## Root cause
Commit 2db7a80 added typed DNS options (`serverStacks.headscale.dns.*`) and
mapped them into `services.headscale.settings` as PLAIN values:

```nix
settings = mkMerge [
  {
    dns = {
      magic_dns = cfg.dns.magicDns;        # priority 100
      base_domain = cfg.dns.baseDomain;
      ...
    };
  }
  cfg.settings                              # consumer overrides, priority 100
];
```

Pre-existing consumers kept overriding the raw upstream keys through the
freeform hatch at the same priority:
- hosts/example-headscale/default.nix
- labs/scenarios/tailscale.nix
- labs/scenarios/headscale/common.nix
- tests/headscale-stack-eval.nix (three evaluations)

Result: hard merge conflict introduced 2026-08-20, detected 2026-08-24 only
because a baseline `nix flake check` was run. Nothing else in the repo
surfaced it — all local edits had been evaluated in narrower scopes.

## Fix pattern
1. Framework side: lower the priority of derived settings so the operator
   hatch wins silently:
   ```nix
   dns = {
     magic_dns = lib.mkDefault cfg.dns.magicDns;
     base_domain = lib.mkDefault cfg.dns.baseDomain;
   };
   ```
   (`lib.mkOverride 900` equivalent.)
2. Migrate consumers onto the typed options
   (`serverStacks.headscale.dns.magicDns`) instead of raw upstream keys;
   keep raw keys only for upstream settings the typed surface does not map.
3. Verify resolution end-to-end:
   ```
   nix flake check --no-build
   nix eval .#nixosConfigurations.<host>.config.services.headscale.settings.dns.magic_dns
   ```

## Audit sweep for the same class
```
grep -rn "settings = mkMerge\|// cfg.settings\|cfg.settings$" modules/
```
Findings in nixos-server-base (2026-08): grafana.nix, hedgedoc.nix,
nextcloud.nix, mysql.nix, postgresql.nix, surrealdb.nix, headplane.nix,
headscale.nix all merge a freeform settings hatch after derived values at
equal priority. These are LATENT — they only explode when an operator
overrides exactly a key the framework derives. vector.nix avoids the class
via `recursiveUpdate derivedSettings cfg.settings`; postgresql.nix uses
deliberate `mkForce` + explanatory comment for `listen_addresses`.

Severity guidance: fix immediately any module with known consumers overriding
derived keys (whole-flake outage); flag the rest as medium-risk debt with a
pointer to this pattern.

## Related trap seen in the same audit
A second red check came from an ORPHANED TEST ASSERTION: the module fixed
token/userinfo OIDC endpoints from internalUrl to rootUrl (iss-claim
correctness) but the eval-check still asserted the old internalUrl literals.
Locate ownership fast with:
```
git log -S "http://127.0.0.1:9000/application/o/token/" --format="%h %ad %s" -- tests/ modules/
```
The commit pair tells you who introduced the expectation and who changed the
behavior; updating the assertion is part of the fix deliverable.
