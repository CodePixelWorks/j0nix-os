# Settings Passthrough Priority Collisions

Pattern: a stack module owns typed options AND exposes a freeform `settings` attrset merged into an upstream service's settings. If the framework writes its derived values at plain priority (100), any operator key set through the passthrough collides at equal priority.

## Symptom

```
error: The option `services.headscale.settings.dns.magic_dns' has conflicting definition values:
       - In .../modules/stacks/network/headscale.nix': false
       - In .../modules/stacks/network/headscale.nix': true
```

One collision kills `nix flake check --no-build` for EVERYTHING — all checks, hosts, and labs become unevaluable. This is audit blocker #1: resolve eval errors before any other review work.

## Root cause

```nix
settings = mkMerge [
  { dns.magic_dns = cfg.dns.magicDns;   # priority 100
    ...
  }
  cfg.settings                          # also priority 100 -> boom
];
```

Introduced when structured typed options were added alongside an existing raw-settings habit; consumers kept using the raw keys.

## Fix (framework side)

Wrap every derived leaf in `mkDefault` so explicit operator values WIN instead of colliding:

```nix
dns = {
  magic_dns = mkDefault cfg.dns.magicDns;
  nameservers.global = mkDefault cfg.dns.nameservers.global;
};
```

Add `mkDefault` to the file's `inherit (lib)` list (missing imports are a classic follow-up error). Comment WHY at the block: tailnet-side DNS (what Headscale pushes to mesh clients) is independent of the host system resolver (`services.resolved`) — never blur that boundary when renaming/migrating.

## Fix (consumers)

Migrate hosts/labs/tests off the raw keys onto the typed options, keeping their intent comments. Grep consumers with:
`grep -rn "<stack>.settings." hosts/ labs/ tests/ customers/`

## Cross-stack global options (ownership)

When two stacks write the same global option (real case: `serverStacks.acme` and `serverStacks.nginx` both writing `security.acme.acceptTerms`/`defaults.email`):

- Owning stack: `lib.mkDefault` (was `mkForce` — force silently overrules host settings).
- Secondary stack: write only when its own option is explicitly configured:
  `security.acme.defaults.email = lib.mkIf (cfg.acme.defaultEmail != null) cfg.acme.defaultEmail;`
- Hosts then win over both stacks without any force. Check eval tests that combine both stacks before assuming priorities.

## Sweep candidates (same shape)

Grep `// cfg.settings` and `cfg.settings$` inside `mkMerge` blocks: grafana, hedgedoc, nextcloud, mysql, postgresql, surrealdb (vector uses recursiveUpdate — already correct; postgresql guards `listen_addresses` with `mkForce` + comment — acceptable for a true control-surface key).

## Pitfalls hit while patching (Nix `''` strings)

- Comments INSIDE a `''…''` string still terminate on `''`: a shell comment like `('' inside '...')` breaks eval with "invalid token". Rephrase the comment.
- To emit two literal quote characters through the string you must write `'''` (collapses to `''` in the emitted shell) — e.g. sed replacements that double quotes.
- After editing, verify with a real eval (`nix eval .#nixosConfigurations.<host>.config.<option>`); editor LSP diagnostics on .nix can lag or mislead.
