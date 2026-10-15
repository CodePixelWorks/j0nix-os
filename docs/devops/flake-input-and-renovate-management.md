# How j0nix-os and nixos-server-base manage their flake inputs and dependency updates

Applies to both repos. Written 2026-10-15 after the Renovate
hard-crash + digest-pin rollout on j0nix-os.

## The two repos, two pinning philosophies

| | nixos-server-base | j0nix-os |
|---|---|---|
| Rev-pinned inputs | yes — `git+https://…?rev=` / `git+ssh://…?rev=` forms, Renovate nix-manager updates them via git-refs datasource (one digest PR per input) | only `ags` (historically) and, since the digest-pin rollout (issue #6, PR #16), 18 more update-eligible inputs |
| Branch-tracking inputs | nixpkgs `nixos-26.05`, headplane, sops-nix — updated by `lockFileMaintenance` grouped PR | nixpkgs `nixos-unstable`, home-manager `master`, open-design `main`, quickshell-stable tag, caelestia-shell-dev, hyprland tag, nix-cachyos-kernel `release` — deliberately left to `lockFileMaintenance` / manual |
| automerge | true (sensitive groups off) | true since 2026-10-15 (same pattern) |

**Rule: an input gets rev-pinned iff it should receive automated digest
PRs. Branch-tracking is a deliberate choice for inputs that should
follow upstream (fast-moving shell stack, kernel binary-cache branch) —
do not "fix" those to rev-pins; the digest PR would fight the intent.**

## The nix-cachyos-kernel special case (j0nix-os)

- Input must NOT follow the host nixpkgs (`inputs.nixpkgs.follows` is
  the bug). The `overlays.pinned` overlay builds kernels with the
  flake's OWN nixpkgs revision — cache hits require exactly that
  revision.
- Use the `release` branch (Hydra-built, guaranteed in
  `attic.xuyh0120.win/lantian`), never `master` (cache-misses →
  multi-hour local kernel builds).
- Substituter config lives in `nix/system/nix/default.nix`
  (substituters + trustedPublicKeys mkDefault lists): lantian-attic
  (`lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=`), hyprland
  cachix, fleet attic `cache.j0lab.xyz`
  (`default:5H4f5V5KItu2HsoWWFVZv7gl6gW8F7hmp2vbjSvzQKA=`).
- Verify a cache hit with
  `nix build …--dry-run --option substituters https://attic.xuyh0120.win/lantian …`
  → expect "0 derivations will be built". Without the explicit option
  the dry-run uses the LIVE system's substituters, which lags the
  repo config until the next switch.

## Private flake inputs and credentials

- Private Gitea inputs (`git+ssh://git@git.j0lab.xyz/...`) are fetched
  via the user's SSH agent outside the nix build sandbox. Anything a
  sandboxed derivation fetches (cargo-vendor, FOD) cannot authenticate
  — resolve private deps via flake inputs, never from inside a build.
- Locked flake URLs can carry `https://git.j0lab.xyz/...` even for
  inputs declared `git+ssh` (nix stores the fetched URL form). Plain
  https fetches need credentials from `~/.netrc` (user side, works
  for the libgit2 fetcher) or the CI service's git insteadOf rewrite.
- **Renovate on app-srv-01** (modules/stacks/operations/renovate.nix):
  the prep service writes
  `url."https://oauth2:<token>@git.j0lab.xyz/".insteadOf` for BOTH the
  `ssh://git@` and the `https://` transports. BOTH are required:
  - without the https rewrite, `nix flake lock` fails on any
    https-form lock URL of a private repo ("Repository not found")
    and the nix manager hard-crashes the whole renovate run
    (2026-10-15, Rust/discord-mcp).
  - the https line must be added with `git config --add` — both
    insteadOf values live in the SAME url section (identical section
    value), and a second plain `git config` invocation overwrites the
    first insteadOf key instead of appending. Verified post-deploy:
    the config must carry two insteadOf lines in one section.
- nix's git fetcher DOES honor `~/.netrc` for git+https (user side).
  The `git config insteadOf` mechanism does NOT rewrite plain https
  URLs for nix's libgit2 fetcher when set via ~/.gitconfig — netrc is
  the working user-side mechanism.

## Renovate nix-manager mechanics (the github:-form trap)

- The nix manager updates flake.lock inputs ONLY when the input URL is
  `git+https://github.com/owner/repo?rev=<digest>` (git-refs
  datasource → digest PRs).
- `github:owner/repo` short forms resolve through the github-tags
  datasource → "no results" for repos without versioned tags → the
  input is invisible to Renovate (issue #6: 22 of 31 inputs).
- Branch-pinned inputs (`?ref=main`, `?ref=refs/tags/…`) are
  intentionally invisible — Renovate cannot update ref names, and
  that is desired.
- The locked `type` in flake.lock switches github→git when an input is
  rewritten to the git+https form; regenerating the lock with revs =
  currently locked digests is a type-only change (host toplevel
  derivation unchanged).
- Phantom-suppression: Renovate's nix manager hallucinates a "pin nix"
  update on repos without a `nix` flake input — both repos carry a
  packageRule disabling `matchDepNames: [nix]` for the nix manager.

## Renovate scheduling and automerge (both repos)

- Three-window schedule (`before 6am`, lunch, evening) — a single
  6am slot collides with the morning commit rush.
- `automerge: true` + `automergeType: pr` + `platformAutomerge: true`
  globally; sensitive groups keep explicit `automerge: false`
  (j0nix-os: private inputs, active Hyprland/Caelestia stack,
  nixpkgs, home-manager, system integration).
- `rebaseWhen: never`, prHourlyLimit/prConcurrentLimit 10.
