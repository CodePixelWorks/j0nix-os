# Shared SSH Config via Identity Flake

## IST

1. **Identity-Flake** `j0nix-identity-secrets` (Lokal: `/home/jonas/DEV/j0nix-identity-secrets`, Remote: `git@git.j0lab.xyz:NixOS/j0nix-identity-secrets.git`):
   - `secrets/ssh.yaml`: verschlüsselte Private Keys, Top-Level-Struktur `ssh:` / `ssh_passphrases:`
   - `lib/default.nix`: nicht-geheime Metadaten:
     - `sshSopsFile` / `gpgSopsFile`
     - `ssh.pc/server/git.<name>` mit `key`, `passphraseKey`, `targetName`
     - `gpg.<identity>` mit `key`, `passphraseKey`, `fingerprint`, `keygrip`
     - `keySets.{workstation,server,git,all}` und `resolveKeySet`
   - Kein `knownHosts`, kein `forwardHost`, kein Auto-Mechanismus.
2. **my-nixservers** (Customer-Flake): `customer.nix:65-127` deployed für `jonas.tschoche` auf `app-srv-01` die `git`-Keys + GPG. **Server-Keys (`ssh.server.*`) und shared ssh config fehlen komplett.**
3. **nixos-server-base** `identity.nix` / `identity-config.nix`:
   - `identity.sshHosts` (host, user, port, aliases, identityKey, identitiesOnly, forwardAgent) rendert `~/.ssh/config` Host-Blöcke, `IdentityFile` zeigt auf einen deployed Key aus `identity.sshKeys`.
   - `user-identity-keys-<user>` service: symlinks private keys nach `~/.ssh/<targetName>`, leitet `.pub` ab.
   - `user-ssh-agent-<user>` + `user-identity-refresh-<user>` timer.
4. **Consumer-Anbindung fehlt**: `my-nixservers/flake.nix:9-12` bindet `j0nix-identity-secrets` als Input ein, aber die `extraModules`-Injection via `_module.args.identityFlake` (flake.nix:26-31) existiert nur auf Customer-Ebene – Server-Base-Module sehen `identityFlake` nicht.

## ANSATZ (user confirmed via clarify options)

**Identity-Flake = Policy (was + wie), Customer = Hostname-Auflösung (wo).**

### Scope A — Identity-Flake: `sshHostTemplates` + `knownHosts` (referenz-only)

**`lib/default.nix`** ergänzen (nur Referenzen, keine Hostnamen):

```nix
# Metadaten für SSH-Host-Referenzen. `scope` markiert wofür der
# template gedacht ist — so bleibt policy-trennung zwischen repo-zwecken
# erhalten (private/shared/work/...) und consumer können gezielt filtern.
sshHostTemplates = {
  appsrv = {
    scope = "shared";          # shared | private | work
    identityKeyRef = "jonas-server-webserver";
    user = "ops";
    forwardAgent = true;
    knownHostsRefs = [ "app-srv-01" ];
  };
  webserver = {
    scope = "shared";
    identityKeyRef = "jonas-server-webserver";
    user = "ops";
    forwardAgent = true;
    knownHostsRefs = [ "webserver" ];
  };
  # ausstehend bis scope klar:
  # homeassistant = { scope = "private"; ... };
  # gagaland      = { scope = "private"; ... };
};
```

Hinweise:
- `scope` ist ein freier string (keine enum), damit das repo policy
  definieren kann ohne dass das framework eine liste pflegen muss.
  Customer entscheidet beim auflisten welche scopes er zulässt.

- `identityKeyRef` verweist auf `ssh.server.<name>` (via `resolveKeySet`).
- Keine echten Hostnamen — die löst der Customer auf (`appSrv → app-srv-01.tailnet.ts.net`).
- Host-Templates sind pro "Ziel-Server-Kategorie" definiert (appsrv, webserver, ha, gagaland).

### Scope B — nixos-server-base: sshHosts-Renderer + `sharedSsh` Option

**`identity.nix`** erweitern:

```nix
# Verweis auf ein sshHostTemplate aus dem identity flake
sharedSshHosts = mkOption {
  type = types.attrsOf (types.submodule ({ ... }: {
    options = {
      host = mkOption { type = types.str; };
      user = mkoption { type = types.nullOr types.str; default = null; };
      # ... alle felder von identity.sshHosts
      templateRef = mkOption { type = types.str; };  # key in identityFlake.lib.sshHostTemplates
    };
  }));
};
```

**`identity-config.nix`** erweitern:
- Renderer mischt `template` (defaults) + host-spezifische overrides.
- Renderer rendert auch `KnownHostsFile`/`GlobalKnownHostsFile` wenn `knownHostsRefs` gesetzt sind.
- Wenn `sshAgent.enable` && `forwardAgent` in a host entry: normaler ssh forwardAgent, kein extra feature needed.

### Scope C — Customer: shared SSH config für jonas.tschoche (webserver + appsrv only)

**`my-nixservers/customer.nix`** für `jonas.tschoche` auf `app-srv-01`:

```nix
identity = {
  enable = true;
  # ... existing git-keys + gpg config ...

  # Shared server key (ein einziger für alle shared hosts).
  sshKeys = {
    jonas-service-personal-git = idLib.ssh.git.jonas-service-personal-git;
    jonas-service-github       = idLib.ssh.git.jonas-service-github;
    jonas-server-webserver     = idLib.ssh.server.jonas-server-webserver;
  };

  # Shared SSH host blocks.
  sshHosts = {
    appsrv = {
      host = "app-srv-01.tailnet.ts.net";   # inventory: actual hostname
      user = "ops";
      identityKey = "jonas-server-webserver";
      forwardAgent = true;
      identitiesOnly = true;
      knownHostsFile = "/home/jonas.tschoche/.ssh/known_hosts_app-srv-01";
    };
    webserver = {
      host = "webserver.tailnet.ts.net";
      user = "ops";
      identityKey = "jonas-server-webserver";
      forwardAgent = true;
      identitiesOnly = true;
      knownHostsFile = "/home/jonas.tschoche/.ssh/known_hosts_webserver";
    };
  };
};
```

Notes:
- Initial-Scope: nur `webserver` + `appsrv`. Weitere (homeassistant, gagaland) werden nachgezogen wenn scope (private vs shared) und Key-Material festgelegt sind.
- `knownHostsFile` zeigt auf eine per-user known_hosts-datei (StrictHostKeyChecking=yes Standard).

### Scope E — Wire `identityFlake` arg into server-base identity modules

Currently `customer.nix` reads `idLib` from `identityFlake` directly (line 8), and manually picks `idLib.ssh.git.*` keys and GPG identities. The flake-level injection `_module.args.identityFlake` (my-nixservers/flake.nix:26-31) exists, and `customer.nix` receives `identityFlake` as a module argument.

BUT: the server-base identity module (`modules/server-base/users/identity.nix`) doesn't know about `identityFlake`. If we want `sharedSsh` to resolve `templateRef → identityFlake.lib.sshHostTemplates.<ref>`, we need to pass `identityFlake` into server-base modules. Options:

1. **Option 1 (recommended)**: Keep server-base generic. Add `serverBase.users.<name>.identity.sshHosts.<host>.metadataRef` (ref into the identity flake's lib). The customer resolves the ref → concrete values at eval time and passes them via the existing `sshHosts` option. Server-base stays clean of any flake-specific knowledge.
2. Option 2: Pass `identityFlake` into server-base modules via `_module.args` — server-base reads templates directly. Tighter coupling, but the customer config gets shorter.

## IMPLEMENTIERUNG

### Phase 1 — Identity-Flake: sshHostTemplates + docs
1. `lib/default.nix`: add `sshHostTemplates` attrset with `identityKeyRef`, `user`, `forwardAgent`, `knownHostsRefs` per template. No hostnames.
2. `README.md`: document `sshHostTemplates` + a customer example (Scope C style).
3. Commit + push.
4. `my-nixservers`: `nix flake lock --update-input j0nix-identity-secrets` and bump `server-base` if needed.

### Phase 2 — nixos-server-base: identity option shape
1. Extend `identity.nix` options:
   - `sshHosts.<name>.knownHostsFile` (nullOr str, default null): GlobalKnownHostsFile? Or UserKnownHostsFile + StrictHostKeyChecking?
   - Handle `metadataRef` resolution: If `identityFlake` is available as module arg (already injected by customer flake), server-base could offer `sshHosts.<name>.identityKey` resolution from a flake-level arg — but that requires the customer to inject `identityFlake` into server-base's module args. The customer currently only injects it for its own modules (customer.nix uses it).
   - **Simplest path**: Customer passes `idLib.sshHostTemplates` derived values directly into the existing `sshHosts` option. No server-base change needed for the config rendering itself! Only additions:
     - `sshHosts.<name>.knownHostsFile` for pinning host keys
     - Possibly `proxyJump` support if needed
2. Extend `identity-config.nix` `renderHost`:
   - Render `knownHostsFile` as `UserKnownHostsFile`/`GlobalKnownHostsFile` when set.
3. Update `tests/user-identity-eval.nix` fixtures if needed.
4. `nix flake check --no-build` on my-nixservers after bump.

### Phase 3 — Customer: shared ssh config for jonas.tschoche + ops
1. Add server keys to `sshKeys` on `jonas.tschoche` on app-srv-01: `jonas-server-webserver` (+ maybe `homeassistant`, `gagaland` if needed).
2. Add `sshHosts` entries for `webserver`, `appsrv`, `homeassistant`, `gagaland` as needed — each with `host`, `user`, `identityKey` referencing the deployed server key, `forwardAgent`, and optionally `knownHostsFile`.
3. Do the same for `ops` user (identity block) if we decide ops needs shared ssh too.
4. Rebuild + verify on server: `ssh -G webserver` shows correct config, `ssh webserver true` works.
```

## VERIFIKATION
- `nix flake check --no-build` on identity flake? (it has no tests currently)
- `nix flake check --nix-build` on my-nixservers
- Deploy to app-srv-01 via existing flow (make deploy / nixos-rebuild switch)
- Runtime verify: `ssh -G appsrv` on server, check `hostname`, `user`, `identityfile`, `forwardagent`.
```

## OFFENE PUNKTE
1. `ops` identity block: braucht ops die shared ssh config auch? (jonas.tschoche ist der primary user der sich einloggt)
2. Which hosts should be in the shared config initially? User said "wie webserver, appsrv usw"
3. ProxyJump needed? (e.g. appsrv reachable only via jump host)
4. knownHostsFile: worth adding or keep known_hosts manual?

This plan is NOT yet implemented. Implementation starts after user reviews/adjusts this plan.
