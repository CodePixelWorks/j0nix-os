# Nginx Vhost Include Chain (proxy stack)

How the shared Nginx proxy loads virtual hosts, and the audit bug where app vhosts silently never loaded.

## Architecture

- `modules/stacks/proxy/nginx.nix` renders EVERY `services.nginx.virtualHosts` entry into a per-vhost file `/etc/nginx/vhosts/<safe-name>.vhost.conf` via `lib/renderers/nginx.nix`.
- It passes `virtualHosts = {}` to `renderNginxConf` and REPLACES `services.nginx.config` — so nixpkgs' nginx module knows nothing about these files and will NOT include them automatically.
- The ONLY load path is an explicit glob inside the rendered http block: `include /etc/nginx/vhosts/*.vhost.conf;`
- The web stack (`modules/stacks/web/sites.nix`) also writes vhost files + per-site custom start/end include files into the same directory and relies on the same glob.

## The bug (found 2026-08, fixed)

Historically the glob existed ONLY in sites.nix (`commonHttpConfig`). Result, proven by building `example-gitea` toplevel and grepping its nginx.conf:

- Zero server blocks in the generated nginx.conf.
- Gitea's vhost sat as a dead file in /etc/nginx/vhosts/.
- Every app stack publishing through nginx WITHOUT the web stack enabled served nothing. Eval tests did not catch it because they assert `services.nginx.virtualHosts.*` options, not the rendered config chain.

A stale comment in renderers/nginx.nix even forbade adding the include ("NixOS includes them automatically" — false). Do not trust comments over a built artifact.

## Fix shape (minimal, single source of truth)

1. Put the glob ONCE inside the rendered http block in renderers/nginx.nix, with a comment marking it the exclusive include point.
2. REMOVE any second include elsewhere (sites.nix commonHttpConfig) — duplicates cause "conflicting server name" warnings because each vhost loads twice.
3. Update the wrong comment instead of leaving it as a trap.

## Verification recipe (no booting needed)

```
nix build .#nixosConfigurations.example-gitea-x86_64.config.system.build.toplevel --no-link -o /tmp/gitea-top
grep -c server_name /tmp/gitea-top/etc/nginx/nginx.conf        # >0 after fix
grep -n "include /etc/nginx/vhosts" /tmp/gitea-top/etc/nginx/nginx.conf   # exactly 1 occurrence
ls /tmp/gitea-top/etc/nginx/vhosts/
```

Also build a web-stack host (example-web) and check the glob appears exactly once and site vhost files still carry their custom.start/custom.end includes — this proves app rendering survived the cleanup.

## Known trap (documented, intentionally NOT changed)

`/etc/nginx/nginx.custom.conf` is included via `services.nginx.appendConfig`, which lands in the TOP-LEVEL context outside the `http {}` block. A plain directive there breaks nginx startup. http-level admin overrides belong in conf.d or a vhost file. Documented in docs/module-status/stacks/proxy.md rather than moved (moving = behavior change).

## Audit heuristic

When a module replaces an upstream service's main config option with a custom renderer, trace where each rendered file gets included from by BUILDING a host and grepping the output — option-level eval checks cannot see missing includes.
